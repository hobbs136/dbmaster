//! Generic edit dialog for a Server scheduled task's schedule fields.
//!
//! Backed by the Server's `PATCH /api/tasks/:id` partial-update (#5). Edits
//! the schedule-affecting fields common across task types: name, enabled
//! (pause/resume), and an optional webhook. The schedule field itself (cron)
//! is rendered per [TaskScheduleField] — drift has no cron (interval-driven,
//! lives in `config`), data_sync treats cron as optional (empty = run-once),
//! health requires it.
//!
//! `config` and `target_db_id` are intentionally NOT editable here — changing
//! them mid-flight is risky (re-validation, connection re-bind). Recreate the
//! task instead.
//!
//! Task-type agnostic: the caller supplies the current field values + a
//! [TaskPatchFn] closure bound to the specific ApiService. This keeps the
//! three `*_task_list_dialog.dart` files free of duplicated form code while
//! each binds its own service + task model.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// How [TaskEditDialog] renders the schedule (cron) field.
enum TaskScheduleField {
  /// Cron required (health_check — cron-driven, no immediate mode).
  cron,

  /// Cron optional; empty = run-once / no schedule (data_sync).
  cronOptional,

  /// No schedule field shown (drift — interval-driven via `config`).
  none,
}

/// Closure passed to [showTaskEditDialog]; binds the task id + the specific
/// ApiService's `patchTask`. Mirrors the `patchTask` signature shared by
/// `DataSyncApiService`, `DriftApiService`, `HealthApiService`.
typedef TaskPatchFn =
    Future<Map<String, dynamic>> Function({
      bool? enabled,
      String? name,
      String? cronExpr,
      List<String>? notifyChannels,
    });

/// Shows the task-edit dialog. Returns `true` if a patch was applied (caller
/// refreshes its task list), `false`/`null` on cancel.
Future<bool?> showTaskEditDialog(
  BuildContext context, {
  required String taskName,
  required bool initialEnabled,
  required TaskScheduleField scheduleField,
  String initialCronExpr = '',
  String initialWebhook = '',
  required TaskPatchFn onPatch,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _TaskEditDialog(
      taskName: taskName,
      initialEnabled: initialEnabled,
      scheduleField: scheduleField,
      initialCronExpr: initialCronExpr,
      initialWebhook: initialWebhook,
      onPatch: onPatch,
    ),
  );
}

class _TaskEditDialog extends StatefulWidget {
  final String taskName;
  final bool initialEnabled;
  final TaskScheduleField scheduleField;
  final String initialCronExpr;
  final String initialWebhook;
  final TaskPatchFn onPatch;

  const _TaskEditDialog({
    required this.taskName,
    required this.initialEnabled,
    required this.scheduleField,
    required this.initialCronExpr,
    required this.initialWebhook,
    required this.onPatch,
  });

  @override
  State<_TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<_TaskEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cronController;
  late final TextEditingController _webhookController;
  late bool _enabled;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.taskName);
    _cronController = TextEditingController(text: widget.initialCronExpr);
    _webhookController = TextEditingController(text: widget.initialWebhook);
    _enabled = widget.initialEnabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cronController.dispose();
    _webhookController.dispose();
    super.dispose();
  }

  bool get _showsCron => widget.scheduleField != TaskScheduleField.none;
  bool get _cronRequired => widget.scheduleField == TaskScheduleField.cron;

  bool get _canSubmit => !_submitting && _nameController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // U17：逗号分隔多 URL（wire 上 notify_channels 是数组；单 URL 输入
      // 行为不变——拆分后长度仍为 1）。
      final webhooks = _webhookController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await widget.onPatch(
        name: _nameController.text.trim(),
        enabled: _enabled,
        // For drift (none) we pass null → server leaves cron unchanged.
        cronExpr: _showsCron ? _cronController.text.trim() : null,
        notifyChannels: webhooks,
      );
      if (mounted) Navigator.of(context).pop(true);
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
          Icon(LucideIcons.calendarClock, color: colors.accentBlue, size: 18),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.taskEditTitle),
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
                TextFormField(
                  controller: _nameController,
                  decoration: _inputDecoration(
                    l10n.taskEditName,
                    LucideIcons.tag,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.taskEditInvalidName
                      : null,
                ),
                const SizedBox(height: AppDesignSystem.space2),
                SwitchListTile(
                  value: _enabled,
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _enabled = v),
                  title: Text(l10n.taskEditEnabled),
                  subtitle: Text(
                    _enabled
                        ? l10n.taskEditEnabledHint
                        : l10n.taskEditDisabledHint,
                  ),
                  dense: true,
                ),
                if (_showsCron) ...[
                  const SizedBox(height: AppDesignSystem.space2),
                  TextFormField(
                    controller: _cronController,
                    decoration: _inputDecoration(
                      l10n.taskEditCron,
                      LucideIcons.clock,
                    ).copyWith(helperText: l10n.taskEditCronHint),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) {
                        // health requires cron; data_sync allows empty (run-once).
                        return _cronRequired ? l10n.taskEditInvalidCron : null;
                      }
                      // Lightweight 5-field shape check; semantic validation is
                      // deferred to the Server scheduler (errors surface via
                      // last_status on the next tick).
                      if (s.split(RegExp(r'\s+')).length != 5) {
                        return l10n.taskEditInvalidCron;
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: AppDesignSystem.space2),
                TextFormField(
                  controller: _webhookController,
                  decoration: _inputDecoration(
                    l10n.taskEditWebhook,
                    LucideIcons.webhook,
                  ).copyWith(helperText: l10n.taskEditWebhookHint),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return null;
                    // 逗号分隔的多 URL 逐个校验（单 URL 输入同样成立）。
                    for (final url in s.split(',').map((p) => p.trim())) {
                      if (url.isEmpty) continue;
                      if (!url.startsWith('https://')) {
                        return l10n.taskEditInvalidWebhook;
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
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(l10n.taskEditCancel),
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
              : const Icon(LucideIcons.save, size: 18),
          label: Text(l10n.taskEditSubmit),
        ),
      ],
    );
  }

  /// Inline copy of `drift_create_task_dialog._errorBanner`. Extracting a
  /// shared base class would touch the create-dialog hierarchy (cross-spec
  /// risk); the two dialogs stay self-contained.
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
