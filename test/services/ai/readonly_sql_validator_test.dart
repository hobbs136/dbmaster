import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/ai/readonly_sql_validator.dart';

// =============================================================================
// 通用数据库 Agent · run_readonly_query 只读校验器单元测试。
// =============================================================================
// 覆盖：首关键字白名单 / 多语句拒绝 / INTO/FOR UPDATE 黑名单 /
// WITH-CTE 藏 DML / EXPLAIN ANALYZE / SQLite PRAGMA 名单 /
// 字符串字面量与注释掩码（防误伤、防漏判）。
// =============================================================================

void main() {
  group('ReadonlySqlValidator.validate · 放行', () {
    const allowed = <String>[
      "SELECT * FROM tasks WHERE assignee_id = 7 AND iteration_id = 4 LIMIT 100",
      "SELECT a.* FROM tasks a JOIN users u ON a.assignee_id = u.id",
      'SELECT * FROM "tasks" WHERE name = \'plain delete me\'',
      "WITH recent AS (SELECT id FROM tasks WHERE created_at > NOW() - INTERVAL '7 days') SELECT * FROM recent",
      "SHOW TABLES",
      "EXPLAIN SELECT * FROM tasks",
      "DESCRIBE tasks",
      "DESC tasks",
      "SELECT COUNT(*) FROM task_comments WHERE task_id IN (SELECT id FROM tasks WHERE assignee_id = 7)",
      // 尾部分号允许
      "SELECT 1;",
      // 字面量里的分号 / 注释里的分号不误伤
      "SELECT * FROM t WHERE note = 'a;b'",
      "SELECT 1 /* ; DROP TABLE x */ FROM t",
      "SELECT * FROM t -- comment with ; semicolon\nWHERE id = 1",
    ];

    for (final sql in allowed) {
      test('allows: ${sql.length > 60 ? '${sql.substring(0, 60)}…' : sql}', () {
        final check = ReadonlySqlValidator.validate(sql, isSqlite: false);
        expect(check.allowed, isTrue, reason: 'should allow: $sql');
      });
    }

    test('SQLite 只读 PRAGMA 放行', () {
      for (final pragma in [
        'PRAGMA table_info(tasks)',
        'PRAGMA foreign_key_list(tasks)',
        'PRAGMA index_list(tasks)',
      ]) {
        final check = ReadonlySqlValidator.validate(pragma, isSqlite: true);
        expect(check.allowed, isTrue, reason: pragma);
      }
    });
  });

  group('ReadonlySqlValidator.validate · 拒绝', () {
    const denied = <String>[
      // 写语句前缀
      "DELETE FROM tasks WHERE id = 1",
      "UPDATE tasks SET title = 'x' WHERE id = 1",
      "INSERT INTO tasks (id) VALUES (1)",
      "DROP TABLE tasks",
      "TRUNCATE TABLE tasks",
      "ALTER TABLE tasks ADD COLUMN x INT",
      "CREATE TABLE t (id INT)",
      "GRANT ALL ON *.* TO u",
      "SET @x = 1",
      "CALL do_something()",
      // 多语句
      "SELECT 1; DROP TABLE tasks",
      "SELECT 1; SELECT 2",
      // SELECT ... INTO（写表/文件/变量）
      "SELECT * INTO OUTFILE '/tmp/x' FROM tasks",
      "SELECT * INTO DUMPFILE '/tmp/x' FROM tasks",
      "SELECT @total := COUNT(*) FROM tasks",
      "SELECT * INTO new_table FROM tasks",
      // 锁定子句
      "SELECT * FROM tasks WHERE id = 1 FOR UPDATE",
      "SELECT * FROM tasks WHERE id = 1 FOR SHARE",
      "SELECT * FROM tasks LOCK IN SHARE MODE",
      // WITH CTE 藏 DML（PG 可执行）
      "WITH del AS (DELETE FROM tasks RETURNING id) SELECT * FROM del",
      "WITH x AS (SELECT 1) UPDATE tasks SET title = 'x'",
      "WITH x AS (SELECT 1) INSERT INTO t VALUES (1)",
      // EXPLAIN 危险形态
      "EXPLAIN ANALYZE DELETE FROM tasks",
      "EXPLAIN ANALYZE UPDATE tasks SET title = 'x'",
      "EXPLAIN DELETE FROM tasks",
      // 空语句 / 非关键字开头
      "",
      "   ",
      ";",
      "123",
    ];

    for (final sql in denied) {
      test('denies: ${sql.length > 60 ? '${sql.substring(0, 60)}…' : sql}', () {
        final check = ReadonlySqlValidator.validate(sql, isSqlite: false);
        expect(check.allowed, isFalse, reason: 'should deny: $sql');
        expect(check.reason, isNotNull);
      });
    }

    test('PRAGMA 非 SQLite 连接拒绝', () {
      final check = ReadonlySqlValidator.validate(
        'PRAGMA table_info(tasks)',
        isSqlite: false,
      );
      expect(check.allowed, isFalse);
    });

    test('SQLite 写性 PRAGMA 拒绝', () {
      for (final pragma in [
        'PRAGMA writable_schema = ON',
        'PRAGMA journal_mode = DELETE',
        'PRAGMA user_version = 2',
      ]) {
        final check = ReadonlySqlValidator.validate(pragma, isSqlite: true);
        expect(check.allowed, isFalse, reason: pragma);
      }
    });
  });
}
