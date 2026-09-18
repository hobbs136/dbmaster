import 'package:flutter/foundation.dart';

import 'sql_statement.dart';

/// DML risk level — mirrors the risk classification from spec FR-001.
enum DmlRiskLevel {
  /// Green — safe to execute without user interaction
  normal,

  /// Yellow — requires non-blocking warning + second-click confirmation
  high,

  /// Red — requires modal confirmation with object name input
  critical;

  /// Whether this risk level requires modal blocking (user must type object name).
  bool get isBlocking => this == DmlRiskLevel.critical;

  /// Whether this risk level requires at least a non-blocking warning.
  bool get requiresWarning => this != DmlRiskLevel.normal;
}

/// Specific risk conditions detected in SQL statements.
enum RiskTrigger {
  deleteWithoutWhere,
  updateWithoutWhere,
  dropTable,
  dropDatabase,
  truncateTable,
  dmlWithoutLimit,
  alterDropColumn,
  sqlInjection,
  // Doris UPDATE 模型守卫——DUP/AGG 模型不支持 UPDATE
  dorisUpdateOnNonUpdatableModel,
}

extension RiskTriggerLevel on RiskTrigger {
  /// The risk level each trigger maps to.
  DmlRiskLevel get riskLevel {
    switch (this) {
      case RiskTrigger.deleteWithoutWhere:
      case RiskTrigger.updateWithoutWhere:
      case RiskTrigger.dropTable:
      case RiskTrigger.dropDatabase:
      case RiskTrigger.truncateTable:
        return DmlRiskLevel.critical;
      case RiskTrigger.dmlWithoutLimit:
      case RiskTrigger.alterDropColumn:
      // Doris DUP/AGG 模型不支持 UPDATE → 高风险警告（非阻断）
      case RiskTrigger.dorisUpdateOnNonUpdatableModel:
        return DmlRiskLevel.high;
      case RiskTrigger.sqlInjection:
        return DmlRiskLevel.high; // base level; escalated when combined with other triggers
    }
  }
}

/// Result of analyzing one or more SQL statements for DML risk.
@immutable
class RiskAnalysisResult {
  /// The combined (maximum) risk level across all analyzed statements.
  final DmlRiskLevel riskLevel;

  /// All risk triggers detected across all statements.
  final List<RiskTrigger> triggers;

  /// Names of affected database objects (tables, databases).
  final List<String> affectedObjects;

  /// Whether SQL injection patterns were detected.
  final bool hasInjectionPattern;

  /// Human-readable details about detected injection patterns, if any.
  final String? injectionDetails;

  const RiskAnalysisResult({
    required this.riskLevel,
    this.triggers = const [],
    this.affectedObjects = const [],
    this.hasInjectionPattern = false,
    this.injectionDetails,
  });

  /// Safe result — no risk detected, proceed normally.
  static const normal = RiskAnalysisResult(riskLevel: DmlRiskLevel.normal);

  /// Convenience: is this result blocking execution?
  bool get isBlocking => riskLevel.isBlocking;

  /// Convenience: does this result require at least a warning?
  bool get requiresWarning => riskLevel.requiresWarning;

  /// Whether any triggers were detected (non-normal result).
  bool get hasTriggers => triggers.isNotEmpty;

  @override
  String toString() =>
      'RiskAnalysisResult(riskLevel: $riskLevel, triggers: $triggers, '
      'affectedObjects: $affectedObjects, hasInjection: $hasInjectionPattern)';
}

/// User-configurable safety thresholds.
///
/// Persisted to SharedPreferences with key prefix `safety_config_`.
///
/// 字段分两组：
/// - 既有 DML/EXPLAIN 预检开关（explainPreflightEnabled 等）：由
///   [QueryExecutionInterceptor] 的并行 preflight 使用。
/// - 审查规则开关（schemaCompatEnabled 等 6 条）：由 [SafetyReviewService]
///   的规则注册点（query_editor_widget._buildSafetyService）按配置构造规则列表。
///   fullScanRowThreshold 统一喂给行数类规则（MissingLimit /
///   ExplainFullScan / ExplainEstimatedRows）的构造参数。
@immutable
class SafetyConfig {
  final bool explainPreflightEnabled;
  final int fullScanWarningThreshold;
  final int preflightTimeoutSeconds;
  final bool dmlCheckEnabled;

  // ────────── SafetyReviewService 规则开关（既有 6 条）──────────
  // 默认全 true，保持既有「硬编码全开」行为，老用户升级无感知。
  final bool schemaCompatEnabled;
  final bool missingLimitEnabled;
  final bool fullTableScanEnabled;
  final bool sqlInjectionEnabled;
  final bool explainFullScanEnabled;
  final bool explainEstimatedRowsEnabled;

  // ────────── B6 规则包开关（T14 收口，方案 §2.3 六条全默认开）──────────
  // severity 定级：executable_comment/tautology_predicate/complementary_or/
  // file_write/review_degraded_fail_closed = high；writable_cte = medium。
  // reviewFailClosedEnabled 同时约束引擎注入（SafetyReviewService）与
  // 编辑器执行门 catch 两处（T13）。
  final bool executableCommentEnabled;
  final bool tautologyPredicateEnabled;
  final bool complementaryOrEnabled;
  final bool writableCteEnabled;
  final bool fileWriteEnabled;
  final bool reviewFailClosedEnabled;

  /// 行数类规则的统一阈值，同时喂给 MissingLimit / ExplainFullScan /
  /// ExplainEstimatedRows 的构造参数。默认 100000（与 MissingLimit 既有
  /// 默认一致；ExplainFullScan 既有默认 10000，统一后收严到 100000——
  /// 大表才报，减少小表噪声）。
  final int fullScanRowThreshold;

  const SafetyConfig({
    this.explainPreflightEnabled = true,
    this.fullScanWarningThreshold = 10000,
    this.preflightTimeoutSeconds = 3,
    this.dmlCheckEnabled = true,
    this.schemaCompatEnabled = true,
    this.missingLimitEnabled = true,
    this.fullTableScanEnabled = true,
    this.sqlInjectionEnabled = true,
    this.explainFullScanEnabled = true,
    this.explainEstimatedRowsEnabled = true,
    this.fullScanRowThreshold = 100000,
    this.executableCommentEnabled = true,
    this.tautologyPredicateEnabled = true,
    this.complementaryOrEnabled = true,
    this.writableCteEnabled = true,
    this.fileWriteEnabled = true,
    this.reviewFailClosedEnabled = true,
  });

  static const SafetyConfig defaults = SafetyConfig();

  /// fullScanRowThreshold 的合法范围（UI clamp 用）。
  static const int minFullScanRowThreshold = 1000;
  static const int maxFullScanRowThreshold = 1000000;

  SafetyConfig copyWith({
    bool? explainPreflightEnabled,
    int? fullScanWarningThreshold,
    int? preflightTimeoutSeconds,
    bool? dmlCheckEnabled,
    bool? schemaCompatEnabled,
    bool? missingLimitEnabled,
    bool? fullTableScanEnabled,
    bool? sqlInjectionEnabled,
    bool? explainFullScanEnabled,
    bool? explainEstimatedRowsEnabled,
    int? fullScanRowThreshold,
    bool? executableCommentEnabled,
    bool? tautologyPredicateEnabled,
    bool? complementaryOrEnabled,
    bool? writableCteEnabled,
    bool? fileWriteEnabled,
    bool? reviewFailClosedEnabled,
  }) {
    return SafetyConfig(
      explainPreflightEnabled:
          explainPreflightEnabled ?? this.explainPreflightEnabled,
      fullScanWarningThreshold:
          fullScanWarningThreshold ?? this.fullScanWarningThreshold,
      preflightTimeoutSeconds:
          preflightTimeoutSeconds ?? this.preflightTimeoutSeconds,
      dmlCheckEnabled: dmlCheckEnabled ?? this.dmlCheckEnabled,
      schemaCompatEnabled: schemaCompatEnabled ?? this.schemaCompatEnabled,
      missingLimitEnabled: missingLimitEnabled ?? this.missingLimitEnabled,
      fullTableScanEnabled:
          fullTableScanEnabled ?? this.fullTableScanEnabled,
      sqlInjectionEnabled:
          sqlInjectionEnabled ?? this.sqlInjectionEnabled,
      explainFullScanEnabled:
          explainFullScanEnabled ?? this.explainFullScanEnabled,
      explainEstimatedRowsEnabled:
          explainEstimatedRowsEnabled ?? this.explainEstimatedRowsEnabled,
      fullScanRowThreshold:
          fullScanRowThreshold ?? this.fullScanRowThreshold,
      executableCommentEnabled:
          executableCommentEnabled ?? this.executableCommentEnabled,
      tautologyPredicateEnabled:
          tautologyPredicateEnabled ?? this.tautologyPredicateEnabled,
      complementaryOrEnabled:
          complementaryOrEnabled ?? this.complementaryOrEnabled,
      writableCteEnabled: writableCteEnabled ?? this.writableCteEnabled,
      fileWriteEnabled: fileWriteEnabled ?? this.fileWriteEnabled,
      reviewFailClosedEnabled:
          reviewFailClosedEnabled ?? this.reviewFailClosedEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'explainPreflightEnabled': explainPreflightEnabled,
        'fullScanWarningThreshold': fullScanWarningThreshold,
        'preflightTimeoutSeconds': preflightTimeoutSeconds,
        'dmlCheckEnabled': dmlCheckEnabled,
        'schemaCompatEnabled': schemaCompatEnabled,
        'missingLimitEnabled': missingLimitEnabled,
        'fullTableScanEnabled': fullTableScanEnabled,
        'sqlInjectionEnabled': sqlInjectionEnabled,
        'explainFullScanEnabled': explainFullScanEnabled,
        'explainEstimatedRowsEnabled': explainEstimatedRowsEnabled,
        'fullScanRowThreshold': fullScanRowThreshold,
        'executableCommentEnabled': executableCommentEnabled,
        'tautologyPredicateEnabled': tautologyPredicateEnabled,
        'complementaryOrEnabled': complementaryOrEnabled,
        'writableCteEnabled': writableCteEnabled,
        'fileWriteEnabled': fileWriteEnabled,
        'reviewFailClosedEnabled': reviewFailClosedEnabled,
      };

  factory SafetyConfig.fromJson(Map<String, dynamic> json) {
    return SafetyConfig(
      explainPreflightEnabled:
          json['explainPreflightEnabled'] as bool? ?? true,
      fullScanWarningThreshold:
          json['fullScanWarningThreshold'] as int? ?? 10000,
      preflightTimeoutSeconds:
          json['preflightTimeoutSeconds'] as int? ?? 3,
      dmlCheckEnabled: json['dmlCheckEnabled'] as bool? ?? true,
      // 新增字段：老配置（无这些 key）反序列化时落默认值，向后兼容。
      schemaCompatEnabled: json['schemaCompatEnabled'] as bool? ?? true,
      missingLimitEnabled: json['missingLimitEnabled'] as bool? ?? true,
      fullTableScanEnabled: json['fullTableScanEnabled'] as bool? ?? true,
      sqlInjectionEnabled: json['sqlInjectionEnabled'] as bool? ?? true,
      explainFullScanEnabled: json['explainFullScanEnabled'] as bool? ?? true,
      explainEstimatedRowsEnabled:
          json['explainEstimatedRowsEnabled'] as bool? ?? true,
      fullScanRowThreshold:
          json['fullScanRowThreshold'] as int? ?? 100000,
      // B6 规则包开关（T14）：老配置落默认开。
      executableCommentEnabled:
          json['executableCommentEnabled'] as bool? ?? true,
      tautologyPredicateEnabled:
          json['tautologyPredicateEnabled'] as bool? ?? true,
      complementaryOrEnabled:
          json['complementaryOrEnabled'] as bool? ?? true,
      writableCteEnabled: json['writableCteEnabled'] as bool? ?? true,
      fileWriteEnabled: json['fileWriteEnabled'] as bool? ?? true,
      reviewFailClosedEnabled:
          json['reviewFailClosedEnabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SafetyConfig &&
          runtimeType == other.runtimeType &&
          explainPreflightEnabled == other.explainPreflightEnabled &&
          fullScanWarningThreshold == other.fullScanWarningThreshold &&
          preflightTimeoutSeconds == other.preflightTimeoutSeconds &&
          dmlCheckEnabled == other.dmlCheckEnabled &&
          schemaCompatEnabled == other.schemaCompatEnabled &&
          missingLimitEnabled == other.missingLimitEnabled &&
          fullTableScanEnabled == other.fullTableScanEnabled &&
          sqlInjectionEnabled == other.sqlInjectionEnabled &&
          explainFullScanEnabled == other.explainFullScanEnabled &&
          explainEstimatedRowsEnabled == other.explainEstimatedRowsEnabled &&
          fullScanRowThreshold == other.fullScanRowThreshold &&
          executableCommentEnabled == other.executableCommentEnabled &&
          tautologyPredicateEnabled == other.tautologyPredicateEnabled &&
          complementaryOrEnabled == other.complementaryOrEnabled &&
          writableCteEnabled == other.writableCteEnabled &&
          fileWriteEnabled == other.fileWriteEnabled &&
          reviewFailClosedEnabled == other.reviewFailClosedEnabled;

  @override
  int get hashCode => Object.hash(
        explainPreflightEnabled,
        fullScanWarningThreshold,
        preflightTimeoutSeconds,
        dmlCheckEnabled,
        schemaCompatEnabled,
        missingLimitEnabled,
        fullTableScanEnabled,
        sqlInjectionEnabled,
        explainFullScanEnabled,
        explainEstimatedRowsEnabled,
        fullScanRowThreshold,
        executableCommentEnabled,
        tautologyPredicateEnabled,
        complementaryOrEnabled,
        writableCteEnabled,
        fileWriteEnabled,
        reviewFailClosedEnabled,
      );
}

/// Result of an EXPLAIN preflight analysis.
@immutable
class ExplainPreflightResult {
  final bool isFullTableScan;
  final int? estimatedRows;
  final int joinCount;
  final List<String> usedIndexes;
  final bool timedOut;

  const ExplainPreflightResult({
    this.isFullTableScan = false,
    this.estimatedRows,
    this.joinCount = 0,
    this.usedIndexes = const [],
    this.timedOut = false,
  });

  /// Whether this result contains findings worth warning about.
  bool get hasWarning => isFullTableScan || joinCount >= 3;

  @override
  String toString() =>
      'ExplainPreflightResult(fullScan: $isFullTableScan, '
      'estimatedRows: $estimatedRows, joins: $joinCount, '
      'indexes: $usedIndexes, timedOut: $timedOut)';
}

/// Decision made by user when DML operation was blocked.
enum AuditDecision {
  /// User clicked "Cancel"
  cancelled,

  /// User typed a mismatched object name
  mismatch,
}

/// Audit log entry for a blocked DML operation.
@immutable
class AuditLogEntry {
  final DateTime timestamp;
  final String connectionId;
  final String sqlSnippet;
  final DmlRiskLevel riskLevel;
  final AuditDecision decision;

  const AuditLogEntry({
    required this.timestamp,
    required this.connectionId,
    required this.sqlSnippet,
    required this.riskLevel,
    required this.decision,
  });

  @override
  String toString() =>
      '[DML Safety] BLOCKED | sql=${sqlSnippet.length > 200 ? sqlSnippet.substring(0, 200) : sqlSnippet} '
      '| risk=$riskLevel | reason=$decision | connection=$connectionId';
}

/// Exception thrown when DML safety check blocks execution (critical risk).
class DmlConfirmationRequiredException implements Exception {
  final String sql;
  final RiskAnalysisResult analysis;
  final List<SQLStatement> statements;

  const DmlConfirmationRequiredException({
    required this.sql,
    required this.analysis,
    required this.statements,
  });

  @override
  String toString() =>
      'DmlConfirmationRequiredException(risk: ${analysis.riskLevel}, '
      'triggers: ${analysis.triggers}, objects: ${analysis.affectedObjects})';
}

/// Exception thrown when DML safety check requires a non-blocking warning (high risk).
class DmlWarningRequiredException implements Exception {
  final String sql;
  final RiskAnalysisResult analysis;

  const DmlWarningRequiredException({
    required this.sql,
    required this.analysis,
  });

  @override
  String toString() =>
      'DmlWarningRequiredException(risk: ${analysis.riskLevel}, '
      'triggers: ${analysis.triggers})';
}

/// Exception thrown when EXPLAIN preflight detects performance issues.
class ExplainWarningException implements Exception {
  final ExplainPreflightResult result;

  const ExplainWarningException({required this.result});

  @override
  String toString() =>
      'ExplainWarningException(fullScan: ${result.isFullTableScan}, '
      'rows: ${result.estimatedRows}, joins: ${result.joinCount})';
}
