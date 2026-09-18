//! Drift diff page: shows the structural diff between two Server-side
//! snapshots by reusing the existing Schema Diff widgets (SchemaDiffTree +
//! SchemaDiffDetail) over a converted [SchemaDiffReport].
//!
//! Why a custom container instead of `SchemaDiffPage`: the existing page is
//! built around live-DB captures (DatabaseService.getAdapter, useDatabase) and
//! computes diff from two snapshots captured on the fly. Server-side drift
//! snapshots have a different shape (BTreeMap-keyed Rust struct; see
//! `services/drift_schema_adapter.dart`) and no live DB to query. We fetch the
//! two snapshot rows lazily, adapt them to the desktop shape, run
//! `SchemaDiffService.compareSnapshots`, and feed the resulting report to the
//! existing widgets — preserving the look-and-feel the user already knows
//! without forking the Schema Diff model.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/rfc3339.dart';
import '../../../models/drift_models.dart';
import '../../../models/schema_diff_models.dart';
import '../../../services/drift_api_service.dart';
import '../../../services/drift_schema_adapter.dart';
import '../../../services/database_service.dart';
import '../../../services/schema_diff/schema_diff_service.dart';
import '../../../theme/app_colors.dart';
import '../../connection/schema_diff/schema_diff_ddl_preview.dart';
import '../../connection/schema_diff/schema_diff_detail.dart';
import '../../connection/schema_diff/schema_diff_tree.dart';

/// Shows the drift diff dialog for a given connection's snapshot list.
///
/// The user picks two snapshots (newer + older); we fetch both full rows and
/// render the structural diff using the existing Schema Diff widgets.
///
/// [initialNewerId]/[initialOlderId] (U09): preselect — and auto-compare — a
/// specific snapshot pair, used by the run-history "View Diff" to show exactly
/// what that run compared instead of "latest two". Ignored (fallback to the
/// latest two) when absent or no longer in the snapshot list (e.g. pruned).
Future<void> showDriftDiffDialog(
  BuildContext context, {
  required DriftApiService api,
  required DriftSourceConnection connection,
  String? initialNewerId,
  String? initialOlderId,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.85,
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: _DriftDiffPage(
          api: api,
          connection: connection,
          initialNewerId: initialNewerId,
          initialOlderId: initialOlderId,
        ),
      ),
    ),
  );
}

class _DriftDiffPage extends StatefulWidget {
  final DriftApiService api;
  final DriftSourceConnection connection;
  final String? initialNewerId;
  final String? initialOlderId;

  const _DriftDiffPage({
    required this.api,
    required this.connection,
    this.initialNewerId,
    this.initialOlderId,
  });

  @override
  State<_DriftDiffPage> createState() => _DriftDiffPageState();
}

class _DriftDiffPageState extends State<_DriftDiffPage> {
  List<DriftSnapshotMeta> _snapshots = const [];
  String? _newerId;
  String? _olderId;
  bool _loading = true;
  bool _comparing = false;
  String? _error;
  SchemaDiffReport? _report;
  String? _selectedObjectKey;
  DiffCategory _activeFilter = DiffCategory.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSnapshots());
  }

  Future<void> _loadSnapshots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.listSnapshots(widget.connection.id);
      if (mounted) {
        String? newer;
        String? older;
        var autoCompare = false;
        if (list.length >= 2) {
          // Default to the two most recent: list is DESC by captured_at.
          newer = list[0].id;
          older = list[1].id;
        }
        // U09: when opened from a run-history row, land on exactly the pair
        // that run compared. Only honoured when both sides still exist in the
        // list (snapshot retention may have pruned them) and differ.
        final wantedNewer = widget.initialNewerId;
        final wantedOlder = widget.initialOlderId;
        if (wantedNewer != null &&
            wantedOlder != null &&
            wantedNewer != wantedOlder &&
            list.any((s) => s.id == wantedNewer) &&
            list.any((s) => s.id == wantedOlder)) {
          newer = wantedNewer;
          older = wantedOlder;
          autoCompare = true;
        }
        setState(() {
          _snapshots = list;
          _newerId = newer;
          _olderId = older;
          _loading = false;
        });
        if (autoCompare) _compare();
      }
    } on DriftApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compare() async {
    if (_newerId == null || _olderId == null || _newerId == _olderId) return;
    setState(() {
      _comparing = true;
      _error = null;
      _report = null;
      _selectedObjectKey = null;
    });
    try {
      // Fetch both rows in parallel — each GET is a single payload-heavy call.
      final results = await Future.wait([
        widget.api.getSnapshot(_newerId!),
        widget.api.getSnapshot(_olderId!),
      ]);
      final newerSnap = results[0];
      final olderSnap = results[1];

      // Adapt both to the desktop SchemaSnapshot shape. We pass the snapshot
      // row's `captured_at` so the diff header shows real timestamps.
      final newerDesktop = driftSchemaJsonToDesktopSnapshot(
        connectionId: widget.connection.id,
        connectionName: widget.connection.name,
        schemaJson: newerSnap.schemaJson,
        capturedAtIso: newerSnap.capturedAt,
      );
      final olderDesktop = driftSchemaJsonToDesktopSnapshot(
        connectionId: widget.connection.id,
        connectionName: widget.connection.name,
        schemaJson: olderSnap.schemaJson,
        capturedAtIso: olderSnap.capturedAt,
      );

      // SchemaDiffService stores a DatabaseService but compareSnapshots only
      // reads the supplied snapshots; the service never touches the DB on
      // this code path. Constructing a default DatabaseService is cheap
      // (no I/O happens until connect()).
      // DEFENSIVE-NOTE: if SchemaDiffService.compareSnapshots ever starts
      // calling DatabaseService methods, this will throw loudly — preferred
      // over silent no-ops that could mask a future regression.
      final diffService = SchemaDiffService(DatabaseService());
      final report = diffService.compareSnapshots(
        source: olderDesktop, // "source" = older (left)
        target: newerDesktop, // "target" = newer (right)
      );
      if (mounted) setState(() => _report = report);
    } on DriftApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _buildHeader(context, l10n),
        const Divider(height: 1),
        if (_report != null) _buildFilterBar(context),
        if (_report != null) const Divider(height: 1),
        Expanded(child: _buildBody(context, l10n)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    // Two stacked rows instead of one: a single row squeezes the title to a
    // sliver next to the two 200px dropdowns, and the wrapped connection
    // subtitle then blows up the header height (the header sits in a Column
    // that gives it unbounded height). Single-line ellipsis + a Wrap'd
    // controls row keep the header a fixed ~2-row height at any width.
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.arrowRightLeft,
                color: colors.accentBlue,
                size: 22,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.driftDiffTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h3.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      '${widget.connection.name} (${widget.connection.hostLabel})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (_snapshots.length >= 2) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Wrap(
              spacing: AppDesignSystem.space2,
              runSpacing: AppDesignSystem.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _snapshotDropdown(
                  label: l10n.driftDiffSnapshotNewer,
                  value: _newerId,
                  exclude: _olderId,
                  onChanged: (v) => setState(() => _newerId = v),
                ),
                _snapshotDropdown(
                  label: l10n.driftDiffSnapshotOlder,
                  value: _olderId,
                  exclude: _newerId,
                  onChanged: (v) => setState(() => _olderId = v),
                ),
                ElevatedButton.icon(
                  onPressed: (_canCompare && !_comparing) ? _compare : null,
                  icon: _comparing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.arrowRightLeft, size: 18),
                  label: Text(l10n.driftDiffCompare),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _snapshotDropdown({
    required String label,
    required String? value,
    required String? exclude,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        // value: (not initialValue:) so the field reflects external setState
        // updates when the user picks a snapshot pair.
        // ignore: deprecated_member_use
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
            vertical: AppDesignSystem.space1,
          ),
        ),
        items: _snapshots
            .where((s) => s.id != exclude)
            .map(
              (s) => DropdownMenuItem(
                value: s.id,
                child: Text(
                  _formatTimestamp(s.capturedAt),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    // Reuse the Schema Diff filter-chip pattern; minimal subset for drift.
    final colors = context.themeColors;
    Widget chip(String label, DiffCategory cat) => Padding(
      padding: const EdgeInsets.only(right: AppDesignSystem.space1),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeSm,
            color: _activeFilter == cat
                ? colors.accentBlue
                : colors.textSecondary,
          ),
        ),
        selected: _activeFilter == cat,
        onSelected: (_) => setState(() => _activeFilter = cat),
        selectedColor: colors.accentBlue.withValues(alpha: 0.15),
        checkmarkColor: colors.accentBlue,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      child: Row(
        children: [
          chip('All', DiffCategory.all),
          chip('Added', DiffCategory.added),
          chip('Modified', DiffCategory.modified),
          chip('Removed', DiffCategory.removed),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: LucideIcons.circleAlert,
        color: context.themeColors.error,
        message: _error!,
        actionLabel: l10n.driftRetry,
        onAction: _loadSnapshots,
      );
    }
    if (_snapshots.length < 2) {
      // U17：只有 1 个快照 = 首次基线——不是「用户没选」，是「没得选」；
      // 原文案（请选择两个快照）对基线场景是误导。
      return _CenteredMessage(
        icon: LucideIcons.history,
        color: context.themeColors.textSecondary,
        message: _snapshots.length == 1
            ? l10n.driftDiffOnlyBaseline
            : l10n.driftDiffNoComparable,
      );
    }
    if (_report == null) {
      return _CenteredMessage(
        icon: LucideIcons.arrowRightLeft,
        color: context.themeColors.textSecondary,
        message: l10n.driftDiffPickSnapshots,
      );
    }
    if (!_report!.hasChanges) {
      return _CenteredMessage(
        icon: LucideIcons.circleCheckBig,
        color: context.themeColors.success,
        message: l10n.driftDiffEmpty,
      );
    }
    // Reuse the existing Schema Diff tree + detail + DDL-preview widgets
    // (same three-panel layout as the local Schema Diff page). The tree and
    // detail handle filter application internally (SchemaDiffTree.objectKeys).
    // The fixed-width panels (tree 280 + preview 360) need ~1000px; below
    // that the DDL preview collapses out instead of squeezing the detail
    // column into an overflow.
    return LayoutBuilder(
      builder: (context, constraints) {
        final showDdlPanel = constraints.maxWidth >= 1000;
        return Row(
          children: [
            SizedBox(
              width: 280,
              child: SchemaDiffTree(
                report: _report!,
                selectedObjectKey: _selectedObjectKey,
                filter: _activeFilter,
                onSelect: (key) => setState(() => _selectedObjectKey = key),
              ),
            ),
            VerticalDivider(
              width: 1,
              color: context.themeColors.borderSubtle,
            ),
            Expanded(
              child: SchemaDiffDetail(
                report: _report!,
                selectedObjectKey: _selectedObjectKey,
              ),
            ),
            if (showDdlPanel) ...[
              VerticalDivider(
                width: 1,
                color: context.themeColors.borderSubtle,
              ),
              SchemaDiffDdlPreview(
                selectedTableDiff: _selectedTableDiff,
                selectedViewDiff: _selectedViewDiff,
                selectedProcedureDiff: _selectedProcedureDiff,
              ),
            ],
          ],
        );
      },
    );
  }

  // ---- Selection helpers (mirrors schema_diff_page; keyed object ids are
  // produced by SchemaDiffTree and consumed by SchemaDiffDetail the same way) ----

  TableDiff? get _selectedTableDiff {
    if (_selectedObjectKey == null ||
        !_selectedObjectKey!.startsWith('table:')) {
      return null;
    }
    final name = _selectedObjectKey!.substring(6);
    return _report?.tableDiffs.where((t) => t.name == name).firstOrNull;
  }

  ViewDiff? get _selectedViewDiff {
    if (_selectedObjectKey == null ||
        !_selectedObjectKey!.startsWith('view:')) {
      return null;
    }
    final name = _selectedObjectKey!.substring(5);
    return _report?.viewDiffs.where((v) => v.name == name).firstOrNull;
  }

  ProcedureDiff? get _selectedProcedureDiff {
    if (_selectedObjectKey == null ||
        !_selectedObjectKey!.startsWith('proc:')) {
      return null;
    }
    final name = _selectedObjectKey!.substring(5);
    return _report?.procedureDiffs.where((p) => p.name == name).firstOrNull;
  }

  bool get _canCompare =>
      _newerId != null && _olderId != null && _newerId != _olderId;

  String _formatTimestamp(String iso) => formatRfc3339Local(iso);
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CenteredMessage({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: color.withValues(alpha: 0.6)),
          const SizedBox(height: AppDesignSystem.space3),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space6,
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: color),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppDesignSystem.space3),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
