// ============================================================================
// DBT-T7 · MongoDB 能力面板 E2E（W-07 真库验证）
//
// 覆盖（任务书 T7 真库验证节，引擎 = WSL MongoDB 8.0（admin 认证），连接
// 信息唯一来源 test_db_local_wsl.txt，凭据经 DBMASTER_MONGO_* dart-define
// 注入；fixture 库 = dbmaster_test 只读走查，零写入零 pollution）：
//   ① 5 个新面板项逐一打开断言目标出现（dialog 标题）；
//   ② Schema 视图对 dbmaster_test 真集合渲染（集合名 + 推断 schema 字段
//      非空——WorkbenchMongoSchemaView 真数据三态中的内容态）；
//   ③ 验证规则列表真数据（集合清单实渲染；无规则集合显示空态为合法）；
//   ④ 聚合 shell 路由：选库选集合 → 预填 aggregate 模板的新查询 tab
//      （零自动执行）；索引建议面板对真集合真索引出报告；副本集/分片面
//      板对单机环境出真实状态（非副本集 / 非分片集群）。
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
import 'package:dbmaster/organisms/mongodb/schema_view/schema_nested_expander.dart';
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
      id: 'dbt-t7-e2e-mongo',
      type: DatabaseType.mongodb,
      name: 'DBT T7 E2E MongoDB',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );
    // mongo facade 族（loadMongoDBSchema / getMongoCollectionOptions /
    // loadMongoDB*Status）经 savedConnections 解析连接——e2e server 必须
    // 先入 saved 表（connectToServer 本身不登记；生产路径连接恒来自
    // saved 列表，此处仅等价还原生产前置）。
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

  /// 打开面板项对应 dialog 的数据库下拉并选中 [database]（菜单项等待真库
  /// 库列表加载完成；下拉展开态跨轮询帧保持）。
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

  /// fixture 库首个集合名（真实 listCollections，幂等只读）。集合清单走
  /// loadDatabaseInfo（与面板/树同源；mongo getTables 只看当前库上下文，
  /// 该路径内部先 useDatabase）。
  Future<String> firstFixtureCollection() async {
    final info = await provider.loadDatabaseInfo(server.id, _fixtureDb);
    final collections =
        info?.tables.map((t) => t.name).toList() ?? const <String>[];
    expect(collections, isNotEmpty, reason: '$_fixtureDb 库应含真实集合');
    return collections.first;
  }

  testWidgets('DBT-T7-ITEMS：5 个新面板项逐一打开断言目标出现', (tester) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);

    const expectations = <String, String>{
      'mongo.validation': 'Validation Rules',
      'mongo.aggregate': 'Aggregation Shell',
      'mongo.indexAdvice': 'Index Advice',
      'mongo.replication': 'Replication',
      'mongo.schemaView': 'Schema View',
    };
    for (final entry in expectations.entries) {
      await activateItem(tester, entry.key);
      expect(
        await waitUntil(tester, () => tester.any(find.text(entry.value))),
        isTrue,
        reason: '${entry.key} 打开后应出现「${entry.value}」',
      );
      // 关闭 dialog（aggregate 用 Cancel，其余用 Close），恢复 harness。
      final closer = find.widgetWithText(TextButton, entry.key == 'mongo.aggregate' ? 'Cancel' : 'Close');
      expect(closer, findsOneWidget, reason: entry.key);
      await tester.tap(closer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  });

  testWidgets('DBT-T7-SCHEMA：Schema 视图对 dbmaster_test 真集合渲染字段', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);

    // fixture 前置：任务书口径 dbmaster_test（11 集合）存在于 WSL 矩阵。
    final databases = await tester.runAsync(
      () => provider.dbService.getDatabases(connectionId: server.id),
    );
    expect(
      databases,
      contains(_fixtureDb),
      reason: 'fixture 库 $_fixtureDb 不在真库（任务书 T7 真库验证节）',
    );
    final collection = await firstFixtureCollection();

    await pumpHarness(tester);
    await activateItem(tester, 'mongo.schemaView');
    expect(
      await waitUntil(tester, () => tester.any(find.text('Schema View'))),
      isTrue,
    );

    await selectDropdownOption(tester, _fixtureDb);
    await selectDropdownOption(tester, collection, dropdownIndex: 1);

    // 内容态断言：集合名头行 + 推断 schema 字段非空（SchemaNestedExpander
    // 行渲染；加载/空/失败三态中的内容态 = 真数据）。
    final rendered = await waitUntil(
      tester,
      () => tester.any(find.byType(SchemaNestedExpander)),
      timeoutMs: 60000,
    );
    expect(rendered, isTrue, reason: 'Schema 视图应渲染字段行（真集合）');
    expect(find.text(collection), findsWidgets, reason: '集合名头行');
  });

  testWidgets('DBT-T7-VALIDATION：验证规则列表真数据（无规则库空态合法）', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    final collection = await firstFixtureCollection();

    await pumpHarness(tester);
    await activateItem(tester, 'mongo.validation');
    expect(
      await waitUntil(tester, () => tester.any(find.text('Validation Rules'))),
      isTrue,
    );

    await selectDropdownOption(tester, _fixtureDb);

    // 列表真数据：真实集合名渲染为可点行。
    expect(
      await waitUntil(tester, () => tester.any(find.text(collection))),
      isTrue,
      reason: '集合清单应含真库集合 $collection',
    );

    // 点选集合 → 规则详情：无 validator = 空态文案（合法）；有 = 规则渲染。
    await tester.tap(find.text(collection));
    await tester.pump();
    final detailShown = await waitUntil(
      tester,
      () =>
          tester.any(find.textContaining('no validation rules')) ||
          tester.any(find.textContaining('validationLevel')) ||
          tester.any(find.textContaining(r'$jsonSchema')),
      timeoutMs: 30000,
    );
    expect(detailShown, isTrue, reason: '验证规则详情应出（空态或规则体）');
  });

  testWidgets('DBT-T7-AGGREGATE：聚合 shell 路由打开预填模板 tab（零自动执行）', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    final collection = await firstFixtureCollection();
    final tabsBefore = provider.tab.tabs.length;

    await pumpHarness(tester);
    await activateItem(tester, 'mongo.aggregate');
    expect(
      await waitUntil(tester, () => tester.any(find.text('Aggregation Shell'))),
      isTrue,
    );

    await selectDropdownOption(tester, _fixtureDb);
    await selectDropdownOption(tester, collection, dropdownIndex: 1);

    final confirm = find.widgetWithText(ElevatedButton, 'Confirm');
    expect(
      await waitUntil(
        tester,
        () => tester.any(confirm) &&
            tester.widget<ElevatedButton>(confirm).onPressed != null,
      ),
      isTrue,
      reason: '选齐库+集合后 Confirm 应可用',
    );
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.tab.tabs.length, tabsBefore + 1, reason: '新开一个查询 tab');
    final tab = provider.tab.activeTab;
    expect(tab, isNotNull, reason: '新 tab 应为活动 tab');
    expect(tab!.sql, contains('.$collection.aggregate('), reason: '预填聚合模板');
    expect(tab.databaseName, _fixtureDb);
    expect(tab.connectionId, server.id);
  });

  testWidgets('DBT-T7-INDEX：索引建议面板对真集合真索引出报告', (tester) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    final collection = await firstFixtureCollection();
    // 索引对照与 ai_panel 索引建议同语义：按连接当前库上下文取既有索引
    //（getTableIndexes 对 mongo 看当前库）——先切到 fixture 库再分析。
    await tester.runAsync(
      () => provider.dbService.useDatabase(_fixtureDb, connectionId: server.id),
    );

    await pumpHarness(tester);
    await activateItem(tester, 'mongo.indexAdvice');
    expect(
      await waitUntil(tester, () => tester.any(find.text('Index Advice'))),
      isTrue,
    );

    // _id 等值查询 → 既有 _id_ 索引覆盖 → 建议报告渲染（报告为既有服务
    // generateReport 产物，含固定标题行）。
    await tester.enterText(
      find.byType(TextField),
      'db.$collection.find({ _id: ObjectId("000000000000000000000000") })',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Index Suggestion'));
    await tester.pump();
    final reported = await waitUntil(
      tester,
      () => tester.any(find.textContaining('Mongo')),
      timeoutMs: 30000,
    );
    expect(reported, isTrue, reason: '索引建议报告应渲染（真索引对照）');
  });

  testWidgets('DBT-T7-REPL：副本集/分片面板单机真实状态', (tester) async {
    if (!mongoE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);
    await activateItem(tester, 'mongo.replication');

    // WSL 单机 mongod：facade 真实返回「非副本集 / 非分片集群」哨兵状态。
    final rendered = await waitUntil(
      tester,
      () =>
          tester.any(find.text('Not a replica set')) &&
          tester.any(find.text('Not a sharded cluster')),
      timeoutMs: 30000,
    );
    expect(rendered, isTrue, reason: '单机环境应显示真实状态（非副本集/非分片）');
  });
}
