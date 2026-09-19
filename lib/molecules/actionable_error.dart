import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/app_localizations.dart';
import '../models/error_event.dart';
import '../theme/app_colors.dart';
import '../utils/secret_redactor.dart';

/// 键值详情项——错误附带的结构化元信息（如连接失败的 host/port/driver）。
class ErrorDetail {
  final String label;
  final String value;
  const ErrorDetail({required this.label, required this.value});
}

/// [ActionableError] message 的正文样式变体。
///
/// `compact` = 现状紧凑渲染（fontSize 11 等宽小字着色）；`body` = 正文
/// 渲染（fontSize 12）。默认（`style` 传 null）由既有 `compact` bool 派生。
enum ActionableErrorStyle { compact, body }

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
    this.details,
    this.style,
    this.actions,
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

  /// 键值详情列表（渲染于 SQL 区块之后）；null 或空 → 完全不渲染详情区。
  /// 值与 [message]/[sql] 一样经 `redactSecrets` 脱敏后才展示/复制。
  final List<ErrorDetail>? details;

  /// message 正文样式；null → 由既有 [compact] bool 派生（现行为），非空则覆盖。
  final ActionableErrorStyle? style;

  /// 追加在 onAnalyze/onRetry 语法糖按钮之后的自定义动作按钮；null → 不变。
  final List<Widget>? actions;

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
    final detailList = details;
    // style 非空时覆盖；null 时由既有 compact bool 派生，保持现行为不变。
    final effectiveStyle =
        style ??
        (compact ? ActionableErrorStyle.compact : ActionableErrorStyle.body);
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
              fontSize: effectiveStyle == ActionableErrorStyle.compact
                  ? 11
                  : 12,
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
          if (detailList != null && detailList.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space1),
            _buildDetails(context, detailList),
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
              for (final action in actions ?? const <Widget>[]) ...[
                const SizedBox(width: AppDesignSystem.space1),
                action,
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
    final d = details;
    if (d != null && d.isNotEmpty) {
      buf.write('\n\n');
      buf.write(
        d
            .map((detail) => '${detail.label}: ${redactSecrets(detail.value)}')
            .join('\n'),
      );
    }
    return buf.toString();
  }

  /// 键值详情区——沿用既有 SQL 区块语汇（`bgTertiary` + `radiusSm` +
  /// `maxHeight` 120 滚动容器）；label 用 textMuted 小字，value 用等宽小字。
  Widget _buildDetails(BuildContext context, List<ErrorDetail> items) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 120),
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: AppDesignSystem.space1),
              _detailRow(context, items[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, ErrorDetail detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.label,
          style: AppTextStyles.caption.copyWith(
            color: context.themeColors.textMuted,
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: SelectableText(
            redactSecrets(detail.value),
            style: const TextStyle(
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
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
