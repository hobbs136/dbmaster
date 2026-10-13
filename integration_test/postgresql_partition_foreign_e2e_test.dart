// ============================================================================
// DBT-T19 · PostgreSQL 分区建表 + 外部表 E2E（W-16 真库验证）
//
// 覆盖（任务书 T19 真库验证节，引擎 = WSL PostgreSQL 17，连接信息唯一来源
// test_db_local_wsl.txt，口令经 DBMASTER_PG_* dart-define 注入）：
//   ① RANGE 分区表全链路（dialog 表单 → DDL 预览门 → 确认 → 真库建表）：
//      pg_partitioned_table/partition 断言分区结构 + 插入路由到正确分区
//      （tableoid::regclass 断言），3 分区 + PK 含分区键 + MAXVALUE 段；
//   ② LIST 分区至少 1 例（值列表 + 路由断言）；
//   ③ PK 不含分区键 = 表单拒绝（不出 SQL；to_regclass 断言零残留）；
//   ④ 外部表：e2e 自建自删 postgres_fdw 扩展 + foreign server（superuser）
//      → PgForeignTableDialog 建 FOREIGN TABLE → pg_class relkind='f' 断言；
//      取消路径零残留；
//   ⑤ readonly 连接：CREATE FOREIGN TABLE 服务层拦截（fail-closed 既有面
//      的真库锚定）；
//   ⑥ 同名既有表冲突（R2 security 修复）：预建同名表（含数据）→ 分区建表
//      同名失败 → 断言既有表与数据完好（父表 CREATE 失败零回收 DROP，
//      缺陷形态下回收 DROP 会误删用户同名业务表）。
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
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:dbmaster/organisms/connection/table_dialog/create_table_dialog.dart';
import 'package:dbmaster/organisms/connection/table_dialog/pg_foreign_table_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'package:dbmaster/services/audit_log_service.dart';

import 'config/postgresql_test_config.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

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
      id: 'dbt-t19-e2e-pg',
      type: DatabaseType.postgresql,
      name: 'DBT T19 E2E PostgreSQL',
      host: PostgreSQLTestConfig.host,
      port: PostgreSQLTestConfig.port,
      username: PostgreSQLTestConfig.username,
      password: PostgreSQLTestConfig.password,
      // PG 必带初始库（open_pg 按库开池；跨库语句经 database 参数路由）。
      database: 'postgres',
    );
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  /// 种子 adapter（连 postgres 库建测试库；金标准 T8 e2e 同法）。
  Future<PostgreSQLAdapter> seedAdapter(String dbName) async {
    final adapter = PostgreSQLAdapter();
    await adapter.connect(
      DatabaseConnection(
        id: 'seed_${dbName.hashCode}',
        name: 'DBT T19 Seed',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      ),
    );
    return adapter;
  }

  Future<void> createTestDatabase(String dbName) async {
    final adapter = await seedAdapter(dbName);
    await adapter.createDatabase(dbName);
    await adapter.disconnect();
  }

  Future<void> dropTestDatabase(String dbName) async {
    final adapter = await seedAdapter(dbName);
    // WITH (FORCE)：网关每语句独立开池，残留空闲连接会阻塞普通 DROP。
    await adapter.executeQuery(
      'DROP DATABASE IF EXISTS "$dbName" WITH (FORCE)',
    );
    await adapter.disconnect();
  }

  Future<void> connectReal(
    WidgetTester tester,
    String dbName, {
    bool readOnly = false,
  }) async {
    server = DbServer(
      id: readOnly ? 'dbt-t19-e2e-pg-ro' : 'dbt-t19-e2e-pg',
      type: DatabaseType.postgresql,
      name: readOnly ? 'DBT T19 E2E RO' : 'DBT T19 E2E PostgreSQL',
      host: PostgreSQLTestConfig.host,
      port: PostgreSQLTestConfig.port,
      username: PostgreSQLTestConfig.username,
      password: PostgreSQLTestConfig.password,
      database: dbName,
      readOnly: readOnly,
    );
    final connected = await tester.runAsync(
      () => provider.connection.connectToServer(server),
    );
    expect(connected, isTrue, reason: '真库连接失败（${PostgreSQLTestConfig.host}）');
  }

  /// 生产路径单语句执行（断言面：provider.executeQuery → dbService → 网关壳）。
  Future<List<Map<String, dynamic>>> exec(
    WidgetTester tester,
    String sql, {
    String? database,
    String? connectionId,
  }) async {
    final rows = await tester.runAsync(
          () => provider.executeQuery(
            sql,
            connectionId: connectionId ?? server.id,
            database: database,
          ),
        ) ??
        const <Map<String, dynamic>>[];
    return rows;
  }

  Future<void> pumpCreateDialog(WidgetTester tester, String dbName) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => CreatePostgresTableDialog(dbName: dbName),
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
    expect(find.byType(CreatePostgresTableDialog), findsOneWidget);
  }

  Future<void> pumpForeignDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => PgForeignTableDialog.show(
                  context,
                  connectionId: server.id,
                  databaseName: server.database ?? 'postgres',
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
    expect(find.byType(PgForeignTableDialog), findsOneWidget);
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

  /// 填 PG 建表表单（表名 + 2 列 + 分区键 + N 分区；列行含 name+default
  /// 两输入框——col1.name = 第 5 个 TextFormField）。
  Future<void> fillPartitionedForm(
    WidgetTester tester, {
    required String tableName,
    required String col0,
    required String col1,
    required bool col1Pk,
    required List<(String, String)> partitions,
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), tableName);
    await tester.enterText(find.byType(TextFormField).at(2), col0);
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    await tester.tap(find.text('Add Column'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(4), col1);
    if (col1Pk) {
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pump();
    } else {
      await tester.pump();
    }
    // 分区键 = col1。
    await tester.tap(find.byType(DropdownButton<String?>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text(col1).last);
    await tester.pumpAndSettle();
    for (var i = 0; i < partitions.length; i++) {
      await tester.tap(find.text('Add partition'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(Key('pg_partition_name_$i')),
        partitions[i].$1,
      );
      await tester.enterText(
        find.byKey(Key('pg_partition_bound_$i')),
        partitions[i].$2,
      );
      await tester.pump();
    }
  }

  Future<void> submitAndConfirm(WidgetTester tester) async {
    await tester.tap(find.text('Add'));
    await tester.pump();
    final gated = await waitUntil(
      tester,
      () => tester.any(find.byType(DestructiveConfirmDialog)),
    );
    expect(gated, isTrue, reason: 'DDL 预览门应出现');
    await tester.tap(
      find.descendant(
        of: find.byType(DestructiveConfirmDialog),
        matching: find.text('Confirm'),
      ),
    );
    await tester.pump();
  }

  group('DBT-T19 分区建表 E2E（RANGE/LIST/PK 拒绝）', () {
    testWidgets('T19-RANGE：3 分区 + PK 含分区键 → 结构断言 + 插入路由', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) return;
      final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
      await tester.runAsync(() => createTestDatabase(dbName));
      await connectReal(tester, dbName);
      await pumpCreateDialog(tester, dbName);

      await fillPartitionedForm(
        tester,
        tableName: 'sales_range',
        col0: 'id',
        col1: 'amt',
        col1Pk: true,
        partitions: const [('p0', '100'), ('p1', '200'), ('p2', 'MAXVALUE')],
      );
      await submitAndConfirm(tester);

      // 真库执行 → 对话框关闭（等待窗口覆盖网关 IO）。
      final closed = await waitUntil(
        tester,
        () => !tester.any(find.byType(CreatePostgresTableDialog)),
        timeoutMs: 60000,
      );
      if (!closed) {
        final texts = <String>[];
        for (final e in find.byType(Text).evaluate()) {
          final w = e.widget as Text;
          if (w.data != null && w.data!.isNotEmpty) texts.add(w.data!);
        }
        // ignore: avoid_print
        print('T19-RANGE-DEBUG: dialog texts=$texts');
      }
      expect(closed, isTrue, reason: '分区表创建应成功关闭对话框');

      // 结构断言：pg_partitioned_table + pg_partition（3 分区）。
      final ptRows = await exec(
        tester,
        "SELECT count(*)::int AS n FROM pg_partitioned_table "
        "WHERE partrelid = 'public.sales_range'::regclass",
        database: dbName,
      );
      expect(ptRows.first['n'], 1, reason: '应为分区父表');
      final partRows = await exec(
        tester,
        "SELECT count(*)::int AS n FROM pg_inherits "
        "WHERE inhparent = 'public.sales_range'::regclass",
        database: dbName,
      );
      expect(partRows.first['n'], 3, reason: '应有 3 个分区');

      // 插入路由断言：tableoid::regclass。
      await exec(
        tester,
        'INSERT INTO public.sales_range (id, amt) VALUES (1, 50), (2, 150), (3, 250)',
        database: dbName,
      );
      final routed = await exec(
        tester,
        'SELECT amt, tableoid::regclass::text AS part '
        'FROM public.sales_range ORDER BY amt',
        database: dbName,
      );
      expect(routed, hasLength(3));
      // tableoid::regclass 在 search_path 内只出关系名（不带 schema 前缀）。
      String tail(Object? v) => v.toString().split('.').last;
      expect(tail(routed[0]['part']), 'p0', reason: 'amt=50 → p0');
      expect(tail(routed[1]['part']), 'p1', reason: 'amt=150 → p1');
      expect(tail(routed[2]['part']), 'p2', reason: 'amt=250 → p2(MAXVALUE 段)');

      await tester.runAsync(() => dropTestDatabase(dbName));
    });

    testWidgets('T19-LIST：值列表分区 → 路由断言', (tester) async {
      if (!pgE2EGatewayReady) return;
      final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
      await tester.runAsync(() => createTestDatabase(dbName));
      await connectReal(tester, dbName);
      await pumpCreateDialog(tester, dbName);

      // 策略切 LIST，分区键 = zone（INTEGER，两列均 PK）。
      await fillPartitionedForm(
        tester,
        tableName: 'city_list',
        col0: 'code',
        col1: 'zone',
        col1Pk: true,
        partitions: const [('p_a', '1, 2'), ('p_b', '3')],
      );
      await tester.tap(find.text('RANGE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LIST').last);
      await tester.pumpAndSettle();
      await submitAndConfirm(tester);

      final closed = await waitUntil(
        tester,
        () => !tester.any(find.byType(CreatePostgresTableDialog)),
        timeoutMs: 60000,
      );
      expect(closed, isTrue, reason: 'LIST 分区表创建应成功');

      final partRows = await exec(
        tester,
        "SELECT count(*)::int AS n FROM pg_inherits "
        "WHERE inhparent = 'public.city_list'::regclass",
        database: dbName,
      );
      expect(partRows.first['n'], 2, reason: '应有 2 个 LIST 分区');

      await exec(
        tester,
        'INSERT INTO public.city_list (code, zone) VALUES (10, 1), (20, 3)',
        database: dbName,
      );
      final routed = await exec(
        tester,
        'SELECT code, tableoid::regclass::text AS part '
        'FROM public.city_list ORDER BY code',
        database: dbName,
      );
      String tail(Object? v) => v.toString().split('.').last;
      expect(tail(routed[0]['part']), 'p_a', reason: 'zone=1 → p_a');
      expect(tail(routed[1]['part']), 'p_b', reason: 'zone=3 → p_b');

      await tester.runAsync(() => dropTestDatabase(dbName));
    });

    testWidgets('T19-PK：PK 不含分区键 = 表单拒绝（不出 SQL）', (tester) async {
      if (!pgE2EGatewayReady) return;
      final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
      await tester.runAsync(() => createTestDatabase(dbName));
      await connectReal(tester, dbName);
      await pumpCreateDialog(tester, dbName);

      await fillPartitionedForm(
        tester,
        tableName: 'bad_pk',
        col0: 'id',
        col1: 'region',
        col1Pk: false,
        partitions: const [('p0', '10')],
      );
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 前置拦截文案 + 对话框保持（无预览门）。
      expect(
        find.textContaining('must include the partition key column'),
        findsOneWidget,
      );
      expect(find.byType(DestructiveConfirmDialog), findsNothing);
      expect(find.byType(CreatePostgresTableDialog), findsOneWidget);

      // 零残留：bad_pk 不存在。
      final residue = await exec(
        tester,
        "SELECT to_regclass('public.bad_pk')::text AS t",
        database: dbName,
      );
      expect(residue.first['t'], isNull, reason: '被拒表不应建出');

      await tester.runAsync(() => dropTestDatabase(dbName));
    });

    testWidgets('T19-同名冲突：预建同名表（含数据）→ 分区建表失败 → 既有表完好', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) return;
      final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
      await tester.runAsync(() => createTestDatabase(dbName));
      await connectReal(tester, dbName);

      // 预建同名既有表 + 种子数据（用户业务表视角）。
      await exec(
        tester,
        'CREATE TABLE public.legacy_t19 (id INTEGER PRIMARY KEY, note TEXT)',
        database: dbName,
      );
      await exec(
        tester,
        "INSERT INTO public.legacy_t19 VALUES (1, 'precious')",
        database: dbName,
      );

      await pumpCreateDialog(tester, dbName);
      await fillPartitionedForm(
        tester,
        tableName: 'legacy_t19',
        col0: 'id',
        col1: 'amt',
        col1Pk: true,
        partitions: const [('p0', '100')],
      );
      await submitAndConfirm(tester);

      // 父表 CREATE 42P07 → 引擎错误原文兜底（错误 snackbar），
      // 对话框保持打开（不再有回收 DROP 把既有表删掉后「成功」关窗）。
      await waitUntil(
        tester,
        () =>
            tester.any(find.byType(SnackBar)) ||
            !tester.any(find.byType(CreatePostgresTableDialog)),
        timeoutMs: 60000,
      );
      expect(
        tester.any(find.byType(CreatePostgresTableDialog)),
        isTrue,
        reason: '同名冲突失败 → 对话框不关闭（引擎错误展示）',
      );

      // 核心断言：既有表与数据完好（缺陷形态：回收 DROP 会删掉 legacy_t19）。
      final reg = await exec(
        tester,
        "SELECT to_regclass('public.legacy_t19')::text AS t",
        database: dbName,
      );
      expect(reg.first['t'], isNotNull, reason: '同名既有表未被回收 DROP 删除');
      final rows = await exec(
        tester,
        'SELECT count(*)::int AS n FROM public.legacy_t19',
        database: dbName,
      );
      expect(rows.first['n'], 1, reason: '既有表数据完好');
      // 且未被替换成分区父表 / 无分区子表残留。
      final pt = await exec(
        tester,
        "SELECT count(*)::int AS n FROM pg_partitioned_table "
        "WHERE partrelid = 'public.legacy_t19'::regclass",
        database: dbName,
      );
      expect(pt.first['n'], 0, reason: '既有表未被替换为分区父表');
      final inherits = await exec(
        tester,
        "SELECT count(*)::int AS n FROM pg_inherits "
        "WHERE inhparent = 'public.legacy_t19'::regclass",
        database: dbName,
      );
      expect(inherits.first['n'], 0, reason: '无分区子表挂到既有表上');

      await tester.runAsync(() => dropTestDatabase(dbName));
    });
  });

  group('DBT-T19 外部表 E2E（FOREIGN TABLE）', () {
    testWidgets('T19-FT：postgres_fdw server → FOREIGN TABLE → relkind=f；取消零残留',
        (tester) async {
      if (!pgE2EGatewayReady) return;
      final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
      await tester.runAsync(() async {
        await createTestDatabase(dbName);
        // e2e 自建自删前置：FDW 扩展 + foreign server（superuser；随库删回收）。
        final adapter = await seedAdapter(dbName);
        await adapter.disconnect();
        await adapter.connect(
          DatabaseConnection(
            id: 'seed_${dbName.hashCode}_db',
            name: 'DBT T19 Seed DB',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: dbName,
          ),
        );
        await adapter.executeQuery(
          "CREATE EXTENSION IF NOT EXISTS postgres_fdw",
        );
        await adapter.executeQuery(
          "CREATE SERVER dbt_t19_srv FOREIGN DATA WRAPPER postgres_fdw "
          "OPTIONS (host '${PostgreSQLTestConfig.host}', "
          "port '${PostgreSQLTestConfig.port}', dbname 'postgres')",
        );
        await adapter.disconnect();
      });
      await connectReal(tester, dbName);
      await pumpForeignDialog(tester);

      // servers 下拉 = e2e 预建 server。
      final srvReady = await waitUntil(
        tester,
        () => tester.any(find.text('dbt_t19_srv')),
      );
      expect(srvReady, isTrue, reason: 'servers 下拉应含预建 foreign server');

      // 取消路径先走：填表 → 预览门取消 → 零残留。
      await tester.enterText(
        find.byKey(const Key('pgft_table_field')),
        'ext_cancel',
      );
      await tester.tap(find.byKey(const Key('pgft_create')));
      await tester.pump();
      final cancelGate = await waitUntil(
        tester,
        () => tester.any(find.byType(DestructiveConfirmDialog)),
      );
      expect(cancelGate, isTrue);
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Cancel'),
        ),
      );
      // 门退场动画 pump 完（否则残留路由会被后续 waitUntil 误命中——
      // 首轮实跑曾因此把取消路径的 DDL 当正路径确认执行）。
      await tester.pumpAndSettle();
      expect(find.byType(DestructiveConfirmDialog), findsNothing,
          reason: '取消后预览门应关闭');
      expect(find.byType(PgForeignTableDialog), findsOneWidget);
      var residue = await exec(
        tester,
        "SELECT to_regclass('public.ext_cancel')::text AS t",
        database: dbName,
      );
      expect(residue.first['t'], isNull, reason: '取消路径零残留');

      // 正路径：关闭 dialog①后新开 dialog②（独立 State，消除同 dialog
      // 二次提交的状态残留——首轮实跑曾出现 enterText 不生效/旧 DDL 复现）。
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').first);
      await tester.pumpAndSettle();
      expect(find.byType(PgForeignTableDialog), findsNothing,
          reason: 'dialog① 应已关闭');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(PgForeignTableDialog), findsOneWidget);
      expect(
        await waitUntil(tester, () => tester.any(find.text('dbt_t19_srv'))),
        isTrue,
        reason: 'dialog② servers 应重载',
      );

      // 一列 + OPTIONS（postgres_fdw 表级选项）。
      await tester.enterText(
        find.byKey(const Key('pgft_table_field')),
        'ext_contacts',
      );
      await tester.tap(find.byKey(const Key('pgft_col_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pgft_col_name_0')),
        'remote_id',
      );
      await tester.tap(find.byKey(const Key('pgft_opt_add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pgft_opt_key_0')),
        'table_name',
      );
      await tester.enterText(
        find.byKey(const Key('pgft_opt_value_0')),
        'pg_am',
      );
      await tester.tap(find.byKey(const Key('pgft_create')));
      await tester.pump();
      final gate = await waitUntil(
        tester,
        () => tester.any(find.byType(DestructiveConfirmDialog)),
      );
      expect(gate, isTrue);
      if (!tester.any(
        find.textContaining('CREATE FOREIGN TABLE "public"."ext_contacts"'),
      )) {
        final texts = <String>[];
        for (final e in find.byType(SelectableText).evaluate()) {
          final w = e.widget as SelectableText;
          if (w.data != null) texts.add(w.data!);
        }
        // ignore: avoid_print
        print('T19-FT-DEBUG-GATE: selectable=$texts');
        final all = <String>[];
        for (final e in find.byType(Text).evaluate()) {
          final w = e.widget as Text;
          if (w.data != null && w.data!.isNotEmpty) all.add(w.data!);
        }
        // ignore: avoid_print
        print('T19-FT-DEBUG-GATE: texts=$all');
      }
      // 预览必须是正路径表（防旧门残留误命中）。
      expect(
        find.textContaining('CREATE FOREIGN TABLE "public"."ext_contacts"'),
        findsOneWidget,
        reason: '预览门应展示 ext_contacts 的 DDL',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final closed = await waitUntil(
        tester,
        () => !tester.any(find.byType(PgForeignTableDialog)),
        timeoutMs: 60000,
      );
      expect(closed, isTrue, reason: '外部表创建应成功关闭对话框');

      // relkind='f' 断言（pg_class）。网关 decode_cell_pg 会把单字符 'f'
      // 按布尔格解码丢失——服务端 CASE 归一为 text 再断言。
      final relkind = await exec(
        tester,
        "SELECT CASE WHEN relkind = 'f' THEN 'is_foreign' ELSE 'not_foreign' END AS kind "
        "FROM pg_class WHERE relname = 'ext_contacts'",
        database: dbName,
      );
      if (relkind.isEmpty) {
        final texts = <String>[];
        for (final e in find.byType(Text).evaluate()) {
          final w = e.widget as Text;
          if (w.data != null && w.data!.isNotEmpty) texts.add(w.data!);
        }
        // ignore: avoid_print
        print('T19-FT-DEBUG: relkind empty; visible texts=$texts');
        await tester.runAsync(() async {
          final probe = PostgreSQLAdapter();
          await probe.connect(DatabaseConnection(
            id: 'ft_debug_${dbName.hashCode}',
            name: 'DBT T19 FT Debug',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: dbName,
          ));
          final direct = await probe.executeQuery(
            "SELECT current_database() AS d, "
            "(SELECT count(*) FROM pg_class WHERE relname = 'ext_contacts') AS n",
          );
          // ignore: avoid_print
          print('T19-FT-DEBUG: direct probe rows=${direct.rows}');
          await probe.disconnect();
        });
        await tester.runAsync(() async {
          // postgres 库对照：dialog 的建表是否落错了库。
          final probe2 = PostgreSQLAdapter();
          await probe2.connect(DatabaseConnection(
            id: 'ft_debug_pg_${dbName.hashCode}',
            name: 'DBT T19 FT Debug PG',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          ));
          final inPg = await probe2.executeQuery(
            "SELECT (SELECT count(*) FROM pg_class WHERE relname = 'ext_contacts') AS n, "
            "current_database() AS d",
          );
          // ignore: avoid_print
          print('T19-FT-DEBUG: postgres db rows=${inPg.rows}');
          await probe2.disconnect();
          // 审计最近记录：dialog 实际执行的 SQL 与落库。
          final audit = AuditLogService();
          await audit.initialize();
          final recent = audit.getRecentEntries(limit: 5);
          // ignore: avoid_print
          print('T19-FT-DEBUG: audit recent=${[
            for (final r in recent)
              {'db': r.databaseName, 'ok': r.success, 'sql': r.sql.length > 80 ? r.sql.substring(0, 80) : r.sql},
          ]}');
        });
      }
      expect(relkind, isNotEmpty);
      expect(relkind.first['kind'], 'is_foreign',
          reason: 'FOREIGN TABLE relkind=f');

      await tester.runAsync(() => dropTestDatabase(dbName));
    });

    testWidgets('T19-RO：readonly 连接 CREATE FOREIGN TABLE 服务层拦截', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) return;
      final dbName = PostgreSQLTestConfig.generateTestDatabaseName();
      await tester.runAsync(() => createTestDatabase(dbName));
      // readonly 服务层闸门读 savedConnections 标志（T18 先例：先保存再连）。
      await connectReal(tester, dbName, readOnly: true);
      await provider.connection.saveConnection(server);

      // 服务层 _isWriteQuery CREATE 关键字闸门（fail-closed 既有面锚定）。
      Object? caught;
      await tester.runAsync(() async {
        try {
          await provider.dbService.executeQuery(
            'CREATE FOREIGN TABLE public.ro_block (id INTEGER) '
            "SERVER no_such_server",
            connectionId: server.id,
            database: dbName,
          );
        } catch (e) {
          caught = e;
        }
      });
      expect(caught, isNotNull, reason: '只读连接 CREATE 应被服务层拦截');
      // 服务层闸门文案（ensureServerNotReadOnly / 只读模式下禁止执行修改操作）。
      expect(caught.toString(), contains('只读'),
          reason: '拦截错误应为只读语义: $caught');

      await tester.runAsync(() => dropTestDatabase(dbName));
    });
  });
}
