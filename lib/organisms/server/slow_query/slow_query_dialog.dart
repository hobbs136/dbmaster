//! Slow-query stats dialog (reports-M1 / #29): Top N by digest + detail drill
//! down, fed by `GET /api/query-stats{,/summary}`. Scope banner states the
//! capture scope (only queries executed through dbmaster/server above the
//! instance threshold — NOT a whole-database slow log).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/drift_models.dart';
import '../../../models/query_stats_models.dart';
import '../../../services/query_stats_api_service.dart';
import '../../../services/server_connections_api_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/rfc3339.dart';

/// Opens the slow-query stats dialog. Works in both remote and embedded
/// modes (embedded is the primary scenario: every desktop query goes through
/// the embedded server).
Future<void> showSlowQueryDialog(
  BuildContext context, {
  QueryStatsApiService? api,
  ServerConnectionsApiService? connectionsApi,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.75,
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: _SlowQueryDialog(
          api: api ?? QueryStatsApiService(),
          connectionsApi: connectionsApi ?? ServerConnectionsApiService(),
        ),
      ),
    ),
  );
}

class _SlowQueryDialog extends StatefulWidget {
  final QueryStatsApiService api;
  final ServerConnectionsApiService connectionsApi;

  const _SlowQueryDialog({required this.api, required this.connectionsApi});

  @override
  State<_SlowQueryDialog> createState() => _SlowQueryDialogState();
}

class _SlowQueryDialogState extends State<_SlowQueryDialog> {
  String _window = QueryStatsWindow.day;
  String _sort = QueryStatsSort.totalMs;
  String? _connId;
  List<DriftSourceConnection>? _connections;
  late Future<QueryStatsSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.fetchSummary(
      window: _window,
      connId: _connId,
      sort: _sort,
      limit: 50,
    )..ignore();
    // 连接下拉（失败降级为只有“全部连接”）。
    widget.connectionsApi.listConnections().then((list) {
      if (mounted) setState(() => _connections = list);
    }).catchError((_) {});
  }

  void _reload() {
    final future = widget.api.fetchSummary(
      window: _window,
      connId: _connId,
      sort: _sort,
      limit: 50,
    );
    // 关闭对话框时在途请求的拒绝无监听者 → unhandled zone error（灰屏事故
    // 同类加固，对齐 drift_run_history_dialog）。
    future.ignore();
    setState(() { _future = future; });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Column(
      children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              const Icon(LucideIcons.gauge, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.slowQueryDialogTitle,
                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
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
        // ── Scope banner（口径边界：不是整库慢查日志）──
        FutureBuilder<QueryStatsSummary>(
          future: _future,
          builder: (context, snap) {
            final threshold = snap.data?.meta.thresholdMs ?? 1000;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.bgTertiary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.info, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.slowQueryScopeBanner(threshold),
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // ── Filter row ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              _windowSelector(l10n),
              const SizedBox(width: 8),
              _sortSelector(l10n),
              const SizedBox(width: 8),
              Expanded(child: _connSelector(l10n)),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                onPressed: _reload,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Top N list ──
        Expanded(
          child: FutureBuilder<QueryStatsSummary>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                widget.api.logError('fetchSummary', snap.error!);
                return _ErrorView(onRetry: _reload, l10n: l10n);
              }
              final items = snap.data?.items ?? const [];
              if (items.isEmpty) {
                return _EmptyView(l10n: l10n);
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _DigestCard(
                    item: items[i],
                    onTap: () => showSlowQueryDetailDialog(
                      context,
                      api: widget.api,
                      item: items[i],
                      window: _window,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _windowSelector(AppLocalizations l10n) {
    return DropdownButton<String>(
      value: _window,
      underline: const SizedBox.shrink(),
      isDense: true,
      items: [
        DropdownMenuItem(
          value: QueryStatsWindow.oneHour,
          child: Text(l10n.slowQueryWindow1h,
              style: const TextStyle(fontSize: 12)),
        ),
        DropdownMenuItem(
          value: QueryStatsWindow.day,
          child: Text(l10n.slowQueryWindow24h,
              style: const TextStyle(fontSize: 12)),
        ),
        DropdownMenuItem(
          value: QueryStatsWindow.week,
          child: Text(l10n.slowQueryWindow7d,
              style: const TextStyle(fontSize: 12)),
        ),
      ],
      onChanged: (v) {
        if (v != null && v != _window) {
          setState(() => _window = v);
          _reload();
        }
      },
    );
  }

  Widget _sortSelector(AppLocalizations l10n) {
    return DropdownButton<String>(
      value: _sort,
      underline: const SizedBox.shrink(),
      isDense: true,
      items: [
        DropdownMenuItem(
          value: QueryStatsSort.totalMs,
          child: Text(l10n.slowQuerySortTotalMs,
              style: const TextStyle(fontSize: 12)),
        ),
        DropdownMenuItem(
          value: QueryStatsSort.count,
          child: Text(l10n.slowQuerySortCount,
              style: const TextStyle(fontSize: 12)),
        ),
        DropdownMenuItem(
          value: QueryStatsSort.avgMs,
          child: Text(l10n.slowQuerySortAvgMs,
              style: const TextStyle(fontSize: 12)),
        ),
        DropdownMenuItem(
          value: QueryStatsSort.maxMs,
          child: Text(l10n.slowQuerySortMaxMs,
              style: const TextStyle(fontSize: 12)),
        ),
      ],
      onChanged: (v) {
        if (v != null && v != _sort) {
          setState(() => _sort = v);
          _reload();
        }
      },
    );
  }

  Widget _connSelector(AppLocalizations l10n) {
    final conns = _connections;
    final current = _connId;
    final valid = current == null ||
        (conns?.any((c) => c.id == current) ?? false);
    return DropdownButton<String?>(
      value: valid ? current : null,
      underline: const SizedBox.shrink(),
      isDense: true,
      isExpanded: true,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(l10n.slowQueryAllConnections,
              style: const TextStyle(fontSize: 12)),
        ),
        if (conns != null)
          ...conns.map(
            (c) => DropdownMenuItem<String?>(
              value: c.id,
              child: Text(
                '${c.name} (${c.dbType})',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      onChanged: (v) {
        if (v != _connId) {
          setState(() => _connId = v);
          _reload();
        }
      },
    );
  }
}

String _fmtMs(num ms) =>
    ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';

class _DigestCard extends StatelessWidget {
  final QueryStatsDigestSummary item;
  final VoidCallback onTap;

  const _DigestCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.digest,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.slowQueryDigestStats(
                  item.count,
                  _fmtMs(item.totalMs),
                  _fmtMs(item.avgMs),
                  _fmtMs(item.maxMs),
                ),
                style: AppTextStyles.caption.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                '${item.dbKind} · ${l10n.slowQueryLastSeen(formatRfc3339Local(item.lastSeen))}',
                style: AppTextStyles.caption.copyWith(fontSize: 11, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.searchX, size: 32),
          const SizedBox(height: 8),
          Text(l10n.slowQueryEmptyTitle),
          const SizedBox(height: 4),
          Text(
            l10n.slowQueryEmptyBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final AppLocalizations l10n;
  const _ErrorView({required this.onRetry, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.cloudOff, size: 32),
          const SizedBox(height: 8),
          Text(l10n.slowQueryLoadFailed),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.slowQueryRetry)),
        ],
      ),
    );
  }
}

// ── Detail drill-down ──

Future<void> showSlowQueryDetailDialog(
  BuildContext context, {
  required QueryStatsApiService api,
  required QueryStatsDigestSummary item,
  required String window,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.8,
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: _SlowQueryDetailDialog(api: api, item: item, window: window),
      ),
    ),
  );
}

class _SlowQueryDetailDialog extends StatefulWidget {
  final QueryStatsApiService api;
  final QueryStatsDigestSummary item;
  final String window;

  const _SlowQueryDetailDialog({
    required this.api,
    required this.item,
    required this.window,
  });

  @override
  State<_SlowQueryDetailDialog> createState() => _SlowQueryDetailDialogState();
}

class _SlowQueryDetailDialogState extends State<_SlowQueryDetailDialog> {
  int _limit = 50;
  late Future<QueryStatsDetailPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch()..ignore();
  }

  Future<QueryStatsDetailPage> _fetch() => widget.api.fetchDetail(
        window: widget.window,
        connId: widget.item.connId,
        digest: widget.item.digest,
        limit: _limit,
      );

  void _reload() {
    final future = _fetch();
    future.ignore();
    setState(() { _future = future; });
  }

  void _loadMore() {
    _limit += 50;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.item.digest,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
          child: FutureBuilder<QueryStatsDetailPage>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                widget.api.logError('fetchDetail', snap.error!);
                return _ErrorView(onRetry: _reload, l10n: l10n);
              }
              final page = snap.data;
              final items = page?.items ?? const [];
              final total = page?.total ?? 0;
              if (items.isEmpty) {
                return _EmptyView(l10n: l10n);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length + (items.length < total ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  if (i >= items.length) {
                    return Center(
                      child: OutlinedButton(
                        onPressed: _loadMore,
                        child: Text(l10n.slowQueryLoadMore(
                            items.length, total)),
                      ),
                    );
                  }
                  final row = items[i];
                  return _SampleCard(row: row, colors: colors);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SampleCard extends StatelessWidget {
  final QueryStatsRecord row;
  final ThemeColors colors;

  const _SampleCard({required this.row, required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final statusColor = switch (row.status) {
      'error' => colors.error,
      'cancelled' => colors.warning,
      _ => colors.success,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _fmtMs(row.elapsedMs),
                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    switch (row.status) {
                      'error' => l10n.slowQueryStatusError,
                      'cancelled' => l10n.slowQueryStatusCancelled,
                      _ => l10n.slowQueryStatusOk,
                    },
                    style: TextStyle(fontSize: 10, color: statusColor),
                  ),
                ),
                const Spacer(),
                Text(
                  '${row.entry} · ${formatRfc3339Local(row.capturedAt, withSeconds: true)}',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            if (row.database != null) ...[
              const SizedBox(height: 4),
              Text(
                '${l10n.slowQueryDatabaseLabel}: ${row.database}',
                style: AppTextStyles.caption.copyWith(fontSize: 11),
              ),
            ],
            const SizedBox(height: 6),
            if (row.sqlText != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.bgTertiary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  row.sqlText!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: row.sqlText!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.slowQueryCopied)),
                    );
                  },
                  icon: const Icon(LucideIcons.copy, size: 14),
                  label: Text(l10n.slowQueryCopySql),
                ),
              ),
            ] else
              Text(
                l10n.slowQueryNoPlaintext,
                style: AppTextStyles.caption.copyWith(fontSize: 11, color: colors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
