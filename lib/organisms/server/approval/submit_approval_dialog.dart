//! Submit-DDL-for-approval dialog (#25). Collects a DDL statement + a target
//! Server-side connection and POSTs `/api/approvals`.
//!
//! Two entry modes share this dialog:
//! - Editor toolbar entry: [initialSql] is the current editor contents → shown
//!   read-only (the user edited it in the editor; this dialog only picks the
//!   target + confirms).
//! - Approval queue "Add" entry: [initialSql] is null → an editable multi-line
//!   field lets the user author/paste the DDL inline.
//!
//! Entitlement gate: the submit button is disabled and an activation prompt is
//! shown when `GET /api/entitlement` reports `state == "gated"`. The Server
//! also enforces this with HTTP 403 `ENTITLEMENT_GATED` — the local pre-check
//! is purely UX and is refreshed on dialog open.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/drift_models.dart';
import '../../../services/approval_api_service.dart';
import '../../../theme/app_colors.dart';
import '../connections/server_connections_dialog.dart';

/// Shows the submit-approval dialog. Returns the new approval id on success
/// (caller refreshes its list), `null` on cancel.
Future<String?> showSubmitApprovalDialog(
  BuildContext context, {
  ApprovalApiService? api,
  String? initialSql,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _SubmitApprovalDialog(api: api, initialSql: initialSql),
  );
}

class _SubmitApprovalDialog extends StatefulWidget {
  final ApprovalApiService? api;
  final String? initialSql;

  const _SubmitApprovalDialog({this.api, this.initialSql});

  @override
  State<_SubmitApprovalDialog> createState() => _SubmitApprovalDialogState();
}

class _SubmitApprovalDialogState extends State<_SubmitApprovalDialog> {
  late final ApprovalApiService _api;
  final _formKey = GlobalKey<FormState>();
  // Only used when editing (initialSql == null).
  final _ddlController = TextEditingController();

  List<DriftSourceConnection> _connections = const [];
  String? _selectedTargetDbId;
  bool _loadingConnections = true;
  bool _submitting = false;
  String? _error;
  ServerEntitlement? _entitlement;

  /// True when this dialog was opened from the editor toolbar with prefilled
  /// read-only SQL.
  bool get _isReadonly => widget.initialSql != null;

  /// The DDL to submit, trimmed — from the readonly buffer or the controller.
  String get _ddlSql =>
      (_isReadonly ? widget.initialSql! : _ddlController.text).trim();

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApprovalApiService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _ddlController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadConnections(), _loadEntitlement()]);
  }

  Future<void> _loadConnections() async {
    if (!_api.isConnected) {
      if (mounted) setState(() => _loadingConnections = false);
      return;
    }
    try {
      final conns = await _api.listConnections();
      if (mounted) {
        setState(() {
          // U05: approval executes DDL against the target — read-only
          // source_drift rows must never appear in this dropdown.
          _connections = conns.where((c) => !c.isSourceDrift).toList();
          _loadingConnections = false;
          if (_connections.isNotEmpty && _selectedTargetDbId == null) {
            _selectedTargetDbId = _connections.first.id;
          }
        });
      }
    } on ApprovalApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingConnections = false);
    }
  }

  Future<void> _loadEntitlement() async {
    if (!_api.isConnected) return;
    try {
      final ent = await _api.fetchEntitlement();
      if (mounted) setState(() => _entitlement = ent);
    } catch (_) {
      // Soft-fail: assume open when unreachable — the Server's 403 is the
      // source of truth.
    }
  }

  bool get _isGated => _entitlement?.isGated ?? false;

  bool get _canSubmit =>
      !_submitting &&
      !_loadingConnections &&
      !_isGated &&
      _selectedTargetDbId != null &&
      _ddlSql.isNotEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final id = await _api.submit(
        ddlSql: _ddlSql,
        targetDbId: _selectedTargetDbId!,
      );
      if (mounted) Navigator.of(context).pop(id);
    } on ApprovalApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.clipboardCheck, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.approvalSubmitTitle),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isGated) ...[
                  _gatedBanner(l10n, colors),
                  const SizedBox(height: AppDesignSystem.space3),
                ],
                // DDL field — readonly preview or editable multiline.
                _ddlField(l10n, colors),
                const SizedBox(height: AppDesignSystem.space2),
                _targetSelector(l10n, colors),
                if (_error != null) ...[
                  const SizedBox(height: AppDesignSystem.space2),
                  _errorBanner(_error!, colors),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: Text(l10n.approvalCancel),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.send, size: 18),
          label: Text(l10n.approvalSubmitButton),
        ),
      ],
    );
  }

  Widget _ddlField(AppLocalizations l10n, ThemeColors colors) {
    if (_isReadonly) {
      // Readonly preview of the editor contents — monospace, scrollable.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
            child: Text(
              l10n.approvalSubmitDdlLabel,
              style: AppTextStyles.label.copyWith(
                color: colors.textSecondary,
                fontWeight: AppDesignSystem.fontWeightSemibold,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(color: colors.borderLight),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.initialSql!,
                style: AppTextStyles.code.copyWith(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return TextFormField(
      controller: _ddlController,
      maxLines: 6,
      style: AppTextStyles.code.copyWith(
        fontSize: AppDesignSystem.fontSizeSm,
        color: colors.textPrimary,
      ),
      decoration:
          _inputDecoration(
            l10n.approvalSubmitDdlLabel,
            LucideIcons.code,
          ).copyWith(
            hintText: l10n.approvalSubmitDdlHint,
            alignLabelWithHint: true,
          ),
      validator: (v) {
        final s = v?.trim() ?? '';
        if (s.isEmpty) return l10n.approvalSubmitRequired;
        if (!_looksLikeDdl(s)) return l10n.approvalSubmitInvalidSql;
        return null;
      },
    );
  }

  Widget _targetSelector(AppLocalizations l10n, ThemeColors colors) {
    if (!_api.isConnected) {
      return Container(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.06),
          border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Text(
          l10n.approvalSubmitNoConnection,
          style: TextStyle(color: colors.textPrimary),
        ),
      );
    }
    if (_loadingConnections) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space3,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderLight),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              l10n.approvalLoading,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_connections.isEmpty) {
      // U05: point at the server-side registry (the management dialog), not
      // the local sidebar list — on a remote deployment that would loop.
      return Container(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.06),
          border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.approvalSubmitNoConnection,
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(LucideIcons.database, size: 16),
                label: Text(l10n.serverConnectionsMenuLabel),
                onPressed: () async {
                  await showServerConnectionsDialog(context);
                  if (mounted) _loadConnections();
                },
              ),
            ),
          ],
        ),
      );
    }
    return DropdownButtonFormField<String>(
      // `value` (not `initialValue`) so the field tracks external setState
      // updates — mirrors drift_create_task_dialog.
      // ignore: deprecated_member_use
      value: _selectedTargetDbId,
      decoration: _inputDecoration(
        l10n.approvalSubmitTargetDb,
        LucideIcons.cloud,
      ),
      items: _connections
          .map(
            (c) => DropdownMenuItem(
              value: c.id,
              child: Row(
                // min + ConstrainedBox (no flex): DropdownButton pre-measures
                // items under unbounded width and any flex child throws.
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.database, size: 18),
                  const SizedBox(width: AppDesignSystem.space2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Text(
                      '${c.name} (${c.hostLabel})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: _submitting
          ? null
          : (v) => setState(() => _selectedTargetDbId = v),
    );
  }

  Widget _gatedBanner(AppLocalizations l10n, ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.lock, size: 18, color: colors.warning),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.approvalGatedTitle,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: AppDesignSystem.fontWeightSemibold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  l10n.approvalGatedBody,
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message, ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleAlert, size: 16, color: colors.error),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: SelectableText(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
      );

  /// Lightweight DDL-shape check on the first non-empty trimmed line. Advisory
  /// only — the Server's `is_ddl_statement` whitelist is the source of truth
  /// and rejects non-DDL with a redacted error.
  bool _looksLikeDdl(String sql) {
    final firstLine = sql
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return false;
    final upper = firstLine.toUpperCase();
    const heads = ['CREATE', 'ALTER', 'DROP', 'TRUNCATE', 'RENAME'];
    return heads.any((h) => upper.startsWith(h));
  }
}
