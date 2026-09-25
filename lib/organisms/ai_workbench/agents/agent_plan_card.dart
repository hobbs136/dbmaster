//! 行动计划卡（tasks-ai-agent.md T23；ui 规格 design-ai-agent-ui.md §3 全节
//! 为唯一视觉依据，数值/色对逐字执行）。
//!
//! 面三：计划块（轨迹卡体内嵌块，§1.6/§3.1）——**无独立卡框**（不重复
//! bgSecondary + 描边，避免卡中卡的双描边），仅 3px 状态左色条（§3.4 逐态）
//! + 顶部 1px divider 与步列表分隔；块内**不做内层滚动**（§3.7-7：卡体 360
//! 统一滚动、SQL 全文 SelectableText 不截断）。
//!
//! 状态机视觉（§3.4）：9 值 + isConsumed 叠加。plan 是就地可变值对象
//! （`agent_plan.dart` 文件头消费说明）：本卡为纯重建即刷新——每次 build
//! 重读 plan 全量，唯一刷新通道 = 宿主经 `AgentPlanExecutionDeps
//! .onStepStateChange` 触发携带本卡的子树重建（T27/T28 装配）；批准/拒绝/
//! 生成回退**只发回调不执行**（执行归宿主/T28——AC9.1 批准前零库操作）。
//!
//! 卡面语言沿 §0.1/§0.2：文字只用中性三档 + error；语义色只作图形/描边/
//! 色条/实测合规填充底。动作钮尺寸 = `minimumSize(Size.zero,32) +
//! fixedSize(fromHeight(32))`（T26 验证的 M3 正确姿势；agent_confirm_card
//! 的 `fixedSize(0,32)` 钳制问题只登记不修——跟进池已有序）。pendingApproval
//! 动作区含「本会话内允许」勾选行（Fix-E，沿确认卡勾选行先例复用其 ARB
//! key——两卡同门语义；批准回调携带 forSession 勾选态）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/ai/agent/agent_plan.dart'
    show
        AgentActionPlan,
        AgentPlanDmlRiskTier,
        AgentPlanStatus,
        AgentPlanStep,
        AgentPlanStepKind,
        AgentPlanStepStatus,
        AgentRollbackSource,
        AgentRowsEstimateSource;
import '../../../theme/app_colors.dart';

/// 计划卡回调集（任务书接口草案 PlanCallbacks；回调只发信号，执行在 T28
/// 接线层：批准 → executor、拒绝 → 宿主置 rejected、生成回退 → 组装新计划
/// 过同一 L1 门，永不自动执行——AC11.3 铁律）。
class AgentPlanCallbacks {
  /// 常量构造。
  const AgentPlanCallbacks({
    this.onApprove,
    this.onReject,
    this.onGenerateRollback,
    this.onTerminalReplay,
  });

  /// 批准并执行（pendingApproval 动作行主动作）。forSession = 卡面「本会话
  /// 内允许」勾选态（Fix-E，沿确认卡同门语义）：false → approved；true →
  /// approvedForSession（AC9.3 L1 会话放行，落账与执行归宿主桥）。
  final void Function({required bool forSession})? onApprove;

  /// 拒绝（pendingApproval 动作行次要动作）。
  final VoidCallback? onReject;

  /// 生成回退计划（partialFailed 失败边界入口；点击只发起回调，不执行）。
  final VoidCallback? onGenerateRollback;

  /// 终态重放观察（consumed 提示行点击时触发；宿主可用于防重观测，卡面
  /// 终态呈现不产任何库操作——AC11.4）。
  final VoidCallback? onTerminalReplay;
}

/// 工作台行动计划卡（ui 规格 §3；与轨迹卡嵌块宿主 T13 机制对接）。
class AgentPlanCard extends StatelessWidget {
  /// 常量构造（接口草案锁定签名：plan + callbacks，回调只发信号）。
  const AgentPlanCard({super.key, required this.plan, required this.callbacks});

  /// 行动计划（就地可变值对象；每次 build 重读全量）。
  final AgentActionPlan plan;

  /// 动作回调集。
  final AgentPlanCallbacks callbacks;

  /// 块头（34，恒显）。
  static const Key headerKey = ValueKey('agent_plan_card_header');

  /// 3px 状态左色条（§3.4 逐态；结构性断言锚点）。
  static const Key statusBarKey = ValueKey('agent_plan_card_status_bar');

  /// 状态 chip。
  static const Key statusChipKey = ValueKey('agent_plan_card_status_chip');

  /// 「写操作」徽标（§3.2，errorContainer 底 + textPrimary 文字修正版）。
  static const Key writeBadgeKey = ValueKey('agent_plan_card_write_badge');

  /// 影响概要行（仅 pendingApproval，§3.1）。
  static const Key impactSummaryKey = ValueKey(
    'agent_plan_card_impact_summary',
  );

  /// 回退计划标识行（rollbackOfPlanId 非空时，§3.2）。
  static const Key rollbackOfKey = ValueKey('agent_plan_card_rollback_of');

  /// 失败边界区（partialFailed，§3.5）。
  static const Key boundaryKey = ValueKey('agent_plan_card_boundary');

  /// 失败原因行。
  static const Key failureReasonKey = ValueKey(
    'agent_plan_card_failure_reason',
  );

  /// 「生成回退计划」入口。
  static const Key generateRollbackButtonKey = ValueKey(
    'agent_plan_card_generate_rollback',
  );

  /// 「批准并执行」主动作。
  static const Key approveButtonKey = ValueKey('agent_plan_card_approve');

  /// 「拒绝」次要动作。
  static const Key rejectButtonKey = ValueKey('agent_plan_card_reject');

  /// 「本会话内允许」勾选行（Fix-E，沿确认卡勾选行先例；整行可点/可聚焦）。
  static const Key sessionCheckboxKey = ValueKey(
    'agent_plan_card_session_checkbox',
  );

  /// rollbackOffered 提示行（回退计划待批准）。
  static const Key rollbackPendingHintKey = ValueKey(
    'agent_plan_card_rollback_pending_hint',
  );

  /// consumed 提示行（终态重放防重提示）。
  static const Key consumedHintKey = ValueKey('agent_plan_card_consumed_hint');

  /// 语句块（按步序号）。
  static Key stepBlockKey(int index) => ValueKey('agent_plan_card_step_$index');

  /// 语句块「复制」动作（按步序号）。
  static Key stepCopyButtonKey(int index) =>
      ValueKey('agent_plan_card_step_copy_$index');

  /// high 档 DML「需显式确认」徽标（M6，按步序号）。
  static Key stepDmlHighBadgeKey(int index) =>
      ValueKey('agent_plan_card_step_dml_high_$index');

  /// high 档 DML triggers 摘要行（M6，按步序号）。
  static Key stepDmlTriggersKey(int index) =>
      ValueKey('agent_plan_card_step_dml_triggers_$index');

  @override
  Widget build(BuildContext context) {
    final ThemeColors colors = context.themeColors;
    final _PlanVisual visual = _statusVisual(context);
    return Stack(
      children: [
        // 3px 状态左色条（无独立卡框，随宿主卡左缘呈现，§3.1/§3.4）。
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          child: Container(key: statusBarKey, width: 3, color: visual.bar),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部 1px divider：无卡框时与步列表的分隔（§3.1）。
              Divider(height: 1, thickness: 1, color: colors.dividerColor),
              _buildHeader(context, visual),
              _AgentPlanBody(plan: plan, callbacks: callbacks),
            ],
          ),
        ),
      ],
    );
  }

  /// 状态视觉（§3.4 矩阵：左色条 / chip 图标与色 / chip 标签）。isConsumed
  /// 是叠加标记（终态 status 保留，执行器不设 consumed 枚举值）——chip 与
  /// 色条继承其终态；字面 consumed 枚举值防御性落中性档。
  _PlanVisual _statusVisual(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final AgentPlanStatus status = plan.status;
    switch (status) {
      case AgentPlanStatus.pendingApproval:
        return _PlanVisual(
          bar: colors.error,
          icon: LucideIcons.triangleAlert,
          iconColor: colors.error,
          label: l10n.agentPlanStatusPending,
        );
      case AgentPlanStatus.approved:
        return _PlanVisual(
          bar: colors.accentBlue,
          icon: LucideIcons.circleCheck,
          iconColor: colors.accentBlue,
          label: l10n.agentPlanStatusApproved,
        );
      case AgentPlanStatus.executing:
        return _PlanVisual(
          bar: colors.accentBlue,
          icon: LucideIcons.circleCheck,
          iconColor: colors.accentBlue,
          label: l10n.agentPlanStatusExecuting(_doneCount, plan.steps.length),
          spinner: true,
        );
      case AgentPlanStatus.done:
        return _PlanVisual(
          bar: colors.success,
          icon: LucideIcons.circleCheck,
          iconColor: colors.success,
          label: l10n.agentPlanStatusDone,
        );
      case AgentPlanStatus.partialFailed:
        return _PlanVisual(
          bar: colors.error,
          icon: LucideIcons.triangleAlert,
          iconColor: colors.error,
          label: l10n.agentPlanStatusPartialFailed,
        );
      case AgentPlanStatus.rollbackOffered:
        return _PlanVisual(
          bar: colors.warning,
          icon: LucideIcons.undo2,
          iconColor: colors.warning,
          label: l10n.agentPlanStatusRollbackOffered,
        );
      case AgentPlanStatus.rolledBack:
        return _PlanVisual(
          bar: colors.success,
          icon: LucideIcons.rotateCcw,
          iconColor: colors.success,
          label: l10n.agentPlanStatusRolledBack,
        );
      case AgentPlanStatus.rejected:
        return _PlanVisual(
          bar: colors.borderStrong,
          icon: LucideIcons.ban,
          iconColor: colors.textMuted,
          label: l10n.agentPlanStatusRejected,
        );
      case AgentPlanStatus.consumed:
        // 防御分支：执行器不设置该值（isConsumed 标记承担），宿主聚合态
        // 直传时按中性惰性档呈现。
        return _PlanVisual(
          bar: colors.borderStrong,
          icon: LucideIcons.ban,
          iconColor: colors.textMuted,
          label: l10n.agentPlanConsumedHint,
        );
    }
  }

  /// 已完成步数（executing chip 的 n/m）。
  int get _doneCount => plan.steps
      .where((AgentPlanStep s) => s.runtime.status == AgentPlanStepStatus.done)
      .length;

  /// 块头 34（§3.2）：listChecks 16 状态色 + 标题 12 w600 textPrimary +
  /// `{n} 条语句` mono 11 textMuted + 写操作徽标 + 状态 chip。无独立 chevron
  /// （块级无折叠语义，未决不可折叠由宿主强制展开保证，§3.1）。
  Widget _buildHeader(BuildContext context, _PlanVisual visual) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    return SizedBox(
      key: headerKey,
      height: AppDesignSystem.toolCardHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
        child: Row(
          children: [
            Icon(LucideIcons.listChecks, size: 16, color: visual.bar),
            const SizedBox(width: AppDesignSystem.space2),
            Flexible(
              child: Text(
                l10n.agentPlanTitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            Text(
              l10n.agentPlanStatementCount(plan.steps.length),
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            _buildWriteBadge(context),
            const SizedBox(width: AppDesignSystem.space2),
            // chip 弹性收缩（长标签——如 consumed 防御态提示——内层 Text
            // ellipsis 生效的前提，§0.6 标题优先被压缩口径）。
            Flexible(child: _buildStatusChip(context, visual)),
          ],
        ),
      ),
    );
  }

  /// 写操作徽标（§3.2）：errorContainer 底 + error 图标 10 + 文字
  /// textPrimary w600 11（§0.2 修正：error-on-errorContainer 不达正文线；
  /// 标签复用 M1 sql_tool_card 同款 key `workbenchSqlWriteBadge`——同一
  /// 卡面语汇，不碰 ARB）。
  Widget _buildWriteBadge(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    return Container(
      key: writeBadgeKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.triangleAlert, size: 10, color: colors.error),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            l10n.workbenchSqlWriteBadge,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 状态 chip（高 18：底 bgTertiary + 10px 语义图标 + 11px textPrimary
  /// w500，§3.2；executing 用旋转 spinner）。
  Widget _buildStatusChip(BuildContext context, _PlanVisual visual) {
    final ThemeColors colors = context.themeColors;
    final Widget icon = visual.spinner
        ? _PlanSpinnerIcon(size: 10, color: colors.accentBlue)
        : Icon(visual.icon, size: 10, color: visual.iconColor);
    return Container(
      key: statusChipKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: AppDesignSystem.space1),
          Flexible(
            child: Text(
              visual.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态视觉元组（§3.4 矩阵行；私有）。
class _PlanVisual {
  const _PlanVisual({
    required this.bar,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.spinner = false,
  });

  /// 3px 左色条 / 卡头图标色。
  final Color bar;

  /// chip 图标。
  final IconData icon;

  /// chip 图标色。
  final Color iconColor;

  /// chip 标签。
  final String label;

  /// executing 态 chip 前置旋转 spinner。
  final bool spinner;
}

/// 卡内容体（影响概要 / 逐语句三要素 / 失败边界 / 动作行；私有 Stateful
/// 承载复制反馈与焦点节点，公开签名保持 Stateless 不变——沿确认卡先例）。
class _AgentPlanBody extends StatefulWidget {
  const _AgentPlanBody({required this.plan, required this.callbacks});

  final AgentActionPlan plan;
  final AgentPlanCallbacks callbacks;

  @override
  State<_AgentPlanBody> createState() => _AgentPlanBodyState();
}

class _AgentPlanBodyState extends State<_AgentPlanBody> {
  /// 复制反馈态（按步序号，2s 复位——M1 sql_tool_card 同款语义）。
  final Set<int> _copiedSteps = <int>{};

  /// 语句块「复制」钮焦点（键盘序 §3.7-8：复制钮 → 拒绝 → 批准——复制钮
  /// 进 Tab 序，与确认卡不同，ui 规格 §3.7-8 明示）。
  final Map<int, FocusNode> _copyFocusNodes = <int, FocusNode>{};

  late final FocusNode _rejectFocus;
  late final FocusNode _approveFocus;
  late final FocusNode _generateRollbackFocus;

  /// 会话放行勾选（Fix-E，沿确认卡：勾选后主动作回调携带
  /// forSession=true，宿主走 approvedForSession 路径，AC9.3）。
  bool _sessionAllowed = false;

  /// 勾选行焦点（Space 切勾选、Enter 提交主动作、Esc 回上级——确认卡
  /// 同款键语义；键盘序 §3.7-8：复制钮 → 勾选行 → 拒绝 → 批准）。
  late final FocusNode _sessionCheckboxFocus;

  @override
  void initState() {
    super.initState();
    _rejectFocus = FocusNode(onKeyEvent: _onEscKeyEvent);
    _approveFocus = FocusNode(onKeyEvent: _onEscKeyEvent);
    _generateRollbackFocus = FocusNode(onKeyEvent: _onEscKeyEvent);
    _sessionCheckboxFocus = FocusNode(onKeyEvent: _onCheckboxKeyEvent);
  }

  @override
  void didUpdateWidget(_AgentPlanBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 步集合变化防御：越界焦点节点退役（执行期步集合不变，纯防御）。
    for (final int index in List<int>.from(_copyFocusNodes.keys)) {
      if (index >= widget.plan.steps.length) {
        _copyFocusNodes.remove(index)?.dispose();
        _copiedSteps.remove(index);
      }
    }
  }

  @override
  void dispose() {
    for (final FocusNode node in _copyFocusNodes.values) {
      node.dispose();
    }
    _copyFocusNodes.clear();
    _sessionCheckboxFocus.dispose();
    _rejectFocus.dispose();
    _approveFocus.dispose();
    _generateRollbackFocus.dispose();
    super.dispose();
  }

  /// 动作钮 Esc：焦点交还上级（§0.4 逐级回退；卡头重聚焦由嵌块宿主接线）。
  KeyEventResult _onEscKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 勾选行键：Space 切勾选、Enter 提交主动作、Esc 回上级（Fix-E，确认卡
  /// 同款键语义——两卡同门语义，交互一致）。
  KeyEventResult _onCheckboxKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _toggleSession();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submitPrimary();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleSession() => setState(() => _sessionAllowed = !_sessionAllowed);

  /// 主动作提交：未勾选 → forSession=false（approved）；勾选 → true
  /// （approvedForSession，AC9.3）。执行归宿主桥，卡面只发回调。
  void _submitPrimary() {
    widget.callbacks.onApprove?.call(forSession: _sessionAllowed);
  }

  FocusNode _copyNode(int index) => _copyFocusNodes.putIfAbsent(
    index,
    () => FocusNode(onKeyEvent: _onEscKeyEvent),
  );

  Future<void> _copySql(int index, String sql) async {
    await Clipboard.setData(ClipboardData(text: sql));
    if (!mounted) return;
    setState(() => _copiedSteps.add(index));
    // 反馈 2s 后复位（确认卡同款；Future.delayed 回调无待释放资源）。
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _copiedSteps.remove(index)) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final AgentActionPlan plan = widget.plan;
    final bool consumed =
        plan.isConsumed || plan.status == AgentPlanStatus.consumed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2_5,
        0,
        AppDesignSystem.space2_5,
        AppDesignSystem.space2_5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (plan.rollbackOfPlanId != null) _buildRollbackOf(context),
          // 影响概要一行（仅 pendingApproval，§3.1）。
          if (plan.status == AgentPlanStatus.pendingApproval)
            _buildImpactSummary(context),
          const SizedBox(height: AppDesignSystem.space1),
          for (int i = 0; i < plan.steps.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppDesignSystem.space2),
            _buildStep(context, i, plan.steps[i]),
          ],
          // 失败边界（partialFailed 三段呈现，§3.5）。
          if (plan.status == AgentPlanStatus.partialFailed)
            _buildBoundary(context),
          // rollbackOffered：无动作 + 一行提示（§3.4）。
          if (plan.status == AgentPlanStatus.rollbackOffered)
            _buildRollbackPendingHint(context),
          // consumed：终态叠加提示行，动作不渲染（§3.4/AC11.4）。
          if (consumed) _buildConsumedHint(context),
          // pendingApproval 动作行（§3.6）。
          if (plan.status == AgentPlanStatus.pendingApproval && !consumed)
            _buildActions(context),
        ],
      ),
    );
  }

  // ── 回退计划标识（§3.2）─────────────────────────────────────────────────

  Widget _buildRollbackOf(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final String? rollbackOf = widget.plan.rollbackOfPlanId;
    return SizedBox(
      key: AgentPlanCard.rollbackOfKey,
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Tooltip(
            message: l10n.agentPlanRollbackBadge,
            child: Icon(LucideIcons.rotateCcw, size: 12, color: colors.warning),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Flexible(
            child: Text(
              rollbackOf == null ? '' : l10n.agentPlanRollbackOf(rollbackOf),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 影响概要（pendingApproval 一行，§3.1）───────────────────────────────

  /// 聚合规则（任务书未定数值，自决）：Σ 非 null 估算；全 null →
  /// 「估算不可用」（不显示部分和误导——个别步缺估算时以来源标注逐语句
  /// 行为准）。
  Widget _buildImpactSummary(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final List<AgentPlanStep> steps = widget.plan.steps;
    final bool anyEstimate = steps.any(
      (AgentPlanStep s) => s.estimatedRows != null,
    );
    final String valueText = anyEstimate
        ? l10n.agentPlanEstimateRows(
            NumberFormat.decimalPattern().format(
              steps.fold<int>(
                0,
                (int sum, AgentPlanStep s) => sum + (s.estimatedRows ?? 0),
              ),
            ),
          )
        : l10n.agentPlanEstimateUnavailable;
    return SizedBox(
      key: AgentPlanCard.impactSummaryKey,
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Text(
            l10n.agentPlanImpactLabel,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Flexible(
            child: Tooltip(
              message: valueText,
              child: Text(
                valueText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: colors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 逐语句三要素块（§3.3）───────────────────────────────────────────────

  Widget _buildStep(BuildContext context, int index, AgentPlanStep step) {
    return Container(
      key: AgentPlanCard.stepBlockKey(index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStepHeadRow(context, index, step),
          const SizedBox(height: AppDesignSystem.space1),
          _buildStepSqlBlock(context, index, step),
          const SizedBox(height: AppDesignSystem.space0_5),
          _buildStepMetaRow(context, step),
          // M6：high 步 triggers 摘要行（三要素面同位扩展，批准前可见）。
          if (step.dmlRiskTier == AgentPlanDmlRiskTier.high) ...<Widget>[
            const SizedBox(height: AppDesignSystem.space0_5),
            _buildStepDmlTriggersRow(context, index, step),
          ],
        ],
      ),
    );
  }

  /// 语句块第 1 行（24）：序号 + 类型徽标（DML/DDL 常量，不入 l10n）+
  /// 不可逆徽标（两处呈现之一）+ 行尾逐语句状态图标（§3.3）。可回滚步
  /// 第 1 行不加「回滚」徽标——§3.3 规格表只定义类型徽标与不可逆徽标，
  /// 回滚信息由第 3 行承载（示意图中的 [回滚 DELETE] 为示意）。
  Widget _buildStepHeadRow(
    BuildContext context,
    int index,
    AgentPlanStep step,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final String kindText = step.kind == AgentPlanStepKind.ddl ? 'DDL' : 'DML';
    return SizedBox(
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          // 类型徽标：mono 11 textSecondary on bgTertiary（textMuted 在
          // bgTertiary 上不达正文线禁用，§0.2/§3.3）。
          Semantics(
            label: l10n.agentPlanStepKind(kindText),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: colors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                kindText,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
          if (step.irreversible) ...<Widget>[
            const SizedBox(width: AppDesignSystem.space1_5),
            _buildIrreversibleBadge(context),
          ],
          // M6：high 档 DML「需显式确认」徽标（批准即覆盖的标注面）。
          if (step.dmlRiskTier == AgentPlanDmlRiskTier.high) ...<Widget>[
            const SizedBox(width: AppDesignSystem.space1_5),
            _buildDmlHighBadge(context, index),
          ],
          const Spacer(),
          if (_stepStatusIcon(context, step) != null)
            _stepStatusIcon(context, step)!,
        ],
      ),
    );
  }

  /// 不可逆徽标（§3.3 两处呈现之一：errorContainer 底 + error 图标 +
  /// textPrimary 文字）。
  Widget _buildIrreversibleBadge(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.triangleAlert, size: 10, color: colors.error),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            l10n.agentPlanIrreversible,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// high 档 DML 徽标（M6「需显式确认的步」标注）：bgTertiary 底 + warning
  /// 图标 + textPrimary w600 11——警示语义但非阻断（区别于不可逆徽标的
  /// errorContainer 底；文字保持中性档，§0.2 语义色只作图形/图标）。
  Widget _buildDmlHighBadge(BuildContext context, int index) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    return Container(
      key: AgentPlanCard.stepDmlHighBadgeKey(index),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.triangleAlert, size: 10, color: colors.warning),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            l10n.agentPlanDmlHighBadge,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// triggers 摘要行（M6，AC9.5 三要素面同位扩展）：warning 图标 12 +
  /// 「Triggers: a, b」11 textSecondary（trigger 名 = `RiskTrigger.name`
  /// 技术串，沿经典 DML 横幅 `t.name` 直排先例不入 l10n）；maxLines 2 +
  /// tooltip 全文，无内层滚动（§3.7-7）。
  Widget _buildStepDmlTriggersRow(
    BuildContext context,
    int index,
    AgentPlanStep step,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final String line = l10n.agentPlanDmlHighTriggers(
      step.dmlRiskTriggers.join(', '),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppDesignSystem.workbenchDenseRowHeight,
      ),
      child: Row(
        key: AgentPlanCard.stepDmlTriggersKey(index),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 12, color: colors.warning),
          const SizedBox(width: AppDesignSystem.space1),
          Flexible(
            child: Tooltip(
              message: line,
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 逐语句状态图标（§3.3 行尾；自决边界：pendingApproval/approved/rejected
  /// = 无（未进入执行）；执行族状态（executing/partialFailed/rollbackOffered/
  /// rolledBack/done）按 runtime 逐值映射——done/failed/skipped 与 §3.3 的
  /// executing、partialFailed、done 三列一致，rollbackOffered/rolledBack
  /// 保留最后已知的 runtime 边界（回退动在回退计划上，本计划步不再变）。
  Widget? _stepStatusIcon(BuildContext context, AgentPlanStep step) {
    final ThemeColors colors = context.themeColors;
    switch (widget.plan.status) {
      case AgentPlanStatus.pendingApproval:
      case AgentPlanStatus.approved:
      case AgentPlanStatus.rejected:
      case AgentPlanStatus.consumed:
        return null;
      case AgentPlanStatus.executing:
      case AgentPlanStatus.partialFailed:
      case AgentPlanStatus.rollbackOffered:
      case AgentPlanStatus.rolledBack:
      case AgentPlanStatus.done:
        break;
    }
    switch (step.runtime.status) {
      case AgentPlanStepStatus.done:
        return Icon(LucideIcons.circleCheck, size: 12, color: colors.success);
      case AgentPlanStepStatus.running:
        return _PlanSpinnerIcon(size: 10, color: colors.accentBlue);
      case AgentPlanStepStatus.failed:
        return Icon(LucideIcons.circleAlert, size: 12, color: colors.error);
      case AgentPlanStepStatus.pending:
      case AgentPlanStepStatus.skipped:
        return Icon(LucideIcons.circleSlash, size: 12, color: colors.textMuted);
    }
  }

  /// 语句块第 2 行：SQL 块（codeBlockBg / mono 11 / 1.4 / 全文可选中不截断
  /// + 块右上「复制」，§3.3①）。无内层滚动（§3.7-7，卡体统一滚动）。
  Widget _buildStepSqlBlock(
    BuildContext context,
    int index,
    AgentPlanStep step,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final bool copied = _copiedSteps.contains(index);
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.codeBlockBg,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            step.sql,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              color: colors.textPrimary,
            ),
          ),
        ),
        Positioned(
          top: AppDesignSystem.space1,
          right: AppDesignSystem.space1,
          child: InkWell(
            key: AgentPlanCard.stepCopyButtonKey(index),
            focusNode: _copyNode(index),
            onTap: () => _copySql(index, step.sql),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1,
                vertical: AppDesignSystem.space0_5,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    copied ? LucideIcons.check : LucideIcons.copy,
                    size: 12,
                    color: copied ? colors.success : colors.textMuted,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Text(
                    copied ? l10n.messageCopied : l10n.aiPanelCopy,
                    style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 语句块第 3 行（24）：影响 + 回滚（`·` 分隔，§3.3②③）。estimatedRows
  /// null → 「估算不可用」（非 0 非空）；rollbackSql null → 「不可逆 · 无
  /// 自动回滚方案」+ error 图标（两处呈现之二）；来源标注按 §3.3② 同行追加。
  Widget _buildStepMetaRow(BuildContext context, AgentPlanStep step) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final String estimateText = step.estimatedRows == null
        ? l10n.agentPlanEstimateUnavailable
        : '${l10n.agentPlanEstimateRows(NumberFormat.decimalPattern().format(step.estimatedRows))}'
              '（${_estimateSourceLabel(context, step.estimatedRowsSource)}）';
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppDesignSystem.workbenchDenseRowHeight,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.agentPlanImpactLabel,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Flexible(
            flex: 2,
            child: Tooltip(
              message: estimateText,
              child: Text(
                estimateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: colors.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Text('·', style: TextStyle(fontSize: 11, color: colors.textMuted)),
          const SizedBox(width: AppDesignSystem.space1_5),
          Text(
            l10n.agentPlanRollbackLabel,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          if (step.rollbackSql != null)
            Flexible(
              flex: 3,
              child: Tooltip(
                message:
                    '${step.rollbackSql}'
                    '（${_rollbackSourceLabel(context, step.rollbackSource)}）',
                child: Text(
                  '${step.rollbackSql}'
                  '（${_rollbackSourceLabel(context, step.rollbackSource)}）',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            )
          else
            Flexible(
              flex: 3,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    size: 12,
                    color: colors.error,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Flexible(
                    child: Text(
                      l10n.agentPlanNoRollback,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 估算来源标注（AC9.6 同行追加；§3.3② 字段补齐后的呈现形态）。
  String _estimateSourceLabel(
    BuildContext context,
    AgentRowsEstimateSource source,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    switch (source) {
      case AgentRowsEstimateSource.explain:
        return l10n.agentPlanEstimateSourceExplain;
      case AgentRowsEstimateSource.count:
        return l10n.agentPlanEstimateSourceCount;
      case AgentRowsEstimateSource.unavailable:
        return l10n.agentPlanEstimateUnavailable;
    }
  }

  /// 回滚来源标注（§7 两路；§9-A3 卡上标注来源）。
  String _rollbackSourceLabel(
    BuildContext context,
    AgentRollbackSource? source,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    switch (source) {
      case AgentRollbackSource.model:
        return l10n.agentPlanRollbackSourceModel;
      case AgentRollbackSource.auto:
        return l10n.agentPlanRollbackSourceAuto;
      case null:
        return '';
    }
  }

  // ── 失败边界（partialFailed 三段，§3.5）─────────────────────────────────

  Widget _buildBoundary(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final List<AgentPlanStep> steps = widget.plan.steps;
    final int done = steps
        .where(
          (AgentPlanStep s) => s.runtime.status == AgentPlanStepStatus.done,
        )
        .length;
    final int failed = steps
        .where(
          (AgentPlanStep s) => s.runtime.status == AgentPlanStepStatus.failed,
        )
        .length;
    final int skipped = steps
        .where(
          (AgentPlanStep s) => s.runtime.status == AgentPlanStepStatus.skipped,
        )
        .length;
    // 失败原因：首个 failed 步的 runtime.error（执行器写入，已脱敏）。
    final String failedError = steps
        .where(
          (AgentPlanStep s) => s.runtime.status == AgentPlanStepStatus.failed,
        )
        .map((AgentPlanStep s) => s.runtime.error)
        .whereType<String>()
        .firstWhere((String e) => e.isNotEmpty, orElse: () => '');
    final String? reasonText = failedError.isEmpty
        ? null
        : l10n.agentPlanFailureReason(failedError);

    return Container(
      key: AgentPlanCard.boundaryKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppDesignSystem.space2),
          Divider(height: 1, thickness: 1, color: colors.dividerColor),
          const SizedBox(height: AppDesignSystem.space1),
          // 区块标题（§3.1「失败边界」；字号沿结构卡分组标题语汇 11 w600）。
          Text(
            l10n.agentPlanBoundaryTitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          // 汇总行（24）：circleCheck success「已完成 n」textPrimary ·
          // circleAlert error「失败 n」error（唯一允许作正文的语义色）·
          // circleSlash textMuted「未执行 n」（计数 mono，§3.5）。
          SizedBox(
            height: AppDesignSystem.workbenchDenseRowHeight,
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, size: 12, color: colors.success),
                const SizedBox(width: AppDesignSystem.space1),
                Text(
                  l10n.agentPlanBoundaryDone(done),
                  style: _boundaryCountStyle(context, colors.textPrimary),
                ),
                const SizedBox(width: AppDesignSystem.space2_5),
                Icon(LucideIcons.circleAlert, size: 12, color: colors.error),
                const SizedBox(width: AppDesignSystem.space1),
                Text(
                  l10n.agentPlanBoundaryFailed(failed),
                  style: _boundaryCountStyle(context, colors.error),
                ),
                const SizedBox(width: AppDesignSystem.space2_5),
                Icon(
                  LucideIcons.circleSlash,
                  size: 12,
                  color: colors.textMuted,
                ),
                const SizedBox(width: AppDesignSystem.space1),
                Text(
                  l10n.agentPlanBoundaryRemaining(skipped),
                  style: _boundaryCountStyle(context, colors.textMuted),
                ),
              ],
            ),
          ),
          if (reasonText != null) ...<Widget>[
            const SizedBox(height: AppDesignSystem.space1),
            // 失败原因行（24 / maxLines 2 + tooltip，§3.5）。
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppDesignSystem.workbenchDenseRowHeight,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: reasonText,
                      child: Text(
                        key: AgentPlanCard.failureReasonKey,
                        reasonText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppDesignSystem.space1_5),
          // 回退入口（§3.5）：中性「恢复」语义（bgTertiary + borderStrong 描
          // 边 + rotateCcw），点击只发起回调、永不自动执行（AC11.3）。
          Align(
            alignment: Alignment.centerRight,
            child: _actionButton(
              context,
              buttonKey: AgentPlanCard.generateRollbackButtonKey,
              label: l10n.agentPlanGenerateRollback,
              focusNode: _generateRollbackFocus,
              icon: LucideIcons.rotateCcw,
              iconColor: colors.textSecondary,
              filled: true,
              borderColor: colors.borderStrong,
              onPressed: widget.callbacks.onGenerateRollback,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _boundaryCountStyle(BuildContext context, Color color) => TextStyle(
    fontSize: 11,
    fontFamily: AppDesignSystem.monoFontFamily,
    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    color: color,
  );

  // ── rollbackOffered 提示行（§3.4）───────────────────────────────────────

  Widget _buildRollbackPendingHint(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    return SizedBox(
      key: AgentPlanCard.rollbackPendingHintKey,
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Flexible(
            child: Text(
              l10n.agentPlanRollbackPendingHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ── consumed 提示行（§3.4 / AC11.4）────────────────────────────────────

  /// 终态重放提示（isConsumed 叠加或字面 consumed 防御）。点击经
  /// onTerminalReplay 通知宿主（防重观测；卡面不产任何库操作）。
  Widget _buildConsumedHint(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final VoidCallback? onTap = widget.callbacks.onTerminalReplay;
    final Widget row = Row(
      children: [
        Flexible(
          child: Text(
            l10n.agentPlanConsumedHint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ),
      ],
    );
    return SizedBox(
      key: AgentPlanCard.consumedHintKey,
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: onTap == null
          ? row
          : Tooltip(
              message: l10n.agentPlanConsumedHint,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                child: row,
              ),
            ),
    );
  }

  // ── 动作行（pendingApproval，§3.6）──────────────────────────────────────

  /// 动作区（pendingApproval，§3.6 + Fix-E）：「本会话内允许」勾选行（沿
  /// 确认卡 28px 先例，复用其 ARB key——两卡同门语义不碰 ARB）+ 右对齐动
  /// 作 Wrap（间距 space2 / 行距 space1_5），拒绝在前、批准落末位（§0.6
  /// 换行降级序；键盘序与视觉序一致，§3.7-8：勾选行 → 拒绝 → 批准）。
  Widget _buildActions(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    final void Function({required bool forSession})? onApprove =
        widget.callbacks.onApprove;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSessionAllowRow(context),
        const SizedBox(height: AppDesignSystem.space1_5),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: AppDesignSystem.space2,
            runSpacing: AppDesignSystem.space1_5,
            alignment: WrapAlignment.end,
            children: [
              _actionButton(
                context,
                buttonKey: AgentPlanCard.rejectButtonKey,
                label: l10n.agentPlanReject,
                focusNode: _rejectFocus,
                filled: false,
                onPressed: widget.callbacks.onReject,
              ),
              // 批准并执行（主动作，§3.6）：errorContainer 底 + 1px error
              // 描边 + textPrimary w600 + circleCheck 12 error（实测文字
              // 14.61/6.76 ✓）。提交携带勾选态（Fix-E）。
              _actionButton(
                context,
                buttonKey: AgentPlanCard.approveButtonKey,
                label: l10n.agentPlanApprove,
                focusNode: _approveFocus,
                filled: true,
                icon: LucideIcons.circleCheck,
                iconColor: colors.error,
                backgroundColor: colors.errorContainer,
                borderColor: colors.error,
                onPressed: onApprove == null ? null : _submitPrimary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 会话放行勾选行（Fix-E，AC9.3 授予入口）────────────────────────────

  /// 28px 勾选行（沿确认卡 `agent_confirm_card.dart` 勾选行先例逐字执行）：
  /// 勾选框 14×14 radiusSm + 标签 11px textSecondary；整行 tooltip 承载作
  /// 用域说明，hover 与键盘聚焦均可显。文案/tooltip 复用确认卡同语义 ARB
  /// key（`agentConfirmAllowSession`/`agentConfirmAllowSessionHint`），不碰
  /// ARB。
  Widget _buildSessionAllowRow(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeColors colors = context.themeColors;
    return SizedBox(
      key: AgentPlanCard.sessionCheckboxKey,
      height: 28,
      child: Tooltip(
        message: l10n.agentConfirmAllowSessionHint,
        child: InkWell(
          focusNode: _sessionCheckboxFocus,
          onTap: _toggleSession,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDesignSystem.space1_5,
            ),
            child: Row(
              children: [
                _buildSessionCheckbox(context),
                const SizedBox(width: AppDesignSystem.space1_5),
                Flexible(
                  child: Text(
                    l10n.agentConfirmAllowSession,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 勾选框（确认卡同款）：未选 = 1px borderStrong 描边 + 透明底；已选 =
  /// accentBlue 填充 + textInverted 勾（§2.2 实测图形 ≥3 ✓）。
  Widget _buildSessionCheckbox(BuildContext context) {
    final ThemeColors colors = context.themeColors;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: _sessionAllowed ? colors.accentBlue : null,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: _sessionAllowed ? colors.accentBlue : colors.borderStrong,
        ),
      ),
      child: _sessionAllowed
          ? Icon(LucideIcons.check, size: 10, color: colors.textInverted)
          : null,
    );
  }

  /// 动作钮（高 32 / radiusSm / 13px / padding h space3；`minimumSize 归零 +
  /// fixedSize(fromHeight)` ——M3 下 `fixedSize(0,32)` 会被 minimumSize(64,40)
  /// 钳制截断长标签，T26 验证写法；确认卡同位问题只登记不修）。焦点 =
  /// 1.5px accentBlue 描边替换（§0.1）。
  Widget _actionButton(
    BuildContext context, {
    required Key buttonKey,
    required String label,
    required FocusNode focusNode,
    required bool filled,
    required VoidCallback? onPressed,
    Color? backgroundColor,
    Color? borderColor,
    IconData? icon,
    Color? iconColor,
  }) {
    final ThemeColors colors = context.themeColors;
    final Color resolvedBorder = borderColor ?? colors.borderStrong;
    final TextStyle textStyle = TextStyle(
      fontSize: 13,
      fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
      color: filled ? colors.textPrimary : colors.textSecondary,
    );
    final Widget child = icon == null
        ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          );
    return TextButton(
      key: buttonKey,
      focusNode: focusNode,
      onPressed: onPressed,
      style:
          TextButton.styleFrom(
            backgroundColor: filled
                ? (backgroundColor ?? colors.bgTertiary)
                : null,
            foregroundColor: filled ? colors.textPrimary : colors.textSecondary,
            overlayColor: filled ? null : colors.bgTertiary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            // 高 32 / 宽随内容（M3 最小尺寸钳制规避，见方法注释）。
            minimumSize: const Size(0, 32),
            fixedSize: const Size.fromHeight(32),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: textStyle,
          ).copyWith(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: colors.accentBlue, width: 1.5);
              }
              return filled
                  ? BorderSide(color: resolvedBorder)
                  : BorderSide.none;
            }),
          ),
      child: child,
    );
  }
}

/// executing 旋转 spinner（10×10，stroke 1.5）——轨迹卡 `_SpinnerIcon` 同款
/// 视觉语法（私有类不可跨文件复用，按同规格复制）。
class _PlanSpinnerIcon extends StatefulWidget {
  const _PlanSpinnerIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_PlanSpinnerIcon> createState() => _PlanSpinnerIconState();
}

class _PlanSpinnerIconState extends State<_PlanSpinnerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) => Transform.rotate(
        angle: _controller.value * 2 * 3.141592653589793,
        child: CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _PlanArcPainter(color: widget.color),
        ),
      ),
    );
  }
}

/// 3/4 圆弧（stroke 1.5，round cap）。
class _PlanArcPainter extends CustomPainter {
  _PlanArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Offset.zero & size,
      -1.5707963267948966,
      4.71238898038469,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlanArcPainter oldDelegate) => oldDelegate.color != color;
}
