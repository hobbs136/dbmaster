import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/query_optimizer/execution_plan.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';

/// 查询执行计划可视化组件
///
/// 展示 EXPLAIN 结果的结构化视图，包括：
/// - 执行计划步骤列表
/// - 性能瓶颈标记
/// - 索引推荐
/// - 查询重写建议
class QueryPlanVisualizer extends StatefulWidget {
  final PerformanceReport report;

  /// B2：索引推荐「应用此索引」回调。传入时，每张索引推荐卡片渲染一个按钮，
  /// 点击把 DDL 填进编辑器（由调用方实现，不在此自动执行）。
  /// null = 不显示按钮（如 AI 上下文/纯展示场景）。
  final void Function(String ddl)? onApplyDdl;

  const QueryPlanVisualizer({super.key, required this.report, this.onApplyDdl});

  @override
  State<QueryPlanVisualizer> createState() => _QueryPlanVisualizerState();
}

class _QueryPlanVisualizerState extends State<QueryPlanVisualizer> {
  bool _showRawPlan = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.report.executionPlan;
    final bottlenecks = widget.report.bottlenecks;
    final recommendations = widget.report.indexRecommendations;
    final hasCriticalIssues = widget.report.hasCriticalIssues;
    final highestSeverity = widget.report.highestSeverity;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: _getSeverityColor(highestSeverity).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部摘要
          _buildHeader(context, hasCriticalIssues, highestSeverity),

          // 执行计划步骤
          _buildPlanSteps(context, plan),

          // 瓶颈分析
          if (bottlenecks.isNotEmpty) ...[
            _buildBottlenecksSection(context, bottlenecks),
          ],

          // 索引推荐
          if (recommendations.isNotEmpty) ...[
            _buildRecommendationsSection(context, recommendations),
          ],

          // 查询重写建议
          if (widget.report.queryRewrites.isNotEmpty) ...[
            _buildRewriteSection(context, widget.report.queryRewrites),
          ],

          // 原始计划展开
          if (_showRawPlan) ...[_buildRawPlanSection(context, plan)],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool hasCriticalIssues,
    Severity severity,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getSeverityColor(severity).withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDesignSystem.radiusMd),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasCriticalIssues
                    ? LucideIcons.triangleAlert
                    : LucideIcons.gauge,
                size: 18,
                color: _getSeverityColor(severity),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  'Query Execution Plan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _getSeverityColor(severity).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  severity.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _getSeverityColor(severity),
                  ),
                ),
              ),
            ],
          ),
          if (widget.report.summary.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space1_5),
            Text(
              widget.report.summary,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: AppDesignSystem.space2),
          Wrap(
            spacing: 12,
            children: [
              _buildStatChip(
                context,
                icon: LucideIcons.rows3,
                label: '${widget.report.executionPlan.steps.length} steps',
              ),
              if (widget.report.executionPlan.totalRows > 0)
                _buildStatChip(
                  context,
                  icon: LucideIcons.hash,
                  label:
                      '${_formatNumber(widget.report.executionPlan.totalRows)} rows',
                ),
              if (widget.report.totalEstimatedImprovement != null)
                _buildStatChip(
                  context,
                  icon: LucideIcons.trendingUp,
                  label:
                      '${widget.report.totalEstimatedImprovement!.toStringAsFixed(0)}% faster',
                  color: context.themeColors.success,
                ),
              InkWell(
                onTap: () => setState(() => _showRawPlan = !_showRawPlan),
                child: _buildStatChip(
                  context,
                  icon: _showRawPlan
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  label: _showRawPlan ? 'Hide Raw Plan' : 'Show Raw Plan',
                  color: context.themeColors.accentPurple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanSteps(BuildContext context, ExecutionPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(
            'Execution Steps',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textSecondary,
            ),
          ),
        ),
        ...plan.steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          return _PlanStepCard(
            step: step,
            stepNumber: index + 1,
            isLast: index == plan.steps.length - 1,
          );
        }),
      ],
    );
  }

  Widget _buildBottlenecksSection(
    BuildContext context,
    List<Bottleneck> bottlenecks,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Row(
            children: [
              Icon(
                LucideIcons.triangleAlert,
                size: 14,
                color: context.themeColors.warning,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                'Performance Bottlenecks (${bottlenecks.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.warning,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          child: Column(
            children: bottlenecks.map((bottleneck) {
              return _BottleneckCard(bottleneck: bottleneck);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsSection(
    BuildContext context,
    List<IndexRecommendation> recommendations,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Row(
            children: [
              Icon(
                LucideIcons.lightbulb,
                size: 14,
                color: context.themeColors.success,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                'Index Recommendations (${recommendations.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.success,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          child: Column(
            children: recommendations.map((rec) {
              return _IndexRecommendationCard(
                recommendation: rec,
                onApplyDdl: widget.onApplyDdl,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRewriteSection(
    BuildContext context,
    List<QueryRewrite> rewrites,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Row(
            children: [
              Icon(
                LucideIcons.notebookPen,
                size: 14,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                'Query Rewrite Suggestions (${rewrites.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.accentPurple,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          child: Column(
            children: rewrites.map((rewrite) {
              return _QueryRewriteCard(rewrite: rewrite);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRawPlanSection(BuildContext context, ExecutionPlan plan) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Raw EXPLAIN Output',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          SelectableText(
            plan.toJson().toString(),
            style: TextStyle(
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: 11,
              color: context.themeColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? context.themeColors.textMuted),
        const SizedBox(width: AppDesignSystem.space1),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color ?? context.themeColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Color _getSeverityColor(Severity severity) {
    switch (severity) {
      case Severity.critical:
      case Severity.high:
        return context.themeColors.error;
      case Severity.medium:
        return context.themeColors.warning;
      case Severity.low:
        return context.themeColors.info;
      case Severity.info:
        return context.themeColors.success;
    }
  }

  String _formatNumber(int num) {
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(1)}M';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1)}K';
    }
    return num.toString();
  }
}

/// 单个执行步骤卡片
class _PlanStepCard extends StatelessWidget {
  final PlanStep step;
  final int stepNumber;
  final bool isLast;

  const _PlanStepCard({
    required this.step,
    required this.stepNumber,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final scanType = step.scanType;
    final isInefficient = scanType?.isInefficient ?? false;
    final isEfficient = scanType?.isEfficient ?? false;

    Color stepColor;
    if (isInefficient) {
      stepColor = context.themeColors.error;
    } else if (isEfficient) {
      stepColor = context.themeColors.success;
    } else {
      stepColor = context.themeColors.info;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤编号和连接线
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: stepColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: stepColor.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$stepNumber',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: stepColor,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 20,
                  color: context.themeColors.borderSubtle,
                ),
            ],
          ),
          const SizedBox(width: AppDesignSystem.space2_5),
          // 步骤详情
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(color: stepColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.table ?? 'Unknown Table',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.themeColors.textPrimary,
                          ),
                        ),
                      ),
                      if (scanType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDesignSystem.space1_5,
                            vertical: AppDesignSystem.space0_5,
                          ),
                          decoration: BoxDecoration(
                            color: stepColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppDesignSystem.radiusSm,
                            ),
                          ),
                          child: Text(
                            scanType.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: stepColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppDesignSystem.space1_5),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (step.estimatedRows != null)
                        _buildDetailChip(
                          context,
                          LucideIcons.rows3,
                          '${_formatNumber(step.estimatedRows!)} rows',
                        ),
                      if (step.key != null && step.key!.isNotEmpty)
                        _buildDetailChip(
                          context,
                          LucideIcons.keyRound,
                          'Index: ${step.key}',
                          color: context.themeColors.success,
                        ),
                      if (step.cost != null)
                        _buildDetailChip(
                          context,
                          LucideIcons.dollarSign,
                          'Cost: ${step.cost!.toStringAsFixed(1)}',
                        ),
                      if (step.time != null)
                        _buildDetailChip(
                          context,
                          LucideIcons.timer,
                          '${step.time!.toStringAsFixed(2)}ms',
                        ),
                    ],
                  ),
                  if (step.extra != null && step.extra!.isNotEmpty) ...[
                    const SizedBox(height: AppDesignSystem.space1_5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _getExtraColor(
                          context,
                          step.extra!,
                        ).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: Text(
                        step.extra!,
                        style: TextStyle(
                          fontSize: 11,
                          color: _getExtraColor(context, step.extra!),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(
    BuildContext context,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? context.themeColors.textMuted),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color ?? context.themeColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Color _getExtraColor(BuildContext context, String extra) {
    if (extra.contains('Using filesort') || extra.contains('Using temporary')) {
      return context.themeColors.warning;
    }
    return Theme.of(context).dividerColor;
  }

  String _formatNumber(int num) {
    if (num >= 1000000) {
      return '${(num / 1000000).toStringAsFixed(1)}M';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1)}K';
    }
    return num.toString();
  }
}

/// 瓶颈卡片
class _BottleneckCard extends StatelessWidget {
  final Bottleneck bottleneck;

  const _BottleneckCard({required this.bottleneck});

  @override
  Widget build(BuildContext context) {
    final color = _getSeverityColor(context, bottleneck.severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getBottleneckIcon(bottleneck.type), size: 12, color: color),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  bottleneck.description,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.themeColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1_5,
                  vertical: AppDesignSystem.space0_5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  bottleneck.severity.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (bottleneck.recommendation != null) ...[
            const SizedBox(height: AppDesignSystem.space1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.lightbulb,
                  size: 12,
                  color: context.themeColors.success,
                ),
                const SizedBox(width: AppDesignSystem.space1),
                Expanded(
                  child: Text(
                    bottleneck.recommendation!,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.success,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getSeverityColor(BuildContext context, Severity severity) {
    switch (severity) {
      case Severity.critical:
      case Severity.high:
        return context.themeColors.error;
      case Severity.medium:
        return context.themeColors.warning;
      case Severity.low:
        return context.themeColors.info;
      case Severity.info:
        return context.themeColors.success;
    }
  }

  IconData _getBottleneckIcon(BottleneckType type) {
    switch (type) {
      case BottleneckType.fullTableScan:
      case BottleneckType.largeTableScan:
        return LucideIcons.table2;
      case BottleneckType.missingIndex:
        return LucideIcons.keyRound;
      case BottleneckType.fileSort:
        return LucideIcons.arrowUpDown;
      case BottleneckType.temporaryTable:
        return LucideIcons.table;
      case BottleneckType.inefficientJoin:
        return LucideIcons.unlink;
      case BottleneckType.subqueryOptimization:
        return LucideIcons.network;
      case BottleneckType.selectStar:
        return LucideIcons.textSelect;
      case BottleneckType.offsetPagination:
        return LucideIcons.ellipsis;
      case BottleneckType.implicitConversion:
        return LucideIcons.replace;
    }
  }
}

/// 索引推荐卡片
class _IndexRecommendationCard extends StatelessWidget {
  final IndexRecommendation recommendation;

  /// B2：「应用此索引」回调。null = 不显示按钮（纯展示场景）。
  final void Function(String ddl)? onApplyDdl;

  const _IndexRecommendationCard({
    required this.recommendation,
    this.onApplyDdl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.themeColors.success.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.success.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.keyRound,
                size: 12,
                color: context.themeColors.success,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  recommendation.indexName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textPrimary,
                  ),
                ),
              ),
              if (recommendation.estimatedImprovement != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1_5,
                    vertical: AppDesignSystem.space0_5,
                  ),
                  decoration: BoxDecoration(
                    color: context.themeColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Text(
                    '+${recommendation.estimatedImprovement!.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            'Table: ${recommendation.tableName}',
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space0_5),
          Text(
            'Columns: ${recommendation.columns.join(', ')}',
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            recommendation.reason,
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textMuted,
              height: 1.3,
            ),
          ),
          if (recommendation.ddlStatement != null) ...[
            const SizedBox(height: AppDesignSystem.space1_5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: SelectableText(
                recommendation.ddlStatement!,
                style: TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 11,
                  color: context.themeColors.textPrimary,
                ),
              ),
            ),
            // B2：应用此索引——把 DDL 填进编辑器（不自动执行）。
            // 用户手动 Run 时走完整执行门（SafetyReviewService + SchemaAnalyzer）。
            // TODO(l10n): 组件整体未走 AppLocalizations（016 Phase 7 债），按钮文案暂硬编码。
            if (onApplyDdl != null)
              Padding(
                padding: const EdgeInsets.only(top: AppDesignSystem.space1_5),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onApplyDdl!(recommendation.ddlStatement!),
                    icon: Icon(
                      LucideIcons.play,
                      size: 14,
                      color: context.themeColors.success,
                    ),
                    label: Text(
                      'Apply This Index',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.themeColors.success,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 查询重写卡片
class _QueryRewriteCard extends StatelessWidget {
  final QueryRewrite rewrite;

  const _QueryRewriteCard({required this.rewrite});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.themeColors.accentPurple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.accentPurple.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.notebookPen,
                size: 12,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  rewrite.reason,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.themeColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          Text(
            'Suggested Query:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: context.themeColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SelectableText(
              rewrite.rewrittenQuery,
              style: TextStyle(
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 11,
                color: context.themeColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
