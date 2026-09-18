import 'dart:async';

import '../models/database_models.dart';
import '../models/dml_risk_models.dart';
import '../models/sql_statement.dart';
import '../utils/app_logger.dart';
import 'database_abstract.dart';
import 'sql_injection_detector.dart';
import 'sql_parser_service.dart';

/// DML Safety Service — core risk analysis engine.
///
/// Analyzes SQL statements before execution and assigns a risk level
/// (normal, high, critical) based on destructive operation patterns.
/// Used by [QueryExecutionInterceptor] in the execution pipeline.
class DmlSafetyService {
  final SqlInjectionDetector _injectionDetector;

  DmlSafetyService({SqlInjectionDetector? injectionDetector})
      : _injectionDetector = injectionDetector ?? SqlInjectionDetector();

  /// Analyze a list of SQL statements and return the combined risk assessment.
  ///
  /// For non-SQL database types, immediately returns [RiskAnalysisResult.normal].
  /// For SQL types, iterates each statement, detects risk triggers, and returns
  /// the maximum risk level across all statements.
  RiskAnalysisResult analyze(
    List<SQLStatement> statements,
    DatabaseType dbType,
  ) {
    // No-op for non-SQL database types
    if (!_isSqlDatabase(dbType)) {
      return RiskAnalysisResult.normal;
    }

    if (statements.isEmpty) {
      return RiskAnalysisResult.normal;
    }

    final allTriggers = <RiskTrigger>{};
    final allObjects = <String>{};
    bool hasInjection = false;
    String? injectionDetails;

    for (final stmt in statements) {
      final sql = stmt.sql;

      // Detect individual triggers for this statement
      final triggers = _detectTriggers(sql, stmt.type);
      allTriggers.addAll(triggers);

      // Extract affected object names
      final tableName = SQLParserService.extractTableName(sql, stmt.type);
      if (tableName != null) {
        allObjects.add(tableName);
      }

      // Check for SQL injection patterns
      final threats = _injectionDetector.analyze(sql);
      // SQLType.call（EXEC/CALL 存储过程调用）命中 'EXEC执行' 是语句本身
      // 的特性，并非注入。过滤掉该项，避免合法存储过程调用被误判为高风险而弹出
      // DML 警告横幅（堆叠查询 / UNION 等其它模式仍可检测 proc 调用中的真实注入）。
      final relevantThreats = stmt.type == SQLType.call
          ? threats.where((t) => t.type != 'EXEC执行').toList()
          : threats;
      if (relevantThreats.isNotEmpty &&
          relevantThreats.any((t) => t.severity == Severity.high)) {
        hasInjection = true;
        injectionDetails = relevantThreats
            .where((t) => t.severity == Severity.high)
            .map((t) => t.type)
            .join(', ');
      }
    }

    // Compute base risk level (max across all triggers)
    DmlRiskLevel baseLevel = DmlRiskLevel.normal;
    for (final trigger in allTriggers) {
      final level = trigger.riskLevel;
      if (level == DmlRiskLevel.critical) {
        baseLevel = DmlRiskLevel.critical;
        break; // critical is max, no need to check further
      }
      if (level == DmlRiskLevel.high && baseLevel != DmlRiskLevel.critical) {
        baseLevel = DmlRiskLevel.high;
      }
    }

    // Escalate risk if injection patterns detected
    DmlRiskLevel finalLevel = baseLevel;
    if (hasInjection && baseLevel == DmlRiskLevel.normal) {
      finalLevel = DmlRiskLevel.high;
    } else if (hasInjection && baseLevel == DmlRiskLevel.high) {
      finalLevel = DmlRiskLevel.critical;
    }
    // If already critical, stays critical

    return RiskAnalysisResult(
      riskLevel: finalLevel,
      triggers: allTriggers.toList(),
      affectedObjects: allObjects.toList(),
      hasInjectionPattern: hasInjection,
      injectionDetails: injectionDetails,
    );
  }

  /// Quick check: does the SQL text contain any critical-risk DML patterns?
  /// Faster than full [analyze] — skips injection detection.
  bool hasCriticalRisk(String sql, DatabaseType dbType) {
    if (!_isSqlDatabase(dbType)) return false;
    final triggers = _detectTriggers(sql, SQLParserService.detectType(sql));
    return triggers.any((t) => t.riskLevel == DmlRiskLevel.critical);
  }

  /// Attempt to estimate the number of rows in a table.
  ///
  /// Uses `information_schema.tables.table_rows` for MySQL/PostgreSQL/SQL Server,
  /// `SELECT COUNT(*)` with 500ms timeout for SQLite, returns `null` on failure.
  Future<int?> getEstimatedRowCount(
    String tableName,
    DatabaseAdapter adapter,
  ) async {
    try {
      final result = await adapter
          .executeQuery(
            "SELECT table_rows FROM information_schema.tables "
            "WHERE table_name = '${tableName.replaceAll("'", "''")}' "
            'LIMIT 1',
          )
          .timeout(const Duration(milliseconds: 500));
      if (result.rows.isNotEmpty) {
        final row = result.rows.first;
        final val = row['table_rows'] ?? row['TABLE_ROWS'];
        if (val != null) return int.tryParse(val.toString());
      }
    } catch (_) {
      // Fallback: try COUNT(*) with the same timeout
      try {
        final countResult = await adapter
            .executeQuery(
              'SELECT COUNT(*) as cnt FROM ${_escapeIdentifier(tableName)}',
            )
            .timeout(const Duration(milliseconds: 500));
        if (countResult.rows.isNotEmpty) {
          final val = countResult.rows.first['cnt'];
          if (val != null) return int.tryParse(val.toString());
        }
      } catch (_) {
        // Both approaches failed
      }
    }
    return null;
  }

  /// Append `LIMIT 1000` to a SQL statement that lacks one.
  String autoAppendLimit(String sql) {
    final trimmed = sql.trim();
    // Append before trailing semicolon if present
    if (trimmed.endsWith(';')) {
      return '${trimmed.substring(0, trimmed.length - 1).trimRight()} LIMIT 1000;';
    }
    return '$trimmed LIMIT 1000';
  }

  /// Log a blocked DML operation for audit purposes.
  void logBlockedOperation(AuditLogEntry entry) {
    AppLogger.w('DmlSafetyService', entry.toString());
  }

  // ──────────────── Private Helpers ────────────────

  /// Detect risk triggers from a single SQL statement.
  Set<RiskTrigger> _detectTriggers(String sql, SQLType type) {
    final triggers = <RiskTrigger>{};

    switch (type) {
      case SQLType.delete:
        if (!SQLParserService.hasWhereClause(sql)) {
          triggers.add(RiskTrigger.deleteWithoutWhere);
        } else if (!SQLParserService.hasLimitClause(sql)) {
          triggers.add(RiskTrigger.dmlWithoutLimit);
        }
        break;

      case SQLType.update:
        if (!SQLParserService.hasWhereClause(sql)) {
          triggers.add(RiskTrigger.updateWithoutWhere);
        } else if (!SQLParserService.hasLimitClause(sql)) {
          triggers.add(RiskTrigger.dmlWithoutLimit);
        }
        break;

      case SQLType.ddl:
        final subType = SQLParserService.detectDdlSubType(sql);
        switch (subType) {
          case DdlSubType.dropTable:
            triggers.add(RiskTrigger.dropTable);
            break;
          case DdlSubType.dropDatabase:
            triggers.add(RiskTrigger.dropDatabase);
            break;
          case DdlSubType.truncate:
            triggers.add(RiskTrigger.truncateTable);
            break;
          case DdlSubType.alterDropColumn:
            triggers.add(RiskTrigger.alterDropColumn);
            break;
          default:
            break; // CREATE, ALTER (non-drop), unknown — normal risk
        }
        break;

      default:
        break; // SELECT, INSERT, CALL, other — normal risk
    }

    return triggers;
  }

  bool _isSqlDatabase(DatabaseType dbType) {
    switch (dbType) {
            case DatabaseType.mysql:
            case DatabaseType.clickhouse:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.sqlserver:
      case DatabaseType.doris:
      case DatabaseType.tdengine:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return true;
      case DatabaseType.mongodb:
      case DatabaseType.redis:
        return false;
    }
  }

  String _escapeIdentifier(String name) {
    return name.replaceAll('"', '""');
  }
}
