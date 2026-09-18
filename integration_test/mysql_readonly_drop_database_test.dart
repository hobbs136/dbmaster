// ============================================================================
// Regression: Read-Only connection must block destructive DB operations
//
// Bug: 开启 Read Only 的连接仍能通过侧栏「Drop Database」删库。
// Root cause: 唯一的 read-only 守卫在 DatabaseService.executeQuery 里，而
//   DatabaseService.dropDatabase / createDatabase 直接走 adapter、不经
//   executeQuery，read-only 被旁路。
// Fix: 在 _SchemaManager.dropDatabase / createDatabase 服务层 choke point 加
//   read-only 守卫（throw）。
//
// This test connects to a REAL MySQL server and asserts the guard fires AND the
// database survives — without the fix, dropDatabase would delete the DB and the
// existence assertion would fail.
// Target: real MySQL via DBMASTER_MYSQL_* (see config/mysql_test_config.dart)
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/readonly_guard.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Seed a uniquely-named DB via a direct read-write adapter connection.
  Future<MySQLAdapter> seedDatabase(String dbName) async {
    final adapter = MySQLAdapter();
    await adapter.connect(
      DatabaseConnection(
        id: 'seed_${dbName.hashCode}',
        name: 'Read-Only Seed',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      ),
    );
    await adapter.createDatabase(dbName);
    return adapter;
  }

  Future<bool> databaseExists(MySQLAdapter adapter, String dbName) async {
    final dbs = await adapter.getDatabases();
    return dbs.contains(dbName);
  }

  /// Build an AppProvider connected to the test server with the given read-only flag.
  Future<({AppProvider provider, DbServer server})> connectProvider({
    required String dbName,
    required bool readOnly,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();
    AppProvider.devBypassGates = true; // 集成测试绕过 Free/Pro 门禁
    final server = DbServer(
      id: 'ro_test_${dbName.hashCode}_$readOnly',
      name: 'Read-Only Test',
      type: DatabaseType.mysql,
      host: MySQLTestConfig.host,
      port: MySQLTestConfig.port,
      username: MySQLTestConfig.username,
      password: MySQLTestConfig.password,
      readOnly: readOnly,
    );
    await provider.connection.saveConnection(server);
    final connected = await provider.connectToServer(server);
    expect(connected, isTrue, reason: 'Failed to connect to MySQL');
    await provider.refreshDatabases();
    return (provider: provider, server: server);
  }

  Future<void> cleanup(MySQLAdapter adapter, AppProvider provider,
      DbServer server, List<String> dbNames) async {
    for (final db in dbNames) {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$db`');
      } catch (_) {}
    }
    try {
      await adapter.disconnect();
    } catch (_) {}
    try {
      await provider.disconnectConnection(connectionId: server.id);
    } catch (_) {}
    try {
      provider.dispose();
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // THE REGRESSION (reported bug): read-only must block Drop Database
  // --------------------------------------------------------------------------
  testWidgets('read-only connection: dropDatabase is rejected and DB survives',
      (tester) async {
    if (!mysqlE2EGatewayReady) {
      return;
    }
    final dbName = MySQLTestConfig.generateTestDatabaseName();
    final adapter = await seedDatabase(dbName);
    final ctx = await connectProvider(dbName: dbName, readOnly: true);

    // Guard must throw (message uniquely identifies the read-only guard, not a
    // coincidental connection error).
    await expectLater(
      ctx.provider.dropDatabase(dbName),
      throwsA(predicate(
          (Object? e) =>
          e is ReadOnlyBlockedException || e.toString().contains('只读模式'))),
      reason: 'read-only 连接必须拒绝 dropDatabase',
    );

    // Load-bearing assertion: the DB must still exist. Without the fix it would
    // have been deleted.
    expect(await databaseExists(adapter, dbName), isTrue,
        reason: 'read-only 守卫失败：数据库被删除了');

    await cleanup(adapter, ctx.provider, ctx.server, [dbName]);
  });

  // --------------------------------------------------------------------------
  // Sibling guard: read-only must block Create Database
  // --------------------------------------------------------------------------
  testWidgets('read-only connection: createDatabase is rejected', (tester) async {
    if (!mysqlE2EGatewayReady) {
      return;
    }
    final dbName = MySQLTestConfig.generateTestDatabaseName();
    // No seed — we attempt to CREATE this one.
    final adapter = await seedDatabase('__placeholder_for_adapter_conn__');
    // Remove the placeholder so it doesn't pollute the assertion.
    await adapter.executeQuery(
        'DROP DATABASE IF EXISTS `__placeholder_for_adapter_conn__`');
    final ctx = await connectProvider(dbName: dbName, readOnly: true);

    await expectLater(
      ctx.provider.createDatabase(dbName),
      throwsA(predicate(
          (Object? e) =>
          e is ReadOnlyBlockedException || e.toString().contains('只读模式'))),
      reason: 'read-only 连接必须拒绝 createDatabase',
    );
    expect(await databaseExists(adapter, dbName), isFalse,
        reason: 'read-only 守卫失败：数据库被创建了');

    await cleanup(adapter, ctx.provider, ctx.server, [dbName]);
  });

  // --------------------------------------------------------------------------
  // Positive control: read-write connection can still drop (guard does not
  // over-block). Proves the test wiring is correct and the guard is conditional.
  // --------------------------------------------------------------------------
  testWidgets('read-write connection: dropDatabase still works', (tester) async {
    if (!mysqlE2EGatewayReady) {
      return;
    }
    final dbName = MySQLTestConfig.generateTestDatabaseName();
    final adapter = await seedDatabase(dbName);
    final ctx = await connectProvider(dbName: dbName, readOnly: false);

    expect(await databaseExists(adapter, dbName), isTrue);

    final ok = await ctx.provider.dropDatabase(dbName);
    expect(ok, isTrue, reason: 'read-write 连接应能正常删库');
    // 网关时序：dropDatabase 成功后 fire-and-forget 的 refreshDatabases 是
    // 异步 HTTP，落点晚于 cleanup 的 dispose——先 pump 干净再清场。
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(await databaseExists(adapter, dbName), isFalse,
        reason: 'read-write 删库后库应不存在');

    await cleanup(adapter, ctx.provider, ctx.server, [dbName]);
  });
}
