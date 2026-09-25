//! L0.5 读确认卡（tasks-ai-agent.md T12；ui 规格 design-ai-agent-ui.md §2
//! 全节为唯一视觉依据，数值/色对逐字执行）。
//!
//! 阻塞式决策卡（面二）：`outcome == null`（未决）渲染完整内容（影响字段行 /
//! SQL 块 / 会话放行勾选行 / 三动作），不可折叠、无折叠开关（§2.5-1）；
//! `outcome != null` 收为 header + 24px 结论行（§2.4 五态）。
//!
//! 「已随运行取消」与用户「已取消」同为 `GateCardResult.rejected`（runner 在
//! 停止时以 rejected 解决在途 Completer，design §6.4）：卡以内部交互记忆区分
//! ——用户点过 [AgentConfirmCard.onDecision] 的 rejected → 「已取消」；未点
//! 而 outcome 被宿主置为 rejected（停止翻转）→ 「已随运行取消」。记忆落在
//! 私有 Stateful 内容体 [_AgentConfirmBody] 上，跨 outcome 翻转存活（同位置
//! 同类型，Element/State 复用）；对外签名与 T13 锁定的接口草案一致。
//!
//! 卡面语言沿 §0.1 / M1（bgSecondary 卡框 + 1px borderStrong 描边 + 3px
//! warning 左色条 + header 34）：本卡无折叠语义，header 为静态行，无
//! chevron（§2.5-1）。危险感知 = warning 档（§2.1）：左色条/卡头图标/扫描
//! 形态标记用 warning；文字只用中性三档（+ 无 error——高代价读取不是错误）。
//! 键盘序（§2.5-6）：勾选行 → 取消 → 本次允许；Space 切勾选、Enter 提交、
//! Esc 把焦点交还上级（输入区重聚焦由宿主 T13/T14 接线）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/ai/agent/agent_gate_analysis.dart'
    show ReadImpactAnalysis;
import '../../../services/ai/agent/agent_ui_port.dart' show GateCardResult;
import '../../../theme/app_colors.dart';

/// 工作台 L0.5 高代价读取确认卡（ui 规格 §2；与 T13 嵌块宿主锁定的接口）。
class AgentConfirmCard extends StatelessWidget {
  /// 常量构造（接口草案锁定签名，T13 按此消费）。
  const AgentConfirmCard({
    super.key,
    required this.impact,
    required this.sql,
    required this.outcome,
    required this.onDecision,
  });

  /// 读前分析影响面（T05 产物，AC8.4 视觉可证）。
  final ReadImpactAnalysis impact;

  /// 本次待执行 SQL（块内全文可选中 + 复制）。
  final String sql;

  /// 决策结论；null = 未决（全内容 + 动作行），非 null = 收为结论行。
  final GateCardResult? outcome;

  /// 决策回调（approved | approvedForSession | rejected）。宿主可为 async
  /// 闭包（Future 语义在 `void Function` 参数位被安全丢弃，等待由宿主的
  /// Completer 机制承担，卡不等待）。
  final void Function(GateCardResult decision) onDecision;

  /// header 行（静态，恒显）。
  static const Key headerKey = ValueKey('agent_confirm_card_header');

  /// 未决内容滚动区（卡体上限 360 统一滚动，SQL 全文不截断）。
  static const Key contentKey = ValueKey('agent_confirm_card_content');

  /// 会话放行勾选行（整行可点/可聚焦）。
  static const Key sessionCheckboxKey = ValueKey(
    'agent_confirm_card_session_checkbox',
  );

  /// 「取消」动作钮。
  static const Key cancelButtonKey = ValueKey('agent_confirm_card_cancel');

  /// 「本次允许」主动作钮。
  static const Key allowButtonKey = ValueKey('agent_confirm_card_allow');

  /// SQL 块「复制」动作。
  static const Key copyButtonKey = ValueKey('agent_confirm_card_copy');

  /// 决策后结论行（24）。
  static const Key conclusionKey = ValueKey('agent_confirm_card_conclusion');

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      // 3px warning 左色条替换左边描边（§0.1/§2.2：不叠加，随左圆角裁剪）。
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 3, color: colors.warning),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                // 私有内容体恒在树（未决内容 / 决策结论二态）：State 跨
                // outcome 翻转存活，承载「已取消 vs 已随运行取消」记忆。
                _AgentConfirmBody(
                  impact: impact,
                  sql: sql,
                  outcome: outcome,
                  onDecision: onDecision,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// header 34：triangleAlert 16 warning + 标题 12 w600 textPrimary +
  /// 状态 chip（仅未决：「等待确认」，§2.2——决策后状态由结论行表达，§2.4
  /// 未给决策后 chip 规格，不发明）。
  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return SizedBox(
      key: AgentConfirmCard.headerKey,
      height: AppDesignSystem.toolCardHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
        child: Row(
          children: [
            Icon(LucideIcons.triangleAlert, size: 16, color: colors.warning),
            const SizedBox(width: AppDesignSystem.space2),
            Flexible(
              child: Text(
                l10n.agentConfirmReadTitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (outcome == null) ...[
              const SizedBox(width: AppDesignSystem.space2),
              _buildPendingChip(context),
            ],
          ],
        ),
      ),
    );
  }

  /// 未决状态 chip（高 18：底 bgTertiary + hourglass 10 warning +
  /// 11px textPrimary w500；标签沿轨迹卡共用的 awaiting key，§2.2）。
  Widget _buildPendingChip(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Container(
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
          Icon(LucideIcons.hourglass, size: 10, color: colors.warning),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            l10n.agentTrajectoryAwaiting,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡内容体（未决交互 / 决策结论二态；私有 Stateful——勾选与 rejected 双
/// 形态记忆是本卡的局部 UI 状态，公开签名保持 Stateless 不变）。
class _AgentConfirmBody extends StatefulWidget {
  const _AgentConfirmBody({
    required this.impact,
    required this.sql,
    required this.outcome,
    required this.onDecision,
  });

  final ReadImpactAnalysis impact;
  final String sql;
  final GateCardResult? outcome;
  final void Function(GateCardResult decision) onDecision;

  @override
  State<_AgentConfirmBody> createState() => _AgentConfirmBodyState();
}

class _AgentConfirmBodyState extends State<_AgentConfirmBody> {
  /// 会话放行勾选（勾选后主动作返回 approvedForSession，§2.3）。
  bool _sessionAllowed = false;

  /// 用户是否点过「取消」（rejected 双形态记忆，见文件头）。
  bool _userRejected = false;

  /// 复制反馈态（2s 复位，M1 sql_tool_card 同款语义）。
  bool _isCopied = false;

  late final FocusNode _checkboxFocus;
  late final FocusNode _cancelFocus;
  late final FocusNode _allowFocus;

  /// SQL 块可选择但不进 Tab 序（键盘序锁「勾选行 → 取消 → 本次允许」）。
  late final FocusNode _sqlFocus;

  /// 复制钮可聚焦（点击/悬停）但不进 Tab 序（§2.5-6 键盘序不含复制；
  /// 阅读序上它位于 SQL 块内、勾选行之前，不排除会抢占 Tab#1）。
  late final FocusNode _copyFocus;

  @override
  void initState() {
    super.initState();
    _checkboxFocus = FocusNode(onKeyEvent: _onCheckboxKeyEvent);
    _cancelFocus = FocusNode(onKeyEvent: _onEscKeyEvent);
    _allowFocus = FocusNode(onKeyEvent: _onEscKeyEvent);
    _sqlFocus = FocusNode(skipTraversal: true);
    _copyFocus = FocusNode(skipTraversal: true);
  }

  @override
  void dispose() {
    _checkboxFocus.dispose();
    _cancelFocus.dispose();
    _allowFocus.dispose();
    _sqlFocus.dispose();
    _copyFocus.dispose();
    super.dispose();
  }

  /// 勾选行键：Space 切勾选、Enter 提交主动作、Esc 回上级（§2.5-6）。
  KeyEventResult _onCheckboxKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
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

  /// 动作钮 Esc：焦点交还上级（§0.4 逐级回退；输入区重聚焦由宿主接线）。
  KeyEventResult _onEscKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleSession() => setState(() => _sessionAllowed = !_sessionAllowed);

  /// 主动作提交：未勾选 → approved；勾选 → approvedForSession（§2.5-7）。
  void _submitPrimary() {
    widget.onDecision(
      _sessionAllowed
          ? GateCardResult.approvedForSession
          : GateCardResult.approved,
    );
  }

  /// 取消：登记用户取消记忆后回调 rejected（§2.4「已取消」形态依据）。
  void _reject() {
    setState(() => _userRejected = true);
    widget.onDecision(GateCardResult.rejected);
  }

  Future<void> _copySql() async {
    await Clipboard.setData(ClipboardData(text: widget.sql));
    if (!mounted) return;
    setState(() => _isCopied = true);
    // 反馈 2s 后复位（M1 sql_tool_card 同款语义；Future.delayed 回调无待
    // 释放资源，仅 mounted 守卫）。
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.outcome;
    if (outcome != null) return _buildConclusion(context, outcome);
    return _buildPending(context);
  }

  // ── 决策后：header + 结论行 24（§2.4）─────────────────────────────────

  Widget _buildConclusion(BuildContext context, GateCardResult outcome) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    // rejected 双形态：用户点过取消 → 「已取消」（ban）；否则为停止翻转 →
    // 「已随运行取消」（square + tooltip，§2.4 字面要求）。
    final IconData icon;
    final Color iconColor;
    final String text;
    final Color textColor;
    String? tooltip;
    switch (outcome) {
      case GateCardResult.approved:
        icon = LucideIcons.shieldCheck;
        iconColor = colors.accentBlue;
        text = l10n.agentConfirmResultAllowedOnce;
        textColor = colors.textSecondary;
      case GateCardResult.approvedForSession:
        icon = LucideIcons.shieldCheck;
        iconColor = colors.accentBlue;
        text = l10n.agentConfirmResultAllowedSession;
        textColor = colors.textSecondary;
        tooltip = l10n.agentConfirmAllowSessionHint;
      case GateCardResult.rejected:
        if (_userRejected) {
          icon = LucideIcons.ban;
          iconColor = colors.textMuted;
          text = l10n.agentConfirmResultCanceled;
          textColor = colors.textMuted;
        } else {
          icon = LucideIcons.square;
          iconColor = colors.textMuted;
          text = l10n.agentConfirmResultCanceledByRun;
          textColor = colors.textMuted;
          tooltip = l10n.agentConfirmResultCanceledByRun;
        }
    }

    final row = Row(
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: AppDesignSystem.space1_5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: textColor),
          ),
        ),
      ],
    );
    return SizedBox(
      key: AgentConfirmCard.conclusionKey,
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2_5,
        ),
        child: tooltip == null ? row : Tooltip(message: tooltip, child: row),
      ),
    );
  }

  // ── 未决：影响字段行 + SQL 块 + 勾选行 + 动作行（§2.2）────────────────

  Widget _buildPending(BuildContext context) {
    final impact = widget.impact;
    final indexSummary = impact.indexSummary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2_5,
        0,
        AppDesignSystem.space2_5,
        AppDesignSystem.space2_5,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: AppDesignSystem.toolCardContentMaxHeight,
        ),
        child: SingleChildScrollView(
          key: AgentConfirmCard.contentKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRowsValue(context),
              // 扫描形态行：fullScan 为 false 且分析可用时不渲染（§2.5-3）。
              if (impact.fullScan || impact.analysisUnavailable)
                _buildScanShapeRow(context),
              if (indexSummary != null) _buildIndexRow(context, indexSummary),
              if (impact.scannedTables.isNotEmpty) _buildTablesRow(context),
              _buildSqlBlock(context),
              const SizedBox(height: AppDesignSystem.space1_5),
              _buildSessionRow(context),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 字段行骨架：行高 24（标签换行自适应 36）+ 标签列 104（11px
  /// textSecondary，maxLines 2 不截断）+ 值列 Flexible（§2.2/§0.5）。
  Widget _impactRow(String label, Widget value) {
    final colors = context.themeColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppDesignSystem.workbenchDenseRowHeight,
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppDesignSystem.agentImpactLabelWidth,
            child: Text(
              label,
              maxLines: 2,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(child: value),
        ],
      ),
    );
  }

  /// 估算行数值：mono 12 textPrimary w600（等宽数字，定律 5），null →
  /// 「不可用」textMuted（§2.2/AC8.6）。
  ///
  /// 偏差登记：ui 规格 §2.2 的「尾缀行 11px textMuted」双样式无法在 T03
  /// 既有 l10n key（`agentConfirmEstimatedRows` 整串含单位）上实现——整串
  /// 单一样式渲染 + tooltip 全文（§0.6「整串 Flexible + tooltip」口径），
  /// 不碰 ARB。拆 key 走视觉规格变更通道。
  Widget _buildRowsValue(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final rows = widget.impact.estimatedRows;
    if (rows == null) {
      return _impactRow(
        l10n.agentConfirmScanRows,
        Text(
          l10n.agentConfirmValueUnavailable,
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
      );
    }
    final formatted = NumberFormat.decimalPattern().format(rows);
    final valueText = l10n.agentConfirmEstimatedRows(formatted);
    return _impactRow(
      l10n.agentConfirmScanRows,
      Tooltip(
        message: valueText,
        child: Text(
          valueText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: AppDesignSystem.monoFontFamily,
            fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 扫描形态值：warning 图标 12 + 文案（fullScan → 11px textPrimary w600；
  /// analysisUnavailable → 保守档文案 11px textSecondary，§2.2 fail-closed
  /// 同档）。
  Widget _buildScanShapeRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final value = Row(
      children: [
        Icon(LucideIcons.triangleAlert, size: 12, color: colors.warning),
        const SizedBox(width: AppDesignSystem.space1),
        Flexible(
          child: Text(
            widget.impact.analysisUnavailable
                ? l10n.agentConfirmAnalysisUnavailable
                : l10n.agentConfirmFullScanNoIndex,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.impact.analysisUnavailable
                  ? FontWeight.w400
                  : FontWeight.w600,
              color: widget.impact.analysisUnavailable
                  ? colors.textSecondary
                  : colors.textPrimary,
            ),
          ),
        ),
      ],
    );
    return _impactRow(l10n.agentConfirmScanShape, value);
  }

  /// 索引值：自由文本（design §4.2 注 / ui 规格 §9-A5），11px textSecondary，
  /// maxLines 2 + ellipsis + tooltip 全文。
  Widget _buildIndexRow(BuildContext context, String summary) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return _impactRow(
      l10n.agentConfirmIndexRow,
      Tooltip(
        message: summary,
        child: Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      ),
    );
  }

  /// 扫描表值：`join(' · ')`，mono 11 textSecondary，maxLines 2 + tooltip。
  Widget _buildTablesRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final tables = widget.impact.scannedTables.join(' · ');
    return _impactRow(
      l10n.agentConfirmTablesRow,
      Tooltip(
        message: tables,
        child: Text(
          tables,
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
    );
  }

  /// SQL 块：codeBlockBg / mono 11 / 行高 1.4 / 全文可选中 + 块右上「复制」
  /// （§2.2；全文不截断，卡体 360 上限统一滚动）。
  Widget _buildSqlBlock(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return _impactRow(
      l10n.agentConfirmSqlRow,
      Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(
              color: colors.codeBlockBg,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SelectableText(
              widget.sql,
              focusNode: _sqlFocus,
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
              key: AgentConfirmCard.copyButtonKey,
              focusNode: _copyFocus,
              onTap: _copySql,
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
                      _copiedIcon,
                      size: 12,
                      color: _copiedIconColor(context),
                    ),
                    const SizedBox(width: AppDesignSystem.space1),
                    Text(
                      _copiedLabel(context),
                      style: TextStyle(fontSize: 11, color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _copiedIcon => _isCopied ? LucideIcons.check : LucideIcons.copy;

  Color _copiedIconColor(BuildContext context) =>
      _isCopied ? context.themeColors.success : context.themeColors.textMuted;

  String _copiedLabel(BuildContext context) => _isCopied
      ? AppLocalizations.of(context)!.messageCopied
      : AppLocalizations.of(context)!.aiPanelCopy;

  /// 会话放行勾选行（高 28：勾选框 14×14 radiusSm + 标签 11px textSecondary；
  /// 整行 tooltip 承载作用域说明，hover 与键盘聚焦均可显，§2.2）。
  Widget _buildSessionRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return SizedBox(
      key: AgentConfirmCard.sessionCheckboxKey,
      height: 28,
      child: Tooltip(
        message: l10n.agentConfirmAllowSessionHint,
        child: InkWell(
          focusNode: _checkboxFocus,
          onTap: _toggleSession,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDesignSystem.space1_5,
            ),
            child: Row(
              children: [
                _buildCheckbox(context),
                const SizedBox(width: AppDesignSystem.space1_5),
                Flexible(
                  child: Text(
                    l10n.agentConfirmAllowSession,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 勾选框：未选 = 1px borderStrong 描边 + 透明底；已选 = accentBlue 填充
  /// + textInverted 勾（§2.2 实测图形 ≥3 ✓）。
  Widget _buildCheckbox(BuildContext context) {
    final colors = context.themeColors;
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

  /// 动作行：右对齐 Wrap（间距 space2 / 行距 space1_5），取消在前、主动作
  /// 末位（§2.3/§0.6），键盘序与视觉序一致。
  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: AppDesignSystem.space2,
        runSpacing: AppDesignSystem.space1_5,
        alignment: WrapAlignment.end,
        children: [
          _actionButton(
            context,
            buttonKey: AgentConfirmCard.cancelButtonKey,
            label: l10n.agentConfirmCancel,
            focusNode: _cancelFocus,
            filled: false,
            onPressed: _reject,
          ),
          _actionButton(
            context,
            buttonKey: AgentConfirmCard.allowButtonKey,
            label: l10n.agentConfirmAllowOnce,
            focusNode: _allowFocus,
            filled: true,
            onPressed: _submitPrimary,
          ),
        ],
      ),
    );
  }

  /// 动作钮（§2.3）：主动作 = 高 32 / radiusSm / 底 bgTertiary + 1px
  /// borderStrong 描边 + 文字 textPrimary w600；取消 = 无底无描边 / 文字
  /// textSecondary / hover 底 bgTertiary。焦点 = 1.5px accentBlue 描边替换
  /// （§0.1，无发光无位移）。
  Widget _actionButton(
    BuildContext context, {
    required Key buttonKey,
    required String label,
    required FocusNode focusNode,
    required bool filled,
    required VoidCallback onPressed,
  }) {
    final colors = context.themeColors;
    // styleFrom 的 side 是静态值；焦点描边需按状态解析，经 copyWith 注入。
    final baseStyle = TextButton.styleFrom(
      backgroundColor: filled ? colors.bgTertiary : null,
      foregroundColor: filled ? colors.textPrimary : colors.textSecondary,
      overlayColor: filled ? null : colors.bgTertiary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      fixedSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontSize: 13,
        fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
      ),
    );
    return TextButton(
      key: buttonKey,
      focusNode: focusNode,
      onPressed: onPressed,
      style: baseStyle.copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colors.accentBlue, width: 1.5);
          }
          return filled
              ? BorderSide(color: colors.borderStrong)
              : BorderSide.none;
        }),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
