// 第四波 D2 — 内存深度分析(Top-N / Doctor / Stats)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../results/virtualized_data_table.dart';

class RedisMemoryAnalysisPanel extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;

  const RedisMemoryAnalysisPanel({
    super.key,
    required this.connectionId,
    required this.provider,
  });

  @override
  State<RedisMemoryAnalysisPanel> createState() =>
      _RedisMemoryAnalysisPanelState();
}

class _RedisMemoryAnalysisPanelState extends State<RedisMemoryAnalysisPanel> {
  int _tab = 0; // 0=Top-N 1=Doctor 2=Stats
  List<Map<String, dynamic>> _topN = const [];
  String _text = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      if (_tab == 0) {
        final items = await adapter.getTopKeysByMemory();
        if (!mounted) return;
        setState(() {
          _topN = items
              .map(
                (e) => {
                  'key': e['key'],
                  'bytes': e['bytes'],
                  'size': _fmtBytes(e['bytes'] as int),
                },
              )
              .toList();
        });
      } else if (_tab == 1) {
        final t = await adapter.memoryDoctor();
        if (!mounted) return;
        setState(() => _text = t);
      } else {
        final s = await adapter.memoryStats();
        if (!mounted) return;
        setState(() => _text = s?.toString() ?? '(unavailable)');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchTab(int t) {
    if (t == _tab) return;
    setState(() {
      _tab = t;
      _text = '';
      _topN = const [];
    });
    _load();
  }

  String _fmtBytes(int b) {
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 520,
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.chartColumn,
                color: AppDesignSystem.dbRedis,
                size: 24,
              ),
              const SizedBox(width: AppDesignSystem.space3),
              Expanded(
                child: Text(
                  'Memory Analysis',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ChoiceChip(
                label: const Text('Top-N'),
                selected: _tab == 0,
                onSelected: (_) => _switchTab(0),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              ChoiceChip(
                label: const Text('Doctor'),
                selected: _tab == 1,
                onSelected: (_) => _switchTab(1),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              ChoiceChip(
                label: const Text('Stats'),
                selected: _tab == 2,
                onSelected: (_) => _switchTab(2),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space4),
          child: SelectableText(
            _error!,
            style: TextStyle(color: context.themeColors.accentRed),
          ),
        ),
      );
    }
    if (_tab == 0) {
      if (_topN.isEmpty) {
        return Center(
          child: Text(
            'No keys with memory data',
            style: TextStyle(color: context.themeColors.textMuted),
          ),
        );
      }
      return VirtualizedDataTable(
        columns: const ['key', 'bytes', 'size'],
        data: _topN,
        showRowNumbers: false,
      );
    }
    return SingleChildScrollView(
      child: SelectableText(
        _text.isEmpty ? '(loading...)' : _text,
        style: TextStyle(
          color: context.themeColors.textPrimary,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontSize: AppDesignSystem.fontSizeXs,
        ),
      ),
    );
  }
}
