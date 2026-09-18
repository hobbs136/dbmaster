//! DbCapabilityPort —— 统一服务缝（c01_port_contract.md §2.2）。
//!
//! #33 铁律 1/2 的落点：UI / 插件只依赖本接口，不感知后端是本地 Dart 适配器
//! （[AdapterBacking]）还是 T27 网关（[GatewayBacking]，embedded 本地 server
//! 与远程 server 两形态行为一致——差异被 `ServerConnection` 的 baseUrl+token
//! 抽象吸收）。
//!
//! 落地节奏（§6）：C10 连接语义（testConnection / persistConnection /
//! removeConnection / connectionState）与能力位真值表；C13 执行通道
//! （GatewayBacking 真 SSE 流式 + 取消 / AdapterBacking 单批包装）；
//! Tier 1 元数据由 C14 实现（当前抛 [UnimplementedError]）。

import '../../models/database_models.dart';
import 'port_types.dart';

/// 能力位查询 + 元数据树 + 执行 + 连接配置语义的统一接口。
abstract interface class DbCapabilityPort {
  /// 能力位查询（静态位，sync：编译期表）。未知 id 返回 false。
  bool hasCapability(DatabaseType type, String capabilityId);

  /// 全量位集合（菜单装配 / 调试用）。
  Set<String> capabilitiesOf(DatabaseType type);

  /// 连接态位（readOnly / 模式）。异步：GatewayBacking 需查 server 注册值。
  Future<ConnectionState> connectionState(String connectionId);

  /// ── Tier 1 元数据（与 MCP 工具 / 网关 API 同源；C14 落地）──
  Future<List<String>> listDatabases(String connectionId);

  Future<List<TableSummary>> listTables(
    String connectionId, {
    String? database,
    String? schema,
  });

  Future<TableDescription> describeTable(
    String connectionId,
    String table, {
    String? database,
    String? schema,
  });

  /// ── 执行（§2.1；C13 落地）──
  ExecutionSession execute(String connectionId, ExecutionRequest request);

  /// ── 连接配置语义（C10 消费；§5）──

  /// 测试连接。AdapterBacking = 本地直连（现状 adapter 行为）；
  /// GatewayBacking = `POST /api/gw/connections/test` 远程调用（测试即远程）。
  Future<ConnectionTestResult> testConnection(DbServer draft);

  /// 网关语义的连接注册：GatewayBacking 把凭据交 server vault 并返回
  /// serverConnId；AdapterBacking 为本地 no-op 返回原 id（本地保存由
  /// ConnectionProvider 编排，非 port 职责）。
  Future<String> persistConnection(DbServer server);

  /// 注销连接。GatewayBacking = `DELETE /api/gw/connections/{id}`（幂等）；
  /// AdapterBacking no-op。id 语义同 [connectionState]。
  Future<void> removeConnection(String connectionId);
}

/// §2.4 Tier 2 扩展通道（过渡）：非 SQL 树数据 + Tier 1 未覆盖的对象类别。
///
/// v1 仅 AdapterBacking 实现（委托既有 adapter）；GatewayBacking 抛
/// [UnsupportedError]，可用性由能力位（`meta.<kind>`）门控。网关 v1.1+/v2
/// 按 kind 增补端点后逐项迁移；probe 是 port 的逃生舱，不是第二契约——
/// 方法随 C17/C18 重建按需追加。
abstract interface class MetadataProbe {
  /// kind: view|procedure|function|event|trigger|materializedView|sequence|
  /// schema|superTable|collection|…
  Future<List<String>> listObjects(
    String connectionId,
    String objectKind, {
    String? database,
    String? schema,
  });

  /// 版本/uptime 等（getServerVersion 镜像）。
  Future<Map<String, Object?>> serverInfo(String connectionId);
}
