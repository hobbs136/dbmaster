//! 报告中心 dialog（#29 reports 管道 M2）：reports 表的通用 hub——按类型
//! 分组的报告列表 + 「生成本期周报」按钮 + 详情（`slow_query_weekly` typed
//! 渲染 / 未知类型 JSON 回退）。embedded 与远程均可用（生成按钮是 mutation：
//! 远程 Gated 态 403，embedded 合成 Licensed 不受影响）。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/report_models.dart';
import '../../../providers/app_provider.dart';
import '../../../services/reports_api_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/rfc3339.dart';

/// 打开报告中心。
Future<void> showReportsDialog(
  BuildContext context, {
  ReportsApiService? api,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.72,
        height: MediaQuery.of(ctx).size.height * 0.72,
        child: _ReportsDialog(api: api ?? ReportsApiService()),
      ),
    ),
  );
}

class _ReportsDialog extends StatefulWidget {
  final ReportsApiService api;

  const _ReportsDialog({required this.api});

  @override
  State<_ReportsDialog> createState() => _ReportsDialogState();
}

class _ReportsDialogState extends State<_ReportsDialog> {
  int _limit = 50;
  late Future<ReportsPage> _future;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listReports(limit: _limit)..ignore();
  }

  void _reload() {
    final future = widget.api.listReports(limit: _limit);
    // 关闭对话框时在途请求的拒绝无监听者 → unhandled zone error（灰屏事故
    // 同类加固，对齐 drift_run_history_dialog）。
    future.ignore();
    setState(() { _future = future; });
  }

  void _loadMore() {
    _limit += 50;
    _reload();
  }

  Future<void> _generate(AppLocalizations l10n) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final result = await widget.api.generateWeekly();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.created
              ? l10n.reportsGeneratedToast
              : l10n.reportsExistingToast),
        ),
      );
      _reload();
    } on ReportsApiEntitlementException catch (e) {
      if (mounted) _showError(l10n, e);
    } on ReportsApiException catch (e) {
      if (mounted) _showError(l10n, e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showError(AppLocalizations l10n, Object e) {
    widget.api.logError('generateWeekly', e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.reportsLoadFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        // ── Header（标题 + 生成按钮 + 关闭）──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              const Icon(LucideIcons.sparkles, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.reportsDialogTitle,
                  style: AppTextStyles.h4,
                ),
              ),
              TextButton.icon(
                onPressed: _generating ? null : () => _generate(l10n),
                icon: _generating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.plus, size: 16),
                label: Text(l10n.reportsGenerateButton),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── 列表 ──
        Expanded(
          child: FutureBuilder<ReportsPage>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                widget.api.logError('listReports', snap.error!);
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.cloudOff, size: 32),
                      const SizedBox(height: 8),
                      Text(l10n.reportsLoadFailed),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _reload,
                        child: Text(l10n.reportsRetry),
                      ),
                    ],
                  ),
                );
              }
              final page = snap.data;
              final items = page?.items ?? const [];
              final total = page?.total ?? 0;
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.searchX, size: 32),
                      const SizedBox(height: 8),
                      Text(l10n.reportsEmptyTitle),
                      const SizedBox(height: 4),
                      Text(
                        l10n.reportsEmptyBody,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length + (items.length < total ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i >= items.length) {
                      return Center(
                        child: OutlinedButton(
                          onPressed: _loadMore,
                          child:
                              Text(l10n.reportsLoadMore(items.length, total)),
                        ),
                      );
                    }
                    return _ReportCard(report: items[i]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Report report;

  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => showReportDetailDialog(context, report: report),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: colors.accentSubtle,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      report.reportType,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatRfc3339Local(report.generatedAt, withSeconds: true),
                    style: AppTextStyles.caption
                        .copyWith(fontSize: 11, color: colors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(report.title, style: AppTextStyles.body),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 详情 ──

Future<void> showReportDetailDialog(
  BuildContext context, {
  required Report report,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.8,
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: _ReportDetailDialog(report: report),
      ),
    ),
  );
}

class _ReportDetailDialog extends StatelessWidget {
  final Report report;

  const _ReportDetailDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 行的 reportType 是 hub 路由判据；content 解析成功且版本匹配才 typed，
    // 否则（未知类型/形状不符/未知版本）走 JSON 回退。
    final typed = report.reportType == SlowQueryWeeklyReport.reportType &&
            report.contentDecoded != null
        ? SlowQueryWeeklyReport.fromDecoded(report.contentDecoded!)
        : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  report.title,
                  style: AppTextStyles.h4,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: typed != null
              ? _WeeklyReportView(report: typed)
              : _RawContentView(report: report, l10n: l10n),
        ),
      ],
    );
  }
}

/// `slow_query_weekly` typed 渲染（content_version 1）。
class _WeeklyReportView extends StatelessWidget {
  final SlowQueryWeeklyReport report;

  const _WeeklyReportView({required this.report});

  String _fmtMs(num ms) =>
      ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final s = report.summary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── AI 分析（#29 M3 / ADR-0007：客户端侧，用户自配 key）──
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () =>
                context.read<AppProvider>().analyzeWeeklyReportWithAi(report),
            icon: const Icon(LucideIcons.sparkles, size: 14),
            label: Text(l10n.reportsAnalyzeWithAi),
          ),
        ),
        // ── 窗口行 ──
        Text(
          '${l10n.reportsWindowLabel}: '
          '${formatRfc3339Local(report.windowFrom)} → '
          '${formatRfc3339Local(report.windowTo)}',
          style: AppTextStyles.caption.copyWith(color: colors.textSecondary),
        ),
        if (report.windowTruncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(LucideIcons.info, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.reportsTruncatedHint,
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        // ── 汇总卡 ──
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _StatChip(
                label: l10n.reportsSamplesLabel, value: '${s.totalSamples}'),
            _StatChip(
                label: l10n.reportsDistinctLabel, value: '${s.distinctDigests}'),
            _StatChip(label: l10n.reportsTotalTimeLabel, value: _fmtMs(s.totalMs)),
            _StatChip(label: l10n.reportsErrorsLabel, value: '${s.errorCount}'),
            if (s.weekOverWeekPct != null)
              _StatChip(
                label: l10n.reportsWowLabel,
                value:
                    '${s.weekOverWeekPct! >= 0 ? "+" : ""}${s.weekOverWeekPct!.toStringAsFixed(0)}%',
                highlight: s.weekOverWeekPct! > 0 ? colors.warning : null,
              ),
          ],
        ),
        const SizedBox(height: 16),
        // ── Top 查询 ──
        if (report.top.isNotEmpty) ...[
          Text(l10n.reportsTopSection, style: AppTextStyles.h4),
          const SizedBox(height: 8),
          for (final t in report.top)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.digest,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    // 复用 M1 的 digest 统计行键（次数/总/均/峰）。
                    AppLocalizations.of(context)!.slowQueryDigestStats(
                      t.count,
                      _fmtMs(t.totalMs),
                      _fmtMs(t.avgMs),
                      _fmtMs(t.maxMs),
                    ),
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        // ── 按天 ──
        if (report.byDay.isNotEmpty) ...[
          Text(l10n.reportsByDaySection, style: AppTextStyles.h4),
          const SizedBox(height: 8),
          for (final d in report.byDay)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(d.date,
                        style: AppTextStyles.caption.copyWith(fontSize: 11)),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: report.byDay.isEmpty ||
                              report.byDay
                                  .map((x) => x.totalMs)
                                  .reduce((a, b) => a > b ? a : b) ==
                          0
                          ? 0
                          : d.totalMs /
                              report.byDay
                                  .map((x) => x.totalMs)
                                  .reduce((a, b) => a > b ? a : b),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${d.count}× · ${_fmtMs(d.totalMs)}',
                      style: AppTextStyles.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        // ── 按连接 ──
        if (report.byConnection.isNotEmpty) ...[
          Text(l10n.reportsByConnectionSection, style: AppTextStyles.h4),
          const SizedBox(height: 8),
          for (final c in report.byConnection)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${c.dbKind} · ${c.connId} — ${c.count}× · ${_fmtMs(c.totalMs)}',
                style: AppTextStyles.caption.copyWith(fontSize: 11),
              ),
            ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? highlight;

  const _StatChip({required this.label, required this.value, this.highlight});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(fontSize: 10)),
          Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight,
            ),
          ),
        ],
      ),
    );
  }
}

/// 未知 report_type 的回退：原始 JSON 美化展示。
class _RawContentView extends StatelessWidget {
  final Report report;
  final AppLocalizations l10n;

  const _RawContentView({required this.report, required this.l10n});

  @override
  Widget build(BuildContext context) {
    String pretty;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(
          report.content.isEmpty ? {} : jsonDecode(report.content));
    } catch (_) {
      pretty = report.content;
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.reportsUnknownType, style: AppTextStyles.caption),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              pretty,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
