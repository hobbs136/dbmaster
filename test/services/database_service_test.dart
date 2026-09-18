import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/database_service.dart';

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
  });
}
