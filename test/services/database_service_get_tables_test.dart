// =============================================================================
// 批2.6-C1 红测：getTables 库限定路由 —— 生产实现者矩阵 + 服务层门透传。
// =============================================================================
// 服务层门（database_service.dart:1402 `is DatabaseQualifiedTablesAdapter`）
// 行为已由 database_service_test.dart 的 fake 用例锁定（FU-18）；本文件补
// 红测两块：
// 1. **实现者矩阵**：六个修复目标（PG/SS/TD/Mongo/SQLite/Redis）生产 adapter
//    必须实现 DatabaseQualifiedTablesAdapter——现状均未实现（红），门不会
//    拾取它们；实现落地后 mysql/clickhouse 既有实现者同组回归锁绿。
// 2. 门透传：fake（含 database 声明面）确认 databaseName 非空时按
//    `qualified.getTables(database:)` 形状透传。
// 注：database_service_test.dart 的 fake 为库私有（_前缀），不可复用导入，
// 故此处按同形状重建最小 fake（语义复用申报：见汇报）。
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/clickhouse_adapter.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'package:dbmaster/services/adapters/tdengine_gateway_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';

/// 门透传 fake（形状对齐 database_service_test.dart 的库私有版）。
class _QualifiedTablesAdapter
    implements DatabaseAdapter, DatabaseQualifiedTablesAdapter {
  final List<String?> receivedDatabases = <String?>[];

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getTables({String? database}) async {
    receivedDatabases.add(database);
    return <String>['qualified_t'];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DbServer _server(String id) => DbServer(
  id: id,
  name: id,
  type: DatabaseType.mysql,
  host: '127.0.0.1',
  port: 3306,
  username: null,
  password: null,
  database: null,
  useSSL: false,
  timeoutSeconds: 30,
  autoReconnect: false,
);

void main() {
  group('getTables 库限定路由（批2.6-C1）', () {
    group('生产实现者矩阵', () {
      test('既有实现者回归锁：MySQL 族网关壳 + ClickHouse', () {
        expect(MySQLAdapter(), isA<DatabaseQualifiedTablesAdapter>());
        expect(DorisAdapter(), isA<DatabaseQualifiedTablesAdapter>());
        expect(ClickhouseAdapter(), isA<DatabaseQualifiedTablesAdapter>());
      });

      test('PostgreSQLAdapter 应实现 DatabaseQualifiedTablesAdapter', () {
        expect(PostgreSQLAdapter(), isA<DatabaseQualifiedTablesAdapter>());
      });

      test('SqlServerAdapter 应实现 DatabaseQualifiedTablesAdapter', () {
        expect(SqlServerAdapter(), isA<DatabaseQualifiedTablesAdapter>());
      });

      test('TDengineAdapter 应实现 DatabaseQualifiedTablesAdapter', () {
        expect(TDengineAdapter(), isA<DatabaseQualifiedTablesAdapter>());
      });

      test('MongoDBAdapter 应实现 DatabaseQualifiedTablesAdapter', () {
        expect(MongoDBAdapter(), isA<DatabaseQualifiedTablesAdapter>());
      });

      test('SQLiteAdapter 应实现 DatabaseQualifiedTablesAdapter', () {
        expect(SQLiteAdapter(), isA<DatabaseQualifiedTablesAdapter>());
      });

      test('RedisAdapter 应实现 DatabaseQualifiedTablesAdapter', () {
        expect(RedisAdapter(), isA<DatabaseQualifiedTablesAdapter>());
      });
    });

    group('服务层门透传', () {
      test('databaseName 非空 → qualified.getTables(database:) 形状透传', () async {
        final service = DatabaseService();
        final qualified = _QualifiedTablesAdapter();
        service.registerConnectedServerForTest(_server('conn-c1'));
        service.registerConnectedAdapterForTest('conn-c1', qualified);

        final tables = await service.getTables(
          connectionId: 'conn-c1',
          databaseName: 'target_db',
        );

        expect(tables, <String>['qualified_t']);
        expect(qualified.receivedDatabases, <String?>['target_db']);
      });
    });
  });
}
