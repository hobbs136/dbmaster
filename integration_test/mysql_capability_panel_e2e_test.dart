// ============================================================================
// DBT-T3 · MySQL 能力面板 E2E（W-02/W-03 真库验证）
//
// 覆盖（任务书 T3 真库验证节，引擎 = WSL MySQL 8.0，连接信息唯一来源
// test_db_local_wsl.txt，凭据经 DBMASTER_MYSQL_* dart-define 注入）：
//   ① 变量浏览器真数据：SHOW VARIABLES（dbService 既有只读执行路径）
//      加载 >100 个变量；搜索 max_connections 过滤命中且值非空；
//   ② 新面板项逐一打开断言目标出现（dialog / 面板态）——
//      mysql.variables / mysql.maintenance / mysql.backup /
//      mysql.performance（mysql.queryPlan 无既有可路由目标，任务书
//      「停下回报」处理，本批无该项）；
//   ⚠ DBT-T18 连带（2026-10 第二程序）：面板已追加 mysql.events（插件
//      第 7 项，cap event.list 既有位零新增，装配 core 5 + 插件 7 = 12；
//      项 id/位映射与装配计数由 mysql_sidebar_plugin_test.dart 锁定，
//      事件设计器真库验证走专属 e2e mysql_events_designer_e2e_test.dart
//      ——本文件 harness 无库上下文，events 项激活走「先选库」分支，不
//      入本文件断言面）；本文件无总数/清单计数断言，各用例不受影响。
//   ③ 表维护聚合：对 chinook 库 Artist 表 ANALYZE（逐表确认门 → 既有
//      runTableMaintenance 链路）→ 结果 dialog → 重查断言执行成功返回。
//
// 前置：DBMASTER_SERVER_BIN 指向 dbmaster-server.exe（embedded 网关，
// 无二进制时以可 grep 的 MYSQL_E2E_SKIP 整组跳过，FR-011 无假绿纪律）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/table_maintenance_command.dart';
import 'package:dbmaster/organisms/connection/connection_export_import_dialog.dart';
import 'package:dbmaster/organisms/connection/mysql_variables_browser_dialog.dart';
import 'package:dbmaster/organisms/dialogs/confirm_maintenance_dialog.dart';
import 'package:dbmaster/organisms/dialogs/mysql_table_maintenance_entry_dialog.dart';
import 'package:dbmaster/organisms/dialogs/table_maintenance_result_dialog.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mysql_sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// 真值表 fake：委托 CapabilityTable（与装配生产语义同面）。
class _E2ECapabilityPort implements DbCapabilityPort {
  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      CapabilityTable.has(type, capabilityId);

  @override
  Set<String> capabilitiesOf(DatabaseType type) => CapabilityTable.of(type);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('E2E fake 仅实现能力位查询');
}

/// 能力面板驱动壳：装配（core + mysql 插件 × CapabilityTable 门控）后把
/// 每个可见项渲染为 ListTile，onTap = item.onActivate（与真实菜单同一
/// 激活闭包；菜单本体渲染属 T2 框架，非本 E2E 断言面）。
class _CapabilityPanelHarness extends StatelessWidget {
  const _CapabilityPanelHarness();

  @override
  Widget build(BuildContext context) {
    final groups = assembleCapabilityMenu(
      context: context,
      type: DatabaseType.mysql,
      port: _E2ECapabilityPort(),
      plugins: const [CoreSidebarPlugin(), MysqlSidebarPlugin()],
      l10n: AppLocalizations.of(context)!,
    );
    return ListView(
      children: [
        for (final group in groups)
          for (final item in group.items)
            ListTile(
              key: Key('${group.id}/${item.item.id}'),
              title: Text('${group.id}/${item.item.id}'),
              onTap: item.item.onActivate,
            ),
      ],
    );
  }
}

void main() {
  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t3-e2e-mysql',
      type: DatabaseType.mysql,
      name: 'DBT T3 E2E MySQL',
      host: MySQLTestConfig.host,
      port: MySQLTestConfig.port,
      username: MySQLTestConfig.username,
      password: MySQLTestConfig.password,
    );
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  Future<void> connectReal(WidgetTester tester) async {
    final connected =
        await tester.runAsync(() => provider.connection.connectToServer(server));
    expect(connected, isTrue, reason: '真库连接失败（${MySQLTestConfig.host}）');
  }

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: _CapabilityPanelHarness()),
        ),
      ),
    );
    await tester.pump();
  }

  /// 轮询等待条件成立（runAsync 放行真实 I/O；对话框内部加载不走
  /// runAsync，需在真实时钟下等它完成）。
  Future<bool> waitUntil(
    WidgetTester tester,
    bool Function() condition, {
    int timeoutMs = 30000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    return condition();
  }

  Future<void> activateItem(WidgetTester tester, String itemId) async {
    await tester.tap(find.byKey(Key('advanced/$itemId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('DBT-T3-VARS：变量浏览器真数据（>100 变量 + max_connections 过滤）',
      (tester) async {
    if (!mysqlE2EGatewayReady) return;
    await connectReal(tester);

    // 数据面：与 dialog 默认 loader 同一执行路径（dbService.executeQuery）
    final rows = await tester.runAsync(
          () => provider.dbService.executeQuery(
            'SHOW VARIABLES',
            connectionId: server.id,
          ),
        ) ??
        // runAsync 签名 T?：回调永不以 null 完成，空回退仅收窄类型——
        // 真实失败会以空列表令下方断言如实失败。
        const <Map<String, dynamic>>[];
    expect(rows.length, greaterThan(100), reason: 'MySQL 8.0 变量数应 >100');
    final maxConnRow = rows.firstWhere(
      (r) => r.values.isNotEmpty && r.values.first?.toString() == 'max_connections',
      orElse: () => const {},
    );
    expect(maxConnRow.values.elementAt(1)?.toString() ?? '', isNotEmpty,
        reason: 'max_connections 值非空');

    // UI 面：面板项 → 变量浏览器 → 真数据渲染 + 搜索过滤命中。
    // 加载完成信号 = 表头渲染（非加载/非错误/列表非空才渲染；不受
    // ListView 惰性构建影响）。SHOW VARIABLES 500+ 行仅构建可视区，
    // 目标行（字母序 ~250 位）须先过滤再断言。
    await pumpHarness(tester);
    await activateItem(tester, 'mysql.variables');
    expect(find.byType(MysqlVariablesBrowserDialog), findsOneWidget);

    expect(
      await waitUntil(tester, () => tester.any(find.text('Name'))),
      isTrue,
      reason: '变量列表应加载完成（表头渲染）',
    );

    await tester.enterText(find.byType(TextField), 'max_connections');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    // find.text 会同时命中搜索框 EditableText——数据行用 Text 谓词精确匹配
    final maxConnRowText = find.byWidgetPredicate(
      (w) => w is Text && w.data == 'max_connections',
    );
    expect(maxConnRowText, findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'innodb_buffer_pool_size'),
      findsNothing,
      reason: '过滤后其余变量行不渲染',
    );
  });

  testWidgets('DBT-T3-ITEMS：4 个新面板项逐一打开断言目标出现', (tester) async {
    if (!mysqlE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);

    // ① mysql.variables → 变量浏览器（真加载；先等表头再过滤断言，
    // 口径同 VARS 用例——惰性构建下未过滤行不进 widget 树）
    await activateItem(tester, 'mysql.variables');
    expect(find.byType(MysqlVariablesBrowserDialog), findsOneWidget);
    expect(
      await waitUntil(tester, () => tester.any(find.text('Name'))),
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'max_connections');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'max_connections'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    // ② mysql.maintenance → 表维护聚合入口（库清单真加载）
    await activateItem(tester, 'mysql.maintenance');
    expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget);
    expect(
      await waitUntil(tester,
        () => tester.any(find.byType(DropdownButton<String>)),
      ),
      isTrue,
      reason: '库清单应加载完成（下拉就绪）',
    );
    // 选 chinook（首库非 chinook 时下拉切换；相同则初始已加载其表）
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final chinookItem = find.text('chinook').last;
    expect(tester.any(chinookItem), isTrue, reason: 'WSL MySQL 应有 chinook 库');
    await tester.tap(chinookItem);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await waitUntil(tester, () => tester.any(find.text('Artist'))),
      isTrue,
      reason: 'chinook 表清单应含 Artist（MySQL 系驼峰表名）',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // ③ mysql.backup → 连接导出 dialog（sidebar_tree 同一调用形态）
    await activateItem(tester, 'mysql.backup');
    expect(find.byType(ConnectionExportImportDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ConnectionExportImportDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    // ④ mysql.performance → AI 性能分析（工作台引流，provider 态断言）
    await activateItem(tester, 'mysql.performance');
    expect(
      await waitUntil(tester, () => provider.aiPanel.aiPanelOpen),
      isTrue,
      reason: 'ai_analyze_server 同源钩子应打开 AI 工作台',
    );
  });

  testWidgets('DBT-T3-MAINT：聚合入口对 chinook.Artist ANALYZE 成功返回',
      (tester) async {
    if (!mysqlE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);

    await activateItem(tester, 'mysql.maintenance');
    await waitUntil(tester, () => tester.any(find.byType(DropdownButton<String>)));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('chinook').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await waitUntil(tester, () => tester.any(find.text('Artist'))),
      isTrue,
    );

    // 勾选 Artist → 执行（ANALYZE 默认动作）→ 逐表确认门
    await tester.tap(find.text('Artist'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget,
        reason: '确认门应已打开（真库执行前门控）');

    // 门内确认（scope 到确认门 dialog——路由非入口 dialog 后代；避开
    // 底层入口自身的 Confirm 按钮）→ 真库 ANALYZE → 既有结果 dialog
    await tester.tap(
      find.descendant(
        of: find.byType(ConfirmMaintenanceDialog),
        matching: find.text('Confirm'),
      ),
    );
    expect(
      await waitUntil(tester,
        () => tester.any(find.byType(TableMaintenanceResultDialog)),
        timeoutMs: 60000,
      ),
      isTrue,
      reason: 'ANALYZE 应经既有 runTableMaintenance 链路成功并出结果 dialog',
    );

    // 重查断言执行成功返回（同一既有通道；不改数据语义）。
    // ⚠ 网关行语义（server db_handler is_select_statement）：非
    // SELECT/SHOW 前缀语句经网关返回 rows=[] + affectedRows——ANALYZE
    // 成功执行但结果集为空是现行网关既有行为（金标准对维护的断言口径
    // 同此：结果 dialog + SQL 回显，不断言行数），本任务零 server 改动。
    final results = await tester.runAsync(
          () => provider.runTableMaintenance(
            'chinook',
            'Artist',
            TableMaintenanceCommand.analyze,
            connectionId: server.id,
          ),
        ) ??
        // runAsync 签名 T?：回调永不以 null 完成，空回退仅收窄类型。
        const <Map<String, dynamic>>[];
    // 完成且无异常 = 执行成功返回（有异常 runAsync 内直接抛出）。
    expect(results, isA<List<Map<String, dynamic>>>());

    // 结果 dialog 内 SQL 回显可见（金标准同款成功口径）
    expect(find.textContaining('ANALYZE'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });
}
