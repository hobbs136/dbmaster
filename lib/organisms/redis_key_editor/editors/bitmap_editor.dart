// 第二波 A1 — Bitmap 编辑器(位网格 + SETBIT 翻转)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class BitmapEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const BitmapEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<BitmapEditor> createState() => _BitmapEditorState();
}

class _BitmapEditorState extends State<BitmapEditor> {
  // 最多渲染 8K 位,避免超大 key 卡顿
  static const int _maxDisplayBytes = 1024;
  bool _isLoading = true;
  List<int> _bytes = [];
  int _totalBits = 0; // BITCOUNT 置位数
  String? _error;
  bool _bitting = false; // 防止快速连点

  @override
  void initState() {
    super.initState();
    _loadData();
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
      final count = await adapter.getBitCount(widget.keyName);
      if (!mounted) return;
      setState(() {
        _bytes = raw ?? [];
        _totalBits = count;
        _error = _bytes.isEmpty ? 'Key is empty' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load bitmap: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleBit(int byteIdx, int bitIdx) async {
    if (_bitting || byteIdx >= _bytes.length) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    final current = (_bytes[byteIdx] >> (7 - bitIdx)) & 1;
    final newBit = 1 - current;
    // Redis bit offset: offset 0 = MSB of byte 0, i.e. leftmost cell = bitIdx.
    final offset = byteIdx * 8 + bitIdx;
    setState(() => _bitting = true);
    try {
      await adapter.setBit(widget.keyName, offset, newBit);
      if (!mounted) return;
      // 本地更新字节,避免整表重载
      setState(() {
        if (newBit == 1) {
          _bytes[byteIdx] = (_bytes[byteIdx] | (1 << (7 - bitIdx))) & 0xFF;
        } else {
          _bytes[byteIdx] = (_bytes[byteIdx] & ~(1 << (7 - bitIdx))) & 0xFF;
        }
        _totalBits += newBit == 1 ? 1 : -1;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SETBIT failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _bitting = false);
    }
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
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final display = _bytes.length > _maxDisplayBytes
        ? _bytes.sublist(0, _maxDisplayBytes)
        : _bytes;
    final truncated = _bytes.length > _maxDisplayBytes;
    return Column(
      children: [
        _buildInfoBar(context),
        if (truncated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space1,
            ),
            color: context.themeColors.accentOrange.withValues(alpha: 0.1),
            child: Text(
              'Showing first $_maxDisplayBytes bytes (${_bytes.length} total)',
              style: TextStyle(
                color: context.themeColors.accentOrange,
                fontSize: AppDesignSystem.fontSizeXs,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: display.length,
            itemBuilder: (context, i) => _buildByteRow(context, i, display[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.grid3x3, size: 18, color: AppDesignSystem.dbRedis),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'Bytes: ${_bytes.length}',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            'Set bits: $_totalBits',
            style: TextStyle(
              color: context.themeColors.accentGreen,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Reload',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildByteRow(BuildContext context, int byteIdx, int byteValue) {
    final hex = byteValue.toRadixString(16).padLeft(2, '0').toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              byteIdx.toString().padLeft(4, '0'),
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: AppDesignSystem.fontSizeXs,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '0x$hex',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: AppDesignSystem.fontSizeXs,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Row(
              children: List.generate(8, (bitIdx) {
                final set = ((byteValue >> (7 - bitIdx)) & 1) == 1;
                final offset = byteIdx * 8 + bitIdx;
                return Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      onTap: _bitting
                          ? null
                          : () => _toggleBit(byteIdx, bitIdx),
                      child: Tooltip(
                        message: 'offset $offset',
                        child: Container(
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: set
                                ? context.themeColors.accentBlue
                                : context.themeColors.bgTertiary,
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                              width: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppDesignSystem.radiusSm,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
