// ============================================================================
// DBT-T8 · PostgreSQL 运维 E2E（W-09/W-10 真库验证）
//
// 覆盖（任务书 T8 真库验证节，引擎 = WSL PostgreSQL 17，连接信息唯一来源
// test_db_local_wsl.txt，口令经 DBMASTER_PG_PASSWORD dart-define 注入）：
//   ① 通道核实（任务第一步）：VACUUM 经现行网关单语句执行路径
//      （provider.executeQuery → dbService → /api/gw 单语句非事务）真跑成功
//      —— VACUUM 不能在事务块内执行，网关若拒绝（事务块错误类）该组失败
//      即升级跨组件契约审查，不得自行改 server；REINDEX TABLE 同面核实；
//   ② VACUUM/REINDEX 聚合入口 UI 全链路：pg.maintenance 面板项 → 库/表/
//      动作 chip → 专属确认门 → 真库执行 → 结果行成功；
//   ③ 锁分析（W-10）：连接 A 单语句 `SELECT pg_sleep(...) ... FOR UPDATE`
//      持行锁（网关无事务，以长语句代事务持锁）+ 连接 B 同行 UPDATE 阻塞
//      → 面板查询出现 granted=false 等待行；pg.locks 面板项打开 dialog
//      渲染等待行；tearDown 等待两语句完成后自删测试库。
//
// 前置：DBMASTER_SERVER_BIN 指向 dbmaster-server.exe（embedded 网关，
// 无二进制时以可 grep 的 PG_E2E_SKIP 整组跳过，FR-011 无假绿纪律）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:dbmaster/organisms/dialogs/pg_locks_dialog.dart';
import 'package:dbmaster/organisms/dialogs/postgresql_table_maintenance_entry_dialog.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/postgresql_sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
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

/// 能力面板驱动壳（T4 e2e 同款）：装配后把每个可见项渲染为 ListTile，
/// onTap = item.onActivate（与真实菜单同一激活闭包）。
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
  /// 清理历史失败运行遗留的测试库（名称模式 dbmaster_test_<ms>_<hex>）。
  /// 只清 5 分钟前创建的——防误删并行进程刚建的库。遗留库会把下拉菜单
  /// 撑长，新建库（时间戳最大 = 排序最后）被挤出菜单构建视口 →
  /// find 失败（实测竞态来源）。
  Future<void> cleanupStaleTestDatabases() async {
    final adapter = PostgreSQLAdapter();
    await adapter.connect(
      DatabaseConnection(
        id: 'cleanup_${DateTime.now().millisecondsSinceEpoch}',
        name: 'DBT T8 Cleanup',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      ),
    );
    final cutoff = DateTime.now().millisecondsSinceEpoch - 5 * 60 * 1000;
    final result = await adapter.executeQuery(
      "SELECT datname FROM pg_database WHERE datname LIKE 'dbmaster\\_test\\_%'",
    );
    for (final row in result.rows) {
      final name = row['datname']?.toString() ?? '';
      final parts = name.split('_');
      if (parts.length < 4 || parts[0] != 'dbmaster' || parts[1] != 'test') {
        continue;
      }
      final ts = int.tryParse(parts[2]);
      if (ts != null && ts < cutoff) {
        await adapter.executeQuery(
          'DROP DATABASE IF EXISTS "$name" WITH (FORCE)',
        );
      }
    }
    await adapter.disconnect();
  }

  setUpAll(() async {
    pgE2EGatewayReady = await ensureEmbeddedServerForPgE2E();
    if (pgE2EGatewayReady && !PostgreSQLTestConfig.isConfigured) {
      // ignore: avoid_print
      print('PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      pgE2EGatewayReady = false;
    }
    if (pgE2EGatewayReady) {
      // 历史遗留库清理（下拉菜单视口竞态来源，见 cleanupStaleTestDatabases）。
      await cleanupStaleTestDatabases();
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    server = DbServer(
      id: 'dbt-t8-e2e-pg',
      type: DatabaseType.postgresql,
      name: 'DBT T8 E2E PostgreSQL',
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

  /// 生产路径单语句执行（通道核实/数据断言同面：provider.executeQuery →
  /// dbService → 网关壳 adapter）。
  Future<List<Map<String, dynamic>>> exec(
    WidgetTester tester,
    String sql, {
    String? database,
  }) async {
    final rows = await tester.runAsync(
          () => provider.executeQuery(
            sql,
            connectionId: server.id,
            database: database,
          ),
        ) ??
        const <Map<String, dynamic>>[];
    return rows;
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

  /// 种子连接（金标准 postgresql_sidebar_menu_e2e 先例：raw adapter 经
  /// embedded 网关建测试库/建表；产品路径断言仍走 provider 既有面）。
  Future<void> seedTestDatabase(String dbName) async {
    final adapter = PostgreSQLAdapter();
    await adapter.connect(
      DatabaseConnection(
        id: 'seed_${dbName.hashCode}',
        name: 'DBT T8 Seed',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      ),
    );
    await adapter.createDatabase(dbName);
    await adapter.disconnect();
    await adapter.connect(
      DatabaseConnection(
        id: 'seed_${dbName.hashCode}_db',
        name: 'DBT T8 Seed DB',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: dbName,
      ),
    );
    await adapter.executeQuery(
      'CREATE TABLE "t_maint" (id INTEGER PRIMARY KEY, v INTEGER)',
    );
    await adapter.executeQuery(
      'INSERT INTO "t_maint" SELECT g, g FROM generate_series(1, 200) g',
    );
    // 制造死元组（VACUUM 可回收空间的真实工况）。
    await adapter.executeQuery('DELETE FROM "t_maint" WHERE id > 100');
    await adapter.disconnect();
  }


  Future<void> dropTestDatabase(String dbName) async {
    final adapter = PostgreSQLAdapter();
    await adapter.connect(
      DatabaseConnection(
        id: 'teardown_${dbName.hashCode}',
        name: 'DBT T8 Teardown',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      ),
    );
    // WITH (FORCE)：网关每语句独立开池，残留空闲连接会阻塞普通 DROP。
    await adapter.executeQuery('DROP DATABASE IF EXISTS "$dbName" WITH (FORCE)');
    await adapter.disconnect();
  }

  testWidgets('DBT-T8-CHANNEL：VACUUM/REINDEX 经网关单语句通道真跑成功（任务第一步核实）',
      (tester) async {
    if (!pgE2EGatewayReady) return;
    await connectReal(tester);
    final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
    await tester.runAsync(() => seedTestDatabase(dbName));

    // 通道核实：VACUUM（表级）经 provider.executeQuery → dbService →
    // /api/gw 单语句非事务通道。若网关把语句包进事务块，此处抛
    // "VACUUM cannot run inside a transaction block" → 任务书升级条款。
    await exec(tester, 'VACUUM "t_maint"', database: dbName);

    // VACUUM 后库仍可查（pg_stat_user_tables 可查 + 表数据完整）。
    final statRows = await exec(
      tester,
      "SELECT relname, n_live_tup FROM pg_stat_user_tables "
      "WHERE relname = 't_maint'",
      database: dbName,
    );
    expect(statRows, isNotEmpty, reason: 'VACUUM 后 pg_stat_user_tables 应可查');
    final dataRows = await exec(
      tester,
      'SELECT count(*)::int AS n FROM "t_maint"',
      database: dbName,
    );
    expect(dataRows.first['n'], 100, reason: 'VACUUM 后存活行应保持 100');

    // 通道核实：REINDEX TABLE 同面。
    await exec(tester, 'REINDEX TABLE "t_maint"', database: dbName);

    // 库级 VACUUM（无目标形态，当前库全量）同面核实。
    await exec(tester, 'VACUUM', database: dbName);

    await tester.runAsync(() => dropTestDatabase(dbName));
  });

  testWidgets('DBT-T8-ENTRY：聚合入口 VACUUM UI 全链路（确认门 → 真库执行 → 结果行）',
      (tester) async {
    if (!pgE2EGatewayReady) return;
    // 先建库后连 provider（下拉 getDatabases 与连接注册后的库清单刷新
    // 时序解耦——避免「连接注册后才建的库偶发不出现在下拉」竞态）。
    final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
    await tester.runAsync(() => seedTestDatabase(dbName));
    await connectReal(tester);

    await pumpHarness(tester);
    await activateItem(tester, 'pg.maintenance');
    expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsOneWidget);

    // 库下拉切到测试库并等表清单含 t_maint。
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
    // 下拉菜单条目就绪等待 + 滚动兜底：菜单为懒构建列表，长库名清单中
    // 目标条目（时间戳最大 = 排序最后）可能未构建——向上滚动菜单（有界）
    // 直到条目出现。
    var dbItemReady = false;
    for (var attempt = 0; attempt < 12 && !dbItemReady; attempt++) {
      dbItemReady = await waitUntil(
        tester,
        () => tester.any(find.text(dbName)),
        timeoutMs: 2000,
      );
      if (!dbItemReady && tester.any(find.byType(ListView))) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -240));
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
    if (!dbItemReady) {
      // 诊断：dump dialog 内全部文本（loadDatabases 失败 = 错误行 vs 空清单）。
      final texts = <String>[];
      for (final e in find.byType(Text).evaluate()) {
        final w = e.widget as Text;
        if (w.data != null && w.data!.isNotEmpty) texts.add(w.data!);
      }
      // ignore: avoid_print
      print('T8-ENTRY-DEBUG: db item not found; dialog texts=$texts');
    }
    expect(dbItemReady, isTrue, reason: '下拉菜单应渲染出测试库条目');
    await tester.tap(find.text(dbName).last);
    await tester.pump();
    expect(
      await waitUntil(tester, () => tester.any(find.text('t_maint'))),
      isTrue,
      reason: '测试库表清单应含 t_maint',
    );

    // 选 VACUUM 动作 chip → 勾表 → 执行。
    await tester.tap(find.text('VACUUM'));
    await tester.pump();
    await tester.tap(find.text('t_maint'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 专属确认门（DestructiveConfirmDialog 外壳 + pgVacuumConfirm 文案）。
    expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
    expect(find.textContaining('Run VACUUM on'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(DestructiveConfirmDialog),
        matching: find.text('Confirm'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 真库执行 → 结果行成功（pgMaintainSuccess + 耗时）。
    final completed = await waitUntil(
      tester,
      () => tester.any(find.textContaining('VACUUM completed')),
      timeoutMs: 60000,
    );
    if (!completed) {
      // 诊断（失败路径排查）：dump 结果行/错误原文相关文本。
      final texts = <String>[];
      for (final e in find.byType(Text).evaluate()) {
        final w = e.widget as Text;
        final data = w.data ?? '';
        if (data.isNotEmpty && (data.contains('VACUUM') || data.contains('ailed'))) {
          texts.add(data);
        }
      }
      for (final e in find.byType(SelectableText).evaluate()) {
        final w = e.widget as SelectableText;
        if (w.data != null && w.data!.isNotEmpty) texts.add(w.data!);
      }
      // ignore: avoid_print
      print('T8-ENTRY-DEBUG: completed=false; texts=$texts');
    }
    expect(
      completed,
      isTrue,
      reason: 'VACUUM 应经 provider 既有面真库执行成功并出结果行',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => dropTestDatabase(dbName));
  });

  testWidgets('DBT-T8-LOCKS：锁等待行（granted=false）数据面 + pg.locks 面板渲染',
      (tester) async {
    if (!pgE2EGatewayReady) return;
    await connectReal(tester);
    final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
    await tester.runAsync(() => seedTestDatabase(dbName));
    // 锁等待载体表：单行数据。
    await exec(
      tester,
      'CREATE TABLE "t_lock" (id INTEGER PRIMARY KEY, v INTEGER)',
      database: dbName,
    );
    await exec(
      tester,
      'INSERT INTO "t_lock" VALUES (1, 1)',
      database: dbName,
    );

    // 连接 A：单语句长查询持行锁（网关无事务通道，以 pg_sleep + FOR UPDATE
    // 代事务持锁）。持锁顺序：FOR UPDATE 放子查询——行锁在子查询 LockRows
    // 节点输出行时即取得（语句未结束 = 事务未结束 = 锁保持），外层
    // pg_sleep 在持锁期间休眠；若睡在 LockRows 之前（平铺写法）则锁在
    // 休眠后才取，B 不阻塞（实测教训）。
    // 连接 B：同行 UPDATE（请求 A 持有的行事务锁 → 阻塞等待）。
    // 启动顺序：A 先行 + 宽限等待（行锁在 A 启动后毫秒级取得，2s 宽限
    // 远大于取锁耗时），确认 A 已持锁后再发 B——同窗口背靠背启动时 B
    // 可能先到（实测竞态）。
    // 两语句经 dbService.executeQueryBypassDml（用户已确认 DML 的既有通道
    // ——B 的 UPDATE 无 LIMIT 会被 DML 拦截器要求确认；readonly 闸门在该
    // 通道同样生效）。⚠ runAsync 不可重入：各语句在独立窗口启动且不等待，
    // 真实 IO 由后续轮询窗口推进完成。
    Future<List<Map<String, dynamic>>>? lockHolder;
    var aDone = false;
    await tester.runAsync(() {
      lockHolder = provider.connection.dbService
          .executeQueryBypassDml(
            'SELECT pg_sleep(12) AS slept FROM '
            '(SELECT id FROM "t_lock" WHERE id = 1 FOR UPDATE) locked',
            connectionId: server.id,
            database: dbName,
          )
          .whenComplete(() => aDone = true);
      return Future<void>.value();
    });
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2000)),
    );

    Future<List<Map<String, dynamic>>>? blockedUpdate;
    var bDone = false;
    await tester.runAsync(() {
      blockedUpdate = provider.connection.dbService
          .executeQueryBypassDml(
            'UPDATE "t_lock" SET v = v + 1 WHERE id = 1',
            connectionId: server.id,
            database: dbName,
          )
          .whenComplete(() => bDone = true);
      return Future<void>.value();
    });
    await tester.pump();

    // 数据面：面板同一查询（pg_locks × pg_stat_activity 聚合，SQL 与
    // PgLocksDialog 同源常量）出现 granted=false 的等待行。granted 兼容
    // bool/'f' 归一（PgLockEntry.fromRow 同口径）；每轮 poll 打一行诊断
    // （集成测试 print 先例，flake 定位用）。
    var sawWaiting = false;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final rows = await exec(
        tester,
        pgLocksQuery,
        database: dbName,
      );
      // ignore: avoid_print
      print('T8-LOCKS poll rows=${rows.length} aDone=$aDone bDone=$bDone '
          'grantedRaw=${rows.map((r) => r['granted']).toSet().join(',')}');
      final normalizedWaiting = rows.any(
        (r) {
          final g = r['granted'];
          return g == false || g.toString() == 'f' || g.toString() == 'false';
        },
      );
      if (normalizedWaiting) {
        sawWaiting = true;
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    }
    expect(sawWaiting, isTrue,
        reason: 'B 的 UPDATE 应以 granted=false 等待行出现在 pg_locks 聚合中');

    // UI 面：pg.locks 面板项 → 只读锁分析 dialog 渲染等待行
    // （transactionid 等待锁为 UPDATE 阻塞的典型 locktype）。
    await pumpHarness(tester);
    await activateItem(tester, 'pg.locks');
    expect(find.byType(PgLocksDialog), findsOneWidget);
    // 面板查询不带库路由（连接级聚合视图）；渲染非空即可（连接 A/B 会话
    // 与等待行均为真实数据）。
    expect(
      await waitUntil(
        tester,
        () => tester.any(find.byType(PgLocksDialog)) &&
            tester.any(find.text('transactionid')),
        timeoutMs: 12000,
      ),
      isTrue,
      reason: '锁面板应渲染等待行（locktype=transactionid，真实锁等待数据）',
    );
    // 手动刷新按钮在位（只读面板，无 terminate 任何形态）。
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);

    // tearDown：等两语句自然完成（A 12s 到点释放行锁 → B 获锁完成）后回收。
    // ⚠ 后台 future 只在 runAsync 窗口内推进——在窗口内 await 其完成。
    await tester.runAsync(() async {
      await lockHolder;
      await blockedUpdate;
    });
    final vRows = await exec(
      tester,
      'SELECT v FROM "t_lock" WHERE id = 1',
      database: dbName,
    );
    expect(vRows.first['v'], 2, reason: 'B 的 UPDATE 应在 A 释放后生效');

    await tester.runAsync(() => dropTestDatabase(dbName));
  });
}
