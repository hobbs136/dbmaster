import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/results/json_field_picker.dart';
import 'package:dbmaster/models/database_models.dart';

/// US4 JsonExtractionSql 单测（T059）。
/// 覆盖 PG/MySQL/SQLite 三种语法 + 嵌套路径 + 数组下标 + 原列保留。
void main() {
  group('JsonExtractionSql.generate - PostgreSQL', () {
    test('单层字段：col->>\'field\'', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'name',
        databaseType: DatabaseType.postgresql,
        sourceTable: 'users',
        originalColumns: ['id', 'data'],
      );
      // 末层用 ->> 取 text
      expect(sql, contains('"data"->>\'name\''));
      expect(sql, contains('AS "name"'));
      // 保留原列
      expect(sql, contains('"id", "data"'));
      expect(sql, contains('FROM users'));
    });

    test('嵌套字段：col->\'a\'->\'b\'->>\'c\'', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'a.b.c',
        databaseType: DatabaseType.postgresql,
        sourceTable: 't',
        originalColumns: ['data'],
      );
      // 中间层用 ->，末层用 ->>
      expect(sql, contains('"data"->\'a\'->\'b\'->>\'c\''));
      expect(sql, contains('AS "c"'));
    });

    test('数组下标：col->\'tags\'->>0（整数下标）', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'tags[0]',
        databaseType: DatabaseType.postgresql,
        sourceTable: 't',
        originalColumns: ['data'],
      );
      // PG 对象键 ->'tags'，数组整数下标 ->>0（末层取 text）
      expect(sql, contains('"data"->\'tags\'->>0'));
    });
  });

  group('JsonExtractionSql.generate - MySQL', () {
    test('JSON_EXTRACT + \$.path', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'user.name',
        databaseType: DatabaseType.mysql,
        sourceTable: 'users',
        originalColumns: ['id', 'data'],
      );
      expect(sql, contains("JSON_EXTRACT(\"data\", '\$.user.name')"));
      expect(sql, contains('AS "name"'));
      expect(sql, contains('"id", "data"'));
    });

    test('数组路径', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'items[0].id',
        databaseType: DatabaseType.mysql,
        sourceTable: 't',
        originalColumns: ['data'],
      );
      // MySQL JSON 路径用 $.items[0].id
      expect(sql, contains('\$'));
    });
  });

  group('JsonExtractionSql.generate - SQLite', () {
    test('json_extract + \$.path', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'config.timeout',
        databaseType: DatabaseType.sqlite,
        sourceTable: 'settings',
        originalColumns: ['id', 'key', 'data'],
      );
      expect(sql, contains("json_extract(\"data\", '\$.config.timeout')"));
      expect(sql, contains('AS "timeout"'));
      // 保留所有原列
      expect(sql, contains('"id", "key", "data"'));
    });
  });

  group('JsonExtractionSql.generate - 通用', () {
    test('无表名用占位符', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'x',
        databaseType: DatabaseType.postgresql,
        originalColumns: ['data'],
      );
      expect(sql, contains('<target_table>'));
    });

    test('保留原列顺序（FR-018）', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'meta',
        fieldPath: 'score',
        databaseType: DatabaseType.mysql,
        sourceTable: 't',
        originalColumns: ['a', 'b', 'c', 'meta'],
      );
      // 原列在前，提取字段在后
      expect(sql.indexOf('"a"'), lessThan(sql.indexOf('"meta"')));
      expect(sql.indexOf('AS "score"'), greaterThan(sql.indexOf('"meta"')));
    });

    test('未知数据库类型兜底 MySQL 风格', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'data',
        fieldPath: 'x',
        databaseType: DatabaseType.redis, // 不支持的类型
        sourceTable: 't',
        originalColumns: ['data'],
      );
      expect(sql, contains('JSON_EXTRACT'));
    });
  });

  group('JsonExtractionSql - 路径别名', () {
    test('user.address.city → city', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'd',
        fieldPath: 'user.address.city',
        databaseType: DatabaseType.sqlite,
        sourceTable: 't',
        originalColumns: ['d'],
      );
      expect(sql, contains('AS "city"'));
    });

    test('单字段 name → name', () {
      final sql = JsonExtractionSql.generate(
        columnName: 'd',
        fieldPath: 'name',
        databaseType: DatabaseType.sqlite,
        sourceTable: 't',
        originalColumns: ['d'],
      );
      expect(sql, contains('AS "name"'));
    });
  });
}
