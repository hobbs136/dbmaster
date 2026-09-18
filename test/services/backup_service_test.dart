import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/backup_service.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/models/backup_models.dart';
import 'package:dbmaster/models/database_models.dart';

// ============================================================================
// BackupService Tests
// ============================================================================

class _MockDbService extends DatabaseService {
  bool _connected = true;
  DbServer? _currentServer;
  List<String> _tables = const ['users', 'orders'];
  List<Map<String, dynamic>> Function(String sql)? _executeQueryHandler;
  Future<String> Function(String tableName)? _getCreateTableSqlHandler;
  Future<List<DbColumn>> Function(String tableName)? _getTableColumnsHandler;
  Future<List<DbIndex>> Function(String tableName)? _getTableIndexesHandler;

  void setMockData({
    bool connected = true,
    DbServer? currentServer,
    List<String>? tables,
    List<Map<String, dynamic>> Function(String sql)? executeQueryHandler,
    Future<String> Function(String tableName)? getCreateTableSqlHandler,
    Future<List<DbColumn>> Function(String tableName)? getTableColumnsHandler,
    Future<List<DbIndex>> Function(String tableName)? getTableIndexesHandler,
  }) {
    _connected = connected;
    _currentServer = currentServer;
    if (tables != null) _tables = tables;
    if (executeQueryHandler != null) _executeQueryHandler = executeQueryHandler;
    if (getCreateTableSqlHandler != null)
      _getCreateTableSqlHandler = getCreateTableSqlHandler;
    if (getTableColumnsHandler != null)
      _getTableColumnsHandler = getTableColumnsHandler;
    if (getTableIndexesHandler != null)
      _getTableIndexesHandler = getTableIndexesHandler;
  }

  @override
  bool get isConnected => _connected;

  @override
  DbServer? get currentServer => _currentServer;

  @override
  Future<List<String>> getTables({String? connectionId}) async => _tables;

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    final handler = _executeQueryHandler;
    if (handler != null) return handler(sql);
    return const [];
  }

  @override
  Future<String> getCreateTableSql(
    String tableName, {
    String? connectionId,
    String? databaseName,
  }) async {
    final handler = _getCreateTableSqlHandler;
    if (handler != null) return handler(tableName);
    return '';
  }

  @override
  Future<List<DbColumn>> getTableColumns(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    final handler = _getTableColumnsHandler;
    if (handler != null) return handler(tableName);
    return const [];
  }

  @override
  Future<List<DbIndex>> getTableIndexes(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    final handler = _getTableIndexesHandler;
    if (handler != null) return handler(tableName);
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDbService dbService;
  late BackupService backupService;
  late Directory tempDir;

  void mockPathProvider() {
    const channels = [
      MethodChannel('plugins.flutter.io/path_provider'),
      MethodChannel('plugins.flutter.io/path_provider_foundation'),
      MethodChannel('plugins.flutter.io/path_provider_linux'),
      MethodChannel('plugins.flutter.io/path_provider_windows'),
    ];
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          });
    }
  }

  setUp(() {
    dbService = _MockDbService();
    backupService = BackupService(dbService);
    tempDir = Directory.systemTemp.createTempSync('backup_test_');
    mockPathProvider();
  });

  tearDown(() async {
    backupService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BackupService', () {
    test('dispose 不应抛异常', () {
      expect(() => backupService.dispose(), returnsNormally);
    });

    test('未连接时 createBackup 应抛出异常', () async {
      dbService.setMockData(connected: false);

      expect(
        () => backupService.createBackup(BackupOptions(format: 'sql')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('未连接到数据库'),
          ),
        ),
      );
    });

    test('未选择数据库时 createBackup 应使用 unknown 作为数据库名', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: null,
        ),
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'sql', tables: const ['users']),
      );

      expect(backup.name, contains('unknown'));
    });

    test('getBackupList 应返回空列表当无备份时', () async {
      final list = await backupService.getBackupList();
      expect(list, isEmpty);
    });

    test('deleteBackup 不存在的备份应抛出异常', () async {
      expect(
        () => backupService.deleteBackup('non-existent-id'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('备份文件不存在'),
          ),
        ),
      );
    });

    test('importBackup 不支持的格式应抛出异常', () async {
      final file = File('${tempDir.path}/backup.txt');
      await file.writeAsString('test');

      expect(
        () => backupService.importBackup(file.path),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('不支持的文件格式'),
          ),
        ),
      );
    });

    test('importBackup 文件不存在应抛出异常', () async {
      expect(
        () => backupService.importBackup('${tempDir.path}/non_existent.sql'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('文件不存在'),
          ),
        ),
      );
    });

    test('importBackup 有效的 SQL 文件应成功', () async {
      final file = File('${tempDir.path}/test_backup.sql');
      await file.writeAsString('CREATE TABLE users (id INT);');

      final backup = await backupService.importBackup(file.path);

      expect(backup.name, contains('test_backup.sql'));
      expect(backup.type, equals('sql'));
      expect(backup.size, greaterThan(0));
    });

    test('importBackup 有效的 JSON 文件应成功', () async {
      final file = File('${tempDir.path}/test_backup.json');
      await file.writeAsString('{"tables": {"users": []}}');

      final backup = await backupService.importBackup(file.path);

      expect(backup.type, equals('json'));
    });

    test('clearAllBackups 不应抛异常', () async {
      await expectLater(backupService.clearAllBackups(), completes);
    });

    test('getBackupFilePath 不存在的备份应抛出异常', () async {
      expect(
        () => backupService.getBackupFilePath('non-existent'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('备份文件不存在'),
          ),
        ),
      );
    });

    test('progressStream 应可监听', () async {
      final subscription = backupService.progressStream.listen((progress) {
        // No-op
      });
      expect(subscription, isNotNull);
      await subscription.cancel();
    });

    test('createBackup SQL 格式应成功并写入文件', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getCreateTableSqlHandler: (table) async =>
            'CREATE TABLE `$table` (id INT)',
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'sql', tables: const ['users']),
      );

      expect(backup.type, 'sql');
      expect(backup.database, 'test_db');
      expect(backup.tables, ['users']);
      expect(backup.size, greaterThan(0));

      final filePath = await backupService.getBackupFilePath(backup.id);
      expect(filePath, isNotNull);
      final content = await File(filePath!).readAsString();
      expect(content, contains('CREATE TABLE `users`'));
      expect(content, contains('DBMaster Database Backup'));
    });

    test('createBackup JSON 格式应包含结构和数据', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getTableColumnsHandler: (table) async => [
          DbColumn(
            name: 'id',
            type: 'INT',
            isPrimaryKey: true,
            isNullable: false,
          ),
        ],
        getTableIndexesHandler: (table) async => [
          DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
        ],
        executeQueryHandler: (sql) => [
          {'id': 1, 'name': 'Alice'},
        ],
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'json', tables: const ['users']),
      );

      final filePath = await backupService.getBackupFilePath(backup.id);
      final content = await File(filePath!).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      expect(data['metadata']['database'], 'test_db');
      expect(data['tables']['users']['structure']['columns'], isNotEmpty);
      expect(data['tables']['users']['data'], isNotEmpty);
    });

    test('createBackup CSV 格式应包含表头和数据', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getTableColumnsHandler: (table) async => [
          DbColumn(name: 'id', type: 'INT'),
          DbColumn(name: 'name', type: 'VARCHAR'),
        ],
        executeQueryHandler: (sql) => [
          {'id': 1, 'name': 'Alice'},
        ],
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'csv', tables: const ['users']),
      );

      final filePath = await backupService.getBackupFilePath(backup.id);
      final content = await File(filePath!).readAsString();

      expect(content, contains('## TABLE: users'));
      expect(content, contains('"id","name"'));
      expect(content, contains('"1","Alice"'));
    });

    test('createBackup 不支持的格式应抛出异常', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
      );

      expect(
        () => backupService.createBackup(BackupOptions(format: 'xml')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('不支持的备份格式'),
          ),
        ),
      );
    });

    test('createBackup 没有表时应抛出异常', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        tables: [],
      );

      expect(
        () => backupService.createBackup(BackupOptions(format: 'sql')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('没有要备份的表'),
          ),
        ),
      );
    });

    test('createBackup 指定表时只备份指定表', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getCreateTableSqlHandler: (table) async =>
            'CREATE TABLE `$table` (id INT)',
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'sql', tables: const ['orders']),
      );

      expect(backup.tables, ['orders']);
      final filePath = await backupService.getBackupFilePath(backup.id);
      final content = await File(filePath!).readAsString();
      expect(content, contains('CREATE TABLE `orders`'));
      expect(content, isNot(contains('CREATE TABLE `users`')));
    });

    test('createBackup 应发送进度流事件', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getCreateTableSqlHandler: (table) async =>
            'CREATE TABLE `$table` (id INT)',
      );

      final progressEvents = <BackupProgress>[];
      final subscription = backupService.progressStream.listen(
        progressEvents.add,
      );

      await backupService.createBackup(
        BackupOptions(format: 'sql', tables: const ['users']),
      );

      await subscription.cancel();

      expect(progressEvents, isNotEmpty);
      expect(progressEvents.first.status, 'running');
      expect(progressEvents.last.status, 'completed');
      expect(progressEvents.last.progress, 1.0);
    });

    test('createBackup 失败时应发送 error 进度事件并重新抛出', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        tables: [],
      );

      final progressEvents = <BackupProgress>[];
      backupService.progressStream.listen(progressEvents.add);

      await expectLater(
        () => backupService.createBackup(BackupOptions(format: 'sql')),
        throwsA(isA<Exception>()),
      );

      // Stream 事件可能异步调度，等待 microtask 完成
      await Future.delayed(Duration.zero);

      expect(progressEvents.any((p) => p.status == 'error'), isTrue);
    });

    test('备份元数据应在 getBackupList 时持久化加载', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getCreateTableSqlHandler: (table) async =>
            'CREATE TABLE `$table` (id INT)',
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'sql', tables: const ['users']),
      );

      // 新实例模拟应用重启后加载元数据
      final newService = BackupService(dbService);
      final list = await newService.getBackupList();

      expect(list.any((b) => b.id == backup.id), isTrue);
      newService.dispose();
    });

    test('deleteBackup 成功应删除文件和元数据', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getCreateTableSqlHandler: (table) async =>
            'CREATE TABLE `$table` (id INT)',
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'sql', tables: const ['users']),
      );
      final filePath = await backupService.getBackupFilePath(backup.id);
      expect(filePath, isNotNull);
      expect(await File(filePath!).exists(), isTrue);

      await backupService.deleteBackup(backup.id);

      expect(await File(filePath).exists(), isFalse);
      expect(
        () => backupService.getBackupFilePath(backup.id),
        throwsA(isA<Exception>()),
      );
    });

    test('getBackupPreview 应返回文件内容', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getCreateTableSqlHandler: (table) async =>
            'CREATE TABLE `$table` (id INT)',
      );

      final backup = await backupService.createBackup(
        BackupOptions(format: 'sql', tables: const ['users']),
      );

      final preview = await backupService.getBackupPreview(backup.id);

      expect(preview, contains('CREATE TABLE `users`'));
    });

    test('restoreBackup SQL 应执行 SQL 语句', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        getCreateTableSqlHandler: (table) async =>
            'CREATE TABLE `$table` (id INT)',
      );

      final backup = await backupService.createBackup(
        BackupOptions(
          format: 'sql',
          tables: const ['users'],
          includeData: false,
        ),
      );

      final executedSql = <String>[];
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
        executeQueryHandler: (sql) {
          executedSql.add(sql);
          return [];
        },
      );

      await backupService.restoreBackup(backup.id);

      expect(executedSql, anyElement(contains('CREATE TABLE `users`')));
    });

    test('restoreBackup 不存在的备份应抛出异常', () async {
      dbService.setMockData(
        connected: true,
        currentServer: DbServer(
          id: 's1',
          name: 'Test',
          host: 'localhost',
          port: 3306,
          type: DatabaseType.mysql,
          database: 'test_db',
        ),
      );

      expect(
        () => backupService.restoreBackup('non-existent'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('备份文件不存在'),
          ),
        ),
      );
    });
  });
}
