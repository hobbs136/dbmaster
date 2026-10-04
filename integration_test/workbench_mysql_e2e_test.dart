// ============================================================================
// MySQL AI Workbench End-to-End Integration Tests (T15, design §11.2)
// Tests: Real MySQL server + real AppProvider + real gateway adapter +
//        AiWorkbenchShell UI driving (gold-standard pattern:
//        mysql_sidebar_menu_e2e_test.dart)
// Cases: R5 result card content == real seed data / R6 write-confirm cancel
//        leaves DB untouched (confirm path applies) / R7 open-in-classic tab
// Target: real MySQL via DBMASTER_MYSQL_* (see config/mysql_test_config.dart);
//        MySQL family needs the embedded dbmaster server session
//        (helpers/mysql_gateway_e2e_helper.dart, DBMASTER_SERVER_BIN).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_snapshot_table.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_table_card.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_picker.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/organisms/ai_panel/confirm_execute_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/mysql_test_config.dart';
import 'helpers/ai_session_isolation_helper.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得 / DBMASTER_MYSQL_* 未提供时全组以可 grep 的
  // MYSQL_E2E_SKIP 跳过（FR-011 无假绿纪律），setUp 同步早退。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MySQL Workbench E2E', () {
    late AppProvider appProvider;
    late MySQLAdapter adapter;
    late String testDbName;
    late DbServer server;

    const connectionLabel = 'MySQL Workbench E2E';
    const seedTable = 'wb_seed';

    setUp(() async {
      // AG-F-19：prefs 隔离（Fix-H 会话隔离同族）——早于任何 AppProvider
      // 构造与 prefs 触达，把 SharedPreferences 切到 mock 存储，杜绝直写
      // 用户真实偏好（saved_queries / recent_tables / connection_groups 等）。
      SharedPreferences.setMockInitialValues({});
      if (!mysqlE2EGatewayReady) return; // 无环境：整组跳过（标记已打印）
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();

      // 1. 种子专用 adapter 连接（金标准模式：先建库种数，再连 provider，
      //    使其数据库列表已含测试库）。
      final dbConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await adapter.connect(dbConn);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      // 列名刻意避开 PII 敏感关键词（name/username 等）：executeQuery facade
      // 对 SELECT 结果做 PII 脱敏，敏感列名会触发值改写干扰「快照 == 种子」
      // 断言（id/label 不命中启发式，值不命中正则，原样透传）。
      await adapter.createTable(seedTable, [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'label', type: 'VARCHAR(100)', isNullable: false),
      ]);
      await adapter.executeQuery(
        "INSERT INTO `$seedTable` (id, label) VALUES (1, 'alpha'), (2, 'beta')",
      );

      // 2. 真实 AppProvider 连接（真实 DatabaseService + 网关壳 adapter）。
      // Fix-H：注入存储隔离 manager——本文件不调 setMockInitialValues，
      // 真机模式下 ensureSession/addAiMessage 的会话文件 + active-id prefs
      // 此前直写用户真实存储（污染缺陷波及点），现落临时目录 + 前缀键。
      appProvider = AppProvider(
        aiSessionManager: createIsolatedAiSessionManager(),
      );
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      // 会话引导（T15 根因修复）：真实 AppProvider 的会话来自
      // initialize() → sessionManager.load()（恢复持久会话）或用户首条消息
      // 的 ensureSession（workbench_chat_view._sendMessage）。裸构造的
      // provider 两者都没有，_currentSession == null 时 addAiMessage 被
      // AiSessionManager 静默丢弃（种子消息进不了渲染流 → SQL 卡不渲染）。
      // 与 test/organisms/ai_workbench/ 下全部种子用例同款前置。
      appProvider.aiPanel.ensureSession();
      server = DbServer(
        id: 'mysql_workbench_e2e_${testDbName.hashCode}',
        name: connectionLabel,
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');
      await appProvider.refreshDatabases();

      // 3. 工作台上下文：显式开一个绑定上下文的 query tab（openQueryTab 默认
      //    bindContext: true）——resolveWorkbenchContext 继承序「活动 tab 优先」
      //    的真实形态；该 tab 同时充当 R7 的「既有 tab」。
      await appProvider.openQueryTab(server.id, testDbName, sql: 'SELECT 1');
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      // 清理跨用例的 SharedPreferences 键（含工作台统计存储键）。
      // setUp 已 setMockInitialValues：以下清理作用于 mock 存储，不动用户真实偏好。
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_queries');
        await prefs.remove('recent_tables');
        await prefs.remove('sidebar_favorite_tables');
        await prefs.remove('connection_groups');
        await prefs.remove('workbench_stats_v1');
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    // ----------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------
    Widget buildTestApp() {
      // B3/B1 适配：舞台布局段消费 LayoutPreferencesProvider（对话列宽双模
      // 持久化），execution tab 推送会打开舞台——harness 树补齐该 provider
      //（与 main.dart 真实装配一致）。
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>(
            create: (_) => LayoutPreferencesProvider()..load(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: AiWorkbenchShell()),
        ),
      );
    }

    /// B1：测试字体（Ahem 方块字）下 SQL 卡四动作钮 header 在收窄对话列
    /// 假性溢出（真机放得下 520 档；窄档真实溢出属既有卡头缺陷，登记遗留）。
    /// execution tab 推送打开舞台 → 对话列收窄触发；仅吞咽 RenderFlex
    /// overflow 类报告，其余原样转交既有处理器；addTearDown 恢复。
    /// （与 ai_workbench_shell_test.dart 同名 helper 同形态——两文件各自
    /// 持有，不互引私有辅助。）
    void suppressOverflowArtifacts() {
      final previousHandler = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previousHandler);
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exception.toString().contains('RenderFlex overflowed')) {
          return; // 测试字体布局伪影，吞咽
        }
        previousHandler?.call(details);
      };
    }

    /// 泵工作台壳（真实入口语义：aiPanelOpen + aiPanelFullscreen = 进入
    /// 工作台，z2 全屏态宿主渲染 AiWorkbenchShell——与 z2 层同一组件）。
    Future<void> pumpWorkbench(WidgetTester tester) async {
      // 视口加高（金标准先例）：卡的 header/动作钮在消息列表底部，默认
      // 600 高的视口下 tap 派生 Offset 可能落在折叠区外不命中。
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appProvider.setAiPanelOpen(true);
      appProvider.setAiPanelFullscreen(true);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    /// 模拟「AI 产出 SQL」：消息流落入带 code 块的 AI 消息——
    /// WorkbenchCardHost 的 code 拦截路径渲染为 SQL 卡（design §4.4 ②，
    /// 与真实 AI 回复同一渲染层路径）。
    void addAiSqlMessage(String sql) {
      appProvider.addAiMessage(
        AiMessage(
          id: 'ai_sql_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          content: 'Here is the SQL for your request.',
          timestamp: DateTime.now(),
          code: sql,
          status: AiMessageStatus.completed,
        ),
      );
    }

    /// 真实执行是网络往返，不排帧——轮询 provider 消息流直到条件成立。
    Future<bool> waitUntil(
      WidgetTester tester,
      bool Function() predicate, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!predicate()) {
        if (DateTime.now().isAfter(deadline)) return false;
        await tester.pump(const Duration(milliseconds: 100));
      }
      return true;
    }

    /// 最近一条工作台结果卡 payload（执行编排落卡面）。
    WorkbenchResultCardPayload? lastResultCardPayload() {
      for (final message in appProvider.aiMessages.reversed) {
        final raw = message.toolResultData?['workbench'];
        if (raw is Map) {
          final payload = WorkbenchResultCardPayload.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (payload != null) return payload;
        }
      }
      return null;
    }

    /// 最近一条工作台错误卡 payload（失败不静默面；排障用）。
    WorkbenchErrorCardPayload? lastErrorCardPayload() {
      for (final message in appProvider.aiMessages.reversed) {
        final raw = message.toolResultData?['workbench'];
        if (raw is Map) {
          final error = WorkbenchErrorCardPayload.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (error != null) return error;
        }
      }
      return null;
    }

    /// 直查种子表指定行的 label（seed adapter 独立会话，绕开被测 UI 链路）。
    Future<String> readLabel(int id) async {
      await adapter.useDatabase(testDbName);
      final result = await adapter.executeQuery(
        'SELECT label FROM `$seedTable` WHERE id = $id',
      );
      expect(result.rows, isNotEmpty, reason: 'readLabel($id) 应有结果行');
      return result.rows.first['label'].toString();
    }

    // ----------------------------------------------------------------------
    // R5 结果卡：工作台执行 SELECT → 卡内行数/耗时/列名与快照行 == 真实数据
    // ----------------------------------------------------------------------
    testWidgets(
      'R5 workbench execute SELECT lands result card matching real seed data',
      (tester) async {
        if (!mysqlE2EGatewayReady) {
          return;
        }
        await pumpWorkbench(tester);

        const sql = 'SELECT id, label FROM wb_seed ORDER BY id ASC';
        addAiSqlMessage(sql);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // SQL 卡出现（code 拦截路径），经 UI 驱动真实「执行」按钮。
        final executeButton = find.byKey(SqlToolCard.executeButtonKey);
        expect(executeButton, findsOneWidget, reason: 'SQL 卡应渲染执行按钮');
        await tester.ensureVisible(executeButton);
        await tester.tap(executeButton);

        // 真库往返：等结果卡消息落流（失败则抓错误卡原文）。
        final landed = await waitUntil(tester, () =>
            lastResultCardPayload() != null || lastErrorCardPayload() != null);
        expect(
          landed,
          isTrue,
          reason: '执行应落卡（错误卡原文：${lastErrorCardPayload()?.detail}）',
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final payload = lastResultCardPayload();
        expect(payload, isNotNull, reason: 'SELECT 执行应落结果卡（非错误卡）');
        // 断言「功能真生效」：卡数据 == 种子真实数据，不是控件出现就算。
        expect(payload!.rowCount, 2, reason: '行数 == 种子真实行数');
        expect(payload.durationMs, greaterThanOrEqualTo(0), reason: '耗时存在');
        expect(payload.columns, ['id', 'label'], reason: '列名 == 种子列序');
        expect(payload.snapshotRows.length, 2);
        expect(payload.snapshotRows[0]['id'].toString(), '1');
        expect(payload.snapshotRows[0]['label'].toString(), 'alpha');
        expect(payload.snapshotRows[1]['id'].toString(), '2');
        expect(payload.snapshotRows[1]['label'].toString(), 'beta');
        expect(payload.isTruncated, isFalse, reason: '2 行 < N 不截断');

        // 渲染面：折叠元信息 `2 rows · N ms`。
        final cardFinder = find.byType(ResultTableCard);
        expect(cardFinder, findsOneWidget);
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.textContaining(RegExp(r'^2 rows · \d+ ms$')),
          ),
          findsOneWidget,
          reason: '折叠元信息应显示真实行数与耗时',
        );

        // 展开卡：内嵌快照表渲染种子真实列名与行内容。
        // B2 落地修复（W3 波及面）：结果卡头右侧新增「在舞台打开」按钮
        //（有快照即可开）——测试字体下按钮很宽，header 几何中心落在按钮上
        //（点 header 中心会误触开舞台，不再是折叠切换）。改点 header 左侧
        // 元信息文本（同一 InkWell 行内）触发展开。
        await tester.tap(
          find.descendant(
            of: cardFinder,
            matching: find.textContaining(RegExp(r'^2 rows · \d+ ms$')),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byType(ResultSnapshotTable),
          ),
          findsOneWidget,
          reason: '展开态渲染快照表',
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('label')),
          findsAtLeastNWidgets(1),
          reason: '快照表表头含真实列名 label',
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('alpha')),
          findsOneWidget,
          reason: '快照行内容 == 种子真实数据 alpha',
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('beta')),
          findsOneWidget,
          reason: '快照行内容 == 种子真实数据 beta',
        );
      },
    );

    // ----------------------------------------------------------------------
    // R6 写确认取消：确认框取消 → 重查数据未变；确认路径 → 重查已变更
    // ----------------------------------------------------------------------
    testWidgets(
      'R6 write confirm: cancel leaves data unchanged, confirm applies UPDATE',
      (tester) async {
        if (!mysqlE2EGatewayReady) {
          return;
        }
        await pumpWorkbench(tester);
        // B1：确认路径 UPDATE 写批会推 execution tab 打开舞台 → 收窄对话列
        // 卡头测试字体假性溢出过滤（见 harness 注记）。
        suppressOverflowArtifacts();

        // WHERE + LIMIT：DML 风险拦截零触发（updateWithoutWhere/critical、
        // dmlWithoutLimit/high 均不命中），确认流只剩工作台 gate #1——
        // 本用例的被测对象正是 T13 的写确认编排。
        const sql = "UPDATE wb_seed SET label = 'gamma' WHERE id = 1 LIMIT 1";
        addAiSqlMessage(sql);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 写徽标（classifier 判定真生效的 e2e 形态）。
        expect(
          find.byKey(SqlToolCard.writeBadgeKey),
          findsOneWidget,
          reason: 'UPDATE 应判写并渲染危险徽标',
        );

        // —— 取消路径 ——
        await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 500));

        // 写确认框出现（gate #1，AC6.1）：SQL 全文 + 目标连接/库行（AC6.5）。
        final dialogFinder = find.byType(ConfirmExecuteDialog);
        expect(dialogFinder, findsOneWidget, reason: '写 SQL 执行必弹确认');
        expect(find.descendant(of: dialogFinder, matching: find.text(sql)),
            findsOneWidget, reason: '确认框含 SQL 全文');
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.textContaining('Target:'),
          ),
          findsOneWidget,
          reason: '确认框含目标连接/库行（AC6.5）',
        );

        await tester.tap(
          find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(TextButton, 'Cancel'),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(
          find.byType(ConfirmExecuteDialog),
          findsNothing,
          reason: '取消后确认框关闭',
        );

        // 重查数据库：数据未变（AC6.2 零执行，真库形态）。
        expect(await readLabel(1), 'alpha', reason: '取消后数据库零变化');
        expect(
          lastResultCardPayload(),
          isNull,
          reason: '取消后不应有任何结果卡（零执行）',
        );

        // —— 确认路径（对照组）——
        await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        expect(
          find.byType(ConfirmExecuteDialog),
          findsOneWidget,
          reason: '再次执行仍需确认（cancel 不入会话放行集）',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmExecuteDialog),
            matching: find.widgetWithText(ElevatedButton, 'Confirm Execute'),
          ),
        );

        final landed = await waitUntil(tester, () =>
            lastResultCardPayload() != null || lastErrorCardPayload() != null);
        expect(
          landed,
          isTrue,
          reason: '确认后执行应落卡（错误卡原文：${lastErrorCardPayload()?.detail}）',
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final payload = lastResultCardPayload();
        expect(payload, isNotNull, reason: '确认路径应落结果卡（非错误卡）');
        expect(payload!.sql, sql, reason: '结果卡携带被执行的 SQL');

        // 重查数据库：已变更（对照组）。
        expect(await readLabel(1), 'gamma', reason: '确认后数据库已变更');
        expect(await readLabel(2), 'beta', reason: 'WHERE 限定未误伤其它行');
      },
    );

    // ----------------------------------------------------------------------
    // R7 互跳：卡「在经典中打开」→ 新 tab 参数 == 送出内容，既有 tab 前后一致
    // ----------------------------------------------------------------------
    testWidgets(
      'R7 open in classic opens new tab with exact sql/context, existing tab untouched',
      (tester) async {
        if (!mysqlE2EGatewayReady) {
          return;
        }
        await pumpWorkbench(tester);

        // 既有 tab 基线（setUp 打开的上下文 tab）。
        final tabsBefore = appProvider.tab.tabs.toList();
        expect(tabsBefore, isNotEmpty);
        final existingTab = tabsBefore.last;
        final existingId = existingTab.id;
        final existingSql = existingTab.sql;
        final existingConnectionId = existingTab.connectionId;
        final existingDatabaseName = existingTab.databaseName;

        const sql = 'SELECT id, label FROM wb_seed WHERE id = 2';
        addAiSqlMessage(sql);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 经 UI 驱动卡「在经典中打开」按钮。
        final openButton = find.byKey(SqlToolCard.openInClassicButtonKey);
        expect(openButton, findsOneWidget);
        await tester.ensureVisible(openButton);
        await tester.tap(openButton);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 新 tab 落位：不覆盖既有 tab（AC7.1），参数 == 送出内容（AC7.3）。
        expect(
          appProvider.tab.tabs.length,
          tabsBefore.length + 1,
          reason: 'AC7.1 互跳落新 tab，不覆盖既有 tab',
        );
        final newTab = appProvider.tab.tabs.last;
        expect(newTab.sql, sql, reason: 'AC7.3 新 tab sql == 送出内容');
        expect(
          newTab.connectionId,
          server.id,
          reason: '新 tab connectionId == 工作台生效上下文连接',
        );
        expect(
          newTab.databaseName,
          testDbName,
          reason: '新 tab databaseName == 工作台生效上下文库',
        );
        expect(
          appProvider.tab.activeTab?.id,
          newTab.id,
          reason: 'activeTab 应切换到新 tab',
        );

        // 既有 tab 前后一致（AC7.1 对照面）。
        final survivors =
            appProvider.tab.tabs.where((t) => t.id == existingId).toList();
        expect(survivors, isNotEmpty, reason: '既有 tab 仍存在');
        final survivor = survivors.first;
        expect(survivor.sql, existingSql, reason: '既有 tab sql 未被改写');
        expect(
          survivor.connectionId,
          existingConnectionId,
          reason: '既有 tab connectionId 未被改写',
        );
        expect(
          survivor.databaseName,
          existingDatabaseName,
          reason: '既有 tab databaseName 未被改写',
        );

        // 互跳出口语义：退出工作台全屏（落点可见）。
        expect(
          appProvider.aiPanelFullscreen,
          isFalse,
          reason: '互跳后应退出工作台全屏',
        );
      },
    );

    // ----------------------------------------------------------------------
    // B1 execution tab：手动混合批「2 成功 INSERT + 1 失败 UPDATE」→
    // execution tab 3 行逐行状态/耗时/影响行数、失败行置顶 + 错误全文可
    // 展开；真库断言两条 INSERT 真生效（v1 §5-3 真库形态）。
    // 影响行数（裁决选项 A detailed 通道，2026-09-26 落地）：写语句经
    // executeQueryDetailed 贯通引擎 affectedRows——两条 INSERT 各报 1 行
    // （chip 文本「1 rows」×2）；失败 UPDATE 行无影响行数 chip（错误行）。
    // ----------------------------------------------------------------------
    testWidgets(
      'B1 execution tab: mixed batch 2 INSERT ok + 1 UPDATE failed lands 3-row tab',
      (tester) async {
        if (!mysqlE2EGatewayReady) {
          return;
        }
        // 专用表（本用例自建；tearDown DROP DATABASE 整库回收）。
        await adapter.useDatabase(testDbName);
        await adapter.createTable('wb_exec', [
          DbColumn(
            name: 'id',
            type: 'INT',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'label', type: 'VARCHAR(100)', isNullable: false),
        ]);
        await pumpWorkbench(tester);
        // B1：批末 execution tab 推送打开舞台 → 收窄对话列卡头测试字体
        // 假性溢出过滤（见 harness 注记）。
        suppressOverflowArtifacts();

        // 三语句混合批：2 成功 INSERT + 1 失败 UPDATE（缺表）。失败 UPDATE
        // 带 WHERE + LIMIT——DML 风险拦截零触发（R6 同款口径），失败来自
        // 真库执行（表不存在），不经 gate #2 确认对话。
        const sql = "INSERT INTO wb_exec (id, label) VALUES (1, 'a');\n"
            "INSERT INTO wb_exec (id, label) VALUES (2, 'b');\n"
            "UPDATE wb_missing SET label = 'x' WHERE id = 1 LIMIT 1";
        addAiSqlMessage(sql);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        final executeButton = find.byKey(SqlToolCard.executeButtonKey);
        expect(executeButton, findsOneWidget, reason: 'SQL 卡应渲染执行按钮');
        await tester.ensureVisible(executeButton);
        await tester.tap(executeButton);
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 500));

        // gate #1 写确认：「Allow this session」一次放行，批内余下写语句免弹。
        final dialogFinder = find.byType(ConfirmExecuteDialog);
        expect(dialogFinder, findsOneWidget, reason: '含写批必弹确认（AC6.1）');
        await tester.tap(
          find.descendant(
            of: dialogFinder,
            matching: find.text('Allow this session'),
          ),
        );

        // 真库往返：轮询等 execution tab 摘要条上屏（失败也含在内——
        // 部分失败不中断，批末推送）。
        final tabLanded = await waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('workbench_execution_summary'))
              .evaluate()
              .isNotEmpty,
        );
        expect(tabLanded, isTrue, reason: '批末应推 execution tab（含写批）');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final stageContent = find.byKey(WorkbenchStage.contentAreaKey);
        expect(stageContent, findsOneWidget, reason: '舞台自动可见');

        // 摘要条：3 语句 · 1 失败 · 总耗时（真库耗时数值不定，断模式不断值）。
        expect(
          find.descendant(
            of: stageContent,
            matching: find.textContaining(
              RegExp(r'^3 statements · 1 failed · \d+ ms$'),
            ),
          ),
          findsOneWidget,
          reason: '摘要条三占位符（总数/失败数/总耗时）',
        );

        // 失败行置顶：展示序第 0 行 = 失败 UPDATE（triangleAlert）。
        final row0 = find.byKey(const ValueKey('workbench_execution_row_0'));
        expect(
          find.descendant(
            of: row0,
            matching: find.text(
              "UPDATE wb_missing SET label = 'x' WHERE id = 1 LIMIT 1",
            ),
          ),
          findsOneWidget,
          reason: '失败行置顶',
        );
        expect(
          find.descendant(
            of: row0,
            matching: find.byIcon(LucideIcons.triangleAlert),
          ),
          findsOneWidget,
        );
        // 两条成功 INSERT 行（circleCheckBig ×2，行文本逐条可辨）。
        expect(
          find.descendant(
            of: stageContent,
            matching: find.byIcon(LucideIcons.circleCheckBig),
          ),
          findsNWidgets(2),
          reason: '两条成功 INSERT 行各持成功图标',
        );
        expect(
          find.descendant(
            of: stageContent,
            matching: find.text("INSERT INTO wb_exec (id, label) VALUES (1, 'a')"),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: stageContent,
            matching: find.text("INSERT INTO wb_exec (id, label) VALUES (2, 'b')"),
          ),
          findsOneWidget,
        );
        // 逐行影响行数（裁决选项 A detailed 通道）：两条成功 INSERT 各报
        // 引擎真值 1（chip 文本「1 rows」×2）；失败 UPDATE 行不显影响行数
        // （错误行无该 chip——全文断言 N=2 而非 3 即覆盖）。
        expect(
          find.descendant(
            of: stageContent,
            matching: find.text('1 rows'),
          ),
          findsNWidgets(2),
          reason: '两条成功 INSERT 逐行显示引擎真值影响行数 1',
        );
        // 逐行耗时（三行各一「N ms」文本）。
        expect(
          find.descendant(
            of: stageContent,
            matching: find.textContaining(RegExp(r'^\d+ ms$')),
          ),
          findsNWidgets(3),
          reason: '三行逐行耗时在位',
        );

        // 失败行「详情」展开 → 错误全文（含缺表名）可见。
        await tester.tap(
          find.byKey(const ValueKey('workbench_execution_detail_0')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(
          find.descendant(
            of: stageContent,
            matching: find.textContaining('wb_missing'),
          ),
          findsWidgets,
          reason: '错误全文可展开且含真实引擎错误（缺表名）',
        );

        // 真库断言「功能真生效」：两条 INSERT 已落库（种子 adapter 独立会话
        // 绕开被测 UI 链路直查）。
        await adapter.useDatabase(testDbName);
        final check = await adapter.executeQuery(
          'SELECT id, label FROM wb_exec ORDER BY id ASC',
        );
        expect(check.rows, hasLength(2), reason: '两条 INSERT 真生效');
        expect(check.rows[0]['label'].toString(), 'a');
        expect(check.rows[1]['label'].toString(), 'b');
      },
    );

    // ----------------------------------------------------------------------
    // R2-3 上下文选择器（T18 欠账，design-ai-workbench §4.2 R2 / AC3.7 形态）：
    // 未设置态 → 点开 WorkbenchContextPicker → 真实连接流程选连接 → 选库
    // 「选择即锁定」→ lock/selected* 同步 → 真实 SELECT 走通执行路径证明
    // 「未设置上下文」拦截解除。
    // ----------------------------------------------------------------------
    testWidgets(
      'R2-3 context picker: real connect locks context and lifts unset-context guard',
      (tester) async {
        if (!mysqlE2EGatewayReady) {
          return;
        }

        // 1. 驱动到真实未设置态（全部走真实 facade 路径）：关掉 setUp 的
        //    上下文 tab（activeTab 源清零）+ 断开连接（currentServer 源清零；
        //    侧栏选中本组从未设置）。三源全空 → resolver 返回 none →
        //    芯片渲染未设置态。断开同时让选择器的选连接动作走完整真实
        //    connectToServer 流程（而非复用既有连接）。
        await appProvider.tab.forceCloseTab(0);
        await appProvider.disconnectConnection(connectionId: server.id);
        await pumpWorkbench(tester);

        expect(appProvider.aiPanel.workbenchContextLock, isNull,
            reason: '前置：无锁定');
        expect(
          find.byKey(const ValueKey('workbench_context_chip_setup')),
          findsOneWidget,
          reason: '三源全空时芯片应渲染未设置态（选择引导出口）',
        );
        expect(appProvider.aiPanel.selectedConnectionId, isNull,
            reason: '未设置态下 AI 生效上下文连接为空（preflight 拦截前置）');
        expect(appProvider.aiPanel.selectedDatabaseName, isNull,
            reason: '未设置态下 AI 生效上下文库为空');

        // 2. 点未设置态的「选择已有连接」出口 → 打开上下文选择器。
        await tester.tap(
          find.byKey(const ValueKey('workbench_context_chip_setup')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(WorkbenchContextPicker), findsOneWidget);

        // 3. 点连接行 → 真实连接流程（adapter 已断开 → picker 内真实
        //    connectToServer + 真实 getDatabases 网关往返）。
        await tester.tap(
          find.byKey(ValueKey('workbench_context_picker_conn_${server.id}')),
        );
        // 真库往返不排帧：轮询等测试库行出现在库栏。
        final dbRowLoaded = await waitUntil(
          tester,
          () => find
              .byKey(ValueKey('workbench_context_picker_db_$testDbName'))
              .evaluate()
              .isNotEmpty,
        );
        expect(dbRowLoaded, isTrue,
            reason: '选连接后应装载出含测试库的真实数据库列表');

        // 4. 点测试库行 →「选择即锁定」→ picker 关闭。
        final dbRow =
            find.byKey(ValueKey('workbench_context_picker_db_$testDbName'));
        await tester.ensureVisible(dbRow);
        await tester.tap(dbRow);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(WorkbenchContextPicker), findsNothing,
            reason: '选择即锁定后选择器应关闭');

        // 5. 锁定断言：lock == (connId, db)，芯片渲染锁定态。
        final lock = appProvider.aiPanel.workbenchContextLock;
        expect(lock, isNotNull, reason: '选库应落 workbench.context 锁定');
        expect(lock?.connectionId, server.id, reason: '锁定连接 == 所选连接');
        expect(lock?.databaseName, testDbName, reason: '锁定库 == 所选库');
        expect(
          find.byKey(const ValueKey('workbench_context_chip_locked_badge')),
          findsOneWidget,
          reason: '芯片应渲染锁定态徽标',
        );

        // 6. selected* 同步（芯片 §5.1 管道把锁定值写为 AI 生效上下文）。
        //    这两个字段正是 chat view _preflight 的上下文入参——由 null 变
        //    为锁定值即「未设置上下文」拦截解除的直接判据。
        final synced = await waitUntil(
          tester,
          () =>
              appProvider.aiPanel.selectedConnectionId == server.id &&
              appProvider.aiPanel.selectedDatabaseName == testDbName,
        );
        expect(synced, isTrue,
            reason: '锁定后同步管道应写 selectedConnectionId/DatabaseName');

        // 7. 守卫解除的端到端证明：R5 同款执行路径。此刻 tab 与 currentServer
        //    均已清空，执行时上下文只能来自锁定快照——真实 SELECT 落
        //    结果卡且数据 == 种子，即全链路（lock → 执行上下文复核 → 网关
        //    真库往返）走通。
        const sql = 'SELECT id, label FROM wb_seed ORDER BY id ASC';
        addAiSqlMessage(sql);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        final executeButton = find.byKey(SqlToolCard.executeButtonKey);
        expect(executeButton, findsOneWidget, reason: 'SQL 卡应渲染执行按钮');
        await tester.ensureVisible(executeButton);
        await tester.tap(executeButton);

        final landed = await waitUntil(tester, () =>
            lastResultCardPayload() != null || lastErrorCardPayload() != null);
        expect(
          landed,
          isTrue,
          reason: '锁定上下文下执行应落卡（错误卡原文：'
              '${lastErrorCardPayload()?.detail}）',
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final payload = lastResultCardPayload();
        expect(payload, isNotNull,
            reason: 'SELECT 应落结果卡（非错误卡）——守卫解除端到端成立');
        expect(payload!.rowCount, 2, reason: '行数 == 种子真实行数');
        expect(payload.columns, ['id', 'label'], reason: '列名 == 种子列序');
        expect(payload.snapshotRows[0]['label'].toString(), 'alpha');
        expect(payload.snapshotRows[1]['label'].toString(), 'beta');
        expect(find.byType(ResultTableCard), findsOneWidget);
      },
    );
  });
}
