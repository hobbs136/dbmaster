import '../../models/schema_analyzer/impact_report.dart';

/// 回滚脚本生成器
/// 为 DDL 操作生成对应的回滚脚本
class RollbackGenerator {
  /// 生成回滚脚本
  static RollbackScript? generateRollback({
    required String ddlStatement,
    required String ddlType,
    required String tableName,
    String? columnName,
    String? columnType,
    required String databaseType,
  }) {
    switch (ddlType) {
      case 'DROP_TABLE':
        return _generateDropTableRollback(
          tableName: tableName,
          databaseType: databaseType,
        );
      case 'DROP_COLUMN':
        return _generateDropColumnRollback(
          tableName: tableName,
          columnName: columnName,
          columnType: columnType,
          databaseType: databaseType,
        );
      case 'ALTER_COLUMN':
        return _generateAlterColumnRollback(
          tableName: tableName,
          columnName: columnName,
          columnType: columnType,
          databaseType: databaseType,
        );
      case 'ADD_COLUMN':
        return _generateAddColumnRollback(
          tableName: tableName,
          columnName: columnName,
          databaseType: databaseType,
        );
      case 'CREATE_INDEX':
        return _generateCreateIndexRollback(
          ddlStatement: ddlStatement,
          databaseType: databaseType,
        );
      case 'DROP_INDEX':
        return _generateDropIndexRollback(
          ddlStatement: ddlStatement,
          databaseType: databaseType,
        );
      case 'RENAME_TABLE':
        return _generateRenameTableRollback(
          ddlStatement: ddlStatement,
          databaseType: databaseType,
        );
      default:
        return null;
    }
  }

  /// 生成 DROP TABLE 回滚
  static RollbackScript _generateDropTableRollback({
    required String tableName,
    required String databaseType,
  }) {
    return RollbackScript(
      originalDdl: 'DROP TABLE $tableName',
      rollbackDdl:
          '-- ⚠️ Cannot automatically restore dropped table\n'
          '-- Please restore from your backup if needed\n'
          '-- Table name: $tableName',
      description:
          'Table drop cannot be rolled back automatically. Please ensure you have a backup.',
      requiresDataBackup: true,
    );
  }

  /// 生成 DROP COLUMN 回滚
  static RollbackScript _generateDropColumnRollback({
    required String tableName,
    required String? columnName,
    required String? columnType,
    required String databaseType,
  }) {
    final type = columnType ?? 'VARCHAR(255)';
    final col = columnName ?? 'column_name';

    String rollbackDdl;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
        rollbackDdl = 'ALTER TABLE $tableName ADD COLUMN $col $type;';
        break;
      case 'postgresql':
        rollbackDdl = 'ALTER TABLE $tableName ADD COLUMN $col $type;';
        break;
      case 'sqlite':
        // SQLite 不支持直接删除列，需要重建表
        rollbackDdl =
            '-- SQLite: Column drop requires table recreation\n'
            '-- Please restore from backup if needed';
        break;
      default:
        rollbackDdl = 'ALTER TABLE $tableName ADD COLUMN $col $type;';
    }

    return RollbackScript(
      originalDdl: 'ALTER TABLE $tableName DROP COLUMN $col',
      rollbackDdl: rollbackDdl,
      description:
          'Adds the dropped column back. Note: Data cannot be recovered.',
      requiresDataBackup: true,
    );
  }

  /// 生成 ALTER COLUMN 回滚
  static RollbackScript _generateAlterColumnRollback({
    required String tableName,
    required String? columnName,
    required String? columnType,
    required String databaseType,
  }) {
    final type = columnType ?? 'VARCHAR(255)';
    final col = columnName ?? 'column_name';

    String rollbackDdl;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
        rollbackDdl = 'ALTER TABLE $tableName MODIFY COLUMN $col $type;';
        break;
      case 'postgresql':
        rollbackDdl = 'ALTER TABLE $tableName ALTER COLUMN $col TYPE $type;';
        break;
      default:
        rollbackDdl = 'ALTER TABLE $tableName ALTER COLUMN $col $type;';
    }

    return RollbackScript(
      originalDdl: 'ALTER TABLE $tableName ALTER COLUMN $col',
      rollbackDdl: rollbackDdl,
      description:
          'Restores the original column type. Note: Data may have been altered during conversion.',
      requiresDataBackup: true,
    );
  }

  /// 生成 ADD COLUMN 回滚
  static RollbackScript _generateAddColumnRollback({
    required String tableName,
    required String? columnName,
    required String databaseType,
  }) {
    final col = columnName ?? 'column_name';

    String rollbackDdl;
    switch (databaseType.toLowerCase()) {
      case 'mysql':
        rollbackDdl = 'ALTER TABLE $tableName DROP COLUMN $col;';
        break;
      case 'postgresql':
        rollbackDdl = 'ALTER TABLE $tableName DROP COLUMN IF EXISTS $col;';
        break;
      case 'sqlite':
        rollbackDdl =
            '-- SQLite: Column removal requires table recreation\n'
            '-- Use: CREATE TABLE new_table AS SELECT * FROM $tableName;\n'
            '-- Then recreate without column $col';
        break;
      default:
        rollbackDdl = 'ALTER TABLE $tableName DROP COLUMN $col;';
    }

    return RollbackScript(
      originalDdl: 'ALTER TABLE $tableName ADD COLUMN $col',
      rollbackDdl: rollbackDdl,
      description: 'Removes the added column.',
      requiresDataBackup: false,
    );
  }

  /// 生成 CREATE INDEX 回滚
  static RollbackScript _generateCreateIndexRollback({
    required String ddlStatement,
    required String databaseType,
  }) {
    // 提取索引名
    final indexMatch = RegExp(
      r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(ddlStatement);
    final indexName = indexMatch?.group(1) ?? 'index_name';

    return RollbackScript(
      originalDdl: ddlStatement,
      rollbackDdl: 'DROP INDEX $indexName;',
      description: 'Drops the created index.',
      requiresDataBackup: false,
    );
  }

  /// 生成 DROP INDEX 回滚
  static RollbackScript _generateDropIndexRollback({
    required String ddlStatement,
    required String databaseType,
  }) {
    // 提取索引名
    final indexMatch = RegExp(
      r'DROP\s+INDEX\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(ddlStatement);
    final indexName = indexMatch?.group(1) ?? 'index_name';

    return RollbackScript(
      originalDdl: ddlStatement,
      rollbackDdl:
          '-- ⚠️ Cannot automatically recreate dropped index: $indexName\n'
          '-- Please recreate manually if needed',
      description:
          'Dropped index cannot be automatically restored. Please recreate from schema backup.',
      requiresDataBackup: false,
    );
  }

  /// 生成 RENAME TABLE 回滚
  static RollbackScript _generateRenameTableRollback({
    required String ddlStatement,
    required String databaseType,
  }) {
    // 提取旧名和新名
    final renameMatch = RegExp(
      r'RENAME\s+TABLE\s+(\w+)\s+TO\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(ddlStatement);

    if (renameMatch != null) {
      final oldName = renameMatch.group(1)!;
      final newName = renameMatch.group(2)!;

      String rollbackDdl;
      switch (databaseType.toLowerCase()) {
        case 'mysql':
          rollbackDdl = 'RENAME TABLE $newName TO $oldName;';
          break;
        case 'postgresql':
          rollbackDdl = 'ALTER TABLE $newName RENAME TO $oldName;';
          break;
        default:
          rollbackDdl = 'RENAME TABLE $newName TO $oldName;';
      }

      return RollbackScript(
        originalDdl: ddlStatement,
        rollbackDdl: rollbackDdl,
        description: 'Restores the original table name.',
        requiresDataBackup: false,
      );
    }

    return RollbackScript(
      originalDdl: ddlStatement,
      rollbackDdl: '-- Could not parse rename statement',
      description: 'Could not generate rollback script automatically.',
      requiresDataBackup: false,
    );
  }

  /// 提取列名
  static String? extractColumnName(String ddlStatement, String ddlType) {
    if (ddlType == 'DROP_COLUMN' || ddlType == 'ADD_COLUMN') {
      final match = RegExp(
        r'COLUMN\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(ddlStatement);
      return match?.group(1);
    }

    if (ddlType == 'ALTER_COLUMN') {
      final match = RegExp(
        r'ALTER\s+COLUMN\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(ddlStatement);
      return match?.group(1);
    }

    return null;
  }
}
