import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/sql_server_batch_splitter.dart';

void main() {
  group('splitSqlServerBatches', () {
    test('splits a T-SQL script at GO batch terminators (TC-SS-QRY-003)', () {
      const script = '''
CREATE TABLE t_go1 (id INT);
GO
CREATE TABLE t_go2 (id INT);
GO
''';
      final batches = splitSqlServerBatches(script);
      expect(batches.length, equals(2));
      expect(batches[0], contains('CREATE TABLE t_go1'));
      expect(batches[1], contains('CREATE TABLE t_go2'));
    });

    test('supports GO N repeat count', () {
      const script = '''
SELECT 1;
GO 3
''';
      final batches = splitSqlServerBatches(script);
      expect(batches.length, equals(3));
      expect(batches.every((b) => b.contains('SELECT 1')), isTrue);
    });

    test('is case-insensitive for GO', () {
      const script = '''
SELECT 1;
go
SELECT 2;
Go
''';
      final batches = splitSqlServerBatches(script);
      expect(batches.length, equals(2));
      expect(batches[0], contains('SELECT 1'));
      expect(batches[1], contains('SELECT 2'));
    });

    test(
      'only treats GO as batch terminator when it stands alone on a line',
      () {
        const script = '''
SELECT * FROM dbo.goods
WHERE name = 'go';
GO
SELECT * FROM dbo.go;
''';
        final batches = splitSqlServerBatches(script);
        expect(batches.length, equals(2));
        expect(batches[0], contains("name = 'go'"));
        expect(batches[1], contains('dbo.go'));
      },
    );

    test('falls back to semicolon splitting when no GO is present', () {
      const script = 'SELECT 1; SELECT 2;';
      final batches = splitSqlServerBatches(script);
      expect(batches.length, equals(2));
      expect(batches[0], equals('SELECT 1'));
      expect(batches[1], equals('SELECT 2'));
    });

    test('no-GO fast path keeps semicolons inside string literals intact', () {
      const script = "INSERT INTO t VALUES ('a;b'); SELECT 2;";
      final batches = splitSqlServerBatches(script);
      expect(batches.length, equals(2));
      expect(batches[0], equals("INSERT INTO t VALUES ('a;b')"));
      expect(batches[1], equals('SELECT 2'));
    });

    test('skips empty batches', () {
      const script = '''
GO
GO
SELECT 1;
''';
      final batches = splitSqlServerBatches(script);
      expect(batches.length, equals(1));
      expect(batches.first, equals('SELECT 1;'));
    });
  });
}
