import 'dart:async';

import '../models/database_models.dart';
import '../models/dml_risk_models.dart';
import '../utils/app_logger.dart';
import 'database_abstract.dart';
import 'query_optimizer/explain_parser.dart';

/// Service for EXPLAIN preflight analysis before SELECT query execution.
///
/// Detects full table scans and excessive JOINs, returning a non-blocking
/// warning for the user. Silently skips on timeout or error.
class ExplainPreflightService {
  /// Analyze a SELECT query via EXPLAIN and return findings if any issues detected.
  ///
  /// Returns `null` if:
  /// - The query is not SELECT
  /// - EXPLAIN shows index usage
  /// - Preflight is disabled
  /// - EXPLAIN fails or times out
  ///
  /// Returns [ExplainPreflightResult] if full table scan or ≥3 table JOIN detected.
  Future<ExplainPreflightResult?> analyze({
    required String sql,
    required DatabaseType dbType,
    required Future<QueryResult> Function(String) getExplainPlan,
    required SafetyConfig config,
  }) async {
    if (!config.explainPreflightEnabled) return null;
    if (!_isSqlDatabase(dbType)) return null;

    // Only analyze SELECT queries
    final trimmed = sql.trim().toUpperCase();
    if (!trimmed.startsWith('SELECT') && !trimmed.startsWith('WITH')) {
      return null;
    }

    try {
      final explainResult = await getExplainPlan('EXPLAIN $sql')
          .timeout(Duration(seconds: config.preflightTimeoutSeconds));

      if (explainResult.rows.isEmpty) return null;

      final plan = ExplainParser.parse(
        rawResults: explainResult.rows,
        databaseType: dbType.name,
        originalQuery: sql,
      );
      if (plan == null || plan.steps.isEmpty) return null;

      final isFullTableScan = plan.hasFullTableScan;
      final estimatedRows = plan.totalRows;
      final joinCount =
          plan.steps.where((s) => s.table != null).length - 1; // tables - 1
      final usedIndexes = plan.steps
          .where((s) => s.key != null && s.key!.isNotEmpty)
          .map((s) => s.key!)
          .toList();

      final hasWarning = isFullTableScan &&
          (estimatedRows == null ||
              estimatedRows >= config.fullScanWarningThreshold);

      if (hasWarning || joinCount >= 3) {
        return ExplainPreflightResult(
          isFullTableScan: isFullTableScan,
          estimatedRows: estimatedRows,
          joinCount: joinCount.clamp(0, 999),
          usedIndexes: usedIndexes,
        );
      }

      return null;
    } on TimeoutException {
      AppLogger.d('ExplainPreflightService', 'EXPLAIN preflight timed out');
      return ExplainPreflightResult(timedOut: true);
    } catch (e) {
      AppLogger.d('ExplainPreflightService', 'EXPLAIN preflight failed: $e');
      return null; // Silent skip on any other error
    }
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
}
