// T26 chat view 建议卡接线测试（tasks-ai-agent.md T26 / R6 AC6.1-6.4 /
// ui 规格 §4.2-1）。
//
// 覆盖：分组排除（agent_suggest 不进 run 折叠区间、按消息位置平铺、时间序
// 保持）/ AC6.1 未点击零副作用（tab/侧栏/审计计数 0）/ AC6.2 应用 → 新 tab
// 不覆盖既有 tab + 审计 + 卡翻「已应用」/ AC6.3 忽略零副作用 + 翻「已忽略」/
// focus_sidebar 侧栏定位断言。
//
// 消息形态契约（T28 对齐）：toolResultData['agent'] = {kind: 'agent_suggest',
// runId, stepNo?, action: 'open_in_classic'|'focus_sidebar', payload:
// {sql} | {database?, table?}, applied: false} + toolResultSummary 兜底文本。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/audit_log_entry.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_suggestion_card.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_trajectory_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_chat_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_host.dart';
import 'package:dbmaster/services/audit_log_service.dart';
import 'package:dbmaster/providers/app_provider.dart';

const String suggestSql = 'SELECT o.id, o.total FROM orders o WHERE o.total > 1000';

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

/// 建议卡消息（T28 契约形态）。
AiMessage _suggestion(
  String id, {
  String runId = 'run_s1',
  int? stepNo,
  String action = 'open_in_classic',
  Map<String, dynamic> payload = const <String, dynamic>{'sql': suggestSql},
}) => _agentPayload(id, <String, dynamic>{
  'kind': 'agent_suggest',
  'runId': runId,
  if (stepNo != null) 'stepNo': stepNo,
  'action': action,
  'payload': payload,
  'applied': false,
}, summary: 'Suggestion: $action');

/// 一个完整 agent run 的消息区间（锚点 + 步消息对 + 终局）。
List<AiMessage> _agentRunMessages(String runId) => <AiMessage>[
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
  }, summary: 'Agent run started'),
  AiMessage(
    id: 'agent_tc_$runId',
    isUser: false,
    content: '',
    timestamp: DateTime.now(),
    type: AiMessageType.toolCall,
    toolName: 'execute_readonly_sql',
    toolArguments: <String, dynamic>{'sql': 'SELECT 1'},
  ),
  _agentPayload('agent_tr_$runId', <String, dynamic>{
    'kind': 'agent_step',
    'runId': runId,
    'stepNo': 1,
    'tool': 'execute_readonly_sql',
    'gateDecision': 'allowed',
    'summary': 'SELECT 1 ok',
    'durationMs': 12,
  }, summary: 'SELECT 1 ok'),
  _agentPayload('agent_end_$runId', <String, dynamic>{
    'kind': 'agent_run_end',
    'runId': runId,
    'status': 'completed',
    'steps': 1,
    'summaryText': 'Completed · 1 step(s)',
  }, summary: 'Completed · 1 step(s)'),
];

Future<AppProvider> pumpChatView(WidgetTester tester, {AppProvider? app}) async {
  app ??= AppProvider();
  await tester.binding.setSurfaceSize(const Size(1280, 900));
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

int _auditCount() => AuditLogService().getRecentEntries(limit: 10000).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AuditLogService().initialize();
  });

  group('T26 分组排除（宿主裁决：agent_suggest 不进 run 折叠区间）', () {
    test('纯函数：suggest 消息平铺为顶级消息，时间序保持，run 组不含 suggest', () {
      final List<AiMessage> messages = <AiMessage>[
        _user('u1', 'first'),
        ..._agentRunMessages('run_g1'),
        _suggestion('sg1'),
        _user('u2', 'second'),
      ];
      final segments = agentTrajectoryGrouping(
        messages,
        excludeFromRun: (String kind) => kind == 'agent_suggest',
      );

      expect(segments, hasLength(4), reason: 'user + run组 + suggest + user');
      expect(segments[0].isRun, isFalse);
      expect(segments[0].message?.id, 'u1');
      expect(segments[1].isRun, isTrue);
      expect(
        segments[1].run!.messages.map((AiMessage m) => m.id).toList(),
        <String>[
          'agent_anchor_run_g1',
          'agent_tc_run_g1',
          'agent_tr_run_g1',
          'agent_end_run_g1',
        ],
        reason: 'run 组内无 suggest 消息',
      );
      expect(segments[2].isRun, isFalse);
      expect(segments[2].message?.id, 'sg1', reason: '按消息位置平铺（时间序）');
      expect(segments[3].message?.id, 'u2');
    });

    testWidgets('渲染：agent run 一张轨迹卡 + suggest 顶级建议卡，卡序 = 消息时间序', (tester) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.addAiMessage(_user('u1', 'first'));
      for (final AiMessage m in _agentRunMessages('run_g2')) {
        app.addAiMessage(m);
      }
      app.addAiMessage(_suggestion('sg2'));
      app.addAiMessage(_user('u2', 'second'));
      await tester.pumpAndSettle();

      expect(find.byType(AgentTrajectoryCard), findsOneWidget,
          reason: 'suggest 排除后 run 照旧折叠一张轨迹卡（A1 分组零回退）');
      expect(find.byType(AgentSuggestionCard), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);

      final double dyFirst = tester
          .getRect(find.text('first'))
          .top;
      final double dyRun = tester.getTopLeft(find.byType(AgentTrajectoryCard)).dy;
      final double dySuggest = tester
          .getTopLeft(find.byType(AgentSuggestionCard))
          .dy;
      final double dySecond = tester
          .getRect(find.text('second'))
          .top;
      expect(dyFirst < dyRun, isTrue, reason: '时间序：user1 → run 卡');
      expect(dyRun < dySuggest, isTrue, reason: 'suggest 在 run 卡之后（消息位置）');
      expect(dySuggest < dySecond, isTrue, reason: 'suggest 在 user2 之前');
    });
  });

  group('AC6.1 未点击零副作用', () {
    testWidgets('渲染建议卡本身：tab/侧栏/审计计数全 0', (tester) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.addAiMessage(_user('u1', '查一下'));

      await app.addNewTab(connectionId: 'conn-9', databaseName: 'db9');
      app.updateTabSql(app.activeTabIndex, 'SELECT existing');
      final int tabsBefore = app.tabs.length;
      final int auditBefore = _auditCount();
      await tester.pumpAndSettle();

      app.addAiMessage(_suggestion('sg_zero'));
      await tester.pumpAndSettle();
      // 冲洗会话/标签落盘防抖定时器（500ms/800ms），避免测试收尾挂定时器；
      // 零副作用断言不受冲洗影响（冲洗只触发持久化，不改状态）。
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(AgentSuggestionCard), findsOneWidget);
      expect(find.text(l10n.agentSuggestBadgeNotApplied), findsOneWidget,
          reason: '决策前「未执行」chip 恒显（§4.2-2）');
      expect(app.tabs.length, tabsBefore, reason: 'AC6.1：未点击不开 tab');
      expect(app.activeTab?.sql, 'SELECT existing', reason: '既有 tab 不动');
      expect(app.sidebar.selectedConnectionId, isNull, reason: '未点击不动侧栏');
      expect(_auditCount(), auditBefore, reason: '未点击不落审计');
    });
  });

  group('AC6.2 应用 open_in_classic → 新 tab + 审计 + 翻「已应用」', () {
    testWidgets('点击应用：新 tab 承载 SQL（不覆盖既有）+ 退出全屏 + 审计 na/true + 载荷回填', (tester) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.aiPanel.lockWorkbenchContext('conn-1', 'db1');
      app.addAiMessage(_user('u1', '查一下'));
      app.addAiMessage(
        _suggestion('sg3', runId: 'run_a1', stepNo: 3),
      );

      await app.addNewTab(connectionId: 'conn-9', databaseName: 'db9');
      app.updateTabSql(app.activeTabIndex, 'SELECT existing');
      final int existingTabIndex = app.activeTabIndex;
      final String existingTabId = app.activeTab?.id ?? '';
      final int tabsBefore = app.tabs.length;
      final int auditBefore = _auditCount();
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AgentSuggestionCard.applyButtonKey));
      await tester.pumpAndSettle();
      // 冲洗审计持久化防抖（2s）与 SnackBar 定时器，避免测试收尾挂定时器。
      await tester.pump(const Duration(seconds: 5));

      expect(app.tabs.length, tabsBefore + 1, reason: 'AC6.2：新 tab 承载');
      expect(app.activeTab?.sql, suggestSql, reason: '目标 tab SQL == 建议 SQL');
      expect(app.activeTab?.connectionId, 'conn-1');
      expect(app.activeTab?.databaseName, 'db1');
      expect(app.tabs[existingTabIndex].id, existingTabId,
          reason: '既有 tab 原位原内容（不覆盖）');
      expect(app.tabs[existingTabIndex].sql, 'SELECT existing');
      expect(app.aiPanelFullscreen, isFalse, reason: 'M1 出口语义：退出全屏看落点');

      // 审计（AC6.4）：gateDecision na / success true / 工具名 = 动作名。
      final List<AuditLogEntry> entries = AuditLogService()
          .getRecentEntries(limit: 10000);
      expect(entries, hasLength(auditBefore + 1), reason: '应用恰好落一条审计');
      final AuditLogEntry entry = entries.first;
      expect(entry.agentTool, 'open_in_classic', reason: '工具名 = 动作名');
      expect(entry.gateDecision, AgentGateDecision.na);
      expect(entry.success, isTrue);
      expect(entry.agentRunId, 'run_a1', reason: 'runId 自载荷透传');
      expect(entry.agentStep, 3, reason: 'stepNo 自载荷透传');
      expect(entry.sql, '', reason: '建议级为 UI 工具，SQL 不入档');

      // 卡翻「已应用」+ 消息载荷回填（会话重开保持）。
      expect(find.text(l10n.agentSuggestBadgeApplied), findsOneWidget);
      expect(find.text(l10n.agentSuggestBadgeNotApplied), findsNothing);
      expect(find.byKey(AgentSuggestionCard.applyButtonKey), findsNothing);
      final AiMessage backfilled = app.aiMessages
          .firstWhere((AiMessage m) => m.id == 'sg3');
      final Map<String, dynamic> agent =
          backfilled.toolResultData!['agent'] as Map<String, dynamic>;
      expect(agent['applied'], isTrue);
    });
  });

  group('AC6.3 忽略零副作用', () {
    testWidgets('点击忽略：tab/侧栏/审计计数 0，卡翻「已忽略」+ 载荷回填', (tester) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.aiPanel.lockWorkbenchContext('conn-1', 'db1');
      app.addAiMessage(_user('u1', '查一下'));
      app.addAiMessage(_suggestion('sg4'));

      await app.addNewTab(connectionId: 'conn-9', databaseName: 'db9');
      app.updateTabSql(app.activeTabIndex, 'SELECT existing');
      final int tabsBefore = app.tabs.length;
      final int auditBefore = _auditCount();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AgentSuggestionCard.dismissButtonKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      expect(app.tabs.length, tabsBefore, reason: 'AC6.3：忽略不开 tab');
      expect(app.activeTab?.sql, 'SELECT existing');
      expect(app.sidebar.selectedConnectionId, isNull, reason: '忽略不动侧栏');
      expect(_auditCount(), auditBefore, reason: '忽略不落审计');

      expect(find.text(l10n.agentSuggestBadgeDismissed), findsOneWidget);
      expect(find.text(l10n.agentSuggestBadgeNotApplied), findsNothing);
      expect(find.byKey(AgentSuggestionCard.applyButtonKey), findsNothing);
      final AiMessage backfilled = app.aiMessages
          .firstWhere((AiMessage m) => m.id == 'sg4');
      final Map<String, dynamic> agent =
          backfilled.toolResultData!['agent'] as Map<String, dynamic>;
      expect(agent['dismissed'], isTrue);
      expect(agent['applied'], isFalse);
    });
  });

  group('AC6.4 应用 focus_sidebar → 侧栏定位 + 审计', () {
    testWidgets('点击应用：侧栏选中入口定位 database/table + 审计工具名 = focus_sidebar', (tester) async {
      final app = await pumpChatView(tester);
      app.aiPanel.ensureSession();
      app.aiPanel.lockWorkbenchContext('conn-1', 'db1');
      app.addAiMessage(_user('u1', '看看 users 表'));
      app.addAiMessage(
        _suggestion('sg5', runId: 'run_f1', action: 'focus_sidebar',
            payload: const <String, dynamic>{
              'database': 'db2',
              'table': 'users',
            }),
      );
      await tester.pumpAndSettle();

      expect(app.sidebar.selectedConnectionId, isNull);
      final int auditBefore = _auditCount();
      // 工作台全屏可见态：focus_sidebar 应用后必须**保持**全屏（仅侧栏定位，
      // 不像 open_in_classic 退出全屏——AC6.2/AC6.4 出口语义分野）。
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AgentSuggestionCard.applyButtonKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(app.sidebar.selectedConnectionId, 'conn-1',
          reason: '侧栏定位 = 生效上下文连接');
      expect(app.sidebar.selectedDatabaseName, 'db2',
          reason: '定位目标库（载荷 database）');
      expect(app.selectedTable, 'users', reason: '表高亮（载荷 table）');
      expect(app.aiPanelFullscreen, isTrue,
          reason: 'focus_sidebar 不退出工作台（仅侧栏定位）');

      final List<AuditLogEntry> entries = AuditLogService()
          .getRecentEntries(limit: 10000);
      expect(entries, hasLength(auditBefore + 1));
      expect(entries.first.agentTool, 'focus_sidebar');
      expect(entries.first.gateDecision, AgentGateDecision.na);
      expect(entries.first.success, isTrue);
      expect(entries.first.agentRunId, 'run_f1');
      expect(find.text(l10n.agentSuggestBadgeApplied), findsOneWidget);
    });
  });
}
