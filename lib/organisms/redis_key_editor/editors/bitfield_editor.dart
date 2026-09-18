// 第二波 A2 — Bitfield 编辑器(复合 GET/SET/INCRBY + OVERFLOW)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class BitfieldEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const BitfieldEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<BitfieldEditor> createState() => _BitfieldEditorState();
}

class _BitfieldEditorState extends State<BitfieldEditor> {
  static const int _maxPreviewBytes = 256;
  static const List<String> _opOptions = ['GET', 'SET', 'INCRBY'];
  static const List<String> _typeOptions = [
    'u8',
    'u16',
    'u32',
    'i8',
    'i16',
    'i32',
  ];
  static const List<String> _overflowOptions = ['WRAP', 'SAT', 'FAIL'];

  bool _isLoading = true;
  String? _error;
  List<int> _bytes = [];

  String _op = 'GET';
  String _type = 'u8';
  String _overflow = 'WRAP';
  final TextEditingController _offsetCtrl = TextEditingController(text: '0');
  final TextEditingController _valueCtrl = TextEditingController(text: '0');
  final List<String> _ops = [];
  final List<String> _results = [];
  bool _executing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _offsetCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() {
        _error = 'Redis adapter not available';
        _isLoading = false;
      });
      return;
    }
    try {
      final raw = await adapter.getRawBytes(widget.keyName);
      if (!mounted) return;
      setState(() {
        _bytes = raw ?? [];
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addOp() {
    final offset = _offsetCtrl.text.trim();
    if (offset.isEmpty) return;
    final tokens = <String>[_op, _type, offset];
    if (_op == 'SET' || _op == 'INCRBY') {
      tokens.add(_valueCtrl.text.trim());
    }
    setState(() => _ops.add(tokens.join(' ')));
  }

  Future<void> _execute() async {
    if (_ops.isEmpty) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    // 扁平化操作 + 追加 OVERFLOW
    final flat = <String>[];
    for (final op in _ops) {
      flat.addAll(op.split(' '));
    }
    flat.addAll(['OVERFLOW', _overflow]);
    setState(() => _executing = true);
    try {
      final result = await adapter.bitfield(widget.keyName, flat);
      if (!mounted) return;
      // 结果仅对应 GET/INCRBY 操作(SET 不产生返回值)
      final readOps = _ops
          .where((o) => o.startsWith('GET') || o.startsWith('INCRBY'))
          .toList();
      setState(() {
        _results.clear();
        for (var i = 0; i < readOps.length && i < result.length; i++) {
          _results.add('${readOps[i]}  →  ${result[i]}');
        }
      });
      widget.onChanged?.call();
      await _loadData(); // 刷新 hex 预览
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('BITFIELD failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  String get _hexPreview {
    final view = _bytes.length > _maxPreviewBytes
        ? _bytes.sublist(0, _maxPreviewBytes)
        : _bytes;
    if (view.isEmpty) return '(empty)';
    return view
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: context.themeColors.accentRed,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              _error!,
              style: TextStyle(color: context.themeColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHexPreview(context),
          const SizedBox(height: AppDesignSystem.space4),
          _buildOpBuilder(context),
          const SizedBox(height: AppDesignSystem.space3),
          if (_ops.isNotEmpty) _buildOpList(context),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _executing || _ops.isEmpty ? null : _execute,
                icon: const Icon(LucideIcons.play, size: 18),
                label: const Text('Execute'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.accentBlue,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              if (_ops.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_ops.clear),
                  child: const Text('Clear ops'),
                ),
            ],
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space3),
            _buildResults(context),
          ],
        ],
      ),
    );
  }

  Widget _buildHexPreview(BuildContext context) {
    final truncated = _bytes.length > _maxPreviewBytes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: Theme.of(context).dividerColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.brackets,
                size: 16,
                color: AppDesignSystem.dbRedis,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'Raw bytes (${_bytes.length} B${truncated ? ", preview $_maxPreviewBytes" : ""})',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          SelectableText(
            _hexPreview,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: AppDesignSystem.fontSizeXs,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpBuilder(BuildContext context) {
    final needsValue = _op == 'SET' || _op == 'INCRBY';
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: Theme.of(context).dividerColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add operation',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Row(
            children: [
              _dropdown(
                context,
                'Op',
                _op,
                _opOptions,
                (v) => setState(() => _op = v!),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              _dropdown(
                context,
                'Type',
                _type,
                _typeOptions,
                (v) => setState(() => _type = v!),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: TextField(
                  controller: _offsetCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Offset (#N or N)',
                    isDense: true,
                  ),
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  ),
                ),
              ),
              if (needsValue) ...[
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: TextField(
                    controller: _valueCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      isDense: true,
                    ),
                    style: TextStyle(
                      color: context.themeColors.textPrimary,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppDesignSystem.space2),
              IconButton.filled(
                onPressed: _addOp,
                icon: const Icon(LucideIcons.plus),
                tooltip: 'Add operation',
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          _dropdown(
            context,
            'Overflow',
            _overflow,
            _overflowOptions,
            (v) => setState(() => _overflow = v!),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(
    BuildContext context,
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      width: 110,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
        style: TextStyle(
          color: context.themeColors.textPrimary,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontSize: AppDesignSystem.fontSizeSm,
        ),
      ),
    );
  }

  Widget _buildOpList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Operations (${_ops.length})',
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: AppDesignSystem.fontSizeSm,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        ..._ops.asMap().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: context.themeColors.textPrimary,
                      fontSize: AppDesignSystem.fontSizeXs,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 16),
                  onPressed: () => setState(() => _ops.removeAt(e.key)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.accentGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.accentGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Results',
            style: TextStyle(
              color: context.themeColors.accentGreen,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          ..._results.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SelectableText(
                r,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
