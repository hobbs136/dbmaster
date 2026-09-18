import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../atoms/sql_code_block.dart';
import '../../theme/app_theme.dart';
import '../../plugins/ai_skill_plugin.dart';

/// 统一渲染 AI 返回的内容（C23 envelope 化）。
///
/// [envelopeType] 显式声明时按类型分发（技能结果携带 envelopeType 时）：
/// sql → SqlCodeBlock、markdown → MarkdownBody、json → 格式化代码块、
/// diff → 行级着色 diff 视图；null（存量内容）保留启发式
/// （```sql 代码块 → JSON 探测 → markdown）。
class AiResultRenderer extends StatelessWidget {
  final String content;
  final bool allowSqlExecution;

  /// 显式 envelope 类型（null = 启发式）。
  final AiSkillEnvelopeType? envelopeType;

  const AiResultRenderer({
    super.key,
    required this.content,
    this.allowSqlExecution = false,
    this.envelopeType,
  });

  @override
  Widget build(BuildContext context) {
    final type = envelopeType;
    if (type != null) {
      return _buildEnvelope(context, type);
    }
    return _buildHeuristic(context);
  }

  Widget _buildEnvelope(BuildContext context, AiSkillEnvelopeType type) {
    switch (type) {
      case AiSkillEnvelopeType.sql:
        return _codeBlock(context, content);
      case AiSkillEnvelopeType.json:
        final formatted = _formatJson(content) ?? content;
        return _codeBlock(context, formatted);
      case AiSkillEnvelopeType.diff:
        return _DiffView(content: content);
      case AiSkillEnvelopeType.markdown:
        return _markdown(context);
    }
  }

  Widget _buildHeuristic(BuildContext context) {
    final codeBlock = _parseCodeBlock(content);
    if (codeBlock != null) {
      return _codeBlock(context, codeBlock);
    }

    if (_isJsonContent(content)) {
      final formatted = _formatJson(content);
      if (formatted != null) {
        return _codeBlock(context, formatted);
      }
    }

    return _markdown(context);
  }

  Widget _codeBlock(BuildContext context, String code) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: SingleChildScrollView(child: SqlCodeBlock(code: code)),
      ),
    );
  }

  Widget _markdown(BuildContext context) {
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        code: TextStyle(
          fontSize: 11,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          color: Theme.of(context).colorScheme.onSurface,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  /// 解析 markdown 代码块，返回代码内容（如果检测到）。
  String? _parseCodeBlock(String text) {
    final trimmed = text.trim();
    final codeFenceRegex = RegExp(
      r'^```(?:\w+)?\n([\s\S]*?)\n```$',
      multiLine: false,
    );
    final match = codeFenceRegex.firstMatch(trimmed);
    if (match != null) {
      final code = match.group(1);
      if (code != null && code.trim().isNotEmpty) {
        return code.trim();
      }
    }
    return null;
  }

  bool _isJsonContent(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  String? _formatJson(String text) {
    try {
      final decoded = jsonDecode(text);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// unified diff 文本级渲染：+ 行增（绿底）、- 行删（红底）、@@ hunk 头灰。
/// 不做块级对齐——内容是 AI 生成的 diff 文本，行级着色即够用。
class _DiffView extends StatelessWidget {
  final String content;

  const _DiffView({required this.content});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final lines = content.split('\n');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          color: colors.bgPrimary,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in lines)
                  Container(
                    color: _lineColor(context, line),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space2,
                      vertical: 1,
                    ),
                    child: Text(
                      line.isEmpty ? ' ' : line,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontFamily: AppDesignSystem.monoFontFamily,
                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                        color: _lineTextColor(context, line),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color? _lineColor(BuildContext context, String line) {
    final colors = context.themeColors;
    if (line.startsWith('+')) {
      return colors.success.withValues(alpha: 0.1);
    }
    if (line.startsWith('-')) {
      return colors.error.withValues(alpha: 0.1);
    }
    return null;
  }

  Color _lineTextColor(BuildContext context, String line) {
    final colors = context.themeColors;
    if (line.startsWith('+')) return colors.success;
    if (line.startsWith('-')) return colors.error;
    if (line.startsWith('@@')) return colors.textMuted;
    return colors.textSecondary;
  }
}
