// =============================================================================
// 通用数据库 Agent · 反向外键（getReferencingForeignKeys）单元测试。
// =============================================================================
// 覆盖：
// - 基类默认实现：反向过滤 / 大小写不敏感 / 自引用保留 / 单表失败静默 /
//   表数超阈值（>200）返回空；
// - MySQL 网关快路径：information_schema 反查 SQL 形状（REFERENCED_TABLE_NAME
//   过滤 + REFERENTIAL_CONSTRAINTS 取 ON DELETE/UPDATE）、行→ForeignKey 映射；
// - PostgreSQL 网关快路径：同上（referential_constraints 取规则）。
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/server_connection.dart';

// -----------------------------------------------------------------------------
// 基类默认实现 fixtures
// -----------------------------------------------------------------------------

/// extends（而非 implements）以继承基类 getReferencingForeignKeys 默认实现；
/// 未显式覆写的抽象成员由 noSuchMethod 兜底。
class _FakeSqlAdapter extends DatabaseAdapter {
  _FakeSqlAdapter({required this.tables, required this.fksByTable});

  final List<String> tables;
  final Map<String, List<ForeignKey>> fksByTable;
  final Set<String> failTables = {};

  @override
  Future<List<String>> getTables() async => tables;

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async {
    if (failTables.contains(tableName)) {
      throw Exception('metadata boom on $tableName');
    }
    return fksByTable[tableName] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ForeignKey _fk(
  String table,
  String column,
  String refTable,
  String refColumn, {
  String? onDelete,
}) => ForeignKey(
  name: 'fk_${table}_$column',
  table: table,
  column: column,
  referencedTable: refTable,
  referencedColumn: refColumn,
  onDelete: onDelete,
);

// -----------------------------------------------------------------------------
// 网关 HTTP fixtures（模式沿 mysql_gateway_adapter_test.dart）
// -----------------------------------------------------------------------------

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final http.StreamedResponse Function(http.Request request) _handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    requests.add(req);
    return _handler(req);
  }
}

http.StreamedResponse _sse(List<String> events, {int status = 200}) {
  final body = events.join('\n\n') + '\n\n';
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: const {'content-type': 'text/event-stream'},
  );
}

http.StreamedResponse _jsonResp(Object body, int status) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerConnection.resetForTesting();
    ServerConnection().connectEmbedded(
      port: 45674,
      accessToken: 'emb-token',
      refreshToken: 'emb-refresh',
      installUuid: 'uuid',
      version: '0.1.0',
    );
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  group('基类默认实现 getReferencingForeignKeys', () {
    test('反向过滤：仅返回 referencedTable 命中的外键', () async {
      final adapter = _FakeSqlAdapter(
        tables: ['tasks', 'task_comments', 'task_tags', 'projects'],
        fksByTable: {
          'tasks': [_fk('tasks', 'project_id', 'projects', 'id')],
          'task_comments': [
            _fk('task_comments', 'task_id', 'tasks', 'id', onDelete: 'CASCADE'),
          ],
          'task_tags': [
            _fk('task_tags', 'task_id', 'tasks', 'id', onDelete: 'RESTRICT'),
            _fk('task_tags', 'tag_id', 'tags', 'id'),
          ],
        },
      );

      final refs = await adapter.getReferencingForeignKeys('tasks');
      expect(refs.length, 2);
      expect(refs.map((f) => f.table), everyElement(isNot('tasks')));
      expect(refs.map((f) => '${f.table}.${f.column}').toSet(), {
        'task_comments.task_id',
        'task_tags.task_id',
      });
    });

    test('大小写不敏感匹配 + 自引用保留', () async {
      final adapter = _FakeSqlAdapter(
        tables: ['Tasks', 'subtasks'],
        fksByTable: {
          'Tasks': [_fk('Tasks', 'parent_id', 'tasks', 'id')],
          'subtasks': [_fk('subtasks', 'task_id', 'TASKS', 'id')],
        },
      );

      final refs = await adapter.getReferencingForeignKeys('tasks');
      // 自引用（Tasks.parent_id → tasks.id）+ subtasks 引用，都保留
      expect(refs.length, 2);
    });

    test('单表元数据失败静默跳过', () async {
      final adapter = _FakeSqlAdapter(
        tables: ['tasks', 'broken', 'task_comments'],
        fksByTable: {
          'task_comments': [_fk('task_comments', 'task_id', 'tasks', 'id')],
        },
      )..failTables.add('broken');

      final refs = await adapter.getReferencingForeignKeys('tasks');
      expect(refs.length, 1);
      expect(refs.first.table, 'task_comments');
    });

    test('表数超过阈值（>200）返回空防 N+1', () async {
      final bigTables = List.generate(201, (i) => 't$i');
      final adapter = _FakeSqlAdapter(tables: bigTables, fksByTable: {});
      final refs = await adapter.getReferencingForeignKeys('t0');
      expect(refs, isEmpty);
    });
  });

  group('MySQL 网关快路径', () {
    Future<MySQLAdapter> connectedAdapter(
      http.StreamedResponse Function(http.Request) handler,
    ) async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _jsonResp([
            {'id': 'srv-1', 'dbType': 'mysql'},
          ], 200);
        }
        return handler(req);
      });
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
      );
      await adapter.connect(
        DatabaseConnection(
          id: 'local_mysql_1',
          name: 'MySQL Live',
          type: DatabaseType.mysql,
          host: '192.0.2.128',
          port: 3306,
          username: 'root',
          password: 'pw',
          database: 'test',
        ),
      );
      return adapter;
    }

    test('information_schema 反查 + ON DELETE 动作映射', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["CONSTRAINT_NAME","TABLE_NAME","COLUMN_NAME","REFERENCED_COLUMN_NAME","DELETE_RULE","UPDATE_RULE"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["fk_comments_task","task_comments","task_id","id","CASCADE","NO ACTION"],["fk_tags_task","task_tags","task_id","id","RESTRICT","NO ACTION"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":3,"affectedRows":0}',
        ]),
      );

      final refs = await adapter.getReferencingForeignKeys('tasks');
      expect(refs.length, 2);
      expect(refs[0].table, 'task_comments');
      expect(refs[0].column, 'task_id');
      expect(refs[0].referencedTable, 'tasks');
      expect(refs[0].referencedColumn, 'id');
      expect(refs[0].onDelete, 'CASCADE');
      expect(refs[1].table, 'task_tags');
      expect(refs[1].onDelete, 'RESTRICT');
    });

    test('快路径失败回退基类默认扫描', () async {
      // 第一次调用（快路径）返回 500，回退默认扫描会再次执行
      // SHOW CREATE TABLE —— 同样 500 → 基类扫描静默返回空。
      final adapter = await connectedAdapter(
        (req) => _jsonResp({
          'error': {'code': 'X', 'message': 'boom'},
        }, 500),
      );

      final refs = await adapter.getReferencingForeignKeys('tasks');
      expect(refs, isEmpty);
    });
  });

  group('PostgreSQL 网关快路径', () {
    Future<PostgreSQLAdapter> connectedAdapter(
      http.StreamedResponse Function(http.Request) handler,
    ) async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _jsonResp([
            {'id': 'srv-1', 'dbType': 'postgresql'},
          ], 200);
        }
        return handler(req);
      });
      final adapter = PostgreSQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_pg_1': 'srv-1'}),
      );
      await adapter.connect(
        DatabaseConnection(
          id: 'local_pg_1',
          name: 'PG Live',
          type: DatabaseType.postgresql,
          host: '192.0.2.128',
          port: 5432,
          username: 'postgres',
          password: 'pw',
          database: 'test',
        ),
      );
      return adapter;
    }

    test('referential_constraints 取 delete_rule/update_rule', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["constraint_name","table_name","column_name","referenced_column_name","delete_rule","update_rule"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["fk_comments_task","task_comments","task_id","id","CASCADE","NO ACTION"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":1,"truncated":false,"elapsedMs":2,"affectedRows":0}',
        ]),
      );

      final refs = await adapter.getReferencingForeignKeys('tasks');
      expect(refs.length, 1);
      expect(refs[0].table, 'task_comments');
      expect(refs[0].onDelete, 'CASCADE');
      expect(refs[0].onUpdate, 'NO ACTION');
      expect(refs[0].referencedTable, 'tasks');
    });
  });
}
