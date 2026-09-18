// 全功能 Redis GUI — 阶段2: JSON 类型编辑器(简化版)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class JsonEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const JsonEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<JsonEditor> createState() => _JsonEditorState();
}

class _JsonEditorState extends State<JsonEditor> {
  bool _isLoading = true;
  String? _jsonValue;
  String? _errorMessage;
  final TextEditingController _jsonController = TextEditingController();
  final TextEditingController _pathController = TextEditingController(
    text: '\$',
  );

  @override
  void initState() {
    super.initState();
    _loadJsonData();
  }

  @override
  void dispose() {
    _jsonController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _loadJsonData() async {
    setState(() => _isLoading = true);

    // 经 adapter.runCommand 绕过 _parseCommand;修复原 \${widget.keyName} 插值 bug
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() {
        _errorMessage = 'Redis adapter not available';
        _isLoading = false;
      });
      return;
    }

    try {
      final raw = await adapter.runCommand([
        'JSON.GET',
        widget.keyName,
        _pathController.text,
      ]);
      if (raw != null) {
        setState(() {
          _jsonValue = raw.toString();
          _jsonController.text = _jsonValue!;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load JSON data: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveJsonData() async {
    // 经 adapter.runCommand 绕过 _parseCommand,JSON 值原样作为 bulk 传输
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Redis adapter not available'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
      return;
    }

    try {
      await adapter.runCommand([
        'JSON.SET',
        widget.keyName,
        _pathController.text,
        _jsonController.text,
      ]);

      widget.onChanged?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JSON saved successfully'),
            backgroundColor: context.themeColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save JSON: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  void _formatJson() {
    try {
      final json = _jsonController.text;
      // 简化:仅检查是否为有效JSON格式
      if (json.startsWith('{') || json.startsWith('[')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JSON format validation not implemented'),
            backgroundColor: context.themeColors.accentOrange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid JSON: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
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
              _errorMessage!,
              style: TextStyle(color: context.themeColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                LucideIcons.code,
                color: context.themeColors.accentGreen,
                size: 24,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'JSON Editor',
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: AppDesignSystem.fontSizeLg,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space4),

          // JSONPath input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  style: TextStyle(color: context.themeColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'JSONPath',
                    labelStyle: TextStyle(color: context.themeColors.textMuted),
                    hintText: r'$',
                    hintStyle: TextStyle(color: context.themeColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    filled: true,
                    fillColor: context.themeColors.bgTertiary,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: 实现按路径查询
                },
                icon: const Icon(LucideIcons.search, size: 18),
                label: const Text('Query'),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),

          // JSON editor
          Expanded(
            child: TextField(
              controller: _jsonController,
              maxLines: null,
              minLines: 15,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeSm,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              decoration: InputDecoration(
                hintText: '{\n  "key": "value"\n}',
                hintStyle: TextStyle(color: context.themeColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                filled: true,
                fillColor: context.themeColors.bgTertiary,
              ),
              onChanged: (_) => widget.onChanged?.call(),
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),

          // Action buttons
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _formatJson,
                icon: const Icon(LucideIcons.alignLeft, size: 18),
                label: const Text('Format'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesignSystem.accentPrimary,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              ElevatedButton.icon(
                onPressed: _saveJsonData,
                icon: const Icon(LucideIcons.save, size: 18),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.accentGreen,
                ),
              ),
              const Spacer(),
              Text(
                r'JSONPath: $.key',
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppDesignSystem.space3),

          // Info section
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.accentGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.accentGreen.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.info,
                      size: 16,
                      color: context.themeColors.accentGreen,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      'RedisJSON',
                      style: TextStyle(
                        color: context.themeColors.accentGreen,
                        fontSize: AppDesignSystem.fontSizeSm,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space2),
                Text(
                  'RedisJSON is a Redis module that implements JSON data structures',
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                Wrap(
                  spacing: AppDesignSystem.space2,
                  runSpacing: AppDesignSystem.space2,
                  children: [
                    _buildOpChip('JSON.GET'),
                    _buildOpChip('JSON.SET'),
                    _buildOpChip('JSON.MGET'),
                    _buildOpChip('JSON.ARRAPPEND'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpChip(String op) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.accentGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.accentGreen.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        op,
        style: TextStyle(
          color: context.themeColors.accentGreen,
          fontSize: AppDesignSystem.fontSizeXs,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
