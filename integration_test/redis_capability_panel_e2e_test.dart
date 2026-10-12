// ============================================================================
// DBT-T6 · Redis 能力面板 E2E（W-06 真库验证）
//
// 覆盖（任务书 T6 真库验证节，引擎 = WSL Redis 7（127.0.0.1:6379，
// requirepass），连接信息唯一来源 test_db_local_wsl.txt，凭据经
// DBMASTER_REDIS_* dart-define 注入，**只读断言口径**——不制造慢命令、
// 不 CONFIG SET）：
//   ① 装配清单：15 项可见（既有 12 + T6 新 2 + T20 新 1）；「更多」组
//      含且仅含 4 项；组重排后次要项不再挂 advanced；
//   ② redis.slowlog：树节点同源路由（一次性展开信号命中树内节点 key +
//      loadRedisSlowLog 既有取数路径）+ 树展开态列表结构渲染
//      （无记录空态 / 有记录 μs 行，二者皆合法）；
//   ③ redis.expiring：TTL 监控视图打开（树内 Expiring Soon 节点同源
//      复刻 dialog）+ 数据结构渲染（统计头 + 采样行）+ 关闭。
//
// 前置：T29 非 SQL 批（B4）起 Redis 走网关壳，硬依赖 dbmaster server
// 会话——DBMASTER_SERVER_BIN 指向 dbmaster-server.exe（embedded 前置，
// 与 redis_sidebar_menu_e2e 金标准同跑法）；二进制不可得时以可 grep 的
// REDIS_E2E_SKIP 整组跳过（无假绿纪律）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/redis_sidebar_plugin.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

import 'config/redis_test_config.dart';
import 'helpers/redis_gateway_e2e_helper.dart';

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

/// 能力面板驱动壳：装配（core + redis 插件 × CapabilityTable 门控）后把
/// 每个可见项渲染为 ListTile，onTap = item.onActivate（与真实菜单同一
/// 激活闭包；菜单本体渲染属 T2 框架，非本 E2E 断言面）。
class _CapabilityPanelHarness extends StatelessWidget {
  const _CapabilityPanelHarness();

  @override
  Widget build(BuildContext context) {
    final groups = assembleCapabilityMenu(
      context: context,
      type: DatabaseType.redis,
      port: _E2ECapabilityPort(),
      plugins: const [CoreSidebarPlugin(), RedisSidebarPlugin()],
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

/// 树驱动壳：注入 expandedItems 直接渲染插件 buildGlobalTree（单测同款
/// 形态），用于断言 slowlog 节点展开态的列表结构渲染。
class _TreeHarness extends StatelessWidget {
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;

  const _TreeHarness({
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
  });

  @override
  Widget build(BuildContext context) {
    final nodes = const RedisSidebarPlugin().buildGlobalTree(
      context,
      SidebarTreeContext(
        provider: provider,
        connectionId: connectionId,
        expandedItems: expandedItems,
        onToggleExpand: (_) {},
        expandedDatabases: const {},
        onToggleDatabase: (_) {},
        databases: const [],
      ),
    );
    return ListView(children: nodes);
  }
}

void main() {
  // T29 非 SQL 批次（B4）：Redis 网关壳硬依赖 dbmaster server 会话
  // （embedded 前置，D6）。二进制不可得时全组以可 grep 的 REDIS_E2E_SKIP
  // 跳过（无假绿）。
  bool redisE2EGatewayReady = false;
  setUpAll(() async {
    redisE2EGatewayReady = await ensureEmbeddedServerForRedisE2E();
    if (redisE2EGatewayReady && !RedisTestConfig.available) {
      // ignore: avoid_print
      print('REDIS_E2E_SKIP: DBMASTER_REDIS_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      redisE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    AppProvider.devBypassGates = true; // 集成测试测全功能（金标准同款）
    server = DbServer(
      id: 'dbt-t6-e2e-redis',
      type: DatabaseType.redis,
      name: 'DBT T6 E2E Redis',
      host: RedisTestConfig.host,
      port: RedisTestConfig.port,
      password: RedisTestConfig.password,
      database: RedisTestConfig.database,
    );
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  Future<void> connectReal(WidgetTester tester) async {
    await provider.connection.saveConnection(server);
    final connected = await tester.runAsync(
      () => provider.connectToServer(server),
    );
    expect(connected, isTrue, reason: '真库连接失败（${RedisTestConfig.host}）');
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

  Future<void> pumpTreeHarness(
    WidgetTester tester, {
    required Set<String> expandedItems,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: _TreeHarness(
              provider: provider,
              connectionId: server.id,
              expandedItems: expandedItems,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 轮询等待条件成立（runAsync 放行真实 I/O；面板项触发的加载不走
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

  testWidgets('DBT-T6-ITEMS：装配清单 15 项 + 「更多」组含且仅含 4 项',
      (tester) async {
    await pumpHarness(tester);

    // 可见项数 = 既有 12（core schema.diff/ai.assistant + 插件 10）+ T6 新 2
    // + T20 新 1（redis.backup，advanced 组 expiring 之后）= 15。
    const expectedKeys = [
      'keyspace/redis.key.new',
      'advanced/schema.diff',
      'advanced/ai.assistant',
      'advanced/redis.cli',
      'advanced/redis.pubsub',
      'advanced/redis.memory',
      'advanced/redis.acl',
      'advanced/redis.config',
      'advanced/redis.slowlog',
      'advanced/redis.expiring',
      'advanced/redis.backup',
      'more/redis.lua',
      'more/redis.pipeline',
      'more/redis.transaction',
      'more/redis.keyspace.notifications',
    ];
    for (final key in expectedKeys) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: '缺面板项 $key');
    }
    expect(find.byType(ListTile), findsNWidgets(15));

    // 组重排：次要 4 项不再挂 advanced（仅组归属调整，项 id 不变）。
    expect(find.byKey(Key('advanced/redis.lua')), findsNothing);
    expect(find.byKey(Key('advanced/redis.pipeline')), findsNothing);
    expect(find.byKey(Key('advanced/redis.transaction')), findsNothing);
    expect(find.byKey(Key('advanced/redis.keyspace.notifications')),
        findsNothing);
  });

  testWidgets('DBT-T6-SLOWLOG：树节点同源路由 + 展开态列表结构渲染',
      (tester) async {
    if (!redisE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);

    await activateItem(tester, 'redis.slowlog');

    // 路由面：一次性展开信号命中树内 Slow Log 节点 key（消费方在宿主
    // SidebarWidget——harness 未挂载，信号留存可断言）。
    expect(provider.sidebar.sidebarExpandRequest, '${server.id}:redis_slowlog');
    // 数据面：树节点 onTap 同款取数（SLOWLOG GET 只读既有通道）。
    expect(
      await waitUntil(tester, () => provider.getRedisSlowLog(server.id) != null),
      isTrue,
      reason: 'loadRedisSlowLog 应经既有通道完成加载',
    );

    // UI 面：树内 Slow Log 节点展开态结构渲染——空记录空态（'No slow
    // queries'）或有记录 μs 行，二者皆合法（只读口径，不制造慢命令）。
    await pumpTreeHarness(
      tester,
      expandedItems: {'${server.id}:redis_slowlog'},
    );
    expect(
      await waitUntil(
        tester,
        () =>
            tester.any(find.text('No slow queries')) ||
            tester.any(find.textContaining('μs')),
      ),
      isTrue,
      reason: 'slowlog 列表结构应渲染（空态或记录行）',
    );
  });

  testWidgets('DBT-T6-EXPIRING：TTL 监控视图打开 + 数据结构渲染 + 关闭',
      (tester) async {
    if (!redisE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);

    await activateItem(tester, 'redis.expiring');

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Expiring Soon'), findsOneWidget);
    // 数据结构渲染（树节点同源三段中的统计头 + 采样行；db0 空库时另有
    // 空态行，同样合法）。加载完成信号 = 'Sampled' 行出现（仅数据就绪
    // 后渲染，非加载态）。
    expect(
      await waitUntil(tester, () => tester.any(find.textContaining('Sampled'))),
      isTrue,
      reason: 'expiring 视图数据结构应渲染（统计头 + 采样行）',
    );
    expect(find.textContaining('Keys '), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
