// SchemaCompatRule 单测（ADR-0003 Part A T8）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart'
    show Database, DbTable, DbColumn, DatabaseType;
import 'package:dbmaster/models/sql_statement.dart' show SQLType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/schema_compat_rule.dart';

/// 构造含一个表（id, name, status 列）的 schema。
Database _schemaWithUsers() {
  return Database(
    name: 'testdb',
    tables: [
      DbTable(
        name: 'users',
        columns: [
          DbColumn(name: 'id', type: 'int'),
          DbColumn(name: 'name', type: 'varchar'),
          DbColumn(name: 'status', type: 'int'),
        ],
      ),
    ],
  );
}

SafetyContext _context({Database? schema}) {
  return SafetyContext(
    connectionId: 'test',
    dbType: DatabaseType.mysql,
    database: 'testdb',
    schemaCache: schema,
    getRowCount: (_) async => null,
    getColumns: (_) async => null,
  );
}

void main() {
  final rule = SchemaCompatRule();

  test('引用存在的列 → 无 finding', () async {
    final findings = await rule.check(
      'SELECT id, name FROM users',
      _context(schema: _schemaWithUsers()),
    );
    expect(findings, isEmpty);
  });

  test('引用不存在的列 → high finding', () async {
    final findings = await rule.check(
      'SELECT id, nonexistent_col FROM users',
      _context(schema: _schemaWithUsers()),
    );
    expect(findings.length, 1);
    expect(findings.first.severity, Severity.high);
    expect(findings.first.title, contains('nonexistent_col'));
  });

  test('WHERE 子句引用不存在的列 → high finding', () async {
    final findings = await rule.check(
      'SELECT * FROM users WHERE bad_col = 1',
      _context(schema: _schemaWithUsers()),
    );
    expect(findings.length, 1);
    expect(findings.first.title, contains('bad_col'));
  });

  test('schemaCache null → 跳过（空 findings）', () async {
    final findings = await rule.check(
      'SELECT id FROM users',
      _context(schema: null),
    );
    expect(findings, isEmpty);
  });

  test('SELECT * → 无法提取列，跳过', () async {
    final findings = await rule.check(
      'SELECT * FROM users',
      _context(schema: _schemaWithUsers()),
    );
    // SELECT * 的列提取返回空（但 WHERE 列仍提取）。
    // 这里 SELECT * FROM users 无 WHERE，应为空。
    expect(findings, isEmpty);
  });

  test('表不在 schemaCache → 跳过', () async {
    final findings = await rule.check(
      'SELECT id FROM unknown_table',
      _context(schema: _schemaWithUsers()),
    );
    expect(findings, isEmpty);
  });

  test('大小写不敏感匹配', () async {
    final findings = await rule.check(
      'SELECT ID, NAME FROM users',
      _context(schema: _schemaWithUsers()),
    );
    expect(findings, isEmpty); // ID/name 大小写不敏感匹配
  });

  test('INSERT 引用不存在的列 → finding', () async {
    final findings = await rule.check(
      'INSERT INTO users (id, bad_col) VALUES (1, 2)',
      _context(schema: _schemaWithUsers()),
    );
    expect(findings.length, 1);
    expect(findings.first.title, contains('bad_col'));
  });
}
