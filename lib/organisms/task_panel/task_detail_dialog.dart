import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/task_models.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// 任务详情对话框
class TaskDetailDialog extends StatelessWidget {
  final DbTask task;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const TaskDetailDialog({
    super.key,
    required this.task,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = context.themeColors;

    return Dialog(
      backgroundColor: themeColors.bgSecondary,
      child: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            // 标题栏
            _buildHeader(context),
            // 内容区域
            Expanded(
              child: Row(
                children: [
                  // 左侧：任务信息
                  Expanded(flex: 2, child: _buildInfoPanel(context)),
                  // 分隔线
                  VerticalDivider(width: 1, color: themeColors.borderLight),
                  // 右侧：日志
                  Expanded(flex: 3, child: _buildLogPanel(context)),
                ],
              ),
            ),
            // 底部按钮
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final themeColors = context.themeColors;

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
          Icon(task.typeIcon, size: 20, color: task.statusColor),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              task.displayName,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSize2xl,
                fontWeight: FontWeight.w600,
                color: themeColors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: task.statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              task.statusLabel,
              style: TextStyle(
                fontSize: 12,
                color: task.statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: themeColors.textMuted),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(BuildContext context) {
    final themeColors = context.themeColors;

    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSection(context, l10n.taskDetailBasicInfo, themeColors, [
            _buildInfoRow(l10n.taskTypeImport, task.typeLabel, themeColors),
            _buildInfoRow(
              l10n.taskPanelStatusRunning,
              task.statusLabel,
              themeColors,
            ),
            _buildInfoRow(
              'Created',
              _formatDateTime(task.createdAt),
              themeColors,
            ),
            if (task.startedAt != null)
              _buildInfoRow(
                'Started',
                _formatDateTime(task.startedAt!),
                themeColors,
              ),
            if (task.completedAt != null)
              _buildInfoRow(
                'Completed',
                _formatDateTime(task.completedAt!),
                themeColors,
              ),
            if (task.duration != null)
              _buildInfoRow(
                'Duration',
                _formatDuration(task.duration!),
                themeColors,
              ),
          ]),
          const SizedBox(height: AppDesignSystem.space4),
          _buildInfoSection(context, l10n.taskDetailStatistics, themeColors, [
            if (task.totalRows != null)
              _buildInfoRow('Total Rows', '${task.totalRows}', themeColors),
            if (task.processedRows != null)
              _buildInfoRow('Processed', '${task.processedRows}', themeColors),
            if (task.affectedRows != null)
              _buildInfoRow('Affected', '${task.affectedRows}', themeColors),
            _buildInfoRow('Progress', '${task.progress}%', themeColors),
          ]),
          if (task.errorMessage != null) ...[
            const SizedBox(height: AppDesignSystem.space4),
            _buildInfoSection(context, l10n.taskDetailError, themeColors, [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Text(
                  task.errorMessage!,
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ),
            ]),
          ],
          if (task.outputPath != null) ...[
            const SizedBox(height: AppDesignSystem.space4),
            _buildInfoSection(context, l10n.taskDetailOutputFile, themeColors, [
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: task.outputPath!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.taskDetailCopied)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeColors.bgTertiary,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    border: Border.all(color: themeColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.outputPath!,
                          style: TextStyle(
                            fontSize: 11,
                            color: themeColors.textSecondary,
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        LucideIcons.copy,
                        size: 14,
                        color: themeColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildLogPanel(BuildContext context) {
    final themeColors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            color: themeColors.bgTertiary,
            border: Border(bottom: BorderSide(color: themeColors.borderLight)),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.fileText,
                size: 14,
                color: themeColors.textMuted,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                l10n.taskDetailLogs,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: themeColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${task.logs.length}',
                style: TextStyle(fontSize: 11, color: themeColors.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: task.logs.isEmpty
              ? Center(
                  child: Text(
                    l10n.taskPanelEmpty,
                    style: TextStyle(
                      fontSize: 12,
                      color: themeColors.textMuted,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: task.logs.length,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDesignSystem.space1,
                  ),
                  itemBuilder: (context, index) {
                    final log = task.logs[index];
                    return _buildLogItem(context, log);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogItem(BuildContext context, TaskLog log) {
    final themeColors = context.themeColors;

    Color logColor;
    IconData logIcon;

    switch (log.level) {
      case LogLevel.info:
        logColor = themeColors.textSecondary;
        logIcon = LucideIcons.info;
        break;
      case LogLevel.warning:
        logColor = Colors.orange;
        logIcon = LucideIcons.triangleAlert;
        break;
      case LogLevel.error:
        logColor = Colors.red;
        logIcon = LucideIcons.circleAlert;
        break;
      case LogLevel.success:
        logColor = Colors.green;
        logIcon = LucideIcons.circleCheckBig;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1_5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(logIcon, size: 12, color: logColor),
          const SizedBox(width: AppDesignSystem.space1_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.message,
                  style: TextStyle(fontSize: 11, color: logColor, height: 1.4),
                ),
                const SizedBox(height: 1),
                Text(
                  _formatDateTime(log.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: themeColors.textMuted.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final themeColors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: themeColors.bgSecondary,
        border: Border(top: BorderSide(color: themeColors.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (task.status == TaskStatus.running)
            TextButton.icon(
              onPressed: () {
                onCancel();
                Navigator.of(context).pop();
              },
              icon: Icon(LucideIcons.square, size: 16, color: Colors.red),
              label: Text(
                l10n.taskActionCancel,
                style: TextStyle(color: Colors.red),
              ),
            ),
          if (task.status == TaskStatus.failed ||
              task.status == TaskStatus.cancelled) ...[
            TextButton.icon(
              onPressed: () {
                onRetry();
                Navigator.of(context).pop();
              },
              icon: Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: themeColors.accentPurple,
              ),
              label: Text(
                l10n.taskActionRetry,
                style: TextStyle(color: themeColors.accentPurple),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
          ],
          if (task.isDone)
            TextButton.icon(
              onPressed: () {
                onRemove();
                Navigator.of(context).pop();
              },
              icon: Icon(
                LucideIcons.trash2,
                size: 16,
                color: themeColors.textMuted,
              ),
              label: Text(
                l10n.taskActionRemove,
                style: TextStyle(color: themeColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
    BuildContext context,
    String title,
    ThemeColors themeColors,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeColors themeColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space0_5),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: themeColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: themeColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    } else {
      return '${d.inSeconds}s';
    }
  }
}

// 用于获取 themeColors 的辅助变量
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
