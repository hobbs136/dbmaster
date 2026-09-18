import '../models/stored_procedure.dart';
import 'database_abstract.dart';
import 'database_service.dart';
import 'readonly_guard.dart';
import '../utils/app_logger.dart';
import '../utils/sql_escape_utils.dart';

class StoredProcedureService {
  final DatabaseService _dbService;

  StoredProcedureService(this._dbService);

  /// T29：MySQL 族已迁网关壳——经当前连接的 adapter 执行（原裸 MySQLConnection
  /// 通道下线）。行取值按列序位置（网关行是列名 map，保持插入序）。
  DatabaseAdapter? _getAdapter() => _dbService.currentAdapter;

  static String? _colAt(Map<String, dynamic> row, int i) {
    final values = row.values.toList();
    return i < values.length ? values[i]?.toString() : null;
  }

  /// 显式目标库谓词。默认 `DATABASE()` 依赖连接级会话的 USE 状态——
  /// 而现代流程「选库」只做元数据查询（changeDatabase 不发 USE，USE 归
  /// per-tab 查询会话），连接级会话的 DATABASE() 常为 NULL → 恒空列表
  /// （C14 E2E 实测）。调用方应传当前工作库。
  String _schemaPredicateFor(String? database) =>
      database == null ? 'DATABASE()' : SqlEscapeUtils.escapeString(database);

  /// 获取存储过程列表。[database] 为空时按连接会话当前库（历史语义，
  /// 见 [_schemaPredicateFor] 注释——通常应为空）。
  ///
  /// 历史缺陷（C14 真库 E2E 实锤）：SELECT 里的 `PARAMETER_COUNT` 列在
  /// MySQL information_schema.ROUTINES 中**不存在**（error 1054），被
  /// catch-返回空列表吞掉 → 对话框自诞生起恒空。该列本就无人消费
  /// （参数来自 information_schema.PARAMETERS），已删除；列序相应前移。
  Future<List<StoredProcedure>> getStoredProcedures({String? database}) async {
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) return [];

    final results = await adapter.executeQuery('''
      SELECT
        ROUTINE_NAME,
        ROUTINE_TYPE,
        DTD_IDENTIFIER,
        ROUTINE_DEFINITION,
        CREATED,
        LAST_ALTERED
      FROM information_schema.ROUTINES
      WHERE ROUTINE_TYPE = 'PROCEDURE'
        AND ROUTINE_SCHEMA = ${_schemaPredicateFor(database)}
      ORDER BY ROUTINE_NAME
    ''');

    final procedures = <StoredProcedure>[];
    for (final row in results.rows) {
      final name = _colAt(row, 0) ?? '';
      final params = await _getParameters(
        name,
        ProcedureType.procedure,
        database: database,
      );
      procedures.add(
        StoredProcedure(
          name: name,
          type: ProcedureType.procedure,
          parameters: params,
          definition: _colAt(row, 3),
          createdAt: _parseDateTime(_colAt(row, 4)),
          modifiedAt: _parseDateTime(_colAt(row, 5)),
        ),
      );
    }
    return procedures;
  }

  Future<List<StoredProcedure>> getFunctions({String? database}) async {
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) return [];

    final results = await adapter.executeQuery('''
      SELECT
        ROUTINE_NAME,
        ROUTINE_TYPE,
        DTD_IDENTIFIER,
        ROUTINE_DEFINITION,
        CREATED,
        LAST_ALTERED
      FROM information_schema.ROUTINES
      WHERE ROUTINE_TYPE = 'FUNCTION'
        AND ROUTINE_SCHEMA = ${_schemaPredicateFor(database)}
      ORDER BY ROUTINE_NAME
    ''');

    final functions = <StoredProcedure>[];
    for (final row in results.rows) {
      final name = _colAt(row, 0) ?? '';
      final returnType = _colAt(row, 2);
      final params = await _getParameters(
        name,
        ProcedureType.function,
        database: database,
      );
      functions.add(
        StoredProcedure(
          name: name,
          type: ProcedureType.function,
          parameters: params,
          returnType: returnType,
          definition: _colAt(row, 3),
          createdAt: _parseDateTime(_colAt(row, 4)),
          modifiedAt: _parseDateTime(_colAt(row, 5)),
        ),
      );
    }
    return functions;
  }

  Future<List<StoredProcedure>> getAllRoutines({String? database}) async {
    final procedures = await getStoredProcedures(database: database);
    final functions = await getFunctions(database: database);
    return [...procedures, ...functions];
  }

  Future<List<ProcedureParameter>> _getParameters(
    String routineName,
    ProcedureType type, {
    String? database,
  }) async {
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) return [];

    try {
      final results = await adapter.executeQuery('''
        SELECT
          PARAMETER_NAME,
          DATA_TYPE,
          PARAMETER_MODE
        FROM information_schema.PARAMETERS
        WHERE SPECIFIC_NAME = ${SqlEscapeUtils.escapeString(routineName)}
          AND SPECIFIC_SCHEMA = ${_schemaPredicateFor(database)}
          AND PARAMETER_NAME IS NOT NULL
        ORDER BY ORDINAL_POSITION
      ''');

      final params = <ProcedureParameter>[];
      for (final row in results.rows) {
        params.add(
          ProcedureParameter(
            name: _colAt(row, 0) ?? '',
            dataType: _colAt(row, 1) ?? 'VARCHAR',
            mode: (_colAt(row, 2) ?? 'IN').toUpperCase(),
          ),
        );
      }
      return params;
    } catch (e) {
      AppLogger.d('StoredProcedure', 'Error getting parameters: $e');
      return [];
    }
  }

  Future<String> getDefinition(String name, ProcedureType type) async {
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) return '';

    try {
      final results = await adapter.executeQuery('''
        SELECT ROUTINE_DEFINITION, ROUTINE_BODY 
        FROM information_schema.ROUTINES 
        WHERE ROUTINE_NAME = ${SqlEscapeUtils.escapeString(name)} 
          AND ROUTINE_TYPE = ${type == ProcedureType.procedure ? SqlEscapeUtils.escapeString('PROCEDURE') : SqlEscapeUtils.escapeString('FUNCTION')}
          AND ROUTINE_SCHEMA = DATABASE()
      ''');

      if (results.rows.isNotEmpty) {
        return _colAt(results.rows.first, 0) ?? '';
      }
      return '';
    } catch (e) {
      AppLogger.d('StoredProcedure', 'Error getting definition: $e');
      return '';
    }
  }

  Future<String> getCreateStatement(String name, ProcedureType type) async {
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) return '';

    try {
      final typeStr = type == ProcedureType.procedure
          ? 'PROCEDURE'
          : 'FUNCTION';
      final results = await adapter.executeQuery("SHOW CREATE $typeStr `$name`");

      if (results.rows.isNotEmpty) {
        return _colAt(results.rows.first, 2) ?? '';
      }
      return '';
    } catch (e) {
      AppLogger.d('StoredProcedure', 'Error getting create statement: $e');
      return '';
    }
  }

  Future<void> create(StoredProcedure procedure) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'procedure.create');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      final sql = _generateCreateSQL(procedure);
      await adapter.executeQuery(sql);
    } catch (e) {
      throw Exception('Failed to create ${procedure.type}: $e');
    }
  }

  Future<void> update(StoredProcedure procedure) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'procedure.update');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      // Drop and recreate
      await drop(procedure.name, procedure.type);
      await create(procedure);
    } catch (e) {
      throw Exception('Failed to update ${procedure.type}: $e');
    }
  }

  Future<void> drop(String name, ProcedureType type) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'procedure.drop');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      final typeStr = type == ProcedureType.procedure
          ? 'PROCEDURE'
          : 'FUNCTION';
      await adapter.executeQuery("DROP $typeStr IF EXISTS `$name`");
    } catch (e) {
      final typeStr = type == ProcedureType.procedure
          ? 'PROCEDURE'
          : 'FUNCTION';
      throw Exception('Failed to drop $typeStr: $e');
    }
  }

  Future<Map<String, dynamic>> execute(
    String name,
    ProcedureType type,
    Map<String, dynamic> params,
  ) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'procedure.execute');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    final typeName = type == ProcedureType.procedure ? 'PROCEDURE' : 'FUNCTION';

    try {
      // SQL injection prevention: escape parameter values
      String escapeValue(dynamic value) {
        if (value == null) return 'NULL';
        if (value is num) return value.toString();
        if (value is bool) return value ? '1' : '0';
        String str = value.toString();
        str = str.replaceAll('\\', '\\\\');
        str = str.replaceAll("'", "\\'");
        str = str.replaceAll('"', '\\"');
        str = str.replaceAll('\n', '\\n');
        str = str.replaceAll('\r', '\\r');
        str = str.replaceAll('\t', '\\t');
        return "'$str'";
      }

      if (type == ProcedureType.function) {
        // Function returns a value
        final paramStr = params.entries
            .map((e) => escapeValue(e.value))
            .join(', ');
        final results = await adapter.executeQuery(
          'SELECT `$name`($paramStr) as result',
        );
        if (results.rows.isNotEmpty) {
          return {
            'returnValue': _colAt(results.rows.first, 0),
            'rowsAffected': 0,
          };
        }
        return {'returnValue': null, 'rowsAffected': 0};
      } else {
        // Procedure
        // T29：网关每语句独立连接，会话级 `@var :=` 无法跨语句保持——带参
        // CALL 改为单语句字面量直传（与函数路径同一 escapeValue；旧行为只
        // 读 IN 参效果，OUT 参本就未回读）。
        final paramStr = params.entries
            .map((e) => escapeValue(e.value))
            .join(', ');
        final result = await adapter.executeQuery('CALL `$name`($paramStr)');
        return {
          'returnValue': null,
          'rowsAffected': result.affectedRows ?? 0,
        };
      }
    } catch (e) {
      throw Exception('Failed to execute $typeName: $e');
    }
  }

  String _generateCreateSQL(StoredProcedure procedure) {
    final buffer = StringBuffer();
    final typeStr = procedure.type == ProcedureType.procedure
        ? 'PROCEDURE'
        : 'FUNCTION';

    buffer.write('CREATE $typeStr `${procedure.name}`(');

    // Parameters
    final paramList = procedure.parameters
        .map((p) {
          if (procedure.type == ProcedureType.function) {
            return '${p.name} ${p.dataType}';
          } else {
            return '${p.mode} ${p.name} ${p.dataType}';
          }
        })
        .join(', ');
    buffer.write(paramList);
    buffer.write(')');

    // Return type for functions
    if (procedure.type == ProcedureType.function) {
      buffer.write(' RETURNS ${procedure.returnType ?? 'INT'}');
    }

    // Body
    buffer.writeln('\nBEGIN');
    if (procedure.body != null && procedure.body!.isNotEmpty) {
      buffer.writeln(procedure.body);
    } else {
      buffer.writeln('  -- Your SQL code here');
    }
    buffer.write('END');

    return buffer.toString();
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (e) {
      return null;
    }
  }
}
