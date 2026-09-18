import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/schema_analyzer/rollback_generator.dart';

void main() {
  group('RollbackGenerator.generateRollback', () {
    test('DROP_TABLE generates rollback with data backup warning', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'DROP TABLE users',
        ddlType: 'DROP_TABLE',
        tableName: 'users',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.requiresDataBackup, true);
      expect(script.description, contains('backup'));
      expect(script.rollbackDdl, contains('Cannot automatically restore'));
    });

    test('DROP_COLUMN generates ADD COLUMN rollback', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users DROP COLUMN email',
        ddlType: 'DROP_COLUMN',
        tableName: 'users',
        columnName: 'email',
        columnType: 'VARCHAR(255)',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.requiresDataBackup, true);
      expect(script.rollbackDdl, contains('ADD COLUMN email VARCHAR(255)'));
      expect(script.originalDdl, contains('DROP COLUMN email'));
    });

    test('DROP_COLUMN with null column defaults', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE t DROP COLUMN c',
        ddlType: 'DROP_COLUMN',
        tableName: 't',
        columnName: null,
        columnType: null,
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('VARCHAR(255)'));
      expect(script.rollbackDdl, contains('column_name'));
    });

    test('DROP_COLUMN for SQLite', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users DROP COLUMN email',
        ddlType: 'DROP_COLUMN',
        tableName: 'users',
        columnName: 'email',
        columnType: 'VARCHAR(100)',
        databaseType: 'sqlite',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('SQLite'));
    });

    test('DROP_COLUMN for PostgreSQL', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users DROP COLUMN email',
        ddlType: 'DROP_COLUMN',
        tableName: 'users',
        columnName: 'email',
        columnType: 'TEXT',
        databaseType: 'postgresql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('ADD COLUMN email TEXT'));
    });

    test('ALTER_COLUMN generates MODIFY rollback for MySQL', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users MODIFY COLUMN age INT',
        ddlType: 'ALTER_COLUMN',
        tableName: 'users',
        columnName: 'age',
        columnType: 'BIGINT',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('MODIFY COLUMN age BIGINT'));
      expect(script.requiresDataBackup, true);
    });

    test('ALTER_COLUMN generates rollback for PostgreSQL', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users ALTER COLUMN age TYPE INT',
        ddlType: 'ALTER_COLUMN',
        tableName: 'users',
        columnName: 'age',
        columnType: 'BIGINT',
        databaseType: 'postgresql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('ALTER COLUMN age TYPE BIGINT'));
    });

    test('ADD_COLUMN generates DROP COLUMN rollback for MySQL', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users ADD COLUMN phone VARCHAR(20)',
        ddlType: 'ADD_COLUMN',
        tableName: 'users',
        columnName: 'phone',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('DROP COLUMN phone'));
      expect(script.requiresDataBackup, false);
    });

    test('ADD_COLUMN generates rollback for PostgreSQL', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users ADD COLUMN phone VARCHAR(20)',
        ddlType: 'ADD_COLUMN',
        tableName: 'users',
        columnName: 'phone',
        databaseType: 'postgresql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('DROP COLUMN IF EXISTS phone'));
    });

    test('ADD_COLUMN for SQLite with special instructions', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'ALTER TABLE users ADD COLUMN phone VARCHAR(20)',
        ddlType: 'ADD_COLUMN',
        tableName: 'users',
        columnName: 'phone',
        databaseType: 'sqlite',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('SQLite'));
      expect(script.rollbackDdl, contains('table recreation'));
    });

    test('CREATE_INDEX generates DROP INDEX rollback', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'CREATE UNIQUE INDEX idx_users_email ON users(email)',
        ddlType: 'CREATE_INDEX',
        tableName: 'users',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('DROP INDEX'));
      expect(script.rollbackDdl, contains('idx_users_email'));
      expect(script.requiresDataBackup, false);
    });

    test('DROP_INDEX generates warning rollback', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'DROP INDEX idx_users_email',
        ddlType: 'DROP_INDEX',
        tableName: 'users',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('Cannot automatically recreate'));
    });

    test('RENAME_TABLE generates reverse rename for MySQL', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'RENAME TABLE users TO customers',
        ddlType: 'RENAME_TABLE',
        tableName: 'users',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('RENAME TABLE customers TO users'));
      expect(script.requiresDataBackup, false);
    });

    test('RENAME_TABLE for PostgreSQL generates ALTER TABLE RENAME', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'RENAME TABLE users TO customers',
        ddlType: 'RENAME_TABLE',
        tableName: 'users',
        databaseType: 'postgresql',
      );
      expect(script, isNotNull);
      expect(
        script!.rollbackDdl,
        contains('ALTER TABLE customers RENAME TO users'),
      );
    });

    test('RENAME_TABLE with unparseable statement generates warning', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'RENAME something unparseable',
        ddlType: 'RENAME_TABLE',
        tableName: 'something',
        databaseType: 'mysql',
      );
      expect(script, isNotNull);
      expect(script!.rollbackDdl, contains('Could not parse'));
    });

    test('Unknown DDL type returns null', () {
      final script = RollbackGenerator.generateRollback(
        ddlStatement: 'SOME UNKNOWN DDL',
        ddlType: 'UNKNOWN_TYPE',
        tableName: 'users',
        databaseType: 'mysql',
      );
      expect(script, isNull);
    });
  });

  group('RollbackGenerator.extractColumnName', () {
    test('extracts column name from DROP COLUMN', () {
      final name = RollbackGenerator.extractColumnName(
        'ALTER TABLE users DROP COLUMN email',
        'DROP_COLUMN',
      );
      expect(name, 'email');
    });

    test('extracts column name from ADD COLUMN', () {
      final name = RollbackGenerator.extractColumnName(
        'ALTER TABLE users ADD COLUMN phone VARCHAR(20)',
        'ADD_COLUMN',
      );
      expect(name, 'phone');
    });

    test('extracts column name from ALTER COLUMN', () {
      final name = RollbackGenerator.extractColumnName(
        'ALTER TABLE users ALTER COLUMN age TYPE INT',
        'ALTER_COLUMN',
      );
      expect(name, 'age');
    });

    test('returns null for non-column DDL types', () {
      final name = RollbackGenerator.extractColumnName(
        'DROP TABLE users',
        'DROP_TABLE',
      );
      expect(name, isNull);
    });
  });
}
