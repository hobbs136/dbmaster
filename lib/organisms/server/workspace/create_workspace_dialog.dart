//! Create-workspace dialog (#26). Collects a name and POSTs `/api/workspaces`.
//! The Server makes the caller an admin of the new workspace. Server-side name
//! validation is 1–100 chars (after trim); mirrored here as an advisory
//! client-side check (the Server is the source of truth).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/workspace.dart';
import '../../../services/workspace_api_service.dart';
import '../../../theme/app_colors.dart';

/// Shows the create-workspace dialog. Returns the created [Workspace] on
/// success (caller refreshes its list), `null` on cancel.
Future<Workspace?> showCreateWorkspaceDialog(
  BuildContext context, {
  WorkspaceApiService? api,
}) {
  return showDialog<Workspace>(
    context: context,
    builder: (ctx) => _CreateWorkspaceDialog(api: api),
  );
}

class _CreateWorkspaceDialog extends StatefulWidget {
  final WorkspaceApiService? api;
  const _CreateWorkspaceDialog({this.api});
  @override
  State<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<_CreateWorkspaceDialog> {
  late final WorkspaceApiService _api;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? WorkspaceApiService();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_submitting && _nameController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final ws = await _api.create(_nameController.text.trim());
      if (mounted) Navigator.of(context).pop(ws);
    } on WorkspaceApiException catch (e) {
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
          Icon(LucideIcons.circlePlus, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.workspacesCreateTitle),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.workspacesCreateNameLabel,
                  hintText: l10n.workspacesCreateNameHint,
                  prefixIcon: const Icon(LucideIcons.group, size: 18),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _canSubmit ? _submit() : null,
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return l10n.workspacesCreateRequired;
                  if (s.length > 100) return l10n.workspacesCreateTooLong;
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
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: Text(l10n.workspacesCancel),
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
          label: Text(l10n.workspacesCreateButton),
        ),
      ],
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
}
