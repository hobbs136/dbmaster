import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/task_models.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'task_detail_dialog.dart';
import 'task_list_item.dart';

/// 任务面板
/// 显示所有后台任务的列表和状态
class TaskPanel extends StatelessWidget {
  final List<DbTask> tasks;
  final Function(String) onCancelTask;
  final Function(String) onRetryTask;
  final Function(String) onRemoveTask;
  final VoidCallback onClearCompleted;

  const TaskPanel({
    super.key,
    required this.tasks,
    required this.onCancelTask,
    required this.onRetryTask,
    required this.onRemoveTask,
    required this.onClearCompleted,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        // 标题栏
        _buildHeader(context),
        // 任务列表
        Expanded(
          child: ListView.builder(
            itemCount: tasks.length,
            padding: const EdgeInsets.symmetric(
              vertical: AppDesignSystem.space2,
            ),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return TaskListItem(
                task: task,
                onTap: () => _showTaskDetail(context, task),
                onCancel: () => onCancelTask(task.id),
                onRetry: () => onRetryTask(task.id),
                onRemove: () => onRemoveTask(task.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final themeColors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final completedCount = tasks
        .where((t) => t.status == TaskStatus.completed)
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: themeColors.bgSecondary,
        border: Border(bottom: BorderSide(color: themeColors.borderLight)),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.clipboardList,
            size: 18,
            color: themeColors.textSecondary,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.taskPanelTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: themeColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space1_5,
              vertical: AppDesignSystem.space0_5,
            ),
            decoration: BoxDecoration(
              color: themeColors.accentPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            ),
            child: Text(
              '${tasks.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: themeColors.accentPurple,
              ),
            ),
          ),
          const Spacer(),
          if (completedCount > 0)
            TextButton.icon(
              onPressed: onClearCompleted,
              icon: Icon(
                LucideIcons.eraser,
                size: 14,
                color: themeColors.textMuted,
              ),
              label: Text(
                l10n.taskPanelClearCompleted,
                style: TextStyle(fontSize: 12, color: themeColors.textMuted),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space1,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final themeColors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.inbox,
            size: 48,
            color: themeColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.taskPanelEmpty,
            style: TextStyle(fontSize: 14, color: themeColors.textMuted),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.taskPanelEmptyDesc,
            style: TextStyle(
              fontSize: 12,
              color: themeColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _showTaskDetail(BuildContext context, DbTask task) {
    showDialog(
      context: context,
      builder: (context) => TaskDetailDialog(
        task: task,
        onCancel: () => onCancelTask(task.id),
        onRetry: () => onRetryTask(task.id),
        onRemove: () => onRemoveTask(task.id),
      ),
    );
  }
}
