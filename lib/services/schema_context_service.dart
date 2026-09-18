import '../models/database_models.dart';
import 'database_service.dart';

/// Schema 感知 AI 上下文服务
/// 为 AI 生成丰富的数据库 schema 描述，使其能够：
/// - 生成准确的 SQL 查询
/// - 解释表结构和关系
/// - 提供索引和性能建议
/// - 检测 SQL 注入风险
class SchemaContextService {
  final DatabaseService _dbService;

  SchemaContextService(this._dbService);

  /// 构建完整的数据库上下文描述（供 AI 使用）
  /// [includeAllTables] 是否包含所有表的详细结构，默认为 true
  Future<String> buildContext({
    required Database? database,
    required DbServer? server,
    bool includeAllTables = true,
    int maxTables = 100,
  }) async {
    final buffer = StringBuffer();

    // 1. 服务器和数据库基本信息
    if (server != null) {
      buffer.writeln('=== 数据库连接信息 ===');
      buffer.writeln('数据库类型: ${server.type.displayName}');
      buffer.writeln('服务器地址: ${server.host}:${server.port}');
      buffer.writeln('当前数据库: ${server.database ?? "未选择"}');
      buffer.writeln();
    }

    // 2. 表列表概览
    if (database != null && database.tables.isNotEmpty) {
      buffer.writeln('=== 数据库表列表 (${database.tables.length} 个表) ===');
      for (final table in database.tables) {
        buffer.writeln(
          '  - ${table.name} (${table.columns.length} 列, ${table.indexes.length} 索引)',
        );
      }
      buffer.writeln();
    }

    // 3. 表详细结构
    if (database != null && includeAllTables) {
      final tablesToInclude = database.tables.take(maxTables).toList();

      buffer.writeln('=== 表详细结构 ===');
      for (final table in tablesToInclude) {
        buffer.writeln();
        await _appendTableDetails(buffer, table);
      }

      if (database.tables.length > maxTables) {
        buffer.writeln('... 还有 ${database.tables.length - maxTables} 个表的结构未显示');
      }
      buffer.writeln();
    }

    // 4. 视图列表
    if (database != null && database.views.isNotEmpty) {
      buffer.writeln('=== 视图列表 (${database.views.length} 个) ===');
      for (final view in database.views.take(20)) {
        buffer.writeln('  - $view');
      }
      if (database.views.length > 20) {
        buffer.writeln('  ... 还有 ${database.views.length - 20} 个视图');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// 生成指定表的完整上下文（用于 AI 分析特定表）
  Future<String> buildTableContext(String tableName) async {
    final buffer = StringBuffer();

    try {
      final columns = await _dbService.getTableColumns(tableName);
      final indexes = await _dbService.getTableIndexes(tableName);
      final properties = await _dbService.getTableProperties(tableName);
      final createSql = await _dbService.getCreateTableSql(tableName);

      buffer.writeln('=== 表: $tableName ===');
      buffer.writeln();
      buffer.writeln('--- 列结构 ---');
      for (final col in columns) {
        final pk = col.isPrimaryKey ? ' [主键]' : '';
        final nullable = col.isNullable ? '' : ' [NOT NULL]';
        final defaultVal = col.defaultValue != null
            ? ' DEFAULT ${col.defaultValue}'
            : '';
        buffer.writeln('  ${col.name}: ${col.type}$nullable$defaultVal$pk');
      }

      buffer.writeln();
      buffer.writeln('--- 索引 ---');
      if (indexes.isEmpty) {
        buffer.writeln('  (无索引)');
      } else {
        for (final idx in indexes) {
          final unique = idx.isUnique ? ' [UNIQUE]' : '';
          buffer.writeln('  ${idx.name}: ${idx.columns.join(", ")}$unique');
        }
      }

      if (properties != null) {
        buffer.writeln();
        buffer.writeln('--- 表属性 ---');
        properties.forEach((key, value) {
          buffer.writeln('  $key: $value');
        });
      }

      buffer.writeln();
      buffer.writeln('--- 建表语句 ---');
      buffer.writeln(createSql);
    } catch (e) {
      buffer.writeln('获取表结构失败: $e');
    }

    return buffer.toString();
  }

  /// 为指定表生成建表语句（供 AI 生成类似结构的表）
  Future<String> generateCreateTableTemplate(
    String tableName, {
    List<String>? newColumnNames,
    List<String>? newColumnTypes,
  }) async {
    final columns = await _dbService.getTableColumns(tableName);

    final buffer = StringBuffer();
    buffer.writeln('CREATE TABLE new_table_name (');

    final colDefs = columns.map((col) {
      final name = newColumnNames != null && newColumnNames.contains(col.name)
          ? 'new_${col.name}'
          : col.name;
      final type = col.type;
      final nullable = col.isNullable ? '' : ' NOT NULL';
      final defaultVal = col.defaultValue != null
          ? ' DEFAULT ${col.defaultValue}'
          : '';
      return '  $name $type$nullable$defaultVal';
    }).toList();

    buffer.writeln(colDefs.join(',\n'));
    buffer.writeln(');');

    return buffer.toString();
  }

  /// 生成 INSERT 语句模板
  Future<String> generateInsertTemplate(
    String tableName, {
    int rows = 3,
  }) async {
    final columns = await _dbService.getTableColumns(tableName);

    final buffer = StringBuffer();
    buffer.writeln('INSERT INTO $tableName (');
    buffer.writeln('  ${columns.map((c) => c.name).join(',\n  ')}');
    buffer.writeln(') VALUES');

    for (int i = 0; i < rows; i++) {
      final placeholders = columns
          .map((c) {
            if (c.isPrimaryKey) return '<自增/主键值>';
            switch (c.type.toLowerCase().split('(')[0]) {
              case 'int':
              case 'bigint':
              case 'smallint':
              case 'tinyint':
              case 'decimal':
              case 'float':
              case 'double':
              case 'numeric':
                return '<数字>';
              case 'varchar':
              case 'text':
              case 'char':
              case 'longtext':
              case 'mediumtext':
                return '<字符串>';
              case 'date':
                return "'<日期>'";
              case 'datetime':
              case 'timestamp':
                return "'<日期时间>'";
              case 'bool':
              case 'boolean':
                return '<true/false>';
              default:
                return '<值>';
            }
          })
          .join(', ');
      if (i > 0) buffer.writeln(',');
      buffer.write('  ($placeholders)');
    }

    buffer.writeln(';');
    return buffer.toString();
  }

  /// 生成 UPDATE 语句模板
  Future<String> generateUpdateTemplate(String tableName) async {
    final columns = await _dbService.getTableColumns(tableName);
    final pkColumn = columns.firstWhere(
      (c) => c.isPrimaryKey,
      orElse: () => columns.first,
    );

    final buffer = StringBuffer();
    buffer.writeln('UPDATE $tableName SET');

    final setClauses = columns
        .where((c) => c.name != pkColumn.name)
        .map((c) => '  ${c.name} = <新值> /* ${c.type} */')
        .join(',\n');

    buffer.writeln(setClauses);
    buffer.writeln('WHERE ${pkColumn.name} = <条件值>;');
    buffer.writeln();
    buffer.writeln('-- 说明: 建议在 WHERE 条件中包含主键 ${pkColumn.name}');

    return buffer.toString();
  }

  /// 生成 DELETE 语句模板
  Future<String> generateDeleteTemplate(String tableName) async {
    final columns = await _dbService.getTableColumns(tableName);
    final pkColumn = columns.firstWhere(
      (c) => c.isPrimaryKey,
      orElse: () => columns.first,
    );

    final buffer = StringBuffer();
    buffer.writeln('-- 危险操作: DELETE 语句不可回滚，请谨慎执行');
    buffer.writeln();
    buffer.writeln('DELETE FROM $tableName');
    buffer.writeln('WHERE ${pkColumn.name} = <条件值>;');
    buffer.writeln();
    buffer.writeln('-- 建议: 先用 SELECT 确认要删除的记录');
    buffer.writeln(
      '-- SELECT * FROM $tableName WHERE ${pkColumn.name} = <条件值>;',
    );
    buffer.writeln('-- 确认后再执行 DELETE');

    return buffer.toString();
  }

  /// 生成完整的数据库 schema 描述（包含所有表和关系）
  Future<String> buildFullSchemaDescription() async {
    final buffer = StringBuffer();
    final currentServer = _dbService.currentServer;

    if (currentServer == null) {
      return '未连接到数据库';
    }

    buffer.writeln('# 数据库 Schema 完整描述');
    buffer.writeln();
    buffer.writeln('数据库类型: ${currentServer.type.displayName}');
    buffer.writeln('服务器: ${currentServer.host}:${currentServer.port}');
    buffer.writeln('当前数据库: ${currentServer.database ?? "未选择"}');
    buffer.writeln();

    try {
      final databases = await _dbService.getDatabases();
      buffer.writeln('## 数据库列表');
      for (final db in databases) {
        buffer.writeln('- $db');
      }
      buffer.writeln();

      if (currentServer.database != null) {
        final tables = await _dbService.getTables();
        buffer.writeln('## 表结构 (${tables.length} 个表)');

        for (final tableName in tables) {
          await _appendTableDetails(buffer, null, tableName: tableName);
        }
      }
    } catch (e) {
      buffer.writeln('获取 schema 信息失败: $e');
    }

    return buffer.toString();
  }

  Future<void> _appendTableDetails(
    StringBuffer buffer,
    DbTable? table, {
    String? tableName,
  }) async {
    final name = table?.name ?? tableName ?? '';
    final columns =
        table?.columns ??
        (tableName != null
            ? await _dbService.getTableColumns(tableName)
            : <DbColumn>[]);
    final indexes =
        table?.indexes ??
        (tableName != null
            ? await _dbService.getTableIndexes(tableName)
            : <DbIndex>[]);

    buffer.writeln('## 表: $name');

    // 列
    buffer.writeln('列:');
    for (final col in columns) {
      final pk = col.isPrimaryKey ? ' [PK]' : '';
      final nullable = col.isNullable ? ' [NULL]' : ' [NOT NULL]';
      final defaultVal = col.defaultValue != null
          ? ' DEFAULT ${col.defaultValue}'
          : '';
      buffer.writeln('  ${col.name}: ${col.type}$nullable$defaultVal$pk');
    }

    // 索引
    if (indexes.isNotEmpty) {
      buffer.writeln('索引:');
      for (final idx in indexes) {
        final unique = idx.isUnique ? ' UNIQUE' : '';
        buffer.writeln('  ${idx.name}: ${idx.columns.join(", ")}[$unique]');
      }
    }

    buffer.writeln();
  }
}
