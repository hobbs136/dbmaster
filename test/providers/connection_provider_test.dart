import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/database_service.dart';

class _MockDatabaseService extends DatabaseService {
  bool Function(String)? hasConnectionHandler;
  void Function(String)? setActiveConnectionHandler;
  Future<List<String>> Function({String? connectionId})? getDatabasesHandler;
  DbServer? currentServerValue;
  Future<void> Function({String? connectionId})? disconnectHandler;
  bool Function(String)? isConnectingHandler;

  @override
  bool hasConnection(String connectionId) =>
      hasConnectionHandler?.call(connectionId) ?? false;

  @override
  void setActiveConnection(String connectionId) =>
      setActiveConnectionHandler?.call(connectionId);

  @override
  Future<List<String>> getDatabases({String? connectionId}) async =>
      getDatabasesHandler?.call(connectionId: connectionId) ?? const [];

  @override
  DbServer? get currentServer => currentServerValue;

  @override
  Future<void> disconnect({String? connectionId}) async =>
      disconnectHandler?.call(connectionId: connectionId);

  @override
  bool isConnecting(String connectionId) =>
      isConnectingHandler?.call(connectionId) ?? false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DbServer _createServer({
  required String id,
  String name = 'test',
  String host = 'localhost',
  bool connected = false,
  DateTime? lastConnected,
}) => DbServer(
  id: id,
  name: name,
  type: DatabaseType.sqlite, // T29 第三批：CH 已 gateway-backed，占位切 sqlite
  host: host,
  port: 8123,
  username: 'root',
  password: null,
  connected: connected,
  lastConnected: lastConnected,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionProvider', () {
    late ConnectionProvider provider;
    late _MockDatabaseService mockDbService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockDbService = _MockDatabaseService();
      provider = ConnectionProvider(dbService: mockDbService);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              switch (call.method) {
                case 'read':
                case 'write':
                case 'delete':
                case 'deleteAll':
                  return null;
                case 'readAll':
                  return <String, String>{};
                default:
                  return null;
              }
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    });

    group('初始状态', () {
      test('应无初始连接', () {
        expect(provider.currentServer, isNull);
        expect(provider.isConnecting, isFalse);
        expect(provider.databases, isEmpty);
      });
    });

    group('连接管理', () {
      test('应获取数据库服务', () {
        expect(provider.dbService, isNotNull);
      });

      test('应获取已保存的连接', () {
        expect(provider.savedConnections, isEmpty);
      });
    });

    group('switchToConnection 连接活性验证', () {
      test('hasConnection 返回 false 时应直接返回 false', () async {
        mockDbService.hasConnectionHandler = (_) => false;

        final result = await provider.switchToConnection('conn1');

        expect(result, isFalse);
        expect(provider.currentServer, isNull);
        expect(provider.databases, isEmpty);
      });

      test('getDatabases 抛出异常时应返回 false 并清理状态', () async {
        mockDbService.hasConnectionHandler = (_) => true;
        mockDbService.setActiveConnectionHandler = (_) {};
        mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
            throw Exception('连接已断开');
        mockDbService.disconnectHandler = ({String? connectionId}) async {};

        // 预置一个虚假当前状态，验证被清理
        provider.setCurrentServer(_createServer(id: 'conn1'));
        provider.setCurrentDatabase(Database(name: 'db1'));

        final result = await provider.switchToConnection('conn1');

        expect(result, isFalse);
        expect(provider.currentServer, isNull);
        expect(provider.databases, isEmpty);
        expect(provider.currentDatabase, isNull);
      });

      test('getDatabases 返回空列表但服务器对象存在时应返回 true', () async {
        final server = _createServer(id: 'conn1');
        mockDbService.hasConnectionHandler = (_) => true;
        mockDbService.setActiveConnectionHandler = (_) {};
        mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
            const [];
        mockDbService.currentServerValue = server;

        final result = await provider.switchToConnection('conn1');

        expect(result, isTrue);
        expect(provider.currentServer, equals(server));
        expect(provider.databases, isEmpty);
      });
    });

    group('connectToServer 半开连接处理', () {
      test('对已连接但底层失效的实例应返回 false', () async {
        final server = _createServer(id: 'conn1');
        mockDbService.isConnectingHandler = (_) => false;
        mockDbService.hasConnectionHandler = (_) => true;
        mockDbService.setActiveConnectionHandler = (_) {};
        mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
            throw Exception('连接活性验证失败');
        mockDbService.disconnectHandler = ({String? connectionId}) async {};

        final result = await provider.connectToServer(server);

        expect(result, isFalse);
        expect(provider.currentServer, isNull);
        expect(provider.databases, isEmpty);
        expect(provider.currentDatabase, isNull);
      });
    });

    group('状态管理', () {
      test('setCurrentServer 应更新当前服务器并通知', () async {
        final server = _createServer(id: 'conn1');
        var notified = false;
        provider.addListener(() => notified = true);

        provider.setCurrentServer(server);

        expect(provider.currentServer, equals(server));
        expect(notified, isTrue);
      });

      test('setCurrentServer 相同 id 不应重复通知', () async {
        final server = _createServer(id: 'conn1');
        provider.setCurrentServer(server);

        var notifiedCount = 0;
        provider.addListener(() => notifiedCount++);
        provider.setCurrentServer(server);

        expect(notifiedCount, 0);
      });

      test('setCurrentDatabase 应更新当前数据库并通知', () async {
        final db = Database(name: 'db1');
        var notified = false;
        provider.addListener(() => notified = true);

        provider.setCurrentDatabase(db);

        expect(provider.currentDatabase, equals(db));
        expect(notified, isTrue);
      });

      test('setError / clearError 应更新错误信息', () async {
        provider.setError('connection lost');
        expect(provider.errorMessage, 'connection lost');

        provider.clearError();
        expect(provider.errorMessage, isNull);
      });

      test('setIsConnecting 应更新连接中状态', () {
        provider.setIsConnecting(true);
        expect(provider.isConnecting, isTrue);

        provider.setIsConnecting(false);
        expect(provider.isConnecting, isFalse);
      });
    });

    group('数据库列表过滤', () {
      test('getConnectionDatabases 默认只返回非空数据库', () {
        provider.setConnectionDatabasesForTest(
          'conn1',
          ['db1', 'db2', 'db3'],
          ['db2'],
        );
        expect(provider.getConnectionDatabases('conn1'), ['db2']);
      });

      test('toggleShowEmptyDatabases 为 true 时返回全部数据库', () {
        provider.setConnectionDatabasesForTest(
          'conn1',
          ['db1', 'db2', 'db3'],
          ['db2'],
        );
        provider.toggleShowEmptyDatabases('conn1');
        expect(provider.getConnectionDatabases('conn1'), ['db1', 'db2', 'db3']);
      });

      test('toggleShowEmptyDatabases 会切换状态并通知', () {
        provider.setConnectionDatabasesForTest(
          'conn1',
          ['db1', 'db2'],
          ['db2'],
        );
        var notified = false;
        provider.addListener(() => notified = true);

        provider.toggleShowEmptyDatabases('conn1');

        expect(provider.isShowingEmptyDatabases('conn1'), isTrue);
        expect(notified, isTrue);
      });

      test('无非空数据时返回全部数据库', () {
        provider.setConnectionDatabasesForTest('conn1', ['db1', 'db2'], []);
        expect(provider.getConnectionDatabases('conn1'), ['db1', 'db2']);
      });
    });

    group('缓存管理', () {
      test('invalidateDatabaseCache 应移除缓存并通知', () {
        final dbInfo = Database(name: 'db1');
        provider.setCachedDatabaseForTest('conn1', 'db1', dbInfo);
        expect(provider.getCachedDatabase('conn1', 'db1'), equals(dbInfo));

        var notified = false;
        provider.addListener(() => notified = true);
        provider.invalidateDatabaseCache('conn1', 'db1');

        expect(provider.getCachedDatabase('conn1', 'db1'), isNull);
        expect(notified, isTrue);
      });

      // Regression: same-name recreate should not show stale schema (hotfix pg-schema-cache-stale)
      test('invalidateDatabaseCache prevents stale schema on same-name recreate', () {
        // Simulate: create "test" DB, cache tables, drop it, recreate same name
        final oldDb = Database(
          name: 'test',
          tables: [DbTable(name: 'old_table')],
          views: const [],
          functions: const [],
        );
        provider.setCachedDatabaseForTest('conn1', 'test', oldDb);
        expect(provider.getCachedDatabase('conn1', 'test')?.tables.length, 1);

        // Simulate drop: invalidate cache BEFORE drop operation (the fix)
        provider.invalidateDatabaseCache('conn1', 'test');
        expect(provider.getCachedDatabase('conn1', 'test'), isNull,
            reason: 'Cache for dropped database must be null');

        // Simulate recreate: cache new empty DB with same name
        final newDb = Database(
          name: 'test',
          tables: const [],
          views: const [],
          functions: const [],
        );
        provider.setCachedDatabaseForTest('conn1', 'test', newDb);
        expect(provider.getCachedDatabase('conn1', 'test')?.tables.length, 0,
            reason: 'Recreated same-name DB must show empty tables, not stale old_table');
      });

      // Regression: cross-connection cache isolation (US3)
      test('invalidateDatabaseCache does not affect other connections', () {
        final dbA = Database(name: 'shared_name', tables: [DbTable(name: 'conn_a_table')]);
        final dbB = Database(name: 'shared_name', tables: [DbTable(name: 'conn_b_table')]);

        provider.setCachedDatabaseForTest('connA', 'shared_name', dbA);
        provider.setCachedDatabaseForTest('connB', 'shared_name', dbB);

        // Drop on connA only
        provider.invalidateDatabaseCache('connA', 'shared_name');

        expect(provider.getCachedDatabase('connA', 'shared_name'), isNull,
            reason: 'Dropped DB cache on connA must be cleared');
        expect(provider.getCachedDatabase('connB', 'shared_name')?.tables.first.name, 'conn_b_table',
            reason: 'Cache on connB must be untouched');
      });
    });

    group('importConnections 冲突策略', () {
      Future<void> seedExisting(String id, String name) async {
        await provider.saveConnection(
          _createServer(id: id, name: name, host: 'original-host'),
        );
      }

      DbServer serverToImport(String id, String name) => _createServer(
        id: id,
        name: name,
        host: 'imported-host',
        connected: true,
        lastConnected: DateTime(2026, 6, 21),
      );

      test('skip 策略保留现有连接并跳过导入', () async {
        await seedExisting('existing_1', 'MyConn');

        await provider.importConnections([
          serverToImport('imported_1', 'MyConn'),
        ], strategy: ConnectionImportConflictStrategy.skip);

        expect(provider.savedConnections.length, 1);
        expect(provider.savedConnections.first.id, 'existing_1');
        expect(provider.savedConnections.first.host, 'original-host');
      });

      test('rename 策略为导入连接生成唯一名称', () async {
        await seedExisting('existing_1', 'MyConn');

        await provider.importConnections([
          serverToImport('imported_1', 'MyConn'),
        ], strategy: ConnectionImportConflictStrategy.rename);

        expect(provider.savedConnections.length, 2);
        final imported = provider.savedConnections.firstWhere(
          (c) => c.name == 'MyConn-imported-1',
        );
        expect(imported.id, isNot('imported_1'));
        expect(imported.host, 'imported-host');
        expect(imported.connected, isFalse);
        expect(imported.lastConnected, isNull);
      });

      test('overwrite 策略替换现有连接但保留原 ID', () async {
        await seedExisting('existing_1', 'MyConn');

        await provider.importConnections([
          serverToImport('imported_1', 'MyConn'),
        ], strategy: ConnectionImportConflictStrategy.overwrite);

        expect(provider.savedConnections.length, 1);
        final connection = provider.savedConnections.first;
        expect(connection.id, 'existing_1');
        expect(connection.name, 'MyConn');
        expect(connection.host, 'imported-host');
        expect(connection.connected, isFalse);
        expect(connection.lastConnected, isNull);
      });

      test('导入连接默认 disconnected 且 lastConnected 为 null', () async {
        await provider.importConnections([
          serverToImport('imported_1', 'UniqueConn'),
        ], strategy: ConnectionImportConflictStrategy.skip);

        expect(provider.savedConnections.length, 1);
        final imported = provider.savedConnections.first;
        expect(imported.name, 'UniqueConn');
        expect(imported.host, 'imported-host');
        expect(imported.connected, isFalse);
        expect(imported.lastConnected, isNull);
      });

      test('导入失败时 loadSavedConnections 可回滚到持久化状态', () async {
        // 先保存一个连接并持久化
        await seedExisting('existing_1', 'OriginalConn');
        expect(provider.savedConnections.length, 1);
        expect(provider.savedConnections.first.host, 'original-host');

        // importConnections 的 rollback 机制：
        // 1. 循环中逐个 SecureStorageService.saveConnection + _savedConnections.add
        // 2. 最后调用 _persistConnections()
        // 如果第1步中途失败，_savedConnections 部分更新但 SharedPreferences 未变
        // catch 块调用 loadSavedConnections() 从 SharedPreferences 恢复
        //
        // 此处验证 loadSavedConnections 本身能正确恢复：
        // 先新建一个 provider 从 SharedPreferences 加载，确认状态一致
        final restoredProvider = ConnectionProvider();
        await restoredProvider.loadSavedConnections();
        expect(restoredProvider.savedConnections.length, 1);
        expect(restoredProvider.savedConnections.first.id, 'existing_1');
        expect(restoredProvider.savedConnections.first.name, 'OriginalConn');
        expect(restoredProvider.savedConnections.first.host, 'original-host');
      });
    });
  });
}
