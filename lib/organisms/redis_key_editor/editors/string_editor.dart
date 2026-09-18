// 全功能 Redis GUI — 阶段2: String 类型编辑器
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';

class StringEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const StringEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<StringEditor> createState() => _StringEditorState();
}

class _StringEditorState extends State<StringEditor> {
  late TextEditingController _controller;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadStringValue();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadStringValue() async {
    setState(() => _isLoading = true);

    // 经 adapter.runCommand 绕过 _parseCommand;
    // 原 'GET ${key}' 字符串拼接在 key 含空格时会损坏。
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() {
        _errorMessage = 'Redis adapter not available';
        _isLoading = false;
      });
      return;
    }

    try {
      final raw = await adapter.runCommand(['GET', widget.keyName]);
      if (raw != null) {
        _controller.text = raw.toString();
      } else {
        _controller.clear();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load value: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveStringValue() async {
    // 经 adapter.runCommand 绕过 _parseCommand,
    // value 作为单独 bulk 参数传输 —— 含空格/换行/引号都安全。
    // 原 'SET ${key} ${value}' 拼接会让 'hello world' 只存 'hello'。
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Redis adapter not available'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      await adapter.runCommand(['SET', widget.keyName, _controller.text]);

      widget.onChanged?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('String saved successfully'),
            backgroundColor: context.themeColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save value: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            const SizedBox(height: AppDesignSystem.space3),
            ElevatedButton.icon(
              onPressed: _loadStringValue,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
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
          // Value label
          Text(
            'Value',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),

          // Text field for string value
          TextField(
            controller: _controller,
            maxLines: null,
            minLines: 8,
            keyboardType: TextInputType.multiline,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
            decoration: InputDecoration(
              hintText: 'Enter string value',
              hintStyle: TextStyle(color: context.themeColors.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                borderSide: BorderSide(
                  color: context.themeColors.accentBlue,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: context.themeColors.bgTertiary,
            ),
          ),

          const SizedBox(height: AppDesignSystem.space3),

          // Info text
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: AppDesignSystem.accentPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: AppDesignSystem.accentPrimary.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 16,
                  color: AppDesignSystem.accentPrimary,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    'String values can contain up to 512MB of data',
                    style: TextStyle(
                      color: AppDesignSystem.accentPrimary,
                      fontSize: AppDesignSystem.fontSizeSm,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDesignSystem.space3),

          // Action buttons — Save 走 runCommand(['SET', key, value]),
          // value 作为单独 bulk 参数,含空格/特殊字符安全。
          // 与 JsonEditor 的内联 Save 模式一致(参见 json_editor.dart)。
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveStringValue,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.save, size: 18),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.accentGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
