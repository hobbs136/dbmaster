// C08 · ClickHouse 连接表单模块（插件形）。
//
// C08 拍板（2026-08-19）：按现状 wire 9004（MySQL-wire 兼容口），
// 不画设计稿的 HTTP 8123 / HTTP Interface URL / Compress 字段
//（c03 §1.2-14）——客户端 adapter 是 gateway 壳，server 侧
// ClickhouseBackend 走 9004；切 HTTP 需 server 返工，登记 backlog。
// SSL 同砍：网关注册/测试载荷不携带（死 UI）。SSH 已恢复——网关支持
// server 侧 SSH 隧道（配置随 draft 透传，见 network_connection_form）。
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import 'network_connection_form.dart';

class ClickhouseConnectionFormSession extends NetworkConnectionFormSession {
  ClickhouseConnectionFormSession(super.ctx);

  @override
  String get usernameHint => 'default';

  @override
  bool get showSslToggle => false;
}

class ClickhouseConnectionFormPlugin implements ConnectionFormPlugin {
  const ClickhouseConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'clickhouse-connection-plugin',
        supportedTypes: const {DatabaseType.clickhouse},
        source: PluginSource.databaseType,
        icon: DatabaseType.clickhouse.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      ClickhouseConnectionFormSession(context);
}
