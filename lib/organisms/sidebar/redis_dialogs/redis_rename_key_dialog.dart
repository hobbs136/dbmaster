// C17 · Redis Rename Key 对话框 —— 自 builders/redis_tree_builder.dart 内嵌类
// _RenameKeyDialog 迁出（行为逐行保持）。RENAME 经 QueryTab 间接执行。
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart' show QueryTab;
import '../../../theme/app_theme.dart';
import '../../connection/error_boundary.dart';

class RedisRenameKeyDialog extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;
  final String dbName;
  final String redisKey;

  const RedisRenameKeyDialog({
    super.key,
    required this.provider,
    required this.connectionId,
    required this.dbName,
    required this.redisKey,
  });

  @override
  State<RedisRenameKeyDialog> createState() => _RedisRenameKeyDialogState();
}

class _RedisRenameKeyDialogState extends State<RedisRenameKeyDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.redisKey);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        'Rename Key',
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: TextField(
        controller: controller,
        style: TextStyle(color: context.themeColors.textPrimary),
        decoration: InputDecoration(
          labelText: 'New Key Name',
          labelStyle: TextStyle(color: context.themeColors.textMuted),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _onConfirm,
          style: TextButton.styleFrom(
            foregroundColor: context.themeColors.accentBlue,
          ),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }

  Future<void> _onConfirm() async {
    final newKey = controller.text.trim();

    if (newKey.isEmpty || newKey == widget.redisKey) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    try {
      final tab = QueryTab(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        title: 'RENAME',
        sql: 'RENAME \'${widget.redisKey}\' \'$newKey\'',
        connectionId: widget.connectionId,
        databaseName: widget.dbName,
        isAutoTitle: false,
      );
      await widget.provider.addTab(tab);
      widget.provider.loadRedisDatabaseKeyInfo(
        widget.connectionId,
        widget.dbName,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(context, 'Failed to rename key: $e');
    }
  }
}
