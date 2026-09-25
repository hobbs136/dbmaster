// T23 AgentPlanCard 组件测试（ui 规格 design-ai-agent-ui.md §3.7 八条验收
// 逐条 + §3.2/§3.3/§3.4/§3.5/§3.6 结构与状态矩阵）。
//
// 覆盖：§3.7-1 不可逆双呈现（AC9.5 视觉可证）/ §3.7-2 estimatedRows null →
// 「估算不可用」/ §3.7-3 9 态 + consumed 矩阵（chip 文案/图标 + 动作行存在性；
// 左色条色按组件级测试纪律「断言功能而非样式」不作色值断言，色条以
// statusBarKey 结构锚点呈现 + 双主题可构建覆盖，颜色走查归 ui 规格
// §10.2 真机复验）/ §3.7-4 批准前零回调（AC9.1 组件面互补）+ 批准钮在末位 +
// Fix-E 会话放行勾选行（不勾选 → forSession=false；勾选 → true，AC9.3 勾选
// 路径）/ §3.7-5 partialFailed 三段计数与语句块图标交叉一致 + 生成回退只发
// 回调零执行 / §3.7-6 consumed 无动作 + 提示行 / §3.7-7 无内层滚动 + SQL
// 全文可选中 / §3.7-8 键盘序（复制钮 → 勾选行 → 拒绝 → 批准；Space/Enter
// 触发；Esc 交还上级）/ 回退计划标识行 / 来源标注 / 复制一致 / 暗亮主题可构建。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/organisms/ai_workbench/agents/agent_plan_card.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentRunContext;
import 'package:dbmaster/services/ai/agent/agent_plan.dart';

Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 720,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness, useMaterial3: true),
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    ),
  ),
);

const String kSql = 'UPDATE orders SET status = 1 WHERE id IN (1, 2, 3)';
const String kRollback = 'UPDATE orders SET status = 0 WHERE id IN (1, 2, 3)';

/// 步 fixture（三要素齐备基线：SQL + 估算 + 回滚）。
AgentPlanStep mkStep({
  String sql = kSql,
  AgentPlanStepKind kind = AgentPlanStepKind.dml,
  int? estimatedRows = 12043,
  AgentRowsEstimateSource source = AgentRowsEstimateSource.explain,
  String? rollbackSql = kRollback,
  AgentRollbackSource? rollbackSource = AgentRollbackSource.model,
  bool irreversible = false,
  AgentPlanStepStatus runtime = AgentPlanStepStatus.pending,
  String? error,
  AgentPlanDmlRiskTier dmlRiskTier = AgentPlanDmlRiskTier.none,
  List<String> dmlRiskTriggers = const <String>[],
}) {
  final AgentPlanStep s = AgentPlanStep(
    sql: sql,
    kind: kind,
    estimatedRows: estimatedRows,
    estimatedRowsSource: source,
    rollbackSql: rollbackSql,
    rollbackSource: rollbackSource,
    irreversible: irreversible,
    dmlRiskTier: dmlRiskTier,
    dmlRiskTriggers: dmlRiskTriggers,
  );
  s.runtime
    ..status = runtime
    ..error = error;
  return s;
}

/// 计划 fixture（三步基线：done / failed / skipped 可覆写 runtime）。
AgentActionPlan mkPlan(
  AgentPlanStatus status, {
  bool isConsumed = false,
  List<AgentPlanStep>? steps,
  String? rollbackOfPlanId,
}) {
  final List<AgentPlanStep> base =
      steps ??
      <AgentPlanStep>[
        mkStep(runtime: AgentPlanStepStatus.done),
        mkStep(
          runtime: AgentPlanStepStatus.failed,
          error: 'duplicate key value violates unique constraint "orders_pkey"',
        ),
        mkStep(runtime: AgentPlanStepStatus.skipped),
      ];
  return AgentActionPlan(
    planId: 'plan_test_1',
    runId: 'run_plan',
    ctx: const AgentRunContext(
      runId: 'run_plan',
      dbType: DatabaseType.mysql,
      readOnly: false,
    ),
    steps: base,
    status: status,
    rollbackOfPlanId: rollbackOfPlanId,
    isConsumed: isConsumed,
  );
}

/// 记录回调触发的宿主（回调只发信号；执行计数恒可断言——AC9.1 组件面）。
/// approve 按 forSession 勾选态记录：未勾选 → `approve`；勾选 →
/// `approve:session`（Fix-E）。
class _CallbackLog {
  final List<String> calls = <String>[];

  AgentPlanCallbacks get callbacks => AgentPlanCallbacks(
    onApprove: ({required bool forSession}) =>
        calls.add(forSession ? 'approve:session' : 'approve'),
    onReject: () => calls.add('reject'),
    onGenerateRollback: () => calls.add('generateRollback'),
    onTerminalReplay: () => calls.add('terminalReplay'),
  );
}

/// 断言主焦点当前落在 [key] 子树内（T12 测试同款 helper）。
bool primaryFocusWithin(Key key) {
  final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  var within = false;
  ctx.visitAncestorElements((Element el) {
    if (el.widget.key == key) {
      within = true;
      return false;
    }
    return true;
  });
  return within;
}

void main() {
  final AppLocalizationsEn l10n = AppLocalizationsEn();

  group('§3.7-1 不可逆双呈现（AC9.5 三要素齐备性可判定）', () {
    testWidgets('rollbackSql null 且 irreversible → 不可逆徽标 + 行内说明同现', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.approved,
              steps: <AgentPlanStep>[
                mkStep(
                  rollbackSql: null,
                  rollbackSource: null,
                  irreversible: true,
                  kind: AgentPlanStepKind.ddl,
                ),
              ],
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 两处呈现：语句块第 1 行「不可逆」徽标 + 第 3 行行内说明（§3.3③）。
      expect(find.text(l10n.agentPlanIrreversible), findsOneWidget);
      expect(find.text(l10n.agentPlanNoRollback), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsWidgets);
    });

    testWidgets('可回滚步：无不可逆徽标；回滚全文 + 来源标注同行', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.approved,
              steps: <AgentPlanStep>[mkStep()],
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentPlanIrreversible), findsNothing);
      expect(find.text(l10n.agentPlanNoRollback), findsNothing);
      // 回滚全文（§3.3③ maxLines 2 + tooltip）+ 来源标注（§9-A3）。
      expect(find.textContaining(kRollback), findsOneWidget);
      expect(
        find.textContaining(l10n.agentPlanRollbackSourceModel),
        findsOneWidget,
      );
    });
  });

  group('§3.7-2 estimatedRows null → 估算不可用（非 0 / 非空）', () {
    testWidgets('null 估算 → 「估算不可用」；有值 → 数值 + 来源同行', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.approved,
              steps: <AgentPlanStep>[
                mkStep(
                  estimatedRows: null,
                  source: AgentRowsEstimateSource.unavailable,
                ),
              ],
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.agentPlanEstimateUnavailable), findsOneWidget);
      expect(find.textContaining('0 rows'), findsNothing);

      // 有值：mono 数值 + 「EXPLAIN estimate」来源标注（§3.3② 同行追加）。
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.approved,
              steps: <AgentPlanStep>[mkStep()],
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('12,043 rows'), findsOneWidget);
      expect(
        find.textContaining(l10n.agentPlanEstimateSourceExplain),
        findsOneWidget,
      );
    });
  });

  group('§3.7-3 9 态 + consumed 矩阵（chip 文案 / 动作行存在性）', () {
    /// 逐态断言（矩阵行：chip 标签 + 动作行存在性）。
    Future<void> pumpState(AgentActionPlan plan, WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(AgentPlanCard(plan: plan, callbacks: _CallbackLog().callbacks)),
      );
      // executing 态含持续 spinner（重复 Ticker），不 pumpAndSettle。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    void expectNoActions() {
      expect(find.byKey(AgentPlanCard.approveButtonKey), findsNothing);
      expect(find.byKey(AgentPlanCard.rejectButtonKey), findsNothing);
      expect(find.byKey(AgentPlanCard.sessionCheckboxKey), findsNothing);
    }

    testWidgets('pendingApproval：待批准 chip + 动作行', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.pendingApproval), tester);
      expect(find.text(l10n.agentPlanStatusPending), findsOneWidget);
      expect(find.byKey(AgentPlanCard.approveButtonKey), findsOneWidget);
      expect(find.byKey(AgentPlanCard.rejectButtonKey), findsOneWidget);
      // 影响概要一行仅 pendingApproval（§3.1）。
      expect(find.byKey(AgentPlanCard.impactSummaryKey), findsOneWidget);
    });

    testWidgets('approved：已批准 chip，动作消失', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.approved), tester);
      expect(find.text(l10n.agentPlanStatusApproved), findsOneWidget);
      expectNoActions();
    });

    testWidgets('executing：Running n/m chip（done 计数），动作消失', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.executing), tester);
      expect(find.text(l10n.agentPlanStatusExecuting(1, 3)), findsOneWidget);
      expectNoActions();
    });

    testWidgets('done：已执行 chip 全绿，动作消失', (tester) async {
      await pumpState(
        mkPlan(
          AgentPlanStatus.done,
          steps: <AgentPlanStep>[
            mkStep(runtime: AgentPlanStepStatus.done),
            mkStep(runtime: AgentPlanStepStatus.done),
            mkStep(runtime: AgentPlanStepStatus.done),
          ],
        ),
        tester,
      );
      expect(find.text(l10n.agentPlanStatusDone), findsOneWidget);
      expectNoActions();
    });

    testWidgets('partialFailed：部分失败 chip + 失败边界区', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.partialFailed), tester);
      expect(find.text(l10n.agentPlanStatusPartialFailed), findsOneWidget);
      expectNoActions();
      expect(
        find.byKey(AgentPlanCard.generateRollbackButtonKey),
        findsOneWidget,
      );
    });

    testWidgets('rollbackOffered：待回退 chip + 提示行，无动作', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.rollbackOffered), tester);
      expect(find.text(l10n.agentPlanStatusRollbackOffered), findsOneWidget);
      expect(find.byKey(AgentPlanCard.rollbackPendingHintKey), findsOneWidget);
      expectNoActions();
    });

    testWidgets('rolledBack：已回退 chip，动作消失', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.rolledBack), tester);
      expect(find.text(l10n.agentPlanStatusRolledBack), findsOneWidget);
      expectNoActions();
    });

    testWidgets('rejected：已拒绝 chip，全文仍可读（审计痕迹），动作消失', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.rejected), tester);
      expect(find.text(l10n.agentPlanStatusRejected), findsOneWidget);
      // 基线三步同 SQL：全文仍可读（每步 SQL 块都渲染）。
      expect(find.textContaining(kSql), findsWidgets);
      expectNoActions();
    });

    testWidgets('consumed 叠加：继承终态 chip + 提示行 + 动作不渲染（§3.7-6）', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.done, isConsumed: true), tester);
      // chip 继承终态（done）而非 consumed 文案。
      expect(find.text(l10n.agentPlanStatusDone), findsOneWidget);
      expect(find.byKey(AgentPlanCard.consumedHintKey), findsOneWidget);
      expect(find.text(l10n.agentPlanConsumedHint), findsOneWidget);
      expectNoActions();
      expect(find.byKey(AgentPlanCard.generateRollbackButtonKey), findsNothing);
    });

    testWidgets('字面 consumed 枚举（防御）：中性档 + 提示行', (tester) async {
      await pumpState(mkPlan(AgentPlanStatus.consumed), tester);
      expect(find.byKey(AgentPlanCard.consumedHintKey), findsOneWidget);
      expectNoActions();
    });
  });

  group('§3.7-4 pendingApproval 动作行（批准前零执行 + 批准钮末位）', () {
    testWidgets('泵卡不点击：回调计数 0（AC9.1 组件面互补）；批准钮在拒绝之后', (tester) async {
      final _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(AgentPlanStatus.pendingApproval),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 批准前无任何执行（协作回调零触发）。
      expect(log.calls, isEmpty);
      // 批准钮在最右（末位，§3.6）。
      final Rect reject = tester.getRect(
        find.byKey(AgentPlanCard.rejectButtonKey),
      );
      final Rect approve = tester.getRect(
        find.byKey(AgentPlanCard.approveButtonKey),
      );
      expect(approve.right, greaterThanOrEqualTo(reject.right));

      // 点击批准 → 只发 approve 回调（无 reject / 无其它信号）。
      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      await tester.pump();
      expect(log.calls, <String>['approve']);
    });

    testWidgets('拒绝 → 只发 reject 回调', (tester) async {
      final _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(AgentPlanStatus.pendingApproval),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentPlanCard.rejectButtonKey));
      await tester.pump();
      expect(log.calls, <String>['reject']);
    });

    testWidgets('Fix-E：不勾选批准 → forSession=false；勾选后批准 → true', (
      tester,
    ) async {
      // 阶段一：未勾选直接批准 → forSession=false（approved 单次语义）。
      _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(AgentPlanStatus.pendingApproval),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 勾选行在位（28px 授予入口，文案/tooltip 复用确认卡同语义 key）。
      expect(find.byKey(AgentPlanCard.sessionCheckboxKey), findsOneWidget);
      expect(find.text(l10n.agentConfirmAllowSession), findsOneWidget);
      // 未勾选：勾选框无勾图形。
      expect(
        find.descendant(
          of: find.byKey(AgentPlanCard.sessionCheckboxKey),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      await tester.pump();
      expect(log.calls, <String>['approve']);

      // 阶段二：勾选「本会话内允许」→ 批准回调携带 forSession=true。
      log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              rollbackOfPlanId: 'plan_src_9',
            ),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentPlanCard.sessionCheckboxKey));
      await tester.pump();
      // 勾选图形出现（accentBlue 填充 + check）。
      expect(
        find.descendant(
          of: find.byKey(AgentPlanCard.sessionCheckboxKey),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
      await tester.pump();
      expect(log.calls, <String>['approve:session']);
    });
  });

  group('§3.7-5 partialFailed 失败边界（三段一致 + 回退入口零执行）', () {
    testWidgets('三段汇总计数与语句块状态图标逐块交叉一致', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(AgentPlanStatus.partialFailed),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 汇总行（§3.5）：Done 1 / Failed 1 / Skipped 1。
      expect(find.text(l10n.agentPlanBoundaryTitle), findsOneWidget);
      expect(find.text(l10n.agentPlanBoundaryDone(1)), findsOneWidget);
      expect(find.text(l10n.agentPlanBoundaryFailed(1)), findsOneWidget);
      expect(find.text(l10n.agentPlanBoundaryRemaining(1)), findsOneWidget);
      // 逐块交叉：step1 circleCheck / step2 circleAlert / step3 circleSlash。
      expect(
        find.descendant(
          of: find.byKey(AgentPlanCard.stepBlockKey(0)),
          matching: find.byIcon(LucideIcons.circleCheck),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(AgentPlanCard.stepBlockKey(1)),
          matching: find.byIcon(LucideIcons.circleAlert),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(AgentPlanCard.stepBlockKey(2)),
          matching: find.byIcon(LucideIcons.circleSlash),
        ),
        findsOneWidget,
      );
      // 失败原因行 = 首个 failed 步的 runtime.error。
      expect(
        find.text(
          l10n.agentPlanFailureReason(
            'duplicate key value violates unique constraint "orders_pkey"',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('[生成回退计划] 存在；点击只发回调不执行任何语句', (tester) async {
      final _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(AgentPlanStatus.partialFailed),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(log.calls, isEmpty);
      await tester.tap(find.byKey(AgentPlanCard.generateRollbackButtonKey));
      await tester.pump();
      // 只发 generateRollback 信号（AC11.3：永不自动执行）。
      expect(log.calls, <String>['generateRollback']);
    });
  });

  group('§3.7-7 无内层滚动 + SQL 全文可选中', () => _noInnerScrollGroup(l10n));

  group('§3.7-8 键盘序', () {
    testWidgets('Tab = 复制钮 → 勾选行 → 拒绝 → 批准；Space/Enter 触发；Esc 交还上级', (
      tester,
    ) async {
      final _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              steps: <AgentPlanStep>[mkStep()],
            ),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentPlanCard.stepCopyButtonKey(0)),
        isTrue,
        reason: 'Tab#1 落语句块复制钮（§3.7-8）',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentPlanCard.sessionCheckboxKey),
        isTrue,
        reason: 'Tab#2 落会话放行勾选行（Fix-E 键盘序：勾选行 → 拒绝 → 批准）',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentPlanCard.rejectButtonKey),
        isTrue,
        reason: 'Tab#3 落拒绝',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentPlanCard.approveButtonKey),
        isTrue,
        reason: 'Tab#4 落批准',
      );

      // Enter 触发批准（§3.7-8：批准可用 Space/Enter 触发）；未勾选 →
      // forSession=false。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log.calls, <String>['approve']);
    });

    testWidgets('Space 触发拒绝；Esc 后焦点离开卡内控件', (tester) async {
      final _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              steps: <AgentPlanStep>[mkStep()],
            ),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(AgentPlanCard.rejectButtonKey), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(log.calls, <String>['reject']);

      // Esc：焦点交还上级（不在卡内控件上停留）。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentPlanCard.rejectButtonKey),
        isFalse,
        reason: 'Esc 后焦点不得停留在卡内控件（卡头重聚焦由嵌块宿主接线）',
      );
    });

    testWidgets('Fix-E：勾选行 Space 切勾选 → 批准键 Enter 携带 forSession=true', (
      tester,
    ) async {
      final _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              steps: <AgentPlanStep>[mkStep()],
            ),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tab#1 复制钮 → Tab#2 勾选行；Space 切勾选（确认卡同款键语义）。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(AgentPlanCard.sessionCheckboxKey), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(AgentPlanCard.sessionCheckboxKey),
          matching: find.byIcon(LucideIcons.check),
        ),
        findsOneWidget,
        reason: 'Space 已切为勾选态',
      );

      // Tab#3 拒绝 → Tab#4 批准；Enter 提交 → 回调携带 forSession=true。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(AgentPlanCard.approveButtonKey), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log.calls, <String>['approve:session']);
    });

    testWidgets('Fix-E：勾选行 Esc 焦点交还上级（确认卡同款）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              steps: <AgentPlanStep>[mkStep()],
            ),
            callbacks: _CallbackLog().callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(primaryFocusWithin(AgentPlanCard.sessionCheckboxKey), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        primaryFocusWithin(AgentPlanCard.sessionCheckboxKey),
        isFalse,
        reason: 'Esc 后焦点不得停留在卡内控件（卡头重聚焦由嵌块宿主接线）',
      );
    });
  });

  group('结构面与回归防线', () {
    testWidgets('回退计划标识行：rotateCcw + 回退自 planId（AC11.2 可回溯）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              rollbackOfPlanId: 'plan_src_9',
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(AgentPlanCard.rollbackOfKey), findsOneWidget);
      expect(find.text(l10n.agentPlanRollbackOf('plan_src_9')), findsOneWidget);
    });

    testWidgets('M6 ②：high 步 → 「需显式确认」徽标 + triggers 摘要行渲染；none 步双无', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              steps: <AgentPlanStep>[
                mkStep(
                  sql: 'ALTER TABLE users DROP COLUMN legacy',
                  kind: AgentPlanStepKind.ddl,
                  rollbackSql: null,
                  rollbackSource: null,
                  irreversible: true,
                  dmlRiskTier: AgentPlanDmlRiskTier.high,
                  dmlRiskTriggers: const <String>['alterDropColumn'],
                ),
                mkStep(),
              ],
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // high 步（步 0）：徽标 + triggers 行，trigger 名直排（经典横幅同例）。
      expect(find.byKey(AgentPlanCard.stepDmlHighBadgeKey(0)), findsOneWidget);
      expect(find.text(l10n.agentPlanDmlHighBadge), findsOneWidget);
      expect(find.byKey(AgentPlanCard.stepDmlTriggersKey(0)), findsOneWidget);
      expect(
        find.text(l10n.agentPlanDmlHighTriggers('alterDropColumn')),
        findsOneWidget,
      );
      // none 步（步 1）：徽标与 triggers 行均不渲染。
      expect(find.byKey(AgentPlanCard.stepDmlHighBadgeKey(1)), findsNothing);
      expect(find.byKey(AgentPlanCard.stepDmlTriggersKey(1)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('M6 ②：多 trigger 摘要逗号直排 + 暗主题可构建', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.pendingApproval,
              steps: <AgentPlanStep>[
                mkStep(
                  sql: 'DELETE FROM users WHERE id = 1',
                  rollbackSql: null,
                  rollbackSource: null,
                  irreversible: true,
                  dmlRiskTier: AgentPlanDmlRiskTier.high,
                  dmlRiskTriggers: const <String>[
                    'dmlWithoutLimit',
                    'sqlInjection',
                  ],
                ),
              ],
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          l10n.agentPlanDmlHighTriggers('dmlWithoutLimit, sqlInjection'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('consumed 提示行点击 → 只发 terminalReplay 信号（终态重放零库操作）', (
      tester,
    ) async {
      final _CallbackLog log = _CallbackLog();
      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(AgentPlanStatus.done, isConsumed: true),
            callbacks: log.callbacks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AgentPlanCard.consumedHintKey));
      await tester.pump();
      expect(log.calls, <String>['terminalReplay']);
    });

    testWidgets('SQL 全文块复制内容一致（沿 M1 复制语汇）', (tester) async {
      String? clipText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          clipText = args?['text'] as String?;
          return null;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        _wrap(
          AgentPlanCard(
            plan: mkPlan(
              AgentPlanStatus.approved,
              steps: <AgentPlanStep>[mkStep()],
            ),
            callbacks: const AgentPlanCallbacks(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      await tester.tap(find.byKey(AgentPlanCard.stepCopyButtonKey(0)));
      await tester.pump();
      expect(clipText, kSql);
      expect(find.text(l10n.messageCopied), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('暗/亮主题均可构建（异常为空；色值走查归双主题人工复验）', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _wrap(
            AgentPlanCard(
              plan: mkPlan(AgentPlanStatus.pendingApproval),
              callbacks: const AgentPlanCallbacks(),
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(AgentPlanCard.headerKey), findsOneWidget);
        expect(find.byKey(AgentPlanCard.statusBarKey), findsOneWidget);
      }
    });
  });
}

/// §3.7-7：计划块无内层滚动（卡体 360 统一滚动约束在嵌块宿主，§3.1）+
/// SQL 全文 SelectableText 不截断。（内容规模控制在测试面板 600px 高内
/// ——本卡无内层滚动是规格本身，宿主 360 滚动由轨迹卡测试覆盖。）
void _noInnerScrollGroup(AppLocalizationsEn l10n) {
  testWidgets('无 Scrollable/ScrollView；SQL 全文可选中', (tester) async {
    final String longSql = List.generate(
      20,
      (int i) => '-- line $i',
    ).join('\n');
    await tester.pumpWidget(
      _wrap(
        AgentPlanCard(
          plan: mkPlan(
            AgentPlanStatus.approved,
            steps: <AgentPlanStep>[mkStep(sql: longSql)],
          ),
          callbacks: const AgentPlanCallbacks(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 无内层滚动（§3.7-7 单 Scrollable 断言的组件面）：卡面不引入任何滚动
    // 容器——树中唯一 Scrollable 属于 SelectableText 内部原生结构（文本选择
    // 自带），并有 SingleChildScrollView findsNothing 双证。
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    // SQL 全文可选中、不截断。
    expect(find.textContaining('-- line 19'), findsOneWidget);
  });
}
