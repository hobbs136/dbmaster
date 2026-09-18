//! DbCapabilityPort 契约类型（c01_port_contract.md §2 的 Dart 落地）。
//!
//! 本文件只放**形状**：与网关 wire 同源的 DTO（§2.0）、执行通道类型（§2.1）、
//! 连接语义类型（§2.2 前置）与统一异常。接口本体在 `db_capability_port.dart`，
//! 能力真值表在 `capability_table.dart`，双实现（AdapterBacking /
//! GatewayBacking）见同目录。
//!
//! 字段命名与 automation `metadata.rs` serde 结构逐一对应（camelCase +
//! skip_serializing_if 的 Optional 字段在 Dart 侧为可空）；GatewayBacking 是
//! `DatabaseType` 枚举 ↔ wire 小写字符串的唯一换算点（§4.5）。

import 'dart:async';

import '../../models/database_models.dart';

// ============================================================================
// §2.0 Tier 1 元数据 DTO（与 MCP 工具 / 网关 API 同源）
// ============================================================================

/// 表/视图摘要（`list_tables` 行）。
class TableSummary {
  final String name;
  final String kind; // "table" | "view"
  final String? comment; // 引擎没有则 null（wire 省略键）
  final int? rowEstimate; // 统计近似值（InnoDB table_rows / PG reltuples…）

  const TableSummary({
    required this.name,
    required this.kind,
    this.comment,
    this.rowEstimate,
  });
}

/// 列明细。
class ColumnDetail {
  final String name;
  final String dataType; // 引擎完整类型：varchar(255) / Nullable(Int64)
  final bool nullable;
  final String? defaultValue;
  final String? comment;

  const ColumnDetail({
    required this.name,
    required this.dataType,
    required this.nullable,
    this.defaultValue,
    this.comment,
  });
}

/// 索引明细。
class IndexDetail {
  final String name;
  final List<String> columns;
  final bool unique;

  const IndexDetail({
    required this.name,
    required this.columns,
    required this.unique,
  });
}

/// 外键明细。
class ForeignKeyDetail {
  final String? name; // SQLite PRAGMA 无约束名 → null（wire 省略）
  final List<String> columns;
  final String refTable;
  final List<String> refColumns;

  const ForeignKeyDetail({
    this.name,
    required this.columns,
    required this.refTable,
    required this.refColumns,
  });
}

/// `describe_table` 完整响应。
class TableDescription {
  final String table;
  final String? comment;
  final List<ColumnDetail> columns;
  final List<String> primaryKey;
  final List<IndexDetail> indexes;
  final List<ForeignKeyDetail> foreignKeys;

  const TableDescription({
    required this.table,
    this.comment,
    required this.columns,
    required this.primaryKey,
    required this.indexes,
    required this.foreignKeys,
  });
}

// ============================================================================
// §2.1 执行通道（流式 + 显式取消；C13 消费）
// ============================================================================

enum ExecutionChunkType { meta, rows, complete, error }

/// 流式块。所有块携带 kind（v1 恒 "sql"；v2 预留 "redis"/"mongo"/"tdengine"）。
sealed class ExecutionChunk {
  const ExecutionChunk({required this.type});

  final String kind = 'sql';
  final ExecutionChunkType type;
}

class ExecutionMeta extends ExecutionChunk {
  final List<String> columns; // 列名（v2 若需类型再扩 dataType?）

  ExecutionMeta({required this.columns}) : super(type: ExecutionChunkType.meta);
}

class ExecutionRows extends ExecutionChunk {
  final List<List<Object?>> rows; // 行批；NULL = null；值按 JSON 语义解码

  ExecutionRows({required this.rows}) : super(type: ExecutionChunkType.rows);
}

class ExecutionComplete extends ExecutionChunk {
  final int rowCount; // 累计行数
  final bool truncated; // rowCount >= rowLimit 的保守判据（同 read_query.rs）
  final int elapsedMs;

  ExecutionComplete({
    required this.rowCount,
    required this.truncated,
    required this.elapsedMs,
  }) : super(type: ExecutionChunkType.complete);
}

class ExecutionError extends ExecutionChunk {
  final String code; // 稳定错误码（§4.4 码集）
  final String message; // 已清洗（无 host/DNS/凭据；SQL 明文不进）
  final String? engineCode; // 引擎原始错误码透传（MySQL errno / PG SQLSTATE…）

  ExecutionError({
    required this.code,
    required this.message,
    this.engineCode,
  }) : super(type: ExecutionChunkType.error);
}

/// 一次执行请求。
class ExecutionRequest {
  final String sql;
  final String? database; // 不带则用连接 default_database
  final String? schema; // schema-aware 类型（PG/SS）
  final int? rowLimit; // 显式行限；server 按环境上限钳制
  final Duration? timeout; // statement_timeout（墙钟）

  const ExecutionRequest({
    required this.sql,
    this.database,
    this.schema,
    this.rowLimit,
    this.timeout,
  });
}

/// 一次执行的会话句柄：流 + 显式取消（取消必须可达服务端，仅取消订阅不够）。
abstract interface class ExecutionSession {
  Stream<ExecutionChunk> get chunks;

  /// 幂等；GatewayBacking → `DELETE /api/gw/executions/{id}`。
  Future<void> cancel();
}

// ============================================================================
// §2.2 连接语义类型（C10 消费）
// ============================================================================

/// 连接的服务形态：本地 adapter 直连 / embedded 本地 server / 远程 server。
enum ConnectionMode { directAdapter, embeddedServer, remoteServer }

/// 连接态能力位（readOnly / 模式），独立于静态能力位查询。
class ConnectionState {
  final ConnectionMode mode; // embedded/remote 由 server 连接形态决定
  final bool readOnly; // 连接级只读（server 注册值 / 客户端开关）

  const ConnectionState({required this.mode, required this.readOnly});
}

/// 测试连接结果（网关 `POST /api/gw/connections/test` 的镜像形状）。
class ConnectionTestResult {
  final bool ok;
  final String? error; // 已清洗的错误摘要
  final int elapsedMs;
  final String? serverVersion; // 测试成功时的引擎版本（UI 展示）

  const ConnectionTestResult({
    required this.ok,
    this.error,
    this.elapsedMs = 0,
    this.serverVersion,
  });
}

/// port 统一异常：code 集合与网关 wire 错误码一致（§4.4），UI 按 code 分流展示。
///
/// 稳定码集合：`NOT_FOUND` / `UNSUPPORTED_DB_TYPE` / `UNSUPPORTED_KIND` /
/// `CONNECTION_FAILED` / `DB_ERROR` / `TIMEOUT` / `CANCELLED` / `CONFIG`，
/// 外加客户端侧形态：`UNAUTHORIZED`（401）/ `RATE_LIMITED`（429）。
class PortException implements Exception {
  final String code;
  final String message;
  final String? engineCode; // 引擎原始错误码透传（HTTP JSON 层暂不携带）

  const PortException(this.code, this.message, {this.engineCode});

  @override
  String toString() => 'PortException($code): $message';
}

// ============================================================================
// 供双实现共用的辅助：DbServer 上锁 serverConnId 镜像（§5 凭据去向）。
// ============================================================================

/// gateway-backed 连接在本地 `DbServer.extra` 之外另走 ConnectionProvider 的
/// local-id → serverConnId 映射（SharedPreferences `connection_server_id_map`，
/// 与 ADR-0003 S3 镜像共用一张表）。port 层不直接读写该表——由
/// ConnectionProvider 编排（保存时登记、删除时反查），port 只认 id 语义：
/// AdapterBacking 的 connectionId = 本地 id；GatewayBacking 的 = serverConnId。

/// 网关 wire 的小写 db_type 字符串（§4.5）。DatabaseType ↔ wire 的唯一换算
/// 点在 GatewayBacking（AdapterBacking 不经 wire）；本常量表供其内部与测试共用。
/// T28 起含 sqlserver（server 侧白名单同步：handlers.rs SUPPORTED_DB_TYPES）。
const Map<DatabaseType, String> kGatewayWireDbTypes = {
  DatabaseType.mysql: 'mysql',
  DatabaseType.doris: 'doris',
  DatabaseType.postgresql: 'postgresql',
  DatabaseType.sqlite: 'sqlite',
  DatabaseType.clickhouse: 'clickhouse',
  DatabaseType.sqlserver: 'sqlserver',
  // T29 · MySQL 协议族薄适配四成员（wire 名 = 小写枚举名）。
  DatabaseType.oceanbase: 'oceanbase',
  DatabaseType.tidb: 'tidb',
  DatabaseType.starrocks: 'starrocks',
  DatabaseType.mariadb: 'mariadb',
};
