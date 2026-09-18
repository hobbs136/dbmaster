// =============================================================================
// 通用数据库 Agent · 工具层单元测试（registry + _executeTool 分发）。
// =============================================================================
// 覆盖：
// - DatabaseToolRegistry：SQL/Mongo/Redis 工具集包含新增只读工具；
// - get_table_relationships：双向 FK JSON 输出 / 空表名失败；
// - run_readonly_query：白名单放行（真经 adapter.executeQuery）/ 写语句拒绝 /
//   每 run 调用上限（10 次）/ 结果行数与输出长度截断 / SQLite PRAGMA 门控；
// - find_documents_mongo：count + 样本、limit 钳制、非 Mongo 连接拒绝；
// - scan_keys / get_key：只读探索 + 非 Redis 连接拒绝。
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/pro/ai/ai_agent_service.dart';
import 'package:dbmaster/pro/ai/database_tool_registry.dart';
import 'package:dbmaster/services/adapters/mongodb_gateway_adapter.dart';
import 'package:dbmaster/services/adapters/redis_gateway_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

// -----------------------------------------------------------------------------
// fakes
// -----------------------------------------------------------------------------

/// extends 以继承基类默认实现；未覆写成员由 noSuchMethod 兜底
///（工具路径不触达 connect/isConnected 等）。
class _FakeSqlAdapter extends DatabaseAdapter {
  _FakeSqlAdapter({
    this.type = DatabaseType.mysql,
    this.fks = const [],
    this.referencing = const [],
    this.queryResult,
  });

  final DatabaseType type;
  final List<ForeignKey> fks;
  final List<ForeignKey> referencing;
  final QueryResult? queryResult;
  final List<String> executedSql = [];

  @override
  DatabaseType get databaseType => type;

  @override
  Future<void> useDatabase(String dbName) async {}

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async => fks;

  @override
  Future<List<ForeignKey>> getReferencingForeignKeys(String tableName) async =>
      referencing;

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    executedSql.add(sql);
    return queryResult ??
        QueryResult(
          columns: const ['n'],
          rows: const [
            {'n': 1},
          ],
          affectedRows: 0,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMongoAdapter extends MongoDBAdapter {
  final List<Map<String, dynamic>> docs;
  final List<List<Map<String, dynamic>>> pipelines = [];

  _FakeMongoAdapter({this.docs = const []});

  @override
  Future<QueryResult> aggregate(
    String collectionName,
    List<Map<String, dynamic>> pipeline,
  ) async {
    pipelines.add(pipeline);
    return QueryResult(
      columns: const ['_id'],
      rows: docs,
      affectedRows: docs.length,
    );
  }

  @override
  Future<int> countDocuments(
    String collectionName, {
    Map<String, dynamic>? filter,
  }) async => 42;
}

class _FakeRedisAdapter extends RedisAdapter {
  @override
  Future<List<String>> getAllKeys({String? pattern, int limit = 1000}) async =>
      ['session:1', 'session:2'];

  @override
  Future<String> getKeyType(String key) async => 'hash';

  @override
  Future<int> getTTL(String key) async => 300;

  @override
  Future<Map<String, String>> getHashPreview(
    String key, {
    int maxFields = 3,
  }) async => {'user_id': '7'};
}

ForeignKey _fk(String table, String column) => ForeignKey(
  name: 'fk_${table}_$column',
  table: table,
  column: column,
  referencedTable: 'tasks',
  referencedColumn: 'id',
  onDelete: 'CASCADE',
);

AiAgentService _service(DatabaseAdapter adapter) =>
    AiAgentService(adapter: adapter);

void main() {
  group('DatabaseToolRegistry 新工具注册', () {
    test('SQL 工具集含 get_table_relationships 与 run_readonly_query', () {
      for (final type in [
        DatabaseType.mysql,
        DatabaseType.postgresql,
        DatabaseType.sqlite,
        DatabaseType.sqlserver,
        DatabaseType.doris,
      ]) {
        final names = DatabaseToolRegistry.getToolsFor(
          type,
        ).map((t) => t['function']['name']).toSet();
        expect(names, contains('get_table_relationships'), reason: '$type');
        expect(names, contains('run_readonly_query'), reason: '$type');
      }
    });

    test('Mongo 工具集含 find_documents_mongo；Redis 含 scan_keys/get_key', () {
      final mongoNames = DatabaseToolRegistry.getToolsFor(
        DatabaseType.mongodb,
      ).map((t) => t['function']['name']).toSet();
      expect(mongoNames, contains('find_documents_mongo'));

      final redisNames = DatabaseToolRegistry.getToolsFor(
        DatabaseType.redis,
      ).map((t) => t['function']['name']).toSet();
      expect(redisNames, containsAll(['scan_keys', 'get_key']));
    });
  });

  group('get_table_relationships', () {
    test('输出双向 FK JSON（含 on_delete 与处理顺序提示）', () async {
      final adapter = _FakeSqlAdapter(
        fks: [
          ForeignKey(
            name: 'fk_tasks_project',
            table: 'tasks',
            column: 'project_id',
            referencedTable: 'projects',
            referencedColumn: 'id',
          ),
        ],
        referencing: [_fk('task_comments', 'task_id')],
      );

      final result = await _service(
        adapter,
      ).executeToolForTesting('get_table_relationships', {'table': 'tasks'});

      expect(result.success, isTrue);
      final payload = jsonDecode(result.output) as Map<String, dynamic>;
      expect(payload['table'], 'tasks');
      expect(
        (payload['outgoing_foreign_keys'] as List).first['references'],
        'projects.id',
      );
      expect(
        (payload['incoming_references'] as List).first['table'],
        'task_comments',
      );
      expect(
        (payload['incoming_references'] as List).first['on_delete'],
        'CASCADE',
      );
      expect(payload['note'], contains('BEFORE'));
    });

    test('空表名失败', () async {
      final result = await _service(
        _FakeSqlAdapter(),
      ).executeToolForTesting('get_table_relationships', {'table': ''});
      expect(result.success, isFalse);
    });
  });

  group('run_readonly_query', () {
    test('白名单 SELECT 放行并经 adapter 执行', () async {
      final adapter = _FakeSqlAdapter();
      final result = await _service(adapter).executeToolForTesting(
        'run_readonly_query',
        {'sql': 'SELECT COUNT(*) FROM task_comments WHERE task_id IN (1, 2)'},
      );
      expect(result.success, isTrue);
      expect(adapter.executedSql, hasLength(1));
      expect(result.output, contains('n'));
    });

    test('写语句拒绝且不触达 adapter', () async {
      final adapter = _FakeSqlAdapter();
      final result = await _service(adapter).executeToolForTesting(
        'run_readonly_query',
        {'sql': 'DELETE FROM tasks WHERE assignee_id = 7'},
      );
      expect(result.success, isFalse);
      expect(result.output, contains('read-only guard'));
      expect(adapter.executedSql, isEmpty);
    });

    test('PRAGMA 仅 SQLite 放行', () async {
      final mysql = _service(_FakeSqlAdapter(type: DatabaseType.mysql));
      final denied = await mysql.executeToolForTesting('run_readonly_query', {
        'sql': 'PRAGMA table_info(tasks)',
      });
      expect(denied.success, isFalse);

      final sqlite = _service(_FakeSqlAdapter(type: DatabaseType.sqlite));
      final allowed = await sqlite.executeToolForTesting('run_readonly_query', {
        'sql': 'PRAGMA foreign_key_list(tasks)',
      });
      expect(allowed.success, isTrue);
    });

    test('每 run 调用上限 10 次', () async {
      final service = _service(_FakeSqlAdapter());
      for (var i = 0; i < 10; i++) {
        final ok = await service.executeToolForTesting('run_readonly_query', {
          'sql': 'SELECT $i',
        });
        expect(ok.success, isTrue, reason: 'call #$i');
      }
      final over = await service.executeToolForTesting('run_readonly_query', {
        'sql': 'SELECT 11',
      });
      expect(over.success, isFalse);
      expect(over.output, contains('limit'));
    });

    test('行数截断：60 行 → 显示 50 行并附 truncation 说明', () async {
      final rows = List.generate(60, (i) => {'n': i});
      final adapter = _FakeSqlAdapter(
        queryResult: QueryResult(
          columns: const ['n'],
          rows: rows,
          affectedRows: 0,
        ),
      );
      final result = await _service(
        adapter,
      ).executeToolForTesting('run_readonly_query', {'sql': 'SELECT n FROM t'});
      expect(result.success, isTrue);
      expect(result.output, contains('showing 50 of 60 rows'));
    });

    test('长单元格截断', () async {
      final adapter = _FakeSqlAdapter(
        queryResult: QueryResult(
          columns: const ['v'],
          rows: [
            {'v': 'x' * 500},
          ],
          affectedRows: 0,
        ),
      );
      final result = await _service(
        adapter,
      ).executeToolForTesting('run_readonly_query', {'sql': 'SELECT v FROM t'});
      expect(result.success, isTrue);
      expect(result.output, contains('(+300 chars)'));
    });
  });

  group('find_documents_mongo', () {
    test('count + 样本输出；管道含 \$match/\$limit（钳制到 50）', () async {
      final adapter = _FakeMongoAdapter(
        docs: [
          {'_id': 1, 'status': 'active'},
        ],
      );
      final result = await _service(adapter).executeToolForTesting(
        'find_documents_mongo',
        {
          'collection': 'tasks',
          'filter': {'status': 'active'},
          'limit': 999,
        },
      );

      expect(result.success, isTrue);
      expect(result.output, contains('Total matching documents: 42'));
      expect(adapter.pipelines, hasLength(1));
      final pipeline = adapter.pipelines.first;
      expect(pipeline.first.keys, contains('\$match'));
      // limit 被钳制到 50
      expect(
        pipeline.where((s) => s.containsKey('\$limit')).first['\$limit'],
        50,
      );
    });

    test('非 Mongo 连接拒绝', () async {
      final result = await _service(
        _FakeSqlAdapter(),
      ).executeToolForTesting('find_documents_mongo', {'collection': 'tasks'});
      expect(result.success, isFalse);
    });
  });

  group('scan_keys / get_key', () {
    test('scan_keys 返回键列表', () async {
      final result = await _service(
        _FakeRedisAdapter(),
      ).executeToolForTesting('scan_keys', {'pattern': 'session:*'});
      expect(result.success, isTrue);
      expect(result.output, contains('session:1'));
    });

    test('get_key 返回 type/ttl/value 预览', () async {
      final result = await _service(
        _FakeRedisAdapter(),
      ).executeToolForTesting('get_key', {'key': 'session:1'});
      expect(result.success, isTrue);
      final payload = jsonDecode(result.output) as Map<String, dynamic>;
      expect(payload['type'], 'hash');
      expect(payload['ttl_seconds'], 300);
      expect(payload['value'], {'user_id': '7'});
    });

    test('非 Redis 连接拒绝', () async {
      final denied = await _service(
        _FakeSqlAdapter(),
      ).executeToolForTesting('scan_keys', {});
      expect(denied.success, isFalse);
    });
  });
}
