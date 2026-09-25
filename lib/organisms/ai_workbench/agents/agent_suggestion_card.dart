//! 跨经典建议卡（tasks-ai-agent.md T26 / ui 规格 design-ai-agent-ui.md §4
//! 全节 + §0 通则为唯一视觉依据，数值逐字执行）。
//!
//! 建议级 ≠ 已执行（R6 / AC6.1-6.4）：卡面是**一次待用户点击的建议**，
//! 渲染本身零副作用（AC6.3——不导航、不开 tab、不落审计）；动作动词恒为
//! 「应用」（非「执行」）。**区隔四件套（§4.1，缺一不可）**：
//! ① 3px accentBlue 左色条（非 success/error = 无既成事实、无风险）；
//! ② 图标 lightbulb（非数据库/结果类图标）；
//! ③ header 恒显「未执行」chip（底 bgTertiary + 11px textPrimary，tooltip =
//!    「应用前不会产生任何副作用」）；
//! ④ 主动作 = 「应用」（accentSubtle 淡底 + 1px accentBlue 描边 + arrowRight，
//!    非「执行」）。
//!
//! 三态（§4.1 状态行）：未应用（默认，动作行在）→ 已应用（chip「已应用」+
//! circleCheck success；动作行消失）→ 已忽略（chip「已忽略」+ ban textMuted；
//! 动作行消失，正文降为 textMuted）。状态由宿主（chat view）从消息载荷
//! `applied` / `dismissed` 解析传入，本卡无内部状态翻转（会话重开不丢态）。
//!
//! 无 chevron、无内容展开（§4.1 结构：正文 maxLines 3 + tooltip 全文）。
//! 卡面语言沿 §0.1（bgSecondary 卡框 + 1px borderStrong 描边 + radiusMd +
//! header 34）；文字只用中性三档（§0.2）。键盘（§4.2-3）：Tab 进卡后
//! [忽略] → [应用]，Enter 激活；SQL 块可选择但不进 Tab 序（确认卡同款）。
//! 本文件不 import providers（回调驱动）；不碰 ARB（key 引用 T21）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// 跨经典建议卡（ui 规格 §4；与 T26 chat view 平铺分发锁定的接口）。
class AgentSuggestionCard extends StatelessWidget {
  /// 常量构造（回调只发信号；动作执行与审计由宿主接线——T26 chat view）。
  const AgentSuggestionCard({
    super.key,
    required this.action,
    this.payload = const <String, dynamic>{},
    this.applied = false,
    this.dismissed = false,
    required this.onApply,
    required this.onDismiss,
  });

  /// 建议动作名（`'open_in_classic'` | `'focus_sidebar'`，与工具目录同名）。
  final String action;

  /// 建议载荷（open_in_classic → `{sql}`；focus_sidebar → `{database?, table?}`）。
  final Map<String, dynamic> payload;

  /// 已应用（宿主回填后为 true；动作行消失，chip 翻「已应用」）。
  final bool applied;

  /// 已忽略（宿主回填后为 true；动作行消失，chip 翻「已忽略」）。
  final bool dismissed;

  /// 应用回调（宿主执行动作 + 落审计 + 回填状态；卡不等待）。
  final VoidCallback onApply;

  /// 忽略回调（宿主回填状态；零副作用——不审计不导航，AC6.3）。
  final VoidCallback onDismiss;

  /// header 行（静态，恒显）。
  static const Key headerKey = ValueKey('agent_suggestion_card_header');

  /// 状态 chip（三态同位：未执行 / 已应用 / 已忽略）。
  static const Key chipKey = ValueKey('agent_suggestion_card_chip');

  /// 正文块（SQL code 块或定位目标文本）。
  static const Key bodyKey = ValueKey('agent_suggestion_card_body');

  /// 「应用」主动作钮。
  static const Key applyButtonKey = ValueKey('agent_suggestion_card_apply');

  /// 「忽略」动作钮。
  static const Key dismissButtonKey = ValueKey('agent_suggestion_card_dismiss');

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
      // 3px accentBlue 左色条替换左边描边（§0.1/§4.1：不叠加，随左圆角裁剪
      // ——建议卡 = 中性强调档，非 success/error）。
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 3, color: colors.accentBlue),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                _AgentSuggestionBody(
                  action: action,
                  payload: payload,
                  applied: applied,
                  dismissed: dismissed,
                  onApply: onApply,
                  onDismiss: onDismiss,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 动作名本地化（open_in_classic 复用 M1 `workbenchActionOpenInClassic`，
  /// focus_sidebar 用 `agentSuggestFocusSidebar`；未知动作名原样兜底）。
  String _actionLabel(AppLocalizations l10n) {
    switch (action) {
      case 'open_in_classic':
        return l10n.workbenchActionOpenInClassic;
      case 'focus_sidebar':
        return l10n.agentSuggestFocusSidebar;
      default:
        return action;
    }
  }

  /// header 34（§4.1）：lightbulb 16 accentBlue + 标题 `建议 · {动作名}`
  /// 12 w600 textPrimary + 状态 chip（三态同位，§4.1 状态行）。无 chevron、
  /// 无折叠语义（建议卡不展开）。
  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return SizedBox(
      key: AgentSuggestionCard.headerKey,
      height: AppDesignSystem.toolCardHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
        child: Row(
          children: [
            Icon(LucideIcons.lightbulb, size: 16, color: colors.accentBlue),
            const SizedBox(width: AppDesignSystem.space2),
            Flexible(
              child: Tooltip(
                message: l10n.agentSuggestTitle(_actionLabel(l10n)),
                child: Text(
                  l10n.agentSuggestTitle(_actionLabel(l10n)),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            _buildChip(context),
          ],
        ),
      ),
    );
  }

  /// 状态 chip（§4.1 状态行）：未应用 = 「未执行」bgTertiary + 11px
  /// textPrimary（tooltip = 副作用提示）；已应用 = circleCheck success +
  /// 「已应用」；已忽略 = ban textMuted + 「已忽略」。高 18（§0.1 chip 语法）。
  Widget _buildChip(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final String label;
    final IconData? icon;
    final Color iconColor;
    String? tooltip;
    if (applied) {
      label = l10n.agentSuggestBadgeApplied;
      icon = LucideIcons.circleCheck;
      iconColor = colors.success;
    } else if (dismissed) {
      label = l10n.agentSuggestBadgeDismissed;
      icon = LucideIcons.ban;
      iconColor = colors.textMuted;
    } else {
      label = l10n.agentSuggestBadgeNotApplied;
      icon = null;
      iconColor = colors.textPrimary;
      tooltip = l10n.agentSuggestNotAppliedHint;
    }
    final chip = Container(
      key: AgentSuggestionCard.chipKey,
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
          if (icon != null) ...[
            Icon(icon, size: 10, color: iconColor),
            const SizedBox(width: AppDesignSystem.space1),
          ],
          Text(
            label,
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
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip, child: chip);
  }
}

/// 卡内容体（正文 + 动作行；私有 Stateful——SQL 块「可选择但不进 Tab 序」
/// 与动作钮焦点/Esc 键盘语义需要 FocusNode，公开签名保持 Stateless）。
class _AgentSuggestionBody extends StatefulWidget {
  const _AgentSuggestionBody({
    required this.action,
    required this.payload,
    required this.applied,
    required this.dismissed,
    required this.onApply,
    required this.onDismiss,
  });

  final String action;
  final Map<String, dynamic> payload;
  final bool applied;
  final bool dismissed;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  State<_AgentSuggestionBody> createState() => _AgentSuggestionBodyState();
}

class _AgentSuggestionBodyState extends State<_AgentSuggestionBody> {
  /// SQL 块可选择但不进 Tab 序（键盘序锁「忽略 → 应用」，§4.2-3）。
  late final FocusNode _sqlFocus;

  /// 动作钮焦点（Esc 逐级回退，§0.4）。
  late final FocusNode _dismissFocus;
  late final FocusNode _applyFocus;

  @override
  void initState() {
    super.initState();
    _sqlFocus = FocusNode(skipTraversal: true);
    _dismissFocus = FocusNode(onKeyEvent: _onEscKeyEvent);
    _applyFocus = FocusNode(onKeyEvent: _onEscKeyEvent);
  }

  @override
  void dispose() {
    _sqlFocus.dispose();
    _dismissFocus.dispose();
    _applyFocus.dispose();
    super.dispose();
  }

  /// 动作钮 Esc：焦点交还上级（§0.4 逐级回退）。
  KeyEventResult _onEscKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      node.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final bool pending = !widget.applied && !widget.dismissed;
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
        children: [
          if (widget.action == 'open_in_classic')
            _buildSqlBlock(context)
          else
            _buildTargetText(context),
          // 动作行仅未决态构建（已应用/已忽略动作行消失，§4.1 状态行）。
          if (pending) ...[
            const SizedBox(height: AppDesignSystem.space1_5),
            _buildActions(context),
          ],
        ],
      ),
    );
  }

  /// 建议正文文本（focus_sidebar = 定位目标 `database · table`；纯数据拼接，
  /// 不参与 l10n §0.6-③）。已忽略降为 textMuted（§4.1 状态行）。
  String get _targetText {
    final Object? database = widget.payload['database'];
    final Object? table = widget.payload['table'];
    final String db = database is String ? database : '';
    final String tb = table is String ? table : '';
    return <String>[if (db.isNotEmpty) db, if (tb.isNotEmpty) tb].join(' · ');
  }

  /// 正文：SQL 形态（open_in_classic）= codeBlockBg + radiusSm + padding
  /// space2 + mono 11 / 行高 1.4 / 可选中（§0.1 代码块语法 / §4.1），maxLines
  /// 3 + tooltip 全文。
  Widget _buildSqlBlock(BuildContext context) {
    final colors = context.themeColors;
    final Object? raw = widget.payload['sql'];
    final String sql = raw is String ? raw : '';
    if (sql.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: sql,
      child: Container(
        key: AgentSuggestionCard.bodyKey,
        width: double.infinity,
        padding: const EdgeInsets.all(AppDesignSystem.space2),
        decoration: BoxDecoration(
          color: colors.codeBlockBg,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: SelectableText(
          sql,
          focusNode: _sqlFocus,
          maxLines: 3,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            fontFamily: AppDesignSystem.monoFontFamily,
            fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            color: widget.dismissed
                ? colors.textMuted
                : colors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 正文：定位目标形态（focus_sidebar）= 12px textPrimary（已忽略
  /// textMuted），maxLines 3 + ellipsis + tooltip 全文（§4.1）。
  Widget _buildTargetText(BuildContext context) {
    final colors = context.themeColors;
    final String text = _targetText;
    if (text.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: text,
      child: Text(
        key: AgentSuggestionCard.bodyKey,
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: widget.dismissed ? colors.textMuted : colors.textPrimary,
        ),
      ),
    );
  }

  /// 动作行（未决态，§4.1/§4.2-3）：右对齐 Wrap（间距 space2 / 行距
  /// space1_5，§0.6），忽略在前、主动作末位——键盘序与视觉序一致。
  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: AppDesignSystem.space2,
        runSpacing: AppDesignSystem.space1_5,
        alignment: WrapAlignment.end,
        children: [
          _dismissButton(context, l10n),
          _applyButton(context, l10n),
        ],
      ),
    );
  }

  /// 「忽略」（§4.1）：高 32 / 无底 / 文字 textSecondary / hover 底 bgTertiary。
  Widget _dismissButton(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return TextButton(
      key: AgentSuggestionCard.dismissButtonKey,
      focusNode: _dismissFocus,
      onPressed: widget.onDismiss,
      style: TextButton.styleFrom(
        foregroundColor: colors.textSecondary,
        overlayColor: colors.bgTertiary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        // 高 32 / 宽随内容：M3 下 fixedSize 会被 minimumSize(64,40) 钳制成
        // 紧约束 64×40（压死内容）——标准解法 = minimumSize 归零 + 高度紧约束。
        minimumSize: const Size(0, 32),
        fixedSize: const Size.fromHeight(32),
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colors.accentBlue, width: 1.5);
          }
          return BorderSide.none;
        }),
      ),
      child: Text(l10n.agentSuggestDismiss, maxLines: 1),
    );
  }

  /// 「应用」主动作（§4.1）：高 32 / 底 accentSubtle + 1px accentBlue 描边 +
  /// 文字 textPrimary w600 + 图标 arrowRight 12 accentBlue（§0.2 实测淡底
  /// 合规解，不用实心 accent 填充）。焦点 = 1.5px accentBlue 描边替换（§0.1）。
  Widget _applyButton(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return TextButton(
      key: AgentSuggestionCard.applyButtonKey,
      focusNode: _applyFocus,
      onPressed: widget.onApply,
      style: TextButton.styleFrom(
        backgroundColor: colors.accentSubtle,
        foregroundColor: colors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        // 高 32 / 宽随内容：M3 下 fixedSize 会被 minimumSize(64,40) 钳制成
        // 紧约束 64×40（压死内容）——标准解法 = minimumSize 归零 + 高度紧约束。
        minimumSize: const Size(0, 32),
        fixedSize: const Size.fromHeight(32),
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colors.accentBlue, width: 1.5);
          }
          return BorderSide(color: colors.accentBlue);
        }),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.agentSuggestApply, maxLines: 1),
          const SizedBox(width: AppDesignSystem.space1),
          Icon(LucideIcons.arrowRight, size: 12, color: colors.accentBlue),
        ],
      ),
    );
  }
}
