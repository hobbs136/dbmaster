// ============================================================================
// Redis Integration Tests
// Tests: Real Redis database operations using a Redis instance
// Prerequisites: Set environment variables or update redis_test_config.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'config/redis_test_config.dart';
import 'helpers/redis_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // T29 非 SQL 批次（B4）：Redis 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 REDIS_E2E_SKIP 跳过（无假绿）。
  var redisE2EGatewayReady = false;
  setUpAll(() async {
    redisE2EGatewayReady = await ensureEmbeddedServerForRedisE2E();
    if (redisE2EGatewayReady && !RedisTestConfig.available) {
      // ignore: avoid_print
      print('REDIS_E2E_SKIP: DBMASTER_REDIS_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      redisE2EGatewayReady = false;
    }
  });

  group('Redis Connection', () {
    late RedisAdapter adapter;

    setUp(() {
      adapter = RedisAdapter();
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          await adapter.disconnect();
        }
      } catch (_) {
        // Ignore disconnect errors
      }
    });

    testWidgets('should connect to Redis server successfully', (tester) async {
      if (!redisE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'test_redis_conn_1',
        name: 'Test Redis Connection 1',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );

      try {
        final result = await adapter.connect(connection);
        expect(result, isTrue, reason: 'Connection to ${RedisTestConfig.host}:${RedisTestConfig.port} failed');
        expect(adapter.isConnected, isTrue);
      } catch (e) {
        fail('Connection failed with error: $e');
      }
    });

    testWidgets('should handle connection authentication', (tester) async {
      if (!redisE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'test_redis_conn_2',
        name: 'Test Redis Connection 2',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );

      final result = await adapter.connect(connection);
      expect(result, isTrue);
      expect(adapter.isConnected, isTrue);
      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('should test connection successfully', (tester) async {
      if (!redisE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'test_redis_conn_3',
        name: 'Test Redis Connection 3',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );

      final error = await adapter.testConnection(connection);

      expect(error, isNull);
    });
  });

  group('Redis Database Operations', () {
    late RedisAdapter adapter;

    setUp(() async {
      adapter = RedisAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_redis_db_conn',
        name: 'Test Redis DB Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    testWidgets('should list all databases', (tester) async {
      if (!redisE2EGatewayReady) return;
      final databases = await adapter.getDatabases();

      expect(databases, isNotEmpty);
      expect(databases, contains('db0'));
      expect(databases, contains('db15'));
      expect(databases.length, equals(16));
    });

    testWidgets('should switch to a database', (tester) async {
      if (!redisE2EGatewayReady) return;
      await adapter.useDatabase('db5');
      expect(adapter.currentConnection?.database, equals('db5'));

      // Switch back
      await adapter.useDatabase('db0');
      expect(adapter.currentConnection?.database, equals('db0'));
    });

    testWidgets('should get database properties', (tester) async {
      if (!redisE2EGatewayReady) return;
      final props = await adapter.getDatabaseProperties('db0');

      expect(props, isNotNull);
      expect(props!['name'], equals('db0'));
    });

    testWidgets('should drop a database (flushdb)', (tester) async {
      if (!redisE2EGatewayReady) return;
      // Switch to db15 to avoid interfering with other data
      await adapter.useDatabase('db15');
      
      // First set some test data in db15
      await adapter.setString('test:drop_key', 'test_value');
      
      // Verify key exists
      var keys = await adapter.scanKeys(pattern: '*');
      expect(keys, contains('test:drop_key'));
      
      // Drop (flush) the database
      final result = await adapter.dropDatabase('db15');
      expect(result, isTrue);

      // Verify data is gone
      keys = await adapter.scanKeys(pattern: '*');
      expect(keys.where((k) => k == 'test:drop_key'), isEmpty);
      
      // Switch back to db0
      await adapter.useDatabase('db0');
    });
  });

  group('Redis Key Operations', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_key_conn',
        name: 'Test Redis Key Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        // Cleanup: delete all test keys
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should set and get string value', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:string_key';
      final value = 'Hello Redis!';

      final setResult = await adapter.setString(key, value);
      expect(setResult, isTrue);

      final getResult = await adapter.getString(key);
      expect(getResult, equals(value));
    });

    testWidgets('should set string with TTL', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:ttl_key';
      final value = 'temporary';

      final setResult = await adapter.setString(key, value, ttl: Duration(seconds: 10));
      expect(setResult, isTrue);

      final ttl = await adapter.getTTL(key);
      expect(ttl, greaterThan(0));
      expect(ttl, lessThanOrEqualTo(10));
    });

    testWidgets('should handle hash operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:hash_key';

      // Set hash fields via executeQuery
      await adapter.executeQuery("HSET $key field1 value1");
      await adapter.executeQuery("HSET $key field2 value2");
      await adapter.executeQuery("HSET $key field3 value3");

      final hash = await adapter.getHash(key);
      expect(hash, isNotEmpty);
      expect(hash['field1'], equals('value1'));
      expect(hash['field2'], equals('value2'));
    });

    testWidgets('should handle list operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:list_key';

      // Push items
      await adapter.executeQuery("RPUSH $key item1");
      await adapter.executeQuery("RPUSH $key item2");
      await adapter.executeQuery("RPUSH $key item3");

      final list = await adapter.getList(key);
      expect(list, hasLength(3));
      expect(list[0], equals('item1'));
      expect(list[1], equals('item2'));
      expect(list[2], equals('item3'));
    });

    testWidgets('should handle set operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:set_key';

      // Add members
      await adapter.executeQuery("SADD $key member1");
      await adapter.executeQuery("SADD $key member2");
      await adapter.executeQuery("SADD $key member3");

      final set = await adapter.getSet(key);
      expect(set, hasLength(3));
      expect(set, contains('member1'));
      expect(set, contains('member2'));
      expect(set, contains('member3'));
    });

    testWidgets('should handle sorted set operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:zset_key';

      // Add members with scores
      await adapter.executeQuery("ZADD $key 1 one");
      await adapter.executeQuery("ZADD $key 2 two");
      await adapter.executeQuery("ZADD $key 3 three");

      final zset = await adapter.getZSet(key);
      expect(zset, hasLength(3));
      expect(zset[0], equals('one'));
      expect(zset[1], equals('two'));
      expect(zset[2], equals('three'));
    });

    testWidgets('should get key type', (tester) async {
      if (!redisE2EGatewayReady) return;
      final stringKey = '$testPrefix:type_string';
      final hashKey = '$testPrefix:type_hash';
      final listKey = '$testPrefix:type_list';

      await adapter.setString(stringKey, 'value');
      await adapter.executeQuery("HSET $hashKey field value");
      await adapter.executeQuery("LPUSH $listKey item");

      expect(await adapter.getKeyType(stringKey), equals('string'));
      expect(await adapter.getKeyType(hashKey), equals('hash'));
      expect(await adapter.getKeyType(listKey), equals('list'));
    });

    testWidgets('should delete key', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:delete_key';
      await adapter.setString(key, 'to_delete');

      final delResult = await adapter.deleteKey(key);
      expect(delResult, equals(1));

      final getResult = await adapter.getString(key);
      expect(getResult, isNull);
    });

    testWidgets('should set and remove TTL', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:ttl_test';
      await adapter.setString(key, 'value');

      // Set TTL
      final setResult = await adapter.setTTL(key, Duration(seconds: 60));
      expect(setResult, isTrue);

      final ttl1 = await adapter.getTTL(key);
      expect(ttl1, greaterThan(0));

      // Remove TTL
      final removeResult = await adapter.removeTTL(key);
      expect(removeResult, isTrue);

      final ttl2 = await adapter.getTTL(key);
      expect(ttl2, equals(-1)); // -1 means no expiration
    });
  });

  group('Redis Scan and Search', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_scan_conn',
        name: 'Test Redis Scan Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);

      // Create test keys
      for (var i = 1; i <= 5; i++) {
        await adapter.setString('$testPrefix:user:$i', 'User $i');
        await adapter.setString('$testPrefix:product:$i', 'Product $i');
      }
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should scan keys with pattern', (tester) async {
      if (!redisE2EGatewayReady) return;
      final keys = await adapter.scanKeys(pattern: '$testPrefix:user:*');
      expect(keys, hasLength(5));
    });

    testWidgets('should search keys', (tester) async {
      if (!redisE2EGatewayReady) return;
      final keys = await adapter.searchKeys('$testPrefix:product:*');
      expect(keys, hasLength(5));
    });

    testWidgets('should get all keys with limit', (tester) async {
      if (!redisE2EGatewayReady) return;
      final keys = await adapter.getAllKeys(pattern: '$testPrefix:*', limit: 3);
      expect(keys, hasLength(3));
    });

    testWidgets('should get namespaces (tables)', (tester) async {
      if (!redisE2EGatewayReady) return;
      final tables = await adapter.getTables();
      expect(tables, isNotEmpty);
      expect(tables, contains(testPrefix));
    });
  });

  group('Redis Query Execution', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_query_conn',
        name: 'Test Redis Query Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should execute SET command', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = await adapter.executeQuery("SET $testPrefix:exec_key test_value");
      expect(result.rows, isNotEmpty);
    });

    testWidgets('should execute GET command', (tester) async {
      if (!redisE2EGatewayReady) return;
      await adapter.executeQuery("SET $testPrefix:get_key hello");
      final result = await adapter.executeQuery("GET $testPrefix:get_key");
      
      expect(result.rows, isNotEmpty);
    });

    testWidgets('should execute HSET/HGET commands', (tester) async {
      if (!redisE2EGatewayReady) return;
      await adapter.executeQuery("HSET $testPrefix:hash name Alice");
      final result = await adapter.executeQuery("HGET $testPrefix:hash name");
      
      expect(result.rows, isNotEmpty);
    });

    testWidgets('should execute LPUSH/LRANGE commands', (tester) async {
      if (!redisE2EGatewayReady) return;
      await adapter.executeQuery("LPUSH $testPrefix:list first");
      await adapter.executeQuery("LPUSH $testPrefix:list second");
      final result = await adapter.executeQuery("LRANGE $testPrefix:list 0 -1");
      
      expect(result.rows, isNotEmpty);
    });

    testWidgets('should execute INFO command', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = await adapter.executeQuery("INFO server");
      expect(result.rows, isNotEmpty);
    });
  });

  group('Redis Advanced Operations', () {
    late RedisAdapter adapter;

    setUp(() async {
      adapter = RedisAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_redis_adv_conn',
        name: 'Test Redis Advanced Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    testWidgets('should get server version', (tester) async {
      if (!redisE2EGatewayReady) return;
      final version = await adapter.getServerVersion();

      expect(version, isNotNull);
      expect(version!['database'], equals('Redis'));
      expect(version['version'], isNotNull);
    });

    testWidgets('should get server info', (tester) async {
      if (!redisE2EGatewayReady) return;
      final info = await adapter.getServerInfo();

      expect(info, isNotNull);
      expect(info, isA<Map<String, String>>());
      expect(info['redis_version'], isNotNull);
    });

    testWidgets('should get database size', (tester) async {
      if (!redisE2EGatewayReady) return;
      final size = await adapter.getDatabaseSize();
      expect(size, isA<int>());
      expect(size, greaterThanOrEqualTo(0));
    });

    testWidgets('should get memory info', (tester) async {
      if (!redisE2EGatewayReady) return;
      final memory = await adapter.getMemoryInfo();

      expect(memory, isNotNull);
      expect(memory, isA<Map<String, String>>());
    });

    testWidgets('should get charsets', (tester) async {
      if (!redisE2EGatewayReady) return;
      final charsets = await adapter.getCharsets();
      expect(charsets, isNotEmpty);
      expect(charsets, contains('UTF-8'));
    });

    testWidgets('should get views list (empty for Redis)', (tester) async {
      if (!redisE2EGatewayReady) return;
      final views = await adapter.getViews();
      expect(views, isA<List<String>>());
      expect(views, isEmpty);
    });

    testWidgets('should get procedures list (empty for Redis)', (tester) async {
      if (!redisE2EGatewayReady) return;
      final procedures = await adapter.getProcedures();
      expect(procedures, isA<List<String>>());
      expect(procedures, isEmpty);
    });

    testWidgets('should get functions list (empty for Redis)', (tester) async {
      if (!redisE2EGatewayReady) return;
      final functions = await adapter.getFunctions();
      expect(functions, isA<List<String>>());
      expect(functions, isEmpty);
    });
  });

  group('Redis Table Operations', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_table_conn',
        name: 'Test Redis Table Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);

      // Create test namespace data
      for (var i = 1; i <= 3; i++) {
        await adapter.setString('$testPrefix:key$i', 'value$i');
      }
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get table columns (virtual)', (tester) async {
      if (!redisE2EGatewayReady) return;
      final columns = await adapter.getTableColumns(testPrefix);
      
      expect(columns, hasLength(5));
      expect(columns[0].name, equals('key'));
      expect(columns[1].name, equals('type'));
      expect(columns[2].name, equals('value'));
    });

    testWidgets('should get table data', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = await adapter.getTableData(testPrefix, limit: 10, offset: 0);
      
      expect(result.rows, hasLength(3));
      expect(result.columns, contains('key'));
      expect(result.columns, contains('type'));
      expect(result.columns, contains('value'));
    });

    testWidgets('should get table row count', (tester) async {
      if (!redisE2EGatewayReady) return;
      final count = await adapter.getTableRowCount(testPrefix);
      expect(count, equals(3));
    });

    testWidgets('should drop table (namespace)', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = await adapter.dropTable(testPrefix);
      expect(result, isTrue);

      final count = await adapter.getTableRowCount(testPrefix);
      expect(count, equals(0));
    });

    testWidgets('should truncate table (namespace)', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = await adapter.truncateTable(testPrefix);
      expect(result, isTrue);

      final count = await adapter.getTableRowCount(testPrefix);
      expect(count, equals(0));
    });
  });

  group('Redis Export and AI Operations', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_export_conn',
        name: 'Test Redis Export Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);

      // Create various data types
      await adapter.setString('$testPrefix:string', 'Hello');
      await adapter.executeQuery("HSET $testPrefix:hash field1 value1");
      await adapter.executeQuery("LPUSH $testPrefix:list item1");
      await adapter.executeQuery("SADD $testPrefix:set member1");
      await adapter.executeQuery("ZADD $testPrefix:zset 1 member1");
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should export database structure', (tester) async {
      if (!redisE2EGatewayReady) return;
      final structure = await adapter.exportDatabaseStructure('db0');

      expect(structure, isNotEmpty);
      expect(structure, contains('Redis Database Export'));
    });

    testWidgets('should get AI schema summary', (tester) async {
      if (!redisE2EGatewayReady) return;
      final summary = await adapter.getAiSchemaSummary();

      expect(summary, isNotEmpty);
      expect(summary, contains('Redis'));
    });

    testWidgets('should execute AI command', (tester) async {
      if (!redisE2EGatewayReady) return;
      await adapter.setString('$testPrefix:ai_test', 'value');
      
      final result = await adapter.executeAiCommand("GET $testPrefix:ai_test");

      expect(result.success, isTrue);
    });

    testWidgets('should validate safe command', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = adapter.validateCommand('GET test_key');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.safe));
    });

    testWidgets('should validate dangerous command', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = adapter.validateCommand('FLUSHALL');

      expect(result.allowed, isFalse);
      expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
    });

    testWidgets('should validate warning command', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = adapter.validateCommand('SET test_key value');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.warning));
    });

    testWidgets('should block KEYS command', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = adapter.validateCommand('KEYS *');

      expect(result.allowed, isFalse);
      expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
    });
  });

  group('Redis Connection Management', () {
    late RedisAdapter adapter;

    testWidgets('should disconnect cleanly', (tester) async {
      if (!redisE2EGatewayReady) return;
      adapter = RedisAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_redis_disc_conn',
        name: 'Test Redis Disconnect Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
      expect(adapter.isConnected, isTrue);

      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('should handle multiple connections', (tester) async {
      if (!redisE2EGatewayReady) return;
      final adapter1 = RedisAdapter();
      final adapter2 = RedisAdapter();

      final conn1 = DatabaseConnection(
        id: 'multi_1',
        name: 'Multi Connection 1',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: 'db0',
      );

      final conn2 = DatabaseConnection(
        id: 'multi_2',
        name: 'Multi Connection 2',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: 'db1',
      );

      final result1 = await adapter1.connect(conn1);
      final result2 = await adapter2.connect(conn2);

      expect(result1, isTrue);
      expect(result2, isTrue);
      expect(adapter1.isConnected, isTrue);
      expect(adapter2.isConnected, isTrue);

      await adapter1.disconnect();
      await adapter2.disconnect();
    });
  });

  group('Redis Advanced Types', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_advtypes_conn',
        name: 'Test Redis Advanced Types Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should handle stream operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:stream';
      
      // Add stream entries via executeQuery
      await adapter.executeQuery("XADD $key * sensor_id 1234 temperature 19.8");
      await adapter.executeQuery("XADD $key * sensor_id 1235 temperature 20.1");
      await adapter.executeQuery("XADD $key * sensor_id 1236 temperature 18.5");

      final length = await adapter.getStreamLength(key);
      expect(length, equals(3));

      final entries = await adapter.getStreamEntries(key);
      expect(entries, hasLength(3));
      expect(entries[0]['sensor_id'], equals('1234'));
      expect(entries[0]['temperature'], equals('19.8'));

      // Verify via getTableData
      final data = await adapter.getTableData(testPrefix);
      final streamRow = data.rows.firstWhere((r) => r['key'] == key);
      expect(streamRow['type'], equals('stream'));
      expect(streamRow['value'].toString(), contains('stream'));
    });

    testWidgets('should handle bitmap operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:bitmap';
      
      // Set bits
      await adapter.executeQuery("SETBIT $key 0 1");
      await adapter.executeQuery("SETBIT $key 7 1");
      await adapter.executeQuery("SETBIT $key 100 1");

      final bitCount = await adapter.getBitCount(key);
      expect(bitCount, equals(3));

      // Note: Redis TYPE returns 'string' for bitmap keys
      expect(await adapter.getKeyType(key), equals('string'));

      // Verify via getTableData (bitmap is treated as string by TYPE)
      final data = await adapter.getTableData(testPrefix);
      final bitmapRow = data.rows.firstWhere((r) => r['key'] == key);
      expect(bitmapRow['type'], equals('string'));
    });

    testWidgets('should handle geo operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:geo';
      
      // Add geo members
      await adapter.executeQuery("GEOADD $key 116.4074 39.9042 Beijing");
      await adapter.executeQuery("GEOADD $key 121.4737 31.2304 Shanghai");
      await adapter.executeQuery("GEOADD $key 113.2644 23.1291 Guangzhou");

      final geo = await adapter.getGeo(key);
      expect(geo, hasLength(3));
      expect(geo, contains('Beijing'));
      expect(geo, contains('Shanghai'));
      expect(geo, contains('Guangzhou'));

      final positions = await adapter.getGeoPositions(key, ['Beijing', 'Shanghai']);
      expect(positions, contains('Beijing'));
      expect(positions, contains('Shanghai'));
      expect(positions['Beijing']![0], closeTo(116.4, 0.1));
      expect(positions['Beijing']![1], closeTo(39.9, 0.1));

      // Note: Redis TYPE returns 'zset' for geo keys (geo is implemented as zset)
      expect(await adapter.getKeyType(key), equals('zset'));

      // Verify via getTableData (geo is treated as zset by TYPE)
      final data = await adapter.getTableData(testPrefix);
      final geoRow = data.rows.firstWhere((r) => r['key'] == key);
      expect(geoRow['type'], equals('zset'));
    });

    testWidgets('should handle hyperloglog operations', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:hll';
      
      // Add elements
      await adapter.executeQuery("PFADD $key a b c d e f g h i j");
      await adapter.executeQuery("PFADD $key k l m n o p q r s t");

      final count = await adapter.getHyperLogLogCount(key);
      expect(count, greaterThanOrEqualTo(10));
      expect(count, lessThanOrEqualTo(25)); // approximate, should be around 20

      // Note: Redis TYPE returns 'string' for HyperLogLog keys
      expect(await adapter.getKeyType(key), equals('string'));

      // Verify via getTableData (HLL is treated as string by TYPE)
      final data = await adapter.getTableData(testPrefix);
      final hllRow = data.rows.firstWhere((r) => r['key'] == key);
      expect(hllRow['type'], equals('string'));
    });

    testWidgets('should get memory usage of key', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:memtest';
      await adapter.setString(key, 'test_value_for_memory_usage');

      final mem = await adapter.getMemoryUsage(key);
      expect(mem, greaterThan(0));
    });
  });

  group('Redis Lua Scripting', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_lua_conn',
        name: 'Test Redis Lua Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should execute Lua script with simple return', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = await adapter.evalLua(
        'return {KEYS[1], KEYS[2], ARGV[1], ARGV[2]}',
        ['$testPrefix:key1', '$testPrefix:key2'],
        ['hello', 'world'],
      );

      expect(result, isA<List>());
      final list = result as List;
      expect(list, hasLength(4));
      expect(list[0], equals('$testPrefix:key1'));
      expect(list[1], equals('$testPrefix:key2'));
      expect(list[2], equals('hello'));
      expect(list[3], equals('world'));
    });

    testWidgets('should execute Lua script with KEYS and ARGV', (tester) async {
      if (!redisE2EGatewayReady) return;
      // Set a key first
      await adapter.setString('$testPrefix:counter', '10');

      final result = await adapter.evalLua(
        "local current = redis.call('GET', KEYS[1]); return current + tonumber(ARGV[1])",
        ['$testPrefix:counter'],
        ['5'],
      );

      expect(result, equals(15));
    });
  });

  group('Redis Cursor and Rename', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_cursor_conn',
        name: 'Test Redis Cursor Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);

      // Create test keys for cursor scan
      for (var i = 1; i <= 10; i++) {
        await adapter.setString('$testPrefix:cursor:$i', 'value$i');
      }
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should paginate with scanKeysCursor', (tester) async {
      if (!redisE2EGatewayReady) return;
      var cursor = 0;
      var totalKeys = 0;
      var iterations = 0;

      do {
        final result = await adapter.scanKeysCursor(cursor: cursor, pattern: '$testPrefix:cursor:*', count: 3);
        cursor = result.cursor;
        totalKeys += result.keys.length;
        iterations++;
        // Safety limit
        expect(iterations, lessThan(50));
      } while (cursor != 0);

      expect(totalKeys, equals(10));
      expect(iterations, greaterThan(1)); // Should take multiple iterations with count=3
    });

    testWidgets('should rename a key', (tester) async {
      if (!redisE2EGatewayReady) return;
      final oldKey = '$testPrefix:rename_old';
      final newKey = '$testPrefix:rename_new';
      await adapter.setString(oldKey, 'original_value');

      final result = await adapter.renameKey(oldKey, newKey);
      expect(result, isTrue);

      final oldValue = await adapter.getString(oldKey);
      expect(oldValue, isNull);

      final newValue = await adapter.getString(newKey);
      expect(newValue, equals('original_value'));
    });
  });

  group('Redis Lightweight Metadata', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_meta_conn',
        name: 'Test Redis Metadata Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get string length', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:strlen';
      await adapter.setString(key, 'Hello World');

      final len = await adapter.getStringLength(key);
      expect(len, equals(11));
    });

    testWidgets('should get hash length and preview', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:hash_meta';
      await adapter.executeQuery("HSET $key name Alice");
      await adapter.executeQuery("HSET $key age 30");
      await adapter.executeQuery("HSET $key city Beijing");
      await adapter.executeQuery("HSET $key country China");

      final len = await adapter.getHashLength(key);
      expect(len, equals(4));

      final preview = await adapter.getHashPreview(key, maxFields: 2);
      expect(preview.length, lessThanOrEqualTo(2));
      expect(preview.isNotEmpty, isTrue);
    });

    testWidgets('should get list length and preview', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:list_meta';
      await adapter.executeQuery("RPUSH $key a b c d e f g h");

      final len = await adapter.getListLength(key);
      expect(len, equals(8));

      final preview = await adapter.getListPreview(key, maxElements: 3);
      expect(preview, hasLength(3));
      expect(preview[0], equals('a'));
    });

    testWidgets('should get set length and preview', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:set_meta';
      await adapter.executeQuery("SADD $key x y z w v u t s r q");

      final len = await adapter.getSetLength(key);
      expect(len, equals(10));

      final preview = await adapter.getSetPreview(key, maxMembers: 4);
      expect(preview.length, lessThanOrEqualTo(4));
      expect(preview.isNotEmpty, isTrue);
    });

    testWidgets('should get zset length, preview and scores', (tester) async {
      if (!redisE2EGatewayReady) return;
      final key = '$testPrefix:zset_meta';
      await adapter.executeQuery("ZADD $key 100 Alice");
      await adapter.executeQuery("ZADD $key 200 Bob");
      await adapter.executeQuery("ZADD $key 150 Charlie");

      final len = await adapter.getZSetLength(key);
      expect(len, equals(3));

      final preview = await adapter.getZSetPreview(key, maxItems: 2);
      expect(preview, hasLength(2));

      final withScores = await adapter.getZSetWithScores(key);
      expect(withScores, hasLength(3));
      expect(withScores[0]['member'], equals('Alice'));
      expect(withScores[0]['score'], equals('100'));
      expect(withScores[1]['member'], equals('Charlie'));
      expect(withScores[1]['score'], equals('150'));
      expect(withScores[2]['member'], equals('Bob'));
      expect(withScores[2]['score'], equals('200'));
    });
  });

  group('Redis Extended Operations', () {
    late RedisAdapter adapter;
    late String testPrefix;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();
      
      final connection = DatabaseConnection(
        id: 'test_redis_ext_conn',
        name: 'Test Redis Extended Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          final keys = await adapter.scanKeys(pattern: '$testPrefix:*');
          if (keys.isNotEmpty) {
            await adapter.runCommand(['DEL', ...keys]);
          }
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get non-empty databases', (tester) async {
      if (!redisE2EGatewayReady) return;
      // First create data in db14 via a separate connection
      final adapter2 = RedisAdapter();
      final conn2 = DatabaseConnection(
        id: 'test_redis_ext_conn2',
        name: 'Test Redis Extended Connection 2',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: 'db14',
      );
      await adapter2.connect(conn2);
      await adapter2.setString('$testPrefix:db14_key', 'value');
      await adapter2.disconnect();

      // Now check non-empty databases from the main adapter (on db15)
      await adapter.useDatabase('db14');
      final nonEmpty = await adapter.getNonEmptyDatabases();
      expect(nonEmpty, isA<List<String>>());
      // db14 should be in the list (it has our test key)
      expect(nonEmpty, contains('db14'));

      // Cleanup db14
      final adapter3 = RedisAdapter();
      final conn3 = DatabaseConnection(
        id: 'test_redis_ext_conn3',
        name: 'Test Redis Extended Connection 3',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: 'db14',
      );
      await adapter3.connect(conn3);
      await adapter3.dropDatabase('db14');
      await adapter3.disconnect();
    });

    testWidgets('should execute SQL script with multiple commands', (tester) async {
      if (!redisE2EGatewayReady) return;
      final script = '''
# This is a comment
SET $testPrefix:script_key1 value1
HSET $testPrefix:script_hash field1 val1
-- This is also a comment
LPUSH $testPrefix:script_list item1
'''.trim();

      final result = await adapter.executeSqlScript(script);
      expect(result, isTrue);

      // Verify all keys were created
      expect(await adapter.getString('$testPrefix:script_key1'), equals('value1'));
      final hash = await adapter.getHash('$testPrefix:script_hash');
      expect(hash['field1'], equals('val1'));
      final list = await adapter.getList('$testPrefix:script_list');
      expect(list, contains('item1'));
    });

    testWidgets('should rename a namespace (table)', (tester) async {
      if (!redisE2EGatewayReady) return;
      // Create keys in old namespace
      await adapter.setString('$testPrefix:oldns:key1', 'value1');
      await adapter.setString('$testPrefix:oldns:key2', 'value2');

      // Rename namespace
      final result = await adapter.renameTable('$testPrefix:oldns', '$testPrefix:newns');
      expect(result, isTrue);

      // Verify old keys don't exist
      expect(await adapter.getString('$testPrefix:oldns:key1'), isNull);

      // Verify new keys exist
      expect(await adapter.getString('$testPrefix:newns:key1'), equals('value1'));
      expect(await adapter.getString('$testPrefix:newns:key2'), equals('value2'));

      // Cleanup
      await adapter.dropTable('$testPrefix:newns');
    });

    testWidgets('should handle invalid command gracefully', (tester) async {
      if (!redisE2EGatewayReady) return;
      // Execute a non-existent command
      try {
        await adapter.executeQuery('NOTAREALCOMMAND test_key');
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString(), contains('失败'));
      }
    });

    testWidgets('should handle getExplainPlan', (tester) async {
      if (!redisE2EGatewayReady) return;
      final result = await adapter.getExplainPlan('GET test_key');
      expect(result.columns, contains('info'));
      expect(result.rows, isNotEmpty);
      expect(result.rows[0]['info'].toString(), contains('Redis'));
    });
  });
}
