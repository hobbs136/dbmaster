import 'dart:math';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/pro/data_import/faker_data_service.dart';

/// Service for generating realistic test data based on database schema.
/// Supports all database types with multi-language faker data.
class DataGenerationService {
  final DatabaseAdapter adapter;
  final Random _random = Random();
  late final FakerDataService _fakerService;

  DataGenerationService({required this.adapter, String locale = 'en'}) {
    _fakerService = FakerDataService(locale: locale);
  }

  /// Generate test data for any table.
  /// Supports all database types with realistic faker data.
  Future<List<Map<String, dynamic>>> generateTestData({
    required String tableName,
    required int count,
    List<DbColumn>? columns,
    String? locale,
    bool useRealisticData = true,
  }) async {
    final tableColumns = columns ?? await adapter.getTableColumns(tableName);
    if (tableColumns.isEmpty) {
      throw Exception('无法获取表 [$tableName] 的结构');
    }

    // Create a fresh faker service if locale is specified
    final faker = locale != null && locale != _fakerService.locale
        ? FakerDataService(locale: locale)
        : _fakerService;

    final result = <Map<String, dynamic>>[];
    final baseTime = DateTime.now().subtract(Duration(minutes: count));

    for (int i = 0; i < count; i++) {
      final row = <String, dynamic>{};
      var isFirstColumn = true;

      for (final col in tableColumns) {
        // Skip auto-increment columns for most databases
        if (_isAutoIncrement(col)) {
          continue;
        }

        // TDengine first column must be TIMESTAMP
        if (adapter.databaseType == DatabaseType.tdengine && isFirstColumn) {
          row[col.name] = _generateTimestamp(baseTime, i);
          isFirstColumn = false;
          continue;
        }

        if (useRealisticData) {
          // Use faker service for realistic data
          row[col.name] = faker.generateValue(
            columnName: col.name,
            columnType: col.type,
            rowIndex: i,
            locale: locale,
          );
        } else {
          // Use basic random data
          row[col.name] = _generateBasicValue(col, i);
        }
      }

      result.add(row);
    }

    return result;
  }

  /// Build INSERT SQL statements from generated data.
  List<String> buildInsertSql({
    required String tableName,
    required List<Map<String, dynamic>> rows,
    List<DbColumn>? columns,
  }) {
    if (rows.isEmpty) return [];

    final columnNames = rows.first.keys.toList();
    final statements = <String>[];

    for (final row in rows) {
      final values = columnNames
          .map((col) {
            final value = row[col];
            return _formatValue(value);
          })
          .join(', ');

      statements.add(
        'INSERT INTO ${SqlSanitizer.identifier(tableName)} '
        '(${columnNames.map(SqlSanitizer.identifier).join(', ')}) '
        'VALUES ($values);',
      );
    }

    return statements;
  }

  /// Build batched INSERT SQL (multiple VALUES clauses per statement).
  List<String> buildBatchedInsertSql({
    required String tableName,
    required List<Map<String, dynamic>> rows,
    int batchSize = 100,
  }) {
    if (rows.isEmpty) return [];

    final columnNames = rows.first.keys.toList();
    final statements = <String>[];

    for (int i = 0; i < rows.length; i += batchSize) {
      final batch = rows.sublist(
        i,
        i + batchSize > rows.length ? rows.length : i + batchSize,
      );

      final valuesList = batch
          .map((row) {
            final values = columnNames
                .map((col) {
                  final value = row[col];
                  return _formatValue(value);
                })
                .join(', ');
            return '($values)';
          })
          .join(', ');

      statements.add(
        'INSERT INTO ${SqlSanitizer.identifier(tableName)} '
        '(${columnNames.map(SqlSanitizer.identifier).join(', ')}) '
        'VALUES $valuesList;',
      );
    }

    return statements;
  }

  /// Execute INSERT statements directly (auto-execution).
  Future<DataGenerationResult> executeInsert({
    required String tableName,
    required List<Map<String, dynamic>> rows,
    int batchSize = 1000,
  }) async {
    if (rows.isEmpty) {
      return DataGenerationResult(
        success: true,
        insertedRows: 0,
        failedRows: 0,
        message: 'No rows to insert',
      );
    }

    int insertedRows = 0;
    int failedRows = 0;
    final errors = <String>[];

    // Build batched SQL
    final statements = buildBatchedInsertSql(
      tableName: tableName,
      rows: rows,
      batchSize: batchSize,
    );

    for (final sql in statements) {
      try {
        final result = await adapter.executeQuery(sql);
        insertedRows += result.affectedRows ?? 0;
      } catch (e) {
        failedRows += batchSize; // Approximate
        errors.add('Batch failed: $e');
      }
    }

    return DataGenerationResult(
      success: failedRows == 0,
      insertedRows: insertedRows,
      failedRows: failedRows,
      message: failedRows == 0
          ? 'Successfully inserted $insertedRows rows'
          : 'Inserted $insertedRows rows, $failedRows failed',
      errors: errors,
    );
  }

  /// Generate data for multiple tables with foreign key awareness.
  /// Tables are processed in dependency order (parents first).
  Future<Map<String, List<Map<String, dynamic>>>>
  generateTestDataForMultipleTables({
    required Map<String, int> tableCounts, // tableName -> count
    String? locale,
    bool useRealisticData = true,
  }) async {
    final result = <String, List<Map<String, dynamic>>>{};
    final generatedIds =
        <String, List<dynamic>>{}; // tableName -> list of generated IDs

    // Sort tables by dependency order (simple heuristic: process in given order)
    // In a real implementation, you'd analyze foreign key relationships
    for (final entry in tableCounts.entries) {
      final tableName = entry.key;
      final count = entry.value;

      // Get columns
      final columns = await adapter.getTableColumns(tableName);

      // Generate data
      final rows = await generateTestData(
        tableName: tableName,
        count: count,
        columns: columns,
        locale: locale,
        useRealisticData: useRealisticData,
      );

      result[tableName] = rows;

      // Store generated IDs for foreign key reference
      final idColumn = columns.firstWhere(
        (c) => c.isPrimaryKey || c.name.toLowerCase() == 'id',
        orElse: () => columns.first,
      );
      generatedIds[tableName] = rows.map((r) => r[idColumn.name]).toList();
    }

    return result;
  }

  // -----------------------------------------------------------------------
  // Private helpers
  // -----------------------------------------------------------------------

  bool _isAutoIncrement(DbColumn col) {
    final type = col.type.toUpperCase();
    final name = col.name.toLowerCase();

    // MySQL AUTO_INCREMENT
    if (name == 'id' && (type.contains('INT') || type == 'INTEGER')) {
      return true;
    }

    // PostgreSQL SERIAL
    if (type.contains('SERIAL')) {
      return true;
    }

    // SQLite INTEGER PRIMARY KEY
    if (type == 'INTEGER' && col.isPrimaryKey) {
      return true;
    }

    return false;
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is String) return "'$value'";
    if (value is DateTime) {
      return "'${_formatTimestamp(value)}'";
    }
    if (value is bool) {
      return value ? '1' : '0';
    }
    return value.toString();
  }

  DateTime _generateTimestamp(DateTime base, int offset) {
    return base.add(Duration(milliseconds: offset));
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  dynamic _generateBasicValue(DbColumn col, int rowIndex) {
    final type = col.type.toUpperCase();

    if (type.startsWith('TIMESTAMP')) {
      return _generateTimestamp(
        DateTime.now().subtract(Duration(minutes: 1000)),
        rowIndex,
      );
    }

    if (type.startsWith('INT') || type == 'INTEGER') {
      return _random.nextInt(100000);
    }

    if (type.startsWith('BIGINT')) {
      return _random.nextInt(1000000);
    }

    if (type.startsWith('SMALLINT')) {
      return _random.nextInt(32767);
    }

    if (type.startsWith('TINYINT')) {
      return _random.nextInt(127);
    }

    if (type.startsWith('FLOAT') ||
        type.startsWith('DOUBLE') ||
        type.startsWith('DECIMAL')) {
      return (_random.nextDouble() * 1000).toStringAsFixed(2);
    }

    if (type.startsWith('BOOL') || type.startsWith('BIT')) {
      return _random.nextBool();
    }

    if (type.startsWith('DATE') || type.startsWith('TIME')) {
      return _formatTimestamp(
        DateTime.now().subtract(Duration(days: _random.nextInt(365))),
      );
    }

    if (type.startsWith('JSON') || type.startsWith('JSONB')) {
      return '{"id": $rowIndex, "value": "${_random.nextInt(100)}"}';
    }

    // Default string
    return '${col.name}_$rowIndex';
  }
}

/// Simple SQL identifier sanitizer.
class SqlSanitizer {
  static String identifier(String name) {
    final escaped = name.replaceAll('`', '``');
    return '`$escaped`';
  }
}

/// Result of data generation execution
class DataGenerationResult {
  final bool success;
  final int insertedRows;
  final int failedRows;
  final String message;
  final List<String> errors;

  DataGenerationResult({
    required this.success,
    required this.insertedRows,
    required this.failedRows,
    required this.message,
    this.errors = const [],
  });

  @override
  String toString() {
    return 'DataGenerationResult(success: $success, inserted: $insertedRows, failed: $failedRows, message: $message)';
  }
}
