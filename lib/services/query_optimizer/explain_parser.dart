import 'dart:developer' as developer;

import '../../models/query_optimizer/execution_plan.dart';

/// EXPLAIN 结果解析器
/// 支持 MySQL, PostgreSQL, SQLite, Doris, TDengine
class ExplainParser {
  /// 解析原始 EXPLAIN 输出
  /// rawResults 是数据库返回的原始行数据
  /// databaseType 是数据库类型标识
  static ExecutionPlan parse({
    required List<Map<String, dynamic>> rawResults,
    required String databaseType,
    required String originalQuery,
  }) {
    final dbType = databaseType.toLowerCase();
    final steps = <PlanStep>[];

    try {
      switch (dbType) {
        case 'mysql':
        case 'doris':
          steps.addAll(_parseMySQLExplain(rawResults));
          break;
        case 'postgresql':
          steps.addAll(_parsePostgreSQLExplain(rawResults));
          break;
        case 'sqlite':
          steps.addAll(_parseSQLiteExplain(rawResults));
          break;
        case 'tdengine':
          steps.addAll(_parseTDengineExplain(rawResults));
          break;
        default:
          developer.log(
            'Unsupported database type for EXPLAIN: $dbType',
            name: 'ExplainParser',
          );
          // 尝试通用解析
          steps.addAll(_parseGenericExplain(rawResults));
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error parsing EXPLAIN results: $e',
        name: 'ExplainParser',
        error: e,
        stackTrace: stackTrace,
      );
    }

    return ExecutionPlan(
      databaseType: dbType,
      originalQuery: originalQuery,
      steps: steps,
      rawData: {'rawResults': rawResults},
      analyzedAt: DateTime.now(),
    );
  }

  /// 解析 MySQL EXPLAIN 输出
  /// MySQL EXPLAIN 返回的列：
  /// id, select_type, table, partitions, type, possible_keys, key, key_len,
  /// ref, rows, filtered, Extra
  static List<PlanStep> _parseMySQLExplain(List<Map<String, dynamic>> results) {
    return results.map((row) {
      final scanType = _parseMySQLScanType(row['type']?.toString());
      final rows = _parseInt(row['rows']);

      return PlanStep(
        id: _parseInt(row['id']),
        selectType: row['select_type']?.toString(),
        table: row['table']?.toString(),
        partition: row['partitions']?.toString(),
        scanType: scanType,
        possibleKeys: row['possible_keys']?.toString(),
        key: row['key']?.toString(),
        keyLen: row['key_len']?.toString(),
        ref: row['ref']?.toString(),
        estimatedRows: rows,
        extra: row['Extra']?.toString(),
      );
    }).toList();
  }

  /// 解析 PostgreSQL EXPLAIN 输出
  /// PostgreSQL 返回的是文本格式（QUERY PLAN 列）
  /// 需要解析文本中的操作类型
  static List<PlanStep> _parsePostgreSQLExplain(
    List<Map<String, dynamic>> results,
  ) {
    final steps = <PlanStep>[];

    for (final row in results) {
      final planText = row['QUERY PLAN']?.toString() ?? '';
      if (planText.isEmpty) continue;

      // 解析常见的 PostgreSQL 操作
      final operation = _parsePostgresOperation(planText);
      final scanType = _parsePostgresScanType(planText);
      final estimatedRows = _parsePostgresRows(planText);
      final cost = _parsePostgresCost(planText);

      // 提取表名
      final tableName = _extractPostgresTableName(planText);

      steps.add(
        PlanStep(
          operation: operation,
          scanType: scanType,
          table: tableName,
          estimatedRows: estimatedRows,
          cost: cost,
          extra: planText,
        ),
      );
    }

    return steps;
  }

  /// 解析 SQLite EXPLAIN QUERY PLAN 输出
  /// SQLite 返回：id, parent, notused, detail
  static List<PlanStep> _parseSQLiteExplain(
    List<Map<String, dynamic>> results,
  ) {
    return results.map((row) {
      final detail = row['detail']?.toString() ?? '';
      final scanType = _parseSQLiteScanType(detail);
      final tableName = _extractSQLiteTableName(detail);

      return PlanStep(
        id: _parseInt(row['id']),
        operation: detail,
        scanType: scanType,
        table: tableName,
        extra: detail,
      );
    }).toList();
  }

  /// 解析 TDengine EXPLAIN 输出
  static List<PlanStep> _parseTDengineExplain(
    List<Map<String, dynamic>> results,
  ) {
    // TDengine 的 EXPLAIN 格式类似 MySQL
    return _parseMySQLExplain(results);
  }

  /// 通用解析（当数据库类型未知时）
  static List<PlanStep> _parseGenericExplain(
    List<Map<String, dynamic>> results,
  ) {
    // 尝试识别格式
    if (results.isEmpty) return [];

    final firstRow = results.first;
    final columns = firstRow.keys
        .map((k) => k.toString().toLowerCase())
        .toList();

    // 如果有 "type" 和 "table" 列，可能是 MySQL 格式
    if (columns.contains('type') && columns.contains('table')) {
      return _parseMySQLExplain(results);
    }

    // 如果有 "query plan" 列，可能是 PostgreSQL 格式
    if (columns.any((c) => c.contains('plan'))) {
      return _parsePostgreSQLExplain(results);
    }

    // 如果有 "detail" 列，可能是 SQLite 格式
    if (columns.contains('detail')) {
      return _parseSQLiteExplain(results);
    }

    // 无法识别，返回原始数据
    return results.map((row) {
      return PlanStep(extra: row.toString());
    }).toList();
  }

  // === MySQL 解析辅助方法 ===

  static ScanType _parseMySQLScanType(String? type) {
    if (type == null || type.isEmpty || type == 'NULL') {
      return ScanType.unknown;
    }
    return ScanType.fromCode(type);
  }

  // === PostgreSQL 解析辅助方法 ===

  static String _parsePostgresOperation(String planText) {
    final operations = [
      'Seq Scan',
      'Index Scan',
      'Index Only Scan',
      'Bitmap Heap Scan',
      'Bitmap Index Scan',
      'Nested Loop',
      'Hash Join',
      'Merge Join',
      'Hash',
      'Sort',
      'Aggregate',
      'Limit',
    ];

    for (final op in operations) {
      if (planText.contains(op)) {
        return op;
      }
    }
    return 'Unknown';
  }

  static ScanType _parsePostgresScanType(String planText) {
    if (planText.contains('Seq Scan')) return ScanType.seqScan;
    if (planText.contains('Index Scan') &&
        !planText.contains('Bitmap Index Scan')) {
      return ScanType.indexScan;
    }
    if (planText.contains('Bitmap Heap Scan')) return ScanType.bitmapHeapScan;
    return ScanType.unknown;
  }

  static int? _parsePostgresRows(String planText) {
    // 解析 "rows=1234" 格式
    final regex = RegExp(r'rows=(\d+)');
    final match = regex.firstMatch(planText);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  static double? _parsePostgresCost(String planText) {
    // 解析 "cost=0.00..123.45" 格式
    final regex = RegExp(r'cost=[\d.]+\.(\d+)');
    final match = regex.firstMatch(planText);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  static String? _extractPostgresTableName(String planText) {
    // 解析 "Seq Scan on table_name" 格式
    final regex = RegExp(r'(?:Seq Scan|Index Scan) on\s+(\w+)');
    final match = regex.firstMatch(planText);
    return match?.group(1);
  }

  // === SQLite 解析辅助方法 ===

  static ScanType _parseSQLiteScanType(String detail) {
    if (detail.contains('SCAN')) {
      if (detail.contains('TABLE')) return ScanType.fullTable;
      if (detail.contains('INDEX')) return ScanType.index_;
      if (detail.contains('TABLE')) return ScanType.fullTable;
    }
    if (detail.contains('SEARCH')) {
      return ScanType.index_;
    }
    if (detail.contains('USING INDEX')) {
      return ScanType.index_;
    }
    if (detail.contains('USING INDEX')) {
      return ScanType.index_;
    }
    return ScanType.unknown;
  }

  static String? _extractSQLiteTableName(String detail) {
    // 解析 "SCAN TABLE table_name" 或 "SEARCH TABLE table_name" 格式
    final regex = RegExp(r'(?:SCAN|SEARCH)\s+TABLE\s+(\w+)');
    final match = regex.firstMatch(detail);
    return match?.group(1);
  }

  // === 通用辅助方法 ===

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}
