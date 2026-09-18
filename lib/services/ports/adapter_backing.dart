//! AdapterBacking —— DbCapabilityPort 的本地 adapter 实现（未迁移类型）。
//!
//! 连接语义 = 现状行为（c01 §5 第一列）：测试走本地直连（含 SSH 隧道特判与
//! mysql/doris 直连快路径，全部保留在 DatabaseService 内）；persistConnection
//! 为本地 no-op（本地保存由 ConnectionProvider 编排——keychain + prefs 是
//! 主存储，非 port 职责）；凭据留在客户端本地。
//!
//! 执行通道 = C13 包装（现有 executeQuery 一次性结果 → meta/rows/complete
//! 单批块流，维持现状分页/行限）；Tier 1 元数据由 C14 落地。

import 'dart:async';

import '../../models/database_models.dart';
import '../database_service.dart';
import 'capability_table.dart';
import 'db_capability_port.dart';
import 'port_types.dart';

class AdapterBacking implements DbCapabilityPort {
  AdapterBacking({
    required DatabaseService dbService,
    DbServer? Function(String connectionId)? connectionLookup,
  }) : _dbService = dbService,
       _connectionLookup = connectionLookup;

  final DatabaseService _dbService;

  /// 本地连接表反查（connectionState 的 readOnly 来源）。可空：无注入时
  /// readOnly 恒 false。
  final DbServer? Function(String connectionId)? _connectionLookup;

  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      CapabilityTable.has(type, capabilityId);

  @override
  Set<String> capabilitiesOf(DatabaseType type) => CapabilityTable.of(type);

  @override
  Future<ConnectionState> connectionState(String connectionId) async {
    final server = _connectionLookup?.call(connectionId);
    return ConnectionState(
      mode: ConnectionMode.directAdapter,
      readOnly: server?.readOnly ?? false,
    );
  }

  @override
  Future<ConnectionTestResult> testConnection(DbServer draft) async {
    final error = await _dbService.testConnection(draft);
    return ConnectionTestResult(ok: error == null, error: error);
  }

  @override
  Future<String> persistConnection(DbServer server) async => server.id;

  @override
  Future<void> removeConnection(String connectionId) async {}

  // ── C14 落地（Tier 1 委托既有 adapter）──

  @override
  Future<List<String>> listDatabases(String connectionId) =>
      throw UnimplementedError('Tier 1 元数据经 AdapterBacking 落地于 C14');

  @override
  Future<List<TableSummary>> listTables(
    String connectionId, {
    String? database,
    String? schema,
  }) => throw UnimplementedError('Tier 1 元数据经 AdapterBacking 落地于 C14');

  @override
  Future<TableDescription> describeTable(
    String connectionId,
    String table, {
    String? database,
    String? schema,
  }) => throw UnimplementedError('Tier 1 元数据经 AdapterBacking 落地于 C14');

  // ── C13 落地（流式执行包装：单批 meta/rows/complete；维持现状分页）──

  @override
  ExecutionSession execute(String connectionId, ExecutionRequest request) {
    return _AdapterExecutionSession(
      run: () => _runExecution(connectionId, request),
    );
  }

  /// 本地 adapter 路径的块流包装：现有 executeQuery（含只读守卫 / 行限 /
  /// DDL 拦截管线）一次性返回 → 包装为 meta + 单批 rows + complete。分页
  /// /行限语义与编辑器现状完全一致（C13 契约：AdapterBacking 不做真流式）。
  Stream<ExecutionChunk> _runExecution(
    String connectionId,
    ExecutionRequest request,
  ) async* {
    final startTime = DateTime.now();
    try {
      final rows = await _dbService.executeQuery(
        request.sql,
        connectionId: connectionId,
        database: request.database,
      );
      final columns = rows.isNotEmpty
          ? rows.first.keys.toList()
          : const <String>[];
      yield ExecutionMeta(columns: columns);
      yield ExecutionRows(
        rows: [
          for (final row in rows)
            [for (final col in columns) row[col]],
        ],
      );
      yield ExecutionComplete(
        rowCount: rows.length,
        truncated: false,
        elapsedMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      yield ExecutionError(
        code: 'DB_ERROR',
        message: e.toString(),
        // 本地路径无稳定引擎码分层（异常文本已含引擎信息，维持现状透传）。
      );
    }
  }
}

/// AdapterBacking 执行会话：流即包装块；[cancel] 幂等 no-op——本地执行
/// 的取消走既有连接级 KILL QUERY 链路（DatabaseService.cancelQuery），不经
/// port 会话句柄（v1 边界，真取消待网关全面化时统一）。
class _AdapterExecutionSession implements ExecutionSession {
  final Stream<ExecutionChunk> Function() _run;
  Stream<ExecutionChunk>? _started;

  _AdapterExecutionSession({required Stream<ExecutionChunk> Function() run})
    : _run = run;

  @override
  Stream<ExecutionChunk> get chunks => _started ??= _run();

  @override
  Future<void> cancel() async {}
}
