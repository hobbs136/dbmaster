import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:highlight/highlight_core.dart' show highlight;
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/javascript.dart';
import '../../models/database_models.dart';
import '../../models/ai_message_type.dart';
import '../../models/query_optimizer/execution_plan.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/thinking_card.dart';
import '../../atoms/typewriter_text.dart';
import '../../utils/message_time_formatter.dart';
import '../../providers/app_provider.dart';
import '../../plugins/ai_skill_plugin.dart' show AiSkillEnvelope;
import 'ai_result_renderer.dart';
import 'widgets/schema_impact_card.dart';
import 'widgets/tool_card_shell.dart';
import 'widgets/tool_content_view.dart';
import 'widgets/tool_group_view.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../query_optimizer/query_plan_visualizer.dart';

void _registerAiHighlightLanguages() {
  highlight.registerLanguage('json', json);
  highlight.registerLanguage('javascript', javascript);
}

// ignore: unused_element
final bool _aiLanguagesRegistered = () {
  _registerAiHighlightLanguages();
  return true;
}();

class AiMessageItem extends StatelessWidget {
  final AiMessage message;
  final Function(String sql, bool isDangerous) onExecuteSql;
  final Function(String sql) onOpenInNewQuery;
  final Function(String messageId) onToggleBookmark;
  final Function(String messageId, String content) onBranchFromMessage;
  final VoidCallback? onRegenerate;
  final VoidCallback? onContinue;
  final Function(String table, String? whereClause)? onCreateExportTask;

  const AiMessageItem({
    super.key,
    required this.message,
    required this.onExecuteSql,
    required this.onOpenInNewQuery,
    required this.onToggleBookmark,
    required this.onBranchFromMessage,
    this.onRegenerate,
    this.onContinue,
    this.onCreateExportTask,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxBubbleWidth = constraints.maxWidth * 0.82;
          return Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: isUser
                ? [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(context, isUser),
                          const SizedBox(height: AppDesignSystem.space1_5),
                          _buildContentCard(context),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2_5),
                    _buildAvatar(context, isUser),
                  ]
                : [
                    _buildAvatar(context, isUser),
                    const SizedBox(width: AppDesignSystem.space2_5),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(context, isUser),
                          const SizedBox(height: AppDesignSystem.space1_5),
                          _buildContentCard(context),
                          if (message.isDangerous == true)
                            _buildDangerBadge(context),
                          const SizedBox(height: AppDesignSystem.space1),
                          _buildActionBar(context),
                        ],
                      ),
                    ),
                  ],
          );
        },
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, bool isUser) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: isUser
          ? context.themeColors.accentBlue
          : context.themeColors.accentPurple,
      child: Icon(
        isUser ? LucideIcons.user : LucideIcons.bot,
        size: 14,
        color: Colors.white,
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isUser) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: MessageTimeFormatter.formatFullTime(message.timestamp),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            isUser ? l10n.messageLabelYou : l10n.messageLabelAi,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: context.themeColors.textPrimary,
            ),
          ),
          Text(
            MessageTimeFormatter.formatTime(message.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textMuted,
            ),
          ),
          _buildStatusIndicator(context),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    switch (message.status) {
      case AiMessageStatus.sending:
        final l10n = AppLocalizations.of(context)!;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: context.themeColors.accentPurple,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.messageStatusSending,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.accentPurple,
              ),
            ),
          ],
        );
      case AiMessageStatus.streaming:
        final l10n = AppLocalizations.of(context)!;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: context.themeColors.accentPurple,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.messageStatusGenerating,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.accentPurple,
              ),
            ),
          ],
        );
      case AiMessageStatus.completed:
        return Icon(
          LucideIcons.circleCheckBig,
          size: 12,
          color: context.themeColors.success,
        );
      case AiMessageStatus.failed:
        final l10n = AppLocalizations.of(context)!;
        return Tooltip(
          message: message.errorMessage ?? l10n.messageStatusFailed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.circleAlert,
                size: 12,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                l10n.messageStatusFailed,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.error,
                ),
              ),
            ],
          ),
        );
      case AiMessageStatus.cancelled:
        final l10n = AppLocalizations.of(context)!;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleX,
              size: 12,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.messageStatusCancelled,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ],
        );
      case AiMessageStatus.interrupted:
        final l10n = AppLocalizations.of(context)!;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circlePause,
              size: 12,
              color: context.themeColors.warning,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.messageStatusCancelled,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.warning,
              ),
            ),
          ],
        );
      case AiMessageStatus.sent:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTokenUsage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      children: [
        _TokenChip(
          icon: LucideIcons.arrowUp,
          label: l10n.tokenUsagePrompt(message.promptTokens),
        ),
        _TokenChip(
          icon: LucideIcons.arrowDown,
          label: l10n.tokenUsageCompletion(message.completionTokens),
        ),
        _TokenChip(
          icon: LucideIcons.chartPie,
          label: l10n.tokenUsageTotal(message.totalTokens),
          isTotal: true,
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context) {
    if (message.isUser) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final isAnalyzeExport =
        message.toolName == 'analyze_export' ||
        (message.content.contains('## Export Analysis:') &&
            message.content.contains('**Total Rows:**'));

    return Wrap(
      spacing: 12,
      children: [
        if (message.status == AiMessageStatus.interrupted && onContinue != null)
          _buildTextActionButton(
            icon: LucideIcons.play,
            label: l10n.aiPanelContinue,
            onTap: onContinue!,
            color: context.themeColors.accentBlue,
          ),
        if (isAnalyzeExport && onCreateExportTask != null)
          _buildTextActionButton(
            icon: LucideIcons.fileDown,
            label: l10n.aiExportButtonCreate,
            onTap: () {
              final table = message.toolArguments?['table'] as String? ?? '';
              final whereClause =
                  message.toolArguments?['where_clause'] as String?;
              if (table.isNotEmpty) {
                onCreateExportTask!(table, whereClause);
              }
            },
            color: context.themeColors.accentPurple,
          ),
        if (onRegenerate != null)
          _buildTextActionButton(
            icon: LucideIcons.refreshCw,
            label: l10n.messageActionRegenerate,
            onTap: onRegenerate!,
            color: context.themeColors.textMuted,
          ),
        _CopyFeedbackButton(
          text: message.content,
          color: context.themeColors.textMuted,
        ),
      ],
    );
  }

  Widget _buildTextActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space1,
          vertical: AppDesignSystem.space0_5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color ?? Colors.grey),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color ?? Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerBadge(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1,
        ),
        decoration: BoxDecoration(
          color: context.themeColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.triangleAlert,
              size: 12,
              color: context.themeColors.error,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.aiPanelDangerousOperationBadge,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _detectLanguage(String code) {
    final trimmed = code.trim().toLowerCase();
    if (trimmed.startsWith('select ') ||
        trimmed.startsWith('insert ') ||
        trimmed.startsWith('update ') ||
        trimmed.startsWith('delete ') ||
        trimmed.startsWith('create ') ||
        trimmed.startsWith('alter ') ||
        trimmed.startsWith('drop ') ||
        trimmed.startsWith('with ')) {
      return 'sql';
    }
    // MongoDB shell 查询 — fallback to javascript since mongodb language is not available
    if (trimmed.startsWith('db.')) {
      return 'javascript';
    }
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return 'json';
    }
    if (trimmed.startsWith('function ') ||
        trimmed.startsWith('const ') ||
        trimmed.startsWith('let ') ||
        trimmed.startsWith('var ') ||
        trimmed.contains('=>')) {
      return 'javascript';
    }
    if (trimmed.startsWith('def ') ||
        trimmed.startsWith('class ') ||
        trimmed.startsWith('import ') ||
        trimmed.startsWith('from ')) {
      return 'python';
    }
    return 'plaintext';
  }

  bool _isJsonContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    // 检查是否是纯 JSON（不以 Markdown 代码块标记开头）
    if (trimmed.startsWith('```')) return false;
    // 检查是否是 JSON 对象或数组
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  /// 解析性能报告数据
  PerformanceReport? _parsePerformanceReport(Map<String, dynamic> data) {
    try {
      // 解析执行计划步骤
      final stepsData = data['executionPlan']?['steps'] as List<dynamic>? ?? [];
      final steps = stepsData.map((stepData) {
        final map = stepData as Map<String, dynamic>;
        return PlanStep(
          id: map['id'] as int?,
          selectType: map['selectType'] as String?,
          table: map['table'] as String?,
          partition: map['partition'] as String?,
          scanType: map['scanType'] != null
              ? ScanType.values.firstWhere(
                  (t) => t.name == map['scanType'],
                  orElse: () => ScanType.unknown,
                )
              : null,
          possibleKeys: map['possibleKeys'] as String?,
          key: map['key'] as String?,
          keyLen: map['keyLen'] as String?,
          ref: map['ref'] as String?,
          estimatedRows: map['estimatedRows'] as int?,
          cost: map['cost'] as double?,
          time: map['time'] as double?,
          extra: map['extra'] as String?,
          operation: map['operation'] as String?,
        );
      }).toList();

      // 解析瓶颈
      final bottlenecksData = data['bottlenecks'] as List<dynamic>? ?? [];
      final bottlenecks = bottlenecksData.map((bData) {
        final map = bData as Map<String, dynamic>;
        return Bottleneck(
          type: BottleneckType.values.firstWhere(
            (t) => t.name == map['type'],
            orElse: () => BottleneckType.selectStar,
          ),
          description: map['description'] as String? ?? '',
          affectedTable: map['affectedTable'] as String?,
          affectedRows: map['affectedRows'] as int?,
          recommendation: map['recommendation'] as String?,
          severity: Severity.values.firstWhere(
            (s) => s.name == map['severity'],
            orElse: () => Severity.info,
          ),
        );
      }).toList();

      // 解析索引推荐
      final recommendationsData =
          data['indexRecommendations'] as List<dynamic>? ?? [];
      final recommendations = recommendationsData.map((rData) {
        final map = rData as Map<String, dynamic>;
        return IndexRecommendation(
          tableName: map['tableName'] as String? ?? '',
          indexName: map['indexName'] as String? ?? '',
          columns: (map['columns'] as List<dynamic>?)?.cast<String>() ?? [],
          reason: map['reason'] as String? ?? '',
          ddlStatement: map['ddlStatement'] as String?,
          estimatedImprovement: map['estimatedImprovement'] as double?,
          isUnique: map['isUnique'] as bool? ?? false,
        );
      }).toList();

      // 解析查询重写
      final rewritesData = data['queryRewrites'] as List<dynamic>? ?? [];
      final rewrites = rewritesData.map((rData) {
        final map = rData as Map<String, dynamic>;
        return QueryRewrite(
          originalQuery: map['originalQuery'] as String? ?? '',
          rewrittenQuery: map['rewrittenQuery'] as String? ?? '',
          reason: map['reason'] as String? ?? '',
          type: RewriteType.values.firstWhere(
            (t) => t.name == map['type'],
            orElse: () => RewriteType.other,
          ),
        );
      }).toList();

      final executionPlan = ExecutionPlan(
        databaseType:
            data['executionPlan']?['databaseType'] as String? ?? 'mysql',
        originalQuery: data['executionPlan']?['originalQuery'] as String? ?? '',
        steps: steps,
        rawData:
            data['executionPlan']?['rawData'] as Map<String, dynamic>? ?? {},
        analyzedAt:
            DateTime.tryParse(
              data['executionPlan']?['analyzedAt'] as String? ?? '',
            ) ??
            DateTime.now(),
      );

      return PerformanceReport(
        executionPlan: executionPlan,
        bottlenecks: bottlenecks,
        indexRecommendations: recommendations,
        queryRewrites: rewrites,
        summary: data['summary'] as String? ?? '',
        analysisDuration: Duration(
          milliseconds: data['analysisDurationMs'] as int? ?? 0,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// 从内容中移除 <sql>...</sql> 标签，避免重复显示
  String _removeSqlTags(String content) {
    return content
        .replaceAll(
          RegExp(r'<sql>\s*[\s\S]*?\s*</sql>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _formatJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (e) {
      return jsonStr;
    }
  }

  Widget _buildFormattedJson(BuildContext context, String jsonContent) {
    final formatted = _formatJson(jsonContent);
    return _buildCodeBlock(context, formatted, false);
  }

  Widget _buildCodeBlock(BuildContext context, String code, bool isDangerous) {
    final language = _detectLanguage(code);
    final languageLabel = language.toUpperCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.themeColors.codeBlockBg,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: isDangerous
              ? context.themeColors.error.withValues(alpha: 0.5)
              : context.themeColors.accentBlue.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: context.themeColors.accentBlue.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // SQL 卡片标题栏
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2_5,
                  vertical: AppDesignSystem.space1_5,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? context.themeColors.accentBlue.withValues(alpha: 0.15)
                      : context.themeColors.accentBlue.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppDesignSystem.radiusMd),
                    topRight: Radius.circular(AppDesignSystem.radiusMd),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.code,
                      size: 12,
                      color: context.themeColors.accentBlue,
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Text(
                      _formatLanguageLabel(languageLabel),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppDesignSystem.monoFontFamily,

                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                        color: context.themeColors.accentBlue,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      languageLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontFamily: AppDesignSystem.monoFontFamily,

                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    if (isDangerous) ...[
                      const SizedBox(width: AppDesignSystem.space2),
                      Icon(
                        LucideIcons.triangleAlert,
                        size: 10,
                        color: context.themeColors.error,
                      ),
                      const SizedBox(width: AppDesignSystem.space0_5),
                      Text(
                        AppLocalizations.of(context)!.aiPanelDangerous,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 8, 60, 10),
                child: HighlightView(
                  code,
                  language: language,
                  // atom-one 主题 → SqlEditorColors 同源映射（F-23）
                  theme: SqlEditorColors(
                    isDark: isDark,
                    cool: sqlCoolThemeOf(context),
                  ).toHighlightThemeMap(context.themeColors.codeBlockBg),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          // 右上角操作按钮
          Positioned(
            right: 6,
            top: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCodeActionButton(
                  icon: LucideIcons.copy,
                  tooltip: AppLocalizations.of(context)!.tooltipCopyCode,
                  onTap: () => Clipboard.setData(ClipboardData(text: code)),
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                if (!message.isUser) ...[
                  const SizedBox(width: AppDesignSystem.space1),
                  _buildCodeActionButton(
                    icon: LucideIcons.externalLink,
                    tooltip: AppLocalizations.of(
                      context,
                    )!.aiPanelOpenInNewQuery,
                    onTap: () => onOpenInNewQuery(code),
                    color: context.themeColors.accentBlue,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  _buildCodeActionButton(
                    icon: LucideIcons.play,
                    tooltip: AppLocalizations.of(context)!.tooltipExecuteCode,
                    onTap: () => onExecuteSql(code, isDangerous),
                    color: context.themeColors.success,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLanguageLabel(String languageLabel) {
    if (languageLabel == 'SQL') return 'SQL';
    if (languageLabel == 'MONGODB') return 'MONGODB';
    return languageLabel;
  }

  Widget _buildCodeActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildContentCard(BuildContext context) {
    if (message.type == AiMessageType.toolResult &&
        message.toolArguments != null) {
      // 合并显示工具调用和结果
      return _buildMergedToolCard(context);
    }
    if (message.type == AiMessageType.toolCall) {
      return ToolCardShell(
        toolName: message.toolName ?? '',
        child: ToolContentView(
          arguments: message.toolArguments != null
              ? const JsonEncoder.withIndent(
                  '  ',
                ).convert(message.toolArguments)
              : null,
          result: null,
          isCall: true,
        ),
      );
    }
    if (message.type == AiMessageType.toolResult) {
      // 工具组 - 多个工具合并显示
      if (message.toolResultData != null &&
          message.toolResultData!['isToolGroup'] == true) {
        return ToolCardShell(
          toolName: 'tool_group',
          child: ToolGroupView(
            toolCount: message.toolResultData!['toolCount'] as int? ?? 0,
            tools:
                (message.toolResultData!['tools'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
          ),
        );
      }
      // Schema Impact Analysis 特殊渲染
      if (message.toolName == 'analyze_schema_impact' &&
          message.toolResultData != null) {
        return ToolCardShell(
          toolName: message.toolName ?? '',
          child: SchemaImpactCard(data: message.toolResultData!),
        );
      }
      // Query Optimizer 特殊渲染
      if (message.toolName == 'analyze_query_performance' &&
          message.toolResultData != null) {
        try {
          final report = _parsePerformanceReport(message.toolResultData!);
          if (report != null) {
            return ToolCardShell(
              toolName: message.toolName ?? '',
              child: QueryPlanVisualizer(report: report),
            );
          }
        } catch (e) {
          // 解析失败，回退到默认显示
        }
      }
      return ToolCardShell(
        toolName: message.toolName ?? '',
        child: ToolContentView(
          arguments: null,
          result: message.content,
          isCall: false,
        ),
      );
    }
    final hasReasoning =
        message.reasoningContent != null &&
        message.reasoningContent!.isNotEmpty;
    final hasContent = message.content.isNotEmpty && !hasReasoning;
    final hasExtractedCommands =
        message.extractedCommands != null &&
        message.extractedCommands!.isNotEmpty;
    final hasCode = message.code != null && message.code!.isNotEmpty;
    final isJsonContent =
        !hasExtractedCommands && !hasCode && _isJsonContent(message.content);

    final isError =
        message.status == AiMessageStatus.failed ||
        message.status == AiMessageStatus.cancelled ||
        message.status == AiMessageStatus.interrupted;

    final isOverlay = context.watch<AppProvider>().isAiPanelOverlay;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getBubbleColor(context, isOverlay, isError),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppDesignSystem.radiusLg),
          topRight: const Radius.circular(AppDesignSystem.radiusLg),
          bottomLeft: Radius.circular(message.isUser ? 12 : 4),
          bottomRight: Radius.circular(message.isUser ? 4 : 12),
        ),
        border: _getBubbleBorder(context, isOverlay, isError),
        boxShadow: isOverlay
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isError && !message.isUser) ...[
            Row(
              children: [
                Icon(
                  message.status == AiMessageStatus.interrupted
                      ? LucideIcons.circlePause
                      : LucideIcons.circleAlert,
                  size: 14,
                  color: message.status == AiMessageStatus.interrupted
                      ? context.themeColors.warning
                      : context.themeColors.error,
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Text(
                  message.status == AiMessageStatus.cancelled
                      ? AppLocalizations.of(context)!.messageStatusCancelled
                      : message.status == AiMessageStatus.interrupted
                      ? AppLocalizations.of(context)!.messageStatusCancelled
                      : AppLocalizations.of(context)!.messageStatusError,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: message.status == AiMessageStatus.interrupted
                        ? context.themeColors.warning
                        : context.themeColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space2),
          ],
          if (hasReasoning) ...[
            ThinkingCard(
              key: ValueKey('thinking_${message.id}'),
              thinkingProcess: message.reasoningContent!,
              thinkingResult: message.content.isNotEmpty
                  ? message.content
                  : null,
              isStreaming: message.isLoading,
              initiallyExpanded: true,
              typewriterConfig: TypewriterConfig(
                charDelay: message.isLoading
                    ? const Duration(milliseconds: 25)
                    : Duration.zero,
                enabled: message.isLoading,
              ),
            ),
          ],
          // C23 envelope 统一渲染：显式类型声明走 AiResultRenderer 分发
          //（sql/markdown/json/diff）。既有管线优先——extractedCommands
          //（SQL 提取 + 执行按钮）与整段 JSON 格式化分支处理得更好，
          // envelope 只在其未覆盖时接管（diff / 无提取的纯 SQL 等）。
          if (hasContent &&
              !hasExtractedCommands &&
              !isJsonContent &&
              AiSkillEnvelope.typeFromName(message.envelopeType) != null) ...[
            AiResultRenderer(
              content: message.content,
              envelopeType: AiSkillEnvelope.typeFromName(message.envelopeType),
            ),
          ] else if (hasContent && !isJsonContent) ...[
            _buildMarkdownContent(
              context,
              isError,
              hasExtractedCommands
                  ? _removeSqlTags(message.content)
                  : message.content,
            ),
          ],
          if (isJsonContent) ...[
            const SizedBox(height: AppDesignSystem.space2),
            _buildFormattedJson(context, message.content),
          ],
          if (hasExtractedCommands) ...[
            if (hasContent && !isJsonContent)
              const SizedBox(height: AppDesignSystem.space3),
            ...message.extractedCommands!.asMap().entries.map((entry) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key < message.extractedCommands!.length - 1
                      ? 8
                      : 0,
                ),
                child: _buildCodeBlock(
                  context,
                  entry.value,
                  message.isDangerous ?? false,
                ),
              );
            }),
          ] else if (hasCode) ...[
            if (hasContent && !isJsonContent)
              const SizedBox(height: AppDesignSystem.space3),
            _buildCodeBlock(
              context,
              message.code!,
              message.isDangerous ?? false,
            ),
          ],
          if (!message.isUser && message.totalTokens > 0) ...[
            const SizedBox(height: AppDesignSystem.space2),
            _buildTokenUsage(context),
          ],
        ],
      ),
    );
  }

  Color _getBubbleColor(BuildContext context, bool isOverlay, bool isError) {
    if (message.isUser) {
      return isOverlay
          ? Colors.transparent
          : context.themeColors.accentBlue.withValues(alpha: 0.8);
    }
    if (isError) {
      return context.themeColors.error.withValues(alpha: 0.05);
    }
    return isOverlay
        ? Colors.transparent
        : context.themeColors.bgAiMessage.withValues(alpha: 0.5);
  }

  Border _getBubbleBorder(BuildContext context, bool isOverlay, bool isError) {
    if (message.isDangerous == true) {
      return Border.all(color: context.themeColors.error, width: 1);
    }
    if (isError) {
      return Border.all(
        color: context.themeColors.error.withValues(alpha: 0.3),
        width: 1,
      );
    }
    return Border.all(
      color: isOverlay
          ? context.themeColors.borderSubtle
          : context.themeColors.borderLight,
    );
  }

  Widget _buildMergedToolCard(BuildContext context) {
    // Schema Impact Analysis 特殊渲染
    if (message.toolName == 'analyze_schema_impact' &&
        message.toolResultData != null) {
      return ToolCardShell(
        toolName: message.toolName ?? '',
        child: SchemaImpactCard(data: message.toolResultData!),
      );
    }
    // Query Optimizer 特殊渲染
    if (message.toolName == 'analyze_query_performance' &&
        message.toolResultData != null) {
      try {
        final report = _parsePerformanceReport(message.toolResultData!);
        if (report != null) {
          return ToolCardShell(
            toolName: message.toolName ?? '',
            child: QueryPlanVisualizer(report: report),
          );
        }
      } catch (e) {
        // 解析失败，回退到默认显示
      }
    }

    final arguments = message.toolArguments != null
        ? const JsonEncoder.withIndent('  ').convert(message.toolArguments)
        : null;

    return ToolCardShell(
      toolName: message.toolName ?? '',
      child: ToolContentView(
        arguments: arguments,
        result: message.content,
        isCall: false,
      ),
    );
  }

  Widget _buildMarkdownContent(
    BuildContext context,
    bool isError, [
    String? content,
  ]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = message.isUser
        ? Colors.white
        : isError
        ? context.themeColors.error
        : context.themeColors.textPrimary;

    return MarkdownBody(
      data: content ?? message.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 13, color: textColor, height: 1.5),
        h1: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textColor,
          height: 1.4,
        ),
        h2: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: textColor,
          height: 1.4,
        ),
        h3: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: textColor,
          height: 1.4,
        ),
        strong: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        em: TextStyle(fontStyle: FontStyle.italic, color: textColor),
        code: TextStyle(
          fontSize: 12,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          color: textColor,
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
        codeblockDecoration: BoxDecoration(
          color: context.themeColors.codeBlockBg,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        ),
        blockquote: TextStyle(
          fontSize: 13,
          color: textColor.withValues(alpha: 0.8),
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: context.themeColors.accentPurple.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
        listBullet: TextStyle(fontSize: 13, color: textColor),
        tableHead: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        tableBody: TextStyle(color: textColor),
        tableBorder: TableBorder.all(
          color: context.themeColors.borderLight,
          width: 1,
        ),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1,
        ),
      ),
    );
  }
}

class _CollapsibleThinking extends StatefulWidget {
  final String reasoningContent;

  const _CollapsibleThinking({required this.reasoningContent});

  @override
  State<_CollapsibleThinking> createState() => _CollapsibleThinkingState();
}

class _CollapsibleThinkingState extends State<_CollapsibleThinking> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final isOverlay = context.watch<AppProvider>().isAiPanelOverlay;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOverlay
            ? Colors.transparent
            : context.themeColors.bgTertiary.withValues(
                alpha: _expanded ? 1.0 : 0.5,
              ),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderSubtle),
      ),
      child: _expanded
          ? _buildExpandedContent(context)
          : _buildCollapsedContent(context),
    );
  }

  Widget _buildCollapsedContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Icon(LucideIcons.brain, size: 12, color: context.themeColors.textMuted),
        const SizedBox(width: AppDesignSystem.space1_5),
        Text(
          l10n.aiPanelThinkingProcess,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: context.themeColors.textMuted,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _toggle,
          icon: Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: context.themeColors.textMuted,
          ),
          tooltip: l10n.aiPanelExpandThinking,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          splashRadius: 14,
        ),
      ],
    );
  }

  Widget _buildExpandedContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.brain,
              size: 12,
              color: context.themeColors.accentPurple,
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            Text(
              l10n.aiPanelThinkingProcess,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.themeColors.accentPurple,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _toggle,
              icon: Icon(
                LucideIcons.chevronUp,
                size: 16,
                color: context.themeColors.textMuted,
              ),
              tooltip: l10n.aiPanelCollapseThinking,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              splashRadius: 14,
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        SelectableText(
          widget.reasoningContent,
          style: TextStyle(
            fontSize: 11,
            color: context.themeColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _TokenChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isTotal;

  const _TokenChip({
    required this.icon,
    required this.label,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: isTotal
            ? context.themeColors.accentPurple.withValues(alpha: 0.1)
            : context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: isTotal
            ? Border.all(
                color: context.themeColors.accentPurple.withValues(alpha: 0.3),
                width: 0.5,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: isTotal
                ? context.themeColors.accentPurple
                : context.themeColors.textMuted,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isTotal
                  ? context.themeColors.accentPurple
                  : context.themeColors.textMuted,
              fontWeight: isTotal ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyFeedbackButton extends StatefulWidget {
  final String text;
  final Color color;

  const _CopyFeedbackButton({required this.text, required this.color});

  @override
  State<_CopyFeedbackButton> createState() => _CopyFeedbackButtonState();
}

class _CopyFeedbackButtonState extends State<_CopyFeedbackButton> {
  bool _copied = false;

  void _handleCopy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_copied) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.check, size: 12, color: context.themeColors.success),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            AppLocalizations.of(context)!.messageCopied,
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: _handleCopy,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space1,
          vertical: AppDesignSystem.space0_5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.copy, size: 12, color: widget.color),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              AppLocalizations.of(context)!.tooltipCopyCode,
              style: TextStyle(fontSize: 11, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}
