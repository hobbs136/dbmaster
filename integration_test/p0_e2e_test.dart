// ============================================================================
// P0 End-to-End Real-Database Tests
//
// Verifies the adapter-layer behavior of the P0 client-side fixes against real
// database servers (via DBMASTER_* defines). Covers:
//
//   #6  Redis Functions  — load/list/withcode/source/fcall/delete round-trip
//   #7  MongoDB Sharding — getShardingStatus + getReplicaSetStatus on standalone
//                          (must return null gracefully, not throw)
//   #11 Redis String     — SET/GET via runCommand preserves spaces (regression
//                          guard for the v1 "SET k hello world" corruption bug)
//
// Tests target the .128 test server (see integration_test/config/*.dart). They
// need a real Redis 7.0+ (for FUNCTION commands) and a real MongoDB instance.
// Standalone MongoDB (not a sharded cluster / replica set) is the EXPECTED
// deployment on .128 — the #7 tests verify the adapter returns null cleanly
// rather than throwing on non-cluster deployments.
//
// Run:
//   flutter test integration_test/p0_e2e_test.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'config/redis_test_config.dart';
import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // T29 非 SQL 批次（B2）：Mongo 网关壳硬依赖 dbmaster server 会话（embedded
  // 前置，D6）。只影响下方 Mongo 组（Redis 组仍是直连适配器）。
  var mongoE2EGatewayReady = false;
  setUpAll(() async {
    mongoE2EGatewayReady = await ensureEmbeddedServerForMongoE2E();
    if (mongoE2EGatewayReady &&
        (!MongoDBTestConfig.available || !RedisTestConfig.available)) {
      // ignore: avoid_print
      print('MONGO_E2E_SKIP: DBMASTER_MONGO_* / DBMASTER_REDIS_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mongoE2EGatewayReady = false;
    }
  });

  // ──────────────────────────────────────────────────────────────────────
  // #6 + #11: Redis (real Redis 7.4 on .128:6379)
  // ──────────────────────────────────────────────────────────────────────
  group('P0 Redis e2e (#6 Functions + #11 String)', () {
    late RedisAdapter adapter;

    setUp(() async {
      adapter = RedisAdapter();
      final conn = DatabaseConnection(
        id: 'p0_e2e_redis',
        name: 'P0 E2E Redis',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      final ok = await adapter.connect(conn);
      expect(ok, isTrue, reason: 'Redis connect failed');
      // Wipe ALL libraries in this DB so tests start from a known empty state.
      // db15 is the dedicated test DB (RedisTestConfig._defaultDatabase = 15),
      // safe to wipe function libraries between tests. Without this, leftover
      // libs from prior runs make `getRedisFunctions` length assertions flaky.
      try {
        final existing = await adapter.getRedisFunctions();
        for (final lib in existing) {
          await adapter.deleteRedisFunction(lib.name);
        }
      } catch (_) {}
      try {
        await adapter.runCommand(['DEL', 'p0_e2e:string']);
      } catch (_) {}
    });

    tearDown(() async {
      try {
        await adapter.deleteRedisFunction('p0_e2e_lib');
      } catch (_) {}
      try {
        if (adapter.isConnected) await adapter.disconnect();
      } catch (_) {}
    });

    // ─── #6 Redis Functions ───

    test('#6 loadRedisFunction + getRedisFunctions round-trip', () async {
      // Load a function library — shebang + register_function
      const lua = """#!lua name=p0_e2e_lib
redis.register_function('p0_greet', function(keys, args)
    return 'hello ' .. args[1]
end)
redis.register_function('p0_add', function(keys, args)
    return tonumber(args[1]) + tonumber(args[2])
end)
""";
      final ok = await adapter.loadRedisFunction(lua, replace: true);
      expect(ok, isTrue, reason: 'FUNCTION LOAD should succeed');

      // List functions (metadata only, no source)
      final libs = await adapter.getRedisFunctions();
      expect(libs, hasLength(1));
      expect(libs.first.name, 'p0_e2e_lib');
      expect(libs.first.engine, 'LUA');
      expect(libs.first.functions, hasLength(2));
      expect(libs.first.functions.map((f) => f.name).toList()..sort(),
          ['p0_add', 'p0_greet']);
      expect(libs.first.sourceCode, isNull,
          reason: 'withoutCode default should not carry source');
    });

    test('#6 getRedisFunctions(withCode: true) returns Lua source', () async {
      // ensure lib is loaded
      const lua = """#!lua name=p0_e2e_lib
redis.register_function('p0_greet', function(keys, args)
    return 'hello ' .. args[1]
end)
""";
      await adapter.loadRedisFunction(lua, replace: true);

      final libs = await adapter.getRedisFunctions(withCode: true);
      expect(libs, hasLength(1));
      expect(libs.first.sourceCode, isNotNull);
      expect(libs.first.sourceCode, contains('#!lua name=p0_e2e_lib'));
      expect(libs.first.sourceCode, contains('redis.register_function'));
    });

    test('#6 getRedisFunctionSource(libraryName) returns single-lib source',
        () async {
      const lua = """#!lua name=p0_e2e_lib
redis.register_function('p0_greet', function(keys, args) return 'hi' end)
""";
      await adapter.loadRedisFunction(lua, replace: true);

      final source = await adapter.getRedisFunctionSource('p0_e2e_lib');
      expect(source, isNotNull);
      expect(source, contains('#!lua name=p0_e2e_lib'));

      // Non-existent library → null (FILTERBY returns empty)
      final ghost = await adapter.getRedisFunctionSource('does_not_exist');
      expect(ghost, isNull);
    });

    test('#6 callRedisFunction string return + numeric return', () async {
      const lua = """#!lua name=p0_e2e_lib
redis.register_function('p0_greet', function(keys, args)
    return 'hello ' .. args[1]
end)
redis.register_function('p0_add', function(keys, args)
    return tonumber(args[1]) + tonumber(args[2])
end)
""";
      await adapter.loadRedisFunction(lua, replace: true);

      // String-returning function
      final greetResult = await adapter.callRedisFunction(
        'p0_greet',
        keys: [],
        args: ['world'],
      );
      expect(greetResult, 'hello world');

      // Numeric-returning function (Redis coerces to int or string depending on driver)
      final addResult = await adapter.callRedisFunction(
        'p0_add',
        keys: [],
        args: ['3', '4'],
      );
      // redis.dart may return int or string — accept either, value must be 7
      expect(addResult.toString(), '7');
    });

    test('#6 callRedisFunction with keys (FCALL numkeys semantics)', () async {
      // Function that reads a key from the keyspace via keys[1]
      const lua = """#!lua name=p0_e2e_lib
redis.register_function('p0_getkey', function(keys, args)
    return redis.call('GET', keys[1]) or 'nil'
end)
""";
      await adapter.loadRedisFunction(lua, replace: true);
      // Set a value via runCommand, then read it via FCALL
      await adapter.runCommand(['SET', 'p0_e2e:fcall_target', 'magic_value']);
      final result = await adapter.callRedisFunction(
        'p0_getkey',
        keys: ['p0_e2e:fcall_target'],
        args: [],
      );
      expect(result, 'magic_value');
      await adapter.runCommand(['DEL', 'p0_e2e:fcall_target']);
    });

    test('#6 deleteRedisFunction removes the library', () async {
      const lua = """#!lua name=p0_e2e_lib
redis.register_function('p0_x', function(keys, args) return 1 end)
""";
      await adapter.loadRedisFunction(lua, replace: true);
      expect((await adapter.getRedisFunctions()), hasLength(1));

      final ok = await adapter.deleteRedisFunction('p0_e2e_lib');
      expect(ok, isTrue);
      expect((await adapter.getRedisFunctions()), isEmpty);
    });

    // ─── #11 Redis String Editor (regression guard) ───

    test('#11 SET via runCommand preserves spaces in value', () async {
      // This is the exact regression scenario #11 fixed: v1 used string
      // concatenation `SET k v1 v2` which truncated to `v1`. runCommand with
      // separate args preserves the full value.
      const valueWithSpaces = 'hello world with multiple words';
      final setResult = await adapter.runCommand([
        'SET',
        'p0_e2e:string',
        valueWithSpaces,
      ]);
      // SET reply is 'OK' on success
      expect(setResult.toString().toUpperCase(), contains('OK'));

      final getResult = await adapter.runCommand(['GET', 'p0_e2e:string']);
      expect(getResult, valueWithSpaces,
          reason: '#11 regression: GET must return the full value with spaces, '
              'not just the first word');
    });

    test('#11 SET with special chars (newline, quotes, backtick)', () async {
      const special = 'line1\nline2 "quoted" `backticked`';
      await adapter.runCommand(['SET', 'p0_e2e:string', special]);
      final got = await adapter.runCommand(['GET', 'p0_e2e:string']);
      expect(got, special,
          reason: 'special chars (newline/quotes/backtick) must round-trip intact');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // #7: MongoDB (real MongoDB on .128:27017, standalone deployment)
  // ──────────────────────────────────────────────────────────────────────
  group('P0 MongoDB e2e (#7 Sharding + Replication on standalone)', () {
    late MongoDBAdapter adapter;

    setUp(() async {
      if (!mongoE2EGatewayReady) return;
      adapter = MongoDBAdapter();
      final conn = DatabaseConnection(
        id: 'p0_e2e_mongo',
        name: 'P0 E2E Mongo',
        type: DatabaseType.mongodb,
        host: MongoDBTestConfig.host,
        port: MongoDBTestConfig.port,
        username: MongoDBTestConfig.username,
        password: MongoDBTestConfig.password,
        database: MongoDBTestConfig.authDatabase,
      );
      final ok = await adapter.connect(conn);
      expect(ok, isTrue, reason: 'MongoDB connect failed');
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) await adapter.disconnect();
      } catch (_) {}
    });

    test('#7 getShardingStatus on standalone returns null (not throw)', () async {
      if (!mongoE2EGatewayReady) return;
      // .128 MongoDB is a standalone instance, not a sharded cluster.
      // listShards command fails on standalone → adapter catches and returns
      // null. This is the correct non-cluster behavior — the previous bug was
      // the tree builder displaying "will be displayed here" placeholder
      // regardless; the adapter layer was already correct but unwired.
      final status = await adapter.getShardingStatus();
      expect(status, isNull,
          reason: 'standalone MongoDB should return null from getShardingStatus');
    });

    test('#7 getReplicaSetStatus on standalone returns null (not throw)', () async {
      if (!mongoE2EGatewayReady) return;
      // Same reasoning — standalone is not a replica set, replSetGetStatus
      // fails, adapter returns null gracefully.
      final status = await adapter.getReplicaSetStatus();
      expect(status, isNull,
          reason: 'standalone MongoDB should return null from getReplicaSetStatus');
    });
  });
}
