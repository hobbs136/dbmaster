import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// A dialog that prompts the user to enter a password before connecting to a
/// database server whose password was not saved.
///
/// Use [PasswordPromptDialog.ensurePassword] to conditionally show this dialog
/// only when the [DbServer.password] is missing and the database type requires
/// authentication.
class PasswordPromptDialog extends StatefulWidget {
  const PasswordPromptDialog({super.key, required this.server});

  final DbServer server;

  /// If [server] has no password and is not SQLite, shows the password prompt
  /// dialog. Returns the server with the password attached, or `null` if the
  /// user cancelled. Choosing "connect without password" returns the server
  /// unchanged — servers with no auth (e.g. Redis without AUTH) connect fine
  /// with no password, matching the connection-manager path.
  static Future<DbServer?> ensurePassword(
    BuildContext context,
    DbServer server,
  ) async {
    if (server.password != null && server.password!.isNotEmpty) {
      return server;
    }
    if (server.type == DatabaseType.sqlite) {
      return server;
    }

    final password = await showDialog<String>(
      context: context,
      builder: (_) => PasswordPromptDialog(server: server),
    );

    if (password == null) return null;
    if (password.isEmpty) return server;
    return server.copyWith(password: password);
  }

  @override
  State<PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _savePassword = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.themeColors;

    return AlertDialog(
      backgroundColor: c.bgSecondary,
      title: Text(
        l10n.passwordRequiredTitle,
        style: TextStyle(color: c.textPrimary),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.passwordRequiredMessage(widget.server.name),
              style: TextStyle(color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscureText,
              autofocus: true,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                labelText: l10n.connectionPassword,
                labelStyle: TextStyle(color: c.textMuted),
                filled: true,
                fillColor: c.bgTertiary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? LucideIcons.eyeOff : LucideIcons.eye,
                    color: c.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _savePassword,
              onChanged: (v) => setState(() => _savePassword = v ?? false),
              title: Text(
                l10n.connectionSavePassword,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: context.themeColors.accentBlue,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.commonCancel,
            style: TextStyle(color: c.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: Text(
            l10n.connectionConnectNoPassword,
            style: TextStyle(color: c.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _passwordController.text.isEmpty ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.accentBlue,
            foregroundColor: Colors.white,
          ),
          child: Text(l10n.connectionConnect),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    if (_savePassword) {
      try {
        await SecureStorageService.savePassword(widget.server.id, password);
        // 同时更新内存中的连接对象，使同一会话中断开重连时无需再次输入密码
        widget.server.password = password;
      } catch (e, stackTrace) {
        AppLogger.e(
          'PasswordPromptDialog',
          'Failed to save password',
          e,
          stackTrace,
        );
      }
    }

    if (mounted) {
      Navigator.of(context).pop(password);
    }
  }
}
