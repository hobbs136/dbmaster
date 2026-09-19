import 'package:dbmaster/models/connection_failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// T1 契约测试：ConnectionFailure 模型 + 双映射纯函数。
///
/// 契约以 docs/tasks/task_error_ux.md 契约快照为准（冻结）。
void main() {
  group('sqliteKindFromResultCode（设计锁定映射）', () {
    test('5 (SQLITE_BUSY) → fileLocked', () {
      expect(sqliteKindFromResultCode(5), ConnectionFailureKind.fileLocked);
    });

    test('6 (SQLITE_LOCKED) → fileLocked', () {
      expect(sqliteKindFromResultCode(6), ConnectionFailureKind.fileLocked);
    });

    test('14 (SQLITE_CANTOPEN) → fileNotFound', () {
      expect(sqliteKindFromResultCode(14), ConnectionFailureKind.fileNotFound);
    });

    test('3 (SQLITE_PERM) → permissionDenied', () {
      expect(
        sqliteKindFromResultCode(3),
        ConnectionFailureKind.permissionDenied,
      );
    });

    test('8 (SQLITE_READONLY) → permissionDenied', () {
      expect(
        sqliteKindFromResultCode(8),
        ConnectionFailureKind.permissionDenied,
      );
    });

    test('26 (SQLITE_NOTADB) → notADatabase', () {
      expect(sqliteKindFromResultCode(26), ConnectionFailureKind.notADatabase);
    });

    test('11 (SQLITE_CORRUPT) → corrupt', () {
      expect(sqliteKindFromResultCode(11), ConnectionFailureKind.corrupt);
    });

    test('null → unknown', () {
      expect(sqliteKindFromResultCode(null), ConnectionFailureKind.unknown);
    });

    test('未列码 7 → unknown', () {
      expect(sqliteKindFromResultCode(7), ConnectionFailureKind.unknown);
    });
  });

  group('gatewayEnvelopeFailure（envelope → ConnectionFailure）', () {
    test('有 code 无 engineCode：errorCode=code，rawMessage 原样不追加后缀', () {
      final failure = gatewayEnvelopeFailure(
        code: 'AUTH_FAILED',
        message: 'server rejected credentials',
        target: '192.168.3.128:5432',
      );
      expect(failure.kind, ConnectionFailureKind.unknown);
      expect(failure.errorCode, 'AUTH_FAILED');
      expect(failure.rawMessage, 'server rejected credentials');
      expect(failure.target, '192.168.3.128:5432');
    });

    test('无 code 有 engineCode：errorCode=engineCode，rawMessage 追加后缀', () {
      final failure = gatewayEnvelopeFailure(
        code: null,
        engineCode: '1045',
        message: 'Access denied for user',
      );
      expect(failure.kind, ConnectionFailureKind.unknown);
      expect(failure.errorCode, '1045');
      expect(failure.rawMessage, 'Access denied for user (engine code: 1045)');
    });

    test('双无：errorCode 为空串 且 kind 为 unknown', () {
      final failure = gatewayEnvelopeFailure(
        code: null,
        engineCode: null,
        message: 'connection refused',
      );
      expect(failure.errorCode, '');
      expect(failure.kind, ConnectionFailureKind.unknown);
      expect(failure.rawMessage, 'connection refused');
    });

    test('code 与 engineCode 并存：errorCode 取 code，rawMessage 仍追加后缀', () {
      final failure = gatewayEnvelopeFailure(
        code: 'GW_TIMEOUT',
        engineCode: '1105',
        message: 'engine aborted',
      );
      expect(failure.errorCode, 'GW_TIMEOUT');
      expect(failure.rawMessage, 'engine aborted (engine code: 1105)');
    });

    test('occurredAt 缺省取当前时间', () {
      final before = DateTime.now();
      final failure = gatewayEnvelopeFailure(code: 'E1', message: 'm');
      final after = DateTime.now();
      expect(
        failure.occurredAt.isBefore(after) || failure.occurredAt == after,
        isTrue,
      );
      expect(
        failure.occurredAt.isAfter(before) || failure.occurredAt == before,
        isTrue,
      );
    });

    test('occurredAt 显式传入时原样保留', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final failure = gatewayEnvelopeFailure(
        code: 'E2',
        message: 'm',
        occurredAt: at,
      );
      expect(failure.occurredAt, at);
    });
  });

  group('gatewayEnvelopeFailure code→kind（T12c 稳定码映射）', () {
    test('AUTH_DENIED → authFailed，errorCode 保留稳定码', () {
      final failure = gatewayEnvelopeFailure(
        code: 'AUTH_DENIED',
        message: 'Access denied for user',
        target: '192.168.3.128:3306',
      );
      expect(failure.kind, ConnectionFailureKind.authFailed);
      expect(failure.errorCode, 'AUTH_DENIED');
      expect(failure.rawMessage, 'Access denied for user');
      expect(failure.target, '192.168.3.128:3306');
    });

    test('UNREACHABLE → unreachable', () {
      final failure = gatewayEnvelopeFailure(
        code: 'UNREACHABLE',
        message: 'connection refused',
      );
      expect(failure.kind, ConnectionFailureKind.unreachable);
      expect(failure.errorCode, 'UNREACHABLE');
    });

    test('TIMEOUT → unknown（不唯一指"端口没开"，文案由展示层兜底）', () {
      final failure = gatewayEnvelopeFailure(
        code: 'TIMEOUT',
        message: 'pool timed out',
      );
      expect(failure.kind, ConnectionFailureKind.unknown);
      expect(failure.errorCode, 'TIMEOUT');
    });

    test('DB_ERROR → unknown', () {
      final failure = gatewayEnvelopeFailure(
        code: 'DB_ERROR',
        message: 'engine error',
      );
      expect(failure.kind, ConnectionFailureKind.unknown);
      expect(failure.errorCode, 'DB_ERROR');
    });

    test('未列稳定码 → unknown', () {
      final failure = gatewayEnvelopeFailure(code: 'SOMETHING_NEW', message: 'm');
      expect(failure.kind, ConnectionFailureKind.unknown);
    });

    test('code 为 null（仅 engineCode）→ unknown（映射只看稳定码 code）', () {
      final failure = gatewayEnvelopeFailure(
        code: null,
        engineCode: '1045',
        message: 'Access denied',
      );
      expect(failure.kind, ConnectionFailureKind.unknown);
      expect(failure.errorCode, '1045');
    });

    test('新枚举值 toString 无回归（AdapterConnectException 冻结格式）', () {
      final failure = gatewayEnvelopeFailure(
        code: 'AUTH_DENIED',
        message: 'bad credentials',
      );
      final exception = AdapterConnectException(failure, StateError('x'));
      expect(
        exception.toString(),
        'AdapterConnectException('
        '${ConnectionFailureKind.authFailed}, code=AUTH_DENIED): '
        'bad credentials',
      );
    });
  });

  group('ConnectionFailure / AdapterConnectException（载体契约）', () {
    test('ConnectionFailure 字段完整保留', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1758260000000);
      final failure = ConnectionFailure(
        kind: ConnectionFailureKind.fileLocked,
        errorCode: '5',
        offendingStatement: 'PRAGMA journal_mode = DELETE',
        target: r'C:\data\chinook.db',
        rawMessage: 'database is locked',
        occurredAt: at,
      );
      expect(failure.kind, ConnectionFailureKind.fileLocked);
      expect(failure.errorCode, '5');
      expect(failure.offendingStatement, 'PRAGMA journal_mode = DELETE');
      expect(failure.target, r'C:\data\chinook.db');
      expect(failure.rawMessage, 'database is locked');
      expect(failure.occurredAt, at);
    });

    test('AdapterConnectException 保留 cause 链且 toString 为冻结格式', () {
      final original = StateError('os error 32');
      final failure = ConnectionFailure(
        kind: ConnectionFailureKind.permissionDenied,
        errorCode: '14',
        target: '/opt/db/readonly.db',
        rawMessage: 'unable to open database file',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(1758260000001),
      );
      final exception = AdapterConnectException(failure, original);
      expect(exception.failure, same(failure));
      expect(exception.cause, same(original));
      expect(
        exception.toString(),
        'AdapterConnectException('
        '${ConnectionFailureKind.permissionDenied}, code=14): '
        'unable to open database file',
      );
    });
  });
}
