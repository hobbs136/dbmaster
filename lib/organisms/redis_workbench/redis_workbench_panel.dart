// 第三波 C2 — 命令行 Workbench(自由执行任意 Redis 命令)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../services/redis_result_formatter.dart';
import '../results/virtualized_data_table.dart';

class RedisWorkbenchPanel extends StatefulWidget {
  final String connectionId;
  final String databaseName;
  final AppProvider provider;

  const RedisWorkbenchPanel({
    super.key,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
  });

  @override
  State<RedisWorkbenchPanel> createState() => _RedisWorkbenchPanelState();
}

class _RedisWorkbenchPanelState extends State<RedisWorkbenchPanel> {
  final TextEditingController _cmdController = TextEditingController();
  final List<String> _history = [];
  List<String> _columns = const [];
  List<Map<String, dynamic>> _data = const [];
  bool _loading = false;
  String? _error;

  static const Set<String> _dangerous = {
    'FLUSHALL',
    'FLUSHDB',
    'SHUTDOWN',
    'MONITOR',
    'SAVE',
    'BGSAVE',
    'CONFIG',
    'DEBUG',
    'KEYS',
  };

  @override
  void dispose() {
    _cmdController.dispose();
    super.dispose();
  }

  /// 切分命令:支持双引号/单引号包围 + 空格。
  List<String> _parse(String cmd) {
    final parts = <String>[];
    final re = RegExp(r'''"([^"]*)"|'([^']*)'|(\S+)''');
    for (final m in re.allMatches(cmd)) {
      parts.add(m.group(1) ?? m.group(2) ?? m.group(3) ?? '');
    }
    return parts.where((s) => s.isNotEmpty).toList();
  }

  Future<bool> _confirm(String cmd) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          'Confirm: $cmd',
          style: TextStyle(color: context.themeColors.accentRed),
        ),
        content: Text(
          '$cmd is a potentially dangerous command. Continue?',
          style: TextStyle(color: context.themeColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.accentRed,
            ),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _execute() async {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    final parts = _parse(cmd);
    if (parts.isEmpty) return;
    final upper = parts[0].toUpperCase();

    if (_dangerous.contains(upper)) {
      if (!await _confirm(upper)) return;
    }

    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() => _error = 'Redis adapter not available');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 走 runCommand 绕过 executeQuery 黑名单/解析
      final result = await adapter.runCommand(parts);
      final rows = RedisResultFormatter.format(result, upper);
      if (!mounted) return;
      setState(() {
        _columns = rows.isNotEmpty
            ? rows.first.keys.toList()
            : const ['result'];
        _data = rows.isNotEmpty
            ? rows
            : [
                {'result': result?.toString() ?? '(nil)'},
              ];
        _history.insert(0, cmd);
        if (_history.length > 20) _history.removeLast();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 600,
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildInput(),
          if (_history.isNotEmpty) _buildHistory(),
          Expanded(child: _buildResult()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.terminal, color: AppDesignSystem.dbRedis, size: 24),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Command Workbench',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Run any Redis command (CONFIG/DEBUG/CLUSTER allowed with confirm)',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cmdController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              decoration: InputDecoration(
                hintText:
                    'e.g.  CONFIG GET maxmemory   |   CLUSTER INFO   |   GET mykey',
                hintStyle: TextStyle(color: context.themeColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                filled: true,
                fillColor: context.themeColors.bgTertiary,
              ),
              onSubmitted: (_) => _execute(),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: _loading ? null : _execute,
            icon: const Icon(LucideIcons.play, size: 18),
            label: const Text('Run'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Wrap(
        spacing: AppDesignSystem.space1,
        runSpacing: AppDesignSystem.space1,
        children: _history.take(10).map((h) {
          return ActionChip(
            label: Text(
              h.length > 30 ? '${h.substring(0, 30)}...' : h,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: AppDesignSystem.fontSizeXs,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
            ),
            onPressed: () => setState(() => _cmdController.text = h),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResult() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space4),
          child: SelectableText(
            _error!,
            style: TextStyle(
              color: context.themeColors.accentRed,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
        ),
      );
    }
    if (_data.isEmpty) {
      return Center(
        child: Text(
          'Run a command to see results',
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      child: VirtualizedDataTable(
        columns: _columns,
        data: _data,
        showRowNumbers: false,
      ),
    );
  }
}
