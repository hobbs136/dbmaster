// AI 工作台 T10 组件测试（design-ai-workbench §11.1 R1/R2/R9 + §3.1 入口）。
//
// 覆盖：AC1.3 对话为主体 / AC1.1 启动默认经典与进入退出 / AC2.1 发送入流
// / AC2.2 会话流复用 provider / AC2.3 同源 / AC9.1 欢迎态 / AC9.2 加载骨架
// / AC9.3 请求失败错误态 / AC1.6 死页面删除静态断言 / §3.1 footer AI 键
// 进入工作台 / 统计接线（recordEntry / recordSession）。
import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_panel/ai_welcome_state.dart';
import 'package:dbmaster/organisms/ai_panel/confirm_execute_dialog.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_plan_card.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_trajectory_card.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_artifact_strip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_chat_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_footer.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart' show AgentRunContext;
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart'
    show AgentRunStatus;
import 'package:dbmaster/services/ai/agent/agent_plan.dart'
    show
        AgentActionPlan,
        AgentPlanStatus,
        AgentPlanStepInput,
        AgentPlanStepStatus,
        AgentPlanSubmitter;
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show GateCardResult;
import 'package:dbmaster/services/audit_log_service.dart' show AuditLogService;
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';

/// executeQuery 计数桩（T13 shell 级接线验证：卡执行经 shell 注入的编排入口）。
class _CountingAppProvider extends AppProvider {
  int executeCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executeCalls++;
    return Future<List<Map<String, dynamic>>>.value(
      <Map<String, dynamic>>[
        <String, dynamic>{'id': 1},
      ],
    );
  }
}

/// Fix-F ⑤ 用：指定语句执行失败的 executeQuery 桩（制造 partialFailed 边界）。
class _FlakyPlanAppProvider extends AppProvider {
  _FlakyPlanAppProvider({required this.failOn});

  final String failOn;
  final List<String> executed = <String>[];

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executed.add(sql);
    if (sql == failOn) {
      return Future<List<Map<String, dynamic>>>.error(
        Exception('boom: $sql'),
      );
    }
    return Future<List<Map<String, dynamic>>>.value(
      <Map<String, dynamic>>[
        <String, dynamic>{'id': 1},
      ],
    );
  }
}

/// Fix-F ⑥ 用：describe 四件取数 spy（记录连接/库实参，断言快照绑定）。
class _StructureSpyDbService extends DatabaseService {
  String? columnsConnectionId;
  String? columnsDatabaseName;

  @override
  Future<List<DbColumn>> getTableColumns(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    columnsConnectionId = connectionId;
    columnsDatabaseName = databaseName;
    return <DbColumn>[];
  }

  @override
  Future<List<DbIndex>> getTableIndexes(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async => <DbIndex>[];

  @override
  Future<List<ForeignKey>> getForeignKeys(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async => <ForeignKey>[];

  @override
  Future<String> getCreateTableSql(
    String tableName, {
    String? connectionId,
    String? databaseName,
  }) async => '';
}

/// T30 用：`agent_run_end` 终局消息（与 runner `_landTerminal` 落账口径
/// 同构：`toolResultData['agent'] = {kind, runId, status, steps, tokens?,
/// summaryText}`；[tokens] 传 null = tokens 键缺席——runner 用
/// `'tokens': ?tokens` null-aware 入账，提供商未报即缺席）。
AiMessage _runEndMessage(String runId, {required int steps, int? tokens}) =>
    AiMessage(
      id: 'agent_end_$runId',
      isUser: false,
      content: '',
      timestamp: DateTime.now(),
      type: AiMessageType.chat,
      status: AiMessageStatus.completed,
      toolResultSummary: 'Completed · $steps step(s)',
      toolResultData: <String, dynamic>{
        'agent': <String, dynamic>{
          'kind': 'agent_run_end',
          'runId': runId,
          'status': 'completed',
          'steps': steps,
          if (tokens != null) 'tokens': tokens,
          'summaryText': 'Completed · $steps step(s)',
        },
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WorkbenchUsageStatsService.instance.resetForTesting();
    // T28：AgentPlanExecutor 默认审计链（AuditLogService 防抖 Timer）需要
    // 初始化；测试尾用 pump(2s+) 泄放防抖计时器（沿 suggestion test 先例）。
    await AuditLogService().initialize();
  });

  // 统计断言直接读 exportJson 的内存态（recordXxx 同步更新内存）；不在
  // tearDown await flushForTesting——写盘链的 future 在 testWidgets 的
  // fake-async zone 内创建，测试体结束后假时钟冻结，真实 zone 里 await
  // 它会死锁（表现为 "did not complete"）。
  /// 泵工作台壳（独立组件面，不经 z2）。返回所用 AppProvider。
  Future<AppProvider> pumpShell(
    WidgetTester tester, {
    bool enterWorkbench = true,
    Size surface = const Size(1280, 800),
    AppProvider? provider,
  }) async {
    final app = provider ?? AppProvider();
    if (enterWorkbench) {
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
    }
    await tester.binding.setSurfaceSize(surface);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: AiWorkbenchShell()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  group('AiWorkbenchShell 结构（AC1.3 对话为视觉主体）', () {
    testWidgets('对话列 + 输入区 + 退出按钮构成主体', (tester) async {
      await pumpShell(tester);

      expect(find.byType(WorkbenchChatView), findsOneWidget);
      expect(find.byType(AiInputArea), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget, reason: '输入区可达');
      expect(
        find.byKey(const ValueKey('workbench_exit_button')),
        findsOneWidget,
        reason: 'AC1.1 ③ z2 内退出回经典',
      );
      // T11 结构位（本任务不实现，只留挂点）
      expect(
        find.byKey(const ValueKey('workbench_session_rail_slot')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workbench_context_chip_slot')),
        findsOneWidget,
      );
    });

    testWidgets('退出按钮 → setAiPanelFullscreen(false)', (tester) async {
      final app = await pumpShell(tester);
      expect(app.aiPanelFullscreen, isTrue);

      await tester.tap(find.byKey(const ValueKey('workbench_exit_button')));
      await tester.pumpAndSettle();

      expect(app.aiPanelFullscreen, isFalse, reason: '退出回经典模式');
      expect(app.aiPanelOpen, isTrue, reason: 'dock 面板开合状态不被退出改动');
    });

    testWidgets('进入工作台记 entry 统计（§6.4）', (tester) async {
      await pumpShell(tester);

      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      final total = export.dailyEntries.values.fold<int>(0, (a, b) => a + b);
      expect(total, 1, reason: 'open+fs 上升沿记一次 entry');
    });
  });

  group('对话流（AC2.1/2.2/2.3 同源投影）', () {
    testWidgets('AC9.1 空会话 → 欢迎态，示例问题点击填充输入区', (tester) async {
      await pumpShell(tester);

      expect(find.byType(AiWelcomeState), findsOneWidget);

      final l10n = AppLocalizationsEn();
      final question = l10n.aiExampleQuestion1;
      await tester.tap(find.text(question).last);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller?.text,
        question,
        reason: '示例问题填充输入区（可操作引导示例）',
      );
    });

    testWidgets('AC2.1/9.3 发送：用户消息入流 + 守卫失败错误消息不静默', (tester) async {
      final app = await pumpShell(tester);

      await tester.enterText(find.byType(TextField), 'hello workbench');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.send));
      await tester.pumpAndSettle();

      final messages = app.aiMessages;
      expect(messages.length, 2, reason: '用户消息 + 守卫错误消息均入流');
      expect(messages[0].isUser, isTrue);
      expect(messages[0].content, 'hello workbench');
      expect(messages[1].isUser, isFalse);
      expect(
        messages[1].status,
        AiMessageStatus.failed,
        reason: 'AC9.3：请求失败为可辨识错误态，不静默',
      );

      // 首次发送隐式建会话 → recordSession（§6.4 字段 2；exportJson 读内存态）
      final export = WorkbenchUsageStatsService.instance.exportJson(
        appVersion: '0.0.0-test',
      );
      final sessions = export.weeklySessions.values.fold<int>(0, (a, b) => a + b);
      expect(sessions, 1, reason: '工作台内新建会话计数');
    });

    testWidgets('AC2.2 切换会话完整加载历史', (tester) async {
      final app = await pumpShell(tester);
      final service = app.aiPanel.aiConversationService;

      final s1 = service.createSession(title: 'session one');
      app.addAiMessage(
        AiMessage(
          id: 'a1',
          isUser: true,
          content: 'alpha question',
          timestamp: DateTime.now(),
        ),
      );
      service.createSession(title: 'session two');
      app.addAiMessage(
        AiMessage(
          id: 'b1',
          isUser: true,
          content: 'beta question',
          timestamp: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('beta question'), findsOneWidget, reason: '当前会话 s2');

      app.aiPanel.switchSession(s1.id);
      await tester.pumpAndSettle();
      expect(find.text('alpha question'), findsOneWidget);
      expect(find.text('beta question'), findsNothing, reason: '切换后消息流换轨');

      // 继续发送追加到同一会话（AC2.2 后半）：守卫错误路径也落同一会话
      final countBefore = app.aiMessages.length;
      await tester.enterText(find.byType(TextField), 'continue on s1');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.send));
      await tester.pumpAndSettle();
      expect(app.aiMessages.length, countBefore + 2);
      expect(service.currentSession?.id, s1.id, reason: '消息落在当前会话');
    });

    testWidgets('AC2.3 会话同源：工作台消息即经典面板消息（同一 provider）', (tester) async {
      final app = await pumpShell(tester);
      app.aiPanel.ensureSession();
      app.addAiMessage(
        AiMessage(
          id: 'shared-1',
          isUser: true,
          content: 'same ledger message',
          timestamp: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('same ledger message'), findsOneWidget);
      // 经典面板投影读的是同一个 AiPanelProvider（不产生第二本账）
      expect(app.aiMessages.map((m) => m.id), contains('shared-1'));
    });
  });

  group('四态（AC9）', () {
    testWidgets('AC9.2 加载骨架态可渲染（发送中占位，不白屏）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: WorkbenchChatLoading()),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().workbenchLoadingState),
        findsOneWidget,
      );
    });
  });

  group('§3.1 入口：侧栏 footer AI 键进入工作台', () {
    testWidgets('footer AI 键 = setAiPanelOpen(true)+setAiPanelFullscreen(true)', (tester) async {
      final app = AppProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppProvider>.value(value: app),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SidebarFooter(onShowSettings: () {}),
            ),
          ),
        ),
      );

      expect(app.aiPanelOpen, isFalse);
      expect(app.aiPanelFullscreen, isFalse);

      await tester.tap(find.byIcon(LucideIcons.sparkles));
      await tester.pumpAndSettle();

      expect(app.aiPanelOpen, isTrue, reason: 'footer 键打开 AI 面（工作台）');
      expect(app.aiPanelFullscreen, isTrue, reason: 'footer 键进入工作台（fs）');
    });
  });

  group('AC1.6 死代码处置（静态断言）', () {
    test('ai_chat_page.dart 已删除且目录不存留', () {
      expect(
        File('lib/pages/ai_chat/ai_chat_page.dart').existsSync(),
        isFalse,
        reason: 'AC1.6：全项目不存在零引用保留的 ai_chat_page.dart',
      );
      expect(Directory('lib/pages/ai_chat').existsSync(), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T13：卡动作注入 + _allowedWriteServers（design §6.2/§6.5）
  // ──────────────────────────────────────────────────────────────────────────

  group('T13 卡动作注入与写确认会话放行集', () {
    Future<_CountingAppProvider> pumpShellWithCounter(
      WidgetTester tester,
    ) async {
      final app = _CountingAppProvider();
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
      app.aiPanel.ensureSession();
      app.aiPanel.lockWorkbenchContext('conn-1', 'db1');
      app.addAiMessage(
        AiMessage(
          id: 'sql-card-1',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'workbench',
          toolResultData: <String, dynamic>{
            'workbench': const WorkbenchSqlCardPayload(
              sql: "UPDATE users SET name = 'x' WHERE id = 1",
              statementType: 'UPDATE',
              isWrite: true,
            ).toJson(),
          },
          status: AiMessageStatus.completed,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: app,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(body: AiWorkbenchShell()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('SQL 卡「执行」经 shell 注入编排：写 SQL 弹确认，确认后执行', (
      tester,
    ) async {
      final app = await pumpShellWithCounter(tester);
      final l10n = AppLocalizationsEn();
      expect(find.byType(SqlToolCard), findsOneWidget);

      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pump();
      expect(find.byType(ConfirmExecuteDialog), findsOneWidget,
          reason: 'T13 接线生效：卡执行进入写确认编排（非过渡 openQueryTab）');

      await tester.tap(find.text(l10n.aiPanelConfirmExecute));
      await tester.pumpAndSettle();

      expect(app.executeCalls, 1, reason: '确认后真实执行');
      expect(find.byType(ConfirmExecuteDialog), findsNothing);
    });

    testWidgets('allowSession 放行集跨工作台退出/再进保留（§6.5 shell State）', (
      tester,
    ) async {
      final app = await pumpShellWithCounter(tester);
      final l10n = AppLocalizationsEn();

      // 第一次：allowSession → 执行并入集。
      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pump();
      await tester.tap(find.text(l10n.aiPanelAllowSession));
      await tester.pumpAndSettle();
      expect(app.executeCalls, 1);

      // 退出工作台（shell State 不销毁）→ 再进。
      await tester.tap(find.byKey(const ValueKey('workbench_exit_button')));
      await tester.pumpAndSettle();
      expect(app.aiPanelFullscreen, isFalse);
      app.setAiPanelFullscreen(true);
      await tester.pumpAndSettle();

      // 第二次：会话放行集仍在 → 免弹直接执行。
      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pump();
      expect(find.byType(ConfirmExecuteDialog), findsNothing,
          reason: '退出再进，_allowedWriteServers 保留（§6.5）');
      await tester.pumpAndSettle();
      expect(app.executeCalls, 2);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T14：agent 合龙装配（design §2.2 末段 / §4.3 GateCallbacks）
  // ──────────────────────────────────────────────────────────────────────────

  group('T14 agent 合龙装配', () {
    testWidgets('shell 注入 reader 与门卡回调到 chat view', (tester) async {
      final app = await pumpShell(tester);

      // reader 注入（AppProvider 级解析能力闭包化供给 provider 层）。
      expect(app.aiPanel.agentContextSnapshotReader, isNotNull,
          reason: 'run 上下文快照读取器（D15）');
      expect(app.aiPanel.agentChatConfigReader, isNotNull,
          reason: 'chat 配置读取器');

      // 无锁定 / 无 tab / 无侧栏连接 → 快照解析为 null（AC7.4 引导态）。
      expect(app.aiPanel.agentContextSnapshotReader!(), isNull);

      // 门卡回调 + 决策桥注入 chat view（runner 包装层承担落卡/翻转，shell
      // 只供「呈现卡面 + 等决策」的桥）。
      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      expect(view.agentGates, isNotNull);
      expect(view.onGateDecision, isNotNull);
    });

    testWidgets('T14/T-1：锁定连接已删除 → 快照 readOnly 保守取 true', (
      tester,
    ) async {
      final app = await pumpShell(tester);
      app.aiPanel.ensureSession();
      // 锁定到不在 savedConnections 的连接（连接已删除但会话锁定仍指向）。
      app.aiPanel.lockWorkbenchContext('conn-gone', 'db1');
      await tester.pumpAndSettle();

      final snapshot = app.aiPanel.agentContextSnapshotReader!();
      expect(snapshot, isNotNull, reason: '锁定优先：连接已删但快照仍解析');
      expect(snapshot!.connectionId, 'conn-gone');
      expect(snapshot.readOnly, isTrue, reason: 'Fix-B T-1：已删除连接 readOnly 保守 true');
      expect(snapshot.dbType, DatabaseType.mysql, reason: '方言占位语义不变');
    });

    testWidgets('T14/T-1：连接在保存表内 → readOnly 按真实值（保守占位不误伤）', (
      tester,
    ) async {
      final app = await pumpShell(tester);
      app.connection.addSavedServerForTest(
        DbServer(
          id: 'conn-live',
          name: '在档连接',
          type: DatabaseType.postgresql,
          host: '127.0.0.1',
          port: 5432,
          readOnly: false,
        ),
      );
      app.aiPanel.ensureSession();
      app.aiPanel.lockWorkbenchContext('conn-live', 'db1');
      await tester.pumpAndSettle();

      final snapshot = app.aiPanel.agentContextSnapshotReader!();
      expect(snapshot, isNotNull);
      expect(snapshot!.connectionId, 'conn-live');
      expect(snapshot.readOnly, isFalse, reason: '在档连接按真实 readOnly');
      expect(snapshot.dbType, DatabaseType.postgresql, reason: '方言按真实类型');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T27：舞台并置布局装配（ui 规格 §5.1/§5.4-1/2/3）+ port/轨迹卡接线
  // ──────────────────────────────────────────────────────────────────────────

  group('T27 舞台并置布局与装配', () {
    /// 开舞台（产物条左端开关 = 用户可达入口）。
    Future<void> openStage(WidgetTester tester) async {
      await tester.tap(find.byKey(WorkbenchArtifactStrip.toggleKey));
      await tester.pumpAndSettle();
    }

    double railWidth(WidgetTester tester) => tester
        .getSize(find.byKey(const ValueKey('workbench_session_rail_slot')))
        .width;

    double chatColumnWidth(WidgetTester tester) =>
        tester.getSize(find.byType(WorkbenchChatView)).width;

    testWidgets('§5.4-1 1024×768 舞台可见：无 overflow、舞台 ≥480、会话栏 44', (
      tester,
    ) async {
      await pumpShell(tester, surface: const Size(1024, 768));

      // 初始态（M1 零回退）：舞台收起不入树，产物条已常驻。
      expect(find.byType(WorkbenchStage), findsNothing);
      expect(find.byType(WorkbenchArtifactStrip), findsOneWidget);
      final stripBefore = tester.getSize(
        find.byKey(WorkbenchArtifactStrip.stripKey),
      );
      expect(stripBefore.height, 32.0, reason: '产物条高 32 常驻');
      expect(stripBefore.width, 1024.0, reason: '产物条 shell 全宽');

      await openStage(tester);

      expect(tester.takeException(), isNull, reason: '1024×768 并置无 overflow');
      final stage = tester.getSize(find.byType(WorkbenchStage));
      expect(
        stage.width,
        greaterThanOrEqualTo(480),
        reason: '舞台 ≥ workbenchStageMinWidth（1024−44−360=620）',
      );
      expect(stage.width, closeTo(620, 1), reason: '1024 下舞台实得 620（§5.1）');
      expect(railWidth(tester), 44.0, reason: '1024 ≤ 1080 → 会话栏收 44');
      expect(chatColumnWidth(tester), closeTo(360, 1), reason: '对话列恒 360');
    });

    testWidgets('§5.4-2 边界探针：1081 → 会话栏 240；1080 → 收 44（双向）', (
      tester,
    ) async {
      await pumpShell(tester, surface: const Size(1280, 800));
      await openStage(tester);
      expect(railWidth(tester), 240.0, reason: '1280 > 1080 → 会话栏展开 240');

      await tester.binding.setSurfaceSize(const Size(1081, 800));
      await tester.pumpAndSettle();
      expect(railWidth(tester), 240.0, reason: '1081 展开三列和刚好满足');
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(1080, 800));
      await tester.pumpAndSettle();
      expect(railWidth(tester), 44.0, reason: '1080 触发折叠（边界含等号）');
      expect(tester.takeException(), isNull);
      final stage = tester.getSize(find.byType(WorkbenchStage));
      expect(stage.width, greaterThanOrEqualTo(480));
    });

    testWidgets('§5.4-3 舞台收起 → 对话列 360–760 居中；可见 → 恒 360', (
      tester,
    ) async {
      await pumpShell(tester, surface: const Size(1280, 800));

      // 舞台收起：M1 布局（1280 下对话列顶到 760 上限居中）。
      expect(
        chatColumnWidth(tester),
        closeTo(760, 1),
        reason: '舞台收起恢复 M1 360–760（1280 取上限）',
      );

      await openStage(tester);
      expect(chatColumnWidth(tester), closeTo(360, 1), reason: '舞台可见恒 360');

      // 收起开关（展开态图标为收起语义）→ 回 M1。
      await tester.tap(find.byKey(WorkbenchArtifactStrip.toggleKey));
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchStage), findsNothing, reason: '收起后舞台不入树');
      expect(chatColumnWidth(tester), closeTo(760, 1));
    });

    testWidgets('装配断言：chat view 注入 uiPort / 舞台开格回调 / 计划两缝', (
      tester,
    ) async {
      await pumpShell(tester);

      final view = tester.widget<WorkbenchChatView>(find.byType(WorkbenchChatView));
      expect(view.uiPort, isNotNull, reason: 'uiPort 经 shell 下沉注入（T28 接 start）');
      expect(view.onOpenResultInStage, isNotNull, reason: '轨迹卡「在舞台打开」接线');
      expect(view.planResolver, isNotNull, reason: '计划注册表 resolver（T28 落账）');
      expect(view.planBlockBuilder, isNotNull, reason: '计划嵌块渲染器');
    });

    testWidgets('轨迹卡步详情「在舞台打开」→ 舞台开网格 tab（快照重建）', (
      tester,
    ) async {
      final app = await pumpShell(tester);
      app.aiPanel.ensureSession();
      final DateTime now = DateTime.now();
      // 步消息对（executor §5.2 形态）：rowCount 25 > 快照上限 → 截断入口出现。
      app.addAiMessage(
        AiMessage(
          id: 'agent_anchor_run_s1',
          isUser: false,
          content: '',
          timestamp: now,
          type: AiMessageType.toolResult,
          toolName: 'agent_run',
          toolResultSummary: 'Agent run started (step limit 25)',
          toolResultData: <String, dynamic>{
            'agent': <String, dynamic>{
              'kind': 'agent_run',
              'runId': 'run_s1',
              'goal': 'list orders',
              'contextSnapshot': <String, dynamic>{
                'conn': 'conn',
                'db': 'db',
                'readOnly': true,
                'maxSteps': 25,
              },
            },
          },
        ),
      );
      app.addAiMessage(
        AiMessage(
          id: 'agent_tc_run_s1_1',
          isUser: false,
          content: '',
          timestamp: now,
          type: AiMessageType.toolCall,
          toolName: 'execute_readonly_sql',
          toolArguments: <String, dynamic>{
            'sql': 'SELECT id, amount FROM orders',
          },
        ),
      );
      app.addAiMessage(
        AiMessage(
          id: 'agent_tr_run_s1_1',
          isUser: false,
          content: 'queried 25 rows',
          timestamp: now,
          type: AiMessageType.toolResult,
          toolName: 'execute_readonly_sql',
          toolResultSummary: 'queried 25 rows',
          toolResultData: <String, dynamic>{
            'agent': <String, dynamic>{
              'kind': 'agent_step',
              'runId': 'run_s1',
              'stepNo': 1,
              'tool': 'execute_readonly_sql',
              'gateLevel': 'none',
              'gateDecision': 'na',
              'summary': 'queried 25 rows',
              'resultRef': <String, dynamic>{
                'rowCount': 25,
                'columns': <String>['id', 'amount'],
                'snapshotRows': <Map<String, dynamic>>[
                  <String, dynamic>{'id': 1, 'amount': 100},
                  <String, dynamic>{'id': 2, 'amount': 200},
                ],
              },
              'durationMs': 12,
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      // 展开轨迹卡 → 展开步 1 → 点「在舞台打开」。
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentTrajectoryCard.stepRowKey(1)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(AgentTrajectoryCard.openInStageKey(1)),
      );
      await tester.tap(find.byKey(AgentTrajectoryCard.openInStageKey(1)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(WorkbenchStage), findsOneWidget, reason: '舞台入树');
      expect(
        find.byKey(WorkbenchStage.emptyStateKey),
        findsNothing,
        reason: '网格 tab 已开（非空态）',
      );
      expect(
        find.byKey(WorkbenchStage.contentAreaKey),
        findsOneWidget,
        reason: '内容区挂载',
      );
      // 产物条同步呈现该 tab 未钉住（空态常驻一行）。
      expect(
        find.byKey(WorkbenchArtifactStrip.emptyKey),
        findsOneWidget,
        reason: 'openGrid 不钉住（§6.3）',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T28：onPlanApproval 真实现（计划决策桥 + approve/execute 装配 + L1 放行短路）
  // ──────────────────────────────────────────────────────────────────────────

  group('T28 计划决策桥与执行装配', () {
    /// 构造 pendingApproval 计划（T22 submitter 真链）。
    Future<AgentActionPlan> buildPlan(String runId) async {
      final result = await const AgentPlanSubmitter().submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(
            sql: "UPDATE users SET name = 'x' WHERE id = 1",
            rollbackSql: "UPDATE users SET name = 'old' WHERE id = 1",
          ),
        ],
        ctx: AgentRunContext(
          runId: runId,
          connectionId: 'conn-plan',
          connectionName: '计划连接',
          databaseName: 'db1',
          dbType: DatabaseType.mysql,
          readOnly: false,
        ),
      );
      expect(result.ok, isTrue);
      return result.plan!;
    }

    /// 种子消息：轨迹锚点 + runner 包装层形态的 agent_plan 门卡消息
    ///（id = `agent_gc_<runId>_<stepNo>`；planId 由 shell 回填）。
    void seedGateCard(AppProvider app, String runId, int stepNo) {
      app.aiPanel.ensureSession();
      app.addAiMessage(
        AiMessage(
          id: 'agent_anchor_$runId',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'agent_run',
          toolResultData: <String, dynamic>{
            'agent': <String, dynamic>{'kind': 'agent_run', 'runId': runId},
          },
        ),
      );
      app.addAiMessage(
        AiMessage(
          id: 'agent_gc_${runId}_$stepNo',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'agent_plan',
          toolResultData: <String, dynamic>{
            'agent': <String, dynamic>{
              'kind': 'agent_plan',
              'runId': runId,
              'stepNo': stepNo,
            },
          },
        ),
      );
    }

    testWidgets('onPlanApproval：注册表落账 + planId 回填门卡消息 + 等决策',
        (tester) async {
      final app = AppProvider();
      await pumpShell(tester, provider: app);
      final plan = await buildPlan('run-plan-1');
      seedGateCard(app, 'run-plan-1', 0);

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      unawaited(view.agentGates!.onPlanApproval(plan));
      await tester.pumpAndSettle();
      // 折叠态懒构建不渲染门卡块（NF1.1）——展开轨迹卡。
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();

      // 门卡消息已回填 planId（轨迹卡 planResolver 寻址面）。
      final AiMessage gate = app.aiMessages.firstWhere(
        (AiMessage m) => m.id == 'agent_gc_run-plan-1_0',
      );
      expect(
        (gate.toolResultData!['agent'] as Map<String, dynamic>)['planId'],
        plan.planId,
      );
      // 计划卡渲染（注册表解析命中 + 真回调接线 → 批准/拒绝动作在位）。
      expect(find.byKey(AgentPlanCard.approveButtonKey), findsOneWidget);
      expect(find.byKey(AgentPlanCard.rejectButtonKey), findsOneWidget);
      // 未决策：future 未完成，计划仍 pendingApproval。
      expect(plan.status, AgentPlanStatus.pendingApproval);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('批准 → approve + execute（provider facade 执行通道）', (tester) async {
      final app = _CountingAppProvider();
      await pumpShell(tester, provider: app);
      final plan = await buildPlan('run-plan-2');
      seedGateCard(app, 'run-plan-2', 0);

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final Future<GateCardResult> pending = view.agentGates!.onPlanApproval(
        plan,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();

      // 批准前零执行（AC9.1）。
      expect(app.executeCalls, 0);

      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      final GateCardResult result = await pending;
      await tester.pump(const Duration(seconds: 3));

      expect(result, GateCardResult.approved);
      expect(app.executeCalls, 1, reason: '单步计划逐语句执行 1 次');
      expect(plan.status, AgentPlanStatus.done);
      expect(plan.steps.single.runtime.status, AgentPlanStepStatus.done);
    });

    testWidgets('拒绝 → reject 零执行 + PLAN_REJECTED 语义（AC9.2）', (tester) async {
      final app = _CountingAppProvider();
      await pumpShell(tester, provider: app);
      final plan = await buildPlan('run-plan-3');
      seedGateCard(app, 'run-plan-3', 0);

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final Future<GateCardResult> pending = view.agentGates!.onPlanApproval(
        plan,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AgentPlanCard.rejectButtonKey));
      final GateCardResult result = await pending;
      await tester.pump(const Duration(seconds: 3));

      expect(result, GateCardResult.rejected);
      expect(app.executeCalls, 0, reason: '拒绝零执行');
      expect(plan.status, AgentPlanStatus.rejected);
      expect(plan.isConsumed, isTrue);
    });

    testWidgets('终态重放 → execute 防重守卫（PLAN_ALREADY_EXECUTED 语义，AC11.4）',
        (tester) async {
      final app = _CountingAppProvider();
      await pumpShell(tester, provider: app);
      final plan = await buildPlan('run-plan-4');
      seedGateCard(app, 'run-plan-4', 0);

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final Future<GateCardResult> first = view.agentGates!.onPlanApproval(
        plan,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      await first;
      await tester.pump(const Duration(seconds: 3));
      expect(app.executeCalls, 1);
      expect(plan.status, AgentPlanStatus.done);

      // 终态后卡面不再提供批准/拒绝动作（AC11.4「重复触发结果可预期」的
      // 卡层呈现：终态无动作面 = 无重放入口；execute 级 PLAN_ALREADY_EXECUTED
      // 守卫由 T22 agent_plan_test 覆盖）。
      await tester.pumpAndSettle();
      expect(
        find.byKey(AgentPlanCard.approveButtonKey),
        findsNothing,
        reason: '终态无批准动作（重放入口不存在）',
      );
      expect(find.byKey(AgentPlanCard.rejectButtonKey), findsNothing);
      expect(app.executeCalls, 1, reason: '终态后零库操作');
      expect(plan.status, AgentPlanStatus.done);
    });

    testWidgets('L1 会话放行短路（AC9.3）：账本命中 → 免卡直接批准执行', (tester) async {
      final app = _CountingAppProvider();
      await pumpShell(tester, provider: app);
      final plan = await buildPlan('run-plan-5');
      seedGateCard(app, 'run-plan-5', 0);
      app.aiPanel.agentRunner.ledger.allowL1('conn-plan');

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final GateCardResult result = await view.agentGates!.onPlanApproval(plan);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(result, GateCardResult.approvedForSession, reason: '审计判据面');
      expect(app.executeCalls, 1, reason: '免卡仍执行（逐语句审计在执行器内）');
      expect(plan.status, AgentPlanStatus.done);
    });

    testWidgets('Fix-E 勾选路径：卡面勾选「本会话内允许」+ 批准 → '
        'approvedForSession + ledger.allowL1 落账（AC9.3 授予入口）', (tester) async {
      final app = _CountingAppProvider();
      await pumpShell(tester, provider: app);
      final plan = await buildPlan('run-plan-6');
      seedGateCard(app, 'run-plan-6', 0);
      // 前置：账本未放行（走卡，不短路）。
      expect(
        app.aiPanel.agentRunner.ledger.l1Allowed.contains('conn-plan'),
        isFalse,
      );

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final Future<GateCardResult> pending = view.agentGates!.onPlanApproval(
        plan,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();

      // 勾选「本会话内允许」→ 批准（回调携带 forSession=true）。
      await tester.tap(find.byKey(AgentPlanCard.sessionCheckboxKey));
      await tester.pump();
      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      final GateCardResult result = await pending;
      await tester.pump(const Duration(seconds: 3));

      expect(result, GateCardResult.approvedForSession, reason: '勾选态翻转决策');
      expect(app.executeCalls, 1, reason: '批准即执行（单步计划逐语句 1 次）');
      expect(plan.status, AgentPlanStatus.done);
      // ledger.allowL1 落账（T28 链路面）：本连接后续 L1 计划免卡（AC9.3）。
      expect(
        app.aiPanel.agentRunner.ledger.l1Allowed.contains('conn-plan'),
        isTrue,
        reason: '会话放行已落账',
      );
    });
  });

  group('Fix-F ② 停止×计划竞态探针（agentPlanExecutionMayContinue）', () {
    test('桥路径（bindRunnerStop=true）：stopping/stoppedByUser → 中止，其余放行', () {
      for (final AgentRunStatus status in AgentRunStatus.values) {
        final bool may = agentPlanExecutionMayContinue(
          mounted: true,
          bindRunnerStop: true,
          runnerStatus: status,
        );
        final bool stopping =
            status == AgentRunStatus.stopping ||
            status == AgentRunStatus.stoppedByUser;
        expect(
          may,
          !stopping,
          reason: '桥路径下 $status 应${stopping ? '中止' : '放行'}',
        );
      }
    });

    test('直接路径（bindRunnerStop=false）：任何 runner 状态放行（回退在 run 结束后可用）', () {
      for (final AgentRunStatus status in AgentRunStatus.values) {
        expect(
          agentPlanExecutionMayContinue(
            mounted: true,
            bindRunnerStop: false,
            runnerStatus: status,
          ),
          isTrue,
          reason: '直接路径不绑停止态（$status 放行）',
        );
      }
    });

    test('壳卸载（mounted=false）恒中止（既有语义不回归）', () {
      expect(
        agentPlanExecutionMayContinue(
          mounted: false,
          bindRunnerStop: false,
          runnerStatus: AgentRunStatus.idle,
        ),
        isFalse,
      );
      expect(
        agentPlanExecutionMayContinue(
          mounted: false,
          bindRunnerStop: true,
          runnerStatus: AgentRunStatus.awaitingUser,
        ),
        isFalse,
      );
    });
  });

  group('Fix-F ⑤⑥ 计划链修复（直接路径落账 + 快照绑定）', () {
    /// 种子门卡消息（同 T28 组形态）。
    void seedGateCard(AppProvider app, String runId, int stepNo) {
      app.aiPanel.ensureSession();
      app.addAiMessage(
        AiMessage(
          id: 'agent_anchor_$runId',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'agent_run',
          toolResultData: <String, dynamic>{
            'agent': <String, dynamic>{'kind': 'agent_run', 'runId': runId},
          },
        ),
      );
      app.addAiMessage(
        AiMessage(
          id: 'agent_gc_${runId}_$stepNo',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'agent_plan',
          toolResultData: <String, dynamic>{
            'agent': <String, dynamic>{
              'kind': 'agent_plan',
              'runId': runId,
              'stepNo': stepNo,
            },
          },
        ),
      );
    }

    testWidgets('⑤：回退计划卡勾选「本会话内允许」+ 批准（直接路径）→ '
        'ledger.allowL1 落账 + 回退执行（与桥路径一致，AC9.3）', (tester) async {
      final app = _FlakyPlanAppProvider(
        failOn: "UPDATE users SET name = 'x' WHERE id = 7",
      );
      await pumpShell(tester, provider: app);
      // 源计划：step1 INSERT（模型回退 DELETE）+ step2 UPDATE（执行失败）。
      final submitResult = await const AgentPlanSubmitter().submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(
            sql: "INSERT INTO users (id, name) VALUES (7, 'z')",
            rollbackSql: 'DELETE FROM users WHERE id = 7',
          ),
          AgentPlanStepInput(
            sql: "UPDATE users SET name = 'x' WHERE id = 7",
            irreversible: true,
          ),
        ],
        ctx: AgentRunContext(
          runId: 'run-plan-rb',
          connectionId: 'conn-plan',
          connectionName: '计划连接',
          databaseName: 'db1',
          dbType: DatabaseType.mysql,
          readOnly: false,
        ),
      );
      expect(submitResult.ok, isTrue);
      final AgentActionPlan plan = submitResult.plan!;
      seedGateCard(app, 'run-plan-rb', 0);
      expect(
        app.aiPanel.agentRunner.ledger.l1Allowed.contains('conn-plan'),
        isFalse,
        reason: '前置：账本未放行',
      );

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final Future<GateCardResult> pending = view.agentGates!.onPlanApproval(
        plan,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();

      // 桥路径批准（不勾选）→ step2 失败 → partialFailed 边界。
      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      final GateCardResult r1 = await pending;
      await tester.pump(const Duration(seconds: 3));
      expect(r1, GateCardResult.approved);
      expect(plan.status, AgentPlanStatus.partialFailed);

      // 生成回退计划（点击只组装不执行，AC11.3）。按钮在卡体滚动区内，
      // 先 ensureVisible 再点（不可命中时 tap 只告警不触发）。
      await tester.ensureVisible(
        find.byKey(AgentPlanCard.generateRollbackButtonKey),
      );
      await tester.tap(find.byKey(AgentPlanCard.generateRollbackButtonKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(plan.status, AgentPlanStatus.rollbackOffered);
      expect(
        app.executed,
        isNot(contains('DELETE FROM users WHERE id = 7')),
        reason: '组装零执行',
      );

      // 回退计划卡：勾选「本会话内允许」+ 批准 → 直接路径（决策桥已随源
      // 计划决策移除——回退计划经合成门卡渲染，无桥条目）。
      await tester.ensureVisible(
        find.byKey(AgentPlanCard.sessionCheckboxKey),
      );
      await tester.tap(find.byKey(AgentPlanCard.sessionCheckboxKey));
      await tester.pump();
      await tester.ensureVisible(find.byKey(AgentPlanCard.approveButtonKey));
      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      // Fix-F ⑤ 主断言：直接路径 approvedForSession 同样落账。
      expect(
        app.aiPanel.agentRunner.ledger.l1Allowed.contains('conn-plan'),
        isTrue,
        reason: '直接路径勾选批准 → allowL1 落账（与桥路径一致）',
      );
      // 回退执行：模型逆语句 DELETE 经执行通道触达。
      expect(app.executed, contains('DELETE FROM users WHERE id = 7'));
      expect(
        find.text(AppLocalizationsEn().agentPlanStatusDone),
        findsOneWidget,
        reason: '回退计划卡呈 done',
      );
    });

    testWidgets('⑥：结构取数绑 run 启动快照（D15）——点击时锁定漂移不进取数', (
      tester,
    ) async {
      final _StructureSpyDbService db = _StructureSpyDbService();
      final app = AppProvider(
        connectionProvider: ConnectionProvider(dbService: db),
      );
      await pumpShell(tester, provider: app);
      app.aiPanel.ensureSession();
      // run 启动快照解析（= runner start 的 D15 挂点；reader 由 shell 注入
      // didChangeDependencies）：锁定 conn_a/db_a 时取快照。
      app.aiPanel.lockWorkbenchContext('conn_a', 'db_a');
      app.aiPanel.agentContextSnapshotReader?.call();
      // 点击时上下文漂移（锁定变更）——run 内取数不得跟随。
      app.aiPanel.lockWorkbenchContext('conn_b', 'db_b');

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final outcome = await view.uiPort!.showTableStructure('orders');
      await tester.pumpAndSettle();

      expect(outcome.ok, isTrue, reason: '结构取数成功: ${outcome.message}');
      expect(
        db.columnsConnectionId,
        'conn_a',
        reason: '取数绑 run 启动快照（D15），不随锁定漂移',
      );
      expect(db.columnsDatabaseName, 'db_a');
    });
  });

  group('T30 会话累计 chip（AC3.2）', () {
    /// AC3.2 对账口径：从当前会话终局消息重推累计（测试独立实现，不引用
    /// 壳内私有聚合），chip 呈现值必须与之逐字一致。
    (int, int) reconcileTerminalTotals(AppProvider app) {
      int tokens = 0;
      int steps = 0;
      for (final AiMessage message in app.aiMessages) {
        final Object? agent = message.toolResultData?['agent'];
        if (agent is! Map<String, dynamic>) continue;
        if (agent['kind'] != 'agent_run_end') continue;
        tokens += (agent['tokens'] as num?)?.toInt() ?? 0;
        steps += (agent['steps'] as num?)?.toInt() ?? 0;
      }
      return (tokens, steps);
    }

    testWidgets('多 run 会话累计正确：tokens 求和 + 步数合计，与终局消息对账一致', (
      tester,
    ) async {
      final app = await pumpShell(tester);
      final service = app.aiPanel.aiConversationService;
      service.createSession(title: 'token session');
      app.addAiMessage(_runEndMessage('r1', steps: 5, tokens: 1200));
      app.addAiMessage(_runEndMessage('r2', steps: 3, tokens: 2340));
      // 噪声消息：非 agent 消息与 agent 非 run_end 消息不得进入累计。
      app.addAiMessage(
        AiMessage(
          id: 'plain-user',
          isUser: true,
          content: 'plain question',
          timestamp: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      // AC3.2 对账断言：chip 值 = 终局消息重推值。
      final (tokens, steps) = reconcileTerminalTotals(app);
      expect(tokens, 3540, reason: '1200 + 2340');
      expect(steps, 8, reason: '5 + 3');
      expect(
        find.byKey(const ValueKey('workbench_session_tokens_chip')),
        findsOneWidget,
      );
      // compact(3540) = '3.5k'（agentTrajectoryCompactTokens 口径）。
      expect(find.text('Session 3.5k tok · Steps: 8'), findsOneWidget);
    });

    testWidgets('tokens 缺席的 run 不计入求和；其步数仍计入', (tester) async {
      final app = await pumpShell(tester);
      final service = app.aiPanel.aiConversationService;
      service.createSession(title: 'partial usage');
      app.addAiMessage(_runEndMessage('r1', steps: 5, tokens: 1000));
      app.addAiMessage(_runEndMessage('r2', steps: 2));
      await tester.pumpAndSettle();

      // 对账：r2 无 tokens 键 → 不计入 token 和（不加 0 占位也不降级整 chip）。
      final (tokens, steps) = reconcileTerminalTotals(app);
      expect(tokens, 1000);
      expect(steps, 7, reason: 'steps 恒有值，缺席 tokens 的 run 仍计步');
      expect(find.text('Session 1.0k tok · Steps: 7'), findsOneWidget);
    });

    testWidgets('空会话 → chip 隐藏', (tester) async {
      await pumpShell(tester);
      expect(
        find.byKey(const ValueKey('workbench_session_tokens_chip')),
        findsNothing,
        reason: '无任何含 tokens 的 run → 整 chip 不渲染（零态自决）',
      );
    });

    testWidgets('run 均无 tokens 键 → chip 隐藏（AC3.4 降级同源）', (tester) async {
      final app = await pumpShell(tester);
      final service = app.aiPanel.aiConversationService;
      service.createSession(title: 'no usage');
      app.addAiMessage(_runEndMessage('r1', steps: 5));
      app.addAiMessage(_runEndMessage('r2', steps: 2));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workbench_session_tokens_chip')),
        findsNothing,
      );
    });

    testWidgets('切换会话重算：chip 随当前会话终局消息重投影', (tester) async {
      final app = await pumpShell(tester);
      final service = app.aiPanel.aiConversationService;
      final heavy = service.createSession(title: 'heavy');
      app.addAiMessage(_runEndMessage('r1', steps: 5, tokens: 1200));
      app.addAiMessage(_runEndMessage('r2', steps: 3, tokens: 2340));
      final light = service.createSession(title: 'light');
      app.addAiMessage(_runEndMessage('r3', steps: 2, tokens: 500));
      await tester.pumpAndSettle();

      expect(
        find.text('Session 500 tok · Steps: 2'),
        findsOneWidget,
        reason: '当前会话 light',
      );

      app.aiPanel.switchSession(heavy.id);
      await tester.pumpAndSettle();
      expect(find.text('Session 3.5k tok · Steps: 8'), findsOneWidget);

      // 切到全新空会话 → 隐藏（重算含零态）。
      service.createSession(title: 'empty');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workbench_session_tokens_chip')),
        findsNothing,
      );

      // 切回 light → 恢复该会话的累计（非单向缓存）。
      app.aiPanel.switchSession(light.id);
      await tester.pumpAndSettle();
      expect(find.text('Session 500 tok · Steps: 2'), findsOneWidget);
    });
  });
}
