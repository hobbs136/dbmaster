// SPDX-License-Identifier: Apache-2.0
//
// spec 050：SQLite ATTACH 跨库对话框。
//
// 流程：FilePicker 选 .db 文件 → alias 自动填去扩展名文件名（可改）→
// 失焦实时校验（SqliteAliasValidator）→ Attach 返回 (path, alias)。
//
// 调用方（sqlite_tree_builder._showAttachDialog）拿到结果后调
// provider.connection.attachDatabase + SnackBar 反馈。
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../services/sqlite_alias_validator.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// AttachDatabaseDialog 返回值：用户确认的 (path, alias)。
class AttachResult {
  final String path;
  final String alias;
  const AttachResult(this.path, this.alias);
}

/// spec 050：附加 SQLite 数据库文件到当前连接的对话框。
///
/// 用法：
/// ```dart
/// final result = await showDialog<_AttachResult?>(
///   context: context,
///   builder: (_) => AttachDatabaseDialog(connectionId: connectionId),
/// );
/// ```
/// result 为 null 表示用户取消。
class AttachDatabaseDialog extends StatefulWidget {
  /// 当前连接 ID（用于查已附加 alias 列表做重复校验）。
  final String connectionId;

  const AttachDatabaseDialog({super.key, required this.connectionId});

  @override
  State<AttachDatabaseDialog> createState() => _AttachDatabaseDialogState();
}

class _AttachDatabaseDialogState extends State<AttachDatabaseDialog> {
  final _pathController = TextEditingController();
  final _aliasController = TextEditingController();
  String? _pathError;
  String? _aliasError;

  @override
  void dispose() {
    _pathController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  /// 选文件：弹系统文件对话框，选 .db/.sqlite/.sqlite3/.db3。
  Future<void> _pickFile() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db', 'sqlite', 'sqlite3', 'db3'],
        allowMultiple: false,
        dialogTitle: l10n.sqliteAttachDatabase,
      );
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path!;
        final filename = result.files.first.name;
        setState(() {
          _pathController.text = path;
          _pathError = null;
          // alias 默认 = 去扩展名文件名，仅当用户未手改时自动填
          if (_aliasController.text.isEmpty) {
            _aliasController.text = _stripExtension(filename);
          }
          _validateAlias();
        });
      }
    } catch (e) {
      AppLogger.e('AttachDatabaseDialog', 'pick file failed', e);
    }
  }

  String _stripExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  /// 实时校验 alias（用 SqliteAliasValidator）。
  void _validateAlias() {
    final alias = _aliasController.text.trim();
    if (alias.isEmpty) {
      setState(() => _aliasError = null);
      return;
    }
    // existing 列表暂不查 provider（dialog 不持有 provider），重复校验由
    // provider.attachDatabase 前置校验兜底（返回 sqliteAttachAliasDuplicate）。
    final err = SqliteAliasValidator.validate(alias);
    setState(() => _aliasError = err);
  }

  bool get _canAttach =>
      _pathController.text.isNotEmpty &&
      _aliasController.text.trim().isNotEmpty &&
      _aliasError == null &&
      _pathError == null;

  void _submit() {
    final path = _pathController.text.trim();
    final alias = _aliasController.text.trim();
    if (path.isEmpty || alias.isEmpty || _aliasError != null) return;
    Navigator.of(context).pop(AttachResult(path, alias));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.link, color: context.themeColors.accentGreen),
          const SizedBox(width: 8),
          Text(l10n.sqliteAttachDatabase),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File 选择行
            Text(l10n.sqliteAttachFileLabel),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: l10n.sqliteAttachFileHint,
                      errorText: _pathError,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _pickFile,
                  icon: const Icon(LucideIcons.folderOpen, size: 20),
                  tooltip: l10n.sqliteAttachPickFile,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Alias 输入
            Text(l10n.sqliteAttachAliasLabel),
            const SizedBox(height: 4),
            TextField(
              controller: _aliasController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.sqliteAttachAliasHint,
                errorText: _aliasError == null
                    ? null
                    : _localizeError(_aliasError!),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _validateAlias(),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.sqliteAttachAliasHelp,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.themeColors.textMuted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton.icon(
          onPressed: _canAttach ? _submit : null,
          icon: const Icon(LucideIcons.link, size: 18),
          label: Text(l10n.sqliteAttachButton),
        ),
      ],
    );
  }

  String _localizeError(String errorKey) {
    final l10n = AppLocalizations.of(context)!;
    switch (errorKey) {
      case 'sqliteAttachAliasInvalid':
        return l10n.sqliteAttachAliasInvalid;
      case 'sqliteAttachAliasReserved':
        return l10n.sqliteAttachAliasReserved;
      case 'sqliteAttachAliasKeyword':
        return l10n.sqliteAttachAliasKeyword;
      case 'sqliteAttachAliasDuplicate':
        return l10n.sqliteAttachAliasDuplicate;
      default:
        return errorKey;
    }
  }
}
