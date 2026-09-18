// C08 · Doris 连接表单模块（插件形）。
//
// 字段集与 MySQL 完全一致（MySQL 协议兼容，charset 含 gbk——c03 §2
// 核对一致），复用 [SqlConnectionFormSession]。
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import 'mysql_connection_form.dart';

class DorisConnectionFormSession extends SqlConnectionFormSession {
  DorisConnectionFormSession(super.ctx) {
    selectedCharset = initial.charset;
    selectedTimezone = initial.timezone;
  }
}

class DorisConnectionFormPlugin implements ConnectionFormPlugin {
  const DorisConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'doris-connection-plugin',
        supportedTypes: const {DatabaseType.doris},
        source: PluginSource.databaseType,
        icon: DatabaseType.doris.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      DorisConnectionFormSession(context);
}
