// ============================================================================
// DBT-T4 · PostgreSQL 能力面板 E2E（W-04 真库验证）
//
// 覆盖（任务书 T4 真库验证节，引擎 = WSL PostgreSQL 17，连接信息唯一来源
// test_db_local_wsl.txt，凭据经 DBMASTER_PG_* dart-define 注入）：
//   ① 扩展列表真数据：pg_extension 查询非空（WSL PG 自带基础扩展）；
//      pg.extension 面板项 → 2b.1 R3 一次性展开信号（provider 态断言）；
//   ② 新面板项逐一打开断言——pg.extension / pg.maintenance 必断言；
//      pg.vector 按 vector 扩展实际安装态分支断言（已装 → 详情对话框
//      内嵌 PgVectorPanel；未装 → 无既有落点静默返回，不崩溃）；
//      （pg.queryPlan 主代理裁定暂缓，本批无该项）；
//   ③ 表维护聚合：对 chinook 库 artist 表（PG 小写表名）ANALYZE（逐表
//      确认门 → 既有 runTableMaintenance 链路）→ 结果 dialog → 重查断言
//      执行成功返回。
//
// 前置：DBMASTER_SERVER_BIN 指向 dbmaster-server.exe（embedded 网关，
// 无二进制时以可 grep 的 PG_E2E_SKIP 整组跳过，FR-011 无假绿纪律）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/table_maintenance_command.dart';
import 'package:dbmaster/organisms/connection/pg_extension_panel.dart';
import 'package:dbmaster/organisms/dialogs/confirm_maintenance_dialog.dart';
import 'package:dbmaster/organisms/dialogs/postgresql_table_maintenance_entry_dialog.dart';
import 'package:dbmaster/organisms/dialogs/table_maintenance_result_dialog.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/postgresql_sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

import 'config/postgresql_test_config.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

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

/// 能力面板驱动壳：装配（core + postgresql 插件 × CapabilityTable 门控）
/// 后把每个可见项渲染为 ListTile，onTap = item.onActivate（与真实菜单
/// 同一激活闭包；菜单本体渲染属 T2 框架，非本 E2E 断言面）。
class _CapabilityPanelHarness extends StatelessWidget {
  const _CapabilityPanelHarness();

  @override
  Widget build(BuildContext context) {
    final groups = assembleCapabilityMenu(
      context: context,
      type: DatabaseType.postgresql,
      port: _E2ECapabilityPort(),
      plugins: const [CoreSidebarPlugin(), PostgresqlSidebarPlugin()],
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
  // T29：PG 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  bool pgE2EGatewayReady = false;
  setUpAll(() async {
    pgE2EGatewayReady = await ensureEmbeddedServerForPgE2E();
    if (pgE2EGatewayReady && !PostgreSQLTestConfig.isConfigured) {
      // ignore: avoid_print
      print('PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      pgE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t4-e2e-pg',
      type: DatabaseType.postgresql,
      name: 'DBT T4 E2E PostgreSQL',
      host: PostgreSQLTestConfig.host,
      port: PostgreSQLTestConfig.port,
      username: PostgreSQLTestConfig.username,
      password: PostgreSQLTestConfig.password,
      // PG 必带初始库（open_pg 按库开池；跨库语句经 database 参数路由）。
      database: PostgreSQLTestConfig.database,
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
    expect(connected, isTrue, reason: '真库连接失败（${PostgreSQLTestConfig.host}）');
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

  /// 库下拉切到 chinook 并等表清单含 artist（PG 小写表名）。
  Future<void> selectChinookArtist(WidgetTester tester) async {
    expect(
      await waitUntil(
        tester,
        () => tester.any(find.byType(DropdownButton<String>)),
      ),
      isTrue,
      reason: '库清单应加载完成（下拉就绪）',
    );
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final chinookItem = find.text('chinook').last;
    expect(tester.any(chinookItem), isTrue, reason: 'WSL PG 应有 chinook 库');
    await tester.tap(chinookItem);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      await waitUntil(tester, () => tester.any(find.text('artist'))),
      isTrue,
      reason: 'chinook 表清单应含 artist（PG 小写表名）',
    );
  }

  testWidgets('DBT-T4-EXT：扩展列表真数据 + pg.extension 展开信号', (tester) async {
    if (!pgE2EGatewayReady) return;
    await connectReal(tester);

    // 数据面：pg_extension 真数据（plpgsql 为 PG 自带基础扩展，恒在）。
    final rows = await tester.runAsync(
          () => provider.executeQuery(
            'SELECT extname FROM pg_extension ORDER BY extname',
            connectionId: server.id,
          ),
        ) ??
        // runAsync 签名 T?：回调永不以 null 完成，空回退仅收窄类型。
        const <Map<String, dynamic>>[];
    expect(rows, isNotEmpty, reason: 'pg_extension 应非空（基础扩展）');

    // UI 面：pg.extension 面板项 → 一次性展开信号（树节点同源打开）。
    await pumpHarness(tester);
    await activateItem(tester, 'pg.extension');
    expect(
      provider.sidebar.sidebarExpandRequest,
      '${server.id}:extensions',
      reason: '应发起 Extensions 节点展开请求（2b.1 R3 信号通道）',
    );
  });

  testWidgets('DBT-T4-ITEMS：新面板项逐一打开断言目标出现', (tester) async {
    if (!pgE2EGatewayReady) return;
    await connectReal(tester);

    // vector 安装态决定 pg.vector 断言分支（未装 = 无既有落点静默返回）。
    final vectorRows = await tester.runAsync(
          () => provider.executeQuery(
            "SELECT 1 FROM pg_extension WHERE extname = 'vector'",
            connectionId: server.id,
          ),
        ) ??
        const <Map<String, dynamic>>[];
    final vectorInstalled = vectorRows.isNotEmpty;

    await pumpHarness(tester);

    // ① pg.extension → 展开信号（口径同 EXT 用例）
    await activateItem(tester, 'pg.extension');
    expect(provider.sidebar.sidebarExpandRequest, '${server.id}:extensions');

    // ② pg.vector → 按安装态分支：已装 → 详情对话框（内嵌 PgVectorPanel）；
    //    未装 → 无既有落点，静默返回不崩溃。
    await activateItem(tester, 'pg.vector');
    await tester.pump(const Duration(milliseconds: 500));
    if (vectorInstalled) {
      expect(
        await waitUntil(tester, () => tester.any(find.byType(PgExtensionDetailDialog))),
        isTrue,
        reason: 'vector 已装时应打开扩展详情（PgVectorPanel 落点）',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
    } else {
      expect(find.byType(PgExtensionDetailDialog), findsNothing,
          reason: 'vector 未装时无既有落点，应静默返回（AppLogger 记录）');
    }

    // ③ pg.maintenance → 表维护聚合入口（库清单真加载 + chinook/artist）
    await activateItem(tester, 'pg.maintenance');
    expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsOneWidget);
    await selectChinookArtist(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('DBT-T4-MAINT：聚合入口对 chinook.artist ANALYZE 成功返回',
      (tester) async {
    if (!pgE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);

    await activateItem(tester, 'pg.maintenance');
    await selectChinookArtist(tester);

    // 勾选 artist → 执行（ANALYZE 默认动作）→ 逐表确认门
    await tester.tap(find.text('artist'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsOneWidget,
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
      await waitUntil(
        tester,
        () => tester.any(find.byType(TableMaintenanceResultDialog)),
        timeoutMs: 60000,
      ),
      isTrue,
      reason: 'ANALYZE 应经既有 runTableMaintenance 链路成功并出结果 dialog',
    );

    // 重查断言执行成功返回（同一既有通道；不改数据语义）。
    // ⚠ 网关行语义：非 SELECT 前缀语句经网关返回 rows=[]——ANALYZE 成功
    // 执行但结果集为空是现行网关既有行为（金标准对维护的断言口径同此：
    // 结果 dialog + SQL 回显，不断言行数），本任务零 server 改动。
    final results = await tester.runAsync(
          () => provider.runTableMaintenance(
            'chinook',
            'artist',
            TableMaintenanceCommand.analyze,
            connectionId: server.id,
          ),
        ) ??
        // runAsync 签名 T?：回调永不以 null 完成，空回退仅收窄类型。
        const <Map<String, dynamic>>[];
    // 完成且无异常 = 执行成功返回（有异常 runAsync 内直接抛出）。
    expect(results, isA<List<Map<String, dynamic>>>());

    // 结果 dialog 内 SQL 回显可见（PG 分支 buildSql：ANALYZE "artist"）
    expect(find.textContaining('ANALYZE'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
  });
}
