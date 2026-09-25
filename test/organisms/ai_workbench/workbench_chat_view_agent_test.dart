// T14 对话列组件级测试（tasks-ai-agent.md T14 / design-ai-agent §2.3、
// AC1.4、AC7.4）。
//
// 覆盖：key 未配置引导（守卫失败用户消息先行 + 错误消息不静默 + runner
// 未启动）/ _mergeToolMessages 不吞 agent 消息 + T13 分组渲染（经典合并
// 照旧，agent run 一张轨迹卡，步消息不平铺不泄漏）/ CONTEXT_REQUIRED
// 「去设置上下文」出口（渲染 + 打开 WorkbenchContextPicker）。
//
// 发送即启动 run / 停止 / isRunning 守卫的行为面在
// test/providers/ai_panel_provider_agent_test.dart 经注入式 runner 覆盖
// （AppProvider 的 aiPanel 为 late final，组件树级无法替换默认 runner——
// 默认 runner 的 chat 为真实 AiService，组件级测试不可脚本化不触网）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_trajectory_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_host.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_chat_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_context_picker.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:dbmaster/organisms/ai_panel/ai_slash_command_menu.dart';
import 'package:dbmaster/organisms/ai_panel/widgets/tool_card_shell.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/workbench_usage_stats_service.dart';

AiMessage _user(String id, String content) => AiMessage(
  id: id,
  isUser: true,
  content: content,
  timestamp: DateTime.now(),
  type: AiMessageType.chat,
  status: AiMessageStatus.sent,
);

AiMessage _agentPayload(
  String id,
  Map<String, dynamic> payload, {
  String summary = '',
}) => AiMessage(
  id: id,
  isUser: false,
  content: summary,
  timestamp: DateTime.now(),
  type: AiMessageType.toolResult,
  toolResultSummary: summary.isEmpty ? null : summary,
  toolResultData: <String, dynamic>{'agent': payload},
);

/// 一个完整 agent run 的消息区间（锚点 + 步消息对 + 终局）。
List<AiMessage> _agentRunMessages(String runId, {String? stepErrorCode}) {
  final Map<String, dynamic> stepPayload = <String, dynamic>{
    'kind': 'agent_step',
    'runId': runId,
    'stepNo': 1,
    'tool': 'execute_readonly_sql',
    'gateDecision': 'allowed',
    'summary': 'SELECT 1 ok',
    'durationMs': 12,
  };
  if (stepErrorCode != null) {
    stepPayload['error'] = <String, dynamic>{
      'code': stepErrorCode,
      'message': 'no workbench context',
    };
  }
  return <AiMessage>[
    _agentPayload('agent_anchor_$runId', <String, dynamic>{
      'kind': 'agent_run',
      'runId': runId,
      'goal': '查一下',
      'contextSnapshot': <String, dynamic>{
        'conn': '',
        'db': '',
        'readOnly': false,
        'maxSteps': 25,
      },
    }, summary: 'Agent run started (step limit 25)'),
    AiMessage(
      id: 'agent_tc_${runId}_1',
      isUser: false,
      content: '',
      timestamp: DateTime.now(),
      type: AiMessageType.toolCall,
      toolName: 'execute_readonly_sql',
      toolArguments: <String, dynamic>{'sql': 'SELECT 1'},
    ),
    _agentPayload(
      'agent_tr_${runId}_1',
      stepPayload,
      summary: 'SELECT 1 ok',
    ),
    _agentPayload('agent_end_$runId', <String, dynamic>{
      'kind': 'agent_run_end',
      'runId': runId,
      'status': 'completed',
      'steps': 1,
      'summaryText': 'Completed · 1 step(s)',
    }, summary: 'Completed · 1 step(s)'),
  ];
}

Future<AppProvider> pumpChatView(WidgetTester tester, {AppProvider? app}) async {
  app ??= AppProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(
          body: WorkbenchChatView(actions: WorkbenchCardActions()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WorkbenchUsageStatsService.instance.resetForTesting();
  });

  group('T14 key 未配置引导（AC1.4，§2.3 preflight 只留 key 守卫）', () {
    testWidgets('守卫失败：用户消息先行 + 引导错误消息 + runner 未启动', (tester) async {
      final app = await pumpChatView(tester);

      await tester.enterText(find.byType(TextField), 'hello agent');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.send));
      await tester.pumpAndSettle();

      final messages = app.aiMessages;
      expect(messages.length, 2, reason: '用户消息 + 守卫错误消息均入流（M1 语义）');
      expect(messages[0].isUser, isTrue);
      expect(messages[0].content, 'hello agent');
      expect(messages[1].status, AiMessageStatus.failed);
      expect(
        messages[1].content,
        AppLocalizationsEn().configureApiKeyFirst(app.selectedAiProvider),
        reason: 'AC1.4：configureApiKeyFirst 引导（对象级断言——渲染态为多行）',
      );
      expect(
        app.aiMessages.where((AiMessage m) => m.id.startsWith('agent_')),
        isEmpty,
        reason: 'runner 未启动（无锚点/步消息）',
      );
      expect(app.aiPanel.agentRunner.isRunning, isFalse);
    });
  });

  group('T14 _mergeToolMessages 不吞 agent 消息 + 分组渲染（design §2.3）', () {
    testWidgets('经典 toolCall/toolResult 照旧合并，agent run 折叠一张轨迹卡', (
      tester,
    ) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.addAiMessage(_user('u1', 'classic question'));
      // 经典式 toolCall + toolResult（合并算法既有行为基准）。
      app.addAiMessage(
        AiMessage(
          id: 'ct1',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolCall,
          toolName: 'classicTool',
          toolArguments: <String, dynamic>{'q': 1},
        ),
      );
      app.addAiMessage(
        AiMessage(
          id: 'ctr1',
          isUser: false,
          content: 'classic result',
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'classicTool',
          status: AiMessageStatus.completed,
        ),
      );
      for (final AiMessage m in _agentRunMessages('run_1')) {
        app.addAiMessage(m);
      }
      await tester.pumpAndSettle();

      expect(
        find.byType(AgentTrajectoryCard),
        findsOneWidget,
        reason: 'agent run 折叠为一张轨迹卡（D9）',
      );
      expect(
        find.byType(ToolCardShell),
        findsOneWidget,
        reason: '经典式 toolCall/toolResult 照旧合并（合并产物 = 单一工具卡；'
            '若合并失效则为两张）',
      );
      expect(
        find.text('SELECT 1 ok'),
        findsNothing,
        reason: 'agent 步消息不被合并/平铺成经典气泡（折叠态懒构建，NF1.1）',
      );
      expect(
        find.text('Completed · 1 step(s)'),
        findsOneWidget,
        reason: '终局汇报行恒显（轨迹卡 report row）',
      );
      // 消息对象不被吞：会话账本条数与输入一致（渲染层零改写）。
      expect(app.aiMessages.length, 7);
    });
  });

  group('T14 CONTEXT_REQUIRED「去设置上下文」出口（AC7.4）', () {
    testWidgets('步错误渲染出口行，按钮打开 WorkbenchContextPicker', (tester) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.addAiMessage(_user('u1', '查一下'));
      for (final AiMessage m
          in _agentRunMessages('run_2', stepErrorCode: 'CONTEXT_REQUIRED')) {
        app.addAiMessage(m);
      }
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      expect(
        find.byKey(const ValueKey('workbench_agent_context_required_exit')),
        findsOneWidget,
        reason: '出口挂 agent run 错误消息下方（沿 M1 错误卡出口语汇）',
      );
      expect(find.text(l10n.agentContextRequired), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench_agent_context_required_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('workbench_agent_context_required_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(WorkbenchContextPicker),
        findsOneWidget,
        reason: '动作 = 打开既有上下文选择器',
      );
    });

    testWidgets('无 CONTEXT_REQUIRED 错误的 run 不渲染出口', (tester) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.addAiMessage(_user('u1', '查一下'));
      for (final AiMessage m in _agentRunMessages('run_3')) {
        app.addAiMessage(m);
      }
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workbench_agent_context_required_exit')),
        findsNothing,
      );
    });
  });

  group('T15 技能入口 slash 接线（R12 / AC12.1、AC12.2）', () {
    // 「选中启动 run」用例需经 saveAiConfig 配 key（preflight 放行）——其
    // key 持久化走 FlutterSecureStorage 真平台通道，flutter_tester 中不回落
    // → future 永不完成。沿 workbench_context_chip_test 的通道 mock 惯例。
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          switch (call.method) {
            case 'readAll':
              return <String, String>{};
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
    });

    testWidgets('入口可用：输入 / 弹出经典 SlashCommandMenu（复用不复制）', (tester) async {
      await pumpChatView(tester);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();

      expect(find.byType(SlashCommandMenu), findsOneWidget);
      expect(find.text('/optimize'), findsOneWidget);
      expect(find.text('/explain'), findsOneWidget);
      expect(find.text('/analyze'), findsOneWidget);
    });

    testWidgets('选中技能启动 run：模板作为用户消息落会话（AC12.1）+ 统一 agent 工具链（AC12.2）', (
      tester,
    ) async {
      final app = await pumpChatView(tester);
      await tester.pumpAndSettle();
      // preflight key 守卫放行；chat 走默认装配的空 AgentChatConfig（组件级
      // 无 shell 注入 reader）→ Unsupported provider 快速失败，无网不悬挂
      // （沿 ai_panel_provider_agent_test 默认装配同款驱动口径）。
      await app.saveAiConfig(
        'DeepSeek',
        'deepseek-chat',
        <String, Map<String, String>>{
          'DeepSeek': <String, String>{'apiKey': 'k-t15'},
        },
      );
      expect(app.getAiApiKey('DeepSeek'), 'k-t15', reason: '前置：key 已就位');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.tap(find.text('/optimize'));
      await tester.pumpAndSettle();

      final String template = AppLocalizationsEn().aiSkillQueryOptimizerPrompt;
      final List<AiMessage> messages = app.aiMessages;

      // AC12.1 可观察面：模板文本作为用户消息落会话——且由 runner 落账
      // （agent_u_ 前缀 = run 已启动，非守卫补落路径）。
      final List<AiMessage> userMsgs = messages
          .where((AiMessage m) => m.id.startsWith('agent_u_'))
          .toList();
      expect(userMsgs, hasLength(1), reason: '用户消息由 runner 落账（run 已启动）');
      expect(userMsgs.first.content, template);
      expect(userMsgs.first.isUser, isTrue);

      // 轨迹锚点：goal = 模板全文（run 以模板为预设 prompt 启动）。
      final List<AiMessage> anchors = messages
          .where((AiMessage m) => m.id.startsWith('agent_anchor_'))
          .toList();
      expect(anchors, hasLength(1));
      final Map<String, dynamic> anchorPayload =
          anchors.first.toolResultData?['agent'] as Map<String, dynamic>;
      expect(anchorPayload['kind'], 'agent_run');
      expect(anchorPayload['goal'], template);

      // 终局：空 chat 配置快速失败 → failed 收敛（证明走 agent 回路，
      // AC12.2——无独立单轮技能执行路径）。
      final List<AiMessage> terminals = messages
          .where((AiMessage m) => m.id.startsWith('agent_end_'))
          .toList();
      expect(terminals, hasLength(1));
      final Map<String, dynamic> endPayload =
          terminals.first.toolResultData?['agent'] as Map<String, dynamic>;
      expect(endPayload['status'], 'failed');
      expect(terminals.first.status, AiMessageStatus.failed);

      // 渲染面：run 折叠为一张轨迹卡（T13 分组消费）。
      expect(find.byType(AgentTrajectoryCard), findsOneWidget);
      expect(app.aiPanel.agentRunner.isRunning, isFalse);
    });

    testWidgets('key 未配置：守卫链继承（模板仍落用户消息 + 引导错误 + run 未启动）', (tester) async {
      final app = await pumpChatView(tester); // 无 key

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.tap(find.text('/analyze'));
      await tester.pumpAndSettle();

      final String template = AppLocalizationsEn().aiSkillIndexSuggestPrompt;
      final List<AiMessage> messages = app.aiMessages;
      expect(messages.length, 2, reason: '用户消息 + 守卫错误（与手输发送同一守卫链，AC12.2）');
      expect(messages.first.isUser, isTrue);
      expect(messages.first.content, template, reason: 'AC12.1：模板文本作为用户消息可观察');
      expect(
        messages[1].status,
        AiMessageStatus.failed,
        reason: 'configureApiKeyFirst 引导不静默',
      );
      expect(
        messages.where((AiMessage m) => m.id.startsWith('agent_')),
        isEmpty,
        reason: 'runner 未启动（key 守卫先行）',
      );
      expect(app.aiPanel.agentRunner.isRunning, isFalse);
    });
  });
}
