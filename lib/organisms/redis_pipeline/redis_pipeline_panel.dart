// 第三波 C4 — Pipeline 执行器(批量并发 + Future.wait)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';

class RedisPipelinePanel extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;

  const RedisPipelinePanel({
    super.key,
    required this.connectionId,
    required this.provider,
  });

  @override
  State<RedisPipelinePanel> createState() => _RedisPipelinePanelState();
}

class _PipeResult {
  final String command;
  final String result;
  final bool ok;
  const _PipeResult(this.command, this.result, this.ok);
}

class _RedisPipelinePanelState extends State<RedisPipelinePanel> {
  final TextEditingController _cmdsController = TextEditingController(
    text: 'SET pipe:k1 v1\nSET pipe:k2 v2\nGET pipe:k1\nINCR pipe:counter',
  );
  final List<_PipeResult> _results = [];
  bool _busy = false;
  int _totalMs = 0;
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

  Future<void> _run() async {
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
    if (lines.isEmpty) return;
    final commands = lines.map(_parse).where((c) => c.isNotEmpty).toList();
    if (commands.isEmpty) return;

    setState(() {
      _busy = true;
      _results.clear();
      _error = null;
    });
    final sw = Stopwatch()..start();
    try {
      // pipeStart 启用 Nagle 缓冲 → 连发 runCommand → Future.wait 一次 RTT
      adapter.pipeStart();
      final futures = commands.map(
        (c) => adapter.runCommand(c).then((v) => v).catchError((e) => e),
      );
      final raw = await Future.wait(futures);
      adapter.pipeEnd();
      sw.stop();
      if (!mounted) return;
      setState(() {
        _totalMs = sw.elapsedMilliseconds;
        for (var i = 0; i < commands.length && i < raw.length; i++) {
          final r = raw[i];
          final isErr = r is Exception || r is Error;
          _results.add(
            _PipeResult(
              commands[i].join(' '),
              r?.toString() ?? '(nil)',
              !isErr,
            ),
          );
        }
      });
    } catch (e) {
      adapter.pipeEnd(); // 确保 flush
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cmdsController.dispose();
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
          Icon(
            LucideIcons.fastForward,
            color: AppDesignSystem.dbRedis,
            size: 24,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pipeline',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Batch commands in one RTT (no atomicity guarantee)',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(LucideIcons.play, size: 18),
            label: const Text('Run Pipeline'),
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
          child: Text(
            'Commands (one per line, # for comment)',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
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
          child: Row(
            children: [
              Text(
                'Results (${_results.length})',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeSm,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_results.isNotEmpty)
                Text(
                  '$_totalMs ms',
                  style: TextStyle(
                    color: context.themeColors.accentGreen,
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: context.themeColors.accentRed,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                    ),
                  ),
                )
              : _results.isEmpty
              ? Center(
                  child: Text(
                    'Run a pipeline to see results',
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
                          Row(
                            children: [
                              Icon(
                                r.ok
                                    ? LucideIcons.circleCheckBig
                                    : LucideIcons.circleAlert,
                                size: 14,
                                color: r.ok
                                    ? context.themeColors.accentGreen
                                    : context.themeColors.accentRed,
                              ),
                              const SizedBox(width: AppDesignSystem.space1),
                              Expanded(
                                child: Text(
                                  r.command,
                                  style: TextStyle(
                                    color: context.themeColors.textSecondary,
                                    fontFamily: AppDesignSystem.monoFontFamily,

                                    fontFamilyFallback:
                                        AppDesignSystem.monoFontFamilyFallback,
                                    fontSize: AppDesignSystem.fontSizeXs,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
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
