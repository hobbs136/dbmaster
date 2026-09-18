// C17 · Redis 确认类对话框 —— 自 builders/redis_tree_builder.dart 的内联方法
// _confirmDeleteKey / _showFlushDBDialog 迁出（行为逐行保持）。两件均为
// 高危操作二次确认：DEL / FLUSHDB 经 QueryTab 间接执行。
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart' show QueryTab;
import '../../../theme/app_theme.dart';
import '../../connection/error_boundary.dart';

/// 删除单个 key 确认（树 key 右键 Delete）。
class RedisDeleteKeyDialog extends StatelessWidget {
  final AppProvider provider;
  final String connectionId;
  final String dbName;
  final String redisKey;

  const RedisDeleteKeyDialog({
    super.key,
    required this.provider,
    required this.connectionId,
    required this.dbName,
    required this.redisKey,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        'Delete Key',
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Are you sure you want to delete this key?',
            style: TextStyle(color: context.themeColors.textSecondary),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            'Key: $redisKey',
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            'This action cannot be undone.',
            style: TextStyle(
              color: context.themeColors.accentRed,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () async {
            try {
              final tab = QueryTab(
                id: '${DateTime.now().millisecondsSinceEpoch}',
                title: 'DEL',
                sql: 'DEL \'$redisKey\'',
                connectionId: connectionId,
                databaseName: dbName,
                isAutoTitle: false,
              );
              await provider.addTab(tab);
              provider.loadRedisDatabaseKeyInfo(connectionId, dbName);
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) {
                AppErrorHandler.showErrorSnackBar(
                  context,
                  'Failed to delete key: $e',
                );
              }
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: context.themeColors.accentRed,
          ),
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }
}

/// FLUSHDB 确认（树 db 右键 Flush DB，红字高危项）。
class RedisFlushDbDialog extends StatelessWidget {
  final AppProvider provider;
  final String connectionId;
  final String dbName;

  const RedisFlushDbDialog({
    super.key,
    required this.provider,
    required this.connectionId,
    required this.dbName,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: Text(
        AppLocalizations.of(context)!.sidebarFlushDB,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      content: Text(
        AppLocalizations.of(context)!.sidebarFlushConfirm(dbName),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.commonCancel),
        ),
        TextButton(
          onPressed: () async {
            try {
              final tab = QueryTab(
                id: '${DateTime.now().millisecondsSinceEpoch}',
                title: 'FLUSHDB',
                sql: 'FLUSHDB',
                connectionId: connectionId,
                databaseName: dbName,
                isAutoTitle: false,
              );
              await provider.addTab(tab);
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) {
                AppErrorHandler.showErrorSnackBar(
                  context,
                  AppLocalizations.of(context)!.sidebarFlushFailed(
                    e.toString(),
                  ),
                );
              }
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: context.themeColors.accentRed,
          ),
          child: Text(AppLocalizations.of(context)!.sidebarFlushDB),
        ),
      ],
    );
  }
}
