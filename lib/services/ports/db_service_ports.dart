//! port 路由器 —— 迁移协调矩阵的编译期落点（「迁移协调矩阵」铁律）。
//!
//! 每个类型固定路由到 AdapterBacking（未迁移，本地 adapter 直连）或
//! GatewayBacking（已迁移，走网关；embedded/远程两形态行为一致）。路由是
//! 编译期常量而非用户配置——port 铁律验收点：某类型后端切换（T28 SQL Server
//! 首发、T29 滚动迁移）= 只改 [_gatewayBackedTypes] 一处 + 删 adapter，UI 与
//! ConnectionProvider 编排零改动。
//!
//! 当前（2026-08-26，T29 第三批落地）：SQL Server（T28）+ MySQL 协议族
//! 六成员（mysql/doris/oceanbase/tidb/starrocks/mariadb）+ PostgreSQL +
//! ClickHouse 走 GatewayBacking（连接语义），数据面经 *_gateway_adapter
//! （网关壳 adapter）；sqlite 与非 SQL 三类型维持 AdapterBacking。

import 'package:http/http.dart' as http;

import '../../models/database_models.dart';
import '../database_service.dart';
import '../server_connection.dart';
import 'adapter_backing.dart';
import 'db_capability_port.dart';
import 'gateway_backing.dart';

/// 网关迁移白名单。T28 加入 `DatabaseType.sqlserver`（2026-08-19）；T29
/// 加入 MySQL 协议族全六成员（mysql/doris/oceanbase/tidb/starrocks/mariadb，
/// 网关壳 adapter 见 mysql_gateway_adapter.dart）+ postgresql（第二批）+
/// clickhouse（第三批，2026-08-26，壳 = clickhouse_adapter.dart 原地重写）；
/// 非 SQL（mongo/redis/tdengine）与 sqlite 在网关 v2 前维持 Adapter
/// （sqlite 已拍板永久豁免，ADR-0005 §2.1 修订）。
const Set<DatabaseType> _gatewayBackedTypes = {
  DatabaseType.sqlserver,
  DatabaseType.mysql,
  DatabaseType.doris,
  DatabaseType.oceanbase,
  DatabaseType.tidb,
  DatabaseType.starrocks,
  DatabaseType.mariadb,
  DatabaseType.postgresql,
  DatabaseType.clickhouse,
};

/// 按类型解析 port 实例。持有单例形态的双 backing（均无状态）。
class DbServicePorts {
  DbServicePorts({
    required DatabaseService adapterDbService,
    DbServer? Function(String connectionId)? connectionLookup,
    ServerConnection? serverConnection,
    http.Client? gatewayHttpClient,
  }) : _adapter = AdapterBacking(
         dbService: adapterDbService,
         connectionLookup: connectionLookup,
       ),
       _gateway = GatewayBacking(
         connection: serverConnection,
         httpClient: gatewayHttpClient,
       );

  final AdapterBacking _adapter;
  final GatewayBacking _gateway;

  /// 该类型是否路由到网关（测试与 UI 门控共用）。
  static bool isGatewayBacked(DatabaseType type) =>
      _gatewayBackedTypes.contains(type);

  DbCapabilityPort resolveFor(DatabaseType type) =>
      isGatewayBacked(type) ? _gateway : _adapter;
}
