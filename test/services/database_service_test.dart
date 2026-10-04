import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';

/// 库限定表枚举 fake（FU-18）：实现 [DatabaseQualifiedTablesAdapter]，
/// 记录每次收到的库（含 null —— 原路径零参调用）。
class _QualifiedTablesAdapter
    implements DatabaseAdapter, DatabaseQualifiedTablesAdapter {
  final List<String?> receivedDatabases = <String?>[];

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getTables({String? database}) async {
    receivedDatabases.add(database);
    return <String>['qualified_t'];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 未实现能力接口的 fake（PG/SS/SQLite 族代表）：只提供基类零参 getTables。
class _PlainTablesAdapter implements DatabaseAdapter {
  int getTablesCalls = 0;

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getTables() async {
    getTablesCalls++;
    return <String>['plain_t'];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DbServer _server(String id) => DbServer(
  id: id,
  name: id,
  type: DatabaseType.mysql,
  host: '127.0.0.1',
  port: 3306,
  username: null,
  password: null,
  database: null,
  useSSL: false,
  timeoutSeconds: 30,
  autoReconnect: false,
);

void main() {
  group('DatabaseService', () {
    late DatabaseService service;

    setUp(() {
      service = DatabaseService();
    });

    group('初始状态', () {
      test('isConnected 应为 false', () {
        expect(service.isConnected, isFalse);
      });

      test('activeConnectionId 应为 null', () {
        expect(service.activeConnectionId, isNull);
      });

      test('currentServer 应为 null', () {
        expect(service.currentServer, isNull);
      });

      test('connectedIds 应为空列表', () {
        expect(service.connectedIds, isEmpty);
      });

      test('connectionCount 应为 0', () {
        expect(service.connectionCount, 0);
      });

      test('currentAdapter 应为 null', () {
        expect(service.currentAdapter, isNull);
      });
    });

    group('连接状态查询 - 无连接时', () {
      test('isConnecting 应返回 false', () {
        expect(service.isConnecting('any_id'), isFalse);
      });

      test('isConnectionActive 应返回 false', () {
        expect(service.isConnectionActive('any_id'), isFalse);
      });

      test('hasConnection 应返回 false', () {
        expect(service.hasConnection('any_id'), isFalse);
      });

      test('getAdapter 应返回 null', () {
        expect(service.getAdapter('any_id'), isNull);
      });
    });

    group('事务状态 - 无连接时', () {
      test('isInTransaction 应返回 false', () {
        expect(service.isInTransaction('any_id'), isFalse);
      });

      test('isInTransaction(null) 应返回 false', () {
        expect(service.isInTransaction(null), isFalse);
      });

      test('isSessionInTransaction 应返回 false', () {
        expect(service.isSessionInTransaction('any_session'), isFalse);
      });
    });

    group('事务事件 Stream', () {
      test('transactionEvents 应为 broadcast stream', () {
        expect(service.transactionEvents.isBroadcast, isTrue);
      });

      test('transactionEvents 可监听', () async {
        final sub = service.transactionEvents.listen((_) {});
        expect(sub, isNotNull);
        await sub.cancel();
      });

      test('sessionTransactionEvents 应为 broadcast stream', () {
        expect(service.sessionTransactionEvents.isBroadcast, isTrue);
      });

      test('sessionTransactionEvents 可监听', () async {
        final sub = service.sessionTransactionEvents.listen((_) {});
        expect(sub, isNotNull);
        await sub.cancel();
      });
    });

    group('连接事件 Stream', () {
      test('events 应为 broadcast stream', () {
        expect(service.events.isBroadcast, isTrue);
      });

      test('events 可监听', () async {
        final sub = service.events.listen((_) {});
        expect(sub, isNotNull);
        await sub.cancel();
      });
    });

    group('setActiveConnection', () {
      test('设置不存在的连接不应崩溃，且不改变 activeConnectionId', () {
        expect(
          () => service.setActiveConnection('nonexistent'),
          returnsNormally,
        );
        expect(service.activeConnectionId, isNull);
      });
    });

    group('isQueryCancelled', () {
      test('未追踪的查询应返回 false', () {
        expect(service.isQueryCancelled('nonexistent'), isFalse);
      });
    });

    // FU-18：list_tables 库路由对齐 run 快照——databaseName 只对
    // DatabaseQualifiedTablesAdapter 实现者生效，其余路径零行为变化。
    group('getTables databaseName 分支（FU-18）', () {
      late _QualifiedTablesAdapter qualified;
      late _PlainTablesAdapter plain;

      setUp(() {
        qualified = _QualifiedTablesAdapter();
        plain = _PlainTablesAdapter();
        service.registerConnectedServerForTest(_server('conn-q'));
        service.registerConnectedServerForTest(_server('conn-p'));
        service.registerConnectedAdapterForTest('conn-q', qualified);
        service.registerConnectedAdapterForTest('conn-p', plain);
      });

      test(
        '实现 DatabaseQualifiedTablesAdapter + databaseName 非空 → 带库调用被记录',
        () async {
          final tables = await service.getTables(
            connectionId: 'conn-q',
            databaseName: 'testdb',
          );

          expect(tables, <String>['qualified_t']);
          expect(qualified.receivedDatabases, <String?>['testdb']);
        },
      );

      test('databaseName null / 空串 → 不带库原路径（零参调用，不传空串）', () async {
        await service.getTables(connectionId: 'conn-q');
        await service.getTables(connectionId: 'conn-q', databaseName: '');

        expect(qualified.receivedDatabases, <String?>[null, null]);
      });

      test(
        '未实现该接口的 adapter + databaseName 非空 → 走原 adapter.getTables() 路径（零回归）',
        () async {
          final tables = await service.getTables(
            connectionId: 'conn-p',
            databaseName: 'testdb',
          );

          expect(tables, <String>['plain_t']);
          expect(plain.getTablesCalls, 1);
        },
      );
    });
  });
}
