//! Server-side connection registry management dialog (U05 / #32).
//!
//! Remote deployments historically had NO writer for the server's
//! `database_connections` table (the only one was the embedded-mode mirror),
//! so data_sync / health_check / approval creation dead-ended against an
//! empty registry. This dialog is that writer: list (`GET /api/connections`),
//! create (POST kind=collab), in-place edit (PUT — never delete+recreate,
//! which would CASCADE-delete referencing tasks), delete (DELETE with a
//! task-reference warning first).
//!
//! Mirrors `mcp_token_dialog.dart` structure (showXxxDialog + FutureBuilder
//! list + confirm-on-delete); the API client is
//! [ServerConnectionsApiService] (test-injectable via [api]).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/drift_models.dart';
import '../../../services/server_connections_api_service.dart';
import '../../../theme/app_colors.dart';

/// Opens the Server connections management dialog.
Future<void> showServerConnectionsDialog(
  BuildContext context, {
  ServerConnectionsApiService? api,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 680,
        height: 540,
        child: _ServerConnectionsDialog(api: api),
      ),
    ),
  );
}

class _ServerConnectionsDialog extends StatefulWidget {
  final ServerConnectionsApiService? api;

  const _ServerConnectionsDialog({this.api});

  @override
  State<_ServerConnectionsDialog> createState() =>
      _ServerConnectionsDialogState();
}

class _ServerConnectionsDialogState extends State<_ServerConnectionsDialog> {
  late final ServerConnectionsApiService _api;
  Future<List<DriftSourceConnection>>? _future;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ServerConnectionsApiService();
    _refresh();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  void _refresh() {
    // Not connected: build() short-circuits before FutureBuilder consumes
    // _future; skip the round-trip (would only reject + unhandled Future).
    if (!_api.isConnected) return;
    final future = _api.listConnections();
    // 对话框关闭时在途请求的拒绝无 FutureBuilder 监听者 → unhandled zone
    // error 打到 ErrorBoundary（2026-08-22 灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _l10n.serverConnectionsTitle,
                  style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final changed = await _openForm(null);
                  if (changed == true) _refresh();
                },
                icon: const Icon(LucideIcons.plus, size: 16),
                label: Text(_l10n.serverConnectionsAdd),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            _l10n.serverConnectionsIntro,
            style: AppTextStyles.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Expanded(
            child: !_api.isConnected
                ? _buildNotConnected(colors)
                : _buildList(colors),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnected(ThemeColors colors) {
    return Center(
      child: Text(
        _l10n.serverConnectionsNotConnected,
        style: AppTextStyles.body.copyWith(color: colors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildList(ThemeColors colors) {
    return FutureBuilder<List<DriftSourceConnection>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              snapshot.error.toString(),
              style: AppTextStyles.caption.copyWith(color: colors.error),
            ),
          );
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) return _buildEmpty(colors);
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _buildRow(colors, rows[i]),
        );
      },
    );
  }

  Widget _buildEmpty(ThemeColors colors) {
    return Center(
      child: Text(
        _l10n.serverConnectionsEmpty,
        style: AppTextStyles.body.copyWith(color: colors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRow(ThemeColors colors, DriftSourceConnection conn) {
    final busy = _busy.contains(conn.id);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        conn.dbType.toLowerCase() == 'sqlite'
            ? LucideIcons.fileText
            : LucideIcons.database,
        size: 18,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              conn.name,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          _kindChip(colors, conn),
        ],
      ),
      subtitle: Text(
        [
          conn.dbType,
          conn.hostLabel,
          if (conn.defaultDatabase != null && conn.defaultDatabase!.isNotEmpty)
            conn.defaultDatabase!,
        ].join(' · '),
        style: AppTextStyles.caption.copyWith(color: colors.textMuted),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _l10n.serverConnectionsEdit,
                  icon: const Icon(LucideIcons.pencil, size: 18),
                  onPressed: () async {
                    final changed = await _openForm(conn);
                    if (changed == true) _refresh();
                  },
                ),
                IconButton(
                  tooltip: _l10n.serverConnectionsDelete,
                  icon: Icon(LucideIcons.trash2, size: 18, color: colors.error),
                  onPressed: () => _delete(conn),
                ),
              ],
            ),
    );
  }

  Widget _kindChip(ThemeColors colors, DriftSourceConnection conn) {
    final drift = conn.isSourceDrift;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: (drift ? colors.warning : colors.accentBlue).withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: (drift ? colors.warning : colors.accentBlue).withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: Text(
        drift
            ? _l10n.serverConnectionsKindSourceDrift
            : _l10n.serverConnectionsKindCollab,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10,
          color: drift ? colors.warning : colors.accentBlue,
        ),
      ),
    );
  }

  /// Create ([existing] == null) or edit dialog. Returns true when a mutation
  /// landed (caller refreshes).
  Future<bool?> _openForm(DriftSourceConnection? existing) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) =>
          _ServerConnectionFormDialog(api: _api, existing: existing),
    );
  }

  Future<void> _delete(DriftSourceConnection conn) async {
    final l10n = _l10n;
    // Best-effort fetch of referencing tasks for the FK-cascade warning
    // (source references are CASCADE-deleted, target references detached).
    var refs = const <Map<String, dynamic>>[];
    try {
      final tasks = await _api.listTaskRefs();
      refs = tasks
          .where(
            (t) => t['source_db_id'] == conn.id || t['target_db_id'] == conn.id,
          )
          .toList();
    } catch (_) {
      // Warning degrades to the plain confirm when the fetch fails.
    }
    if (!mounted) return;
    final refNames = refs.map(
      (t) => (t['name'] as String?) ?? t['id'] as String? ?? '?',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.themeColors;
        return AlertDialog(
          title: Text(l10n.serverConnectionsDeleteTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.serverConnectionsDeleteBody(conn.name)),
              if (refs.isNotEmpty) ...[
                const SizedBox(height: AppDesignSystem.space2),
                Text(
                  l10n.serverConnectionsDeleteTaskWarning(refs.length),
                  style: AppTextStyles.caption.copyWith(color: colors.warning),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  refNames.take(5).join(', ') + (refs.length > 5 ? ', …' : ''),
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.serverConnectionsDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _busy.add(conn.id));
    try {
      await _api.deleteConnection(conn.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(conn.id));
    }
  }
}

/// db_type values the registry accepts (server canonical names).
const _kDbTypes = {
  'mysql': 3306,
  'postgres': 5432,
  'sqlite': 0,
  'clickhouse': 8123,
};

class _ServerConnectionFormDialog extends StatefulWidget {
  final ServerConnectionsApiService api;
  final DriftSourceConnection? existing;

  const _ServerConnectionFormDialog({required this.api, this.existing});

  @override
  State<_ServerConnectionFormDialog> createState() =>
      _ServerConnectionFormDialogState();
}

class _ServerConnectionFormDialogState
    extends State<_ServerConnectionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _databaseController = TextEditingController();
  final _filePathController = TextEditingController();

  late String _dbType;
  bool _portTouched = false;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;
  bool get _isSqlite => _dbType == 'sqlite';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _dbType = existing.dbType.toLowerCase();
      _nameController.text = existing.name;
      _hostController.text = existing.dbType.toLowerCase() == 'sqlite'
          ? ''
          : existing.host;
      _portController.text = '${existing.port}';
      _usernameController.text =
          existing.username == 'sqlite' &&
              existing.dbType.toLowerCase() == 'sqlite'
          ? ''
          : existing.username;
      _databaseController.text = existing.defaultDatabase ?? '';
      _filePathController.text = existing.filePath ?? '';
    } else {
      _dbType = 'mysql';
      _portController.text = '${_kDbTypes['mysql']}';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _databaseController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        final existing = widget.existing!;
        // Omitted password = keep the stored ciphertext (server-side PUT
        // semantics); every other field is sent so the form is WYSIWYG.
        await widget.api.updateConnection(
          existing.id,
          name: _nameController.text.trim(),
          dbType: _dbType,
          host: _isSqlite ? 'sqlite' : _hostController.text.trim(),
          port: _isSqlite
              ? 0
              : (int.tryParse(_portController.text.trim()) ?? 0),
          username: _isSqlite ? 'sqlite' : _usernameController.text.trim(),
          password: _passwordController.text,
          defaultDatabase: _databaseController.text.trim().isEmpty
              ? null
              : _databaseController.text.trim(),
          filePath: _isSqlite ? _filePathController.text.trim() : null,
        );
      } else {
        await widget.api.createConnection(
          name: _nameController.text.trim(),
          dbType: _dbType,
          host: _isSqlite ? 'sqlite' : _hostController.text.trim(),
          port: _isSqlite
              ? 0
              : (int.tryParse(_portController.text.trim()) ?? 0),
          username: _isSqlite ? 'sqlite' : _usernameController.text.trim(),
          password: _isSqlite ? '' : _passwordController.text,
          defaultDatabase: _databaseController.text.trim().isEmpty
              ? null
              : _databaseController.text.trim(),
          filePath: _isSqlite ? _filePathController.text.trim() : null,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ServerConnectionsApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = _l10n;
    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.database, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            _isEdit
                ? l10n.serverConnFormEditTitle
                : l10n.serverConnFormCreateTitle,
          ),
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
                TextFormField(
                  controller: _nameController,
                  decoration: _input(l10n.serverConnFormName),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.serverConnFormRequired
                      : null,
                ),
                const SizedBox(height: AppDesignSystem.space2),
                DropdownButtonFormField<String>(
                  // `value` (not `initialValue`) so the field tracks external
                  // setState updates — mirrors the other server dialogs.
                  // ignore: deprecated_member_use
                  value: _dbType,
                  decoration: _input(l10n.serverConnFormType),
                  items: _kDbTypes.keys
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _dbType = v);
                          // Reset the port to the new type's default unless
                          // the user customized it.
                          if (!_portTouched) {
                            _portController.text = '${_kDbTypes[v]}';
                          }
                        },
                ),
                if (_isSqlite) ...[
                  const SizedBox(height: AppDesignSystem.space2),
                  TextFormField(
                    controller: _filePathController,
                    decoration: _input(l10n.serverConnFormSqlitePath),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.serverConnFormRequired
                        : null,
                  ),
                ] else ...[
                  const SizedBox(height: AppDesignSystem.space2),
                  TextFormField(
                    controller: _hostController,
                    decoration: _input(l10n.serverConnFormHost),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.serverConnFormRequired
                        : null,
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  TextFormField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: _input(l10n.serverConnFormPort),
                    onChanged: (_) => _portTouched = true,
                    validator: (v) => int.tryParse((v ?? '').trim()) == null
                        ? l10n.serverConnFormInvalidPort
                        : null,
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  TextFormField(
                    controller: _usernameController,
                    decoration: _input(l10n.serverConnFormUsername),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: _input(l10n.serverConnFormPassword).copyWith(
                      // Edit mode: blank keeps the stored secret.
                      helperText: _isEdit
                          ? l10n.serverConnFormPasswordKeepHint
                          : null,
                    ),
                    validator: (v) {
                      if (_isEdit || _isSqlite) return null;
                      return (v == null || v.isEmpty)
                          ? l10n.serverConnFormRequired
                          : null;
                    },
                  ),
                ],
                const SizedBox(height: AppDesignSystem.space2),
                TextFormField(
                  controller: _databaseController,
                  decoration: _input(l10n.serverConnFormDatabase),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppDesignSystem.space2),
                  Container(
                    padding: const EdgeInsets.all(AppDesignSystem.space2),
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      border: Border.all(
                        color: colors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SelectableText(
                      _error!,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
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
          child: Text(l10n.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.save, size: 18),
          label: Text(l10n.serverConnFormSave),
        ),
      ],
    );
  }

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    border: const OutlineInputBorder(),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppDesignSystem.space3,
      vertical: AppDesignSystem.space2,
    ),
  );
}
