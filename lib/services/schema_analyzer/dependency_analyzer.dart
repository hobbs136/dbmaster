import 'dart:developer' as developer;

import '../../models/schema_analyzer/impact_report.dart';

String _escString(String value) => "'${value.replaceAll("'", "''")}'";

/// 依赖关系分析器
/// 分析数据库对象之间的依赖关系
class DependencyAnalyzer {
  /// 分析表的依赖关系
  static Future<List<SchemaDependency>> analyzeTableDependencies({
    required String tableName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    final dependencies = <SchemaDependency>[];

    try {
      // 1. 查找引用此表的视图
      final viewDependencies = await _findViewDependencies(
        tableName: tableName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );
      dependencies.addAll(viewDependencies);

      // 2. 查找引用此表的外键
      final foreignKeyDependencies = await _findForeignKeyDependencies(
        tableName: tableName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );
      dependencies.addAll(foreignKeyDependencies);

      // 3. 查找引用此表的存储过程和函数
      final procedureDependencies = await _findProcedureDependencies(
        tableName: tableName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );
      dependencies.addAll(procedureDependencies);

      // 4. 查找引用此表的触发器
      final triggerDependencies = await _findTriggerDependencies(
        tableName: tableName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );
      dependencies.addAll(triggerDependencies);
    } catch (e, stackTrace) {
      developer.log(
        'Error analyzing dependencies: $e',
        name: 'DependencyAnalyzer',
        error: e,
        stackTrace: stackTrace,
      );
    }

    return dependencies;
  }

  /// 分析列的依赖关系
  static Future<List<SchemaDependency>> analyzeColumnDependencies({
    required String tableName,
    required String columnName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    final dependencies = <SchemaDependency>[];

    try {
      // 1. 查找引用此列的索引
      final indexDependencies = await _findIndexDependencies(
        tableName: tableName,
        columnName: columnName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );
      dependencies.addAll(indexDependencies);

      // 2. 查找引用此列的视图
      final viewDependencies = await _findViewColumnDependencies(
        tableName: tableName,
        columnName: columnName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );
      dependencies.addAll(viewDependencies);

      // 3. 查找引用此列的约束
      final constraintDependencies = await _findConstraintDependencies(
        tableName: tableName,
        columnName: columnName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );
      dependencies.addAll(constraintDependencies);
    } catch (e) {
      developer.log(
        'Error analyzing column dependencies: $e',
        name: 'DependencyAnalyzer',
      );
    }

    return dependencies;
  }

  // === 私有方法：查找各类依赖 ===

  static Future<List<SchemaDependency>> _findViewDependencies({
    required String tableName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    final dependencies = <SchemaDependency>[];

    String sql;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
      case 'doris':
        // Return VIEW_DEFINITION and word-boundary match in Dart.
        // The old `VIEW_DEFINITION LIKE '%table%'` substring match produced false
        // positives: table `user` was flagged against views referencing `users` /
        // `user_log`. The LIKE now only narrows candidate rows; escape tableName
        // via _escString to close the SQL-injection hole the raw interpolation
        // had (parity with the FK/trigger/index queries in this file).
        sql =
            '''
          SELECT TABLE_NAME as view_name, VIEW_DEFINITION as view_definition
          FROM INFORMATION_SCHEMA.VIEWS
          WHERE TABLE_SCHEMA = DATABASE()
            AND VIEW_DEFINITION LIKE CONCAT('%', ${_escString(tableName)}, '%')
        ''';
        break;
      case 'postgresql':
        sql =
            '''
          SELECT viewname as view_name, definition as view_definition
          FROM pg_views
          WHERE definition LIKE CONCAT('%', ${_escString(tableName)}, '%')
        ''';
        break;
      case 'sqlite':
        // SQLite 没有 INFORMATION_SCHEMA，使用简化的检测
        return [];
      default:
        return [];
    }

    try {
      final results = await executeQuery(sql);
      for (final row in results) {
        final viewName = row['view_name']?.toString();
        final viewDefinition = row['view_definition']?.toString() ?? '';
        // Word-boundary check so table `user` does not match view
        // text that only references `users` / `user_log`.
        if (viewName != null &&
            _referencesIdentifier(viewDefinition, tableName)) {
          dependencies.add(
            SchemaDependency(
              sourceTable: tableName,
              dependentObject: viewName,
              dependentType: AffectedObjectType.view,
              relationship: 'View references table',
            ),
          );
        }
      }
    } catch (e) {
      developer.log(
        'Error finding view dependencies: $e',
        name: 'DependencyAnalyzer',
      );
    }

    return dependencies;
  }

  /// Whether [definition] references [identifier] as a whole SQL identifier
  /// (bounded by non-identifier characters or the string edges), so a table
  /// named `user` is NOT reported as referenced by view text that only mentions
  /// `users` or `user_log`.
  // Added for correct (false-positive-free) view matching.
  static bool _referencesIdentifier(String definition, String identifier) {
    if (identifier.isEmpty || definition.isEmpty) return false;
    final pattern = RegExp(
      r'(?:^|[^A-Za-z0-9_])' +
          RegExp.escape(identifier) +
          r'(?:[^A-Za-z0-9_]|$)',
      caseSensitive: false,
    );
    return pattern.hasMatch(definition);
  }

  static Future<List<SchemaDependency>> _findForeignKeyDependencies({
    required String tableName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    final dependencies = <SchemaDependency>[];

    String sql;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
      case 'doris':
        sql =
            '''
          SELECT TABLE_NAME as table_name, CONSTRAINT_NAME as constraint_name
          FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
          WHERE REFERENCED_TABLE_NAME = ${_escString(tableName)}
            AND TABLE_SCHEMA = DATABASE()
        ''';
        break;
      case 'postgresql':
        sql =
            '''
          SELECT tc.table_name, tc.constraint_name
          FROM information_schema.table_constraints tc
          JOIN information_schema.constraint_column_usage ccu 
            ON tc.constraint_name = ccu.constraint_name
          WHERE tc.constraint_type = 'FOREIGN KEY' 
            AND ccu.table_name = ${_escString(tableName)}
        ''';
        break;
      default:
        return [];
    }

    try {
      final results = await executeQuery(sql);
      for (final row in results) {
        final dependentTable = row['table_name']?.toString();
        final constraintName = row['constraint_name']?.toString();
        if (dependentTable != null) {
          dependencies.add(
            SchemaDependency(
              sourceTable: tableName,
              dependentObject: dependentTable,
              dependentType: AffectedObjectType.foreignKey,
              relationship: 'Foreign key references: $constraintName',
            ),
          );
        }
      }
    } catch (e) {
      developer.log(
        'Error finding FK dependencies: $e',
        name: 'DependencyAnalyzer',
      );
    }

    return dependencies;
  }

  static Future<List<SchemaDependency>> _findProcedureDependencies({
    required String tableName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    // 存储过程依赖检测比较复杂，简化处理
    // 实际实现需要解析存储过程体
    return [];
  }

  static Future<List<SchemaDependency>> _findTriggerDependencies({
    required String tableName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    final dependencies = <SchemaDependency>[];

    String sql;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
      case 'doris':
        sql =
            '''
          SELECT TRIGGER_NAME as trigger_name
          FROM INFORMATION_SCHEMA.TRIGGERS
          WHERE EVENT_OBJECT_TABLE = ${_escString(tableName)}
        ''';
        break;
      case 'postgresql':
        sql =
            '''
          SELECT trigger_name
          FROM information_schema.triggers
          WHERE event_object_table = ${_escString(tableName)}
        ''';
        break;
      default:
        return [];
    }

    try {
      final results = await executeQuery(sql);
      for (final row in results) {
        final triggerName = row['trigger_name']?.toString();
        if (triggerName != null) {
          dependencies.add(
            SchemaDependency(
              sourceTable: tableName,
              dependentObject: triggerName,
              dependentType: AffectedObjectType.trigger,
              relationship: 'Trigger on table',
            ),
          );
        }
      }
    } catch (e) {
      developer.log(
        'Error finding trigger dependencies: $e',
        name: 'DependencyAnalyzer',
      );
    }

    return dependencies;
  }

  static Future<List<SchemaDependency>> _findIndexDependencies({
    required String tableName,
    required String columnName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    final dependencies = <SchemaDependency>[];

    String sql;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
      case 'doris':
        sql =
            '''
          SELECT INDEX_NAME as index_name
          FROM INFORMATION_SCHEMA.STATISTICS
          WHERE TABLE_NAME = ${_escString(tableName)} 
            AND COLUMN_NAME = ${_escString(columnName)}
            AND INDEX_NAME != 'PRIMARY'
        ''';
        break;
      case 'postgresql':
        sql =
            '''
          SELECT indexname as index_name
          FROM pg_indexes
          WHERE tablename = ${_escString(tableName)}
            AND indexdef LIKE '%${columnName.replaceAll("'", "''")}%'
        ''';
        break;
      default:
        return [];
    }

    try {
      final results = await executeQuery(sql);
      for (final row in results) {
        final indexName = row['index_name']?.toString();
        if (indexName != null && indexName != 'PRIMARY') {
          dependencies.add(
            SchemaDependency(
              sourceTable: tableName,
              sourceColumn: columnName,
              dependentObject: indexName,
              dependentType: AffectedObjectType.index_,
              relationship: 'Index on column',
            ),
          );
        }
      }
    } catch (e) {
      developer.log(
        'Error finding index dependencies: $e',
        name: 'DependencyAnalyzer',
      );
    }

    return dependencies;
  }

  static Future<List<SchemaDependency>> _findViewColumnDependencies({
    required String tableName,
    required String columnName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    // 简化实现：查找包含表名和列名的视图
    return [];
  }

  static Future<List<SchemaDependency>> _findConstraintDependencies({
    required String tableName,
    required String columnName,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    required String databaseType,
  }) async {
    final dependencies = <SchemaDependency>[];

    String sql;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
      case 'doris':
        sql =
            '''
          SELECT CONSTRAINT_NAME as constraint_name, CONSTRAINT_TYPE as constraint_type
          FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
          WHERE TABLE_NAME = ${_escString(tableName)}
            AND CONSTRAINT_NAME IN (
              SELECT CONSTRAINT_NAME
              FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
              WHERE TABLE_NAME = ${_escString(tableName)} AND COLUMN_NAME = ${_escString(columnName)}
            )
        ''';
        break;
      default:
        return [];
    }

    try {
      final results = await executeQuery(sql);
      for (final row in results) {
        final constraintName = row['constraint_name']?.toString();
        final constraintType = row['constraint_type']?.toString();
        if (constraintName != null && constraintName != 'PRIMARY') {
          dependencies.add(
            SchemaDependency(
              sourceTable: tableName,
              sourceColumn: columnName,
              dependentObject: constraintName,
              dependentType: AffectedObjectType.constraint,
              relationship: '$constraintType constraint',
            ),
          );
        }
      }
    } catch (e) {
      developer.log(
        'Error finding constraint dependencies: $e',
        name: 'DependencyAnalyzer',
      );
    }

    return dependencies;
  }
}
