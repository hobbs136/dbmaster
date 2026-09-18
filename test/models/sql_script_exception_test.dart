import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/sql_script_exception.dart';

void main() {
  group('SqlScriptExecutionException', () {
    test('toString 带行号范围与已执行条数', () {
      const e = SqlScriptExecutionException(
        statementIndex: 2,
        lineStart: 12,
        lineEnd: 15,
        statementSql: 'ALTER TABLE t ADD COLUMN c INT',
        cause: 'Exception: syntax error',
        committedCount: 2,
      );

      expect(e.toString(), contains('第 3 条语句'));
      expect(e.toString(), contains('第 12-15 行'));
      expect(e.toString(), contains('syntax error'));
      expect(e.toString(), contains('前 2 条已执行生效'));
      expect(e.toString(), contains('未执行'));
    });

    test('单行语句不输出行号范围，零已执行不输出部分提交提示', () {
      const e = SqlScriptExecutionException(
        statementIndex: 0,
        lineStart: 1,
        lineEnd: 1,
        statementSql: 'INVALID',
        cause: 'Exception: bad sql',
        committedCount: 0,
      );

      expect(e.toString(), contains('第 1 条语句（第 1 行）'));
      expect(e.toString(), isNot(contains('已执行生效')));
      expect(e.toString(), isNot(contains('-')));
    });

    test('行号未知（网关/GO 批路径）只报序号', () {
      const e = SqlScriptExecutionException(
        statementIndex: 4,
        statementSql: 'BATCH',
        cause: 'err',
        committedCount: 3,
      );

      expect(e.toString(), contains('第 5 条语句'));
      expect(e.toString(), isNot(contains('行）')));
    });
  });
}
