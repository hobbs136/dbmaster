// ============================================================================
// DBT-T12 · MongoDB Explain 计划面板 E2E（W-13b 真库验证）
//
// 覆盖（派单前置核实结论两态，引擎 = WSL MongoDB 8.0（admin 认证），连接
// 信息唯一来源 test_db_local_wsl.txt，凭据经 DBMASTER_MONGO_* dart-define
// 注入；fixture 库 = dbmaster_test 只读走查，explain 命令零写语义）：
//   ① find（有索引→IXSCAN 摘要）：_id 等值查询 → 摘要 stage/使用索引
//      真数据（indexName = _id_），完整 JSON 节默认折叠；
//   ② aggregate（SBE unknown → JSON 为准）：SBE 包装 winningPlan → 摘要
//      stage = unknown，完整 JSON 节默认展开（stage=unknown 置顶展开，
//      T9 核实结论①的 dialog 侧处置）；
//   ③ 非 find/aggregate 语句（insertOne）→ parser 不可解释提示行按错误
//      态呈现（核实结论②；explain 通道零写语义，insertOne 不被执行）。
//
// 前置：Mongo 网关壳（ADR-0006）硬依赖 dbmaster server 会话——
// DBMASTER_SERVER_BIN 指向 dbmaster-server.exe；无二进制或未注入凭据时以
// 可 grep 的 MONGO_E2E_SKIP 整组跳过（FR-011 无假绿纪律）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mongodb_sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

/// dbmaster_test fixture 库（任务书 T7 真库验证节：11 集合 100,160 docs）。
const String _fixtureDb = 'dbmaster_test';

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

/// 能力面板驱动壳：装配（core + mongo 插件 × CapabilityTable 门控）后把
/// 每个可见项渲染为 ListTile，onTap = item.onActivate（与真实菜单同一
/// 激活闭包；菜单本体渲染属 T2 框架，非本 E2E 断言面）。
class _CapabilityPanelHarness extends StatelessWidget {
  const _CapabilityPanelHarness();

  @override
  Widget build(BuildContext context) {
    final groups = assembleCapabilityMenu(
      context: context,
      type: DatabaseType.mongodb,
      port: _E2ECapabilityPort(),
      plugins: const [CoreSidebarPlugin(), MongodbSidebarPlugin()],
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
  // Mongo 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  bool mongoE2EGatewayReady = false;
  setUpAll(() async {
    mongoE2EGatewayReady = await ensureEmbeddedServerForMongoE2E();
    if (mongoE2EGatewayReady && !MongoDBTestConfig.available) {
      // ignore: avoid_print
      print('MONGO_E2E_SKIP: DBMASTER_MONGO_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      mongoE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t12-e2e-mongo',
      type: DatabaseType.mongodb,
      name: 'DBT T12 E2E MongoDB',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );
    // 面板闭包族（loadDatabaseInfo / dbService.getExplainPlan）经 saved
    // 连接解析——e2e server 必须先入 saved 表（T7 同前置）。
    provider.connection.addSavedServerForTest(server);
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  Future<void> connectReal(WidgetTester tester) async {
    final connected =
        await tester.runAsync(() => provider.connection.connectToServer(server));
    expect(connected, isTrue, reason: '真库连接失败（${MongoDBTestConfig.host}）');
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

  /// 轮询等待条件成立（runAsync 放行真实 I/O；explain 真库往返不走
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

  /// 打开面板项对应 dialog 的下拉并选中 [option]（菜单项等待真库列表加载
  /// 完成；下拉展开态跨轮询帧保持）。
  Future<void> selectDropdownOption(
    WidgetTester tester,
    String option, {
    int dropdownIndex = 0,
  }) async {
    await tester.tap(find.byType(DropdownButton<String>).at(dropdownIndex));
    await tester.pump();
    final appeared = await waitUntil(
      tester,
      () => tester.any(find.text(option).last),
    );
    expect(appeared, isTrue, reason: '下拉选项未出现：$option');
    await tester.tap(find.text(option).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// fixture 库首个集合名（真实 listCollections，幂等只读；与面板/树同源
  /// loadDatabaseInfo 路径）。
  Future<String> firstFixtureCollection() async {
    final info = await provider.loadDatabaseInfo(server.id, _fixtureDb);
    final collections =
        info?.tables.map((t) => t.name).toList() ?? const <String>[];
    expect(collections, isNotEmpty, reason: '$_fixtureDb 库应含真实集合');
    return collections.first;
  }

  /// 打开 Explain 面板并选齐 fixture 库 + 集合（查询框被预填 find 模板）。
  Future<String> openExplainOnFixture(
    WidgetTester tester,
  ) async {
    final collection = await firstFixtureCollection();
    await pumpHarness(tester);
    await activateItem(tester, 'mongo.explain');
    expect(
      await waitUntil(tester, () => tester.any(find.text('Explain Plan'))),
      isTrue,
    );
    await selectDropdownOption(tester, _fixtureDb);
    await selectDropdownOption(tester, collection, dropdownIndex: 1);
    // 预填模板断言（任务书锁定交互：选集合后预填 db.<coll>.find 模板）。
    expect(find.textContaining('db.$collection.find('), findsOneWidget);
    return collection;
  }

  /// 填入查询并点运行（异步往返各测试自选条件等待——摘要态等
  /// winningPlan.stage，提示态等提示文案）。
  Future<void> runExplain(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Explain Query'));
    await tester.pump();
  }

  /// 填入查询并点运行，等摘要首行（winningPlan.stage）渲染。
  Future<void> runExplainAndWait(
    WidgetTester tester,
    String query,
  ) async {
    await runExplain(tester, query);
    final rendered = await waitUntil(
      tester,
      () => tester.any(find.textContaining('winningPlan.stage')),
      timeoutMs: 60000,
    );
    expect(rendered, isTrue, reason: 'explain 摘要应渲染（真库往返）');
  }

  testWidgets('DBT-T12-FIND：find（有索引）→ IXSCAN 摘要 + JSON 默认折叠', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    final collection = await openExplainOnFixture(tester);

    // _id 等值 → 既有 _id_ 索引（classic 引擎 FETCH→IXSCAN，indexName
    // = _id_；SBE 不包装简单 find——与 aggregate 对照态）。
    await runExplainAndWait(
      tester,
      'db.$collection.find({ _id: ObjectId("000000000000000000000000") })',
    );
    expect(find.textContaining('_id_'), findsWidgets,
        reason: '使用索引行应显示 _id_（IXSCAN 摘要）');
    // JSON 节默认折叠（stage 已知，不触发展开条件）。
    expect(find.byKey(const Key('explain_full_json')), findsNothing);
    expect(find.byKey(const Key('explain_json_toggle')), findsOneWidget);
  });

  testWidgets('DBT-T12-AGG：aggregate（SBE）→ stage unknown + JSON 默认展开', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    final collection = await openExplainOnFixture(tester);

    // 聚合模板（与聚合 shell 入口同一 MongoCollectionDragData.aggregateStatement
    // 生产模板）：Mongo 8 SBE 包装 winningPlan → adapter 摘要 stage 显示
    // unknown → JSON 节默认展开（完整计划为准，核实结论①）。
    final template = MongoCollectionDragData(
      collectionName: collection,
      databaseName: _fixtureDb,
      connectionId: server.id,
    ).aggregateStatement;
    await runExplainAndWait(tester, template);

    expect(find.text('unknown'), findsOneWidget,
        reason: 'SBE 包装下摘要 stage 应为 unknown');
    expect(find.byKey(const Key('explain_full_json')), findsOneWidget,
        reason: 'stage=unknown 时完整 JSON 应默认展开');
  });

  testWidgets('DBT-T12-UNPARSABLE：非 find/aggregate 语句 → 提示行错误态', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    final collection = await openExplainOnFixture(tester);

    // insertOne 不可解释：parser 返回 null → adapter 单值提示行 → 面板按
    // 错误态呈现（核实结论②）。explain 通道零写语义——该语句不会被执行。
    await runExplain(tester, 'db.$collection.insertOne({ a: 1 })');
    final noticed = await waitUntil(
      tester,
      () => tester.any(find.textContaining('无法解析')),
      timeoutMs: 60000,
    );
    expect(noticed, isTrue, reason: '不可解释提示行应按错误态渲染（adapter 既有文案）');
    expect(find.byKey(const Key('explain_json_toggle')), findsNothing);
  });
}
