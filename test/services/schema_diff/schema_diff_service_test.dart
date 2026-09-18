import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/schema_diff/schema_diff_service.dart';

/// Minimal fake adapter for SchemaDiffService unit tests.
/// Tracks which database was last used via [useDatabase] calls.
class _FakeAdapter extends DatabaseAdapter {
  final DatabaseType _dbType;
  DatabaseConnection? _currentConnection;
  final List<String> _useDatabaseCalls = [];
  final Map<String, List<DbColumn>> _columns;
  final Map<String, List<DbIndex>> _indexes;
  final List<String> _views;
  final List<String> _procedures;
  final List<String> _functions;
  final QueryResult? Function(String sql)? _queryHandler;
  final Exception? _columnsException;

  @override
  bool get isSwitchingDatabase => false;

  _FakeAdapter({
    DatabaseType dbType = DatabaseType.mysql,
    DatabaseConnection? connection,
    Map<String, List<DbColumn>>? columns,
    Map<String, List<DbIndex>>? indexes,
    List<String>? views,
    List<String>? procedures,
    List<String>? functions,
    QueryResult? Function(String sql)? queryHandler,
    Exception? columnsException,
  }) : _dbType = dbType,
       _currentConnection = connection,
       _columns = columns ?? {},
       _indexes = indexes ?? {},
       _views = views ?? [],
       _procedures = procedures ?? [],
       _functions = functions ?? [],
       _queryHandler = queryHandler,
       _columnsException = columnsException;

  List<String> get useDatabaseCalls => List.unmodifiable(_useDatabaseCalls);

  @override
  DatabaseType get databaseType => _dbType;

  @override
  DatabaseConnection? get currentConnection => _currentConnection;

  @override
  bool get isConnected => true;

  @override
  void Function()? get onDisconnect => null;

  @override
  set onDisconnect(void Function()? cb) {}

  @override
  Future<void> useDatabase(String dbName) async {
    _useDatabaseCalls.add(dbName);
    if (_currentConnection != null) {
      _currentConnection = _currentConnection!.copyWith(database: dbName);
    }
  }

  @override
  Future<List<String>> getTables() async => _columns.keys.toList();

  @override
  Future<List<String>> getViews() async => List.unmodifiable(_views);

  @override
  Future<List<String>> getProcedures() async => List.unmodifiable(_procedures);

  @override
  Future<List<String>> getFunctions() async => List.unmodifiable(_functions);

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    final exception = _columnsException;
    if (exception != null) throw exception;
    return _columns[tableName] ?? [];
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async {
    return _indexes[tableName] ?? [];
  }

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    final handler = _queryHandler;
    if (handler != null) {
      final result = handler(sql);
      if (result != null) return result;
    }
    return QueryResult.empty();
  }

  // --------------------------------------------------------------------------
  // Unimplemented stubs (not used by SchemaDiffService in these tests)
  // --------------------------------------------------------------------------
  @override
  Future<bool> connect(DatabaseConnection connection) =>
      throw UnimplementedError();

  @override
  Future<void> disconnect() => throw UnimplementedError();

  @override
  Future<String?> testConnection(DatabaseConnection connection) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getDatabases() => throw UnimplementedError();

  @override
  Future<List<String>> getEvents() => throw UnimplementedError();

  @override
  Future<List<DbTrigger>> getTriggers() => throw UnimplementedError();

  @override
  bool get supportsSchemaNamespace => false;

  @override
  Future<List<String>> getSchemas({String? database}) =>
      throw UnimplementedError();

  @override
  Future<void> setSchema(String schemaName) => throw UnimplementedError();

  @override
  Future<List<String>> getMaterializedViews() => throw UnimplementedError();

  @override
  Future<List<String>> getSequences() => throw UnimplementedError();

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) =>
      throw UnimplementedError();

  @override
  Future<DbTable> getTableDetails(String tableName) =>
      throw UnimplementedError();

  @override
  Future<QueryResult> getExplainPlan(String sql) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getServerVersion() =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) =>
      throw UnimplementedError();

  @override
  Future<bool> createDatabase(String dbName, {Map<String, dynamic>? options}) =>
      throw UnimplementedError();

  @override
  Future<bool> dropDatabase(String dbName) => throw UnimplementedError();

  @override
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    Map<String, dynamic>? options,
  }) => throw UnimplementedError();

  @override
  Future<bool> dropTable(String tableName) => throw UnimplementedError();

  @override
  Future<bool> renameTable(String oldName, String newName) =>
      throw UnimplementedError();

  @override
  Future<bool> truncateTable(String tableName, {TruncateOptions? options}) =>
      throw UnimplementedError();

  @override
  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  }) => throw UnimplementedError();

  @override
  Future<int> getTableRowCount(String tableName) => throw UnimplementedError();

  @override
  Future<bool> addColumn(String tableName, DbColumn column) =>
      throw UnimplementedError();

  @override
  Future<bool> dropColumn(String tableName, String columnName) =>
      throw UnimplementedError();

  @override
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) => throw UnimplementedError();

  @override
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) => throw UnimplementedError();

  @override
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  }) => throw UnimplementedError();

  @override
  Future<bool> dropIndex(String tableName, String indexName) =>
      throw UnimplementedError();

  @override
  Future<String> exportDatabaseStructure(String dbName) =>
      throw UnimplementedError();

  @override
  Future<bool> executeSqlScript(String script) => throw UnimplementedError();

  @override
  Future<List<String>> getCharsets() => throw UnimplementedError();

  @override
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, String>>> getCollations({String? charset}) =>
      throw UnimplementedError();

  @override
  Future<List<DbTableMetadata>> getTablesWithMetadata({
    String? database,
  }) async {
    final names = await getTables();
    return names.map((name) => DbTableMetadata(name: name)).toList();
  }

  @override
  Future<DbTableMetadata> getTableMetadata(String tableName) async {
    return DbTableMetadata(name: tableName);
  }

  @override
  Future<String> getAiSchemaSummary({
    String? target,
    String? databaseName,
    String locale = 'en',
  }) =>
      throw UnimplementedError();

  @override
  Future<AiExecutionResult> executeAiCommand(
    String command, {
    String locale = 'en',
  }) =>
      throw UnimplementedError();

  @override
  SecurityCheckResult validateCommand(String command) =>
      throw UnimplementedError();

  @override
  Future<void> beginTransaction() => throw UnimplementedError();

  @override
  Future<void> commit() => throw UnimplementedError();

  @override
  Future<void> rollback() => throw UnimplementedError();

  @override
  bool get isInTransaction => false;

  @override
  bool get supportsSchemaOperations => true;

  @override
  Future<List<PgExtension>> getExtensions() async => [];

  @override
  Future<List<String>> getJsonColumns(String tableName) async => [];

  @override
  Future<ReplicationStatus?> getReplicationStatus() async => null;

  @override
  Future<List<VectorIndex>> getVectorIndexes() async => [];

  @override
  Future<bool> isJsonColumn(String tableName, String columnName) async => false;

  @override
  Future<bool> killProcess(int processId) async => false;
}

/// Minimal fake DatabaseService that returns a pre-configured adapter.
class _FakeDatabaseService extends DatabaseService {
  final Map<String, DatabaseAdapter> _adapters;
  final Map<String, String> _createTableSql;

  _FakeDatabaseService(this._adapters, {Map<String, String>? createTableSql})
    : _createTableSql = createTableSql ?? {};

  @override
  DatabaseAdapter? getAdapter(String connectionId) => _adapters[connectionId];

  @override
  Future<String> getCreateTableSql(
    String tableName, {
    String? connectionId,
    String? databaseName,
  }) async {
    return _createTableSql[tableName] ?? '';
  }
}

void main() {
  group('SchemaDiffService.captureSnapshot', () {
    test('同服务器跨数据库比较时应先切换源库再切换目标库', () async {
      // 模拟一个 MySQL 连接，包含两个数据库的 schema
      final connection = DatabaseConnection(
        id: 'conn1',
        name: 'Local MySQL',
        type: DatabaseType.mysql,
        host: '192.0.2.128',
        port: 3306,
        username: 'root',
        database: 'ecommerce',
      );

      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        connection: connection,
        columns: {
          'products': [
            DbColumn(
              name: 'id',
              type: 'INT',
              isPrimaryKey: true,
              isNullable: false,
            ),
            DbColumn(name: 'name', type: 'VARCHAR(255)', isNullable: false),
          ],
          'orders': [
            DbColumn(
              name: 'id',
              type: 'INT',
              isPrimaryKey: true,
              isNullable: false,
            ),
            DbColumn(name: 'product_id', type: 'INT', isNullable: false),
          ],
        },
        indexes: {
          'products': [
            DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
          ],
          'orders': [
            DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            DbIndex(
              name: 'idx_product_id',
              columns: ['product_id'],
              isUnique: false,
            ),
          ],
        },
      );

      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      // Capture source snapshot (ecommerce)
      final sourceSnapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local MySQL',
        databaseName: 'ecommerce',
      );

      expect(sourceSnapshot.databaseName, 'ecommerce');
      expect(sourceSnapshot.tables.length, 2);
      expect(sourceSnapshot.tables.map((t) => t.name).toSet(), {
        'products',
        'orders',
      });

      // Capture target snapshot (test_db) — 同一个 adapter，模拟 test_db 结构略有不同
      adapter._columns['products']!.add(
        DbColumn(name: 'price', type: 'DECIMAL(10,2)', isNullable: true),
      );

      final targetSnapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local MySQL',
        databaseName: 'test_db',
      );

      expect(targetSnapshot.databaseName, 'test_db');
      expect(targetSnapshot.tables.length, 2);

      // 关键断言：useDatabase 应按顺序被调用
      expect(adapter.useDatabaseCalls, ['ecommerce', 'test_db']);
      expect(adapter.currentConnection?.database, 'test_db');
    });

    test('应正确生成 diff 报告（源库有 price 列，目标库没有）', () async {
      final sourceSnapshot = SchemaSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local MySQL',
        databaseName: 'ecommerce',
        capturedAt: DateTime.now(),
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
              DbColumn(name: 'name', type: 'VARCHAR(255)', isNullable: false),
              DbColumn(name: 'price', type: 'DECIMAL(10,2)', isNullable: true),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        createStatements: {
          'products':
              'CREATE TABLE `products` (\n  `id` INT PRIMARY KEY,\n  `name` VARCHAR(255),\n  `price` DECIMAL(10,2)\n)',
        },
      );

      final targetSnapshot = SchemaSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local MySQL',
        databaseName: 'test_db',
        capturedAt: DateTime.now(),
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
              DbColumn(name: 'name', type: 'VARCHAR(255)', isNullable: false),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        createStatements: {
          'products':
              'CREATE TABLE `products` (\n  `id` INT PRIMARY KEY,\n  `name` VARCHAR(255)\n)',
        },
      );

      final dbService = _FakeDatabaseService({});
      final diffService = SchemaDiffService(dbService);

      final report = diffService.compareSnapshots(
        source: sourceSnapshot,
        target: targetSnapshot,
      );

      expect(report.tableDiffs.length, 1);
      expect(report.tableDiffs.first.name, 'products');
      expect(report.tableDiffs.first.type, DiffType.modified);
      expect(
        report.tableDiffs.first.columnDiffs.any(
          (c) => c.name == 'price' && c.type == DiffType.added,
        ),
        isTrue,
      );
    });

    test('应正确识别新增的表', () async {
      final sourceSnapshot = SchemaSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local MySQL',
        databaseName: 'ecommerce',
        capturedAt: DateTime.now(),
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
          DbTable(
            name: 'categories',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        createStatements: {
          'products': 'CREATE TABLE `products` (id INT PRIMARY KEY)',
          'categories': 'CREATE TABLE `categories` (id INT PRIMARY KEY)',
        },
      );

      final targetSnapshot = SchemaSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local MySQL',
        databaseName: 'test_db',
        capturedAt: DateTime.now(),
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        createStatements: {
          'products': 'CREATE TABLE `products` (id INT PRIMARY KEY)',
        },
      );

      final dbService = _FakeDatabaseService({});
      final diffService = SchemaDiffService(dbService);

      final report = diffService.compareSnapshots(
        source: sourceSnapshot,
        target: targetSnapshot,
      );

      final addedTable = report.tableDiffs.firstWhere(
        (t) => t.type == DiffType.added,
      );
      expect(addedTable.name, 'categories');
      expect(addedTable.sourceCreateSql, contains('categories'));
    });

    test('应正确识别删除的表', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        createStatements: {
          'products': 'CREATE TABLE `products` (id INT PRIMARY KEY)',
        },
      );

      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
          DbTable(
            name: 'categories',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        createStatements: {
          'products': 'CREATE TABLE `products` (id INT PRIMARY KEY)',
          'categories': 'CREATE TABLE `categories` (id INT PRIMARY KEY)',
        },
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      final removedTable = report.tableDiffs.firstWhere(
        (t) => t.type == DiffType.removed,
      );
      expect(removedTable.name, 'categories');
      expect(removedTable.targetCreateSql, contains('categories'));
    });

    test('两库完全相同时应报告无变化', () {
      final tables = [
        DbTable(
          name: 'products',
          columns: [
            DbColumn(
              name: 'id',
              type: 'INT',
              isPrimaryKey: true,
              isNullable: false,
            ),
          ],
          indexes: [
            DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
          ],
        ),
      ];
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: tables,
        createStatements: {
          'products': 'CREATE TABLE `products` (id INT PRIMARY KEY)',
        },
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: tables,
        createStatements: {
          'products': 'CREATE TABLE `products` (id INT PRIMARY KEY)',
        },
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      expect(report.hasChanges, isFalse);
      expect(report.tableDiffs.first.type, DiffType.unchanged);
      expect(report.totalTableChanges, 0);
      expect(report.totalColumnChanges, 0);
      expect(report.totalIndexChanges, 0);
    });

    test('应正确识别列类型变更', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [],
          ),
        ],
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'BIGINT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [],
          ),
        ],
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      final columnDiff = report.tableDiffs.first.columnDiffs.first;
      expect(columnDiff.type, DiffType.modified);
      expect(columnDiff.sourceColumn!.type, 'INT');
      expect(columnDiff.targetColumn!.type, 'BIGINT');
      expect(report.totalColumnChanges, 1);
    });

    test('应正确识别 nullable / defaultValue / primaryKey 变更', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
              DbColumn(
                name: 'name',
                type: 'VARCHAR(255)',
                isNullable: false,
                defaultValue: 'x',
              ),
            ],
            indexes: [],
          ),
        ],
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: false,
                isNullable: false,
              ),
              DbColumn(
                name: 'name',
                type: 'VARCHAR(255)',
                isNullable: true,
                defaultValue: 'y',
              ),
            ],
            indexes: [],
          ),
        ],
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      final modifiedColumns = report.tableDiffs.first.columnDiffs
          .where((c) => c.type == DiffType.modified)
          .map((c) => c.name)
          .toSet();
      expect(modifiedColumns, {'id', 'name'});
      expect(report.totalColumnChanges, 2);
    });

    test('应正确识别删除的列', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [],
          ),
        ],
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
              DbColumn(name: 'price', type: 'DECIMAL(10,2)', isNullable: true),
            ],
            indexes: [],
          ),
        ],
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      final removedColumn = report.tableDiffs.first.columnDiffs.firstWhere(
        (c) => c.name == 'price' && c.type == DiffType.removed,
      );
      expect(removedColumn.targetColumn!.type, 'DECIMAL(10,2)');
    });

    test('应正确识别索引的新增、删除与修改', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
              DbIndex(name: 'idx_name', columns: ['name'], isUnique: false),
            ],
          ),
        ],
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
              DbIndex(
                name: 'idx_name',
                columns: ['name', 'desc'],
                isUnique: false,
              ),
              DbIndex(name: 'idx_price', columns: ['price'], isUnique: true),
            ],
          ),
        ],
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      final indexDiffs = report.tableDiffs.first.indexDiffs;
      expect(
        indexDiffs.any(
          (i) => i.name == 'idx_name' && i.type == DiffType.modified,
        ),
        isTrue,
      );
      expect(
        indexDiffs.any(
          (i) => i.name == 'idx_price' && i.type == DiffType.removed,
        ),
        isTrue,
      );
      expect(report.totalIndexChanges, 2);
    });

    test('应正确识别视图的新增与删除', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [],
        views: ['active_products'],
        viewCreateStatements: {
          'active_products':
              'CREATE VIEW active_products AS SELECT * FROM products',
        },
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [],
        views: ['inactive_products'],
        viewCreateStatements: {
          'inactive_products':
              'CREATE VIEW inactive_products AS SELECT * FROM products',
        },
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      expect(
        report.viewDiffs.any(
          (v) => v.name == 'active_products' && v.type == DiffType.added,
        ),
        isTrue,
      );
      expect(
        report.viewDiffs.any(
          (v) => v.name == 'inactive_products' && v.type == DiffType.removed,
        ),
        isTrue,
      );
    });

    test('应正确识别存储过程的新增与删除', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [],
        procedures: ['sync_inventory'],
        procedureCreateStatements: {
          'sync_inventory': 'CREATE PROCEDURE sync_inventory() BEGIN END',
        },
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [],
        procedures: ['cleanup_logs'],
        procedureCreateStatements: {
          'cleanup_logs': 'CREATE PROCEDURE cleanup_logs() BEGIN END',
        },
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      expect(
        report.procedureDiffs.any(
          (p) => p.name == 'sync_inventory' && p.type == DiffType.added,
        ),
        isTrue,
      );
      expect(
        report.procedureDiffs.any(
          (p) => p.name == 'cleanup_logs' && p.type == DiffType.removed,
        ),
        isTrue,
      );
    });

    test('应合并源和目标的 captureErrors', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [],
        captureErrors: ['source error'],
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [],
        captureErrors: ['target error'],
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      expect(report.captureErrors, contains('source error'));
      expect(report.captureErrors, contains('target error'));
    });

    test('report 的计数属性应计算正确', () {
      final sourceSnapshot = _buildSnapshot(
        databaseName: 'ecommerce',
        tables: [
          DbTable(
            name: 'a',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
              DbColumn(name: 'new_col', type: 'INT', isNullable: true),
            ],
            indexes: [],
          ),
        ],
      );
      final targetSnapshot = _buildSnapshot(
        databaseName: 'test_db',
        tables: [
          DbTable(
            name: 'a',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [],
          ),
          DbTable(
            name: 'b',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
            ],
            indexes: [],
          ),
        ],
      );

      final report = SchemaDiffService(
        _FakeDatabaseService({}),
      ).compareSnapshots(source: sourceSnapshot, target: targetSnapshot);

      expect(report.addedTables, 0);
      expect(report.removedTables, 1);
      expect(report.modifiedTables, 1);
      expect(report.totalColumnChanges, 1);
    });
  });

  group('SchemaDiffService.captureSnapshot', () {
    test('connectionId 不存在时应抛出异常', () async {
      final dbService = _FakeDatabaseService({});
      final diffService = SchemaDiffService(dbService);

      expect(
        () => diffService.captureSnapshot(
          connectionId: 'missing',
          connectionName: 'Missing',
          databaseName: 'db',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('missing'),
          ),
        ),
      );
    });

    test('表元数据获取失败时应记录 captureErrors 且不影响其他表', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        columnsException: Exception('connection lost'),
        columns: {
          'products': [
            DbColumn(
              name: 'id',
              type: 'INT',
              isPrimaryKey: true,
              isNullable: false,
            ),
          ],
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(snapshot.tables, isEmpty);
      expect(snapshot.captureErrors, isNotEmpty);
      expect(snapshot.captureErrors.first, contains('connection lost'));
    });

    test('应使用 queryHandler 捕获 MySQL 视图 CREATE 语句', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        views: ['v1'],
        queryHandler: (sql) {
          if (sql.contains("SHOW CREATE VIEW `v1`")) {
            return QueryResult(
              columns: ['Create View'],
              rows: [
                {'Create View': 'CREATE VIEW `v1` AS SELECT id FROM products'},
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(snapshot.views, ['v1']);
      expect(snapshot.viewCreateStatements['v1'], contains('CREATE VIEW'));
    });

    test('MySQL 视图 SQL 应被移除 DEFINER 子句', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        views: ['v1'],
        queryHandler: (sql) {
          if (sql.contains('SHOW CREATE VIEW')) {
            return QueryResult(
              columns: ['Create View'],
              rows: [
                {
                  'Create View':
                      'CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v1` AS SELECT 1',
                },
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      final sql = snapshot.viewCreateStatements['v1'];
      expect(sql, isNotNull);
      expect(sql, isNot(contains('DEFINER=`')));
      expect(sql, contains('CREATE'));
      expect(sql, contains('SQL SECURITY DEFINER'));
    });

    test('应使用 queryHandler 捕获 PostgreSQL 视图 CREATE 语句', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.postgresql,
        views: ['v1'],
        queryHandler: (sql) {
          if (sql.contains('pg_get_viewdef')) {
            return QueryResult(
              columns: ['definition'],
              rows: [
                {'definition': 'SELECT id FROM products'},
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(
        snapshot.viewCreateStatements['v1'],
        contains('CREATE OR REPLACE VIEW'),
      );
      expect(snapshot.viewCreateStatements['v1'], contains('"v1"'));
    });

    test('应使用 queryHandler 捕获 SQLite 视图 CREATE 语句', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.sqlite,
        views: ['v1'],
        queryHandler: (sql) {
          if (sql.contains('sqlite_master')) {
            return QueryResult(
              columns: ['sql'],
              rows: [
                {'sql': 'CREATE VIEW v1 AS SELECT id FROM products'},
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(snapshot.viewCreateStatements['v1'], contains('CREATE VIEW v1'));
    });

    test('应使用 queryHandler 捕获 SQL Server 视图 CREATE 语句', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.sqlserver,
        views: ['v1'],
        queryHandler: (sql) {
          if (sql.contains('OBJECT_DEFINITION')) {
            return QueryResult(
              columns: ['definition'],
              rows: [
                {'definition': 'CREATE VIEW v1 AS SELECT id FROM products'},
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(snapshot.viewCreateStatements['v1'], contains('CREATE VIEW v1'));
    });

    test('视图获取失败时应记录 captureErrors', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        views: ['v1'],
        queryHandler: (sql) {
          if (sql.contains('SHOW CREATE VIEW')) {
            throw Exception('view denied');
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(snapshot.captureErrors, anyElement(contains('view denied')));
    });

    test('应捕获 MySQL 存储过程 CREATE 语句', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        procedures: ['proc1'],
        queryHandler: (sql) {
          if (sql.contains('SHOW CREATE PROCEDURE')) {
            return QueryResult(
              columns: ['Create Procedure'],
              rows: [
                {'Create Procedure': 'CREATE PROCEDURE proc1() BEGIN END'},
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(
        snapshot.procedureCreateStatements['proc1'],
        contains('CREATE PROCEDURE'),
      );
    });

    test('MySQL 函数应回退到 SHOW CREATE FUNCTION', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        functions: ['func1'],
        queryHandler: (sql) {
          if (sql.contains('SHOW CREATE PROCEDURE')) {
            return QueryResult(columns: ['Create Procedure'], rows: []);
          }
          if (sql.contains('SHOW CREATE FUNCTION')) {
            return QueryResult(
              columns: ['Create Function'],
              rows: [
                {
                  'Create Function':
                      'CREATE FUNCTION func1() RETURNS INT RETURN 1',
                },
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(
        snapshot.procedureCreateStatements['func1'],
        contains('CREATE FUNCTION'),
      );
    });

    test('应捕获 PostgreSQL 函数 CREATE 语句', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.postgresql,
        functions: ['func1'],
        queryHandler: (sql) {
          if (sql.contains('pg_get_functiondef')) {
            return QueryResult(
              columns: ['definition'],
              rows: [
                {
                  'definition':
                      'CREATE OR REPLACE FUNCTION func1() RETURNS integer AS \$\$ BEGIN RETURN 1; END; \$\$ LANGUAGE plpgsql;',
                },
              ],
            );
          }
          return null;
        },
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(
        snapshot.procedureCreateStatements['func1'],
        contains('CREATE OR REPLACE FUNCTION'),
      );
    });

    test('SQLite 不应尝试获取存储过程', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.sqlite,
        procedures: ['proc1'],
      );
      final dbService = _FakeDatabaseService({'conn1': adapter});
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(snapshot.procedureCreateStatements, isEmpty);
    });

    test('getCreateTableSql 失败时不应中断快照', () async {
      final adapter = _FakeAdapter(
        dbType: DatabaseType.mysql,
        columns: {
          'products': [
            DbColumn(
              name: 'id',
              type: 'INT',
              isPrimaryKey: true,
              isNullable: false,
            ),
          ],
        },
        indexes: {
          'products': [
            DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
          ],
        },
      );
      final dbService = _FakeDatabaseService({
        'conn1': adapter,
      }, createTableSql: {});
      // 当 createTableSql map 没有 products 时返回空字符串，模拟失败
      final diffService = SchemaDiffService(dbService);

      final snapshot = await diffService.captureSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
      );

      expect(snapshot.tables.length, 1);
      expect(snapshot.createStatements['products'], '');
    });
  });

  group('SchemaDiffService snapshot serialization', () {
    test('snapshotToJson / snapshotFromJson 应完整往返', () {
      final service = SchemaDiffService(_FakeDatabaseService({}));
      final original = SchemaSnapshot(
        connectionId: 'conn1',
        connectionName: 'Local',
        databaseName: 'db',
        capturedAt: DateTime(2026, 6, 1, 12, 0, 0),
        tables: [
          DbTable(
            name: 'products',
            columns: [
              DbColumn(
                name: 'id',
                type: 'INT',
                isPrimaryKey: true,
                isNullable: false,
              ),
              DbColumn(name: 'name', type: 'VARCHAR(255)', isNullable: false),
            ],
            indexes: [
              DbIndex(name: 'PRIMARY', columns: ['id'], isUnique: true),
            ],
          ),
        ],
        views: ['v1'],
        procedures: ['p1'],
        createStatements: {'products': 'CREATE TABLE products (id INT)'},
        viewCreateStatements: {'v1': 'CREATE VIEW v1 AS SELECT 1'},
        procedureCreateStatements: {'p1': 'CREATE PROCEDURE p1()'},
        captureErrors: ['err'],
      );

      final json = service.snapshotToJson(original);
      final restored = service.snapshotFromJson(json);

      expect(restored.connectionId, original.connectionId);
      expect(restored.connectionName, original.connectionName);
      expect(restored.databaseName, original.databaseName);
      expect(restored.capturedAt, original.capturedAt);
      expect(restored.tables.length, original.tables.length);
      expect(restored.tables.first.name, 'products');
      expect(restored.tables.first.columns.length, 2);
      expect(restored.tables.first.indexes.first.isUnique, isTrue);
      expect(restored.views, ['v1']);
      expect(restored.procedures, ['p1']);
      expect(
        restored.createStatements['products'],
        original.createStatements['products'],
      );
      expect(
        restored.viewCreateStatements['v1'],
        original.viewCreateStatements['v1'],
      );
      expect(
        restored.procedureCreateStatements['p1'],
        original.procedureCreateStatements['p1'],
      );
      expect(restored.captureErrors, ['err']);
    });
  });
}

SchemaSnapshot _buildSnapshot({
  required String databaseName,
  required List<DbTable> tables,
  List<String> views = const [],
  List<String> procedures = const [],
  Map<String, String> createStatements = const {},
  Map<String, String> viewCreateStatements = const {},
  Map<String, String> procedureCreateStatements = const {},
  List<String> captureErrors = const [],
}) {
  return SchemaSnapshot(
    connectionId: 'conn1',
    connectionName: 'Local',
    databaseName: databaseName,
    capturedAt: DateTime.now(),
    tables: tables,
    views: views,
    procedures: procedures,
    createStatements: createStatements,
    viewCreateStatements: viewCreateStatements,
    procedureCreateStatements: procedureCreateStatements,
    captureErrors: captureErrors,
  );
}
