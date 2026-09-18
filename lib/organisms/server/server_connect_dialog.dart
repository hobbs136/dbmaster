//! Modal dialog for connecting to a DbMaster team server.
//!
//! Prompts for server URL, email, and password. Validates inputs,
//! shows connection progress, and displays errors.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/server_connection_provider.dart';
import '../../services/server_connection.dart';
import '../../services/telemetry_service.dart';
import '../../theme/app_colors.dart';

/// Landing page for "don't have a server?" link — emitted as
/// `server_download_clicked` per telemetry-funnel-plan §4.3.
/// TODO(marketing): final URL pending; harmless default for now.
const String _kServerDownloadUrl = 'https://dbmaster.tech-site/server/download';

/// Shows the server connect dialog and returns `true` if connected successfully.
Future<bool> showServerConnectDialog(
  BuildContext context,
  ServerConnectionProvider provider,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ServerConnectDialog(provider: provider),
  ).then((result) => result ?? false);
}

class _ServerConnectDialog extends StatefulWidget {
  final ServerConnectionProvider provider;

  const _ServerConnectDialog({required this.provider});

  @override
  State<_ServerConnectDialog> createState() => _ServerConnectDialogState();
}

class _ServerConnectDialogState extends State<_ServerConnectDialog> {
  final _urlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _connecting = false;
  String? _error;
  bool _hasStoredSession = false;

  @override
  void initState() {
    super.initState();
    _prefillFromStoredSession();
  }

  /// Prefill URL/email from the last successful sign-in (only the password
  /// needs re-entry after a session expiry) and note whether a refresh token
  /// is stored (enables the one-click "reconnect to last server" button).
  Future<void> _prefillFromStoredSession() async {
    final stored = await ServerConnection().readStoredSession();
    if (stored == null || !mounted) return;
    setState(() {
      _urlController.text = stored.url;
      if (stored.email != null) _emailController.text = stored.email!;
      _hasStoredSession = stored.hasRefreshToken;
    });
  }

  /// One-click reconnect via the stored refresh token — no password needed.
  /// Covers the transient-disconnect / session-expired recovery path.
  Future<void> _reconnectLastSession() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final restored = await widget.provider.tryRestoreSession();
    if (!mounted) return;
    if (restored) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = AppLocalizations.of(context)!.serverReconnectFailed;
        _connecting = false;
      });
    }
  }

  bool get _canSubmit {
    return _urlController.text.trim().isNotEmpty &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        !_connecting;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      await widget.provider.connect(
        _urlController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ServerConnectionException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _connecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context)!.serverConnectUnexpectedError;
          _connecting = false;
        });
      }
    }
  }

  Future<void> _launchServerDownloadUrl() async {
    // Record the click before opening the URL so the count is captured even
    // if the launcher silently fails.
    TelemetryService.instance.logServerDownloadClick(
      _kServerDownloadUrl,
      source: 'connect_dialog',
    );
    final uri = Uri.parse(_kServerDownloadUrl);
    try {
      await launchUrl(uri);
    } catch (_) {
      // Best-effort launch; click already counted.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.serverConnectTitle),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Server URL
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: l10n.serverConnectUrl,
                  hintText: 'https://myserver:3000',
                  prefixIcon: Icon(LucideIcons.server),
                ),
                keyboardType: TextInputType.url,
                enabled: !_connecting,
                // Rebuild on each keystroke so _canSubmit re-evaluates and the
                // Connect button enables once fields are filled.
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return l10n.serverUrlRequired;
                  }
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                    return l10n.serverUrlInvalid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppDesignSystem.space3),

              // Email
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: l10n.serverConnectEmail,
                  prefixIcon: Icon(LucideIcons.mail),
                ),
                keyboardType: TextInputType.emailAddress,
                enabled: !_connecting,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return l10n.serverEmailRequired;
                  }
                  if (!v.contains('@')) return l10n.serverEmailInvalid;
                  return null;
                },
              ),
              const SizedBox(height: AppDesignSystem.space3),

              // Password
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: l10n.connectionPassword,
                  prefixIcon: Icon(LucideIcons.lock),
                ),
                obscureText: true,
                enabled: !_connecting,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return l10n.serverPasswordRequired;
                  }
                  return null;
                },
                onFieldSubmitted: _canSubmit ? (_) => _connect() : null,
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: AppDesignSystem.space3),
                Container(
                  padding: const EdgeInsets.all(AppDesignSystem.space2),
                  decoration: BoxDecoration(
                    color: context.themeColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    border: Border.all(
                      color: context.themeColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.circleAlert,
                        size: 16,
                        color: context.themeColors.error,
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppTextStyles.body.copyWith(
                            color: context.themeColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // One-click reconnect with the stored session (refresh token).
              if (_hasStoredSession && !_connecting) ...[
                const SizedBox(height: AppDesignSystem.space3),
                OutlinedButton.icon(
                  onPressed: _reconnectLastSession,
                  icon: const Icon(LucideIcons.history, size: 16),
                  label: Text(l10n.serverReconnectLastSession),
                ),
              ],

              // "Don't have a server? Learn more" link — emits
              // `server_download_clicked` per telemetry-funnel-plan §4.3.
              if (!_connecting) ...[
                const SizedBox(height: AppDesignSystem.space3),
                Center(
                  child: InkWell(
                    onTap: _launchServerDownloadUrl,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space1,
                        vertical: 2,
                      ),
                      child: Text(
                        l10n.serverConnectNoServerLearnMore,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: context.themeColors.accentBlue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // Spinner
              if (_connecting) ...[
                const SizedBox(height: AppDesignSystem.space3),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _connecting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _canSubmit ? _connect : null,
          child: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.connectionConnect),
        ),
      ],
    );
  }
}
