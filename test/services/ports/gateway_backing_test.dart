// =============================================================================
// GatewayBacking 单元测试（C10 · port 化连接语义——网关双形态）。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例两形态（embedded 握手注入 / 远程 login
// 全程），验证 T27 wire 契约：POST /api/gw/connections/test（camelCase 草稿体、
// 测试即远程调用、连接失败也是 200 {ok:false}）、POST /api/gw/connections
// （凭据入 vault、返回 serverConnId）、DELETE /api/gw/connections/{id}（幂等
// 204），以及 embedded 与远程两形态行为一致（同一路径/头/体，仅 baseUrl 不同）。
// =============================================================================

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/ports/adapter_backing.dart';
import 'package:dbmaster/services/ports/db_service_ports.dart';
import 'package:dbmaster/services/ports/gateway_backing.dart';
import 'package:dbmaster/services/ports/port_types.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 记录最近一次请求并按 handler 回放的客户端。
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final http.Response Function(http.Request request) _handler;
  http.Request? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    lastRequest = req;
    final resp = _handler(req);
    return http.StreamedResponse(
      Stream.value(resp.bodyBytes),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

Map<String, dynamic> _sentBody(http.Request req) =>
    jsonDecode(req.body) as Map<String, dynamic>;

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async => _store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async => _store.remove(key);
}

DbServer _mysqlServer() => DbServer(
      id: 'conn_local_1',
      name: 'prod mysql',
      type: DatabaseType.mysql,
      host: 'db.example.com',
      port: 3306,
      username: 'root',
      password: 'secret',
      database: 'appdb',
    );

DbServer _sqliteServer() => DbServer(
      id: 'conn_local_2',
      name: 'local sqlite',
      type: DatabaseType.sqlite,
      host: 'C:/data/chinook.db',
      port: 0,
    );

void main() {
  setUp(() {
    ServerConnection.resetForTesting();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  /// embedded 形态：握手注入（与 EmbeddedServerService.applyTo 同路径）。
  GatewayBacking wireEmbedded(_RecordingClient client, {int port = 45671}) {
    ServerConnection().connectEmbedded(
      port: port,
      accessToken: 'emb-access-token',
      refreshToken: 'emb-refresh',
      installUuid: 'uuid',
      version: '0.1.0',
    );
    return GatewayBacking(httpClient: client);
  }

  /// 远程形态：完整 login（fake storage + fake client）。
  Future<GatewayBacking> wireRemote(
    http.Client loginClient,
    http.Client gatewayClient,
  ) async {
    final conn = ServerConnection()
      ..testSecureStorage = _FakeSecureStorage()
      ..testHttpClient = loginClient;
    await conn.connect('http://remote.example:8080', 'a@b.com', 'pw');
    return GatewayBacking(httpClient: gatewayClient);
  }

  group('testConnection（POST /api/gw/connections/test）', () {
    test('请求形状：路径/Bearer/JSON camelCase 草稿体（embedded 形态）', () async {
      final client = _RecordingClient(
        (_) => _json({'ok': true, 'elapsedMs': 87, 'serverVersion': '8.0.36'}),
      );
      final backing = wireEmbedded(client);

      final result = await backing.testConnection(_mysqlServer());

      final req = client.lastRequest!;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'http://127.0.0.1:45671/api/gw/connections/test');
      expect(req.headers['Authorization'], 'Bearer emb-access-token');
      expect(req.headers['Content-Type'], contains('application/json'));
      expect(_sentBody(req), {
        'dbType': 'mysql',
        'host': 'db.example.com',
        'port': 3306,
        'username': 'root',
        'password': 'secret',
        'defaultDatabase': 'appdb',
      });
      expect(result.ok, isTrue);
      expect(result.serverVersion, '8.0.36');
      expect(result.elapsedMs, 87);
    });

    test('sqlite 草稿体：仅 filePath（客户端 host=路径的 wire 映射）', () async {
      final client = _RecordingClient((_) => _json({'ok': true, 'elapsedMs': 5}));
      final backing = wireEmbedded(client);

      await backing.testConnection(_sqliteServer());

      expect(_sentBody(client.lastRequest!), {
        'dbType': 'sqlite',
        'filePath': 'C:/data/chinook.db',
      });
    });

    test('连接失败也是 HTTP 200：{ok:false,error} 映射为失败结果', () async {
      final client = _RecordingClient(
        (_) => _json({'ok': false, 'error': 'connection timed out',
                      'elapsedMs': 5000}),
      );
      final backing = wireEmbedded(client);

      final result = await backing.testConnection(_mysqlServer());
      expect(result.ok, isFalse);
      expect(result.error, 'connection timed out');
      expect(result.elapsedMs, 5000);
    });

    test('wire 校验错误（400 UNSUPPORTED_DB_TYPE）→ PortException', () async {
      final client = _RecordingClient(
        (_) => _json(
          {'error': {'code': 'UNSUPPORTED_DB_TYPE', 'message': 'bad type'}},
          400,
        ),
      );
      final backing = wireEmbedded(client);

      await expectLater(
        backing.testConnection(_mysqlServer()),
        throwsA(
          isA<PortException>()
              .having((e) => e.code, 'code', 'UNSUPPORTED_DB_TYPE'),
        ),
      );
    });

    test('401 → PortException UNAUTHORIZED', () async {
      final client = _RecordingClient(
        (_) => _json(
          {'error': {'code': 'UNAUTHORIZED', 'message': 'invalid token'}},
          401,
        ),
      );
      final backing = wireEmbedded(client);

      await expectLater(
        backing.testConnection(_mysqlServer()),
        throwsA(
          isA<PortException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );
    });

    test('未连接 server → PortException CONFIG（embedded 硬依赖语义）', () async {
      final backing = GatewayBacking(
        httpClient: _RecordingClient((_) => _json({'ok': true})),
      );
      await expectLater(
        backing.testConnection(_mysqlServer()),
        throwsA(
          isA<PortException>().having((e) => e.code, 'code', 'CONFIG'),
        ),
      );
    });

    test('非网关类型（redis）本地即拒：UNSUPPORTED_DB_TYPE，不发请求', () async {
      var calls = 0;
      final client = _RecordingClient((_) {
        calls++;
        return _json({'ok': true});
      });
      final backing = wireEmbedded(client);

      await expectLater(
        backing.testConnection(
          _mysqlServer().copyWith(type: DatabaseType.redis),
        ),
        throwsA(
          isA<PortException>()
              .having((e) => e.code, 'code', 'UNSUPPORTED_DB_TYPE'),
        ),
      );
      expect(calls, 0);
    });
  });

  group('embedded 与远程两形态行为一致', () {
    test('同一路径/头/体，仅 baseUrl 不同', () async {
      final embClient = _RecordingClient(
        (_) => _json({'ok': true, 'elapsedMs': 10}),
      );
      final remoteClient = _RecordingClient(
        (_) => _json({'ok': true, 'elapsedMs': 10}),
      );

      // GatewayBacking 经 ServerConnection 单例解析 baseUrl（生产中同一时刻
      // 只有一种形态）——先记录 embedded 请求，再切远程形态对比。
      final emb = wireEmbedded(embClient);
      final embResult = await emb.testConnection(_mysqlServer());
      final embReq = embClient.lastRequest!;

      final remote = await wireRemote(
        _RecordingClient(
          (req) => req.url.path == '/api/auth/login'
              ? _json({
                  'access_token': 'remote-access',
                  'refresh_token': 'remote-refresh',
                  'user': {
                    'id': 'u1',
                    'email': 'a@b.com',
                    'display_name': 'T',
                  },
                })
              : _json({'error': {'code': 'NOT_FOUND', 'message': 'x'}}, 404),
        ),
        remoteClient,
      );
      final remoteResult = await remote.testConnection(_mysqlServer());
      final remoteReq = remoteClient.lastRequest!;

      expect(remoteReq.url.path, embReq.url.path);
      expect(remoteReq.headers['Content-Type'], embReq.headers['Content-Type']);
      expect(_sentBody(remoteReq), _sentBody(embReq));
      expect(
        remoteReq.url.authority,
        isNot(embReq.url.authority), // remote.example:8080 ≠ 127.0.0.1:45671
      );
      expect(remoteResult.ok, embResult.ok);
      expect(
        remoteReq.headers['Authorization'],
        'Bearer remote-access', // token 来自各自会话，形态由 ServerConnection 吸收
      );
    });
  });

  group('persistConnection（POST /api/gw/connections）', () {
    test('草稿体 + name/readOnly；charset/timezone 空则省略', () async {
      final client = _RecordingClient(
        (_) => _json({'serverConnId': 'srv-conn-uuid-1'}),
      );
      final backing = wireEmbedded(client);

      // charset 构造默认 'utf8mb4'——显式置 null 才是「空则省略」路径。
      final server = DbServer(
        id: 'conn_local_1',
        name: 'prod mysql',
        type: DatabaseType.mysql,
        host: 'db.example.com',
        port: 3306,
        username: 'root',
        password: 'secret',
        database: 'appdb',
        charset: null,
      );
      final id = await backing.persistConnection(server);

      expect(id, 'srv-conn-uuid-1');
      final body = _sentBody(client.lastRequest!);
      expect(body['name'], 'prod mysql');
      expect(body['dbType'], 'mysql');
      expect(body['host'], 'db.example.com');
      expect(body['password'], 'secret');
      expect(body['readOnly'], false);
      expect(body.containsKey('charset'), isFalse);
      expect(body.containsKey('timezone'), isFalse);
    });

    test('readOnly/charset/timezone 随连接透传', () async {
      final client = _RecordingClient(
        (_) => _json({'serverConnId': 'x'}),
      );
      final backing = wireEmbedded(client);
      await backing.persistConnection(
        _mysqlServer().copyWith(
          readOnly: true,
          charset: 'utf8mb4',
          timezone: 'UTC',
        ),
      );
      final body = _sentBody(client.lastRequest!);
      expect(body['readOnly'], true);
      expect(body['charset'], 'utf8mb4');
      expect(body['timezone'], 'UTC');
    });

    test('响应缺 serverConnId → PortException DB_ERROR', () async {
      final client = _RecordingClient((_) => _json({'unexpected': 1}));
      final backing = wireEmbedded(client);
      await expectLater(
        backing.persistConnection(_mysqlServer()),
        throwsA(
          isA<PortException>().having((e) => e.code, 'code', 'DB_ERROR'),
        ),
      );
    });
  });

  group('removeConnection（DELETE /api/gw/connections/{id}）', () {
    test('204 幂等删除', () async {
      final client = _RecordingClient((_) => http.Response('', 204));
      final backing = wireEmbedded(client);

      await backing.removeConnection('srv-conn-uuid-1');

      final req = client.lastRequest!;
      expect(req.method, 'DELETE');
      expect(
        req.url.toString(),
        'http://127.0.0.1:45671/api/gw/connections/srv-conn-uuid-1',
      );
      expect(req.headers['Authorization'], 'Bearer emb-access-token');
    });

    test('服务端错误 → PortException', () async {
      final client = _RecordingClient(
        (_) => _json(
          {'error': {'code': 'DB_ERROR', 'message': 'boom'}},
          500,
        ),
      );
      final backing = wireEmbedded(client);
      await expectLater(
        backing.removeConnection('srv-conn-uuid-1'),
        throwsA(
          isA<PortException>().having((e) => e.code, 'code', 'DB_ERROR'),
        ),
      );
    });
  });

  group('connectionState', () {
    test('embedded 形态 + 注册表 readOnly 反查', () async {
      final client = _RecordingClient(
        (_) => _json([
          {'id': 'srv-1', 'name': 'a', 'dbType': 'mysql',
           'readOnly': true, 'defaultDatabase': null},
          {'id': 'srv-2', 'name': 'b', 'dbType': 'pg',
           'readOnly': false, 'defaultDatabase': null},
        ]),
      );
      final backing = wireEmbedded(client);

      final state = await backing.connectionState('srv-1');
      expect(state.mode, ConnectionMode.embeddedServer);
      expect(state.readOnly, isTrue);

      expect((await backing.connectionState('srv-2')).readOnly, isFalse);
      expect((await backing.connectionState('missing')).readOnly, isFalse);
    });

    test('远程形态 → remoteServer；列表失败不阻断（readOnly 退化 false）',
        () async {
      final gatewayClient = _RecordingClient(
        (_) => _json({'error': {'code': 'DB_ERROR', 'message': 'x'}}, 500),
      );
      final backing = await wireRemote(
        _RecordingClient(
          (req) => req.url.path == '/api/auth/login'
              ? _json({
                  'access_token': 't',
                  'refresh_token': 'r',
                  'user': {'id': 'u', 'email': 'a@b.com', 'display_name': 'T'},
                })
              : _json({'error': {'code': 'NOT_FOUND', 'message': 'x'}}, 404),
        ),
        gatewayClient,
      );

      final state = await backing.connectionState('any');
      expect(state.mode, ConnectionMode.remoteServer);
      expect(state.readOnly, isFalse);
    });
  });

  group('路由（迁移协调矩阵编译期落点）', () {
    test('T29 第二批后：sqlserver + mysql 族 + postgresql 走 GatewayBacking，其余 Adapter', () {
      final ports = DbServicePorts(adapterDbService: DatabaseService());
      // T28 首发 sqlserver；T29 首批加入 mysql 族六成员，第二批加入 pg，
      // 第三批加入 clickhouse。
      const gatewayBacked = {
        DatabaseType.sqlserver,
        DatabaseType.mysql,
        DatabaseType.doris,
        DatabaseType.oceanbase,
        DatabaseType.tidb,
        DatabaseType.starrocks,
        DatabaseType.mariadb,
        DatabaseType.postgresql,
        DatabaseType.clickhouse,
      };
      for (final type in gatewayBacked) {
        expect(DbServicePorts.isGatewayBacked(type), isTrue,
            reason: type.name);
        expect(ports.resolveFor(type), isA<GatewayBacking>(),
            reason: type.name);
      }
      for (final type in DatabaseType.values) {
        if (gatewayBacked.contains(type)) continue;
        expect(DbServicePorts.isGatewayBacked(type), isFalse,
            reason: type.name);
        expect(ports.resolveFor(type), isA<AdapterBacking>(),
            reason: type.name);
      }
    });
  });
}

