import '../models/trigger.dart';
import 'database_abstract.dart';
import 'database_service.dart';
import 'readonly_guard.dart';
import '../utils/app_logger.dart';

class TriggerService {
  final DatabaseService _dbService;

  TriggerService(this._dbService);

  /// T29：MySQL 族已迁网关壳——经当前连接的 adapter 执行（原裸 MySQLConnection
  /// 通道下线）。行取值按列序位置（网关行是列名 map，保持插入序）。
  DatabaseAdapter? _getAdapter() => _dbService.currentAdapter;

  static String? _colAt(Map<String, dynamic> row, int i) {
    final values = row.values.toList();
    return i < values.length ? values[i]?.toString() : null;
  }

  /// 获取数据库中的所有触发器
  Future<List<DatabaseTrigger>> getTriggers() async {
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) return [];

    try {
      final results = await adapter.executeQuery('''
        SELECT 
          TRIGGER_NAME,
          ACTION_TIMING,
          EVENT_MANIPULATION,
          EVENT_OBJECT_TABLE,
          ACTION_STATEMENT,
          DEFINER,
          CREATED,
          LAST_ALTERED
        FROM information_schema.TRIGGERS 
        WHERE TRIGGER_SCHEMA = DATABASE()
        ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME
      ''');

      final triggers = <DatabaseTrigger>[];
      for (final row in results.rows) {
        triggers.add(
          DatabaseTrigger(
            name: _colAt(row, 0) ?? '',
            timing: TriggerTimingExtension.fromString(
              _colAt(row, 1) ?? 'AFTER',
            ),
            events: TriggerEventExtension.fromString(
              _colAt(row, 2) ?? 'INSERT',
            ),
            tableName: _colAt(row, 3) ?? '',
            definition: _colAt(row, 4) ?? '',
            definer: _colAt(row, 5),
            createdAt: _parseDateTime(_colAt(row, 6)),
            modifiedAt: _parseDateTime(_colAt(row, 7)),
            body: _colAt(row, 4),
            enabled: true,
          ),
        );
      }
      return triggers;
    } catch (e) {
      AppLogger.d('TriggerService', 'Error getting triggers: $e');
      return [];
    }
  }

  /// 获取触发器的完整 CREATE 语句
  Future<String> getCreateStatement(String name) async {
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) return '';

    try {
      final results = await adapter.executeQuery("SHOW CREATE TRIGGER `$name`");

      if (results.rows.isNotEmpty) {
        return _colAt(results.rows.first, 2) ?? '';
      }
      return '';
    } catch (e) {
      AppLogger.d('TriggerService', 'Error getting create statement: $e');
      return '';
    }
  }

  /// 创建触发器
  Future<void> create(DatabaseTrigger trigger) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'trigger.create');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      final sql = _generateCreateSQL(trigger);
      await adapter.executeQuery(sql);
    } catch (e) {
      throw Exception('Failed to create trigger: $e');
    }
  }

  /// 更新触发器（删除后重建）
  Future<void> update(String name, DatabaseTrigger newTrigger) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'trigger.update');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      // Drop existing trigger
      await drop(name);
      // Create new trigger
      await create(newTrigger);
    } catch (e) {
      throw Exception('Failed to update trigger: $e');
    }
  }

  /// 删除触发器
  Future<void> drop(String name) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'trigger.drop');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      await adapter.executeQuery("DROP TRIGGER IF EXISTS `$name`");
    } catch (e) {
      throw Exception('Failed to drop trigger: $e');
    }
  }

  /// 启用触发器（MySQL 触发器默认就是启用的，这是通过重建实现）
  Future<void> enable(String name) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'trigger.enable');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      // MySQL 触发器无法直接禁用，但可以通过重建来确保它们处于启用状态
      final createStmt = await getCreateStatement(name);
      if (createStmt.isEmpty) {
        throw Exception('Trigger not found');
      }
      await drop(name);
      await adapter.executeQuery(createStmt);
    } catch (e) {
      throw Exception('Failed to enable trigger: $e');
    }
  }

  /// 禁用触发器（MySQL 不支持直接禁用，需要删除）
  /// 返回删除前的 CREATE 语句，以便之后重新启用
  Future<String> disable(String name) async {
    ensureServerNotReadOnly(_dbService.currentServer, operation: 'trigger.disable');
    final adapter = _getAdapter();
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      final createStmt = await getCreateStatement(name);
      await drop(name);
      return createStmt;
    } catch (e) {
      throw Exception('Failed to disable trigger: $e');
    }
  }

  /// 获取所有可用的表（排除视图）
  Future<List<String>> getTables() async {
    try {
      return await _dbService.getTables();
    } catch (e) {
      AppLogger.d('TriggerService', 'Error getting tables: $e');
      return [];
    }
  }

  /// 生成 CREATE TRIGGER SQL 语句
  String _generateCreateSQL(DatabaseTrigger trigger) {
    final buffer = StringBuffer();

    buffer.writeln('CREATE TRIGGER `${trigger.name}`');
    buffer.write('${trigger.timing.value} ${trigger.eventString}');
    buffer.writeln(' ON `${trigger.tableName}`');
    buffer.writeln('FOR EACH ROW');
    buffer.writeln('BEGIN');
    if (trigger.body != null && trigger.body!.isNotEmpty) {
      // 确保语句以分号结尾
      final body = trigger.body!.trim();
      if (body.endsWith(';')) {
        buffer.writeln('  $body');
      } else {
        buffer.writeln('  $body;');
      }
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

  /// 验证触发器名称是否合法
  bool isValidName(String name) {
    if (name.isEmpty || name.length > 64) return false;
    // MySQL 标识符规则：字母、数字、下划线、美元符号，不能以数字开头
    final regex = RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]*$');
    return regex.hasMatch(name);
  }

  /// 验证触发器体语法（基本验证）
  String? validateBody(String body) {
    if (body.trim().isEmpty) {
      return 'Trigger body cannot be empty';
    }

    // 检查是否包含基本的 SQL 语句
    final normalized = body.toLowerCase().trim();
    final hasSql =
        normalized.contains('insert ') ||
        normalized.contains('update ') ||
        normalized.contains('delete ') ||
        normalized.contains('set ') ||
        normalized.contains('select ');

    if (!hasSql) {
      return 'Trigger body should contain at least one SQL statement';
    }

    return null;
  }
}
