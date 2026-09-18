import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/database_service.dart';

class _MockDatabaseService extends DatabaseService {
  bool Function(String)? hasConnectionHandler;
  bool Function(String)? isConnectionActiveHandler;
  bool Function(String)? isConnectingHandler;
  Future<bool> Function(DbServer)? connectHandler;
  Future<void> Function({String? connectionId})? disconnectHandler;
  Future<List<String>> Function({String? connectionId})? getDatabasesHandler;
  void Function(String)? setActiveConnectionHandler;
  DbServer? currentServerValue;
  List<String> connectedIdsValue = const [];
  Future<List<Map<String, dynamic>>> Function(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  })? executeQueryHandler;

  @override
  bool hasConnection(String connectionId) =>
      hasConnectionHandler?.call(connectionId) ?? false;

  @override
  bool isConnectionActive(String connectionId) =>
      isConnectionActiveHandler?.call(connectionId) ?? false;

  @override
  bool isConnecting(String connectionId) =>
      isConnectingHandler?.call(connectionId) ?? false;

  @override
  Future<bool> connect(DbServer server) async =>
      connectHandler?.call(server) ?? false;

  @override
  Future<void> disconnect({String? connectionId}) async =>
      disconnectHandler?.call(connectionId: connectionId);

  @override
  Future<List<String>> getDatabases({String? connectionId}) async =>
      getDatabasesHandler?.call(connectionId: connectionId) ?? const [];

  @override
  void setActiveConnection(String connectionId) =>
      setActiveConnectionHandler?.call(connectionId);

  @override
  DbServer? get currentServer => currentServerValue;

  @override
  List<String> get connectedIds => connectedIdsValue;

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    if (executeQueryHandler != null) {
      return executeQueryHandler!(
        sql,
        connectionId: connectionId,
        database: database,
        sessionId: sessionId,
      );
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DbServer _createSqlServer({
  required String id,
  String name = 'SQL Server Test',
  String host = '192.0.2.128',
  bool connected = false,
}) => DbServer(
  id: id,
  name: name,
  type: DatabaseType.sqlserver,
  host: host,
  port: 1433,
  username: 'sa',
  password: 'test-password',
  database: 'dbmaster_handoff_setup',
  connected: connected,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SQL Server ConnectionProvider', () {
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

    test('TC-SS-CON-001: new SQL Server connection succeeds and loads databases', () async {
      final server = _createSqlServer(id: 'ss_conn_001');
      mockDbService.isConnectingHandler = (_) => false;
      mockDbService.hasConnectionHandler = (_) => false;
      mockDbService.connectHandler = (s) async {
        mockDbService.currentServerValue = s;
        return true;
      };
      mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
          const ['dbmaster_handoff_setup', 'master', 'tempdb'];
      mockDbService.isConnectionActiveHandler = (_) => true;

      final result = await provider.connectToServer(server);

      expect(result, isTrue);
      expect(provider.currentServer, equals(server));
      expect(provider.databases, contains('dbmaster_handoff_setup'));
      expect(provider.isConnecting, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('TC-SS-CON-002: connection loss is detected gracefully and state is cleared', () async {
      final server = _createSqlServer(id: 'ss_conn_002');
      final connectedIds = <String>{};
      mockDbService.isConnectingHandler = (_) => false;
      mockDbService.hasConnectionHandler = connectedIds.contains;
      mockDbService.connectHandler = (s) async {
        connectedIds.add(s.id);
        mockDbService.currentServerValue = s;
        mockDbService.connectedIdsValue = connectedIds.toList();
        return true;
      };
      mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
          const ['dbmaster_handoff_setup'];
      mockDbService.disconnectHandler = ({String? connectionId}) async {
        connectedIds.remove(connectionId);
        mockDbService.connectedIdsValue = connectedIds.toList();
      };

      await provider.connectToServer(server);
      expect(provider.currentServer, isNotNull);

      // Simulate connection loss: getDatabases now throws.
      mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
          throw Exception('Connection reset by peer');
      mockDbService.isConnectionActiveHandler = (_) => false;

      final switched = await provider.switchToConnection('ss_conn_002');

      expect(switched, isFalse);
      expect(provider.currentServer, isNull);
      expect(provider.databases, isEmpty);
      expect(provider.currentDatabase, isNull);
    });

    test('TC-SS-CON-003: disconnect and reconnect works for SQL Server', () async {
      final server = _createSqlServer(id: 'ss_conn_003');
      final connectedIds = <String>{};

      mockDbService.isConnectingHandler = (_) => false;
      mockDbService.hasConnectionHandler = connectedIds.contains;
      mockDbService.connectHandler = (s) async {
        connectedIds.add(s.id);
        mockDbService.currentServerValue = s;
        mockDbService.connectedIdsValue = connectedIds.toList();
        return true;
      };
      mockDbService.disconnectHandler = ({String? connectionId}) async {
        connectedIds.remove(connectionId);
        mockDbService.currentServerValue = connectedIds.isEmpty ? null : server;
        mockDbService.connectedIdsValue = connectedIds.toList();
      };
      mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
          const ['dbmaster_handoff_setup'];

      // First connect
      expect(await provider.connectToServer(server), isTrue);
      expect(provider.isConnectionConnected('ss_conn_003'), isTrue);

      // Disconnect
      await provider.disconnectConnection(connectionId: 'ss_conn_003');
      expect(provider.isConnectionConnected('ss_conn_003'), isFalse);
      expect(provider.currentServer, isNull);
      expect(provider.databases, isEmpty);

      // Reconnect
      expect(await provider.connectToServer(server), isTrue);
      expect(provider.isConnectionConnected('ss_conn_003'), isTrue);
      expect(provider.currentServer, equals(server));
      expect(provider.databases, contains('dbmaster_handoff_setup'));
    });

    test('TC-SS-EXE-002: connection remains usable after a failed EXEC', () async {
      final server = _createSqlServer(id: 'ss_conn_exe_002');
      final connectedIds = <String>{};
      var queryCallCount = 0;

      mockDbService.isConnectingHandler = (_) => false;
      mockDbService.hasConnectionHandler = connectedIds.contains;
      mockDbService.isConnectionActiveHandler = (_) => true;
      mockDbService.connectHandler = (s) async {
        connectedIds.add(s.id);
        mockDbService.currentServerValue = s;
        mockDbService.connectedIdsValue = connectedIds.toList();
        return true;
      };
      mockDbService.getDatabasesHandler = ({String? connectionId}) async =>
          const ['dbmaster_handoff_setup'];
      mockDbService.executeQueryHandler = (sql, {connectionId, database, sessionId}) async {
        queryCallCount++;
        if (sql.toLowerCase().contains('p_needparam')) {
          throw Exception(
            "Procedure or function 'p_needparam' expects parameter '@x', which was not supplied.",
          );
        }
        return const [
          <String, dynamic>{'result': 'ok'},
        ];
      };

      await provider.connectToServer(server);
      expect(provider.isConnectionConnected('ss_conn_exe_002'), isTrue);

      // Failed EXEC
      await expectLater(
        provider.dbService.executeQuery('EXEC p_needparam;'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains("p_needparam"),
          ),
        ),
      );

      // Connection must remain usable
      expect(provider.isConnectionConnected('ss_conn_exe_002'), isTrue);
      expect(provider.isConnectionActive('ss_conn_exe_002'), isTrue);
      expect(provider.currentServer, isNotNull);

      // Subsequent query succeeds
      final result = await provider.dbService.executeQuery('SELECT 1 AS result;');
      expect(result.first['result'], equals('ok'));
      expect(queryCallCount, equals(2));
    });
  });
}
