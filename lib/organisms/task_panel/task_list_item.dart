import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/task_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/open_directory.dart';

/// 任务列表项
class TaskListItem extends StatelessWidget {
  final DbTask task;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const TaskListItem({
    super.key,
    required this.task,
    required this.onTap,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = context.themeColors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space4,
          vertical: AppDesignSystem.space3,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: themeColors.borderSubtle,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 任务类型图标
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getTypeColor(themeColors).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Icon(
                    task.typeIcon,
                    size: 16,
                    color: _getTypeColor(themeColors),
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space3),
                // 任务信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.displayName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: themeColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppDesignSystem.space0_5),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: task.statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppDesignSystem.space1),
                          Text(
                            task.statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: task.statusColor,
                            ),
                          ),
                          if (task.currentPhase != null) ...[
                            const SizedBox(width: AppDesignSystem.space2),
                            Expanded(
                              child: Text(
                                task.currentPhase!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: themeColors.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 操作按钮
                _buildActionButtons(themeColors),
              ],
            ),
            // 进度条
            if (task.status == TaskStatus.running ||
                task.status == TaskStatus.completed) ...[
              const SizedBox(height: AppDesignSystem.space2),
              _buildProgressBar(themeColors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(ThemeColors themeColors) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: LinearProgressIndicator(
              value: task.progress / 100,
              backgroundColor: themeColors.bgTertiary,
              valueColor: AlwaysStoppedAnimation<Color>(
                task.status == TaskStatus.completed
                    ? Colors.green
                    : themeColors.accentPurple,
              ),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Text(
          '${task.progress}%',
          style: TextStyle(
            fontSize: 11,
            color: themeColors.textMuted,
            fontFamily: AppDesignSystem.monoFontFamily,

            fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          ),
        ),
        if (task.processedRows != null && task.totalRows != null) ...[
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            '(${task.processedRows}/${task.totalRows})',
            style: TextStyle(
              fontSize: 11,
              color: themeColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(ThemeColors themeColors) {
    switch (task.status) {
      case TaskStatus.pending:
        return IconButton(
          icon: Icon(
            LucideIcons.circleX,
            size: 18,
            color: themeColors.textMuted,
          ),
          onPressed: onCancel,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        );
      case TaskStatus.running:
        return IconButton(
          icon: Icon(
            LucideIcons.circleStop,
            size: 18,
            color: Colors.red.shade400,
          ),
          onPressed: onCancel,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        );
      case TaskStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                LucideIcons.play,
                size: 18,
                color: themeColors.accentPurple,
              ),
              onPressed: onRetry,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 18,
                color: themeColors.textMuted,
              ),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        );
      case TaskStatus.completed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (task.outputPath != null)
              IconButton(
                icon: Icon(
                  LucideIcons.folderOpen,
                  size: 18,
                  color: themeColors.accentPurple,
                ),
                tooltip: task.outputPath,
                onPressed: () => _openFileFolder(task.outputPath!),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 18,
                color: themeColors.textMuted,
              ),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        );
      case TaskStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                LucideIcons.refreshCw,
                size: 18,
                color: themeColors.accentPurple,
              ),
              onPressed: onRetry,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 18,
                color: themeColors.textMuted,
              ),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        );
      case TaskStatus.cancelled:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                LucideIcons.refreshCw,
                size: 18,
                color: themeColors.accentPurple,
              ),
              onPressed: onRetry,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 18,
                color: themeColors.textMuted,
              ),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        );
    }
  }

  Color _getTypeColor(ThemeColors themeColors) {
    switch (task.type) {
      case TaskType.import:
        return Colors.blue;
      case TaskType.export:
        return Colors.green;
      case TaskType.query:
        return themeColors.accentPurple;
      case TaskType.dataSync:
        return Colors.teal;
    }
  }

  /// 在系统文件管理器中打开输出文件所在目录。
  Future<void> _openFileFolder(String filePath) async {
    await openDirectoryInFileManager(File(filePath).parent.path);
  }
}
