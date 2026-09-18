// Phase E — dart:convert for JSON heuristic detection
import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite;
import '../database_abstract.dart';
import '../sqlite_alias_validator.dart';
import '../../models/database_models.dart';
import '../schema_diff/table_dependency_sorter.dart';
import '../../utils/app_logger.dart';
import '../sql_parser_service.dart';
import '../../models/sql_script_exception.dart';
import '../../utils/sql_escape_utils.dart';
import 'ai_adapter_mixin.dart';

/// SQLite 适配器实现（基于 sqflite_common_ffi）
///
/// SQLite 是文件型数据库，通过文件路径连接。
/// host 字段用于存储数据库文件路径。
class SQLiteAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware
    implements
        TransactionalAdapter,
        SqlSchemaAdapter,
        DdlAdapter,
        SqlScriptAdapter,
        JsonAdapter,
        PragmaAdapter,
        AttachAwareAdapter,
        MultiSchemaObjectAdapter {
  // Phase E — ^ JsonAdapter
  sqflite.Database? _db;
  DatabaseConnection? _currentConnection;
  bool _inTransaction = false;

  @override
  bool get isConnected => _db != null && _db!.isOpen;

  @override
  DatabaseType get databaseType => DatabaseType.sqlite;

  @override
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) {
    final escaped = tableName
        .split('.')
        .map(SqlEscapeUtils.escapePgIdentifier)
        .join('.');
    return 'SELECT * FROM $escaped LIMIT $limit;';
  }

  @override
  DatabaseConnection? get currentConnection => _currentConnection;

  /// feature 039 D3：刷新连接 readOnly（运行时开关实时生效）。
  @override
  void updateReadOnly(bool value) {
    _currentConnection = _currentConnection?.copyWith(readOnly: value);
  }

  String get _dbPath => _currentConnection?.host ?? '';

  @override
  Future<bool> connect(DatabaseConnection connection) async {
    try {
      sqflite.sqfliteFfiInit();
      final databaseFactory = sqflite.databaseFactoryFfi;

      _db = await databaseFactory.openDatabase(
        connection.host,
        options: sqflite.OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) {},
          singleInstance: false,
        ),
      );

      // 确保数据一致性和立即可见性
      await _db!.execute('PRAGMA journal_mode = DELETE');
      await _db!.execute('PRAGMA synchronous = FULL');

      _currentConnection = connection.copyWith(
        connected: true,
        connectedAt: DateTime.now(),
      );

      AppLogger.i('SQLiteAdapter', 'SQLite 连接成功: ${connection.host}');
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', 'SQLite 连接失败: ${connection.host}', e);
      return false;
    }
  }

  @override
  bool get isInTransaction => _inTransaction;

  @override
  bool get supportsSchemaOperations => true;

  @override
  Future<void> disconnect() async {
    if (_db != null && _db!.isOpen) {
      if (_inTransaction) {
        try {
          await rollback();
        } catch (_) {}
      }
      try {
        await _db!.close();
      } catch (e) {
        AppLogger.d('SQLiteAdapter', 'SQLite 断开连接时忽略错误: $e');
      }
      _db = null;
      _currentConnection = null;
      _inTransaction = false;
    }
  }

  @override
  Future<void> beginTransaction() async {
    if (!isConnected) throw Exception('未连接到数据库');
    await _db!.execute('BEGIN');
    _inTransaction = true;
  }

  @override
  Future<void> commit() async {
    if (!isConnected) throw Exception('未连接到数据库');
    await _db!.execute('COMMIT');
    _inTransaction = false;
  }

  @override
  Future<void> rollback() async {
    if (!isConnected) throw Exception('未连接到数据库');
    await _db!.execute('ROLLBACK');
    _inTransaction = false;
  }

  @override
  Future<String?> testConnection(DatabaseConnection connection) async {
    try {
      sqflite.sqfliteFfiInit();
      final databaseFactory = sqflite.databaseFactoryFfi;
      final db = await databaseFactory.openDatabase(
        connection.host,
        options: sqflite.OpenDatabaseOptions(singleInstance: false),
      );
      await db.close();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  @override
  Future<List<String>> getDatabases() async {
    // spec 050：ATTACH 跨库——反映真实附加状态（main + temp + 已附加 alias）。
    // 数据源 PRAGMA database_list，是附加库状态的唯一真相源。
    // temp 是 SQLite 内置临时库，UI 层（侧边栏树）负责过滤。
    if (!isConnected) return ['main'];
    final rows = await _db!.rawQuery(
      'SELECT name FROM pragma_database_list ORDER BY seq',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  @override
  Future<void> useDatabase(String dbName) async {
    // SQLite 不支持 USE 语句，单个文件只有一个数据库
    if (_currentConnection != null) {
      _currentConnection = _currentConnection!.copyWith(database: dbName);
    }
  }

  /// spec 050：返回限定到指定库（schemaName=alias）的 `sqlite_master` 表名。
  /// null/'main' 时返回未限定的 `sqlite_master`（保持既有行为）。
  /// schemaName 走白名单校验（由调用方保证合法标识符），避免拼接注入。
  String _qualifiedMaster([String? schemaName]) {
    if (schemaName == null || schemaName == 'main' || schemaName.isEmpty) {
      return 'sqlite_master';
    }
    // alias 已由 SqliteAliasValidator 校验为 ^[a-zA-Z_][a-zA-Z0-9_]*$，安全拼接。
    return '$schemaName.sqlite_master';
  }

  @override
  Future<List<String>> getTables({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final master = _qualifiedMaster(schemaName);
    final results = await _db!.rawQuery(
      "SELECT name FROM $master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return results.map((row) => row['name'] as String).toList();
  }

  @override
  Future<List<DbTableMetadata>> getTablesWithMetadata({
    String? database,
  }) async {
    // SQLite 禁用逐表 count(*)，避免大表全表扫描
    // 只返回表名列表，元信息为空，但标记 isApproximateCount 以触发后台精确计数
    final tableNames = await getTables(schemaName: database);
    return tableNames
        .map((name) => DbTableMetadata(name: name, isApproximateCount: true))
        .toList();
  }

  @override
  Future<DbTableMetadata> getTableMetadata(String tableName) async {
    // SQLite 不执行 count(*)，避免性能问题
    return DbTableMetadata(name: tableName);
  }

  @override
  Future<List<String>> getViews({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final master = _qualifiedMaster(schemaName);
    final results = await _db!.rawQuery(
      "SELECT name FROM $master WHERE type='view' ORDER BY name",
    );
    return results.map((row) => row['name'] as String).toList();
  }

  /// spec 050：MultiSchemaObjectAdapter 签名匹配（SQLite 无存储过程，返回空）。
  @override
  Future<List<String>> getProcedures({String? schemaName}) async {
    // SQLite 不支持存储过程
    return [];
  }

  /// spec 050：MultiSchemaObjectAdapter 签名匹配（SQLite 无自定义函数，返回空）。
  @override
  Future<List<String>> getFunctions({String? schemaName}) async {
    // SQLite 不支持自定义函数（除了内置函数）
    return [];
  }

  @override
  Future<List<String>> getEvents() async {
    // SQLite 不支持事件调度器
    return [];
  }

  /// [schemaName]（spec 050 ATTACH）：限定到附加库的 sqlite_master；
  /// null/'main' 保持未限定（既有行为）。
  @override
  Future<List<DbTrigger>> getTriggers({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final master = _qualifiedMaster(schemaName);
    final results = await _db!.rawQuery(
      "SELECT name, tbl_name, sql FROM $master WHERE type='trigger' ORDER BY name",
    );

    return results.map((row) {
      final sql = row['sql'] as String? ?? '';
      final name = row['name'] as String? ?? '';
      final table = row['tbl_name'] as String? ?? '';

      // Parse timing and event from CREATE TRIGGER statement
      String timing = 'UNKNOWN';
      String event = 'UNKNOWN';

      // Match pattern: CREATE TRIGGER name [BEFORE|AFTER|INSTEAD OF] [INSERT|UPDATE|DELETE] ON table
      final triggerRegex = RegExp(
        r'CREATE\s+TRIGGER\s+\S+\s+(BEFORE|AFTER|INSTEAD\s+OF)\s+(INSERT|UPDATE|DELETE)',
        caseSensitive: false,
      );
      final match = triggerRegex.firstMatch(sql);
      if (match != null) {
        timing = match.group(1)!.toUpperCase();
        event = match.group(2)!.toUpperCase();
      }

      return DbTrigger(
        name: name,
        event: event,
        table: table,
        timing: timing,
        statement: sql,
      );
    }).toList();
  }

  /// PRAGMA 限定的 schema 前缀（spec 050 ATTACH）：`PRAGMA <alias>.table_info(t)`
  /// 形态；null/'main' 无前缀（既有行为）。
  String _pragmaPrefix(String? schemaName) {
    if (schemaName == null || schemaName == 'main' || schemaName.isEmpty) {
      return '';
    }
    return '$schemaName.';
  }

  /// [schemaName]（spec 050 ATTACH）：附加库表的列信息需限定
  /// `PRAGMA <alias>.table_info`（未限定恒查 main——C16 登记存量缺陷的
  /// 列展开半边）。
  @override
  Future<List<DbColumn>> getTableColumns(
    String tableName, {
    String? schemaName,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await _db!.rawQuery(
      'PRAGMA ${_pragmaPrefix(schemaName)}table_info($tableName)',
    );

    return results.map((row) {
      final type = row['type'] as String? ?? 'TEXT';
      final notNull = (row['notnull'] as int?) == 1;
      final pk = (row['pk'] as int?) == 1;
      final defaultValue = row['dflt_value']?.toString();

      return DbColumn(
        name: row['name'] as String,
        type: type,
        isPrimaryKey: pk,
        isNullable: !notNull,
        defaultValue: defaultValue,
      );
    }).toList();
  }

  /// [schemaName]（spec 050 ATTACH）：附加库表的索引需限定
  /// `PRAGMA <alias>.index_list`（同 getTableColumns 的缺陷半边）。
  @override
  Future<List<DbIndex>> getTableIndexes(
    String tableName, {
    String? schemaName,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await _db!.rawQuery(
      'PRAGMA ${_pragmaPrefix(schemaName)}index_list($tableName)',
    );
    final indexes = <DbIndex>[];

    for (final row in results) {
      final indexName = row['name'] as String;
      final isUnique = (row['unique'] as int?) == 1;
      final origin = row['origin'] as String?;

      // 跳过自动创建的索引（如主键索引）
      if (origin == 'pk') continue;

      final indexInfo = await _db!.rawQuery('PRAGMA index_info($indexName)');
      final columns = indexInfo.map((r) => r['name'] as String).toList();

      indexes.add(
        DbIndex(name: indexName, columns: columns, isUnique: isUnique),
      );
    }

    return indexes;
  }

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final results = await _db!.rawQuery(
        'PRAGMA foreign_key_list("$tableName")',
      );
      final fks = <ForeignKey>[];
      final seenIds = <int>{};

      for (final row in results) {
        final id = row['id'] as int;
        if (seenIds.contains(id)) continue;
        seenIds.add(id);

        fks.add(
          ForeignKey(
            name: 'fk_$id',
            table: tableName,
            column: row['from']?.toString() ?? '',
            referencedTable: row['table']?.toString() ?? '',
            referencedColumn: row['to']?.toString() ?? '',
            onUpdate: row['on_update']?.toString(),
            onDelete: row['on_delete']?.toString(),
          ),
        );
      }
      return fks;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', 'getForeignKeys failed', e);
      return [];
    }
  }

  @override
  Future<DbTable> getTableDetails(String tableName) async {
    final columns = await getTableColumns(tableName);
    final indexes = await getTableIndexes(tableName);

    return DbTable(name: tableName, columns: columns, indexes: indexes);
  }

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    // feature 039 只读守卫——query-tab SQL + sidebar/AI DDL 经此汇聚。
    guardReadOnlyQuery(sql, operation: 'executeQuery');
    if (!isConnected) throw Exception('未连接到数据库');

    final startTime = DateTime.now();

    try {
      final trimmedSql = sql.trim().toUpperCase();
      final isSelect =
          trimmedSql.startsWith('SELECT') ||
          trimmedSql.startsWith('EXPLAIN') ||
          trimmedSql.startsWith('PRAGMA');
      final isInsert = trimmedSql.startsWith('INSERT');
      final isDelete = trimmedSql.startsWith('DELETE');

      if (isSelect) {
        final results = await _db!.rawQuery(sql);
        final columns = <String>[];
        final rows = <Map<String, dynamic>>[];

        for (final row in results) {
          rows.add(Map<String, dynamic>.from(row));
          if (columns.isEmpty) {
            columns.addAll(row.keys);
          }
        }

        // T032: SQLite 无 JSON 类型，用启发式检测（前 5 非空值 ≥80% 可解析为
        // JSON 且以 {/[ 开头 → 标 json_detected）。跨库 JSONB 支持。
        final columnTypes = _detectJsonColumns(columns, rows);

        return QueryResult(
          columns: columns,
          rows: rows,
          affectedRows: rows.length,
          executionTime: DateTime.now().difference(startTime).inMilliseconds,
          columnTypes: columnTypes.isEmpty ? null : columnTypes,
        );
      } else if (isInsert) {
        final id = await _db!.rawInsert(sql);
        return QueryResult(
          columns: [],
          rows: [],
          affectedRows: id > 0 ? 1 : 0,
          executionTime: DateTime.now().difference(startTime).inMilliseconds,
        );
      } else if (isDelete) {
        final affectedRows = await _db!.rawDelete(sql);
        return QueryResult(
          columns: [],
          rows: [],
          affectedRows: affectedRows,
          executionTime: DateTime.now().difference(startTime).inMilliseconds,
        );
      } else {
        final affectedRows = await _db!.rawUpdate(sql);
        return QueryResult(
          columns: [],
          rows: [],
          affectedRows: affectedRows,
          executionTime: DateTime.now().difference(startTime).inMilliseconds,
        );
      }
    } catch (e) {
      throw Exception('查询执行失败: $e');
    }
  }

  @override
  Future<QueryResult> getExplainPlan(String sql) async {
    if (!isConnected) throw Exception('未连接到数据库');
    return await executeQuery('EXPLAIN QUERY PLAN $sql');
  }

  @override
  Future<Map<String, dynamic>?> getServerVersion() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await _db!.rawQuery('SELECT sqlite_version() as version');
    return {'version': results.first['version'], 'database': 'SQLite'};
  }

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final encoding = await _db!.rawQuery('PRAGMA encoding');
    return {'encoding': encoding.first['encoding'], 'file': _dbPath};
  }

  // ==========================================================================
  // spec 050：ATTACH 跨库（AttachAwareAdapter 实现）
  //
  // alias 是 SQLite 标识符，不能参数化（`ATTACH ? AS ?` 第二个占位符 SQLite 不接受），
  // 故 alias 由调用方经 [SqliteAliasValidator] 校验后传入，这里手拼但保证安全。
  // path 走参数化绑定。失败抛原生错误，由 UI 层 SnackBar 透传。
  // ==========================================================================

  @override
  Future<void> attachDatabase(String path, String alias) async {
    if (!isConnected) throw Exception('未连接到数据库');
    // 双保险：调用方已校验，adapter 层再校验一次防绕过。
    final err = SqliteAliasValidator.validate(alias);
    if (err != null) {
      throw ArgumentError.value(alias, 'alias', '非法 SQLite alias: $err');
    }
    // path 参数化绑定；alias 已校验为合法标识符，安全手拼。
    await _db!.execute('ATTACH DATABASE ? AS $alias', [path]);
  }

  @override
  Future<void> detachDatabase(String alias) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final err = SqliteAliasValidator.validate(alias);
    if (err != null) {
      throw ArgumentError.value(alias, 'alias', '非法 SQLite alias: $err');
    }
    await _db!.execute('DETACH DATABASE $alias');
  }

  @override
  Future<List<AttachedDatabaseInfo>> listAttachedDatabases() async {
    if (!isConnected) throw Exception('未连接到数据库');
    final rows = await _db!.rawQuery(
      'SELECT seq, name, file FROM pragma_database_list ORDER BY seq',
    );
    return rows
        .map(
          (r) => AttachedDatabaseInfo(
            seq: (r['seq'] as num?)?.toInt() ?? 0,
            name: r['name'] as String,
            file: r['file'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<bool> createDatabase(
    String dbName, {
    Map<String, dynamic>? options,
  }) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'createDatabase');
    // SQLite 的数据库就是文件本身，创建连接时已自动创建。
    // 旧的 ATTACH 脚手架保留向后兼容（通用 createDatabase 接口），但 spec 050
    // 的新 UI 走专用 [attachDatabase]（带 alias 校验 + 状态反映），不经过这里。
    if (dbName == 'main') return true;

    try {
      final path = options?['path'] as String? ?? '$dbName.db';
      await _db!.execute('ATTACH DATABASE ? AS $dbName', [path]);
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '创建数据库失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropDatabase(String dbName) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'dropDatabase');
    // SQLite 没有 DROP DATABASE 语句，直接删除文件
    try {
      await disconnect();
      // 文件删除由调用方处理
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '删除数据库失败', e);
      return false;
    }
  }

  @override
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    Map<String, dynamic>? options,
  }) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'createTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final columnDefs = columns
          .map((col) {
            String def = '"${col.name}" ${col.type}';
            if (col.isPrimaryKey) def += ' PRIMARY KEY';
            if (!col.isNullable) def += ' NOT NULL';
            if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
            return def;
          })
          .join(', ');

      await _db!.execute(
        'CREATE TABLE IF NOT EXISTS "$tableName" ($columnDefs)',
      );
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '创建表失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropTable(String tableName) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'dropTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await _db!.execute('DROP TABLE IF EXISTS "$tableName"');
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '删除表失败', e);
      return false;
    }
  }

  @override
  Future<bool> renameTable(String oldName, String newName) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'renameTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await _db!.execute('ALTER TABLE "$oldName" RENAME TO "$newName"');
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '重命名表失败', e);
      return false;
    }
  }

  @override
  Future<bool> truncateTable(
    String tableName, {
    TruncateOptions? options,
  }) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'truncateTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await _db!.execute('DELETE FROM "$tableName"');
      await _db!.execute('VACUUM');
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '清空表失败', e);
      return false;
    }
  }

  @override
  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final escapedTable = '"$tableName"';
    if (cursorColumn != null && cursorValue != null) {
      final escapedColumn = '"$cursorColumn"';
      final escapedValue = "'${cursorValue.toString().replaceAll("'", "''")}'";
      return await executeQuery(
        'SELECT * FROM $escapedTable WHERE $escapedColumn > $escapedValue ORDER BY $escapedColumn LIMIT $limit',
      );
    }
    return await executeQuery(
      'SELECT * FROM $escapedTable LIMIT $limit OFFSET $offset',
    );
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await _db!.rawQuery(
      'SELECT COUNT(*) as count FROM "$tableName"',
    );
    return (results.first['count'] as int?) ?? 0;
  }

  @override
  Future<bool> addColumn(String tableName, DbColumn column) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'addColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      String def = 'ADD COLUMN "${column.name}" ${column.type}';
      if (!column.isNullable) def += ' NOT NULL';
      if (column.defaultValue != null) def += ' DEFAULT ${column.defaultValue}';

      await _db!.execute('ALTER TABLE "$tableName" $def');
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '添加列失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropColumn(String tableName, String columnName) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'dropColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await _db!.execute('ALTER TABLE "$tableName" DROP COLUMN "$columnName"');
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '删除列失败', e);
      return false;
    }
  }

  @override
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'renameColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final columns = await getTableColumns(tableName);
      final indexes = await getTableIndexes(tableName);

      // 构建新的列定义（只修改列名）
      final newColumnDefs = columns
          .map((col) {
            String def =
                '"${col.name == oldColumnName ? newColumnName : col.name}" ${col.type}';
            if (!col.isNullable) def += ' NOT NULL';
            if (col.defaultValue != null && col.defaultValue!.isNotEmpty) {
              def += ' DEFAULT ${col.defaultValue}';
            }
            return def;
          })
          .join(', ');

      // 构建 SELECT 和 INSERT 列映射
      final selectColumns = columns
          .map(
            (col) => col.name == oldColumnName
                ? '"${col.name}" AS "$newColumnName"'
                : '"${col.name}"',
          )
          .join(', ');

      final insertColumns = columns
          .map(
            (col) =>
                '"${col.name == oldColumnName ? newColumnName : col.name}"',
          )
          .join(', ');

      // 保存索引创建语句
      final indexStatements = <String>[];
      for (final index in indexes) {
        final colNames = index.columns.map((c) => '"$c"').join(', ');
        final uniqueStr = index.isUnique ? 'UNIQUE ' : '';
        indexStatements.add(
          'CREATE ${uniqueStr}INDEX IF NOT EXISTS "${index.name}" ON "$tableName" ($colNames)',
        );
      }

      // 重建表
      await _db!.execute('PRAGMA foreign_keys = OFF');
      await _db!.execute('BEGIN TRANSACTION');

      try {
        await _db!.execute(
          'ALTER TABLE "$tableName" RENAME TO "${tableName}_temp_old"',
        );
        await _db!.execute('CREATE TABLE "$tableName" ($newColumnDefs)');
        await _db!.execute(
          'INSERT INTO "$tableName" ($insertColumns) SELECT $selectColumns FROM "${tableName}_temp_old"',
        );
        for (final stmt in indexStatements) {
          await _db!.execute(stmt);
        }
        await _db!.execute('DROP TABLE "${tableName}_temp_old"');
        await _db!.execute('COMMIT');
        await _db!.execute('PRAGMA foreign_keys = ON');
        return true;
      } catch (e) {
        await _db!.execute('ROLLBACK');
        rethrow;
      }
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '重命名列失败', e);
      try {
        await _db!.execute('PRAGMA foreign_keys = ON');
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'modifyColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      // SQLite 不支持 ALTER COLUMN，需要使用重建表的方式
      // 获取当前表的所有列和索引
      final columns = await getTableColumns(tableName);
      final indexes = await getTableIndexes(tableName);

      // 构建新的列定义
      final newColumnDefs = columns
          .map((col) {
            if (col.name == oldColumnName) {
              String def = '"${newColumn.name}" ${newColumn.type}';
              if (!newColumn.isNullable) def += ' NOT NULL';
              if (newColumn.defaultValue != null &&
                  newColumn.defaultValue!.isNotEmpty) {
                def += ' DEFAULT ${newColumn.defaultValue}';
              }
              return def;
            } else {
              String def = '"${col.name}" ${col.type}';
              if (!col.isNullable) def += ' NOT NULL';
              if (col.defaultValue != null && col.defaultValue!.isNotEmpty) {
                def += ' DEFAULT ${col.defaultValue}';
              }
              return def;
            }
          })
          .join(', ');

      // 构建 SELECT 和 INSERT 列映射（处理列名变化）
      final selectColumns = columns
          .map(
            (col) =>
                col.name == oldColumnName && newColumn.name != oldColumnName
                ? '"${col.name}" AS "${newColumn.name}"'
                : '"${col.name}"',
          )
          .join(', ');

      final insertColumns = columns
          .map(
            (col) => col.name == oldColumnName
                ? '"${newColumn.name}"'
                : '"${col.name}"',
          )
          .join(', ');

      // 保存索引创建语句
      final indexStatements = <String>[];
      for (final index in indexes) {
        final colNames = index.columns.map((c) => '"$c"').join(', ');
        final uniqueStr = index.isUnique ? 'UNIQUE ' : '';
        indexStatements.add(
          'CREATE ${uniqueStr}INDEX IF NOT EXISTS "${index.name}" ON "$tableName" ($colNames)',
        );
      }

      // 重建表
      await _db!.execute('PRAGMA foreign_keys = OFF');
      await _db!.execute('BEGIN TRANSACTION');

      try {
        // 重命名旧表
        await _db!.execute(
          'ALTER TABLE "$tableName" RENAME TO "${tableName}_temp_old"',
        );

        // 创建新表
        await _db!.execute('CREATE TABLE "$tableName" ($newColumnDefs)');

        // 迁移数据
        await _db!.execute(
          'INSERT INTO "$tableName" ($insertColumns) SELECT $selectColumns FROM "${tableName}_temp_old"',
        );

        // 重建索引
        for (final stmt in indexStatements) {
          await _db!.execute(stmt);
        }

        // 删除旧表
        await _db!.execute('DROP TABLE "${tableName}_temp_old"');

        await _db!.execute('COMMIT');
        await _db!.execute('PRAGMA foreign_keys = ON');
        return true;
      } catch (e) {
        await _db!.execute('ROLLBACK');
        rethrow;
      }
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '修改列失败', e);
      try {
        await _db!.execute('PRAGMA foreign_keys = ON');
      } catch (_) {}
      return false;
    }
  }

  @override
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  }) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'createIndex');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final colNames = columns.map((c) => '"$c"').join(', ');
      final uniqueStr = unique ? 'UNIQUE ' : '';
      await _db!.execute(
        'CREATE ${uniqueStr}INDEX IF NOT EXISTS "$indexName" ON "$tableName" ($colNames)',
      );
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '创建索引失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropIndex(String tableName, String indexName) async {
    // feature 039 只读守卫（双保险）。
    guardReadOnly(operation: 'dropIndex');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await _db!.execute('DROP INDEX IF EXISTS "$indexName"');
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '删除索引失败', e);
      return false;
    }
  }

  @override
  Future<String> exportDatabaseStructure(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final sb = StringBuffer();
    sb.writeln('-- SQLite Database: $_dbPath');
    sb.writeln('-- Generated by DBMaster');
    sb.writeln('-- Date: ${DateTime.now().toIso8601String()}');
    sb.writeln();

    final tables = await getTables();

    // Collect FK dependencies for topological sort
    final fksMap = <String, List<ForeignKey>>{};
    for (final table in tables) {
      fksMap[table] = await getForeignKeys(table);
    }

    // Build dependency map for the topological sorter
    final sortMap = <String, String>{};
    for (final table in tables) {
      final fks = fksMap[table] ?? [];
      sortMap[table] = fks.isNotEmpty
          ? 'CREATE TABLE "$table" (${fks.map((fk) => 'FOREIGN KEY ("${fk.column}") REFERENCES "${fk.referencedTable}" ("${fk.referencedColumn}")').join(', ')})'
          : 'CREATE TABLE "$table" (id INT)';
    }

    final sortedTables = TableDependencySorter.sortByCreateOrder(sortMap);

    for (final table in sortedTables) {
      final details = await getTableDetails(table);
      final fks = fksMap[table] ?? [];
      sb.writeln('-- Table: $table');
      sb.writeln(
        _buildCreateTableExportSql(
          table,
          details.columns,
          details.indexes,
          fks,
        ),
      );
      sb.writeln();

      // 导出索引
      for (final idx in details.indexes) {
        final unique = idx.isUnique ? 'UNIQUE ' : '';
        sb.writeln(
          'CREATE ${unique}INDEX "${idx.name}" ON "$table" (${idx.columns.map((c) => '"$c"').join(', ')});',
        );
      }
      if (details.indexes.isNotEmpty) sb.writeln();
    }

    return sb.toString();
  }

  String _buildCreateTableExportSql(
    String tableName,
    List<DbColumn> columns,
    List<DbIndex> indexes,
    List<ForeignKey> foreignKeys,
  ) {
    final buf = StringBuffer();
    buf.writeln('CREATE TABLE "$tableName" (');

    final pkColumns = columns.where((c) => c.isPrimaryKey).toList();
    final hasCompositePk = pkColumns.length > 1;
    final filteredIndexes = indexes.where((i) => i.name != 'PRIMARY').toList();

    final parts = <String>[];
    for (final col in columns) {
      String def = '  "${col.name}" ${col.type}';
      if (col.isPrimaryKey && !hasCompositePk) def += ' PRIMARY KEY';
      if (!col.isNullable) def += ' NOT NULL';
      if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
      parts.add(def);
    }
    if (hasCompositePk) {
      final pkColList = pkColumns.map((c) => '"${c.name}"').join(', ');
      parts.add('  PRIMARY KEY ($pkColList)');
    }
    for (final idx in filteredIndexes) {
      final unique = idx.isUnique ? 'UNIQUE ' : '';
      final colList = idx.columns.map((c) => '"$c"').join(', ');
      parts.add('  ${unique}INDEX "${idx.name}" ($colList)');
    }
    for (final fk in foreignKeys) {
      parts.add(
        '  FOREIGN KEY ("${fk.column}") REFERENCES "${fk.referencedTable}" ("${fk.referencedColumn}")',
      );
    }
    buf.writeln(parts.join(',\n'));
    buf.write(');');
    return buf.toString();
  }

  @override
  Future<bool> executeSqlScript(String script) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // U08：SQL-aware 分割 + 逐条执行 + 失败定位（语句序号/行号/已执行条数）。
    // 旧实现吞错返回 false——失败原因与部分提交状态均不可见。
    final statements = SQLParserService.split(script);
    var executed = 0;
    try {
      for (final statement in statements) {
        try {
          await _db!.execute(statement.sql);
        } catch (e) {
          throw SqlScriptExecutionException(
            statementIndex: statement.index,
            lineStart: statement.lineStart,
            lineEnd: statement.lineEnd,
            statementSql: statement.sql,
            cause: e.toString(),
            committedCount: executed,
          );
        }
        executed++;
      }
      return true;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', '执行脚本失败', e);
      rethrow;
    }
  }

  @override
  Future<List<String>> getCharsets() async {
    // SQLite 只支持 UTF-8、UTF-16le、UTF-16be
    return ['UTF-8', 'UTF-16le', 'UTF-16be'];
  }

  @override
  Future<List<Map<String, String>>> getCollations({String? charset}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await _db!.rawQuery('PRAGMA collation_list');
    return results
        .map((row) => {'name': row['name'] as String, 'charset': 'UTF-8'})
        .toList();
  }

  // ============================================================================
  // Phase E — JsonAdapter with heuristic JSON detection
  // ============================================================================

  @override
  Future<List<String>> getJsonColumns(String tableName) async {
    if (!isConnected) return [];
    try {
      final pragmaResult =
          await _db!.rawQuery('PRAGMA table_info("$tableName")');
      final columns =
          pragmaResult.map((r) => r['name'].toString()).toList();

      final jsonColumns = <String>[];
      for (final col in columns) {
        final isJson = await isJsonColumn(tableName, col);
        if (isJson) jsonColumns.add(col);
      }
      return jsonColumns;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', 'getJsonColumns($tableName) failed', e);
      return [];
    }
  }

  /// T032: 启发式检测结果集中的 JSON 列（不依赖表名）。
  /// 每列取前 5 个非空值，≥80% 可解析为 JSON 且以 {/[ 开头 → 标 'json_detected'。
  Map<String, String> _detectJsonColumns(
      List<String> columns, List<Map<String, dynamic>> rows) {
    final result = <String, String>{};
    if (columns.isEmpty || rows.isEmpty) return result;

    for (final col in columns) {
      final samples = rows
          .map((r) => r[col])
          .where((v) => v != null)
          .take(5)
          .toList();
      if (samples.isEmpty) continue;

      int jsonCount = 0;
      for (final value in samples) {
        final str = value.toString().trim();
        if (!(str.startsWith('{') || str.startsWith('['))) continue;
        try {
          json.decode(str);
          jsonCount++;
        } catch (_) {
          // not valid JSON
        }
      }
      if ((jsonCount / samples.length) >= 0.8) {
        result[col] = 'json_detected';
      }
    }
    return result;
  }

  Future<bool> isJsonColumn(String tableName, String columnName) async {
    if (!isConnected) return false;
    try {
      final result = await _db!.rawQuery(
        'SELECT "$columnName" FROM "$tableName" '
        'WHERE "$columnName" IS NOT NULL LIMIT 5',
      );
      if (result.isEmpty) return false;

      final sampleValues = result
          .map((row) => row[columnName])
          .where((v) => v != null)
          .toList();
      if (sampleValues.isEmpty) return false;

      int jsonCount = 0;
      for (final value in sampleValues) {
        final str = value.toString();
        if (!(str.trim().startsWith('{') || str.trim().startsWith('['))) {
          continue;
        }
        try {
          json.decode(str);
          jsonCount++;
        } catch (_) {
          // Not valid JSON
        }
      }

      return sampleValues.isNotEmpty &&
          (jsonCount / sampleValues.length) >= 0.8;
    } catch (e) {
      AppLogger.e('SQLiteAdapter', 'isJsonColumn failed', e);
      return false;
    }
  }

  // ============================================================================
  // 维护操作（SQLite 专属，不走 executeQuery 的 rawUpdate 分支）
  //
  // 设计：VACUUM/OPTIMIZE 不以 SELECT/INSERT/DELETE/PRAGMA 开头，落 executeQuery
  // 的 else 分支（rawUpdate），对 VACUUM 这种无受影响行数的命令不稳健。这里用
  // _db!.execute 直接跑（与 truncateTable 同模式）。integrity_check 是查询走
  // rawQuery 取全部行（_readPragmaValue 只取第一行会截断错误）。
  //
  // 不加到 DatabaseAdapter 基类——SQLite 专属概念；调用方用类型检查访问：
  //   if (adapter is SQLiteAdapter) await adapter.vacuum();
  // ============================================================================

  /// VACUUM — 回收空闲页、重建数据库文件。**锁库、不可逆**。
  ///
  /// 右键菜单的「VACUUM」目前仍走「预填 SQL 到新 Tab」安全闸（让用户手动 Run
  /// 走完整安全审查门）；本方法提供干净 API 供状态栏/未来功能/编程式调用。
  /// VACUUM 不能在事务内执行，sqflite 的 _db!.execute 不开事务，安全。
  Future<QueryResult> vacuum() async {
    guardReadOnly(operation: 'vacuum');
    if (!isConnected) throw Exception('未连接到数据库');
    final startTime = DateTime.now();
    await _db!.execute('VACUUM');
    return QueryResult(
      columns: [],
      rows: [],
      affectedRows: 0,
      message: 'VACUUM completed',
      executionTime: DateTime.now().difference(startTime).inMilliseconds,
    );
  }

  /// PRAGMA integrity_check — 返回**全部行**。
  ///
  /// 正常 = 单行 `{integrity_check: ok}`；异常 = 多行错误描述。
  /// 与 `_readPragmaValue('integrity_check')` 不同（后者只取第一行第一列，
  /// 会截断多行错误），本方法保留所有行供诊断。
  Future<QueryResult> integrityCheck() async {
    if (!isConnected) throw Exception('未连接到数据库');
    final startTime = DateTime.now();
    final results = await _db!.rawQuery('PRAGMA integrity_check;');
    final rows = results.map((r) => Map<String, dynamic>.from(r)).toList();
    return QueryResult(
      columns: rows.isNotEmpty ? rows.first.keys.toList() : const ['integrity_check'],
      rows: rows,
      affectedRows: rows.length,
      executionTime: DateTime.now().difference(startTime).inMilliseconds,
    );
  }

  /// PRAGMA optimize — SQLite 3.x+ 推荐的轻量优化（基于统计信息重建部分索引）。
  ///
  /// 与 sqlite_tree_builder 的 `_optimizeDatabase`（ANALYZE+REINDEX+VACUUM 三连，
  /// 深度优化）不同，这是 SQLite 官方推荐的轻量版，可在连接关闭前安全调用。
  Future<QueryResult> optimize() async {
    guardReadOnly(operation: 'optimize');
    if (!isConnected) throw Exception('未连接到数据库');
    final startTime = DateTime.now();
    await _db!.execute('PRAGMA optimize;');
    return QueryResult(
      columns: [],
      rows: [],
      affectedRows: 0,
      message: 'PRAGMA optimize completed',
      executionTime: DateTime.now().difference(startTime).inMilliseconds,
    );
  }

  /// 把当前数据库事务一致地复制到 [destPath]（VACUUM INTO 策略）。
  ///
  /// 产出干净 DELETE 模式单文件（无 -wal/-shm）、自动瘦身碎片。WAL 模式下也
  /// 安全——`VACUUM INTO` 会把已提交的 WAL 事务合并进目标（裸拷贝 .db 会丢）。
  /// **源库不受影响**（仅读锁、不阻塞写）→ 不加 `guardReadOnly`（语义同
  /// [integrityCheck]：源库只读，只读连接仍可导出副本，合理）。
  ///
  /// SQLite ≥ 3.27.0 才支持 VACUUM INTO（sqflite_common_ffi 内嵌版本远新）。
  /// `destPath` 含单引号会被拒绝——VACUUM INTO 的文件名 token 不支持参数绑定，
  /// 手动防注入。
  Future<QueryResult> saveAs(String destPath) async {
    if (!isConnected) throw Exception('未连接到数据库');
    // VACUUM INTO 的文件名 token 不支持参数绑定，手动防注入
    if (destPath.contains("'")) {
      throw ArgumentError('目标路径不能包含单引号: $destPath');
    }
    final startTime = DateTime.now();
    await _db!.execute("VACUUM INTO '$destPath'");
    return QueryResult(
      columns: [],
      rows: [],
      affectedRows: 0,
      message: 'VACUUM INTO completed',
      executionTime: DateTime.now().difference(startTime).inMilliseconds,
    );
  }

  // ============================================================================
  // PragmaAdapter（PRAGMA Explorer）
  // ============================================================================

  /// 已知 PRAGMA 元信息目录（name / category / description / writable）。
  /// adapter 遍历它查当前值。
  static const _pragmaCatalog = <PragmaInfo>[
    // 性能
    PragmaInfo(name: 'cache_size', category: PragmaCategory.performance, description: 'Number of pages in the in-memory page cache (negative = KiB)'),
    PragmaInfo(name: 'mmap_size', category: PragmaCategory.performance, description: 'Maximum bytes of memory-mapped I/O'),
    PragmaInfo(name: 'page_size', category: PragmaCategory.performance, description: 'Page size in bytes (power of 2)'),
    PragmaInfo(name: 'temp_store', category: PragmaCategory.performance, description: 'Where temporary tables and indices are stored (0=default, 1=file, 2=memory)'),
    // 持久性
    PragmaInfo(name: 'synchronous', category: PragmaCategory.durability, description: 'FSync level (0=OFF, 1=NORMAL, 2=FULL, 3=EXTRA)'),
    PragmaInfo(name: 'journal_mode', category: PragmaCategory.durability, description: 'Journal mode (DELETE/TRUNCATE/PERSIST/MEMORY/WAL/OFF)'),
    PragmaInfo(name: 'wal_autocheckpoint', category: PragmaCategory.durability, description: 'WAL auto-checkpoint threshold in pages (0=disabled)'),
    PragmaInfo(name: 'wal_checkpoint', category: PragmaCategory.durability, description: 'WAL checkpoint status (PASSIVE/FULL/RESTART/TRUNCATE)', writable: false),
    // 安全
    PragmaInfo(name: 'foreign_keys', category: PragmaCategory.security, description: 'Enforce foreign key constraints (0=OFF, 1=ON)'),
    PragmaInfo(name: 'recursive_triggers', category: PragmaCategory.security, description: 'Allow recursive trigger firing (0=OFF, 1=ON)'),
    PragmaInfo(name: 'defer_foreign_keys', category: PragmaCategory.security, description: 'Defer FK enforcement until transaction commit (0=OFF, 1=ON)'),
    // 调试
    PragmaInfo(name: 'encoding', category: PragmaCategory.debug, description: 'Text encoding (UTF-8/UTF-16le/UTF-16be)', writable: false),
    PragmaInfo(name: 'integrity_check', category: PragmaCategory.debug, description: 'Database integrity check result', writable: false),
    PragmaInfo(name: 'application_id', category: PragmaCategory.debug, description: 'Application-specific database ID (32-bit integer)'),
    PragmaInfo(name: 'user_version', category: PragmaCategory.debug, description: 'User-defined database version number (32-bit integer)'),
  ];

  @override
  Future<List<PragmaInfo>> getPragmas() async {
    if (!isConnected) return [];
    final results = <PragmaInfo>[];
    for (final meta in _pragmaCatalog) {
      try {
        final value = await _readPragmaValue(meta.name);
        results.add(meta.copyWithCurrentValue(value));
      } catch (e) {
        AppLogger.w('SQLiteAdapter', 'PRAGMA ${meta.name} read failed: $e');
        results.add(meta.copyWithCurrentValue(null));
      }
    }
    return results;
  }

  @override
  Future<PragmaInfo> setPragma(String name, String value) async {
    guardReadOnly(operation: 'setPragma');
    if (!isConnected) throw Exception('未连接到数据库');
    // 找到 catalog 里的 meta（校验是已知 PRAGMA）
    final meta = _pragmaCatalog.firstWhere(
      (p) => p.name == name,
      orElse: () => throw Exception('unknown PRAGMA: $name'),
    );
    // 执行 PRAGMA name = value（参数化不适用 PRAGMA，但 name 来自 catalog 白名单）
    await _db!.execute("PRAGMA $name = $value");
    // 重新查确认新值
    final newValue = await _readPragmaValue(name);
    return meta.copyWithCurrentValue(newValue);
  }

  /// 读单个 PRAGMA 的当前值。
  /// 对返回多列的 PRAGMA（如 integrity_check / wal_checkpoint）取第一行拼接。
  Future<String?> _readPragmaValue(String name) async {
    final rows = await _db!.rawQuery('PRAGMA $name');
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row.values.isEmpty) return null;
    // 大多数 PRAGMA 返回单列（如 {journal_mode: wal}）。
    // integrity_check 返回多行（如 {integrity_check: ok}），取第一行第一列。
    // compile_options 返回多行多列，取第一行所有值拼接。
    final firstValue = row.values.first?.toString() ?? '';
    return firstValue;
  }
}
