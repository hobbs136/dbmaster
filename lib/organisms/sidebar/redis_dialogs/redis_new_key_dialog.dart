// C17 · Redis 新建键对话框 —— 自 builders/redis_tree_builder.dart 内嵌类
// _NewKeyDialog 迁出（行为逐行保持）。独立成件：树右键菜单与能力菜单
// （键空间组「新建键」项）双入口共享。
//
// #hotfix-redis（迁入）：StatefulWidget 形态确保 TextEditingController 在
// 路由完全移除后才 dispose，避免退场动画期间 dispose 引发 framework crash。
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../connection/error_boundary.dart';

class RedisNewKeyDialog extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;
  final String dbName;

  const RedisNewKeyDialog({
    super.key,
    required this.provider,
    required this.connectionId,
    required this.dbName,
  });

  @override
  State<RedisNewKeyDialog> createState() => _RedisNewKeyDialogState();
}

class _RedisNewKeyDialogState extends State<RedisNewKeyDialog> {
  late final TextEditingController keyController;
  late final TextEditingController valueController;
  late final TextEditingController fieldController;
  late final TextEditingController scoreController;
  String selectedType = 'string';
  int? selectedTtlSeconds;

  final ttlOptions = const [
    (label: 'Never expire', seconds: null),
    (label: '1 minute', seconds: 60),
    (label: '5 minutes', seconds: 300),
    (label: '15 minutes', seconds: 900),
    (label: '1 hour', seconds: 3600),
    (label: '6 hours', seconds: 21600),
    (label: '1 day', seconds: 86400),
    (label: '7 days', seconds: 604800),
    (label: '30 days', seconds: 2592000),
  ];

  @override
  void initState() {
    super.initState();
    keyController = TextEditingController();
    valueController = TextEditingController();
    fieldController = TextEditingController();
    scoreController = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    keyController.dispose();
    valueController.dispose();
    fieldController.dispose();
    scoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final needsField = selectedType == 'hash' || selectedType == 'stream';

    return AlertDialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: Text(
        l10n.sidebarNewKey,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(selectedType),
                initialValue: selectedType,
                decoration: InputDecoration(labelText: l10n.sidebarRedisType),
                items: [
                  'string',
                  'hash',
                  'list',
                  'set',
                  'zset',
                  'stream',
                  'json',
                  'hyperloglog',
                ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) =>
                    setState(() => selectedType = v ?? selectedType),
              ),
              const SizedBox(height: AppDesignSystem.space3),
              TextField(
                controller: keyController,
                decoration: InputDecoration(labelText: l10n.sidebarKeys),
              ),
              if (needsField) ...[
                const SizedBox(height: AppDesignSystem.space3),
                TextField(
                  controller: fieldController,
                  decoration: InputDecoration(
                    labelText: l10n.sidebarRedisField,
                  ),
                ),
              ],
              if (selectedType == 'zset') ...[
                const SizedBox(height: AppDesignSystem.space3),
                TextField(
                  controller: scoreController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Score'),
                ),
              ],
              const SizedBox(height: AppDesignSystem.space3),
              TextField(
                controller: valueController,
                decoration: InputDecoration(
                  labelText: selectedType == 'hash'
                      ? l10n.sidebarRedisFieldValue
                      : l10n.sidebarRedisValue,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: AppDesignSystem.space3),
              DropdownButtonFormField<int?>(
                key: ValueKey(selectedTtlSeconds),
                initialValue: selectedTtlSeconds,
                decoration: InputDecoration(labelText: l10n.sidebarRedisExpire),
                items: ttlOptions
                    .map(
                      (opt) => DropdownMenuItem(
                        value: opt.seconds,
                        child: Text(opt.label),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => selectedTtlSeconds = v),
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
        TextButton(onPressed: _onAdd, child: Text(l10n.commonAdd)),
      ],
    );
  }

  Future<void> _onAdd() async {
    final key = keyController.text.trim();
    final value = valueController.text.trim();
    final field = fieldController.text.trim();
    final needsField = selectedType == 'hash' || selectedType == 'stream';

    if (key.isEmpty || value.isEmpty || (needsField && field.isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.sidebarRedisFieldsRequired,
          ),
        ),
      );
      return;
    }

    try {
      final scoreText = scoreController.text.trim();
      final score = double.tryParse(scoreText) != null ? scoreText : '0';
      final mainCommand = switch (selectedType) {
        'string' =>
          selectedTtlSeconds != null
              ? "SET '$key' '$value' EX $selectedTtlSeconds"
              : "SET '$key' '$value'",
        'hash' => "HSET '$key' '$field' '$value'",
        'list' => "LPUSH '$key' '$value'",
        'set' => "SADD '$key' '$value'",
        'zset' => "ZADD '$key' $score '$value'",
        'stream' => "XADD '$key' * '$field' '$value'",
        'json' => "JSON.SET '$key' '\$' '$value'",
        'hyperloglog' => "PFADD '$key' '$value'",
        _ => "SET '$key' '$value'",
      };

      final commands = <String>[mainCommand];
      if (selectedTtlSeconds != null && selectedType != 'string') {
        commands.add("EXPIRE '$key' $selectedTtlSeconds");
      }

      for (final cmd in commands) {
        await widget.provider.executeQuery(
          cmd,
          connectionId: widget.connectionId,
          database: widget.dbName,
        );
      }

      widget.provider.loadRedisDatabaseKeyInfo(
        widget.connectionId,
        widget.dbName,
      );
      widget.provider.loadRedisTTLKeys(widget.connectionId, widget.dbName);
      widget.provider.loadRedisDBStats(widget.connectionId, widget.dbName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.sidebarKeyCreated(key)),
          backgroundColor: context.themeColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        AppLocalizations.of(context)!.sidebarKeyFailed(e.toString()),
      );
    }
  }
}
