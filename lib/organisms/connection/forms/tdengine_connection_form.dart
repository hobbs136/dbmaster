// C08 · TDengine 连接表单模块（插件形）。
//
// C08 拍板（2026-08-19）：维持 HTTP Basic 认证，不画 REST Token 字段
//（adapter 无 token 代码路径，c03 §1.2-15）。本地直连时代的 useSSL
// 同砍（死 UI）；网关 TLS 透传已开（showTlsToggle——server 侧
// taosAdapter 走 HTTPS）。既有超时字段经
// extra['timeout'] 镜像写入后对该类型实际生效（adapter 只读 extra，
// 不读一等字段 timeoutSeconds）。
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import 'connection_extra_keys.dart';
import 'network_connection_form.dart';

class TDengineConnectionFormSession extends NetworkConnectionFormSession {
  TDengineConnectionFormSession(super.ctx);

  @override
  String get usernameHint => 'root';

  @override
  bool get showSslToggle => false;

  /// 网关 TLS 透传（server 侧 taosAdapter HTTPS，经 draft extra 传两键）。
  @override
  bool get showTlsToggle => true;

  @override
  Map<String, dynamic>? buildExtra() => {
        ConnectionExtraKeys.tdTimeout:
            int.tryParse(timeoutController.text) ?? 30,
      };
}

class TDengineConnectionFormPlugin implements ConnectionFormPlugin {
  const TDengineConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'tdengine-connection-plugin',
        supportedTypes: const {DatabaseType.tdengine},
        source: PluginSource.databaseType,
        icon: DatabaseType.tdengine.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      TDengineConnectionFormSession(context);
}
