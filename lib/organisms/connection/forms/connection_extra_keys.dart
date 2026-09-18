// C08 · per-type 连接表单 —— `DbServer.extra` 键常量表。
//
// 依据 `c03_design_contract_review.md` §2 extra 键初稿 + C08 核实/拍板结论：
// - **已有持久化键逐字保留**（spec 044 Mongo 集群四键、TDengine `timeout`），
//   防止 adapter 读取侧断裂；键名收敛进本表，表单内禁止裸写字符串键。
// - **设计稿超前字段不落键**（c03 §1.2 backlog，与 CH wire 9004 / TD 维持
//   Basic 两项拍板同精神）：PG sslMode 六档/search_path/applicationName、
//   SQLite journalMode/foreignKeys/加密密码、CH HTTP 8123/Compress/
//   maxConcurrentQueries、TD REST Token、Mongo readPreference——adapter 无
//   对应代码路径，画进表单即死 UI。待 adapter 支持后在此登记新键再上 UI。
abstract final class ConnectionExtraKeys {
  // ── Mongo 集群（spec 044，现状键）──────────────────────────────

  /// 集群模式：direct / replicaSet / sharded / advanced。
  static const String mongoConnectionMode = 'mongoConnectionMode';

  /// 种子/路由节点列表（List<String>，`host[:port]`）。
  static const String mongoHosts = 'mongoHosts';

  /// 副本集名称（replicaSet 模式）。
  static const String mongoReplicaSet = 'mongoReplicaSet';

  /// 高级模式连接串（**已剥离凭据**，FR-007；密码只走 DbServer.password）。
  static const String mongoConnectionString = 'mongoConnectionString';

  // ── TDengine ─────────────────────────────────────────────────

  /// REST 查询超时（秒，int）——`tdengine_adapter.executeQuery` 消费。
  /// 表单从 timeoutSeconds 镜像写入，使超时字段对该类型实际生效
  /// （现状 adapter 不读一等字段 timeoutSeconds，读 extra['timeout']）。
  static const String tdTimeout = 'timeout';
}
