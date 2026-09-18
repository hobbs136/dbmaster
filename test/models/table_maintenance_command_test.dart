import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/table_maintenance_command.dart';

void main() {
  group('TableMaintenanceCommand', () {
    group('sqlKeyword', () {
      test('ANALYZE 关键字正确', () {
        expect(TableMaintenanceCommand.analyze.sqlKeyword, 'ANALYZE');
      });

      test('OPTIMIZE 关键字正确', () {
        expect(TableMaintenanceCommand.optimize.sqlKeyword, 'OPTIMIZE');
      });

      test('CHECK 关键字正确', () {
        expect(TableMaintenanceCommand.check.sqlKeyword, 'CHECK');
      });

      test('VACUUM 关键字正确', () {
        expect(TableMaintenanceCommand.vacuum.sqlKeyword, 'VACUUM');
      });

      test('VACUUM FULL 关键字正确', () {
        expect(TableMaintenanceCommand.vacuumFull.sqlKeyword, 'VACUUM FULL');
      });

      test('PostgreSQL ANALYZE 关键字正确', () {
        expect(TableMaintenanceCommand.pgAnalyze.sqlKeyword, 'ANALYZE');
      });

      test('REINDEX 关键字正确', () {
        expect(TableMaintenanceCommand.reindex.sqlKeyword, 'REINDEX');
      });

      test('REINDEX CONCURRENTLY 关键字正确', () {
        expect(
          TableMaintenanceCommand.reindexConcurrently.sqlKeyword,
          'REINDEX CONCURRENTLY',
        );
      });

      test('CLUSTER 关键字正确', () {
        expect(TableMaintenanceCommand.cluster.sqlKeyword, 'CLUSTER');
      });
    });

    group('buildSql', () {
      test('生成 ANALYZE TABLE SQL', () {
        final sql = TableMaintenanceCommand.analyze.buildSql(
          'my_db',
          'my_table',
        );
        expect(sql, 'ANALYZE TABLE `my_db`.`my_table`');
      });

      test('生成 OPTIMIZE TABLE SQL', () {
        final sql = TableMaintenanceCommand.optimize.buildSql(
          'my_db',
          'my_table',
        );
        expect(sql, 'OPTIMIZE TABLE `my_db`.`my_table`');
      });

      test('生成 CHECK TABLE SQL', () {
        final sql = TableMaintenanceCommand.check.buildSql('my_db', 'my_table');
        expect(sql, 'CHECK TABLE `my_db`.`my_table`');
      });

      test('转义标识符中的反引号', () {
        final sql = TableMaintenanceCommand.analyze.buildSql(
          'my`db',
          'my`table',
        );
        expect(sql, 'ANALYZE TABLE `my``db`.`my``table`');
      });

      test('生成 PostgreSQL VACUUM SQL', () {
        final sql = TableMaintenanceCommand.vacuum.buildSql(
          'public',
          'my_table',
          dbType: DatabaseType.postgresql,
        );
        expect(sql, 'VACUUM "my_table"');
      });

      test('生成 PostgreSQL VACUUM FULL SQL', () {
        final sql = TableMaintenanceCommand.vacuumFull.buildSql(
          'public',
          'my_table',
          dbType: DatabaseType.postgresql,
        );
        expect(sql, 'VACUUM FULL "my_table"');
      });

      test('生成 PostgreSQL ANALYZE SQL', () {
        final sql = TableMaintenanceCommand.pgAnalyze.buildSql(
          'public',
          'my_table',
          dbType: DatabaseType.postgresql,
        );
        expect(sql, 'ANALYZE "my_table"');
      });

      test('生成 PostgreSQL REINDEX SQL', () {
        final sql = TableMaintenanceCommand.reindex.buildSql(
          'public',
          'my_table',
          dbType: DatabaseType.postgresql,
        );
        expect(sql, 'REINDEX TABLE "my_table"');
      });

      test('生成 PostgreSQL REINDEX CONCURRENTLY SQL', () {
        final sql = TableMaintenanceCommand.reindexConcurrently.buildSql(
          'public',
          'my_table',
          dbType: DatabaseType.postgresql,
        );
        expect(sql, 'REINDEX TABLE CONCURRENTLY "my_table"');
      });

      test('生成 PostgreSQL CLUSTER SQL', () {
        final sql = TableMaintenanceCommand.cluster.buildSql(
          'public',
          'my_table',
          dbType: DatabaseType.postgresql,
        );
        expect(sql, 'CLUSTER "my_table"');
      });

      test('PostgreSQL 双引号转义', () {
        final sql = TableMaintenanceCommand.vacuum.buildSql(
          'public',
          'my"_table',
          dbType: DatabaseType.postgresql,
        );
        expect(sql, 'VACUUM "my""_table"');
      });
    });

    group('isPostgreSql', () {
      test('MySQL 命令不是 PostgreSQL 命令', () {
        expect(TableMaintenanceCommand.analyze.isPostgreSql, isFalse);
        expect(TableMaintenanceCommand.optimize.isPostgreSql, isFalse);
        expect(TableMaintenanceCommand.check.isPostgreSql, isFalse);
      });

      test('PostgreSQL 命令标记为 PostgreSQL', () {
        expect(TableMaintenanceCommand.vacuum.isPostgreSql, isTrue);
        expect(TableMaintenanceCommand.vacuumFull.isPostgreSql, isTrue);
        expect(TableMaintenanceCommand.pgAnalyze.isPostgreSql, isTrue);
        expect(TableMaintenanceCommand.reindex.isPostgreSql, isTrue);
        expect(
          TableMaintenanceCommand.reindexConcurrently.isPostgreSql,
          isTrue,
        );
        expect(TableMaintenanceCommand.cluster.isPostgreSql, isTrue);
      });
    });
  });

  group('DatabaseType maintenance granular flags', () {
    test('MySQL 支持全部维护命令', () {
      expect(DatabaseType.mysql.supportsAnalyzeTable, isTrue);
      expect(DatabaseType.mysql.supportsOptimizeTable, isTrue);
      expect(DatabaseType.mysql.supportsCheckTable, isTrue);
    });

    test('Doris 仅支持 ANALYZE TABLE', () {
      expect(DatabaseType.doris.supportsAnalyzeTable, isTrue);
      expect(DatabaseType.doris.supportsOptimizeTable, isFalse);
      expect(DatabaseType.doris.supportsCheckTable, isFalse);
    });

    test('PostgreSQL 支持全部维护命令', () {
      expect(DatabaseType.postgresql.supportsAnalyzeTable, isTrue);
      expect(DatabaseType.postgresql.supportsOptimizeTable, isTrue);
      expect(DatabaseType.postgresql.supportsCheckTable, isTrue);
    });

    test('SQLite 不支持任何维护命令', () {
      expect(DatabaseType.sqlite.supportsAnalyzeTable, isFalse);
      expect(DatabaseType.sqlite.supportsOptimizeTable, isFalse);
      expect(DatabaseType.sqlite.supportsCheckTable, isFalse);
    });

    test('SQL Server 不支持任何维护命令', () {
      expect(DatabaseType.sqlserver.supportsAnalyzeTable, isFalse);
      expect(DatabaseType.sqlserver.supportsOptimizeTable, isFalse);
      expect(DatabaseType.sqlserver.supportsCheckTable, isFalse);
    });
  });
}
