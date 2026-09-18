import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AiWelcomeState extends StatelessWidget {
  final VoidCallback? onOptimizeSql;
  final VoidCallback? onSecurityAnalysis;
  final VoidCallback? onExecutionPlan;
  final VoidCallback? onIndexSuggestions;
  final VoidCallback? onQueryHistory;
  final Function(String question)? onQuestionTap;
  final String? connectionName;
  final String? databaseName;

  const AiWelcomeState({
    super.key,
    this.onOptimizeSql,
    this.onSecurityAnalysis,
    this.onExecutionPlan,
    this.onIndexSuggestions,
    this.onQueryHistory,
    this.onQuestionTap,
    this.connectionName,
    this.databaseName,
  });

  List<Map<String, dynamic>> _exampleQuestions(AppLocalizations l10n) {
    return [
      {
        'icon': LucideIcons.zap,
        'text': l10n.aiExampleQuestion1,
        'action': 'optimize',
      },
      {
        'icon': LucideIcons.table2,
        'text': l10n.aiExampleQuestion2,
        'action': 'analyze',
      },
      {
        'icon': LucideIcons.shield,
        'text': l10n.aiExampleQuestion3,
        'action': 'security',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasConnection = connectionName != null && connectionName!.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space6,
          vertical: AppDesignSystem.space8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHeader(context),
              const SizedBox(height: AppDesignSystem.space3),
              _buildDescription(context, l10n),
              if (hasConnection) ...[
                const SizedBox(height: AppDesignSystem.space4),
                _buildConnectionBadge(context),
              ],
              const SizedBox(height: AppDesignSystem.space8),
              _buildSectionTitle(context, l10n.aiExampleSectionTitle),
              const SizedBox(height: AppDesignSystem.space3),
              _buildExampleQuestions(context, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.themeColors.accentPurple.withValues(alpha: 0.2),
                context.themeColors.accentPurple.withValues(alpha: 0.05),
              ],
            ),
            // AI 欢迎页面 Logo 容器，使用设计系统标准圆角
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: Icon(
            LucideIcons.bot,
            size: 36,
            color: context.themeColors.accentPurple,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space4),
        Text(
          l10n.aiWelcomeTitle,
          style: AppTextStyles.h1.copyWith(
            color: context.themeColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(BuildContext context, AppLocalizations l10n) {
    return Text(
      l10n.aiWelcomeDescription,
      textAlign: TextAlign.center,
      style: AppTextStyles.body.copyWith(
        color: context.themeColors.textMuted,
        height: 1.6,
      ),
    );
  }

  Widget _buildConnectionBadge(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space2_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.accentGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.accentGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleCheckBig,
            size: 16,
            color: context.themeColors.accentGreen,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.aiConnectedTo(connectionName!),
            style: AppTextStyles.label.copyWith(
              color: context.themeColors.accentGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (databaseName != null && databaseName!.isNotEmpty) ...[
            Text(
              ' / ',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.themeColors.textMuted,
              ),
            ),
            Text(
              databaseName!,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.themeColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        Expanded(
          child: Container(height: 1, color: context.themeColors.borderLight),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          child: Text(
            title,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: context.themeColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: Container(height: 1, color: context.themeColors.borderLight),
        ),
      ],
    );
  }

  Widget _buildExampleQuestions(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: _exampleQuestions(l10n).map((question) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildQuestionCard(
            context,
            icon: question['icon'] as IconData,
            text: question['text'] as String,
            onTap: () => onQuestionTap?.call(question['text'] as String),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context, {
    required IconData icon,
    required String text,
    VoidCallback? onTap,
  }) {
    final isOverlay = context.watch<AppProvider>().isAiPanelOverlay;
    return Material(
      color: isOverlay ? Colors.transparent : context.themeColors.bgTertiary,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space4,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: isOverlay
                  ? context.themeColors.borderSubtle
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.themeColors.accentPurple.withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: context.themeColors.accentPurple,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space3),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.body.copyWith(
                    color: context.themeColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 12,
                color: context.themeColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
