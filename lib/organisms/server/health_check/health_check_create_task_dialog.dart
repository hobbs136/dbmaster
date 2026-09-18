//! Create-health-check-task dialog. Picks a source `database_connection`,
//! a cron schedule, an optional alert threshold, and an optional webhook URL;
//! assembles the Server-side config JSON and POSTs `/api/tasks`.
//!
//! Mirrors `drift_create_task_dialog.dart`. Entitlement gate: the create
//! button is disabled and an activation prompt is shown when
//! `GET /api/entitlement` reports `state == "gated"`. The Server also enforces
//! this with HTTP 403 `ENTITLEMENT_GATED` — the local pre-check is purely UX
//! (immediate feedback + a clear remediation path) and is refreshed on open.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/drift_models.dart';
import '../../../models/health_summary.dart';
import '../../../services/health_api_service.dart';
import '../../../theme/app_colors.dart';
import '../connections/server_connections_dialog.dart';

/// Shows the create-health-check-task dialog. Returns the created [HealthTask]
/// on success (caller refreshes its list), `null` on cancel.
Future<HealthTask?> showHealthCheckCreateTaskDialog(
  BuildContext context, {
  required HealthApiService api,
}) {
  return showDialog<HealthTask>(
    context: context,
    builder: (ctx) => _HealthCheckCreateTaskDialog(api: api),
  );
}

class _HealthCheckCreateTaskDialog extends StatefulWidget {
  final HealthApiService api;
  const _HealthCheckCreateTaskDialog({required this.api});

  @override
  State<_HealthCheckCreateTaskDialog> createState() =>
      _HealthCheckCreateTaskDialogState();
}

class _HealthCheckCreateTaskDialogState
    extends State<_HealthCheckCreateTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _webhookController = TextEditingController();

  /// Cron schedule. Default every 5 minutes (health is a frequent probe).
  final _cronController = TextEditingController(text: '*/5 * * * *');

  /// Consecutive-failure count before alerting (flap suppression). Default
  /// mirrors the Server's `default_fail_threshold` (3).
  final _failThresholdController = TextEditingController(
    text: '${HealthCheckTaskConfig.defaultFailThreshold}',
  );

  List<DriftSourceConnection> _connections = const [];
  String? _selectedConnectionId;
  bool _loadingConnections = true;
  bool _submitting = false;
  String? _error;
  ServerEntitlement? _entitlement;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _webhookController.dispose();
    _cronController.dispose();
    _failThresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadConnections(), _loadEntitlement()]);
  }

  Future<void> _loadConnections() async {
    setState(() => _loadingConnections = true);
    try {
      final connections = await widget.api.listConnections();
      if (mounted) {
        setState(() {
          // U05: source_drift rows are read-only, canary-verified drift
          // sources — semantically wrong as health probes. Collab rows only.
          _connections = connections.where((c) => !c.isSourceDrift).toList();
          _loadingConnections = false;
          if (_connections.isNotEmpty && _selectedConnectionId == null) {
            _selectedConnectionId = _connections.first.id;
          }
        });
      }
    } on HealthApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingConnections = false);
    }
  }

  Future<void> _loadEntitlement() async {
    try {
      final ent = await widget.api.fetchEntitlement();
      if (mounted) setState(() => _entitlement = ent);
    } catch (_) {
      // Soft-fail: assume open when unreachable — the Server's 403 is the
      // source of truth (mirrors drift_create_task_dialog).
    }
  }

  bool get _isGated => _entitlement?.isGated ?? false;

  bool get _canSubmit =>
      !_submitting &&
      !_loadingConnections &&
      !_isGated &&
      _selectedConnectionId != null &&
      _nameController.text.trim().isNotEmpty &&
      _cronController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    final failRaw = int.tryParse(_failThresholdController.text.trim());
    if (failRaw == null ||
        failRaw < HealthCheckTaskConfig.minFailThreshold ||
        failRaw > HealthCheckTaskConfig.maxFailThreshold) {
      setState(() => _error = l10n.healthCreateTaskInvalidFailThreshold);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final webhook = _webhookController.text.trim();
      // metrics + the other thresholds use Server defaults; only the
      // user-tuned fail_threshold is overridden here.
      final config = HealthCheckTaskConfig(failThreshold: failRaw);
      final task = await widget.api.createTask(
        name: _nameController.text.trim(),
        sourceDbId: _selectedConnectionId!,
        cronExpr: _cronController.text.trim(),
        config: config.toJson(),
        notifyChannels: webhook.isEmpty ? const [] : [webhook],
      );
      if (mounted) Navigator.of(context).pop(task);
    } on HealthApiException catch (e) {
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
          Icon(LucideIcons.heartPulse, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.healthCreateTaskTitle),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isGated) _gatedBanner(l10n, colors),
                if (_isGated) const SizedBox(height: AppDesignSystem.space3),
                TextFormField(
                  controller: _nameController,
                  decoration: _inputDecoration(
                    l10n.healthCreateTaskName,
                    LucideIcons.tag,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.healthCreateTaskInvalidName
                      : null,
                ),
                const SizedBox(height: AppDesignSystem.space2),
                _connectionSelector(l10n, colors),
                const SizedBox(height: AppDesignSystem.space2),
                TextFormField(
                  controller: _cronController,
                  decoration: _inputDecoration(
                    l10n.healthCreateTaskCron,
                    LucideIcons.clock,
                  ).copyWith(helperText: l10n.healthCreateTaskCronHint),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return l10n.healthCreateTaskInvalidCron;
                    // Light 5-field shape check; full cron semantics are
                    // validated by the Server scheduler when it parses the row.
                    if (s.split(RegExp(r'\s+')).length != 5) {
                      return l10n.healthCreateTaskInvalidCron;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppDesignSystem.space2),
                TextFormField(
                  controller: _failThresholdController,
                  keyboardType: TextInputType.number,
                  decoration:
                      _inputDecoration(
                        l10n.healthCreateTaskFailThreshold,
                        LucideIcons.triangleAlert,
                      ).copyWith(
                        helperText: l10n.healthCreateTaskFailThresholdHint,
                      ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null ||
                        n < HealthCheckTaskConfig.minFailThreshold ||
                        n > HealthCheckTaskConfig.maxFailThreshold) {
                      return l10n.healthCreateTaskInvalidFailThreshold;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppDesignSystem.space2),
                TextFormField(
                  controller: _webhookController,
                  decoration: _inputDecoration(
                    l10n.healthCreateTaskWebhook,
                    LucideIcons.webhook,
                  ).copyWith(helperText: l10n.healthCreateTaskWebhookHint),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return null;
                    if (!s.startsWith('https://')) {
                      return l10n.healthCreateTaskInvalidWebhook;
                    }
                    return null;
                  },
                ),
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
          child: Text(l10n.healthClose),
        ),
        ElevatedButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _submitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Icon(LucideIcons.plus, size: 18),
          label: Text(l10n.healthCreateTaskSubmit),
        ),
      ],
    );
  }

  Widget _connectionSelector(AppLocalizations l10n, ThemeColors colors) {
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
              l10n.healthLoading,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_connections.isEmpty) {
      // U05: the registry is server-side; adding a connection via the
      // management dialog is the way out of this state (pointing at the
      // local sidebar list would loop forever on a remote deployment).
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
              l10n.healthCreateTaskNoConnections,
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
      // ignore: deprecated_member_use
      value: _selectedConnectionId,
      decoration: _inputDecoration(
        l10n.healthCreateTaskSource,
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
          : (v) => setState(() => _selectedConnectionId = v),
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
                  l10n.healthGatedTitle,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: AppDesignSystem.fontWeightSemibold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  l10n.healthGatedBody,
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
              style: AppTextStyles.caption.copyWith(color: colors.error),
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
}
