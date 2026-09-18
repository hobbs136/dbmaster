import 'package:dbmaster/services/adapters/mongo_cluster_strategy.dart';
import 'package:dbmaster/services/database_abstract.dart';

/// MongoDB 集群（副本集 / 分片）连接 URI 构建策略（Pro 实现，open-core B.2）。
///
/// 从 OSS 的 `lib/services/adapters/mongodb_adapter.dart` 历史方法
/// `_buildReplicaSetUri` / `_buildShardedUri` / `_readMongoHosts` 字节级
/// 移植（commit 03a7f182^ 前的算法）。算法保持不变的契约由
/// `pro_staging/test/services/adapters/mongodb_replicaset_uri_test.dart`
/// 钉住（replicaSet/sharded URI shape）。
///
/// **不进 URI 的凭据契约**：返回的 URI 不含 username/password——认证由
/// `MongoDBAdapter._authenticate` 单独完成（密码绝不进 URI，FR-007）。
class ClusterMongoUriStrategy implements MongoClusterStrategy {
  const ClusterMongoUriStrategy();

  /// 此策略处理 `replicaSet` 与 `sharded` 两种模式（其它模式交回 adapter）。
  @override
  bool handles(String mode) => mode == 'replicaSet' || mode == 'sharded';

  /// 按 `connection.extra['mongoConnectionMode']` 分发到副本集 / 分片 URI 构建器。
  @override
  String buildUri(
    DatabaseConnection connection,
    String? targetDatabase, {
    String? authDatabase,
  }) {
    final mode = _connectionMode(connection);
    switch (mode) {
      case 'replicaSet':
        return _buildReplicaSetUri(
          connection,
          targetDatabase,
          authDatabase: authDatabase,
        );
      case 'sharded':
        return _buildShardedUri(
          connection,
          targetDatabase,
          authDatabase: authDatabase,
        );
      default:
        // 防御：[handles] 仅对 replicaSet/sharded 返回 true，理论上不会走到这里；
        // fail-loud 提示调用方策略注入模式与分发不一致。
        throw UnsupportedError(
          'ClusterMongoUriStrategy 不处理模式 "$mode"；'
          'adapter 应在 strategy.handles 返回 false 时直接走 Direct 路径。',
        );
    }
  }

  /// 连接模式读取自 `connection.extra['mongoConnectionMode']`，默认 'direct'。
  /// 算法与 OSS `MongoDBAdapter._mongoConnectionMode` 完全一致。
  String _connectionMode(DatabaseConnection connection) =>
      (connection.extra?['mongoConnectionMode'] as String?) ?? 'direct';

  /// 多主机副本集 seed-list URI。`replicaSet=` 参数被 mongo_dart 忽略（驱动
  /// 自行发现 primary），但仍发射——用于 post-connect 名称校验（PD-5）与
  /// 保留用户意图。无凭据。
  String _buildReplicaSetUri(
    DatabaseConnection connection,
    String? targetDatabase, {
    String? authDatabase,
  }) {
    final hosts = _readMongoHosts(connection);
    final buffer = StringBuffer('mongodb://');
    buffer.write(hosts.join(','));
    if (targetDatabase != null && targetDatabase.isNotEmpty) {
      buffer.write('/${Uri.encodeComponent(targetDatabase)}');
    }
    final query = <String>[];
    final rsName = (connection.extra?['mongoReplicaSet'] as String?)?.trim();
    if (rsName != null && rsName.isNotEmpty) {
      query.add('replicaSet=${Uri.encodeQueryComponent(rsName)}');
    }
    final authSrc = (authDatabase != null && authDatabase.isNotEmpty)
        ? authDatabase
        : 'admin';
    query.add('authSource=${Uri.encodeQueryComponent(authSrc)}');
    buffer.write('?${query.join('&')}');
    return buffer.toString();
  }

  /// 多 mongos seed-list URI（分片集群）。**不带 `replicaSet=` 参数**
  /// （mongos 自报 isWritablePrimary，PD-10）。无凭据。
  String _buildShardedUri(
    DatabaseConnection connection,
    String? targetDatabase, {
    String? authDatabase,
  }) {
    final hosts = _readMongoHosts(connection);
    final buffer = StringBuffer('mongodb://');
    buffer.write(hosts.join(','));
    if (targetDatabase != null && targetDatabase.isNotEmpty) {
      buffer.write('/${Uri.encodeComponent(targetDatabase)}');
    }
    final authSrc = (authDatabase != null && authDatabase.isNotEmpty)
        ? authDatabase
        : 'admin';
    buffer.write('?authSource=${Uri.encodeQueryComponent(authSrc)}');
    return buffer.toString();
  }

  /// 从 `connection.extra['mongoHosts']` 读取并清理 seed-list；缺失时回退到
  /// 单机 `host:port`（防御性，保持与原 adapter 实现一致的回退行为）。
  List<String> _readMongoHosts(DatabaseConnection connection) {
    final raw = connection.extra?['mongoHosts'];
    if (raw is List) {
      final list = raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    }
    return ['${connection.host}:${connection.port}'];
  }
}
