// AI 工作台 T10 组件测试（design-ai-workbench §11.1 R1/R2/R9 + §3.1 入口）。
//
// 覆盖：AC1.3 对话为主体 / AC1.1 启动默认经典与进入退出 / AC2.1 发送入流
// / AC2.2 会话流复用 provider / AC2.3 同源 / AC9.1 欢迎态 / AC9.2 加载骨架
// / AC9.3 请求失败错误态 / AC1.6 死页面删除静态断言 / §3.1 footer AI 键
// 进入工作台 / 统计接线（recordEntry / recordSession）。
import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/molecules/resizer_widgets.dart'
    show EditorResultsResizer;
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/workbench_entry_intent.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_panel/ai_welcome_state.dart';
import 'package:dbmaster/organisms/ai_panel/confirm_execute_dialog.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_plan_card.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_trajectory_card.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_table_card.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_artifact_strip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_chat_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_session_list_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_footer.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentRunContext;
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
import 'package:dbmaster/theme/design_system.dart';

/// executeQueryDetailed 计数桩（T13 shell 级接线验证：卡执行经 shell 注入的
/// 编排入口。裁决选项 A 起工作台执行走 detailed 通道）。
class _CountingAppProvider extends AppProvider {
  int executeCalls = 0;

  @override
  Future<QueryExecutionResult> executeQueryDetailed(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executeCalls++;
    return Future<QueryExecutionResult>.value(
      QueryExecutionResult(<Map<String, dynamic>>[
        <String, dynamic>{'id': 1},
      ]),
    );
  }
}

/// Fix-F ⑤ 用：指定语句执行失败的 executeQueryDetailed 桩（制造
/// partialFailed 边界）。
class _FlakyPlanAppProvider extends AppProvider {
  _FlakyPlanAppProvider({required this.failOn});

  final String failOn;
  final List<String> executed = <String>[];

  @override
  Future<QueryExecutionResult> executeQueryDetailed(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) {
    executed.add(sql);
    if (sql == failOn) {
      return Future<QueryExecutionResult>.error(Exception('boom: $sql'));
    }
    return Future<QueryExecutionResult>.value(
      QueryExecutionResult(<Map<String, dynamic>>[
        <String, dynamic>{'id': 1},
      ]),
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
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          // B3：shell 舞台布局段消费对话列持久化宽度（与 main.dart 同款装配）。
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
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  /// B1 适配：安装「卡头测试字体假性溢出」过滤器——写批/计划执行完成 →
  /// execution tab 推送打开舞台 → 对话列收窄 → SQL 卡四动作钮 header /
  /// 计划卡步行在测试字体（Ahem 方块字）下溢出（真机字体放得下 520 档；
  /// 360–430 窄档的真实溢出属既有卡头缺陷，与断言语义无关，已登记遗留
  /// 项——B2 组 1920 注记同款伪影，但 SQL 卡内容更宽、1920 也放不下，
  /// 只能过滤）。
  ///
  /// 仅吞咽 `RenderFlex overflowed` 类报告，其余 FlutterError 原样转交
  /// 既有处理器（不失掩）；addTearDown 恢复原处理器。
  /// （不用 takeException 吞咽：同一帧可能记录多条 overflow，flutter_test
  /// 会把多条合并成「Multiple exceptions」wrapper（binding.dart:1514），
  /// 成分无法反解。）
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
      expect(field.controller?.text, question, reason: '示例问题填充输入区（可操作引导示例）');
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
      final sessions = export.weeklySessions.values.fold<int>(
        0,
        (a, b) => a + b,
      );
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
    testWidgets(
      'footer AI 键 = setAiPanelOpen(true)+setAiPanelFullscreen(true)',
      (tester) async {
        final app = AppProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppProvider>.value(value: app),
              ChangeNotifierProvider<ThemeProvider>.value(
                value: ThemeProvider(),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(body: SidebarFooter(onShowSettings: () {})),
            ),
          ),
        );

        expect(app.aiPanelOpen, isFalse);
        expect(app.aiPanelFullscreen, isFalse);

        await tester.tap(find.byIcon(LucideIcons.sparkles));
        await tester.pumpAndSettle();

        expect(app.aiPanelOpen, isTrue, reason: 'footer 键打开 AI 面（工作台）');
        expect(app.aiPanelFullscreen, isTrue, reason: 'footer 键进入工作台（fs）');
      },
    );
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
        // B1 适配：写批执行完成 → execution tab 推送打开舞台 → 舞台布局段
        // 消费 LayoutPreferencesProvider（B3）——本组树补齐该 provider（与
        // main.dart / pumpShell 同款装配）。
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppProvider>.value(value: app),
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
        ),
      );
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('SQL 卡「执行」经 shell 注入编排：写 SQL 弹确认，确认后执行', (tester) async {
      final app = await pumpShellWithCounter(tester);
      final l10n = AppLocalizationsEn();
      // B1：执行完成 → execution tab 打开舞台 → 卡头测试字体假性溢出过滤
      //（见 suppressOverflowArtifacts 注记）。
      suppressOverflowArtifacts();
      expect(find.byType(SqlToolCard), findsOneWidget);

      await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
      await tester.pump();
      expect(
        find.byType(ConfirmExecuteDialog),
        findsOneWidget,
        reason: 'T13 接线生效：卡执行进入写确认编排（非过渡 openQueryTab）',
      );

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
      suppressOverflowArtifacts(); // B1：同上（舞台打开后卡头伪影）

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
      expect(
        find.byType(ConfirmExecuteDialog),
        findsNothing,
        reason: '退出再进，_allowedWriteServers 保留（§6.5）',
      );
      await tester.pumpAndSettle();
      expect(app.executeCalls, 2, reason: '二次执行真实发生');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T14：agent 合龙装配（design §2.2 末段 / §4.3 GateCallbacks）
  // ──────────────────────────────────────────────────────────────────────────

  group('T14 agent 合龙装配', () {
    testWidgets('shell 注入 reader 与门卡回调到 chat view', (tester) async {
      final app = await pumpShell(tester);

      // reader 注入（AppProvider 级解析能力闭包化供给 provider 层）。
      expect(
        app.aiPanel.agentContextSnapshotReader,
        isNotNull,
        reason: 'run 上下文快照读取器（D15）',
      );
      expect(
        app.aiPanel.agentChatConfigReader,
        isNotNull,
        reason: 'chat 配置读取器',
      );

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

    testWidgets('T14/T-1：锁定连接已删除 → 快照 readOnly 保守取 true', (tester) async {
      final app = await pumpShell(tester);
      app.aiPanel.ensureSession();
      // 锁定到不在 savedConnections 的连接（连接已删除但会话锁定仍指向）。
      app.aiPanel.lockWorkbenchContext('conn-gone', 'db1');
      await tester.pumpAndSettle();

      final snapshot = app.aiPanel.agentContextSnapshotReader!();
      expect(snapshot, isNotNull, reason: '锁定优先：连接已删但快照仍解析');
      expect(snapshot!.connectionId, 'conn-gone');
      expect(
        snapshot.readOnly,
        isTrue,
        reason: 'Fix-B T-1：已删除连接 readOnly 保守 true',
      );
      expect(snapshot.dbType, DatabaseType.mysql, reason: '方言占位语义不变');
    });

    testWidgets('T14/T-1：连接在保存表内 → readOnly 按真实值（保守占位不误伤）', (tester) async {
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
    /// 开舞台（产物条左端展开钮 = 收起态用户可达入口；走查修复批件①后
    /// 展开态收起改走舞台 tab 条右端收起钮）。
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

    testWidgets('§5.4-2 边界探针：1081 → 会话栏 240；1080 → 收 44（双向）', (tester) async {
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

    testWidgets('§5.4-3 舞台收起 → 对话列吃满 region；可见 → 弹性 [360,520]', (tester) async {
      // AI-CW 批（2026-09-29）：收起态列宽 = region 恒等（rail 240；原 M1
      // 760 居中封顶退役）。全档 takeException 全 null。
      await pumpShell(tester, surface: const Size(1280, 800));

      // 舞台收起：1280 − 240 = 1040（吃满，不再 760 封顶）。
      expect(
        chatColumnWidth(tester),
        closeTo(1040, 1),
        reason: '收起态列宽 = region 恒等（1280−240=1040，AI-CW 吃满）',
      );

      await openStage(tester);
      expect(
        chatColumnWidth(tester),
        closeTo(374.4, 1),
        reason: '舞台可见弹性分配：1040×0.36=374.4 ∈ [360,520]（走查缺陷修复）',
      );

      // 收起（舞台 tab 条右端收起钮——走查修复批件①入口移位）→ 回吃满。
      await tester.tap(find.byKey(WorkbenchStage.collapseKey));
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchStage), findsNothing, reason: '收起后舞台不入树');
      expect(chatColumnWidth(tester), closeTo(1040, 1));

      // 收起态吃满多档锁死（region 恒等三档：1024/1440/1920，AI-CW 批；
      // 原「1920 仍 760 封顶」断言随批退役）。
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      await tester.pumpAndSettle();
      expect(chatColumnWidth(tester), closeTo(784, 1), reason: '1024−240=784');
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await tester.pumpAndSettle();
      expect(
        chatColumnWidth(tester),
        closeTo(1200, 1),
        reason: '1440−240=1200',
      );
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      await tester.pumpAndSettle();
      expect(
        chatColumnWidth(tester),
        closeTo(1680, 1),
        reason: '1920−240=1680（吃满）',
      );
      expect(tester.takeException(), isNull);

      // 切换回归三段（B3 不变式：舞台不自动收起/展开）：1920 收起（已在此档）
      // → 开舞台弹性 clamp → 收起回 1680，全程无 overflow。
      await openStage(tester);
      expect(find.byType(WorkbenchStage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(WorkbenchStage.collapseKey));
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchStage), findsNothing);
      expect(chatColumnWidth(tester), closeTo(1680, 1), reason: '收起回程仍吃满 1680');
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI-CW：收起态气泡内层 cap（1920 触发 640 / 1024 边界 623.2 不触发）、SQL/结果卡吃满 >760', (
      tester,
    ) async {
      final app = await pumpShell(tester, surface: const Size(1920, 1080));
      app.aiPanel.ensureSession();
      final now = DateTime.now();
      // 纯文本长 markdown 消息（CardHost 不拦截 → AiMessageItem 气泡路径）。
      // 20 段重复（≈560 字符，Ahem 定宽下意图宽远超 640 → cap 生效）；
      // 刻意不过长——气泡矮于视口，SQL 卡留在同屏可见区（ListView 懒构建）。
      app.addAiMessage(
        AiMessage(
          id: 'cw_text_msg',
          isUser: false,
          content: List<String>.filled(
            20,
            'lorem ipsum dolor sit amet',
          ).join(' '),
          timestamp: now,
        ),
      );
      // SQL 代码块消息（CardHost ② 拦截 → SqlToolCard，不受气泡约束）。
      app.addAiMessage(
        AiMessage(
          id: 'cw_sql_msg',
          isUser: false,
          content: '',
          timestamp: now,
          code: 'SELECT id, name, email FROM users ORDER BY id;',
        ),
      );
      await tester.pumpAndSettle();

      // 收起态 region = 1920−240 = 1680；气泡 0.82×(1680−24) ≈ 1358 > 640
      // → min 次序 cap 生效。
      final bubble = find.descendant(
        of: find.byType(AiMessageItem),
        matching: find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 640.0,
        ),
      );
      expect(bubble, findsOneWidget, reason: '气泡 ConstrainedBox 唯一命中 cap=640');
      expect(
        tester.getSize(bubble).width,
        lessThanOrEqualTo(640),
        reason: '长文本气泡实得 ≤ 640 可读宽封顶',
      );

      // SQL 卡走 CardHost 路径（气泡外），吃满列宽：1680−24=1656 > 760。
      final cardSize = tester.getSize(find.byType(SqlToolCard));
      expect(cardSize.width, greaterThan(760), reason: 'SQL 卡吃满列宽（证卡不经气泡 cap）');
      expect(tester.takeException(), isNull);

      // 1024 边界（验收 3，min 次序防反）：region = 1024−240 = 784，消息区
      // 减列表横向 padding 24（space3×2）= 760 → 气泡 = 0.82×760 = 623.2 <
      // 640，cap 不触发（与旧版 760 封顶列内 0.82×760 行长持平——跨态零跳
      // 变）；实现若误写 max 则实得 640，本断言必失败。
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      await tester.pumpAndSettle();
      final bubbleBoundary = find.descendant(
        of: find.byType(AiMessageItem),
        matching: find.byWidgetPredicate(
          (w) =>
              w is ConstrainedBox &&
              (w.constraints.maxWidth - 623.2).abs() < 1.0,
        ),
      );
      expect(
        bubbleBoundary,
        findsOneWidget,
        reason: '1024 档气泡约束 = 0.82×(784−24)=623.2，cap 不触发（min 次序守卫）',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('装配断言：chat view 注入 uiPort / 舞台开格回调 / 计划两缝', (tester) async {
      await pumpShell(tester);

      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      expect(
        view.uiPort,
        isNotNull,
        reason: 'uiPort 经 shell 下沉注入（T28 接 start）',
      );
      expect(view.onOpenResultInStage, isNotNull, reason: '轨迹卡「在舞台打开」接线');
      expect(view.planResolver, isNotNull, reason: '计划注册表 resolver（T28 落账）');
      expect(view.planBlockBuilder, isNotNull, reason: '计划嵌块渲染器');
    });

    testWidgets('轨迹卡步详情「在舞台打开」→ 舞台开网格 tab（快照重建）', (tester) async {
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
  // v2 A2：收窄态会话路由（R6 接缝）——shell 把 _stageController 传入 rail，
  // 收窄态活动条点会话图标 → rail 直调 controller.openSessions()（舞台
  // sessionList 单例 tab）。1024 下收窄态前置 = 舞台可见（1024 ≤ 1080 三列
  // 断点，§5.4-1 探针）；舞台不可见 → 自动可见的转换断言由
  // workbench_session_rail_test.dart / workbench_stage_test.dart 的
  // openSessions 用例以新 controller 承载。
  // ──────────────────────────────────────────────────────────────────────────

  group('v2 A2 收窄态会话路由（R6 接缝）', () {
    /// 开舞台（产物条左端展开钮 = 收起态用户可达入口；走查修复批件①后
    /// 展开态收起改走舞台 tab 条右端收起钮）。
    Future<void> openStage(WidgetTester tester) async {
      await tester.tap(find.byKey(WorkbenchArtifactStrip.toggleKey));
      await tester.pumpAndSettle();
    }

    testWidgets('1024 收窄态点会话图标 → 舞台自动可见 + sessionList tab 激活；重复点击 tab 恒 1', (
      tester,
    ) async {
      await pumpShell(tester, surface: const Size(1024, 768));

      // 收窄态前置：开舞台 → 1024 ≤ 1080 → 会话栏收 44（§5.4-1 既有探针）。
      await openStage(tester);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('workbench_session_rail_slot')))
            .width,
        AppDesignSystem.workbenchRailActivityBarWidth,
        reason: '1024 舞台可见 → 会话栏收窄态（活动条 44）',
      );

      // 收窄态点会话图标 → R6 接缝：rail 直调 stageController.openSessions()。
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();

      final stage = tester.widget<WorkbenchStage>(find.byType(WorkbenchStage));
      expect(stage.controller.stageVisible, isTrue, reason: '舞台自动可见');
      expect(stage.controller.tabs.map((t) => t.kind), [
        WorkbenchStageTabKind.sessionList,
      ], reason: 'sessionList 单例 tab 落地');
      expect(
        stage.controller.activeTab?.kind,
        WorkbenchStageTabKind.sessionList,
        reason: 'sessionList tab 激活',
      );
      // v2 §8-5：舞台 tab 全宽形态渲染同一共享组件。
      expect(find.byType(SessionListView), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 重复点击 → 复用激活，tab 恒 1（§8-2）。
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();
      expect(stage.controller.tabs, hasLength(1));
      expect(
        stage.controller.activeTab?.kind,
        WorkbenchStageTabKind.sessionList,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // A5（v2 §8-6）：F6/Shift+F6 六区轮转——壳根 Focus 冒泡承接（R10 不碰
  // 全局层），未注册区（舞台收起 / rail 收窄）动态跳过；六区 = 活动条 /
  // rail 内容页 / 对话列 / 舞台 tab 条 / 舞台内容 / 产物条。
  // 区识别面：活动条图标与 rail 槽走 keyed 元素祖先链；舞台 tab 条与产物条
  // 条目走焦点节点 debugLabel（itemKey 的 AnimatedContainer 在 Focus 后代
  // 方向，祖先链不可达——沿 strip/stage 组件测试同款 debugLabel 口径）；
  // 对话列 = 唯一 EditableText 的焦点节点。
  // ──────────────────────────────────────────────────────────────────────────

  group('A5 F6 六区轮转（v2 §8-6）', () {
    final l10n = AppLocalizationsEn();

    /// 成对发送按下/抬起（AGENTS.md §8-10：缺抬起触发 HardwareKeyboard 断言）。
    Future<void> pressF6(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f6);
    }

    /// Shift+F6（修饰键释放顺序与按下相反——AGENTS.md §8-10）。
    Future<void> pressShiftF6(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }

    /// 主焦点是否落在 [key] 元素（或其后代）内。
    bool focusWithinAnyKey(Key key) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return false;
      for (final Element keyed in find.byKey(key).evaluate()) {
        if (identical(ctx, keyed)) return true;
        var found = false;
        (ctx as Element).visitAncestorElements((ancestor) {
          if (identical(ancestor, keyed)) {
            found = true;
            return false;
          }
          return true;
        });
        if (found) return true;
      }
      return false;
    }

    /// 主焦点当前所在区（轮转断言的识别面；顺序敏感——活动条图标是 rail
    /// 槽后代，先判活动条）。
    String? zoneOfFocus(WidgetTester tester) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null) return null;
      final label = focus.debugLabel ?? '';
      if (label.startsWith('artifact_item_')) return 'artifactStrip';
      if (label.startsWith('stage_tab_')) return 'stageTabBar';
      if (focusWithinAnyKey(const ValueKey('workbench_activity_sessions'))) {
        return 'activityBar';
      }
      if (focusWithinAnyKey(const ValueKey('workbench_session_rail_slot'))) {
        return 'railContentPage';
      }
      if (focusWithinAnyKey(WorkbenchStage.contentAreaKey)) {
        return 'stageContent';
      }
      for (final EditableText editable in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        if (identical(focus, editable.focusNode)) return 'chatColumn';
      }
      return null;
    }

    /// 起点确定化：焦点放回对话列输入区（AC1.2 进入态等价；区下标起点 =
    /// chatColumn，首个 F6 → 舞台 tab 条）。输入区 = 壳内唯一 TextField。
    Future<void> refocusChatInput(WidgetTester tester) async {
      final TextField input = tester.widget<TextField>(find.byType(TextField));
      final FocusNode? node = input.focusNode;
      expect(node, isNotNull, reason: '对话列输入区持有焦点节点');
      node!.requestFocus();
      await tester.pump();
    }

    /// 六区齐备前置：880 收窄态点会话图标开 sessionList tab（A2 动线）→
    /// 1920 rail 展开（>1080，内容页区入列）→ 右键钉住 tab（产物条条目
    /// 可聚焦）。返回舞台控制器（skip 用例收起后读 pinned 断言）。
    Future<WorkbenchStageController> pumpSixZonesReady(
      WidgetTester tester,
    ) async {
      await pumpShell(tester, surface: const Size(880, 700));
      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<WorkbenchStage>(find.byType(WorkbenchStage))
          .controller;
      expect(controller.stageVisible, isTrue, reason: '前置：舞台自动可见');

      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      await tester.pumpAndSettle();

      final String? activeTabId = controller.activeTab?.id;
      expect(activeTabId, isNotNull, reason: '前置：sessionList tab 激活');
      await tester.tap(
        find.byKey(WorkbenchStage.tabItemKey(activeTabId!)),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.agentStageTabPin));
      await tester.pumpAndSettle();
      expect(controller.pinnedTabs, hasLength(1), reason: '前置：产物条条目在位');

      await refocusChatInput(tester);
      return controller;
    }

    testWidgets('F6 六区循环无死区：tab 条 → 舞台内容 → 产物条 → 活动条 → '
        'rail 内容页 → 对话列 → 回绕 tab 条', (tester) async {
      await pumpSixZonesReady(tester);

      const expected = <String>[
        'stageTabBar',
        'stageContent',
        'artifactStrip',
        'activityBar',
        'railContentPage',
        'chatColumn',
        'stageTabBar', // 回绕：第六次 F6 回到起点（无死区）
      ];
      for (final zone in expected) {
        await pressF6(tester);
        await tester.pumpAndSettle();
        expect(zoneOfFocus(tester), zone);
      }
    });

    testWidgets('Shift+F6 反向：rail 内容页 → 活动条 → 产物条 → 舞台内容 → '
        '舞台 tab 条 → 对话列', (tester) async {
      await pumpSixZonesReady(tester);

      const expected = <String>[
        'railContentPage',
        'activityBar',
        'artifactStrip',
        'stageContent',
        'stageTabBar',
        'chatColumn',
      ];
      for (final zone in expected) {
        await pressShiftF6(tester);
        await tester.pumpAndSettle();
        expect(zoneOfFocus(tester), zone);
      }
    });

    testWidgets('舞台不可见：舞台两区跳过（四区循环）', (tester) async {
      final controller = await pumpSixZonesReady(tester);

      // 收起舞台（舞台 tab 条右端收起钮——走查修复批件①入口移位）→ 舞台
      // 不入树 → tab 条/内容区两区注销。
      await tester.tap(find.byKey(WorkbenchStage.collapseKey));
      await tester.pumpAndSettle();
      expect(find.byType(WorkbenchStage), findsNothing);
      expect(controller.pinnedTabs, hasLength(1), reason: '收起不影响 pinned 投影');

      await refocusChatInput(tester);

      // F6：对话列 → （跳过舞台两区）→ 产物条 → 活动条 → rail 内容页 → 对话列。
      const expected = <String>[
        'artifactStrip',
        'activityBar',
        'railContentPage',
        'chatColumn',
        'artifactStrip', // 四区回绕
      ];
      for (final zone in expected) {
        await pressF6(tester);
        await tester.pumpAndSettle();
        expect(
          zoneOfFocus(tester),
          zone,
          reason: '跳过 stageTabBar/stageContent',
        );
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // A5（v2 §8-2）：收窄态路由组合矩阵——三图标 × 首点建 tab / 复点激活 /
  // 各 kind 单例 tab 恒 1，1024（收窄态前置 = 舞台可见 ≤1080，A2 模式）与
  // <900（rail 初始即收窄）两档。A2/A3/A4 逐图标已立，本组补全组合级。
  // ──────────────────────────────────────────────────────────────────────────

  group('A5 收窄态路由组合矩阵（三图标 × 两档宽度）', () {
    /// 开舞台（产物条左端展开钮 = 收起态用户可达入口；走查修复批件①后
    /// 展开态收起改走舞台 tab 条右端收起钮）。
    Future<void> openStage(WidgetTester tester) async {
      await tester.tap(find.byKey(WorkbenchArtifactStrip.toggleKey));
      await tester.pumpAndSettle();
    }

    const iconKeys = <WorkbenchStageTabKind, ValueKey<String>>{
      WorkbenchStageTabKind.sessionList: ValueKey(
        'workbench_activity_sessions',
      ),
      WorkbenchStageTabKind.savedQueries: ValueKey(
        'workbench_activity_savedQueries',
      ),
      WorkbenchStageTabKind.history: ValueKey('workbench_activity_history'),
    };

    for (final (width, label) in const [
      (1024.0, '1024（收窄态前置 = 开舞台 ≤1080 收 44）'),
      (880.0, '<900（rail 初始即收窄，首点自动开舞台）'),
    ]) {
      testWidgets('$label：三图标首点各建单例 tab、复点激活不重建、tab 数恒 1', (tester) async {
        await pumpShell(tester, surface: Size(width, 768));
        if (width >= 900) {
          await openStage(tester);
        }

        // 首点（会话）：建 sessionList 单例 tab（<900 档含舞台自动可见）。
        await tester.tap(
          find.byKey(
            iconKeys[WorkbenchStageTabKind.sessionList] ??
                const ValueKey('workbench_activity_sessions'),
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<WorkbenchStage>(find.byType(WorkbenchStage))
            .controller;
        expect(controller.stageVisible, isTrue);
        expect(controller.tabs.map((t) => t.kind), [
          WorkbenchStageTabKind.sessionList,
        ]);

        // 首点（保存的查询 / 历史）：各建各的单例 tab。
        await tester.tap(
          find.byKey(
            iconKeys[WorkbenchStageTabKind.savedQueries] ??
                const ValueKey('workbench_activity_savedQueries'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            iconKeys[WorkbenchStageTabKind.history] ??
                const ValueKey('workbench_activity_history'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          controller.tabs.map((t) => t.kind),
          containsAll(const [
            WorkbenchStageTabKind.savedQueries,
            WorkbenchStageTabKind.history,
          ]),
        );
        expect(controller.activeTab?.kind, WorkbenchStageTabKind.history);

        // 复点：激活切回、不再新建；各 kind tab 数恒 1、总数恒 3。
        for (final entry in iconKeys.entries) {
          await tester.tap(find.byKey(entry.value));
          await tester.pumpAndSettle();
          expect(
            controller.activeTab?.kind,
            entry.key,
            reason: '复点激活 ${entry.key}',
          );
          expect(
            controller.tabs.where((t) => t.kind == entry.key),
            hasLength(1),
            reason: '${entry.key} 单例 tab 恒 1',
          );
        }
        expect(controller.tabs, hasLength(3));
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  // v2 B2：结果卡「在舞台打开」改路由——shell `_cardActions.onOpenResultInGrid`
  // 经 `_openCardResultInStage(payload, cardId)` 组装 AgentResultRef
  // （refId = `card_<消息 id>`，cardId 经 host 构建点注入）→ 同壳单
  // `_stageController.openGrid`。R7 快照语义：tab 呈现卡快照全量，
  // 不重执行不补全。
  // ──────────────────────────────────────────────────────────────────────────

  group('v2 B2 结果卡「在舞台打开」改路由', () {
    /// 结果卡消息（toolResultData['workbench'] 挂 result_card payload）。
    /// [rowCount] 默认 3 = 非截断有快照（v2 B2 放宽后的入口出现条件）。
    AiMessage resultCardMessage({required String id, int rowCount = 3}) {
      final rows = List<Map<String, dynamic>>.generate(
        rowCount,
        (i) => <String, dynamic>{'id': i + 1},
      );
      return AiMessage(
        id: id,
        isUser: false,
        content: '',
        timestamp: DateTime.now(),
        type: AiMessageType.toolResult,
        toolName: 'workbench',
        toolResultData: <String, dynamic>{
          'workbench': WorkbenchResultCardPayload(
            sql: 'SELECT id FROM users',
            rowCount: rowCount,
            durationMs: 42,
            columns: const ['id'],
            rows: rows,
          ).toJson(),
        },
      );
    }

    testWidgets(
      '点卡「在舞台打开」→ 舞台自动可见 + grid tab 落地（refId=card_<id>）；重复点击复用激活 tab 恒 1',
      (tester) async {
        // 1920×1080：本组断言路由语义。舞台可见后对话列封顶 520——测试字体
        // （Ahem 方块字）下双动作钮 header 固定宽 ≈413px，1280 档对话列
        // 374 会假性溢出（真机字体 ≈253px，最窄 360 对话列也放得下）。
        final app = await pumpShell(tester, surface: const Size(1920, 1080));
        app.aiPanel.ensureSession();
        app.addAiMessage(resultCardMessage(id: 'card_msg_b2'));
        await tester.pumpAndSettle();

        final button = find.byKey(ResultTableCard.openInGridButtonKey);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        final stage = tester.widget<WorkbenchStage>(
          find.byType(WorkbenchStage),
        );
        expect(stage.controller.stageVisible, isTrue, reason: '舞台自动可见');
        expect(
          stage.controller.tabs.map((t) => t.kind),
          [WorkbenchStageTabKind.grid],
          reason: '卡入口落 grid tab（openGrid）',
        );
        expect(stage.controller.activeTab?.kind, WorkbenchStageTabKind.grid);
        expect(
          stage.controller.activeTab?.resultRef?.refId,
          'card_card_msg_b2',
          reason: 'refId = card_<消息 id>',
        );
        // R7：tab 持卡快照（非截断时 = 全量 3 行），rowCount 保留全量口径；
        // 不重执行（app.aiMessages 不新增、无执行调用面）。
        expect(stage.controller.activeTab?.resultRef?.rows, hasLength(3));
        expect(stage.controller.activeTab?.resultRef?.rowCount, 3);

        // 重复点击 → 同 refId 复用激活，tab 恒 1（v1 §5-2）。
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(stage.controller.tabs, hasLength(1));
        expect(
          stage.controller.activeTab?.resultRef?.refId,
          'card_card_msg_b2',
        );
        expect(stage.controller.stageVisible, isTrue);
        expect(tester.takeException(), isNull);
        expect(app.aiMessages.length, 1, reason: '渲染层出口不新建消息');
      },
    );

    testWidgets(
      '轨迹卡步详情入口与卡入口同一 controller 方法 openGrid：同壳单 controller，两入口各落未钉住 grid tab',
      (tester) async {
        // 同上：1920×1080（对话列 520）避开测试字体下的假性 header 溢出。
        final app = await pumpShell(tester, surface: const Size(1920, 1080));
        app.aiPanel.ensureSession();
        final DateTime now = DateTime.now();
        // 轨迹步消息对（executor §5.2 形态；run 内注册表为空 → 快照重建回落）。
        app.addAiMessage(
          AiMessage(
            id: 'agent_anchor_run_b2',
            isUser: false,
            content: '',
            timestamp: now,
            type: AiMessageType.toolResult,
            toolName: 'agent_run',
            toolResultSummary: 'Agent run started (step limit 25)',
            toolResultData: <String, dynamic>{
              'agent': <String, dynamic>{
                'kind': 'agent_run',
                'runId': 'run_b2',
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
            id: 'agent_tc_run_b2_1',
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
            id: 'agent_tr_run_b2_1',
            isUser: false,
            content: 'queried 25 rows',
            timestamp: now,
            type: AiMessageType.toolResult,
            toolName: 'execute_readonly_sql',
            toolResultSummary: 'queried 25 rows',
            toolResultData: <String, dynamic>{
              'agent': <String, dynamic>{
                'kind': 'agent_step',
                'runId': 'run_b2',
                'stepNo': 1,
                'tool': 'execute_readonly_sql',
                'gateLevel': 'none',
                'gateDecision': 'na',
                // rowCount 25 > 快照上限 → 截断——轨迹步详情「在舞台打开」
                // 入口的既有出现条件（AC5.4，AgentTrajectoryCard:1975）。
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
        // 结果卡消息（入口二）。
        app.addAiMessage(resultCardMessage(id: 'card_msg_b2b'));
        await tester.pumpAndSettle();

        // 入口一：卡「在舞台打开」。
        final button = find.byKey(ResultTableCard.openInGridButtonKey);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        final stage = tester.widget<WorkbenchStage>(
          find.byType(WorkbenchStage),
        );
        expect(stage.controller.tabs, hasLength(1));
        expect(
          stage.controller.activeTab?.resultRef?.refId,
          'card_card_msg_b2b',
        );

        // 入口二：轨迹卡步详情「在舞台打开」（既有 T27 动线）。
        await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AgentTrajectoryCard.stepRowKey(1)));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(AgentTrajectoryCard.openInStageKey(1)),
        );
        await tester.tap(find.byKey(AgentTrajectoryCard.openInStageKey(1)));
        await tester.pumpAndSettle();

        // 同一 controller 方法 openGrid 的指纹：两入口都落「未钉住的 grid
        // tab」且舞台自动可见（pinArtifact 会钉住且不改可见性，openChart
        // 是 chart kind——均非本指纹）。
        expect(
          stage.controller.tabs.map((t) => t.kind),
          everyElement(WorkbenchStageTabKind.grid),
          reason: '两入口同落 grid tab（openGrid）',
        );
        expect(
          stage.controller.tabs.map((t) => t.resultRef?.refId),
          containsAll(const ['card_card_msg_b2b', 'res_1']),
        );
        expect(stage.controller.tabs.where((t) => t.pinned), isEmpty);
        expect(stage.controller.stageVisible, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 对话列弹性伸缩（走查缺陷修复 2026-09-25）：舞台可见态对话列宽 =
  // clamp(360, 520, 可用宽 × 0.36)，markdown 会话区随窗口变宽同步变宽；
  // 收起态吃满 region（AI-CW 批 2026-09-29，原 760 封顶退役，region 恒等
  // 断言见上方 §5.4-3）。任务书五个行为断言点：a 单调增长+封顶、b 公式
  // 抽验（1440）、c 下限守卫（1081）、e 回程无残留——d（收起态 1920=1680
  // region 恒等）并入上方 §5.4-3 更新后的多档断言，不重复设用例。
  // ──────────────────────────────────────────────────────────────────────────

  group('对话列弹性伸缩（走查缺陷修复）', () {
    /// 开舞台（产物条左端展开钮 = 收起态用户可达入口；走查修复批件①后
    /// 展开态收起改走舞台 tab 条右端收起钮）。
    Future<void> openStage(WidgetTester tester) async {
      await tester.tap(find.byKey(WorkbenchArtifactStrip.toggleKey));
      await tester.pumpAndSettle();
    }

    double railWidth(WidgetTester tester) => tester
        .getSize(find.byKey(const ValueKey('workbench_session_rail_slot')))
        .width;

    double chatColumnWidth(WidgetTester tester) =>
        tester.getSize(find.byType(WorkbenchChatView)).width;

    testWidgets('a 舞台可见：1280→1920 单调增长、≥1685 封顶 520 不再增长', (tester) async {
      await pumpShell(tester, surface: const Size(1280, 800));
      await openStage(tester);

      expect(tester.takeException(), isNull, reason: '1280 并置无 overflow');
      final double w1280 = chatColumnWidth(tester);
      expect(w1280, closeTo(374, 1), reason: '1280：1040×0.36=374.4');
      expect(
        tester.getSize(find.byType(WorkbenchStage)).width,
        greaterThanOrEqualTo(480),
      );

      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '1920 并置无 overflow');
      final double w1920 = chatColumnWidth(tester);
      expect(w1920, closeTo(520, 1), reason: '1920：1680×0.36=604.8 触顶 520');
      expect(w1920, greaterThan(w1280), reason: '1280→1920 宽度严格增长');
      expect(
        tester.getSize(find.byType(WorkbenchStage)).width,
        greaterThanOrEqualTo(480),
      );

      await tester.binding.setSurfaceSize(const Size(2560, 1400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '2560 并置无 overflow');
      expect(chatColumnWidth(tester), closeTo(520, 1), reason: '封顶后不再增长');
      expect(
        tester.getSize(find.byType(WorkbenchStage)).width,
        greaterThanOrEqualTo(480),
      );
    });

    testWidgets('b 公式抽验：1440 下对话列 ≈432、舞台 ≈768', (tester) async {
      await pumpShell(tester, surface: const Size(1440, 900));
      await openStage(tester);

      expect(tester.takeException(), isNull);
      expect(chatColumnWidth(tester), closeTo(432, 1), reason: '1200×0.36=432');
      expect(
        tester.getSize(find.byType(WorkbenchStage)).width,
        closeTo(768, 1),
        reason: '1440−240−432=768',
      );
    });

    testWidgets('c 下限守卫：1081 下对话列 360、舞台 ≥480、会话栏 240', (tester) async {
      await pumpShell(tester, surface: const Size(1081, 800));
      await openStage(tester);

      expect(tester.takeException(), isNull, reason: '1081 并置无 overflow');
      expect(
        chatColumnWidth(tester),
        closeTo(360, 1),
        reason: '841×0.36=302.8 触下限 360',
      );
      expect(
        tester.getSize(find.byType(WorkbenchStage)).width,
        greaterThanOrEqualTo(480),
      );
      expect(railWidth(tester), 240.0, reason: '1081 > 1080 → 会话栏展开 240');
    });

    testWidgets('e 回程无残留：1920 缩回 1024 → 对话列 360、舞台 620、会话栏 44', (tester) async {
      await pumpShell(tester, surface: const Size(1920, 1080));
      await openStage(tester);
      expect(chatColumnWidth(tester), closeTo(520, 1), reason: '1920 封顶 520');

      // 弹性是纯函数（LayoutBuilder 约束驱动，无残留态）。
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '缩回 1024 无 overflow');
      expect(chatColumnWidth(tester), closeTo(360, 1), reason: '回程触下限 360');
      expect(
        tester.getSize(find.byType(WorkbenchStage)).width,
        closeTo(620, 1),
        reason: '1024−44−360=620（§5.4-1 数值复现）',
      );
      expect(railWidth(tester), 44.0, reason: '1024 ≤ 1080 → 会话栏收 44');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // v2 B3：舞台宽度拖拽 + 对话列并置态宽度持久化（R1 零占位叠层 / R2 双模）
  // ──────────────────────────────────────────────────────────────────────────

  group('v2 B3 舞台宽度拖拽与对话列宽度持久化', () {
    /// 开舞台（产物条左端展开钮 = 收起态用户可达入口；走查修复批件①后
    /// 展开态收起改走舞台 tab 条右端收起钮）。
    Future<void> openStage(WidgetTester tester) async {
      await tester.tap(find.byKey(WorkbenchArtifactStrip.toggleKey));
      await tester.pumpAndSettle();
    }

    double railWidth(WidgetTester tester) => tester
        .getSize(find.byKey(const ValueKey('workbench_session_rail_slot')))
        .width;

    double chatColumnWidth(WidgetTester tester) =>
        tester.getSize(find.byType(WorkbenchChatView)).width;

    double stageWidth(WidgetTester tester) =>
        tester.getSize(find.byType(WorkbenchStage)).width;

    /// 对话列右缘边界 x（会话栏宽 + 对话列宽）——分隔条 12px 命中区中心。
    double splitBoundaryX(WidgetTester tester) =>
        railWidth(tester) + chatColumnWidth(tester);

    /// 从边界水平偏移 [startDx]（−6..+6 命中区）处起拖，交付原始 delta [dx]
    /// 像素（AppResizer 灵敏度 0.8：dx 100 = 宽度 +80）。
    ///
    /// 两段式手势（flutter_test 契约）：第一段 move 40px（> kPanSlop 36 →
    /// PanGR 承认；该段 delta 按 DragStartBehavior.start 被吸收进起点、
    /// 不交付，monodrag.dart `_checkDrag`）；第二段逐字交付 [dx]。
    /// 不用 `dragFrom`：其默认 touchSlop 拆分会吞掉 20px，交付量不可预期。
    Future<void> dragSplit(
      WidgetTester tester, {
      required double startDx,
      required double dx,
    }) async {
      final double boundary = splitBoundaryX(tester);
      final TestGesture gesture = await tester.startGesture(
        Offset(boundary + startDx, 300),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(Offset(dx, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('R1 叠层命中实证：边界 −5px（对话列侧）起拖命中', (tester) async {
      await pumpShell(tester, surface: const Size(1024, 768));
      await openStage(tester);
      expect(chatColumnWidth(tester), closeTo(360, 1), reason: '弹性基线');

      await dragSplit(tester, startDx: -5, dx: 100);
      expect(
        chatColumnWidth(tester),
        closeTo(440, 1),
        reason: '−5px 起拖命中：360 + 80（溢出命中是 R1 成立前提）',
      );
    });

    testWidgets('R1 叠层命中实证：边界 +5px（舞台侧）起拖命中', (tester) async {
      await pumpShell(tester, surface: const Size(1024, 768));
      await openStage(tester);
      expect(chatColumnWidth(tester), closeTo(360, 1), reason: '弹性基线');

      await dragSplit(tester, startDx: 5, dx: 100);
      expect(
        chatColumnWidth(tester),
        closeTo(440, 1),
        reason: '+5px 起拖命中：360 + 80',
      );
    });

    testWidgets('拖拽 +80 → 对话列 440、舞台同步收缩（1024 基线 360）', (tester) async {
      await pumpShell(tester, surface: const Size(1024, 768));
      await openStage(tester);

      await dragSplit(tester, startDx: 0, dx: 100);
      expect(chatColumnWidth(tester), closeTo(440, 1), reason: '360 + 80');
      expect(
        stageWidth(tester),
        closeTo(540, 1),
        reason: '舞台同步收缩：980 − 440 = 540',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble('workbench_chat_split_width'),
        440.0,
        reason: 'onResizeEnd 一次落盘（R2 显式宽度模式）',
      );
    });

    testWidgets('拖到上限：宽钳 520、舞台恒 ≥480', (tester) async {
      await pumpShell(tester, surface: const Size(1024, 768));
      await openStage(tester);

      await dragSplit(tester, startDx: 0, dx: 1000);
      expect(
        chatColumnWidth(tester),
        closeTo(500, 1),
        reason: '内存宽钳 520 后被窗口 clamp 到 980−480=500',
      );
      expect(
        stageWidth(tester),
        greaterThanOrEqualTo(480),
        reason: '窗口感知 clamp 保舞台下限',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble('workbench_chat_split_width'),
        520.0,
        reason: '落盘值为 [360,520] 钳制结果',
      );
    });

    testWidgets('SharedPreferences 预置 440 → 重 pump 恢复 440（显式模式）', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'workbench_chat_split_width': 440.0,
      });
      await pumpShell(tester, surface: const Size(1280, 800));
      await openStage(tester);
      expect(
        chatColumnWidth(tester),
        closeTo(440, 1),
        reason: '1280 弹性默认应为 374.4——440 生效即显式宽度模式（R2）',
      );

      // 窗口往返后仍 440（显式模式不随窗口重算）。
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      await tester.pumpAndSettle();
      expect(chatColumnWidth(tester), closeTo(440, 1));
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpAndSettle();
      expect(chatColumnWidth(tester), closeTo(440, 1));
    });

    testWidgets('键盘三步进 ±Shift 与 Home 复位：即时生效并落盘', (tester) async {
      await pumpShell(tester, surface: const Size(1024, 768));
      await openStage(tester);

      // tooltip 消费预登记 key（en 文案标注快捷键，v1 §5-4）。
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message?.contains('16px') ?? false),
        ),
        findsOneWidget,
        reason: 'workbenchSplitResizerTooltip 标注 ←/→ 16px 快捷键',
      );

      final resizerContext = tester.element(find.byType(EditorResultsResizer));
      Focus.of(resizerContext).requestFocus();
      await tester.pump();

      // 三步进：16 × 3 = +48。
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(chatColumnWidth(tester), closeTo(408, 1), reason: '360 + 16×3');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble('workbench_chat_split_width'),
        408.0,
        reason: '键盘调整即时落盘',
      );

      // Shift+→ = 64。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(chatColumnWidth(tester), closeTo(472, 1), reason: '408 + 64');

      // Home 复位 360（写盘）。
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(chatColumnWidth(tester), closeTo(360, 1), reason: 'Home 复位');
      final prefsAfterReset = await SharedPreferences.getInstance();
      expect(
        prefsAfterReset.getDouble('workbench_chat_split_width'),
        360.0,
        reason: 'Home 复位写盘 360（允许自决采建议）',
      );
    });

    testWidgets('窗口 1920 缩到 1081：持久化 520 被窗口 clamp 到 361 显示', (tester) async {
      SharedPreferences.setMockInitialValues({
        'workbench_chat_split_width': 520.0,
      });
      await pumpShell(tester, surface: const Size(1920, 1080));
      await openStage(tester);
      expect(chatColumnWidth(tester), closeTo(520, 1));

      await tester.binding.setSurfaceSize(const Size(1081, 800));
      await tester.pumpAndSettle();
      expect(
        chatColumnWidth(tester),
        closeTo(361, 1),
        reason: 'min(520, max(360, 841−480)) = 361——窗口 clamp 只影响显示',
      );
      expect(stageWidth(tester), greaterThanOrEqualTo(480));

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble('workbench_chat_split_width'),
        520.0,
        reason: '落盘值不动',
      );
    });

    testWidgets('缩窗全程舞台不自动收起（守卫锁死）', (tester) async {
      await pumpShell(tester, surface: const Size(1920, 1080));
      await openStage(tester);
      final controller = tester
          .widget<WorkbenchStage>(find.byType(WorkbenchStage))
          .controller;
      final List<bool> visibilityHistory = <bool>[controller.stageVisible];
      controller.addListener(
        () => visibilityHistory.add(controller.stageVisible),
      );

      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(900, 700));
      await tester.pumpAndSettle();

      expect(find.byType(WorkbenchStage), findsOneWidget, reason: '缩窗全程舞台保持入树');
      expect(
        visibilityHistory,
        everyElement(isTrue),
        reason: '历次通知里 stageVisible 均未翻 false（setStageVisible(false) 零调用）',
      );
      expect(controller.stageVisible, isTrue);
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

    testWidgets('onPlanApproval：注册表落账 + planId 回填门卡消息 + 等决策', (tester) async {
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

    testWidgets('终态重放 → execute 防重守卫（PLAN_ALREADY_EXECUTED 语义，AC11.4）', (
      tester,
    ) async {
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
      // 1920×1080（对话列 520）：B1 起批准执行完成会推 execution tab 打开
      // 舞台、对话列收窄——测试字体下计划卡步行/状态 chip 在 1280 档假性
      // 溢出（B2 组同款注记）。1920 档个别步行仍溢出 → 叠过滤器兜底。
      final app = _FlakyPlanAppProvider(
        failOn: "UPDATE users SET name = 'x' WHERE id = 7",
      );
      await pumpShell(tester, provider: app, surface: const Size(1920, 1080));
      suppressOverflowArtifacts();
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

      // B1 适配：批准执行完成 → execution tab 推送打开舞台 → 对话列从
      // 居中分支切换到舞台并置分支，轨迹卡展开态随之重置（既有舞台开合
      // 语义，非本批新引入）——重新展开后再操作计划卡。
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
      await tester.pumpAndSettle();

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
      await tester.ensureVisible(find.byKey(AgentPlanCard.sessionCheckboxKey));
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

    testWidgets('⑥：结构取数绑 run 启动快照（D15）——点击时锁定漂移不进取数', (tester) async {
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

    testWidgets('多 run 会话累计正确：tokens 求和 + 步数合计，与终局消息对账一致', (tester) async {
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

  group('B1 execution tab（手动通道 + 计划链推送，R3/R4）', () {
    /// 舞台 controller（舞台可见后在树）。
    WorkbenchStageController stageControllerOf(WidgetTester tester) =>
        tester.widget<WorkbenchStage>(find.byType(WorkbenchStage)).controller;

    /// 种子计划门卡消息（T28 组同款形态：轨迹锚点 + agent_plan 门卡，
    /// planId 由 shell 回填）。
    void seedPlanGateCard(AppProvider app, String runId, int stepNo) {
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

    /// 两步写计划（T22 submitter 真链；LIMIT 形态避开 M6 high 标注噪音）。
    Future<AgentActionPlan> buildTwoStepPlan(String runId) async {
      final result = await const AgentPlanSubmitter().submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(
            sql: "INSERT INTO users (name) VALUES ('x')",
            rollbackSql: "DELETE FROM users WHERE name = 'x' LIMIT 1",
          ),
          AgentPlanStepInput(
            sql: "UPDATE users SET name = 'y' WHERE id = 1 LIMIT 1",
            rollbackSql: "UPDATE users SET name = 'old' WHERE id = 1 LIMIT 1",
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

    /// 批准流公共段：onPlanApproval → 展开轨迹卡 → 点批准 → 等决策。
    Future<void> approvePlanViaCard(
      WidgetTester tester,
      AgentActionPlan plan, {
      required bool expandLastTrajectory,
    }) async {
      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );
      final Future<GateCardResult> pending = view.agentGates!.onPlanApproval(
        plan,
      );
      await tester.pumpAndSettle();
      final headers = find.byKey(AgentTrajectoryCard.headerKey);
      await tester.tap(expandLastTrajectory ? headers.last : headers.first);
      await tester.pumpAndSettle();
      // 舞台打开后对话列收窄、计划卡动作行可能出视口——先滚入再点（假
      // 性 miss 会让决策桥永远等不到 → 挂起）。
      final approve = find.byKey(AgentPlanCard.approveButtonKey);
      await tester.ensureVisible(approve);
      await tester.pumpAndSettle();
      await tester.tap(approve);
      final GateCardResult result = await pending;
      expect(result, GateCardResult.approved);
      // 审计链防抖计时器泄放（T28 组同款收尾）。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }

    testWidgets('手动通道：onExecuteSql 写批 → execution tab 落地（manual 键）；'
        '再执行 → 同 tabKey 复用刷新 tab 恒 1', (tester) async {
      // 1920×1080（对话列 520）：执行落结果卡后舞台打开、对话列收窄——
      // 测试字体（Ahem 方块字）下结果卡双动作钮 header ≈413px，1280 档
      // 374 会假性溢出（B2 组同款注记，真机字体放得下 360）。
      final app = _CountingAppProvider();
      app.aiPanel.ensureSession();
      app.aiPanel.lockWorkbenchContext('conn-1', 'db1');
      await pumpShell(tester, provider: app, surface: const Size(1920, 1080));
      final l10n = AppLocalizationsEn();
      final view = tester.widget<WorkbenchChatView>(
        find.byType(WorkbenchChatView),
      );

      // 第一次：单句写批。经 shell 注入的 `_cardActions.onExecuteSql` 驱动
      // （SQL 卡按钮 → 该回调的卡面一跳由 T13 组覆盖；本例不断 SQL 卡本体——
      // 测试字体下四动作钮卡头在收窄对话列假性溢出，见 B2 组同款注记）。
      view.actions.onExecuteSql?.call("INSERT INTO users (name) VALUES ('a')");
      await tester.pump();
      expect(
        find.byType(ConfirmExecuteDialog),
        findsOneWidget,
        reason: 'gate #1 写确认在位（编排语义不变）',
      );
      await tester.tap(find.text(l10n.aiPanelConfirmExecute));
      await tester.pumpAndSettle();
      expect(app.executeCalls, 1);

      final controller = stageControllerOf(tester);
      expect(controller.stageVisible, isTrue, reason: '推送自动开舞台');
      final execTabs1 = controller.tabs
          .where((t) => t.kind == WorkbenchStageTabKind.execution)
          .toList();
      expect(execTabs1, hasLength(1), reason: '写批执行 → execution tab 落地');
      expect(
        execTabs1.single.execution?.tabKey,
        StageExecutionData.manualTabKey,
        reason: 'R4：手动批单例键 manual',
      );
      expect(execTabs1.single.execution?.rows, hasLength(1));
      expect(
        execTabs1.single.execution?.rows.single.status,
        StageExecutionStatus.done,
      );
      expect(
        execTabs1.single.title,
        startsWith('Execution '),
        reason: '标题含时间戳',
      );

      // 第二次：两句批（UPDATE + SELECT）→ 同 'manual' 键复用刷新——
      // tab 恒 1，内容以新批为准。
      view.actions.onExecuteSql?.call(
        "UPDATE users SET name = 'b' WHERE id = 1; SELECT 9",
      );
      await tester.pump();
      await tester.tap(find.text(l10n.aiPanelConfirmExecute));
      await tester.pumpAndSettle();
      expect(app.executeCalls, 3, reason: 'UPDATE + SELECT 两句各执行一次');

      final execTabs2 = controller.tabs
          .where((t) => t.kind == WorkbenchStageTabKind.execution)
          .toList();
      expect(execTabs2, hasLength(1), reason: '同 tabKey 复用不累积新 tab');
      expect(execTabs2.single.id, execTabs1.single.id);
      expect(
        execTabs2.single.execution?.rows,
        hasLength(2),
        reason: '载荷刷新为新批次（2 行）',
      );
      // 新批 SQL 上屏（舞台内容区；execution tab 激活态）。
      expect(
        find.descendant(
          of: find.byKey(WorkbenchStage.contentAreaKey),
          matching: find.text("UPDATE users SET name = 'b' WHERE id = 1"),
        ),
        findsOneWidget,
      );
      // 防抖类计时器泄放（历史/会话落盘链；T28 组同款收尾）。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('计划批准执行完成 → execution tab 落地（tabKey=planId，'
        '逐语句行步序对齐 + 耗时收集）', (tester) async {
      final app = _CountingAppProvider();
      await pumpShell(tester, provider: app);
      final plan = await buildTwoStepPlan('run-b1-plan-1');
      seedPlanGateCard(app, 'run-b1-plan-1', 0);

      await approvePlanViaCard(tester, plan, expandLastTrajectory: false);

      expect(plan.status, AgentPlanStatus.done);
      expect(app.executeCalls, 2, reason: '两步逐语句执行');
      final controller = stageControllerOf(tester);
      final execTabs = controller.tabs
          .where((t) => t.kind == WorkbenchStageTabKind.execution)
          .toList();
      expect(execTabs, hasLength(1), reason: '计划执行完成 → execution tab 落地');
      final data = execTabs.single.execution;
      expect(data, isNotNull);
      expect(data!.tabKey, plan.planId, reason: 'R4：计划链去重键 = planId');
      expect(data.title, startsWith('Execution '), reason: '标题含时间戳');
      // 步序对齐（executor 严格串行语义保证收集行序 = 步序）：SQL 逐步一致。
      expect(
        data.rows.map((r) => r.sql).toList(),
        plan.steps.map((s) => s.sql).toList(),
        reason: '行序 = plan.steps 步序（join 对齐断言）',
      );
      expect(
        data.rows.map((r) => r.status),
        everyElement(StageExecutionStatus.done),
      );
      expect(
        data.rows.every((r) => r.durationMs != null),
        isTrue,
        reason: '执行通道收集器耗时逐行在位',
      );
    });

    testWidgets('部分失败计划 → failed 行（error 全文）+ skipped 行（步序对齐）', (tester) async {
      final app = _FlakyPlanAppProvider(
        failOn: "INSERT INTO users (name) VALUES ('x')",
      );
      await pumpShell(tester, provider: app);
      final plan = await buildTwoStepPlan('run-b1-plan-2');
      seedPlanGateCard(app, 'run-b1-plan-2', 0);

      await approvePlanViaCard(tester, plan, expandLastTrajectory: false);

      expect(plan.status, AgentPlanStatus.partialFailed);
      expect(app.executed, hasLength(1), reason: '失败即停：步 2 未执行');
      final controller = stageControllerOf(tester);
      final data = controller.tabs
          .where((t) => t.kind == WorkbenchStageTabKind.execution)
          .single
          .execution;
      expect(data, isNotNull);
      expect(data!.tabKey, plan.planId);
      expect(data.rows, hasLength(2), reason: '行 = 全计划语句（含 skipped）');
      expect(data.rows[0].sql, plan.steps[0].sql, reason: '步序对齐');
      expect(data.rows[0].status, StageExecutionStatus.failed);
      expect(
        data.rows[0].error,
        contains('boom'),
        reason: '失败行错误全文（执行器口径，已脱敏）',
      );
      expect(data.rows[0].durationMs, isNotNull, reason: '真执行失败 → 收集器耗时在位');
      expect(data.rows[1].sql, plan.steps[1].sql);
      expect(
        data.rows[1].status,
        StageExecutionStatus.skipped,
        reason: '失败边界余下语句 skipped（从 plan.steps 终态读）',
      );
      expect(data.rows[1].durationMs, isNull, reason: '未执行无指标（降级）');
      expect(data.rows[1].error, isNull);
    });

    testWidgets('planId 去重：两计划各落各的 execution tab（异 planId 共存）', (tester) async {
      // 1920×1080（对话列 520）：双轨迹卡展开 + 舞台打开后对话列收窄，
      // 1280 档下计划卡状态 chip 在测试字体下假性溢出（B2 组同款注记）。
      final app = _CountingAppProvider();
      await pumpShell(tester, provider: app, surface: const Size(1920, 1080));

      // 计划 1 批准执行 → tab 落地。
      final plan1 = await buildTwoStepPlan('run-b1-plan-3a');
      seedPlanGateCard(app, 'run-b1-plan-3a', 0);
      await approvePlanViaCard(tester, plan1, expandLastTrajectory: false);
      expect(plan1.status, AgentPlanStatus.done);

      // 计划 2（异 runId/planId）批准执行 → 新 tab（不覆盖计划 1 的 tab）。
      final plan2 = await buildTwoStepPlan('run-b1-plan-3b');
      seedPlanGateCard(app, 'run-b1-plan-3b', 0);
      await approvePlanViaCard(tester, plan2, expandLastTrajectory: true);
      expect(plan2.status, AgentPlanStatus.done);

      final controller = stageControllerOf(tester);
      final execTabs = controller.tabs
          .where((t) => t.kind == WorkbenchStageTabKind.execution)
          .toList();
      expect(execTabs, hasLength(2), reason: '异 planId 各自落地共存');
      expect(
        execTabs.map((t) => t.execution?.tabKey),
        containsAll([plan1.planId, plan2.planId]),
        reason: 'tabKey = 各自 planId（R4）',
      );
      // 计划 1 的 tab 内容未被计划 2 改写。
      final tab1 = execTabs.firstWhere(
        (t) => t.execution?.tabKey == plan1.planId,
      );
      expect(tab1.execution?.rows, hasLength(2));
      // 同 tabKey 复用刷新的去重语义由 workbench_stage_test 的
      // openExecution 用例直锁（controller 层）。
    });
  });

  group('2b.4 工作台入口 intent 消费（R7）', () {
    WorkbenchStageController stageControllerOf(WidgetTester tester) =>
        tester.widget<WorkbenchStage>(find.byType(WorkbenchStage)).controller;

    String inputTextOf(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller?.text ?? '';

    testWidgets('intent 注入 → post-frame 推 observe tab + 预填 + 清除', (
      tester,
    ) async {
      final app = await pumpShell(tester);
      expect(app.aiPanel.workbenchEntryIntent, isNull);

      app.aiPanel.requestWorkbenchEntry(
        prompt: 'prefill prompt',
        tabTarget: WorkbenchEntryTabTarget.observe,
      );
      await tester.pumpAndSettle();

      final controller = stageControllerOf(tester);
      expect(
        controller.tabs.any((t) => t.kind == WorkbenchStageTabKind.observe),
        isTrue,
        reason: 'post-frame openObserve 被调',
      );
      expect(inputTextOf(tester), equals('prefill prompt'));
      expect(app.aiPanel.workbenchEntryIntent, isNull, reason: '消费后清除 intent');
    });

    testWidgets('savedQueries / history 目标各推各的单例 tab', (tester) async {
      final app = await pumpShell(tester);

      app.aiPanel.requestWorkbenchEntry(
        tabTarget: WorkbenchEntryTabTarget.savedQueries,
      );
      await tester.pumpAndSettle();
      var controller = stageControllerOf(tester);
      expect(
        controller.tabs.any(
          (t) => t.kind == WorkbenchStageTabKind.savedQueries,
        ),
        isTrue,
      );

      app.aiPanel.requestWorkbenchEntry(
        tabTarget: WorkbenchEntryTabTarget.history,
      );
      await tester.pumpAndSettle();
      controller = stageControllerOf(tester);
      expect(
        controller.tabs.any((t) => t.kind == WorkbenchStageTabKind.history),
        isTrue,
      );
      expect(app.aiPanel.workbenchEntryIntent, isNull);
    });

    testWidgets('同 id 不重复消费：post-frame 前多次通知只消费一次', (tester) async {
      final app = await pumpShell(tester);

      app.aiPanel.requestWorkbenchEntry(
        prompt: 'exactly-once',
        tabTarget: WorkbenchEntryTabTarget.none,
      );
      // post-frame 前触发多次 provider 通知（同一 pending intent）——
      // 防重入锚保证只调度一次消费。
      app.aiPanel.setSelectedTable('t1');
      app.aiPanel.setSelectedTable('t2');
      app.setPendingUpgradeFeature('f');
      await tester.pumpAndSettle();

      expect(inputTextOf(tester), equals('exactly-once'));
      expect(app.aiPanel.workbenchEntryIntent, isNull);
      expect(
        find.byType(WorkbenchStage),
        findsNothing,
        reason: 'tabTarget none 不开舞台',
      );
    });

    testWidgets('prompt 为空不预填：输入框草稿保持原值（tabTarget none）', (tester) async {
      final app = await pumpShell(tester);
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();

      // 无 prompt、不推 tab（tabTarget none）→ 输入框零触碰。
      app.aiPanel.requestWorkbenchEntry();
      await tester.pumpAndSettle();

      expect(inputTextOf(tester), equals('draft'));
      expect(app.aiPanel.workbenchEntryIntent, isNull);
    });

    testWidgets('连续两次意图各消费一次（id 递增各自消费）', (tester) async {
      final app = await pumpShell(tester);

      app.aiPanel.requestWorkbenchEntry(prompt: 'first');
      await tester.pumpAndSettle();
      expect(inputTextOf(tester), equals('first'));

      app.aiPanel.requestWorkbenchEntry(prompt: 'second');
      await tester.pumpAndSettle();
      expect(inputTextOf(tester), equals('second'));
      expect(app.aiPanel.workbenchEntryIntent, isNull);
    });
  });
}
