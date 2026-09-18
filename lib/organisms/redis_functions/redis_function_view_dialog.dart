// #6 — Redis Function Library 只读查看对话框
// 显示库名/engine/函数列表/Lua 源码（通过 FUNCTION LIST WITHCODE FILTERBY 拉取）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../atoms/app_loading.dart';

class RedisFunctionViewDialog extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;
  final String libraryName;

  const RedisFunctionViewDialog({
    super.key,
    required this.connectionId,
    required this.provider,
    required this.libraryName,
  });

  @override
  State<RedisFunctionViewDialog> createState() =>
      _RedisFunctionViewDialogState();
}

class _RedisFunctionViewDialogState extends State<RedisFunctionViewDialog> {
  bool _isLoading = true;
  String? _error;
  String? _source;
  List<Map<String, dynamic>> _functions = const [];
  String _engine = '';

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  Future<void> _loadSource() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final adapter = widget.provider.getRedisAdapter(widget.connectionId);
      if (adapter == null) {
        setState(() {
          _error = 'Redis adapter not available';
          _isLoading = false;
        });
        return;
      }
      // 拉取该库的元数据 + 源码（WITHCODE FILTERBY LIBRARY name）
      final source = await adapter.getRedisFunctionSource(widget.libraryName);
      // 用普通 LIST 拉元数据（保险：FILTERBY WITHCODE 在极旧版本不支持时降级）
      final libs = await adapter.getRedisFunctions();
      final lib = libs.where((l) => l.name == widget.libraryName).toList();
      if (!mounted) return;
      setState(() {
        if (lib.isNotEmpty) {
          _engine = lib.first.engine;
          _functions = lib.first.functions
              .map(
                (f) => {
                  'name': f.name,
                  'description': f.description ?? '',
                  'flags': f.flags.join(', '),
                },
              )
              .toList();
        }
        _source = source; // null 表示服务器不支持 WITHCODE
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(
            LucideIcons.bookOpen,
            color: context.themeColors.accentPurple,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              'Library: ${widget.libraryName}',
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeLg,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Copy source',
            icon: Icon(
              LucideIcons.copy,
              size: 18,
              color: context.themeColors.textSecondary,
            ),
            onPressed: (_source == null || _isLoading)
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _source ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Source copied to clipboard'),
                      ),
                    );
                  },
          ),
        ],
      ),
      content: SizedBox(width: 700, height: 500, child: _buildBody()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: AppBrandedLoading(size: 28, label: 'Loading source...'),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              color: context.themeColors.accentRed,
              size: 40,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            SelectableText(
              _error!,
              style: TextStyle(color: context.themeColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Meta
        if (_engine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
            child: Row(
              children: [
                _metaChip('Engine', _engine),
                const SizedBox(width: AppDesignSystem.space2),
                _metaChip('Functions', '${_functions.length}'),
              ],
            ),
          ),
        if (_functions.isNotEmpty) ...[
          Text(
            'Functions',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Wrap(
            spacing: AppDesignSystem.space2,
            runSpacing: AppDesignSystem.space1,
            children: _functions
                .map(
                  (f) => Chip(
                    label: Text(f['name'] as String),
                    labelStyle: const TextStyle(fontSize: 11),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppDesignSystem.space3),
        ],
        // Source
        Text(
          'Source (Lua)',
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: AppDesignSystem.fontSizeSm,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(color: context.themeColors.borderColor),
            ),
            child: _source == null
                ? Center(
                    child: Text(
                      'Source not available (server may not support FUNCTION LIST WITHCODE)',
                      style: TextStyle(color: context.themeColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      _source!,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontFamily: AppDesignSystem.monoFontFamily,
                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                        fontSize: AppDesignSystem.fontSizeXs,
                        height: 1.4,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.accentPurple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.accentPurple.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: AppDesignSystem.fontSizeXs,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: context.themeColors.accentPurple,
              fontSize: AppDesignSystem.fontSizeXs,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
