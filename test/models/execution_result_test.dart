import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';

void main() {
  group('ExecutionResult', () {
    final selectStatement = SQLStatement(
      index: 0,
      sql: 'SELECT * FROM users',
      type: SQLType.select,
      lineStart: 1,
      lineEnd: 1,
    );
    final insertStatement = SQLStatement(
      index: 0,
      sql: 'INSERT INTO users VALUES (1)',
      type: SQLType.insert,
      lineStart: 1,
      lineEnd: 1,
    );

    test('构造成功结果', () {
      final result = ExecutionResult(
        statement: selectStatement,
        success: true,
        data: [
          {'id': 1},
        ],
        executionTime: const Duration(milliseconds: 100),
      );
      expect(result.success, isTrue);
      expect(result.hasData, isTrue);
      expect(result.isSelect, isTrue);
      expect(result.isDML, isFalse);
    });

    test('构造失败结果', () {
      final result = ExecutionResult(
        statement: selectStatement,
        success: false,
        executionTime: const Duration(milliseconds: 50),
        errorMessage: 'Syntax error',
        errorCode: '42000',
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Syntax error'));
      expect(result.errorCode, equals('42000'));
      expect(result.hasData, isFalse);
    });

    test('isDML 识别 INSERT/UPDATE/DELETE', () {
      final insert = ExecutionResult(
        statement: insertStatement,
        success: true,
        affectedRows: 1,
        executionTime: const Duration(milliseconds: 20),
      );
      expect(insert.isDML, isTrue);
      expect(insert.isSelect, isFalse);
    });

    test('hasData 空数据返回 false', () {
      final result = ExecutionResult(
        statement: selectStatement,
        success: true,
        data: [],
        executionTime: const Duration(milliseconds: 10),
      );
      expect(result.hasData, isFalse);
    });

    test('hasData null 数据返回 false', () {
      final result = ExecutionResult(
        statement: selectStatement,
        success: true,
        executionTime: const Duration(milliseconds: 10),
      );
      expect(result.hasData, isFalse);
    });

    test('copyWith 更新字段', () {
      final result = ExecutionResult(
        statement: selectStatement,
        success: true,
        data: [
          {'id': 1},
        ],
        executionTime: const Duration(milliseconds: 100),
      );
      final updated = result.copyWith(success: false, errorMessage: 'Timeout');
      expect(updated.success, isFalse);
      expect(updated.errorMessage, equals('Timeout'));
      expect(updated.data, equals(result.data));
      expect(updated.statement, equals(result.statement));
    });

    test('toJson / fromJson 序列化', () {
      final result = ExecutionResult(
        statement: selectStatement,
        success: true,
        data: [
          {'id': 1, 'name': 'Alice'},
        ],
        affectedRows: 0,
        executionTime: const Duration(milliseconds: 150),
        isTruncated: true,
        limitValue: 100,
      );
      final json = result.toJson();
      expect(json['success'], isTrue);
      expect(json['affectedRows'], equals(0));
      expect(json['isTruncated'], isTrue);
      expect(json['limitValue'], equals(100));
    });

    test('isTruncated 默认值', () {
      final result = ExecutionResult(
        statement: selectStatement,
        success: true,
        executionTime: Duration.zero,
      );
      expect(result.isTruncated, isFalse);
    });
  });
}
