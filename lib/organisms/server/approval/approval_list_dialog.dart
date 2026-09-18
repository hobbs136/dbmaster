//! DDL Approval queue dialog (#25). Lists pending/resolved approvals from the
//! Server (`GET /api/approvals`) and exposes the in-row approve / reject /
//! view-DDL actions. Mirrors `TeamQueryLibraryDialog`'s list+inline-action
//! shape, with a status-driven action set and a fast poll while open.
//!
//! Data flow: [ApprovalProvider] (a long-lived ChangeNotifier registered in
//! main.dart) owns the approval list + drives the status-bar pending badge.
//! This dialog watches the provider, triggers `refresh()` on open / poll /
//! manual refresh / after a mutation. Connection id → name resolution uses a
//! short-lived local [ApprovalApiService] (`GET /api/connections`).
//!
//! Poll: while the dialog is open, a 3s [Timer.periodic] calls
//! `provider.refresh()` so the `executing → approved/failed` transition (the
//! Server runs the approved DDL in a spawned task) is surfaced without the
//! user clicking refresh. Pending rows can also be resolved by another team
//! member, so the poll runs regardless of whether any row is executing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/rfc3339.dart';
import '../../../models/ddl_approval.dart';
import '../../../providers/approval_provider.dart';
import '../../../services/approval_api_service.dart';
import '../../../theme/app_colors.dart';
import 'submit_approval_dialog.dart';

/// Opens the DDL approval queue dialog. [api] is injectable for tests
/// (mirrors the health-check task list dialog); defaults to a short-lived
/// [ApprovalApiService] bound to the live ServerConnection.
Future<void> showApprovalListDialog(
  BuildContext context, {
  ApprovalApiService? api,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 860,
        height: 580,
        child: _ApprovalListDialog(api: api),
      ),
    ),
  );
}

class _ApprovalListDialog extends StatefulWidget {
  final ApprovalApiService? api;

  const _ApprovalListDialog({this.api});

  @override
  State<_ApprovalListDialog> createState() => _ApprovalListDialogState();
}

class _ApprovalListDialogState extends State<_ApprovalListDialog> {
  late final ApprovalApiService _api;
  final Map<String, String> _connectionNames = {};
  final Set<String> _actionInFlight = {};
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApprovalApiService();
    // Initial fetch (provider guards itself on connection state).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ApprovalProvider>().refresh();
      _loadConnectionNames();
      _startPoll();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) context.read<ApprovalProvider>().refresh();
    });
  }

  Future<void> _loadConnectionNames() async {
    if (!_api.isConnected) return;
    try {
      final conns = await _api.listConnections();
      if (mounted) {
        setState(() {
          _connectionNames
            ..clear()
            ..addEntries(conns.map((c) => MapEntry(c.id, c.name)));
        });
      }
    } catch (_) {
      // Name resolution is best-effort; fall back to the raw id.
    }
  }

  Future<void> _submitNew() async {
    final created = await showSubmitApprovalDialog(context, api: _api);
    if (created != null && mounted) {
      context.read<ApprovalProvider>().refresh();
    }
  }

  Future<void> _approve(DdlApproval a) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _actionInFlight.add(a.id));
    try {
      await _api.approve(a.id);
      if (mounted) context.read<ApprovalProvider>().refresh();
    } on ApprovalApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(e, l10n))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(a.id));
    }
  }

  Future<void> _reject(DdlApproval a) async {
    final l10n = AppLocalizations.of(context)!;
    // The Server does NOT validate the current status on reject and does not
    // roll back an already-executed DDL — confirm first to prevent clobbering
    // an approved/executing row.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.approvalRejectTitle),
        content: Text(l10n.approvalRejectConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.approvalCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.approvalReject),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInFlight.add(a.id));
    try {
      await _api.reject(a.id);
      if (mounted) context.read<ApprovalProvider>().refresh();
    } on ApprovalApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(e, l10n))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(a.id));
    }
  }

  String _errorMessage(ApprovalApiException e, AppLocalizations l10n) {
    switch (e.code) {
      case 'ALREADY_RESOLVED':
        return l10n.approvalAlreadyResolved;
      case 'CONFLICT':
        return l10n.approvalConflict;
      case 'APPROVAL_NOT_FOUND':
        return l10n.approvalNotFound;
      case 'ENTITLEMENT_GATED':
        return l10n.approvalGatedBody;
      default:
        return e.message;
    }
  }

  Future<void> _viewDdl(DdlApproval a) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.approvalViewDdl),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // U10 — failed executions show the full redacted error above
                // the DDL (the list row only carries a one-line preview).
                if (a.hasExecError) ...[
                  SelectableText(
                    l10n.approvalExecError(a.execError!),
                    style: AppTextStyles.caption.copyWith(
                      color: ctx.themeColors.error,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  const Divider(),
                  const SizedBox(height: AppDesignSystem.space2),
                ],
                SelectableText(
                  a.ddlSql,
                  style: AppTextStyles.code.copyWith(
                    fontSize: AppDesignSystem.fontSizeSm,
                    color: ctx.themeColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.approvalCancel),
          ),
        ],
      ),
    );
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = _l10n;
    final provider = context.watch<ApprovalProvider>();
    final approvals = provider.approvals;

    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Row(
            children: [
              Icon(
                LucideIcons.clipboardCheck,
                color: colors.accentBlue,
                size: 18,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  l10n.approvalListTitle,
                  style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
                ),
              ),
              IconButton(
                tooltip: l10n.approvalAddTooltip,
                icon: const Icon(LucideIcons.circlePlus),
                onPressed: _api.isConnected ? _submitNew : null,
              ),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw),
                tooltip: l10n.approvalRefresh,
                onPressed: () => provider.refresh(),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: AppDesignSystem.space2),
          Expanded(
            child: !_api.isConnected
                ? _centeredMessage(l10n.approvalNotConnected, colors)
                : _body(provider, approvals, colors),
          ),
        ],
      ),
    );
  }

  Widget _body(
    ApprovalProvider provider,
    List<DdlApproval> approvals,
    ThemeColors colors,
  ) {
    final l10n = _l10n;
    if (provider.isRefreshing &&
        approvals.isEmpty &&
        provider.lastError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (approvals.isEmpty) {
      final msg = provider.lastError != null
          ? (provider.lastError is ApprovalApiException
                ? (provider.lastError as ApprovalApiException).message
                : provider.lastError.toString())
          : l10n.approvalListEmpty;
      return RefreshIndicator(
        onRefresh: () => provider.refresh(),
        child: _centeredMessage(msg, colors),
      );
    }
    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      child: ListView.separated(
        itemCount: approvals.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colors.borderSubtle,
        ),
        itemBuilder: (context, i) => _approvalRow(approvals[i], colors),
      ),
    );
  }

  Widget _approvalRow(DdlApproval a, ThemeColors colors) {
    final inFlight = _actionInFlight.contains(a.id);
    final statusColor = _statusColor(a, colors);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status dot / executing spinner.
          if (a.isExecuting)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: statusColor,
                ),
              ),
            )
          else
            Icon(LucideIcons.circle, size: 10, color: statusColor),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status label + time.
                Row(
                  children: [
                    Text(
                      _statusLabel(a),
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: AppDesignSystem.fontWeightSemibold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      _formatTime(a.createdAt),
                      style: AppTextStyles.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _sqlPreview(a.ddlSql),
                  style: AppTextStyles.code.copyWith(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _metaLine(a),
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                // U10 — surface the failure reason inline (single line; the
                // full text lives in the view-DDL dialog).
                if (a.hasExecError)
                  Text(
                    _l10n.approvalExecError(a.execError!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(color: colors.error),
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
          else
            ..._actionsFor(a, colors),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(DdlApproval a, ThemeColors colors) {
    if (a.isPending) {
      return [
        IconButton(
          icon: Icon(
            LucideIcons.circleCheckBig,
            size: 18,
            color: colors.success,
          ),
          tooltip: _l10n.approvalApprove,
          onPressed: () => _approve(a),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: Icon(LucideIcons.circleX, size: 18, color: colors.error),
          tooltip: _l10n.approvalReject,
          onPressed: () => _reject(a),
          visualDensity: VisualDensity.compact,
        ),
      ];
    }
    // Resolved rows: only view-DDL (no mutate action).
    return [
      IconButton(
        icon: Icon(LucideIcons.eye, size: 18, color: colors.textSecondary),
        tooltip: _l10n.approvalViewDdl,
        onPressed: () => _viewDdl(a),
        visualDensity: VisualDensity.compact,
      ),
    ];
  }

  Color _statusColor(DdlApproval a, ThemeColors colors) {
    if (a.isPending) return colors.warning;
    if (a.isExecuting) return colors.accentBlue;
    if (a.isApproved) return colors.success;
    if (a.isFailed) return colors.error;
    if (a.isRejected) return colors.textMuted;
    return colors.textMuted;
  }

  String _statusLabel(DdlApproval a) {
    final l10n = _l10n;
    if (a.isPending) return l10n.approvalStatusPending;
    if (a.isExecuting) return l10n.approvalStatusExecuting;
    if (a.isApproved) return l10n.approvalStatusApproved;
    if (a.isFailed) return l10n.approvalStatusFailed;
    if (a.isRejected) return l10n.approvalStatusRejected;
    return a.status;
  }

  String _metaLine(DdlApproval a) {
    final target = _connectionNames[a.targetDbId] ?? a.targetDbId;
    final submitter = a.submitterId.isEmpty ? '—' : a.submitterId;
    return _l10n.approvalMetaLine(target, submitter);
  }

  String _sqlPreview(String sql) {
    final lines = sql
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(2)
        .join(' ');
    if (lines.length > 140) return '${lines.substring(0, 140)}…';
    return lines;
  }

  String _formatTime(String iso) {
    // U17：此前字符串切片显示的是 UTC 值，与本地时间差数小时。
    return formatRfc3339Local(iso);
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
