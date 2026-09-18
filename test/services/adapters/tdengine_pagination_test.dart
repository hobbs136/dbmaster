import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/sql_sanitizer.dart';

/// TDengine SQL generation tests
void main() {
  group('SuperTable identifier escaping', () {
    test('SuperTable name should use identifier escaping in subquery', () {
      final stableName = SqlSanitizer.identifier('meters');
      expect(stableName, equals('`meters`'));
    });

    test('SuperTable name with underscore should be escaped correctly', () {
      final stableName = SqlSanitizer.identifier('my_table');
      expect(stableName, equals('`my_table`'));
    });
  });

  group('SubTable creation SQL', () {
    test('CREATE TABLE USING should use identifier escaping for names', () {
      final tableName = SqlSanitizer.identifier('device_001');
      final superTableName = SqlSanitizer.identifier('meters');
      final sql =
          'CREATE TABLE $tableName USING $superTableName TAGS (\'location_a\')';
      expect(sql, contains('`device_001`'));
      expect(sql, contains('`meters`'));
      expect(sql, isNot(contains("'meters'")));
    });
  });

  group('String value escaping', () {
    test('String values should be properly escaped', () {
      final value = SqlSanitizer.value("device'");
      expect(value, equals("'device'''"));
    });

    test('LIKE pattern should be escaped', () {
      final pattern = SqlSanitizer.value('%sensor%');
      expect(pattern, equals("'%sensor%'"));
    });
  });
}
