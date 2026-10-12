// ============================================================================
// DBT-T10 · MongoDB currentOp / killOp E2E（W-11 真库验证）
//
// 覆盖（任务书 T10 真库验证节，引擎 = WSL MongoDB 8.0.32（admin 认证），
// 连接信息唯一来源 test_db_local_wsl.txt，口令经 DBMASTER_MONGO_PASSWORD
// dart-define 注入；fixture = 自建自删测试库——只触自建测试集合，零共享库
// 写入）：
//   ① 面板项打开 → currentOp 列表真数据加载（列表或空态收敛，无失败态）；
//   ② 优先路径（实杀链路）：聚合 `$function` 忙等制造可控长操作（Mongo 8.0
//      已移除 eval，server 端 forbidden 面也禁 eval——两侧都不用）→ 面板
//      出现该 op 行 → 行内 Kill → 确认门（opid 明示）→ 确认 → snackbar
//      killed + 复查刷新行消失 + 背景聚合 future 以 Interrupted 终止；
//   ③ fallback 断言：killOp 对已消失（bogus）opid → ok:1 fire-and-forget
//      幂等（无崩溃、无错误）。
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
import 'package:dbmaster/services/adapters/mongodb_gateway_adapter.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

/// 忙等秒数：足够完成「面板出现 → 确认 → kill」全链路，又不至于在断言
/// 失败时长期占住 mongod（tearDown 兜底杀连接 + 删库）。
const int _busyWaitSeconds = 30;

/// `$function` 忙等聚合管道（自建测试集合上的长操作制造器）。
List<Map<String, dynamic>> _busyWaitPipeline() => [
  {
    r'$addFields': {
      '_busyWait': {
        r'$function': {
          'body':
              'function() { const t = Date.now(); '
              'while (Date.now() - t < ${_busyWaitSeconds * 1000}) {} '
              'return 1; }',
          'args': [],
          'lang': 'js',
        },
      },
    },
  },
];

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

/// 能力面板驱动壳（与 T7 e2e 同款）：装配后把可见项渲染为 ListTile，
/// onTap = item.onActivate（与真实菜单同一激活闭包）。
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
    return Scaffold(
      body: ListView(
        children: [
          for (final group in groups)
            for (final item in group.items)
              ListTile(
                key: Key('${group.id}/${item.item.id}'),
                title: Text('${group.id}/${item.item.id}'),
                onTap: item.item.onActivate,
              ),
        ],
      ),
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
  late String testDb;
  MongoDBAdapter? adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDb = MongoDBTestConfig.generateTestDatabaseName();
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t10-e2e-mongo',
      type: DatabaseType.mongodb,
      name: 'DBT T10 E2E MongoDB',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );
    // 面板闭包经 savedConnections 解析连接 → e2e server 先入 saved 表
    //（T7 e2e 同款生产前置还原）。
    provider.connection.addSavedServerForTest(server);
  });

  tearDown(() async {
    try {
      if (adapter?.isConnected == true) {
        await adapter!.dropDatabase(testDb);
      }
    } catch (_) {}
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  Future<MongoDBAdapter> connectReal(WidgetTester tester) async {
    final connected = await tester.runAsync(
      () => provider.connection.connectToServer(server),
    );
    expect(connected, isTrue, reason: '真库连接失败（${MongoDBTestConfig.host}）');
    // getAdapter 为同步检索（连接后 adapter 已在位，无需真实时钟等待）。
    final raw = provider.dbService.getAdapter(server.id);
    expect(raw, isA<MongoDBAdapter>(), reason: '应取得 MongoDB 网关壳 adapter');
    return raw as MongoDBAdapter;
  }

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const _CapabilityPanelHarness(),
        ),
      ),
    );
    await tester.pump();
  }

  /// 打开 currentOp 面板（面板项 → dialog）。
  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('advanced/mongo.currentOp')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 轮询等待 UI 条件成立（runAsync 放行真实 I/O；面板内部加载在真实时钟
  /// 下完成——T7 e2e 同款）。
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

  /// 真实时钟轮询（非 UI 条件——直接 adapter 取数）。[poll] 返回 false 继续
  /// 轮询，true 停止。
  Future<bool> pollReal(
    WidgetTester tester,
    Future<bool> Function() poll, {
    int timeoutMs = 20000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (await tester.runAsync(poll) == true) return true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }
    return false;
  }

  /// 复查刷新直到目标 ns 行消失（kill 后 mongod 摘除 inprog 条目有毫秒级
  /// 窗口，一次刷新可能仍见僵尸行——循环内手动点 Refresh）。
  Future<bool> refreshUntilGone(WidgetTester tester, String ns) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (!tester.any(find.text(ns))) return true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    return !tester.any(find.text(ns));
  }

  testWidgets('DBT-T10-PANEL：面板项打开 → currentOp 列表真数据加载', (tester) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);
    await pumpHarness(tester);
    await openPanel(tester);

    // 真数据收敛：列表或空态（单机 idle 时 inprog 可为空——空态本身即
    //「通道真数据」证据）；失败态 = 通道问题，不许出现。
    final settled = await waitUntil(
      tester,
      () =>
          tester.any(find.byType(DataTable)) ||
          tester.any(find.text('No active operations')),
      timeoutMs: 30000,
    );
    expect(settled, isTrue, reason: 'currentOp 面板应收敛到列表/空态（非失败态）');

    await tester.tap(find.text('Close'));
    await tester.pump();
  });

  testWidgets('DBT-T10-KILL：长操作 → 面板行 → 确认门 kill → 行消失 + Interrupted', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);
    const collection = 'killop_fixture';
    final ns = '$testDb.$collection';

    // fixture：自建测试库 + 集合（插入一条触发惰性建库建集合）。
    final seeded = await tester.runAsync(() async {
      await adapter!.useDatabase(testDb);
      return adapter!.insertOne(collection, {'seed': 1});
    });
    expect(seeded, isTrue, reason: 'fixture 集合创建失败');

    // 制造可控长操作（不 await；kill 后以引擎 Interrupted 终止——实杀
    // 最强断言锚点）。错误全文捕获备断言（onError 吞形态保 future 完成）。
    Object? busyError;
    final busyWait = adapter!
        .aggregate(collection, _busyWaitPipeline())
        .then<void>((_) {}, onError: (Object e) { busyError = e; });

    // 直接轮询 currentOp 直到长操作入列（比 UI 轮询更稳的锚点）。
    Object? opId;
    final opAppeared = await pollReal(
      tester,
      () async {
        final doc = await adapter!.getCurrentOp();
        final entries = doc['inprog'];
        if (entries is! List) return false;
        for (final item in entries) {
          if (item is Map && item['ns'] == ns) {
            opId = item['opid'];
            return true;
          }
        }
        return false;
      },
      timeoutMs: 20000,
    );
    expect(opAppeared, isTrue, reason: '长操作应出现在 currentOp（ns=$ns）');
    expect(opId, isNotNull, reason: '应捕获到 opid');

    // 面板路径：打开 → 目标行出现 → 行内 Kill（动作列首列；Key 含 opid——
    // DataTable 行为私有 widget 类型，经 Key 定位）。
    await pumpHarness(tester);
    await openPanel(tester);
    final rowShown = await waitUntil(tester, () => tester.any(find.text(ns)));
    expect(rowShown, isTrue, reason: '面板列表应出现长操作行（ns=$ns）');

    await tester.tap(find.byKey(Key('killop_$opId')));
    await tester.pumpAndSettle();

    // 确认门：opid 明示。
    expect(find.text('Kill operation $opId?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Kill Query').last);
    await tester.pump();

    // 结果 snackbar（fire-and-forget：ok=1 即受理文案）。
    final snackbarShown = await waitUntil(
      tester,
      () => tester.any(find.text('Operation $opId killed')),
      timeoutMs: 15000,
    );
    expect(snackbarShown, isTrue, reason: 'kill 成功回执应出现（opId=$opId）');

    // 复查刷新：目标行消失（实际终止的列表证据）。
    final gone = await refreshUntilGone(tester, ns);
    expect(gone, isTrue, reason: 'kill 后复查刷新应不再出现目标行（ns=$ns）');

    // 实杀最强证据：背景聚合以引擎 Interrupted 错误终止。
    await tester.runAsync(() => busyWait);
    expect(busyError, isNotNull, reason: '被 kill 的聚合应以错误终止');
    expect(busyError.toString(), contains('Interrupted'),
        reason: '终止错误应为引擎 Interrupted（engineCode 透传）');

    await tester.tap(find.text('Close'));
    await tester.pump();
  });

  testWidgets('DBT-T10-BOGUS：killOp 对已消失 opid = ok:1 幂等（fire-and-forget）', (
    tester,
  ) async {
    if (!mongoE2EGatewayReady) return;
    adapter = await connectReal(tester);

    // 不存在的 opid（standalone 数值形态）：Mongo 回 ok:1 无错误——「目标
    // 已消失」错误态只能由 kill 后 currentOp 复查派生（任务书边界节）。
    final resp = await tester.runAsync(() => adapter!.killOp(987654321));
    expect(resp, isNotNull, reason: 'killOp 响应文档不应为空');
    expect((resp!['ok'] as num?)?.toDouble(), 1.0,
        reason: 'bogus opid 应幂等 ok:1（fire-and-forget 语义）');
    expect(resp['info'], contains('attempting to kill'),
        reason: 'Mongo killOp 确认回执 info 字段');
  });
}
