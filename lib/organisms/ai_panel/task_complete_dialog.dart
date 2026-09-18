import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

class TaskCompleteDialog extends StatefulWidget {
  final String sql;
  final bool isDangerous;
  final VoidCallback onExecute;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  const TaskCompleteDialog({
    super.key,
    required this.sql,
    required this.isDangerous,
    required this.onExecute,
    required this.onCopy,
    required this.onClose,
  });

  @override
  State<TaskCompleteDialog> createState() => TaskCompleteDialogState();
}

class TaskCompleteDialogState extends State<TaskCompleteDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.elasticOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Dialog(
              backgroundColor: context.themeColors.bgSecondary,
              surfaceTintColor: Colors.transparent,
              child: Container(
                width: 480,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAnimatedIcon(context),
                    const SizedBox(height: AppDesignSystem.space4),
                    // 标题
                    Text(
                      widget.isDangerous
                          ? l10n.aiPanelSqlGenerationCompleteWarning
                          : l10n.aiPanelSqlGenerationComplete,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSize2xl,
                        fontWeight: FontWeight.w600,
                        color: context.themeColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppDesignSystem.space1),
                    // 副标题
                    Text(
                      widget.isDangerous
                          ? l10n.dangerousOperationDesc
                          : l10n.aiPanelTaskCompleteDesc,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isDangerous
                            ? context.themeColors.warning
                            : context.themeColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDesignSystem.space4),
                    _buildSqlCodeArea(context, l10n),
                    const SizedBox(height: AppDesignSystem.space5),
                    _buildActionButtons(context, l10n),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedIcon(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.isDangerous
              ? [context.themeColors.warning, context.themeColors.error]
              : [context.themeColors.success, context.themeColors.accentBlue],
        ),
        shape: BoxShape.circle,
      ),
      child: AnimatedBuilder(
        animation: _checkAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _checkAnimation.value,
            child: Icon(
              widget.isDangerous
                  ? LucideIcons.triangleAlert
                  : LucideIcons.check,
              color: Colors.white,
              size: 36,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSqlCodeArea(BuildContext context, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: widget.isDangerous
              ? context.themeColors.error.withValues(alpha: 0.5)
              : context.themeColors.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSqlCodeHeader(context, l10n),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              child: SelectableText(
                widget.sql,
                style: TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 12,
                  color: context.themeColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSqlCodeHeader(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        color:
            (widget.isDangerous
                    ? context.themeColors.error
                    : context.themeColors.accentBlue)
                .withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDesignSystem.radiusMd),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.code,
            size: 14,
            color: widget.isDangerous
                ? context.themeColors.error
                : context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Text(
            l10n.generatedSql,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.isDangerous
                  ? context.themeColors.error
                  : context.themeColors.accentBlue,
            ),
          ),
          const Spacer(),
          if (widget.isDangerous)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                l10n.dangerous,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: widget.onClose,
            icon: const Icon(LucideIcons.x, size: 16),
            label: Text(l10n.commonClose),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.themeColors.textSecondary,
              side: BorderSide(color: context.themeColors.borderColor),
              padding: const EdgeInsets.symmetric(
                vertical: AppDesignSystem.space3,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: widget.onCopy,
            icon: const Icon(LucideIcons.copy, size: 16),
            label: Text(l10n.aiPanelCopy),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.themeColors.accentBlue,
              side: BorderSide(color: context.themeColors.accentBlue),
              padding: const EdgeInsets.symmetric(
                vertical: AppDesignSystem.space3,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          flex: widget.isDangerous ? 2 : 1,
          child: ElevatedButton.icon(
            onPressed: widget.onExecute,
            icon: Icon(
              widget.isDangerous ? LucideIcons.triangleAlert : LucideIcons.play,
              size: 16,
            ),
            label: Text(
              widget.isDangerous
                  ? l10n.aiPanelConfirmExecute
                  : l10n.aiPanelExecute,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.isDangerous
                  ? context.themeColors.error
                  : context.themeColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                vertical: AppDesignSystem.space3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
