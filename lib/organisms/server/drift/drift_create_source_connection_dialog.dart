//! Dialog for adding a Server-side read-only source database connection
//! (`kind = "source_drift"`).
//!
//! The Server runs a create-time canary (`drift::canary` + the duplicate in
//! `automation::handler::run_create_canary`) and refuses writable accounts
//! with `CANARY_REJECTED`. We surface that error inline rather than letting
//! it bubble as a generic snackbar.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/drift_models.dart';
import '../../../services/drift_api_service.dart';
import '../../../theme/app_colors.dart';

/// Shows the create-source-connection dialog and returns the created
/// [DriftSourceConnection] on success (caller refreshes its list). Returns
/// `null` when the user cancels.
Future<DriftSourceConnection?> showDriftCreateSourceConnectionDialog(
  BuildContext context, {
  required DriftApiService api,
}) {
  return showDialog<DriftSourceConnection>(
    context: context,
    builder: (ctx) => _DriftCreateSourceConnectionDialog(api: api),
  );
}

class _DriftCreateSourceConnectionDialog extends StatefulWidget {
  final DriftApiService api;
  const _DriftCreateSourceConnectionDialog({required this.api});

  @override
  State<_DriftCreateSourceConnectionDialog> createState() =>
      _DriftCreateSourceConnectionDialogState();
}

class _DriftCreateSourceConnectionDialogState
    extends State<_DriftCreateSourceConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '3306');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _databaseController = TextEditingController();
  String _dbType = 'mysql';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _databaseController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _hostController.text.trim().isNotEmpty &&
      _usernameController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      !_submitting;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final port = int.tryParse(_portController.text.trim()) ?? 0;
      final conn = await widget.api.createSourceDriftConnection(
        name: _nameController.text.trim(),
        dbType: _dbType,
        host: _hostController.text.trim(),
        port: port,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        defaultDatabase: _databaseController.text.trim().isEmpty
            ? null
            : _databaseController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(conn);
    } on DriftApiException catch (e) {
      // CANARY_REJECTED, CREATE_FAILED, ENTITLEMENT_GATED — surface verbatim;
      // the Server already redacts SQL / credential detail.
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
          Icon(LucideIcons.link2, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.driftCreateSourceTitle),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dbTypeSelector(l10n, colors),
                const SizedBox(height: AppDesignSystem.space2),
                _textFormField(
                  controller: _nameController,
                  label: l10n.driftCreateTaskName,
                  icon: LucideIcons.tag,
                ),
                const SizedBox(height: AppDesignSystem.space2),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _textFormField(
                        controller: _hostController,
                        label: l10n.driftCreateSourceHost,
                        icon: LucideIcons.server,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Expanded(
                      flex: 1,
                      child: _textFormField(
                        controller: _portController,
                        label: l10n.driftCreateSourcePort,
                        icon: LucideIcons.hash,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space2),
                _textFormField(
                  controller: _usernameController,
                  label: l10n.driftCreateSourceUsername,
                  icon: LucideIcons.user,
                ),
                const SizedBox(height: AppDesignSystem.space2),
                _textFormField(
                  controller: _passwordController,
                  label: l10n.driftCreateSourcePassword,
                  icon: LucideIcons.lock,
                  obscure: true,
                ),
                const SizedBox(height: AppDesignSystem.space2),
                _textFormField(
                  controller: _databaseController,
                  label: l10n.driftCreateSourceDatabase,
                  icon: LucideIcons.database,
                  required: false,
                ),
                const SizedBox(height: AppDesignSystem.space3),
                Container(
                  padding: const EdgeInsets.all(AppDesignSystem.space2),
                  decoration: BoxDecoration(
                    color: colors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    border: Border.all(
                      color: colors.info.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.info, size: 16, color: colors.info),
                      const SizedBox(width: AppDesignSystem.space2),
                      Expanded(
                        child: Text(
                          l10n.driftCreateSourceCanaryNote,
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
          label: Text(l10n.driftCreateSourceSubmit),
        ),
      ],
    );
  }

  Widget _dbTypeSelector(AppLocalizations l10n, ThemeColors colors) {
    // Server v1 supports MySQL + PostgreSQL for source_drift (DbType in
    // crates/drift/src/snapshot.rs). Restricting here avoids a round-trip
    // rejection later for unsupported flavours.
    return DropdownButtonFormField<String>(
      // FormField.initialValue doesn't reflect setState-driven changes
      // (e.g. dbType swap); value: is intentional for this externally
      // controlled dropdown.
      // ignore: deprecated_member_use
      value: _dbType,
      decoration: _inputDecoration(
        l10n.driftCreateSourceDbType,
        LucideIcons.database,
      ),
      items: const [
        DropdownMenuItem(value: 'mysql', child: Text('MySQL')),
        DropdownMenuItem(value: 'postgres', child: Text('PostgreSQL')),
      ],
      onChanged: _submitting
          ? null
          : (v) => setState(() => _dbType = v ?? 'mysql'),
    );
  }

  Widget _textFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool required = true,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label, icon),
      validator: (value) {
        if (!required) return null;
        if (value == null || value.trim().isEmpty) return '$label is required';
        return null;
      },
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
}
