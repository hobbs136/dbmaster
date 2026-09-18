// 回归测试——PG 适配器需正确拆分 schema 限定表名。
// 侧栏 _loadTableSchema 对 PG 传入 'public.users'，而 information_schema.columns
// 的 table_name 仅是 'users'；若不拆分，WHERE table_name='public.users' 永远为空，
// 导致侧栏与 Properties 都看不到字段/索引（但 SELECT 正常）。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';

void main() {
  group('PostgreSQLAdapter.splitSchemaTable', () {
    test('拆分默认 schema 限定名', () {
      final (schema, table) =
          PostgreSQLAdapter.splitSchemaTable('public.users');
      expect(schema, 'public');
      expect(table, 'users');
    });

    test('拆分非默认 schema', () {
      final (schema, table) =
          PostgreSQLAdapter.splitSchemaTable('analytics.events');
      expect(schema, 'analytics');
      expect(table, 'events');
    });

    test('无 schema 前缀时 schema 为 null，原样返回表名', () {
      final (schema, table) = PostgreSQLAdapter.splitSchemaTable('users');
      expect(schema, isNull);
      expect(table, 'users');
    });

    test('以点开头或结尾的名字不误拆', () {
      final (s1, t1) = PostgreSQLAdapter.splitSchemaTable('.users');
      expect(s1, isNull);
      expect(t1, '.users');

      final (s2, t2) = PostgreSQLAdapter.splitSchemaTable('users.');
      expect(s2, isNull);
      expect(t2, 'users.');
    });
  });
}
