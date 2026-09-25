import 'package:flutter/foundation.dart';

/// Agent 门决策的审计值（design-ai-agent.md §5.3 / D13，值集合锁定）。
///
/// 持久化 token（[wireName]）为设计原文的小写下划线形式：
/// `allowed | confirmed | allowed_session | rejected_by_user | blocked | na`。
/// Dart 标识符按 lint 规范用 lowerCamelCase，与 token 的映射在构造处写死。
///
/// - [allowed]：门直接放行（含 X1/X2 豁免后扫描信号全消）；
/// - [confirmed]：经确认卡单次放行；
/// - [allowedSession]：会话放行账本命中短路放行；
/// - [rejectedByUser]：确认卡/计划卡被人拒——拦截尝试也落审计（AC13.1）；
/// - [blocked]：门判定拒绝（UNKNOWN_TOOL / CONTEXT_REQUIRED /
///   READONLY_CONNECTION / WRITE_REJECTED_READONLY_CHANNEL 等）；
/// - [na]：不适用门语义的记录（如计划逐语句执行段）。
enum AgentGateDecision {
  allowed('allowed'),
  confirmed('confirmed'),
  allowedSession('allowed_session'),
  rejectedByUser('rejected_by_user'),
  blocked('blocked'),
  na('na');

  const AgentGateDecision(this.wireName);

  /// 序列化 token（design §5.3 锁定值，只加不改）。
  final String wireName;

  /// 宽容解析：未知 token / 非字符串一律返回 null——旧档与新档互不炸
  /// （D13 加法语义：fromJson 未知键忽略、新键可空）。
  static AgentGateDecision? tryParse(Object? value) {
    if (value is! String) return null;
    for (final AgentGateDecision decision in AgentGateDecision.values) {
      if (decision.wireName == value) return decision;
    }
    return null;
  }
}

/// Represents a single query audit log entry
@immutable
class AuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String connectionId;
  final String? connectionName;
  final String? databaseName;
  final String sql;
  final Duration executionTime;
  final int? rowCount;
  final bool success;
  final String? errorMessage;
  final bool isWriteQuery;

  // ===== Agent 审计扩展字段（design-ai-agent.md §5.3 / D13，全部可空、纯加法）=====
  // 旧档无这些键读入为 null；非 agent 记录（recordQuery 等）恒为 null，
  // 既有序列化与消费方零行为变化。

  /// Agent 运行 id（run 级轨迹对账键）。
  final String? agentRunId;

  /// 工具调用步号（executor.execute() 入口计数口径，D10）。
  final int? agentStep;

  /// 工具名（目录内 snake_case 名）。
  final String? agentTool;

  /// 门档 token（`AgentGateLevel.name`：l0 / l05 / l1 / l2 / suggest）。
  ///
  /// 存 token 而非枚举类型：models 层不反向 import services 层的工具目录
  /// （`AgentGateLevel` 定义于 `lib/services/ai/agent/agent_tool_catalog.dart`），
  /// 类型转换由 `AuditLogService.recordAgentEvent` 在服务边界完成。
  final String? gateLevel;

  /// 门决策（见 [AgentGateDecision]；拦截尝试也落：blocked / rejected_by_user
  /// 时 success=false，AC13.1）。
  final AgentGateDecision? gateDecision;

  /// 行动计划 id（计划逐语句审计链键，AC11.2）。
  final String? planId;

  const AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.connectionId,
    this.connectionName,
    this.databaseName,
    required this.sql,
    required this.executionTime,
    this.rowCount,
    required this.success,
    this.errorMessage,
    this.isWriteQuery = false,
    this.agentRunId,
    this.agentStep,
    this.agentTool,
    this.gateLevel,
    this.gateDecision,
    this.planId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'connectionId': connectionId,
    'connectionName': connectionName,
    'databaseName': databaseName,
    'sql': sql,
    'executionTimeMs': executionTime.inMilliseconds,
    'rowCount': rowCount,
    'success': success,
    'errorMessage': errorMessage,
    'isWriteQuery': isWriteQuery,
    'agentRunId': agentRunId,
    'agentStep': agentStep,
    'agentTool': agentTool,
    'gateLevel': gateLevel,
    'gateDecision': gateDecision?.wireName,
    'planId': planId,
  };

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      connectionId: json['connectionId'] as String,
      connectionName: json['connectionName'] as String?,
      databaseName: json['databaseName'] as String?,
      sql: json['sql'] as String,
      executionTime: Duration(milliseconds: json['executionTimeMs'] as int),
      rowCount: json['rowCount'] as int?,
      success: json['success'] as bool,
      errorMessage: json['errorMessage'] as String?,
      isWriteQuery: json['isWriteQuery'] as bool? ?? false,
      // Agent 扩展键全部可空 + 未知值容忍（D13 加法语义：旧档无新键不炸）。
      agentRunId: json['agentRunId'] as String?,
      agentStep: json['agentStep'] as int?,
      agentTool: json['agentTool'] as String?,
      gateLevel: json['gateLevel'] as String?,
      gateDecision: AgentGateDecision.tryParse(json['gateDecision']),
      planId: json['planId'] as String?,
    );
  }

  AuditLogEntry copyWith({
    String? id,
    DateTime? timestamp,
    String? connectionId,
    String? connectionName,
    String? databaseName,
    String? sql,
    Duration? executionTime,
    int? rowCount,
    bool? success,
    String? errorMessage,
    bool? isWriteQuery,
    String? agentRunId,
    int? agentStep,
    String? agentTool,
    String? gateLevel,
    AgentGateDecision? gateDecision,
    String? planId,
  }) {
    return AuditLogEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      connectionId: connectionId ?? this.connectionId,
      connectionName: connectionName ?? this.connectionName,
      databaseName: databaseName ?? this.databaseName,
      sql: sql ?? this.sql,
      executionTime: executionTime ?? this.executionTime,
      rowCount: rowCount ?? this.rowCount,
      success: success ?? this.success,
      errorMessage: errorMessage ?? this.errorMessage,
      isWriteQuery: isWriteQuery ?? this.isWriteQuery,
      agentRunId: agentRunId ?? this.agentRunId,
      agentStep: agentStep ?? this.agentStep,
      agentTool: agentTool ?? this.agentTool,
      gateLevel: gateLevel ?? this.gateLevel,
      gateDecision: gateDecision ?? this.gateDecision,
      planId: planId ?? this.planId,
    );
  }
}
