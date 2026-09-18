// C08 · PostgreSQL 连接表单模块（插件形）。
//
// 字段集 = 重建前对 pg 的分支：基础网络字段 + SSL bool。设计稿的
// Schema/search_path、SSL Mode 六档、Application Name 为超前项
//（adapter 仅支持 useSSL→SslMode.require/disable 二值，c03 §1.2-1/
// §2），登记 backlog 不画（与 CH/TD 拍板同精神）。
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import 'network_connection_form.dart';

class PostgresqlConnectionFormSession extends NetworkConnectionFormSession {
  PostgresqlConnectionFormSession(super.ctx);

  @override
  String get usernameHint => 'postgres';
}

class PostgresqlConnectionFormPlugin implements ConnectionFormPlugin {
  const PostgresqlConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'postgresql-connection-plugin',
        supportedTypes: const {DatabaseType.postgresql},
        source: PluginSource.databaseType,
        icon: DatabaseType.postgresql.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      PostgresqlConnectionFormSession(context);
}
