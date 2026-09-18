import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('DatabaseType', () {
    // T22-T25 · MySQL 协议族薄适配四成员的表驱动元数据（与 MySQL 同面）。
    group('mysql-family thin members (ob/tidb/starrocks/mariadb)', () {
      const members = [
        (DatabaseType.oceanbase, 'OceanBase', 2881),
        (DatabaseType.tidb, 'TiDB', 4000),
        (DatabaseType.starrocks, 'StarRocks', 9030),
        (DatabaseType.mariadb, 'MariaDB', 3306),
      ];
      for (final (type, label, port) in members) {
        test('$label metadata is MySQL-shaped', () {
          expect(type.displayName, label);
          expect(type.defaultPort, port);
          expect(type.isSQL, isTrue);
          expect(type.isSqlLike, isTrue);
          expect(type.isNoSQL, isFalse);
          expect(type.supportsViews, isTrue);
          expect(type.supportsTableStats, isTrue);
          expect(type.createTableMenuAction, 'create_table');
          expect(type.brandColor, isNotNull); // 品牌色已注册
        });
      }
    });

    group('supportsTableStats', () {
      test('MySQL supports table stats', () {
        expect(DatabaseType.mysql.supportsTableStats, isTrue);
      });

      test('Doris supports table stats', () {
        expect(DatabaseType.doris.supportsTableStats, isTrue);
      });

      test('PostgreSQL supports table stats', () {
        expect(DatabaseType.postgresql.supportsTableStats, isTrue);
      });

      test('SQLite supports table stats', () {
        expect(DatabaseType.sqlite.supportsTableStats, isTrue);
      });

      test('Redis does not support table stats', () {
        expect(DatabaseType.redis.supportsTableStats, isFalse);
      });

      test('MongoDB does not support table stats', () {
        expect(DatabaseType.mongodb.supportsTableStats, isFalse);
      });

      test('TDengine does not support table stats', () {
        expect(DatabaseType.tdengine.supportsTableStats, isFalse);
      });

      test('SQL Server does not support table stats', () {
        expect(DatabaseType.sqlserver.supportsTableStats, isFalse);
      });
    });

    group('PostgreSQL-specific capabilities', () {
      test('PostgreSQL supports schemas', () {
        expect(DatabaseType.postgresql.supportsSchemas, isTrue);
      });

      test('PostgreSQL supports triggers', () {
        expect(DatabaseType.postgresql.supportsTriggers, isTrue);
      });

      test('PostgreSQL supports materialized views', () {
        expect(DatabaseType.postgresql.supportsMaterializedViews, isTrue);
      });

      test('PostgreSQL supports sequences', () {
        expect(DatabaseType.postgresql.supportsSequences, isTrue);
      });

      test('MySQL does not support materialized views', () {
        expect(DatabaseType.mysql.supportsMaterializedViews, isFalse);
      });
    });

    group('DbSchema', () {
      test('can hold schema-centric objects', () {
        final schema = DbSchema(
          name: 'public',
          tables: [DbTable(name: 'users')],
          views: ['active_users'],
          materializedViews: ['mv_stats'],
          functions: ['fn_total'],
          procedures: ['sp_create'],
          sequences: ['users_id_seq'],
          triggers: [
            DbTrigger(
              name: 'trg',
              event: 'INSERT',
              table: 'users',
              timing: 'BEFORE',
            ),
          ],
        );
        expect(schema.name, equals('public'));
        expect(schema.tables.length, equals(1));
        expect(schema.views.length, equals(1));
        expect(schema.materializedViews.length, equals(1));
        expect(schema.functions.length, equals(1));
        expect(schema.procedures.length, equals(1));
        expect(schema.sequences.length, equals(1));
        expect(schema.triggers.length, equals(1));
      });

      test('copyWith returns a new instance with updated values', () {
        final schema = const DbSchema(name: 'public');
        final updated = schema.copyWith(tables: [DbTable(name: 'users')]);
        expect(updated.name, equals('public'));
        expect(updated.tables.length, equals(1));
        expect(schema.tables, isEmpty);
      });
    });

    group('Database', () {
      test('can hold schema list and new top-level fields', () {
        final db = Database(
          name: 'test_db',
          schemas: [
            DbSchema(
              name: 'public',
              tables: [DbTable(name: 'users')],
            ),
          ],
          functions: ['fn_total'],
          materializedViews: ['mv_stats'],
          sequences: ['users_id_seq'],
        );
        expect(db.schemas.length, equals(1));
        expect(db.functions.length, equals(1));
        expect(db.materializedViews.length, equals(1));
        expect(db.sequences.length, equals(1));
      });
    });
  });
}
