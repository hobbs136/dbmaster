// 第三波 C5 — MULTI-EXEC 事务执行器(原子提交,可选 WATCH)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';

class RedisTransactionPanel extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;

  const RedisTransactionPanel({
    super.key,
    required this.connectionId,
    required this.provider,
  });

  @override
  State<RedisTransactionPanel> createState() => _RedisTransactionPanelState();
}

class _TxResult {
  final String command;
  final String result;
  const _TxResult(this.command, this.result);
}

class _RedisTransactionPanelState extends State<RedisTransactionPanel> {
  final TextEditingController _cmdsController = TextEditingController(
    text: 'SET tx:k1 1\nINCR tx:k1\nGET tx:k1',
  );
  final TextEditingController _watchController = TextEditingController();
  final List<_TxResult> _results = [];
  bool _busy = false;
  String? _error;

  /// 切分单条命令(支持双/单引号包围 + 空格)。
  List<String> _parse(String cmd) {
    final parts = <String>[];
    final re = RegExp(r'''"([^"]*)"|'([^']*)'|(\S+)''');
    for (final m in re.allMatches(cmd)) {
      parts.add(m.group(1) ?? m.group(2) ?? m.group(3) ?? '');
    }
    return parts.where((s) => s.isNotEmpty).toList();
  }

  List<String> _parseList(String text) =>
      text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _exec() async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() => _error = 'Redis adapter not available');
      return;
    }
    final lines = _cmdsController.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    final commands = lines.map(_parse).where((c) => c.isNotEmpty).toList();
    if (commands.isEmpty) return;
    final watchKeys = _parseList(_watchController.text);

    setState(() {
      _busy = true;
      _results.clear();
      _error = null;
    });
    try {
      // WATCH(可选) → multiExec 原子 MULTI→cmds→EXEC
      if (watchKeys.isNotEmpty) {
        await adapter.watch(watchKeys);
      }
      final results = await adapter.multiExec(commands);
      if (!mounted) return;
      setState(() {
        _results.clear();
        _results.addAll(
          List.generate(
            commands.length,
            (i) => _TxResult(
              commands[i].join(' '),
              i < results.length
                  ? (results[i]?.toString() ?? '(nil)')
                  : '(no result)',
            ),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      // EXEC/DISCARD 后 WATCH 自动失效,unwatch 兜底
      if (watchKeys.isNotEmpty) {
        try {
          await adapter.unwatch();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cmdsController.dispose();
    _watchController.dispose();
    super.dispose();
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
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildEditor()),
                Container(width: 1, color: Theme.of(context).dividerColor),
                SizedBox(width: 360, child: _buildResults()),
              ],
            ),
          ),
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
          Icon(LucideIcons.lock, color: AppDesignSystem.dbRedis, size: 24),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MULTI / EXEC',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Atomic transaction (all-or-nothing). WATCH for optimistic locking.',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _busy ? null : _exec,
            icon: const Icon(LucideIcons.play, size: 18),
            label: const Text('EXEC'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Commands (one per line, atomic)',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeSm,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space2),
              TextField(
                controller: _watchController,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'WATCH keys (optional, comma separated)',
                  labelStyle: TextStyle(color: context.themeColors.textMuted),
                  hintText: 'leave empty for no optimistic lock',
                  hintStyle: TextStyle(color: context.themeColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            controller: _cmdsController,
            maxLines: null,
            expands: true,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(AppDesignSystem.space3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Text(
            'Results (${_results.length})',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: context.themeColors.accentOrange,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                      fontSize: AppDesignSystem.fontSizeXs,
                    ),
                  ),
                )
              : _results.isEmpty
              ? Center(
                  child: Text(
                    'EXEC to run transaction atomically',
                    style: TextStyle(color: context.themeColors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space3,
                        vertical: AppDesignSystem.space2,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: context.themeColors.borderSubtle,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.command,
                            style: TextStyle(
                              color: context.themeColors.textSecondary,
                              fontFamily: AppDesignSystem.monoFontFamily,

                              fontFamilyFallback:
                                  AppDesignSystem.monoFontFamilyFallback,
                              fontSize: AppDesignSystem.fontSizeXs,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            r.result,
                            style: TextStyle(
                              color: context.themeColors.textPrimary,
                              fontFamily: AppDesignSystem.monoFontFamily,

                              fontFamilyFallback:
                                  AppDesignSystem.monoFontFamilyFallback,
                              fontSize: AppDesignSystem.fontSizeXs,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
