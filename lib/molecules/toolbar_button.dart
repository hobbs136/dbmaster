// ============================================================================
// DbMaster Toolbar Button — unified toolbar button molecule
// ============================================================================
///
/// Replaces the deprecated `HeaderButton` (molecules/) and `ToolbarBtn`
/// (organisms/editor/). Both toolbars — AppHeader and QueryEditorToolbar —
/// now share this single component, ensuring consistent hover feedback,
/// disabled rendering, and sizing.
///
/// Two render modes:
/// - **Icon-only** (label == null): compact 18px icon, 8px padding — for
///   high-frequency muscle-memory actions (Execute, Stop, Save, Format, TX)
/// - **Icon + label** (label != null): 18px icon + 6px gap + 11px text — for
///   lower-frequency or discoverability-sensitive actions (Smart Import,
///   PII Masking, Query Plan, and all AppHeader buttons)
///
/// Hover model (converged, P0-1/P0-3):
/// - Background: InkWell hoverColor = bgTertiary (DataGrip / VS Code convention)
/// - Icon color: textSecondary → semantic [color] on hover (if provided)
/// - Disabled: textMuted, no hover reaction
///
/// Loading state: replaces icon with a 16×16 CircularProgressIndicator.
///
/// Variants (C21, 原型 editor-workspace 工具栏按钮语汇):
/// - [ToolbarButtonVariant.ghost]: 透明底 + hover bgTertiary（默认，存量行为）
/// - [ToolbarButtonVariant.filled]: 主色底 + 反色前景——主操作（运行）
/// - [ToolbarButtonVariant.outline]: bgTertiary 底 + borderLight 描边——次操作
/// - [ToolbarButtonVariant.danger]: bgTertiary 底 + error 描边/前景——破坏性次操作
library;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum ToolbarButtonVariant { ghost, filled, outline, danger }

class ToolbarButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final String? shortcutHint;
  final Color? color;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool disabled;
  final ToolbarButtonVariant variant;

  const ToolbarButton({
    super.key,
    required this.icon,
    this.label,
    required this.tooltip,
    this.shortcutHint,
    this.color,
    this.onPressed,
    this.isLoading = false,
    this.disabled = false,
    this.variant = ToolbarButtonVariant.ghost,
  });

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.disabled || widget.onPressed == null;
    final effectiveDisabled = isDisabled || widget.isLoading;

    // Variant-driven foreground/background (C21). ghost keeps the legacy
    // hover-semantic-colour model; filled/outline/danger are always-on
    // surface styles per the editor-workspace prototype.
    final Color foreground;
    final Color? surface;
    final Border? border;
    switch (widget.variant) {
      case ToolbarButtonVariant.filled:
        foreground = effectiveDisabled
            ? context.themeColors.textMuted
            : Theme.of(context).colorScheme.onPrimary;
        surface = effectiveDisabled
            ? context.themeColors.bgTertiary
            : context.themeColors.accentBlue;
        border = effectiveDisabled
            ? Border.all(color: context.themeColors.borderLight)
            : null;
      case ToolbarButtonVariant.outline:
        foreground = effectiveDisabled
            ? context.themeColors.textMuted
            : (widget.color ?? context.themeColors.textPrimary);
        surface = context.themeColors.bgTertiary;
        border = Border.all(
          color: effectiveDisabled
              ? context.themeColors.borderColor
              : context.themeColors.borderLight,
        );
      case ToolbarButtonVariant.danger:
        foreground = effectiveDisabled
            ? context.themeColors.textMuted
            : context.themeColors.error;
        surface = context.themeColors.bgTertiary;
        border = Border.all(
          color: effectiveDisabled
              ? context.themeColors.borderColor
              : context.themeColors.error,
        );
      case ToolbarButtonVariant.ghost:
        foreground = effectiveDisabled
            ? context.themeColors.textMuted
            : (_isHovered && widget.color != null)
                ? widget.color!
                : context.themeColors.textSecondary;
        surface = null;
        border = null;
    }

    final iconWidget = widget.isLoading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
            ),
          )
        : Icon(widget.icon, size: AppDesignSystem.iconSizeDefault, color: foreground);

    final child = widget.label != null
        ? Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space1_5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                const SizedBox(width: AppDesignSystem.space1_5),
                Text(
                  widget.label!,
                  style: TextStyle(
                    fontSize: widget.variant == ToolbarButtonVariant.filled
                        ? AppDesignSystem.fontSizeMd
                        : AppDesignSystem.fontSizeSm,
                    fontWeight: widget.variant == ToolbarButtonVariant.filled
                        ? FontWeight.w500
                        : FontWeight.normal,
                    color: foreground,
                  ),
                ),
              ],
            ),
          )
        : Container(
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(border: border),
            child: iconWidget,
          );

    final tooltipText = widget.shortcutHint != null
        ? '${widget.tooltip} (${widget.shortcutHint})'
        : widget.tooltip;

    return Tooltip(
      message: tooltipText,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: effectiveDisabled ? null : widget.onPressed,
          onHover: (hovered) => setState(() => _isHovered = hovered),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          hoverColor: effectiveDisabled || surface != null
              ? Colors.transparent
              : context.themeColors.bgTertiary,
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              border: widget.label != null ? border : null,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
