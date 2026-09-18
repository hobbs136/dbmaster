// C17 · Redis Set TTL 对话框 —— 自 builders/redis_tree_builder.dart 内嵌类
// _SetTtlDialog 迁出（行为逐行保持）。支持秒/毫秒/绝对时间三模式，直接调
// adapter（经 provider.getRedisAdapter，不拼 EXPIRE 字符串走 QueryTab）。
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../connection/error_boundary.dart';

class RedisSetTtlDialog extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;
  final String dbName;
  final String redisKey;

  const RedisSetTtlDialog({
    super.key,
    required this.provider,
    required this.connectionId,
    required this.dbName,
    required this.redisKey,
  });

  @override
  State<RedisSetTtlDialog> createState() => _RedisSetTtlDialogState();
}

class _RedisSetTtlDialogState extends State<RedisSetTtlDialog> {
  late final TextEditingController controller;
  // B2 — 支持秒/毫秒/绝对时间三种 TTL 模式
  String _mode = 'seconds'; // seconds | ms | at

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: '3600');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String get _label => switch (_mode) {
    'ms' => 'TTL (milliseconds, PEXPIRE):',
    'at' => 'Expire at Unix seconds (EXPIREAT):',
    _ => 'TTL (seconds, EXPIRE):',
  };

  String get _hint => switch (_mode) {
    'ms' => 'Enter TTL in milliseconds',
    'at' => 'Enter Unix timestamp (seconds)',
    _ => 'Enter TTL in seconds',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        'Set TTL',
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Key: ${widget.redisKey}',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space3),
              Wrap(
                spacing: AppDesignSystem.space1,
                runSpacing: AppDesignSystem.space1,
                children: [
                  ChoiceChip(
                    label: const Text('Seconds (EXPIRE)'),
                    selected: _mode == 'seconds',
                    onSelected: (_) => setState(() => _mode = 'seconds'),
                  ),
                  ChoiceChip(
                    label: const Text('Milli (PEXPIRE)'),
                    selected: _mode == 'ms',
                    onSelected: (_) => setState(() => _mode = 'ms'),
                  ),
                  ChoiceChip(
                    label: const Text('At (EXPIREAT)'),
                    selected: _mode == 'at',
                    onSelected: (_) => setState(() => _mode = 'at'),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Text(
                _label,
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space2),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: TextStyle(color: context.themeColors.textPrimary),
                decoration: InputDecoration(
                  hintText: _hint,
                  hintStyle: TextStyle(color: context.themeColors.textMuted),
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Text(
                'Presets: 60 (1min) | 3600 (1h) | 86400 (1d)',
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: AppDesignSystem.fontSizeXs,
                ),
              ),
            ],
          ),
        ),
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

  // B2 — 直接调 adapter(不再拼 EXPIRE 字符串走 QueryTab)
  Future<void> _onConfirm() async {
    final value = int.tryParse(controller.text.trim());
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid number'),
          backgroundColor: context.themeColors.accentOrange,
        ),
      );
      return;
    }
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      final bool ok;
      switch (_mode) {
        case 'ms':
          ok = await adapter.setPTTL(
            widget.redisKey,
            Duration(milliseconds: value),
          );
          break;
        case 'at':
          ok = await adapter.expireAt(
            widget.redisKey,
            DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true),
          );
          break;
        default:
          ok = await adapter.setTTL(widget.redisKey, Duration(seconds: value));
      }
      if (!mounted) return;
      if (ok) {
        widget.provider.loadRedisTTLKeys(widget.connectionId, widget.dbName);
        Navigator.pop(context);
      } else {
        AppErrorHandler.showErrorSnackBar(
          context,
          'Failed to set TTL (key may not exist)',
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(context, 'Failed to set TTL: $e');
    }
  }
}
