// ============================================================================
// DBT-T20 · Redis 备份与持久化 E2E（W-17 真库验证）
//
// 覆盖（任务书 T20 真库验证节，引擎 = WSL Redis 7（127.0.0.1:6379，
// requirepass），连接信息唯一来源 test_db_local_wsl.txt，凭据经
// DBMASTER_REDIS_* dart-define 注入；**只触本测试实例**）：
//   ① 状态区真数据：INFO persistence 非空 + LASTSAVE 时间合理；
//   ② BGSAVE 真触发：SET 测试 key 制造 changes>0 → 确认门（明示目标实例
//      + fork 影响说明）→ 执行成功 → 状态区自动刷新 rdb_changes_since_
//      last_save=0 且服务级 LASTSAVE 前移（RDB 真落盘旁证）；
//   ③ 取消路径 = 状态不变（确认门 Cancel → LASTSAVE 不动）；
//   ④ SAVE 绝不出现在任何入口：dialog 无 SAVE 文案 + readonly 连接
//      SAVE/BGSAVE 被 adapter 守卫拦截（forbidden 表维持，零改动锚定）。
//
// 前置：T29 非 SQL 批（B4）起 Redis 走网关壳，硬依赖 dbmaster server
// 会话——DBMASTER_SERVER_BIN 指向 dbmaster-server.exe（embedded 前置，
// 与 redis_capability_panel_e2e 同跑法）；二进制不可得时以可 grep 的
// REDIS_E2E_SKIP 整组跳过（无假绿纪律）。
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/atoms/app_loading.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/redis_sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';
import 'package:dbmaster/services/readonly_guard.dart';

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
/// 每个可见项渲染为 ListTile，onTap = item.onActivate（redis_capability_
/// panel_e2e 同款）。
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
  final testKey = '${RedisTestConfig.generateTestKeyPrefix()}_bgsave';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    AppProvider.devBypassGates = true; // 集成测试测全功能（金标准同款）
    server = DbServer(
      id: 'dbt-t20-e2e-redis',
      type: DatabaseType.redis,
      name: 'DBT T20 E2E Redis',
      host: RedisTestConfig.host,
      port: RedisTestConfig.port,
      password: RedisTestConfig.password,
      database: RedisTestConfig.database,
    );
  });

  tearDown(() async {
    // 清理自建 key（可写连接；任务书：测试后清理自建 key）。
    try {
      final w = RedisAdapter();
      if (await w.connect(
        DatabaseConnection(
          id: 'cleanup',
          name: 'cleanup',
          type: DatabaseType.redis,
          host: RedisTestConfig.host,
          port: RedisTestConfig.port,
          password: RedisTestConfig.password,
          database: RedisTestConfig.database,
        ),
      )) {
        await w.runCommand(['DEL', testKey]);
        await w.disconnect();
      }
    } catch (_) {}
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
          home: const _CapabilityPanelHarness(),
        ),
      ),
    );
    await tester.pump();
  }

  /// 轮询等待条件成立（runAsync 放行真实 I/O；dialog 内异步加载不走
  /// runAsync，需在真实时钟下等它完成；**不 pumpAndSettle**——加载态
  /// 存在无限 spinner，永不确定）。条件可为异步（服务级重查轮询用）。
  Future<bool> waitUntil(
    WidgetTester tester,
    FutureOr<bool> Function() condition, {
    int timeoutMs = 30000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) return true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    return await condition();
  }

  Future<void> activateItem(WidgetTester tester, String itemId) async {
    await tester.tap(find.byKey(Key('advanced/$itemId')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('W17-STATUS：备份对话框状态区真数据（INFO persistence + LASTSAVE 合理）',
      (tester) async {
    if (!redisE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);

    await activateItem(tester, 'redis.backup');

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Backup & Persistence'), findsOneWidget);
    // 状态区真数据：LASTSAVE 行 + BGSAVE 状态行 + 变更数行全部渲染
    // （INFO persistence 非空、LASTSAVE 为合理历元日期）。
    expect(
      await waitUntil(
        tester,
        () => tester.any(find.textContaining('Last save: 2')),
      ),
      isTrue,
      reason: 'LASTSAVE 真数据行应渲染',
    );
    expect(find.textContaining('Last BGSAVE:'), findsOneWidget);
    expect(find.textContaining('Changes since last save:'), findsOneWidget);
    // 目标实例明示（连接名 + host:port）。
    expect(find.textContaining('DBT T20 E2E Redis'), findsOneWidget);
  });

  testWidgets('W17-BGSAVE：SET 制造变更 → 确认门 → BGSAVE 成功 → changes 归零 '
      '+ LASTSAVE 前移', (tester) async {
    if (!redisE2EGatewayReady) return;
    await connectReal(tester);

    // 制造 changes>0：SET 测试 key（server 级计数，任意 db 生效）。
    final w = RedisAdapter();
    expect(
      await w.connect(
        DatabaseConnection(
          id: 'writer',
          name: 'writer',
          type: DatabaseType.redis,
          host: RedisTestConfig.host,
          port: RedisTestConfig.port,
          password: RedisTestConfig.password,
          database: RedisTestConfig.database,
        ),
      ),
      isTrue,
    );
    await w.runCommand(['SET', testKey, 'v']);
    await w.disconnect();

    final before = await provider.dbService.getRedisPersistenceInfo(
      connectionId: server.id,
    );
    expect(before['lastsave'], isNotNull);

    await pumpHarness(tester);
    await activateItem(tester, 'redis.backup');

    // 确认门（明示目标实例 + fork 影响说明 + 当前变更数）。
    await tester.tap(find.widgetWithText(FilledButton, 'Trigger BGSAVE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('double memory usage'),
      findsOneWidget,
      reason: 'fork 影响说明应渲染',
    );

    // 确认执行 → 成功 snackbar（UI 面证据）+ 状态区自动刷新。
    await tester.tap(find.widgetWithText(LoadingButton, 'Trigger BGSAVE'));
    await tester.pump();
    expect(
      await waitUntil(
        tester,
        () => tester.any(find.text('BGSAVE triggered')),
      ),
      isTrue,
      reason: '成功 snackbar 应出现',
    );

    // 服务级重查（任务书口径）：rdb_changes_since_last_save 回零 +
    // LASTSAVE 前移（RDB 真落盘旁证；unix 秒单调不减）。
    var after = <String, String>{};
    expect(
      await waitUntil(tester, () async {
        after = await provider.dbService.getRedisPersistenceInfo(
          connectionId: server.id,
        );
        return after['rdb_changes_since_last_save'] == '0';
      }),
      isTrue,
      reason: 'BGSAVE 成功后 rdb_changes_since_last_save 应回零',
    );
    final beforeSec = int.tryParse(before['lastsave'] ?? '') ?? 0;
    final afterSec = int.tryParse(after['lastsave'] ?? '') ?? 0;
    expect(
      afterSec,
      greaterThanOrEqualTo(beforeSec),
      reason: 'LASTSAVE 应前移或持平（BGSAVE 真触发）',
    );
    expect(after['rdb_last_bgsave_status'], 'ok');

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('W17-CANCEL：取消路径 = 状态不变（LASTSAVE 不动、无触发）',
      (tester) async {
    if (!redisE2EGatewayReady) return;
    await connectReal(tester);

    final before = await provider.dbService.getRedisPersistenceInfo(
      connectionId: server.id,
    );

    await pumpHarness(tester);
    await activateItem(tester, 'redis.backup');
    expect(
      await waitUntil(
        tester,
        () => tester.any(find.textContaining('Last save: 2')),
      ),
      isTrue,
    );

    // 打开确认门 → Cancel（取消 = 零执行）。
    await tester.tap(find.widgetWithText(FilledButton, 'Trigger BGSAVE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 确认门关闭，主对话框保持打开且状态不变。
    expect(find.textContaining('double memory usage'), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.textContaining('Last save: 2'), findsOneWidget);

    // 服务级：无 BGSAVE → LASTSAVE 不动（期间无其它写入者）。
    final after = await tester.runAsync(
          () => provider.dbService.getRedisPersistenceInfo(
            connectionId: server.id,
          ),
        ) ??
        const <String, String>{};
    expect(after['lastsave'], before['lastsave'],
        reason: '取消路径不得触发 BGSAVE（LASTSAVE 不动）');

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('W17-NOSAVE：SAVE 零入口（dialog 无 SAVE 文案）+ readonly 连接 '
      'SAVE/BGSAVE 被 forbidden 分类拦截（既有面维持锚定）', (tester) async {
    if (!redisE2EGatewayReady) return;
    await connectReal(tester);
    await pumpHarness(tester);
    await activateItem(tester, 'redis.backup');
    expect(
      await waitUntil(
        tester,
        () => tester.any(find.textContaining('Last save: 2')),
      ),
      isTrue,
    );
    // UI 零 SAVE 入口：对话框内不存在 'SAVE' 文案（同步阻塞命令不暴露）。
    expect(find.text('SAVE'), findsNothing);

    // readonly 连接：SAVE / BGSAVE 均被 adapter 守卫 fail-closed 拦截
    // （forbidden 表 → dangerous ≠ safe，既有面零改动锚定）。
    final ro = RedisAdapter();
    expect(
      await ro.connect(
        DatabaseConnection(
          id: 'ro-t20',
          name: 'ro-t20',
          type: DatabaseType.redis,
          host: RedisTestConfig.host,
          port: RedisTestConfig.port,
          password: RedisTestConfig.password,
          database: RedisTestConfig.database,
          readOnly: true,
        ),
      ),
      isTrue,
    );
    await expectLater(
      ro.runCommand(['SAVE']),
      throwsA(isA<ReadOnlyBlockedException>()),
    );
    await expectLater(
      ro.runCommand(['BGSAVE']),
      throwsA(isA<ReadOnlyBlockedException>()),
    );
    await ro.disconnect();

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
  });
}
