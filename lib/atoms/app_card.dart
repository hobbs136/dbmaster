import 'package:flutter/material.dart';
import '../../theme/design_system.dart';
import '../theme/app_colors.dart';

/// ============================================================================
/// AppCard - 现代化极简卡片组件
/// ============================================================================
enum CardType { basic, elevated, hoverable, interactive }

class AppCard extends StatefulWidget {
  final Widget child;
  final CardType type;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? accentColor;
  final VoidCallback? onTap;
  final bool isSelected;
  final BorderRadius? borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.type = CardType.basic,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.accentColor,
    this.onTap,
    this.isSelected = false,
    this.borderRadius,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveBgColor =
        widget.backgroundColor ?? AppDesignSystem.bgSecondary;
    final effectiveBorderColor = widget.borderColor ?? Colors.transparent;
    final effectiveAccentColor =
        widget.accentColor ?? context.themeColors.accentBlue;
    final effectiveBorderRadius =
        widget.borderRadius ?? BorderRadius.circular(AppDesignSystem.radiusMd);

    return MouseRegion(
      onEnter: (_) {
        if (widget.type == CardType.hoverable && !_isHovered) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        if (_isHovered) {
          setState(() => _isHovered = false);
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: widget.margin ?? EdgeInsets.zero,
          decoration: _buildDecoration(
            effectiveBgColor,
            effectiveBorderColor,
            effectiveAccentColor,
            effectiveBorderRadius,
          ),
          child: Padding(
            padding: widget.padding ?? EdgeInsets.all(AppDesignSystem.space4),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration(
    Color bgColor,
    Color borderColor,
    Color accentColor,
    BorderRadius borderRadius,
  ) {
    switch (widget.type) {
      case CardType.basic:
        return BoxDecoration(color: bgColor, borderRadius: borderRadius);

      case CardType.elevated:
        return BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius,
          border: Border.all(
            color: accentColor.withOpacityValue(0.2),
            width: 1,
          ),
        );

      case CardType.hoverable:
        return BoxDecoration(
          color: _isHovered ? AppDesignSystem.bgTertiary : bgColor,
          borderRadius: borderRadius,
        );

      case CardType.interactive:
        final currentBgColor = widget.isSelected
            ? accentColor.withOpacityValue(0.1)
            : bgColor;
        final currentBorderColor = widget.isSelected
            ? accentColor.withOpacityValue(0.4)
            : borderColor;

        return BoxDecoration(
          color: currentBgColor,
          borderRadius: borderRadius,
          border: currentBorderColor == Colors.transparent && !widget.isSelected
              ? null
              : Border.all(
                  color: currentBorderColor,
                  width: widget.isSelected ? 1.5 : 1,
                ),
        );
    }
  }
}

/// ============================================================================
/// AppSectionCard - 分组卡片
/// ============================================================================
class AppSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final CardType type;
  final EdgeInsets? padding;
  final EdgeInsets? contentPadding;
  final VoidCallback? onTap;

  const AppSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.type = CardType.basic,
    this.padding,
    this.contentPadding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      type: type,
      padding: padding,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Divider(
            height: 1,
            color: AppDesignSystem.divider,
            indent: AppDesignSystem.space4,
          ),
          Padding(
            padding:
                contentPadding ??
                EdgeInsets.symmetric(vertical: AppDesignSystem.space4),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppDesignSystem.fontSize2xl,
                    fontWeight: AppDesignSystem.fontWeightSemibold,
                    color: AppDesignSystem.textPrimary,
                    height: AppDesignSystem.lineHeightTight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  SizedBox(height: AppDesignSystem.space1),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: AppDesignSystem.fontSizeSm,
                      fontWeight: AppDesignSystem.fontWeightRegular,
                      color: AppDesignSystem.textSecondary,
                      height: AppDesignSystem.lineHeightNormal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            SizedBox(width: AppDesignSystem.space3),
            action!,
          ],
        ],
      ),
    );
  }
}

/// ============================================================================
/// InfoRow - 信息行
/// ============================================================================
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final String separator;
  final bool isBold;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.separator = ': ',
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: AppDesignSystem.fontWeightRegular,
              color: AppDesignSystem.textSecondary,
              height: AppDesignSystem.lineHeightNormal,
            ),
          ),
          Text(
            separator,
            style: const TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: AppDesignSystem.fontWeightRegular,
              color: AppDesignSystem.textTertiary,
              height: AppDesignSystem.lineHeightNormal,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: isBold
                    ? AppDesignSystem.fontWeightSemibold
                    : AppDesignSystem.fontWeightRegular,
                color: AppDesignSystem.textPrimary,
                height: AppDesignSystem.lineHeightNormal,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// CardGrid - 卡片网格
/// ============================================================================
class CardGrid extends StatelessWidget {
  final List<Widget> children;
  final int? columns;
  final double? cardWidth;
  final double spacing;
  final bool shrinkWrap;
  final ScrollController? scrollController;

  const CardGrid({
    super.key,
    required this.children,
    this.columns,
    this.cardWidth,
    this.spacing = AppDesignSystem.space4,
    this.shrinkWrap = false,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColumns = columns ?? _calculateColumns(context);

    return SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: EdgeInsets.all(AppDesignSystem.space3),
        child: Column(
          children: [
            for (int i = 0; i < children.length; i += effectiveColumns)
              Row(
                children: [
                  for (
                    int j = 0;
                    j < effectiveColumns && (i + j) < children.length;
                    j++
                  )
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          right: spacing / 2,
                          bottom: spacing / 2,
                        ),
                        child: children[i + j],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  int _calculateColumns(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < AppDesignSystem.breakpointCompact) return 1;
    if (screenWidth < AppDesignSystem.breakpointMedium) return 2;
    if (screenWidth < AppDesignSystem.breakpointExpanded) return 3;
    return 4;
  }
}
