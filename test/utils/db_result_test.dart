import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/db_result.dart';

void main() {
  group('Result<T> - Success', () {
    test('isSuccess 应为 true', () {
      const result = Success<int>(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('data 应返回值', () {
      const result = Success<String>('hello');
      expect(result.data, 'hello');
    });

    test('error 应为 null', () {
      const result = Success<int>(1);
      expect(result.error, isNull);
    });

    test('fold 应调用 onSuccess', () {
      const result = Success<int>(10);
      final value = result.fold(onSuccess: (d) => d * 2, onFailure: (e) => -1);
      expect(value, 20);
    });

    test('map 应转换数据', () {
      const result = Success<int>(5);
      final mapped = result.map((d) => d.toString());
      expect(mapped.isSuccess, isTrue);
      expect(mapped.data, '5');
    });

    test('getOrElse 应返回数据', () {
      const result = Success<int>(7);
      expect(result.getOrElse(100), 7);
    });

    test('getOrThrow 应返回数据', () {
      const result = Success<String>('ok');
      expect(result.getOrThrow(), 'ok');
    });
  });

  group('Result<T> - Failure', () {
    test('isFailure 应为 true', () {
      const error = DbQueryError(
        type: DbQueryErrorType.queryFailed,
        message: 'Failed',
      );
      const result = Failure<int>(error);
      expect(result.isFailure, isTrue);
      expect(result.isSuccess, isFalse);
    });

    test('data 应为 null', () {
      const error = DbQueryError(
        type: DbQueryErrorType.connectionFailed,
        message: 'Disconnected',
      );
      const result = Failure<String>(error);
      expect(result.data, isNull);
    });

    test('error 应返回错误', () {
      const error = DbQueryError(
        type: DbQueryErrorType.tableNotFound,
        message: 'Missing',
      );
      const result = Failure<int>(error);
      expect(result.error, error);
    });

    test('fold 应调用 onFailure', () {
      const error = DbQueryError(
        type: DbQueryErrorType.queryFailed,
        message: 'Syntax error',
      );
      const result = Failure<int>(error);
      final value = result.fold(
        onSuccess: (d) => 'success',
        onFailure: (e) => e.type.name,
      );
      expect(value, 'queryFailed');
    });

    test('map 应传递错误', () {
      const error = DbQueryError(
        type: DbQueryErrorType.unknown,
        message: 'Oops',
      );
      const result = Failure<int>(error);
      final mapped = result.map((d) => d.toString());
      expect(mapped.isFailure, isTrue);
      expect(mapped.error, error);
    });

    test('getOrElse 应返回默认值', () {
      const error = DbQueryError(
        type: DbQueryErrorType.queryTimeout,
        message: 'Timeout',
      );
      const result = Failure<int>(error);
      expect(result.getOrElse(999), 999);
    });

    test('getOrThrow 应抛出异常', () {
      const error = DbQueryError(
        type: DbQueryErrorType.permissionDenied,
        message: 'No access',
      );
      const result = Failure<String>(error);
      expect(() => result.getOrThrow(), throwsA(isA<Exception>()));
    });
  });

  group('DbQueryError factory constructors', () {
    test('connectionFailed factory', () {
      final e = DbQueryError.connectionFailed('host unreachable');
      expect(e.type, DbQueryErrorType.connectionFailed);
      expect(e.message, contains('连接失败'));
      expect(e.message, contains('host unreachable'));
    });

    test('connectionTimeout factory', () {
      final e = DbQueryError.connectionTimeout();
      expect(e.type, DbQueryErrorType.connectionTimeout);
      expect(e.message, contains('连接超时'));
    });

    test('queryFailed factory', () {
      final e = DbQueryError.queryFailed('SELECT *', 'syntax');
      expect(e.type, DbQueryErrorType.queryFailed);
      expect(e.sql, 'SELECT *');
      expect(e.message, contains('syntax'));
    });
  });

  group('DbQueryErrorType labels', () {
    test('所有类型应有中文标签', () {
      for (final type in DbQueryErrorType.values) {
        expect(type.label, isNotEmpty);
        expect(type.label, isNot(contains('null')));
      }
    });

    test('connectionFailed 标签', () {
      expect(DbQueryErrorType.connectionFailed.label, '连接失败');
    });

    test('dangerousOperation 标签', () {
      expect(DbQueryErrorType.dangerousOperation.label, '危险操作');
    });
  });
}
