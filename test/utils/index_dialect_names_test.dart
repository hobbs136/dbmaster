// T063 — deterministic unit tests for the dialect-aware index-arg
// composition shared by the sidebar tree handler and EditIndexDialog.
// Run: flutter test test/utils/index_dialect_names_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/utils/index_dialect_names.dart';

void main() {
  group('IndexDialectNames.dropArgs', () {
    test('PostgreSQL qualifies the index name (DROP INDEX has no ON clause)', () {
      final r = IndexDialectNames.dropArgs(
        DatabaseType.postgresql,
        'app',
        'users',
        'idx_email',
      );
      expect(r.table, 'users'); // PG adapter ignores table for DROP INDEX
      expect(r.index, 'app.idx_email');
    });

    test('SQL Server qualifies the table name (ON clause needs it)', () {
      final r = IndexDialectNames.dropArgs(
        DatabaseType.sqlserver,
        'sales',
        'orders',
        'ix_orders',
      );
      expect(r.table, 'sales.orders');
      expect(r.index, 'ix_orders'); // index name stays bare
    });

    test('MySQL / SQLite / others stay bare (no schema concept)', () {
      for (final type in [
        DatabaseType.mysql,
        DatabaseType.sqlite,
        DatabaseType.doris,
      ]) {
        final r = IndexDialectNames.dropArgs(type, 'ignored', 'users', 'idx');
        expect(r.table, 'users', reason: '$type: table must stay bare');
        expect(r.index, 'idx', reason: '$type: index must stay bare');
      }
    });

    test('empty schema → bare names even on PG/SQL Server', () {
      expect(
        IndexDialectNames.dropArgs(DatabaseType.postgresql, '', 'users', 'idx').index,
        'idx',
      );
      expect(
        IndexDialectNames.dropArgs(DatabaseType.sqlserver, '', 'users', 'idx').table,
        'users',
      );
    });
  });

  group('IndexDialectNames.createTableArg', () {
    test('PostgreSQL + SQL Server qualify the table; index name is left bare by caller', () {
      expect(
        IndexDialectNames.createTableArg(DatabaseType.postgresql, 'app', 'users'),
        'app.users',
      );
      expect(
        IndexDialectNames.createTableArg(DatabaseType.sqlserver, 'sales', 'orders'),
        'sales.orders',
      );
    });

    test('MySQL stays bare', () {
      expect(
        IndexDialectNames.createTableArg(DatabaseType.mysql, 'ignored', 'users'),
        'users',
      );
    });

    test('empty schema → bare table', () {
      expect(
        IndexDialectNames.createTableArg(DatabaseType.postgresql, '', 'users'),
        'users',
      );
    });
  });
}
