import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/ai/mysql_ai_context_collector.dart';

class FakeDatabaseService implements DatabaseService {
  final Future<List<Map<String, dynamic>>> Function(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  })?
  onExecuteQuery;

  FakeDatabaseService({this.onExecuteQuery});

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    if (onExecuteQuery != null) {
      return onExecuteQuery!(
        sql,
        connectionId: connectionId,
        database: database,
        sessionId: sessionId,
      );
    }
    return const [];
  }

  @override
  DatabaseAdapter? getAdapter(String connectionId) => null;

  // Stub all other methods as no-ops or throw
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MysqlAiContextCollector', () {
    late FakeDatabaseService dbService;
    late MysqlAiContextCollector collector;

    setUp(() {
      dbService = FakeDatabaseService();
      collector = MysqlAiContextCollector(dbService);
    });

    group('collectTableContext', () {
      test('包含近似行数和引擎信息', () async {
        dbService = FakeDatabaseService(
          onExecuteQuery: (sql, {connectionId, database, sessionId}) async {
            if (sql.contains('SHOW TABLE STATUS')) {
              return [
                {
                  'Name': 'users',
                  'Engine': 'InnoDB',
                  'Rows': 1500000,
                  'Data_length': 104857600,
                  'Index_length': 20971520,
                  'Collation': 'utf8mb4_0900_ai_ci',
                },
              ];
            }
            if (sql.contains('EXPLAIN')) {
              return [
                {
                  'id': 1,
                  'select_type': 'SIMPLE',
                  'table': 'users',
                  'type': 'ALL',
                },
              ];
            }
            return const [];
          },
        );
        collector = MysqlAiContextCollector(dbService);

        final context = await collector.collectTableContext(
          'conn-1',
          'my_db',
          'users',
          locale: 'zh',
        );

        expect(context, contains('目标表: users'));
        expect(context, contains('引擎: InnoDB'));
        expect(context, contains('近似行数: 1500000'));
        expect(context, contains('100.0 MB'));
        expect(context, contains('20.0 MB'));
        expect(context, contains('EXPLAIN SELECT *'));
      });

      test('对带反引号的表名正确转义', () async {
        dbService = FakeDatabaseService(
          onExecuteQuery: (sql, {connectionId, database, sessionId}) async {
            if (sql.contains('EXPLAIN')) {
              return [
                {
                  'id': 1,
                  'select_type': 'SIMPLE',
                  'table': 'my`table',
                  'type': 'ALL',
                },
              ];
            }
            return const [];
          },
        );
        collector = MysqlAiContextCollector(dbService);

        final context = await collector.collectTableContext(
          'conn-1',
          'my_db',
          'my`table',
          locale: 'zh',
        );

        expect(context, contains('目标表: my`table'));
        // EXPLAIN 执行成功即说明反引号已正确转义，未抛出语法错误
        expect(context, contains('执行计划 (EXPLAIN SELECT *):'));
      });
    });

    group('collectDatabaseContext', () {
      test('使用 INFORMATION_SCHEMA.TABLES 获取近似统计', () async {
        dbService = FakeDatabaseService(
          onExecuteQuery: (sql, {connectionId, database, sessionId}) async {
            if (sql.contains('INFORMATION_SCHEMA.TABLES')) {
              return [
                {
                  'TABLE_NAME': 'users',
                  'TABLE_ROWS': 1500000,
                  'DATA_LENGTH': 104857600,
                  'INDEX_LENGTH': 20971520,
                  'ENGINE': 'InnoDB',
                },
                {
                  'TABLE_NAME': 'orders',
                  'TABLE_ROWS': 500000,
                  'DATA_LENGTH': 52428800,
                  'INDEX_LENGTH': 10485760,
                  'ENGINE': 'InnoDB',
                },
              ];
            }
            return const [];
          },
        );
        collector = MysqlAiContextCollector(dbService);

        final context = await collector.collectDatabaseContext(
          'conn-1',
          'my_db',
          locale: 'zh',
        );

        expect(context, contains('当前数据库: my_db'));
        expect(context, contains('users: ~1500000 行'));
        expect(context, contains('orders: ~500000 行'));
        expect(context, contains('表列表（含近似统计）:'));
        // 不应出现 SELECT COUNT(*)
        expect(context, isNot(contains('SELECT COUNT(*)')));
      });
    });

    group('collectServerContext', () {
      test('包含关键状态变量和配置', () async {
        dbService = FakeDatabaseService(
          onExecuteQuery: (sql, {connectionId, database, sessionId}) async {
            if (sql.contains('SHOW GLOBAL STATUS')) {
              return [
                {'Variable_name': 'Threads_connected', 'Value': '42'},
                {'Variable_name': 'Uptime', 'Value': '3600'},
              ];
            }
            if (sql.contains('SHOW GLOBAL VARIABLES')) {
              return [
                {'Variable_name': 'max_connections', 'Value': '151'},
                {'Variable_name': 'version', 'Value': '8.0.32'},
              ];
            }
            return const [];
          },
        );
        collector = MysqlAiContextCollector(dbService);

        final context = await collector.collectServerContext('conn-1');

        expect(context, contains('Threads_connected: 42'));
        expect(context, contains('max_connections: 151'));
        expect(context, contains('version: 8.0.32'));
      });
    });
  });
}
