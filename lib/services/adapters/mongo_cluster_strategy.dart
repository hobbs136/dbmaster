import '../database_abstract.dart';

/// MongoDB 集群（副本集 / 分片）连接 URI 构建策略（open-core SPI，ADR 0001）。
///
/// 公开仓（OSS）的 [MongoDBAdapter] 仅支持 Direct 单主机连接；集群拓扑
/// （replicaSet / sharded）的 URI 构建属 Pro 能力，经此策略注入。
/// OSS 构建（`main_oss.dart`）不注入实现——adapter 在遇到集群模式时抛
/// [UnsupportedError]（fail-loud：不静默降级为单主机，以免连到错误拓扑）。
///
/// **不进 URI 的凭据契约**：与 Direct 路径一致，[buildUri] 返回的 URI 不含
/// 用户名/密码——认证由 adapter 经 `Db.authenticate` 单独完成（密码绝不进 URI）。
///
/// 遵循宪法 IV.3（Adapter 插件式）—— 集群能力经 strategy 注入，非 adapter 内置。
abstract class MongoClusterStrategy {
  const MongoClusterStrategy();

  /// 此策略是否处理给定的连接模式（读取自 `connection.extra['mongoConnectionMode']`，
  /// 如 `'replicaSet'` / `'sharded'`）。OSS adapter 据此决定是否委托。
  bool handles(String mode);

  /// 构建集群连接 URI（无凭据）。实现按 `connection.extra['mongoConnectionMode']`
  /// 自行分发 replicaSet / sharded 的 seed-list 与 query 参数组装。
  String buildUri(
    DatabaseConnection connection,
    String? targetDatabase, {
    String? authDatabase,
  });
}
