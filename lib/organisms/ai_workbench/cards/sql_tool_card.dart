//! SQL 工具卡（T12 阶段二，design-ai-workbench §8【三】卡片视觉语法 + §4.4）。
//!
//! 结构：卡框（bgSecondary 底 + 1px borderStrong 描边 + 3px 左状态色条替换
//! 左描边 + 左圆角 radiusMd）内含 header 34 恒显（图标 16 + 标题 12 w600 +
//! 类型徽标 + 写操作「危险」徽标 + Spacer + 动作区 + chevron）与展开态
//! SQL 正文块。懒构建写死（`if (_expanded)`，NF1.3 性能不变式，禁止改预构建）。
//!
//! 动作区（复制/执行/在经典中打开）中：复制为内置实现（AC4.3）；
//! 执行与在经典中打开为构造参数注入的接口预留（T13 接线
//! `WorkbenchExecutionActions` / `WorkbenchOpenInClassic`），本组件只渲染
//! 不禁用、不写死禁用态以外的假实现。
//!
//! 键盘（§8【三】）：焦点序 header → 动作钮（左→右）→ content 滚动区；
//! Space/Enter 折叠；Esc 回 header；header 聚焦时卡描边 1.5px accentBlue
//! 替换 1px borderStrong（无发光无位移）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// 工作台 SQL 工具卡：AI 产出的 SQL 语句载体（R4）。
class SqlToolCard extends StatefulWidget {
  const SqlToolCard({
    super.key,
    required this.sql,
    required this.statementType,
    required this.isWrite,
    this.onExecute,
    this.onOpenInClassic,
  });

  /// 卡内 SQL 全文（复制 / 执行 / 互跳出口的数据源）。
  final String sql;

  /// 语句类型（SELECT/INSERT/...，header 类型徽标）。
  final String statementType;

  /// 写操作判定（header「危险」徽标；判定来源 = payload.isWrite 或
  /// `AiToolClassifier.isWriteSql`，语义一致，T06）。
  final bool isWrite;

  /// 「执行」动作（T13 注入；参数为卡内 SQL 全文）。
  final void Function(String sql)? onExecute;

  /// 「在经典中打开」动作（T13 注入）。
  final void Function(String sql)? onOpenInClassic;

  /// header 整行（折叠热区 + 焦点宿主）。
  static const Key headerKey = ValueKey('workbench_sql_card_header');

  /// 展开态 SQL 正文滚动区（懒构建守护断言目标，NF1.3）。
  static const Key contentKey = ValueKey('workbench_sql_card_content');

  /// 写操作「危险」徽标（AC4 写徽标判定断言目标）。
  static const Key writeBadgeKey = ValueKey('workbench_sql_card_write_badge');

  /// 语句类型徽标。
  static const Key typeBadgeKey = ValueKey('workbench_sql_card_type_badge');

  /// 标题文本（header 行内的稳定热区/定位点）。
  static const Key titleTapKey = ValueKey('workbench_sql_card_title');

  static const Key copyButtonKey = ValueKey('workbench_sql_card_copy');
  static const Key executeButtonKey = ValueKey('workbench_sql_card_execute');
  static const Key openInClassicButtonKey = ValueKey(
    'workbench_sql_card_open_in_classic',
  );

  @override
  State<SqlToolCard> createState() => _SqlToolCardState();
}

class _SqlToolCardState extends State<SqlToolCard> {
  bool _expanded = false;
  bool _copied = false;
  late final FocusNode _headerFocus;
  late final FocusNode _contentFocus;

  @override
  void initState() {
    super.initState();
    _headerFocus = FocusNode(onKeyEvent: _onHeaderKeyEvent);
    _contentFocus = FocusNode(onKeyEvent: _onContentKeyEvent);
    _headerFocus.addListener(_onFocusChanged);
    _contentFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _headerFocus.removeListener(_onFocusChanged);
    _contentFocus.removeListener(_onFocusChanged);
    _headerFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  // 焦点态驱动卡描边切换（1px borderStrong ↔ 1.5px accentBlue），需重建。
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  /// header 焦点键处理：
  /// - Space/Enter（header 自身持焦点）→ 折叠/展开（与整行点击同效）；
  /// - Esc（header 后代——动作钮——持焦点时冒泡至此）→ 焦点退回 header。
  KeyEventResult _onHeaderKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isActivate =
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (isActivate && node.hasPrimaryFocus) {
      _toggle();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && !node.hasPrimaryFocus) {
      _headerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// content 滚动区 Esc → 焦点退回 header（§8【三】）。
  KeyEventResult _onContentKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _headerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copySql() async {
    await Clipboard.setData(ClipboardData(text: widget.sql));
    if (!mounted) return;
    setState(() => _copied = true);
    // 反馈 2s 后复位（经典 _CopyFeedbackButton 同款语义；mounted 守卫，
    // Future.delayed 回调无待释放资源）。
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    // §8【一】③：3px 左色条承载状态——写待确认 = error，其余（只读 SQL）
    // = accentBlue 中性强调。
    final statusColor = widget.isWrite ? colors.error : colors.accentBlue;
    final headerFocused = _headerFocus.hasFocus;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        // 焦点 1.5px accentBlue 替换 1px borderStrong（无发光无位移）。
        border: Border.all(
          color: headerFocused ? colors.accentBlue : colors.borderStrong,
          width: headerFocused ? 1.5 : 1.0,
        ),
      ),
      // 左色条覆于描边内侧边缘（child 绘制在 decoration 之上），配合圆角
      // 裁剪实现「3px 左色条替换左边描边不叠加，左圆角 radiusMd」。
      // 用 Stack+Positioned 而非 Row+stretch：卡常处无界高度宿主（消息列
      // Column），stretch 会强制 h=Infinity 断言失败。
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 3, color: statusColor),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context, statusColor),
                // 懒构建（NF1.3 性能不变式）：折叠态不构建正文。
                if (_expanded) _buildContent(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color statusColor) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return SizedBox(
      key: SqlToolCard.headerKey,
      height: AppDesignSystem.toolCardHeaderHeight,
      child: InkWell(
        focusNode: _headerFocus,
        // 点击即聚焦（InkWell 不自动 requestFocus）：整行可点折叠 + 后续
        // Space/Enter 键盘操作可达（§8【三】）。
        onTap: () {
          _headerFocus.requestFocus();
          _toggle();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
          child: Row(
            children: [
              Icon(LucideIcons.database, size: 16, color: statusColor),
              const SizedBox(width: AppDesignSystem.space2),
              Flexible(
                child: Text(
                  l10n.workbenchSqlCardTitle,
                  key: SqlToolCard.titleTapKey,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Flexible(child: _buildTypeBadge(context)),
              if (widget.isWrite) ...[
                const SizedBox(width: AppDesignSystem.space1_5),
                _buildWriteBadge(context),
              ],
              const Spacer(),
              _buildActions(context),
              const SizedBox(width: AppDesignSystem.space1),
              Icon(
                _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 语句类型徽标（折叠态元信息，§8【三】）。
  Widget _buildTypeBadge(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Container(
      key: SqlToolCard.typeBadgeKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        l10n.workbenchSqlTypeBadge(widget.statementType),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  /// 写操作「危险」徽标：error 图标 + error 文字 + errorContainer 底（§8【三】）。
  Widget _buildWriteBadge(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Container(
      key: SqlToolCard.writeBadgeKey,
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
              color: colors.error,
            ),
          ),
        ],
      ),
    );
  }

  /// 动作区（只在 header 出现一次，§8【三】）：复制 / 执行 / 在经典中打开。
  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CardActionButton(
          buttonKey: SqlToolCard.copyButtonKey,
          icon: _copied ? LucideIcons.check : LucideIcons.copy,
          label: _copied ? l10n.messageCopied : l10n.aiPanelCopy,
          color: _copied ? colors.success : colors.textMuted,
          onTap: _copySql,
        ),
        const SizedBox(width: AppDesignSystem.space1_5),
        _CardActionButton(
          buttonKey: SqlToolCard.executeButtonKey,
          icon: LucideIcons.play,
          label: l10n.queryExecute,
          color: colors.success,
          // 接口预留（T13 接线）：回调未注入时按钮照常渲染不禁用。
          onTap: () => widget.onExecute?.call(widget.sql),
        ),
        const SizedBox(width: AppDesignSystem.space1_5),
        _CardActionButton(
          buttonKey: SqlToolCard.openInClassicButtonKey,
          icon: LucideIcons.externalLink,
          label: l10n.workbenchActionOpenInClassic,
          color: colors.accentBlue,
          onTap: () => widget.onOpenInClassic?.call(widget.sql),
        ),
      ],
    );
  }

  /// 展开态 SQL 正文块：codeBlockBg / mono 11 / 行高 1.4 / SelectableText /
  /// 上限 360 内部滚动不截断（§8【三】）。
  Widget _buildContent(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2,
        0,
        AppDesignSystem.space2,
        AppDesignSystem.space2,
      ),
      child: Focus(
        focusNode: _contentFocus,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: AppDesignSystem.toolCardContentMaxHeight,
          ),
          child: SingleChildScrollView(
            key: SqlToolCard.contentKey,
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              decoration: BoxDecoration(
                color: colors.codeBlockBg,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: SelectableText(
                widget.sql,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// header 动作钮（icon 12 + 11px 文案的紧凑按钮；焦点进入 header 焦点链，
/// 满足「焦点序 header→动作钮（左→右）→content」）。
class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: buttonKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space1,
          vertical: AppDesignSystem.space0_5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: AppDesignSystem.space1),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
