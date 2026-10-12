// ============================================================================
// T5（W-05/W-08）· SQLite 维护三件真库 E2E（本地临时文件库，自建自删）
//
// 覆盖（任务书验收口径）：
// 1. 通道核实：VACUUM/ANALYZE/REINDEX 经 provider 既有执行面
//    （dbService 单语句非事务）对真库文件执行成功——VACUUM 在事务块内
//    会报错，本用例通过 = 通道无事务包裹的实证；
// 2. VACUUM 后 PRAGMA integrity_check = ok + 库仍可正常查询；
// 3. ANALYZE 后 sqlite_stat1 出现该表行；
// 4. REINDEX 执行成功返回；
// 5. 确认取消路径 = 库内容前后一致（零执行）。
//
// 全链路走生产默认执行器/审计器（SqliteMaintenanceDialog.show），无接缝注入。
// 真库：SQLiteTestConfig 临时文件（无服务器依赖，tearDown 清理含 -wal/-shm）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/dialogs/sqlite_maintenance_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';

import 'config/sqlite_test_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;
  late String dbPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dbPath = SQLiteTestConfig.generateTestDatabasePath();
    provider = AppProvider();
    server = DbServer(
      id: 't5-maint-e2e',
      type: DatabaseType.sqlite,
      name: 'T5 Maintain',
      host: dbPath,
      port: 0,
    );
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
    await SQLiteTestConfig.cleanupDatabase(dbPath);
  });

  /// 建表 + 插数 + 删数（制造碎片与待统计数据），并建立真实连接。
  /// CREATE INDEX 经 executeQueryBypassDdl（用户已确认语义的既有通道）——
  /// executeSqlScript 对 CREATE_INDEX 触发 DDL 确认拦截（Medium Risk）。
  Future<void> connectAndSeed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await provider.connection.saveConnection(server);
      final connected = await provider.connection.connectToServer(server);
      expect(connected, isTrue, reason: '本地 SQLite 连接失败');
      final db = provider.connection.dbService;
      await db.executeSqlScript(
        'CREATE TABLE maint_probe(id INTEGER PRIMARY KEY, val TEXT);'
        "INSERT INTO maint_probe(val) VALUES ('a'),('b'),('c'),('d'),('e'),('f'),('g'),('h');"
        'DELETE FROM maint_probe WHERE id > 3;',
        connectionId: server.id,
      );
      await db.executeQueryBypassDdl(
        'CREATE INDEX idx_maint_val ON maint_probe(val);',
        connectionId: server.id,
      );
    });
  }

  /// 生产路径打开维护 dialog（默认执行器 + 默认审计）。
  Future<void> pumpHostAndOpenDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => SqliteMaintenanceDialog.show(
                  context,
                  connectionId: server.id,
                  databaseName: server.host,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance'), findsOneWidget);
  }

  /// 确认门 → 确认执行 → 等真库 I/O 完成。
  Future<void> confirmAction(WidgetTester tester, String action) async {
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
    expect(find.text('Run $action on this database?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('T5-E2E-VACUUM：执行成功 + integrity_check ok + 库仍可查询', (tester) async {
    await connectAndSeed(tester);
    await pumpHostAndOpenDialog(tester);

    await confirmAction(tester, 'VACUUM');
    expect(find.textContaining('VACUUM completed'), findsOneWidget);

    await tester.runAsync(() async {
      final db = provider.connection.dbService;
      final integrity = await db.executeQuery(
        'PRAGMA integrity_check;',
        connectionId: server.id,
      );
      expect(integrity.first.values.first.toString(), 'ok');
      final count = await db.executeQuery(
        'SELECT COUNT(*) AS c FROM maint_probe;',
        connectionId: server.id,
      );
      expect(count.first.values.first, 3, reason: 'VACUUM 不得改变数据内容');
    });
  });

  testWidgets('T5-E2E-ANALYZE：执行成功 + sqlite_stat1 出现该表统计行', (tester) async {
    await connectAndSeed(tester);
    await pumpHostAndOpenDialog(tester);

    await confirmAction(tester, 'ANALYZE');
    expect(find.textContaining('ANALYZE completed'), findsOneWidget);

    await tester.runAsync(() async {
      final stat = await provider.connection.dbService.executeQuery(
        "SELECT COUNT(*) AS c FROM sqlite_stat1 WHERE tbl = 'maint_probe';",
        connectionId: server.id,
      );
      expect(stat.first.values.first, greaterThan(0),
          reason: 'ANALYZE 后 sqlite_stat1 需含 maint_probe 行');
    });
  });

  testWidgets('T5-E2E-REINDEX：执行成功返回', (tester) async {
    await connectAndSeed(tester);
    await pumpHostAndOpenDialog(tester);

    await confirmAction(tester, 'REINDEX');
    expect(find.textContaining('REINDEX completed'), findsOneWidget);

    // 索引仍在且可查询
    await tester.runAsync(() async {
      final rows = await provider.connection.dbService.executeQuery(
        "SELECT id FROM maint_probe WHERE val = 'a';",
        connectionId: server.id,
      );
      expect(rows, hasLength(1));
    });
  });

  testWidgets('T5-E2E-CANCEL：确认取消 = 零执行、库内容前后一致', (tester) async {
    await connectAndSeed(tester);

    Future<List<Map<String, dynamic>>> snapshot() =>
        provider.connection.dbService.executeQuery(
          'SELECT id, val FROM maint_probe ORDER BY id;',
          connectionId: server.id,
        );

    var before = <Map<String, dynamic>>[];
    await tester.runAsync(() async => before = await snapshot());

    await pumpHostAndOpenDialog(tester);
    await tester.tap(find.text('ANALYZE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ANALYZE completed'), findsNothing);
    expect(find.textContaining('Running ANALYZE'), findsNothing);

    var after = <Map<String, dynamic>>[];
    await tester.runAsync(() async => after = await snapshot());
    expect(after.toString(), before.toString(),
        reason: '取消路径不得改变库内容');

    // 取消后可再次发起（同一 dialog 内确认执行成功 = 门复位）
    await confirmAction(tester, 'ANALYZE');
    expect(find.textContaining('ANALYZE completed'), findsOneWidget);
  });
}
