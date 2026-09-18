// C08 · SQLite 连接表单模块（插件形）。
//
// 字段集 = 原 SQLiteConnectionDialog 的表单段（路径 + 只读）并入新结构
//（C09 旧文件已删）：
// - 路径落 DbServer.host（既有约定，port=0）、用户名/密码不适用
// - readOnly 一等字段（feature 039 只读守卫消费）
// - 「附加数据库」维持运行时树操作语义（c03 §2：表单不画 attach 列表）；
//   加密密码 / journalMode / foreignKeys 为 adapter 未支持的超前项（backlog）
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../theme/app_theme.dart';
import 'connection_form_fields.dart';

class SqliteConnectionFormSession extends ChangeNotifier
    implements ConnectionFormSession {
  SqliteConnectionFormSession(this.ctx) {
    final s = ctx.draft.value;
    pathController = TextEditingController(text: s.host);
    readOnly = s.readOnly;
  }

  final ConnectionFormPluginContext ctx;

  late final TextEditingController pathController;
  bool readOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConnectionTextField(
            controller: pathController,
            label: l10n.connectionDbFile,
            hint: '/path/to/database.db',
            icon: LucideIcons.folderOpen,
            validator: (v) =>
                v?.isEmpty ?? true ? l10n.connectionDbFileRequired : null,
            suffix: IconButton(
              icon: Icon(
                LucideIcons.folderOpen,
                size: 18,
                color: context.themeColors.textMuted,
              ),
              onPressed: () => _pickFile(context),
            ),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          ConnectionSwitchTile(
            title: l10n.connectionReadOnlyMode,
            subtitle: l10n.connectionReadOnlyModeDesc,
            value: readOnly,
            onChanged: (v) {
              readOnly = v;
              notifyListeners();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: l10n.connectionSelectDbFile,
    );
    if (result != null && result.files.isNotEmpty) {
      pathController.text = result.files.first.path ?? '';
    }
  }

  @override
  DbServer? collect({bool forSave = false}) {
    if (pathController.text.isEmpty) return null;
    final v = ctx.draft.value;
    return DbServer(
      id: v.id,
      name: v.name,
      type: DatabaseType.sqlite,
      host: pathController.text,
      port: 0,
      useSSL: false,
      timeoutSeconds: v.timeoutSeconds,
      autoReconnect: false,
      charset: v.charset,
      groupId: v.groupId,
      lastConnected: v.lastConnected,
      environment: v.environment,
      readOnly: readOnly,
      extra: v.extra,
    );
  }

  @override
  void dispose() {
    pathController.dispose();
    super.dispose();
  }
}

class SqliteConnectionFormPlugin implements ConnectionFormPlugin {
  const SqliteConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'sqlite-connection-plugin',
        supportedTypes: const {DatabaseType.sqlite},
        source: PluginSource.databaseType,
        icon: DatabaseType.sqlite.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      SqliteConnectionFormSession(context);
}
