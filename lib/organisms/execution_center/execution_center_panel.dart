import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../molecules/actionable_error.dart';
import '../../providers/app_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/execution_center_provider.dart';
import '../../providers/task_provider.dart';
import '../../theme/app_colors.dart';
import '../task_panel/task_panel.dart';

/// 常驻底部执行中心面板——Tasks | Errors 两 tab。
///
/// 通过 `ChangeNotifierProvider.value`（在 `HomeScreen` 注入 executionCenter）
/// 直接 watch [ExecutionCenterProvider]；任务来自 [TaskProvider]。
/// AI 分析在点击时经由 [AppProvider.analyzeErrorWithAi] 发送（不在 build 期耦合）。
class ExecutionCenterPanel extends StatelessWidget {
  const ExecutionCenterPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ec = context.watch<ExecutionCenterProvider>();
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        // plan §3.4：面板现处右侧 docked，分隔线在左（与 workspace 分隔）
        border: Border(
          left: BorderSide(color: context.themeColors.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(ec: ec, l10n: l10n),
          const Divider(height: 1),
          Expanded(
            child: ec.activeTab == ExecutionCenterTab.tasks
                ? const _TasksView()
                : _ErrorsView(ec: ec, l10n: l10n),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ec, required this.l10n});
  final ExecutionCenterProvider ec;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              l10n.centerTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          _TabChip(
            label: l10n.centerTabTasks,
            selected: ec.activeTab == ExecutionCenterTab.tasks,
            onTap: () => ec.setActiveTab(ExecutionCenterTab.tasks),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          _TabChip(
            label: l10n.centerTabErrors,
            selected: ec.activeTab == ExecutionCenterTab.errors,
            badge: ec.errors.length,
            onTap: () => ec.setActiveTab(ExecutionCenterTab.errors),
          ),
          const Spacer(),
          if (ec.activeTab == ExecutionCenterTab.errors && ec.errors.isNotEmpty)
            TextButton.icon(
              onPressed: ec.clearErrors,
              icon: const Icon(LucideIcons.brushCleaning, size: 14),
              label: Text(l10n.centerClearErrors),
            ),
          // plan §3.4：钉住/浮动切换（钉住=docked 收缩 workspace；浮动=overlay）
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              ec.isPinned ? LucideIcons.pin : LucideIcons.pin,
              size: 16,
            ),
            tooltip: ec.isPinned ? 'Unpin (float)' : 'Pin (dock)',
            color: ec.isPinned ? context.themeColors.accentBlue : null,
            onPressed: ec.togglePin,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.x, size: 16),
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            onPressed: ec.close,
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.themeColors.accentBlue
        : context.themeColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: selected
              ? context.themeColors.accentBlue.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: AppDesignSystem.space1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: context.themeColors.error.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
                ),
                child: Text(
                  '$badge',
                  style: AppTextStyles.caption.copyWith(
                    color: context.themeColors.error,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TasksView extends StatelessWidget {
  const _TasksView();

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, tp, _) => TaskPanel(
        tasks: tp.tasks,
        onCancelTask: (id) => tp.cancelTask(id),
        onRetryTask: (id) => tp.retryTask(id),
        onRemoveTask: (id) => tp.removeTask(id),
        onClearCompleted: () => tp.clearCompletedTasks(),
      ),
    );
  }
}

class _ErrorsView extends StatelessWidget {
  const _ErrorsView({required this.ec, required this.l10n});
  final ExecutionCenterProvider ec;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (ec.errors.isEmpty) {
      return Center(
        child: Text(
          '—',
          style: AppTextStyles.caption.copyWith(
            color: context.themeColors.textMuted,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      itemCount: ec.errors.length,
      itemBuilder: (context, i) {
        final e = ec.errors[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ActionableError(
                  message: e.message,
                  sql: e.sql,
                  connectionId: e.connectionId,
                  databaseName: e.databaseName,
                  compact: true,
                  onAnalyze: () {
                    unawaited(
                      context.read<AppProvider>().analyzeErrorWithAi(
                        errorText: e.message,
                        sql: e.sql,
                        connectionId: e.connectionId,
                        databaseName: e.databaseName,
                        locale: LocaleProvider.codeOf(
                          Localizations.localeOf(context),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.x, size: 14),
                tooltip: l10n.centerDismissError,
                onPressed: () => ec.dismissError(e.id),
              ),
            ],
          ),
        );
      },
    );
  }
}
