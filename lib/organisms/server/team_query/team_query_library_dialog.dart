//! Team Query Library dialog — browse/search/fork/delete the Server's shared
//! saved queries (`/api/queries`, #4 + #24). Distinct from the local
//! per-connection saved queries (`SavedQueriesSection`): team queries are
//! cross-connection and shared instance-wide by all members (D2-B: the
//! server does not scope them per workspace).
//!
//! Open (fork): loads the team query into a fresh unsaved tab bound to the
//! current connection (`isSaved=false` — user can edit + re-save as personal or
//! re-publish). Delete: author-only (D2-B server-side FORBIDDEN for others;
//! the button is hidden for non-authors).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/saved_query.dart';
import '../../../providers/app_provider.dart';
import '../../../services/saved_query_api_service.dart';
import '../../../services/server_connection.dart';
import '../../../theme/app_colors.dart';

/// Opens the Team Query Library dialog.
Future<void> showTeamQueryLibraryDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const Dialog(
      child: SizedBox(
        width: 820,
        height: 560,
        child: _TeamQueryLibraryDialog(),
      ),
    ),
  );
}

class _TeamQueryLibraryDialog extends StatefulWidget {
  const _TeamQueryLibraryDialog();
  @override
  State<_TeamQueryLibraryDialog> createState() =>
      _TeamQueryLibraryDialogState();
}

class _TeamQueryLibraryDialogState extends State<_TeamQueryLibraryDialog> {
  late final SavedQueryApiService _api;
  Future<List<SavedQuery>>? _future;
  final _searchController = TextEditingController();
  final _tagController = TextEditingController();
  final Set<String> _actionInFlight = {};

  @override
  void initState() {
    super.initState();
    _api = SavedQueryApiService();
    _refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _refresh() {
    // Not connected: build() short-circuits before FutureBuilder consumes
    // _future; skip the round-trip (would only reject + unhandled Future).
    if (!_api.isConnected) return;
    final q = _searchController.text.trim();
    final tag = _tagController.text.trim();
    final future = _api.list(
      q: q.isEmpty ? null : q,
      tag: tag.isEmpty ? null : tag,
    );
    // 关闭对话框时在途请求的拒绝无 FutureBuilder 监听者 → unhandled zone
    // error 打到 ErrorBoundary（2026-08-22 灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  Future<void> _forkQuery(SavedQuery q) async {
    final appProvider = context.read<AppProvider>();
    final connId = appProvider.currentQueryConnectionId;
    final dbName = appProvider.currentQueryDatabaseName;
    final l10n = AppLocalizations.of(context)!;
    if (connId == null || dbName == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.teamQueryForkNoConnection)));
      return;
    }
    // Fork into a fresh unsaved tab (no savedQueryId → isSaved=false). The user
    // can edit + re-save as personal or re-publish to the team library.
    await appProvider.tab.openQueryTab(
      connectionId: connId,
      databaseName: dbName,
      sql: q.sqlText,
      title: q.title,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.teamQueryForked(q.title))));
      Navigator.of(context).pop();
    }
  }

  Future<void> _deleteQuery(SavedQuery q) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.teamQueryDelete),
        content: Text(l10n.teamQueryDeleteConfirm(q.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.teamQueryCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.teamQueryDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInFlight.add(q.id));
    try {
      await _api.delete(q.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(q.id));
    }
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = _l10n;
    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Row(
            children: [
              Icon(
                LucideIcons.folderSymlink,
                color: colors.accentBlue,
                size: 18,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  l10n.teamQueryTitle,
                  style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw),
                tooltip: l10n.teamQueryRefresh,
                onPressed: _refresh,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: AppDesignSystem.space2),
          // Search + tag filters (server-side q / tag params).
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.teamQuerySearchHint,
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _refresh(),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _tagController,
                  decoration: InputDecoration(
                    hintText: l10n.teamQueryTagHint,
                    prefixIcon: const Icon(LucideIcons.tag, size: 18),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _refresh(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          // List.
          Expanded(
            child: !_api.isConnected
                ? _centeredMessage(l10n.teamQueryNotConnected, colors)
                : FutureBuilder<List<SavedQuery>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        final msg = snapshot.error is SavedQueryApiException
                            ? (snapshot.error as SavedQueryApiException).message
                            : snapshot.error.toString();
                        return _centeredMessage(msg, colors);
                      }
                      final queries = snapshot.data ?? const [];
                      if (queries.isEmpty) {
                        return _centeredMessage(l10n.teamQueryEmpty, colors);
                      }
                      return RefreshIndicator(
                        onRefresh: () async => _refresh(),
                        child: ListView.separated(
                          itemCount: queries.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: colors.borderSubtle,
                          ),
                          itemBuilder: (context, i) =>
                              _queryRow(queries[i], colors),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _queryRow(SavedQuery q, ThemeColors colors) {
    final inFlight = _actionInFlight.contains(q.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.fileText, size: 18, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: AppDesignSystem.fontWeightSemibold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _sqlPreview(q.sqlText),
                  style: AppTextStyles.code.copyWith(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (q.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: q.tags.map((t) => _tagChip(t, colors)).toList(),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  _l10n.teamQueryCreatedBy(q.createdBy),
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (inFlight)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: Icon(LucideIcons.play, size: 18, color: colors.success),
              tooltip: _l10n.teamQueryFork,
              onPressed: () => _forkQuery(q),
              visualDensity: VisualDensity.compact,
            ),
            // D2-B：删除收紧为仅作者（server 端 FORBIDDEN 兜底），非作者隐藏按钮。
            if (q.createdBy == ServerConnection().userProfile?.id)
              IconButton(
                icon: Icon(
                  LucideIcons.trash2,
                  size: 18,
                  color: colors.textSecondary,
                ),
                tooltip: _l10n.teamQueryDelete,
                onPressed: () => _deleteQuery(q),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ],
      ),
    );
  }

  Widget _tagChip(String tag, ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.accentBlue.withValues(alpha: 0.3)),
      ),
      child: Text(
        tag,
        style: TextStyle(fontSize: 10, color: colors.accentBlue),
      ),
    );
  }

  String _sqlPreview(String sql) {
    final lines = sql
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(2)
        .join(' ');
    if (lines.length > 120) return '${lines.substring(0, 120)}…';
    return lines;
  }

  /// Centered message in a ListView (RefreshIndicator requires scrollable).
  Widget _centeredMessage(String message, ThemeColors colors) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            child: Text(
              message,
              style: AppTextStyles.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
