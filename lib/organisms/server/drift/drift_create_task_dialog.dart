//! Create-drift-task dialog. Picks a source_drift connection, an interval,
//! and an optional webhook URL; assembles the Server-side config JSON and
//! POSTs `/api/tasks`.
//!
//! Entitlement gate: the create button is disabled and an activation prompt
//! is shown when `GET /api/entitlement` reports `state == "gated"`. The
//! Server also enforces this with HTTP 403 `ENTITLEMENT_GATED` — the local
//! pre-check is purely UX (so the user gets immediate feedback + a clear
//! remediation path) and is refreshed on dialog open.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/drift_models.dart';
import '../../../services/drift_api_service.dart';
import '../../../theme/app_colors.dart';
import 'drift_create_source_connection_dialog.dart';

/// Shows the create-drift-task dialog. Returns the created [DriftTask] on
/// success (caller refreshes its list), `null` on cancel.
Future<DriftTask?> showDriftCreateTaskDialog(
  BuildContext context, {
  required DriftApiService api,
}) {
  return showDialog<DriftTask>(
    context: context,
    builder: (ctx) => _DriftCreateTaskDialog(api: api),
  );
}

class _DriftCreateTaskDialog extends StatefulWidget {
  final DriftApiService api;
  const _DriftCreateTaskDialog({required this.api});

  @override
  State<_DriftCreateTaskDialog> createState() => _DriftCreateTaskDialogState();
}

class _DriftCreateTaskDialogState extends State<_DriftCreateTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _webhookController = TextEditingController();

  /// Interval is edited in minutes; a small UX affordance surfaces the
  /// equivalent in hours when ≥ 60.
  final _intervalController = TextEditingController(text: '5');

  List<DriftSourceConnection> _sources = const [];
  String? _selectedSourceId;
  bool _loadingSources = true;
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
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSources(), _loadEntitlement()]);
  }

  Future<void> _loadSources() async {
    setState(() => _loadingSources = true);
    try {
      final sources = await widget.api.listSourceDriftConnections();
      if (mounted) {
        setState(() {
          _sources = sources;
          _loadingSources = false;
          if (_sources.isNotEmpty && _selectedSourceId == null) {
            _selectedSourceId = sources.first.id;
          }
        });
      }
    } on DriftApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  Future<void> _loadEntitlement() async {
    try {
      final ent = await widget.api.fetchEntitlement();
      if (mounted) setState(() => _entitlement = ent);
    } catch (_) {
      // Soft-fail: entitlement gate stays closed (defensive: assume open when
      // the endpoint is unreachable — the Server's 403 is the source of
      // truth).
    }
  }

  bool get _isGated => _entitlement?.isGated ?? false;

  bool get _canSubmit =>
      !_submitting &&
      !_loadingSources &&
      !_isGated &&
      _selectedSourceId != null &&
      _nameController.text.trim().isNotEmpty;

  Future<void> _addSource() async {
    final created = await showDriftCreateSourceConnectionDialog(
      context,
      api: widget.api,
    );
    if (created != null) {
      // Refresh the list and pre-select the new connection.
      await _loadSources();
      if (mounted) {
        setState(() => _selectedSourceId = created.id);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    final interval = int.tryParse(_intervalController.text.trim());
    if (interval == null || interval < 1 || interval > 1440) {
      setState(() => _error = l10n.driftCreateTaskInvalidInterval);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // U17：逗号分隔多 URL（与编辑对话框一致；单 URL 行为不变）。
      final webhooks = _webhookController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final task = await widget.api.createDriftTask(
        name: _nameController.text.trim(),
        sourceDbId: _selectedSourceId!,
        config: DriftTaskConfig(intervalMinutes: interval),
        webhookUrls: webhooks,
      );
      if (mounted) Navigator.of(context).pop(task);
    } on DriftApiException catch (e) {
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
          Icon(LucideIcons.bellPlus, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.driftCreateTaskTitle),
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
                    l10n.driftCreateTaskName,
                    LucideIcons.tag,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.driftCreateTaskInvalidName
                      : null,
                ),
                const SizedBox(height: AppDesignSystem.space2),
                _sourceSelector(l10n, colors),
                const SizedBox(height: AppDesignSystem.space2),
                TextFormField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    l10n.driftCreateTaskInterval,
                    LucideIcons.clock,
                  ).copyWith(suffixText: 'min'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 1440) {
                      return l10n.driftCreateTaskInvalidInterval;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppDesignSystem.space2),
                TextFormField(
                  controller: _webhookController,
                  decoration: _inputDecoration(
                    l10n.driftCreateTaskWebhook,
                    LucideIcons.webhook,
                  ).copyWith(helperText: l10n.driftCreateTaskWebhookHint),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return null;
                    // 逗号分隔的多 URL 逐个校验（单 URL 输入同样成立）。
                    for (final url in s.split(',').map((p) => p.trim())) {
                      if (url.isEmpty) continue;
                      if (!url.startsWith('https://')) {
                        return l10n.driftCreateTaskInvalidWebhook;
                      }
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
          child: Text(l10n.driftClose),
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
          label: Text(l10n.driftCreateTaskSubmit),
        ),
      ],
    );
  }

  Widget _sourceSelector(AppLocalizations l10n, ThemeColors colors) {
    if (_loadingSources) {
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
              l10n.driftLoading,
              style: AppTextStyles.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }
    if (_sources.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.06),
          border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.driftCreateTaskNoSources,
              style: AppTextStyles.body.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isGated ? null : _addSource,
                icon: const Icon(LucideIcons.link2, size: 18),
                label: Text(l10n.driftCreateTaskAddSource),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          // value: (not initialValue:) so the field tracks external setState
          // updates when a new source connection is added inline.
          // ignore: deprecated_member_use
          value: _selectedSourceId,
          decoration: _inputDecoration(
            l10n.driftCreateTaskSource,
            LucideIcons.cloud,
          ),
          items: _sources
              .map(
                (s) => DropdownMenuItem(
                  value: s.id,
                  child: Row(
                    // min + ConstrainedBox (no flex): DropdownButton
                    // pre-measures items under unbounded width and any
                    // flex child throws (same fix as approval/health).
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_dbTypeIcon(s.dbType), size: 18),
                      const SizedBox(width: AppDesignSystem.space2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Text(
                          '${s.name} (${s.hostLabel})',
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
              : (v) => setState(() => _selectedSourceId = v),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppDesignSystem.space1),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isGated || _submitting ? null : _addSource,
              icon: const Icon(LucideIcons.link2, size: 16),
              label: Text(l10n.driftCreateTaskAddSource),
            ),
          ),
        ),
      ],
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
                  l10n.driftGatedTitle,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: AppDesignSystem.fontWeightSemibold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  l10n.driftGatedBody,
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

  IconData _dbTypeIcon(String dbType) {
    // Use a stable icon across both supported v1 source flavors (MySQL,
    // PostgreSQL). Avoid relying on niche Material icons that may not exist.
    return LucideIcons.database;
  }
}
