import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/app_localizations.dart';
import '../models/error_event.dart';
import '../theme/app_colors.dart';
import '../utils/secret_redactor.dart';

/// 可操作错误展示——`SelectableText` + 复制（+ US2 的 AI 分析按钮）。
///
/// 替换各对话框里红框 `Text`（不可选中复制）的统一组件。风格沿用既有
/// `SelectableText` 约定（monospace 11–12、`bgTertiary`、`radiusSm`）。
class ActionableError extends StatelessWidget {
  const ActionableError({
    super.key,
    required this.message,
    this.sql,
    this.connectionId,
    this.databaseName,
    this.onRetry,
    this.onAnalyze,
    this.severity = ErrorSeverity.error,
    this.redactSql = false,
    this.compact = false,
  });

  final String message;
  final String? sql;
  final String? connectionId;
  final String? databaseName;
  final VoidCallback? onRetry;

  /// 点击后把错误发给 AI 分析（US2）。为 null 时不显示按钮。
  final VoidCallback? onAnalyze;
  final ErrorSeverity severity;
  final bool redactSql;

  /// 紧凑变体（如 `ExpansionTile` subtitle 行）。
  final bool compact;

  Color _color(BuildContext context) {
    switch (severity) {
      case ErrorSeverity.error:
        return context.themeColors.error;
      case ErrorSeverity.warning:
        return context.themeColors.warning;
      case ErrorSeverity.info:
        return context.themeColors.accentBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = _color(context);
    final safeSql = sql;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            redactSecrets(message),
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: compact ? 11 : 12,
            ),
          ),
          if (safeSql != null && safeSql.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space1),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  redactSecrets(safeSql, redactSql: redactSql),
                  style: const TextStyle(
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppDesignSystem.space1),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _CopyButton(text: _copyPayload()),
              if (onAnalyze != null) ...[
                const SizedBox(width: AppDesignSystem.space1),
                TextButton.icon(
                  onPressed: onAnalyze,
                  icon: const Icon(LucideIcons.sparkles, size: 14),
                  label: Text(l10n.errorAnalyzeWithAi),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(width: AppDesignSystem.space1),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  label: Text(l10n.retry),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _copyPayload() {
    final buf = StringBuffer(redactSecrets(message));
    final s = sql;
    if (s != null && s.isNotEmpty) {
      buf.write('\n\nSQL:\n${redactSecrets(s, redactSql: redactSql)}');
    }
    return buf.toString();
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(_copied ? LucideIcons.check : LucideIcons.copy, size: 14),
      label: Text(_copied ? l10n.errorCopied : l10n.errorCopy),
    );
  }
}
