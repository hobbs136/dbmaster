//! Join-workspace dialog (#26). Collects a workspace ID + invite code and POSTs
//! `/api/workspaces/:id/join` with `{invite_code}`.
//!
//! Two inputs are required because the Server route is shaped `:id/join`: it
//! verifies the invite code against the workspace identified by the path id
//! (the invite code is DB-unique, but the API still requires the id). A
//! share-invite therefore carries both — the members dialog's "Copy invite"
//! produces an id+code block for an admin to forward.
//!
//! Error mapping: an invalid code or already-a-member surfaces as 409 CONFLICT
//! (the Server returns a generic message and does not reveal which).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/workspace_api_service.dart';
import '../../../theme/app_colors.dart';

/// Shows the join-workspace dialog. Returns `true` on successful join (caller
/// refreshes its list), `null`/`false` on cancel.
Future<bool?> showJoinWorkspaceDialog(
  BuildContext context, {
  WorkspaceApiService? api,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _JoinWorkspaceDialog(api: api),
  );
}

class _JoinWorkspaceDialog extends StatefulWidget {
  final WorkspaceApiService? api;
  const _JoinWorkspaceDialog({this.api});
  @override
  State<_JoinWorkspaceDialog> createState() => _JoinWorkspaceDialogState();
}

class _JoinWorkspaceDialogState extends State<_JoinWorkspaceDialog> {
  late final WorkspaceApiService _api;
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _codeController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? WorkspaceApiService();
  }

  @override
  void dispose() {
    _idController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _idController.text.trim().isNotEmpty &&
      _codeController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.join(_idController.text.trim(), _codeController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
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
          Icon(LucideIcons.userPlus, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.workspacesJoinTitle),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _idController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.workspacesJoinIdLabel,
                  hintText: l10n.workspacesJoinIdHint,
                  prefixIcon: const Icon(LucideIcons.tag, size: 18),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) => (v?.trim() ?? '').isEmpty
                    ? l10n.workspacesJoinRequired
                    : null,
              ),
              const SizedBox(height: AppDesignSystem.space2),
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l10n.workspacesJoinCodeLabel,
                  hintText: l10n.workspacesJoinCodeHint,
                  prefixIcon: const Icon(LucideIcons.keyRound, size: 18),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) => (v?.trim() ?? '').isEmpty
                    ? l10n.workspacesJoinRequired
                    : null,
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Container(
                padding: const EdgeInsets.all(AppDesignSystem.space2),
                decoration: BoxDecoration(
                  color: colors.bgTertiary,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: colors.borderLight),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.info,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: AppDesignSystem.space1),
                    Expanded(
                      child: Text(
                        l10n.workspacesJoinHint,
                        style: AppTextStyles.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
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
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
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
              : const Icon(LucideIcons.logIn, size: 18),
          label: Text(l10n.workspacesJoinButton),
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
