import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../providers/app_provider.dart';
import '../../providers/connection_provider.dart';
import '../../services/connection_export_import_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

enum ConnectionExportImportMode { export, import }

/// Dialog for exporting the current connections to an encrypted file or
/// importing them from a previously exported `.dbmconns` file.
class ConnectionExportImportDialog extends StatefulWidget {
  const ConnectionExportImportDialog({
    super.key,
    required this.mode,
    this.connectionsToExport,
  });

  final ConnectionExportImportMode mode;
  final List<DbServer>? connectionsToExport;

  static Future<void> showExport(
    BuildContext context, {
    List<DbServer>? connections,
  }) async {
    return showDialog(
      context: context,
      builder: (_) => ConnectionExportImportDialog(
        mode: ConnectionExportImportMode.export,
        connectionsToExport: connections,
      ),
    );
  }

  static Future<void> showImport(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (_) => const ConnectionExportImportDialog(
        mode: ConnectionExportImportMode.import,
      ),
    );
  }

  @override
  State<ConnectionExportImportDialog> createState() =>
      _ConnectionExportImportDialogState();
}

class _ConnectionExportImportDialogState
    extends State<ConnectionExportImportDialog> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedFilePath;
  ConnectionImportConflictStrategy _conflictStrategy =
      ConnectionImportConflictStrategy.rename;
  bool _isProcessing = false;
  String? _errorText;

  bool get _isExport => widget.mode == ConnectionExportImportMode.export;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.themeColors;
    final validationError = _validationError(l10n);
    return AlertDialog(
      backgroundColor: c.bgSecondary,
      title: Text(
        _isExport ? l10n.exportConnectionsTitle : l10n.importConnectionsTitle,
        style: TextStyle(color: c.textPrimary),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isExport) ...[
                if (widget.connectionsToExport != null &&
                    widget.connectionsToExport!.isNotEmpty)
                  Text(
                    '${l10n.exportConnectionsCount}: ${widget.connectionsToExport!.length}',
                    style: TextStyle(color: c.textSecondary),
                  )
                else
                  Text(
                    l10n.noConnectionsToExport,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if (!_isExport) ...[
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickImportFile,
                  icon: const Icon(LucideIcons.folderOpen),
                  label: Text(l10n.selectImportFile),
                ),
                if (_selectedFilePath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _selectedFilePath!,
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ConnectionImportConflictStrategy>(
                  initialValue: _conflictStrategy,
                  decoration: InputDecoration(
                    labelText: l10n.conflictStrategyLabel,
                    labelStyle: TextStyle(color: c.textMuted),
                    filled: true,
                    fillColor: c.bgTertiary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  dropdownColor: c.bgSecondary,
                  style: TextStyle(color: c.textPrimary, fontSize: 14),
                  items: [
                    DropdownMenuItem(
                      value: ConnectionImportConflictStrategy.skip,
                      child: Text(
                        l10n.conflictStrategySkip,
                        style: TextStyle(color: c.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: ConnectionImportConflictStrategy.rename,
                      child: Text(
                        l10n.conflictStrategyRename,
                        style: TextStyle(color: c.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: ConnectionImportConflictStrategy.overwrite,
                      child: Text(
                        l10n.conflictStrategyOverwrite,
                        style: TextStyle(color: c.textPrimary),
                      ),
                    ),
                  ],
                  onChanged: _isProcessing
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _conflictStrategy = value);
                          }
                        },
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _passwordController,
                obscureText: true,
                enabled: !_isProcessing,
                style: TextStyle(color: c.textPrimary),
                decoration: InputDecoration(
                  labelText: _isExport
                      ? l10n.exportPasswordHint
                      : l10n.importPasswordHint,
                  labelStyle: TextStyle(color: c.textMuted),
                  filled: true,
                  fillColor: c.bgTertiary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() => _errorText = null),
              ),
              if (_isExport) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  enabled: !_isProcessing,
                  style: TextStyle(color: c.textPrimary),
                  decoration: InputDecoration(
                    labelText: l10n.confirmExportPasswordHint,
                    labelStyle: TextStyle(color: c.textMuted),
                    filled: true,
                    fillColor: c.bgTertiary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => setState(() => _errorText = null),
                ),
              ],
              if (_errorText != null || validationError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText ?? validationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: Text(
            l10n.commonCancel,
            style: TextStyle(color: c.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _isProcessing || !_canSubmit ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.accentBlue,
            foregroundColor: Colors.white,
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isExport ? l10n.toolbarExport : l10n.toolbarImport),
        ),
      ],
    );
  }

  bool get _canSubmit {
    if (_passwordController.text.isEmpty) return false;
    if (_isExport) {
      if (widget.connectionsToExport?.isEmpty ?? true) return false;
      return _passwordController.text == _confirmPasswordController.text;
    }
    return _selectedFilePath != null;
  }

  String? _validationError(AppLocalizations l10n) {
    if (!_isExport) return null;
    if (_passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      return null;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      return l10n.passwordsDoNotMatch;
    }
    return null;
  }

  Future<void> _pickImportFile() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dbmconns'],
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _errorText = null;
        });
      }
    } catch (e, st) {
      if (!mounted) return;
      AppLogger.e('ConnectionExportImportDialog', 'pick file failed', e, st);
      setState(() => _errorText = l10n.selectImportFileFailed(e.toString()));
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isProcessing = true;
      _errorText = null;
    });

    final l10n = AppLocalizations.of(context)!;

    try {
      if (_isExport) {
        final success = await _doExport(l10n);
        if (!success) return;
      } else {
        // ConnectionProvider 是 AppProvider 的内部字段，未单独注入 Provider，
        // 因此通过 AppProvider 获取，避免导出时触发 ProviderNotFoundError。
        final provider = context.read<AppProvider>().connection;
        await _doImport(provider);
      }
      if (mounted) {
        final message = _isExport ? l10n.exportSuccess : l10n.importSuccess;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      AppLogger.e('ConnectionExportImportDialog', 'submit failed', e, st);
      if (mounted) {
        setState(() => _errorText = _errorMessage(e, l10n));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<bool> _doExport(AppLocalizations l10n) async {
    final connections = widget.connectionsToExport;
    if (connections == null || connections.isEmpty) {
      if (mounted) setState(() => _errorText = l10n.noConnectionsToExport);
      return false;
    }
    final encrypted = await ConnectionExportImportService.exportConnections(
      connections,
      _passwordController.text,
    );

    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: l10n.selectExportFile,
      fileName:
          'dbmaster_connections_${_formatDateTime(DateTime.now().toUtc())}.dbmconns',
      type: FileType.custom,
      allowedExtensions: ['dbmconns'],
    );

    if (outputFile != null) {
      await File(outputFile).writeAsString(encrypted);
      return true;
    }
    return false;
  }

  Future<void> _doImport(ConnectionProvider provider) async {
    final encrypted = await File(_selectedFilePath!).readAsString();
    final connections = await ConnectionExportImportService.importConnections(
      encrypted,
      _passwordController.text,
    );

    await provider.importConnections(connections, strategy: _conflictStrategy);
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_'
        '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';
  }

  String _errorMessage(Object e, AppLocalizations l10n) {
    if (_isExport) {
      if (e is ArgumentError || e is FormatException) {
        return l10n.invalidFile;
      }
      return l10n.exportFailed(e.toString());
    }

    if (e is FormatException) return l10n.invalidFile;
    if (e is FileSystemException) return l10n.importFailed(e.toString());
    return l10n.invalidPassword;
  }
}
