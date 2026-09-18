// C17 · Redis Edit Config 对话框 —— 自 builders/redis_tree_builder.dart 内嵌类
// _EditConfigDialog 迁出（行为逐行保持）。CONFIG SET 经 provider.setRedisConfig。
import 'package:flutter/material.dart';

import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../connection/error_boundary.dart';

class RedisEditConfigDialog extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;

  const RedisEditConfigDialog({
    super.key,
    required this.provider,
    required this.connectionId,
  });

  @override
  State<RedisEditConfigDialog> createState() => _RedisEditConfigDialogState();
}

class _RedisEditConfigDialogState extends State<RedisEditConfigDialog> {
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _valueCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _onApply() async {
    final k = _keyCtrl.text.trim();
    final v = _valueCtrl.text;
    if (k.isEmpty) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.provider.setRedisConfig(widget.connectionId, {
        k: v,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Config updated: $k' : 'Failed (parameter may be read-only)',
          ),
          backgroundColor: ok
              ? context.themeColors.accentGreen
              : context.themeColors.accentOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        'Edit Config',
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _keyCtrl,
              style: TextStyle(color: context.themeColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Parameter (e.g. loglevel, maxmemory)',
              ),
              autofocus: true,
            ),
            const SizedBox(height: AppDesignSystem.space2),
            TextField(
              controller: _valueCtrl,
              style: TextStyle(color: context.themeColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Value'),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              'Uses CONFIG SET. Some parameters (e.g. databases) are read-only.',
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: AppDesignSystem.fontSizeXs,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _onApply,
          style: TextButton.styleFrom(
            foregroundColor: context.themeColors.accentBlue,
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
