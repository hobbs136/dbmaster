import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/utils/sql_escape_utils.dart';

void main() {
  group('SqlServerAdapter', () {
    late SqlServerAdapter adapter;

    setUp(() {
      adapter = SqlServerAdapter();
    });

    group('Interface compliance', () {
      test('implements DatabaseAdapter', () {
        expect(adapter, isA<DatabaseAdapter>());
      });

      test('returns correct databaseType', () {
        expect(adapter.databaseType, DatabaseType.sqlserver);
      });

      test('isConnected returns false by default', () {
        expect(adapter.isConnected, false);
      });

      test('currentConnection is null by default', () {
        expect(adapter.currentConnection, isNull);
      });

      test('isInTransaction is false by default', () {
        expect(adapter.isInTransaction, false);
      });

      test('supportsSchemaOperations is true', () {
        expect(adapter.supportsSchemaOperations, true);
      });

      // T28 网关壳能力接口面：保留 SQL 能力族声明，事务能力降级（网关
      // 无状态单语句——UI 经 `is TransactionalAdapter` 门控自动隐藏）。
      test('is NOT TransactionalAdapter (gateway v1: stateless per-statement)',
          () {
        expect(adapter, isNot(isA<TransactionalAdapter>()));
      });

      test('keeps process/replication/json/schema capability interfaces', () {
        expect(adapter, isA<ProcessListAdapter>());
        expect(adapter, isA<ReplicationAdapter>());
        expect(adapter, isA<JsonAdapter>());
        expect(adapter, isA<SchemaAwareAdapter>());
        expect(adapter, isA<MultiSchemaObjectAdapter>());
        expect(adapter, isA<CharsetAdapter>());
        expect(adapter, isA<SqlScriptAdapter>());
        expect(adapter, isA<DdlAdapter>());
        expect(adapter, isA<SqlSchemaAdapter>());
      });
    });

    group('Connection', () {
      test(
        'testConnection returns error string when no server session',
        () async {
          final connection = DatabaseConnection(
            id: 'test',
            name: 'test',
            type: DatabaseType.sqlserver,
            host: 'invalid-host',
            port: 1433,
            username: 'sa',
            password: 'wrong',
          );
          final result = await adapter.testConnection(connection);
          // 网关模式硬依赖 dbmaster server 会话——缺失时返回引导性错误串。
          expect(result, isNotNull);
          expect(result, isNotEmpty);
        },
      );

      test('executeQuery throws when not connected', () async {
        expect(
          () => adapter.executeQuery('SELECT 1'),
          throwsA(isA<Exception>()),
        );
      });

      test('getTables throw when not connected', () async {
        expect(() => adapter.getTables(), throwsA(isA<Exception>()));
      });

      test('getDatabases throws when not connected', () async {
        expect(() => adapter.getDatabases(), throwsA(isA<Exception>()));
      });

      test('beginTransaction fails loud (gateway: unsupported, T28 boundary)',
          () {
        expect(
          adapter.beginTransaction,
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('commit fails loud (gateway: unsupported)', () {
        expect(adapter.commit, throwsA(isA<UnsupportedError>()));
      });

      test('rollback fails loud (gateway: unsupported)', () {
        expect(adapter.rollback, throwsA(isA<UnsupportedError>()));
      });
    });
  });

  group('DatabaseType.sqlserver', () {
    test('displayName is SQL Server', () {
      expect(DatabaseType.sqlserver.displayName, 'SQL Server');
    });

    test('defaultPort is 1433', () {
      expect(DatabaseType.sqlserver.defaultPort, 1433);
    });

    test('isSQL returns true', () {
      expect(DatabaseType.sqlserver.isSQL, true);
    });

    test('isNoSQL returns false', () {
      expect(DatabaseType.sqlserver.isNoSQL, false);
    });

    test('supportsProcedures returns true', () {
      expect(DatabaseType.sqlserver.supportsProcedures, true);
    });

    test('supportsFunctions returns true', () {
      expect(DatabaseType.sqlserver.supportsFunctions, true);
    });

    test('supportsTriggers returns true', () {
      expect(DatabaseType.sqlserver.supportsTriggers, true);
    });

    test('supportsViews returns true', () {
      expect(DatabaseType.sqlserver.supportsViews, true);
    });

    test('supportsColumnEdit returns true', () {
      expect(DatabaseType.sqlserver.supportsColumnEdit, true);
    });

    test('supportsIndexEdit returns true', () {
      expect(DatabaseType.sqlserver.supportsIndexEdit, true);
    });

    test('supportsRenameTable returns true', () {
      expect(DatabaseType.sqlserver.supportsRenameTable, true);
    });

    test('supportsEvents returns false (SQL Server Agent is different)', () {
      expect(DatabaseType.sqlserver.supportsEvents, false);
    });

    test('supportsProgrammableObjects returns true', () {
      expect(DatabaseType.sqlserver.supportsProgrammableObjects, true);
    });

    test('isSchemaLess returns false', () {
      expect(DatabaseType.sqlserver.isSchemaLess, false);
    });

    test('typeIcon is assigned', () {
      expect(DatabaseType.sqlserver.typeIcon, isNotNull);
    });

    test('typeIcon 与 brandColor 已定义（emoji 已下线）', () {
      expect(DatabaseType.sqlserver.typeIcon, isNotNull);
      expect(DatabaseType.sqlserver.brandColor, isNotNull);
    });

    test('entityPanelTableLabel is Tables', () {
      expect(DatabaseType.sqlserver.entityPanelTableLabel, 'Tables');
    });

    test('fromName parses sqlserver correctly', () {
      expect(DatabaseType.fromName('sqlserver'), DatabaseType.sqlserver);
    });
  });

  group('SqlEscapeUtils', () {
    group('escapeSqlServerIdentifier', () {
      test('wraps simple name in brackets', () {
        expect(SqlEscapeUtils.escapeSqlServerIdentifier('users'), '[users]');
      });

      test('escapes bracket inside name', () {
        expect(SqlEscapeUtils.escapeSqlServerIdentifier('a]b'), '[a]]b]');
      });

      test('escapes multiple brackets', () {
        expect(SqlEscapeUtils.escapeSqlServerIdentifier('a]]b'), '[a]]]]b]');
      });

      test('handles empty string', () {
        expect(SqlEscapeUtils.escapeSqlServerIdentifier(''), '[]');
      });

      test('handles schema-qualified name', () {
        expect(
          SqlEscapeUtils.escapeSqlServerIdentifier('dbo.users'),
          '[dbo.users]',
        );
      });
    });

    group('unescapeSqlServerIdentifier', () {
      test('unwraps simple bracket name', () {
        expect(SqlEscapeUtils.unescapeSqlServerIdentifier('[users]'), 'users');
      });

      test('restores escaped bracket', () {
        expect(SqlEscapeUtils.unescapeSqlServerIdentifier('[a]]b]'), 'a]b');
      });

      test('handles name without brackets', () {
        expect(SqlEscapeUtils.unescapeSqlServerIdentifier('users'), 'users');
      });

      test('handles schema-qualified bracket name', () {
        expect(
          SqlEscapeUtils.unescapeSqlServerIdentifier('[dbo.users]'),
          'dbo.users',
        );
      });
    });
  });

  group('getFunctions SQL', () {
    test('should include all function types', () {
      expect(SqlServerAdapter.functionsSql, contains("'FN'"));
      expect(SqlServerAdapter.functionsSql, contains("'IF'"));
      expect(SqlServerAdapter.functionsSql, contains("'TF'"));
      expect(SqlServerAdapter.functionsSql, contains("'AF'"));
      expect(SqlServerAdapter.functionsSql, contains("'FS'"));
      expect(SqlServerAdapter.functionsSql, contains("'FT'"));
    });
  });

  group('formatColumnType', () {
    test('should show (max) for -1 length', () {
      expect(SqlServerAdapter.formatColumnType('varchar', -1), 'varchar(max)');
      expect(
        SqlServerAdapter.formatColumnType('nvarchar', -1),
        'nvarchar(max)',
      );
      expect(
        SqlServerAdapter.formatColumnType('varbinary', -1),
        'varbinary(max)',
      );
    });

    test('should show length for positive values', () {
      expect(SqlServerAdapter.formatColumnType('varchar', 255), 'varchar(255)');
      expect(
        SqlServerAdapter.formatColumnType('nvarchar', 100),
        'nvarchar(100)',
      );
    });

    test('should return dataType only for null length', () {
      expect(SqlServerAdapter.formatColumnType('int', null), 'int');
      expect(SqlServerAdapter.formatColumnType('datetime', null), 'datetime');
    });

    test('should handle string -1', () {
      expect(
        SqlServerAdapter.formatColumnType('varchar', '-1'),
        'varchar(max)',
      );
    });
  });

  group('buildCreateTableExportSql', () {
    test('should not inline INDEX in CREATE TABLE', () {
      final adapter = SqlServerAdapter();
      final sql = adapter.buildCreateTableExportSql(
        'dbo',
        'users',
        [
          DbColumn(
            name: 'id',
            type: 'INT',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
        ],
        [
          DbIndex(name: 'idx_email', columns: ['email'], isUnique: false),
        ],
        [],
      );
      expect(sql, contains('CREATE TABLE [dbo].[users]'));
      // INDEX should appear only after CREATE TABLE closing );
      final createTableEnd = sql.indexOf(');');
      final indexPos = sql.indexOf('INDEX [idx_email]');
      expect(indexPos, greaterThan(createTableEnd));
      expect(
        sql,
        contains('CREATE INDEX [idx_email] ON [dbo].[users] ([email]);'),
      );
    });

    test('should create UNIQUE INDEX separately', () {
      final adapter = SqlServerAdapter();
      final sql = adapter.buildCreateTableExportSql(
        'dbo',
        'users',
        [
          DbColumn(
            name: 'id',
            type: 'INT',
            isPrimaryKey: true,
            isNullable: false,
          ),
        ],
        [
          DbIndex(name: 'idx_id', columns: ['id'], isUnique: true),
        ],
        [],
      );
      expect(
        sql,
        contains('CREATE UNIQUE INDEX [idx_id] ON [dbo].[users] ([id]);'),
      );
    });
  });

  group('DatabaseType enum - all values present', () {
    // T22-T25 起 13 值：+oceanbase/tidb/starrocks/mariadb（MySQL 族薄适配）。
    test('has 13 values including sqlserver', () {
      expect(DatabaseType.values.length, 13);
    });

    test('values contain sqlserver', () {
      expect(DatabaseType.values, contains(DatabaseType.sqlserver));
    });
  });
}
