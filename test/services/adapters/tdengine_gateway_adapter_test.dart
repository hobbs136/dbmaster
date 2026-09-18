// =============================================================================
// T29 TDengine 批次 · TDengine 网关壳 adapter 单元测试。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 草稿 test → 现场注册写回 / 类型不匹配
//   重注册 / test 失败返回 false；
// - testConnection：单发 /api/gw/connections/test（草稿不落库）；
// - executeQuery：kind:"tdengine" 请求形状（sql/database/rowLimit/
//   X-Execution-Id/timeoutMs）、SSE meta/rows/complete 聚合（位置数组→
//   列名 map + columnTypes 驱动 TIMESTAMP 格式化）、写通道（affectedRows、
//   无数据事件）、error 事件上抛（engineCode 透传）、4xx 前置校验、流尾
//   无 complete → CONNECTION_FAILED、NOT_FOUND/CONNECTION_FAILED →
//   onDisconnect；
// - 浏览：getDatabases（SHOW DATABASES + 系统库滤除 + database:'' 不路由）/
//   getTables（用户库 SHOW STABLES / 系统库 SHOW TABLES）/ useDatabase
//   record-only；
// - DESCRIBE：实机 7 列形状（field/type/length/note/…）——TAG 标记读 note
//   列（旧代码读 index 4 是 encode 列，死代码已修）；
// - 超表六方法 + createSuperTable 的 BINARY 长度拼接；
// - 只读守卫（guardReadOnly/guardReadOnlyQuery）+ 事务 fail-loud；
// - 安全：草稿体密码直传、无 taosdata 硬编码回退（REST 时代语义迁 server
//   侧后的客户端半边）；
// - executeSqlScript：逐行 + 注释跳过。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/tdengine_models.dart';
import 'package:dbmaster/services/adapters/tdengine_gateway_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 记录全部请求并按路径规则回放的客户端。
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
  final body = '${events.join('\n\n')}\n\n';
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

Map<String, dynamic> _sentBody(http.Request req) =>
    jsonDecode(req.body) as Map<String, dynamic>;

DatabaseConnection _conn({
  bool readOnly = false,
  int? timeoutSecs,
  String? password = 'pw',
}) =>
    DatabaseConnection(
      id: 'local_td_1',
      name: 'TD Live',
      type: DatabaseType.tdengine,
      host: '192.0.2.128',
      port: 6041,
      username: 'root',
      password: password,
      database: 'td_db',
      readOnly: readOnly,
      extra: timeoutSecs == null ? null : {'timeout': timeoutSecs},
    );

http.StreamedResponse _listResponse(Map<String, String> idTypes) =>
    _jsonResp(
      [for (final e in idTypes.entries) {'id': e.key, 'dbType': e.value}],
      200,
    );

/// TDengine REST 真实形状的查询 SSE（column_meta 原生类型名 + data 数组行）。
List<String> _tdQueryEvents({
  List<List<String>> meta = const [
    ['ts', 'TIMESTAMP', '8'],
    ['v', 'DOUBLE', '8'],
  ],
  List<List<Object?>> data = const [],
  int rows = 0,
}) {
  final columns = [for (final c in meta) c.first];
  final types = [for (final c in meta) c[1]];
  return [
    'event: meta\ndata: ${jsonEncode({
          'kind': 'tdengine',
          'type': 'meta',
          'columns': columns,
          'columnTypes': types,
        })}',
    'event: rows\ndata: ${jsonEncode({
          'kind': 'tdengine',
          'type': 'rows',
          'rows': data,
        })}',
    'event: complete\ndata: ${jsonEncode({
          'kind': 'tdengine',
          'type': 'complete',
          'rowCount': data.length,
          'truncated': false,
          'elapsedMs': 3,
        })}',
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerConnection.resetForTesting();
    ServerConnection().connectEmbedded(
      port: 45673,
      accessToken: 'emb-token',
      refreshToken: 'emb-refresh',
      installUuid: 'uuid',
      version: '0.1.0',
    );
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  /// 映射有效（srv-1，类型 tdengine）的已连接壳。
  Future<TDengineAdapter> connectedAdapter(
    http.StreamedResponse Function(http.Request) handler, {
    DatabaseConnection? conn,
  }) async {
    final client = _RecordingClient((req) {
      if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
        return _listResponse({'srv-1': 'tdengine'});
      }
      return handler(req);
    });
    final adapter = TDengineAdapter()..httpClient = client;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'connection_server_id_map',
      jsonEncode({'local_td_1': 'srv-1'}),
    );
    await adapter.connect(conn ?? _conn());
    return adapter;
  }

  group('connect：serverConnId 解析', () {
    test('无映射 → 草稿 test → 现场注册 + 写回映射', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'serverVersion': '3.3.6.0'}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
          return _jsonResp({'serverConnId': 'srv-1'}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'unmapped'}}, 500);
      });
      final adapter = TDengineAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(adapter.isConnected, isTrue);

      final draft = client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test');
      final draftBody = _sentBody(draft);
      expect(draftBody['dbType'], 'tdengine');
      expect(draftBody['host'], '192.0.2.128');
      expect(draftBody['port'], 6041);
      expect(draftBody['username'], 'root');
      expect(draftBody['password'], 'pw');
      expect(draftBody['defaultDatabase'], 'td_db');

      final prefs = await SharedPreferences.getInstance();
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_td_1'], 'srv-1');
    });

    test('映射有效且类型一致 → 直接复用（无 test/register 请求）', () async {
      var nonListRequests = 0;
      final adapter = await connectedAdapter((req) {
        nonListRequests++;
        return _jsonResp({'error': {'code': 'X', 'message': 'unmapped'}}, 500);
      });
      expect(adapter.isConnected, isTrue);
      expect(nonListRequests, 0);
    });

    test('映射类型不匹配（注册为 clickhouse）→ 重注册', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1': 'clickhouse'});
        }
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
          return _jsonResp({'serverConnId': 'srv-2'}, 200);
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'unmapped'}}, 500);
      });
      final adapter = TDengineAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_td_1': 'srv-1'}),
      );
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      final register = client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections' && r.method == 'POST');
      expect(_sentBody(register)['dbType'], 'tdengine');
    });

    test('草稿 test 失败 → connect 返回 false（不注册）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': false, 'error': 'Authentication failure'}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'unmapped'}}, 500);
      });
      final adapter = TDengineAdapter()..httpClient = client;
      expect(await adapter.connect(_conn()), isFalse);
      expect(
        client.requests.any(
          (r) => r.url.path == '/api/gw/connections' && r.method == 'POST',
        ),
        isFalse,
      );
    });

    test('testConnection：成功 null / 失败错误串', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'serverVersion': '3.3.6.0'}, 200);
        }
        return _jsonResp({'ok': false, 'error': 'connection failed'}, 200);
      });
      final adapter = TDengineAdapter()..httpClient = client;
      expect(await adapter.testConnection(_conn()), isNull);
      // 第二个 handler 分支不可达（单端点客户端）——失败形态单独验证：
      final failClient = _RecordingClient(
        (_) => _jsonResp({'ok': false, 'error': 'engine error'}, 200),
      );
      final failAdapter = TDengineAdapter()..httpClient = failClient;
      expect(await failAdapter.testConnection(_conn()), contains('engine error'));
    });
  });

  group('executeQuery：请求形状与 SSE 聚合', () {
    test('kind:"tdengine" + database 路由 + rowLimit + 执行头', () async {
      final adapter = await connectedAdapter(
        (_) => _sse(_tdQueryEvents(data: const [
          ['2026-08-27T05:40:38.398Z', 1.5],
        ])),
        conn: _conn(timeoutSecs: 25),
      );
      final r = await adapter.executeQuery('SELECT ts, v FROM t1');
      expect(r.columns, ['ts', 'v']);
      expect(r.rows, hasLength(1));

      final adapter2 = adapter;
      // 请求形状断言：最后一个 query 请求。
      final client = adapter2.httpClient as _RecordingClient;
      final queryReq = client.requests.lastWhere(
        (r) => r.url.path.contains('/query'),
      );
      expect(queryReq.url.path, '/api/gw/connections/srv-1/query');
      expect(queryReq.headers['X-Execution-Id'], isNotNull);
      final body = _sentBody(queryReq);
      expect(body['kind'], 'tdengine');
      expect(body['sql'], 'SELECT ts, v FROM t1');
      expect(body['database'], 'td_db');
      expect(body['rowLimit'], 10000);
      expect(body['timeoutMs'], 25000);
    });

    test('TIMESTAMP 列按 columnTypes 格式化为本地时间字符串', () async {
      final adapter = await connectedAdapter(
        (_) => _sse(_tdQueryEvents(data: const [
          ['2026-08-27T05:40:38.398Z', 1.5],
        ])),
      );
      final r = await adapter.executeQuery('SELECT ts, v FROM t1');
      final ts = r.rows.first['ts'];
      expect(ts, isA<String>());
      expect(ts as String, matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')));
      expect(r.rows.first['v'], 1.5);
    });

    test('TIMESTAMP epoch 毫秒整数臂', () async {
      final adapter = await connectedAdapter(
        (_) => _sse(_tdQueryEvents(data: const [
          [1759278038398, 2.5],
        ])),
      );
      final r = await adapter.executeQuery('SELECT ts, v FROM t1');
      expect(r.rows.first['ts'] as String, matches(
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'),
      ));
    });

    test('非 TIMESTAMP 列不格式化（VARCHAR 原样）', () async {
      final adapter = await connectedAdapter(
        (_) => _sse(
          _tdQueryEvents(
            meta: const [
              ['node', 'VARCHAR', '16'],
            ],
            data: const [
              ['n1'],
            ],
          ),
        ),
      );
      final r = await adapter.executeQuery('SELECT node FROM t1');
      expect(r.rows.first['node'], 'n1');
    });

    test('写通道：affectedRows 透传、无数据行', () async {
      final adapter = await connectedAdapter(
        (_) => _sse([
          'event: complete\ndata: ${jsonEncode({
                'kind': 'tdengine',
                'type': 'complete',
                'rowCount': 0,
                'truncated': false,
                'affectedRows': 2,
                'elapsedMs': 5,
              })}',
        ]),
      );
      final r = await adapter.executeQuery("INSERT INTO c1 USING s TAGS('n') VALUES (NOW, 1) (NOW+1s, 2)");
      expect(r.columns, isEmpty);
      expect(r.rows, isEmpty);
      expect(r.affectedRows, 2);
    });

    test('error 事件 → TdengineGatewayException（engineCode 透传）', () async {
      final adapter = await connectedAdapter(
        (_) => _sse([
          'event: error\ndata: ${jsonEncode({
                'kind': 'tdengine',
                'type': 'error',
                'code': 'DB_ERROR',
                'message': 'Fail to get table info',
                'engineCode': '9731',
              })}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT * FROM missing'),
        throwsA(
          isA<TdengineGatewayException>()
              .having((e) => e.code, 'code', 'DB_ERROR')
              .having((e) => e.engineCode, 'engineCode', '9731'),
        ),
      );
    });

    test('4xx 前置校验错误形状（UNSUPPORTED_KIND 等）', () async {
      final adapter = await connectedAdapter(
        (_) => _jsonResp(
          {'error': {'code': 'MULTI_STATEMENT', 'message': 'one at a time'}},
          400,
        ),
      );
      await expectLater(
        adapter.executeQuery('SELECT 1; SELECT 2'),
        throwsA(
          isA<TdengineGatewayException>()
              .having((e) => e.code, 'code', 'MULTI_STATEMENT'),
        ),
      );
    });

    test('流尾无 complete → CONNECTION_FAILED + onDisconnect', () async {
      var disconnects = 0;
      final adapter = await connectedAdapter((_) => _sse([
            'event: meta\ndata: {"kind":"tdengine","type":"meta","columns":["v"]}',
          ]));
      adapter.onDisconnect = () => disconnects++;
      await expectLater(
        adapter.executeQuery('SELECT v FROM t1'),
        throwsA(
          isA<TdengineGatewayException>()
              .having((e) => e.code, 'code', 'CONNECTION_FAILED'),
        ),
      );
      expect(disconnects, 1);
    });

    test('NOT_FOUND → onDisconnect（serverConnId 失效）', () async {
      var disconnects = 0;
      final adapter = await connectedAdapter(
        (_) => _sse([
          'event: error\ndata: ${jsonEncode({
                'kind': 'tdengine',
                'type': 'error',
                'code': 'NOT_FOUND',
                'message': "connection 'srv-1' not found",
              })}',
        ]),
      );
      adapter.onDisconnect = () => disconnects++;
      await expectLater(
        adapter.executeQuery('SELECT 1'),
        throwsA(isA<TdengineGatewayException>()),
      );
      expect(disconnects, 1);
    });
  });

  group('浏览', () {
    test('getDatabases：SHOW DATABASES + 系统库滤除 + database 不路由', () async {
      String? routedDb = '__unset__';
      final adapter = await connectedAdapter((req) {
        final body = _sentBody(req);
        routedDb = body['database']?.toString();
        return _sse(_tdQueryEvents(
          meta: const [
            ['name', 'VARCHAR', '64'],
          ],
          data: const [
            ['information_schema'],
            ['performance_schema'],
            ['td_db'],
            ['power'],
          ],
        ));
      });
      final dbs = await adapter.getDatabases();
      expect(dbs, ['td_db', 'power']);
      expect(routedDb == null || routedDb!.isEmpty, isTrue,
          reason: 'SHOW DATABASES 不带库路由（database:""）');
    });

    test('getTables：用户库 SHOW STABLES', () async {
      String? sql;
      final adapter = await connectedAdapter((req) {
        sql = _sentBody(req)['sql']?.toString();
        return _sse(_tdQueryEvents(
          meta: const [
            ['stable_name', 'VARCHAR', '192'],
          ],
          data: const [
            ['meters'],
          ],
        ));
      });
      expect(await adapter.getTables(), ['meters']);
      expect(sql, 'SHOW STABLES');
    });

    test('getTables：系统库 SHOW TABLES', () async {
      String? sql;
      final adapter = await connectedAdapter((req) {
        sql = _sentBody(req)['sql']?.toString();
        return _sse(_tdQueryEvents(
          meta: const [
            ['table_name', 'VARCHAR', '192'],
          ],
          data: const [
            ['insp_tables'],
          ],
        ));
      }, conn: _conn().copyWith(database: 'information_schema'));
      // useDatabase 先行（record-only）再取表——覆盖初始库为系统库的路径。
      await adapter.useDatabase('information_schema');
      expect(await adapter.getTables(), ['insp_tables']);
      expect(sql, 'SHOW TABLES');
    });

    test('useDatabase record-only：拷贝连接记录目标库', () async {
      final adapter = await connectedAdapter((_) => _sse(_tdQueryEvents()));
      await adapter.useDatabase('other_db');
      expect(adapter.currentConnection?.database, 'other_db');
    });

    test('getServerVersion：SELECT SERVER_VERSION()', () async {
      String? sql;
      final adapter = await connectedAdapter((req) {
        sql = _sentBody(req)['sql']?.toString();
        return _sse(_tdQueryEvents(
          meta: const [
            ['server_version()', 'VARCHAR', '7'],
          ],
          data: const [
            ['3.3.6.0'],
          ],
        ));
      });
      final v = await adapter.getServerVersion();
      expect(v?['version'], '3.3.6.0');
      expect(v?['database'], 'TDengine');
      expect(sql, contains('SERVER_VERSION'));
    });
  });

  group('DESCRIBE 解析（实机 7 列形状）', () {
    /// 真实 REST 响应列：field/type/length/note/encode/compress/level。
    List<String> describeEvents() => _tdQueryEvents(
          meta: const [
            ['field', 'VARCHAR', '64'],
            ['type', 'VARCHAR', '20'],
            ['length', 'INT', '4'],
            ['note', 'VARCHAR', '16'],
            ['encode', 'VARCHAR', '12'],
            ['compress', 'VARCHAR', '12'],
            ['level', 'VARCHAR', '12'],
          ],
          data: const [
            ['ts', 'TIMESTAMP', 8, '', 'delta-i', 'lz4', 'medium'],
            ['v', 'DOUBLE', 8, '', 'delta-d', 'lz4', 'medium'],
            ['node', 'VARCHAR', 16, 'TAG', 'disabled', 'disabled', 'disabled'],
          ],
        );

    test('getTableColumns：TAG 标记读 note 列 → isTag', () async {
      final adapter = await connectedAdapter((_) => _sse(describeEvents()));
      final cols = await adapter.getTableColumns('t1');
      expect(cols, hasLength(3));
      final node = cols.firstWhere((c) => c.name == 'node');
      expect(node.isTag, isTrue, reason: '旧代码读 index 4（encode 列）恒 false——已修');
      expect(node.type, 'VARCHAR');
      final ts = cols.firstWhere((c) => c.name == 'ts');
      expect(ts.isPrimaryKey, isFalse, reason: '超表 ts 列 note 为空（实机钉定）');
    });

    test('getSuperTableDetail：列/标签分流', () async {
      final adapter = await connectedAdapter((_) => _sse(describeEvents()));
      final detail = await adapter.getSuperTableDetail('t1');
      expect(detail, isNotNull);
      expect(detail!.columns.map((c) => c.name), ['ts', 'v']);
      expect(detail.tags.map((t) => t.name), ['node']);
      expect(detail.tags.first.type, 'VARCHAR');
    });

    test('getSuperTables：名称列表', () async {
      final adapter = await connectedAdapter(
        (_) => _sse(_tdQueryEvents(
          meta: const [
            ['stable_name', 'VARCHAR', '192'],
          ],
          data: const [
            ['meters'],
            [''],
          ],
        )),
      );
      final stables = await adapter.getSuperTables();
      expect(stables.map((s) => s.name), ['meters']);
    });

    test('getTableIndexes：主键 + 标签索引（说明性）', () async {
      final adapter = await connectedAdapter((_) => _sse(describeEvents()));
      final indexes = await adapter.getTableIndexes('t1');
      expect(indexes, hasLength(2)); // 时间戳主键 + node 标签
      expect(indexes.any((i) => i.name == 't1_node_idx'), isTrue);
    });
  });

  group('超表 DDL', () {
    test('createSuperTable：BINARY 长度拼接 + COMMENT', () async {
      String? sql;
      final adapter = await connectedAdapter((req) {
        sql = _sentBody(req)['sql']?.toString();
        return _sse(_tdQueryEvents());
      });
      final ok = await adapter.createSuperTable(
        name: 'meters',
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP'),
          TdColumn(name: 'location', type: 'BINARY', length: 32),
        ],
        tags: [TdTag(name: 'device', type: 'BINARY', length: 16)],
        comment: 'hello',
      );
      expect(ok, isTrue);
      expect(sql, contains('CREATE STABLE IF NOT EXISTS `meters`'));
      expect(sql, contains('`location` BINARY(32)'));
      expect(sql, contains('`device` BINARY(16)'));
      expect(sql, contains("COMMENT 'hello'"));
    });

    test('dropSuperTable / createSubTable / dropSubTable SQL 形状', () async {
      final sqls = <String>[];
      final adapter = await connectedAdapter((req) {
        sqls.add(_sentBody(req)['sql']?.toString() ?? '');
        return _sse(_tdQueryEvents());
      });
      expect(await adapter.dropSuperTable('meters'), isTrue);
      expect(
        await adapter.createSubTable(
          name: 'd1',
          superTableName: 'meters',
          tagValues: {'device': ' sensor-1'},
        ),
        isTrue,
      );
      expect(await adapter.dropSubTable('d1'), isTrue);
      expect(sqls[0], contains('DROP STABLE IF EXISTS `meters`'));
      expect(sqls[1], contains('CREATE TABLE `d1` USING `meters`'));
      expect(sqls[1], contains("TAGS (' sensor-1')"));
      expect(sqls[2], contains('DROP TABLE IF EXISTS `d1`'));
    });
  });

  group('只读守卫 + 事务 fail-loud', () {
    test('readOnly 连接 executeQuery 写语句被拒（客户端守卫）', () async {
      final adapter = await connectedAdapter(
        (_) => _sse(_tdQueryEvents()),
        conn: _conn(readOnly: true),
      );
      await expectLater(
        adapter.executeQuery('INSERT INTO t VALUES (1)'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('readOnly 连接 DDL 直走方法被拒（guardReadOnly）', () async {
      final adapter = await connectedAdapter(
        (_) => _sse(_tdQueryEvents()),
        conn: _conn(readOnly: true),
      );
      await expectLater(
        adapter.createDatabase('x'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      await expectLater(
        adapter.dropSuperTable('m'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('事务 fail-loud（TDengine 引擎层无事务，防假回滚）', () async {
      final adapter = await connectedAdapter((_) => _sse(_tdQueryEvents()));
      expect(() => adapter.beginTransaction(), throwsA(isA<UnsupportedError>()));
      expect(() => adapter.commit(), throwsA(isA<UnsupportedError>()));
      expect(() => adapter.rollback(), throwsA(isA<UnsupportedError>()));
      expect(adapter.isInTransaction, isFalse);
    });
  });

  group('安全：凭据形状（REST Basic 头语义已迁 server 侧）', () {
    test('密码直传草稿体，无 taosdata 硬编码回退', () async {
      Map<String, dynamic>? draft;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          draft = _sentBody(req);
          return _jsonResp({'ok': true}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
          return _jsonResp({'serverConnId': 'srv-1'}, 200);
        }
        return _listResponse({});
      });
      final adapter = TDengineAdapter()..httpClient = client;
      await adapter.connect(_conn(password: 'my_secret_pass'));
      expect(draft?['password'], 'my_secret_pass');

      // 密码 null → 空串上送（server validate_draft 拒空密码），不回退
      // taosdata 默认。
      final nullPwClient = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          draft = _sentBody(req);
          return _jsonResp({'ok': false, 'error': 'password required'}, 200);
        }
        return _listResponse({});
      });
      final nullPwAdapter = TDengineAdapter()..httpClient = nullPwClient;
      await nullPwAdapter.connect(_conn(password: null));
      expect(draft?['password'], '');
      expect(draft?['password'], isNot('taosdata'));
    });
  });

  group('脚本执行', () {
    test('executeSqlScript：逐行执行 + 注释/空行跳过', () async {
      final sqls = <String>[];
      final adapter = await connectedAdapter((req) {
        sqls.add(_sentBody(req)['sql']?.toString() ?? '');
        return _sse(_tdQueryEvents());
      });
      final ok = await adapter.executeSqlScript(
        '-- header\nCREATE DATABASE d1\n\n# hash comment\nCREATE DATABASE d2\n',
      );
      expect(ok, isTrue);
      expect(sqls, ['CREATE DATABASE d1', 'CREATE DATABASE d2']);
    });
  });
  // 网关 TLS 透传 + server 侧 SSH 隧道：draft/test body 形状。
  group('draft body：TLS 透传 + server 侧 SSH 隧道', () {
    final sshWire = {
      'host': 'jump.example.com',
      'port': 22,
      'username': 'deploy',
      'authMode': 'privateKey',
      'privateKey': '-----BEGIN OPENSSH PRIVATE KEY-----',
    };

    test('useTls 开启 → extra 两键；ssh 对象原样透传', () async {
      final client = _RecordingClient((req) =>
          _jsonResp({'ok': true, 'elapsedMs': 4}, 200));
      final adapter = TDengineAdapter()..httpClient = client;
      await adapter.testConnection(DatabaseConnection(
        id: 'local_td_1',
        name: 'TD Live',
        type: DatabaseType.tdengine,
        host: '192.0.2.128',
        port: 6041,
        username: 'root',
        password: 'pw',
        database: 'td_db',
        extra: {'useTls': true, 'tlsInsecure': false, 'ssh': sshWire},
      ));

      final body = _sentBody(client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test'));
      expect(body['extra'], {'useTls': true, 'tlsInsecure': false});
      expect(body['ssh'], sshWire);
    });

    test('useTls 关闭 / 无 ssh → 两键均不下发', () async {
      final client = _RecordingClient((req) =>
          _jsonResp({'ok': true, 'elapsedMs': 4}, 200));
      final adapter = TDengineAdapter()..httpClient = client;
      await adapter.testConnection(DatabaseConnection(
        id: 'local_td_1',
        name: 'TD Live',
        type: DatabaseType.tdengine,
        host: '192.0.2.128',
        port: 6041,
        username: 'root',
        password: 'pw',
        database: 'td_db',
        extra: {'timeout': 10},
      ));

      final body = _sentBody(client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test'));
      expect(body.containsKey('extra'), isFalse);
      expect(body.containsKey('ssh'), isFalse);
    });
  });

}
