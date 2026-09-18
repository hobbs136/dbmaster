// #6 — Redis Function 执行对话框（FCALL / FCALL_RO）
// 用户输入 keys（逗号分隔）和 args（逗号分隔），调用函数并展示返回值。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../atoms/app_loading.dart';

class RedisFunctionExecuteDialog extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;
  final String functionName;

  const RedisFunctionExecuteDialog({
    super.key,
    required this.connectionId,
    required this.provider,
    required this.functionName,
  });

  @override
  State<RedisFunctionExecuteDialog> createState() =>
      _RedisFunctionExecuteDialogState();
}

class _RedisFunctionExecuteDialogState
    extends State<RedisFunctionExecuteDialog> {
  final TextEditingController _keysController = TextEditingController();
  final TextEditingController _argsController = TextEditingController();
  bool _readOnly = false;
  bool _isRunning = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _keysController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  /// 解析逗号分隔输入为参数列表（trim 空段、忽略空串）。
  List<String> _parseCsv(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _run() async {
    setState(() {
      _isRunning = true;
      _result = null;
      _error = null;
    });
    try {
      final adapter = widget.provider.getRedisAdapter(widget.connectionId);
      if (adapter == null) {
        setState(() {
          _error = 'Redis adapter not available';
          _isRunning = false;
        });
        return;
      }
      final keys = _parseCsv(_keysController.text);
      final args = _parseCsv(_argsController.text);
      final result = await adapter.callRedisFunction(
        widget.functionName,
        keys: keys,
        args: args,
        readOnly: _readOnly,
      );
      if (!mounted) return;
      setState(() {
        _result = _prettyPrint(result);
        _isRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isRunning = false;
      });
    }
  }

  /// 把任意 Redis 回复渲染成可读字符串。
  String _prettyPrint(dynamic result) {
    if (result == null) return '(nil)';
    if (result is List) {
      if (result.isEmpty) return '(empty array)';
      final items = result.asMap().entries.map((e) {
        final idx = e.key + 1;
        final val = e.value == null ? '(nil)' : _prettyPrint(e.value);
        return '$idx) $val';
      });
      return items.join('\n');
    }
    return result.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(
            LucideIcons.play,
            color: context.themeColors.accentGreen,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              'Execute: ${widget.functionName}',
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSizeLg,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Keys input
            Text(
              'Keys (comma-separated)',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            TextField(
              controller: _keysController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: AppDesignSystem.fontSizeSm,
              ),
              decoration: InputDecoration(
                hintText: 'key1, key2, ...',
                hintStyle: TextStyle(color: context.themeColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                filled: true,
                fillColor: context.themeColors.bgTertiary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),

            // Args input
            Text(
              'Args (comma-separated)',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            TextField(
              controller: _argsController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: AppDesignSystem.fontSizeSm,
              ),
              decoration: InputDecoration(
                hintText: 'arg1, arg2, ...',
                hintStyle: TextStyle(color: context.themeColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                filled: true,
                fillColor: context.themeColors.bgTertiary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),

            // Read-only switch
            Row(
              children: [
                Switch(
                  value: _readOnly,
                  onChanged: (v) => setState(() => _readOnly = v),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    'Use FCALL_RO (read-only — function must declare no-writes)',
                    style: TextStyle(
                      color: context.themeColors.textSecondary,
                      fontSize: AppDesignSystem.fontSizeXs,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space3),

            // Result / error
            if (_isRunning)
              Center(child: AppBrandedLoading(size: 24, label: 'Running...'))
            else if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDesignSystem.space3),
                decoration: BoxDecoration(
                  color: context.themeColors.accentRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(
                    color: context.themeColors.accentRed.withOpacity(0.3),
                  ),
                ),
                child: SelectableText(
                  _error!,
                  style: TextStyle(
                    color: context.themeColors.accentRed,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                ),
              )
            else if (_result != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Result',
                    style: TextStyle(
                      color: context.themeColors.textSecondary,
                      fontSize: AppDesignSystem.fontSizeSm,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(AppDesignSystem.space3),
                    decoration: BoxDecoration(
                      color: context.themeColors.bgTertiary,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      border: Border.all(
                        color: context.themeColors.borderColor,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _result!,
                        style: TextStyle(
                          color: context.themeColors.textPrimary,
                          fontFamily: AppDesignSystem.monoFontFamily,
                          fontFamilyFallback:
                              AppDesignSystem.monoFontFamilyFallback,
                          fontSize: AppDesignSystem.fontSizeXs,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRunning ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        LoadingButton(
          label: _result == null ? 'Run' : 'Run Again',
          onPressed: _isRunning ? null : _run,
          isLoading: _isRunning,
          backgroundColor: context.themeColors.accentGreen,
        ),
      ],
    );
  }
}
