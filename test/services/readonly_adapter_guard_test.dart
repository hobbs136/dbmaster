// Feature 039 T014 — adapter 自守卫单元测试。
//
// 覆盖 TDengine 专属 DDL 方法（createSuperTable/dropSuperTable/createSubTable/
// dropSubTable）：这些方法直走 `_executeSql`（不经 executeQuery 的
// guardReadOnlyQuery 兜底），必须各自首行 `guardReadOnly(operation:)`。
//
// spec 039 T014 要求：readOnly=true 触发 → 抛 ReadOnlyBlockedException；
// US1 AC8/FR-008 无实例库族的单元覆盖。
//
// 注意：SQLServer/Doris/SQLite 的 DDL 经 executeQuery → guardReadOnlyQuery
// + isWriteCommand 兜住，间接覆盖；Oracle adapter 不存在。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/tdengine_models.dart';
import 'package:dbmaster/services/adapters/ai_adapter_mixin.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/adapters/tdengine_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 网关 envelope 形状的 mock HTTP client（按路径分发，对齐
/// tdengine_gateway_adapter_test 的 fake 形状）：connect 走网关协议——
/// POST /api/gw/connections/test（草稿测试，{ok:true}）+ POST
/// /api/gw/connections（现场注册，{serverConnId}）。connect 真实成功，
/// 守卫用例在「已连接 + readOnly=true」状态下被测（守卫在方法首行抛，
/// 不触达后续查询请求）。未识别端点 500 fail-loud。
class _GatewayOkMockClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    http.StreamedResponse json(Object body, [int status = 200]) =>
        http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(body))),
          status,
          headers: const {'content-type': 'application/json'},
        );
    final path = request.url.path;
    if (path == '/api/gw/connections/test') {
      return json({'ok': true});
    }
    if (path == '/api/gw/connections') {
      return json({'serverConnId': 'srv-td-ro'});
    }
    return json({
      'error': {'code': 'X', 'message': 'unmapped endpoint'},
    }, 500);
  }
}

/// DBT-T8 R4-a mixin 面探针：isWriteCommand 为纯字面判定（不触 _adapter），
/// noSuchMethod 即可承载。
class _MixinProbe with AiAdapterMixin implements DatabaseAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('probe 只承载 isWriteCommand 字面判定');
}

void main() {
  setUp(() {
    // T29 TDengine 批次：壳 connect 首行 _requireServerSession——无会话直接
    // StateError。注入 embedded 握手（同 tdengine_gateway_adapter_test）。
    // mock prefs 供 connect 的映射查找/写回（connection_server_id_map）。
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

  /// 构造一个 readOnly=true 的 TDengineAdapter（fake 按网关 envelope 伪装
  /// ——connect 真实成功：草稿 test → 现场注册 → _currentConnection 带
  /// readOnly → 守卫可发）。
  Future<TDengineAdapter> roAdapter() async {
    final adapter = TDengineAdapter(httpClient: _GatewayOkMockClient());
    await adapter.connect(DatabaseConnection(
      id: 'td_ro',
      name: 'TD RO',
      host: 'localhost',
      port: 6041,
      type: DatabaseType.tdengine,
      username: 'root',
      password: 'taosdata',
      readOnly: true,
    ));
    return adapter;
  }

  group('TDengineAdapter 自守卫（feature 039 T014）', () {
    // —— 本批新加守卫（4 个 TDengine 专属 DDL）——

    test('createSuperTable 在只读连接上被拒', () async {
      final adapter = await roAdapter();
      expect(
        () => adapter.createSuperTable(
          name: 'meters',
          columns: [TdColumn(name: 'ts', type: 'TIMESTAMP')],
          tags: [TdTag(name: 'location', type: 'NCHAR', length: 64)],
        ),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('dropSuperTable 在只读连接上被拒', () async {
      final adapter = await roAdapter();
      expect(
        () => adapter.dropSuperTable('meters'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('createSubTable 在只读连接上被拒', () async {
      final adapter = await roAdapter();
      expect(
        () => adapter.createSubTable(
          name: 'd1001',
          superTableName: 'meters',
          tagValues: {'location': 'Beijing'},
        ),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('dropSubTable 在只读连接上被拒', () async {
      final adapter = await roAdapter();
      expect(
        () => adapter.dropSubTable('d1001'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    // —— 既有守卫回归（确认本次改动不破坏 T012 早期守卫）——

    test('dropTable 既有守卫仍生效（回归）', () async {
      final adapter = await roAdapter();
      expect(
        () => adapter.dropTable('d1001'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });
  });

  // ── DBT-T8 R4-a（security P2-1）：readonly 关键字面维护命令补齐 ──────────
  // 服务层（database_service `_isWriteQuery`，经 :3417 只读闸门消费）与
  // adapter 层（AiAdapterMixin.isWriteCommand，guardReadOnlyQuery 消费）
  // 双层 fail-closed：只读连接上维护命令（VACUUM/REINDEX/ANALYZE/OPTIMIZE）
  // = 拒绝。NoSQL override（Redis/Mongo）不在面内，基类改动仅作用 SQL 族。

  group('AiAdapterMixin.isWriteCommand 维护命令关键字（R4-a mixin 面）', () {
    final probe = _MixinProbe();

    test('VACUUM 前缀语句被判定为写', () {
      expect(probe.isWriteCommand('VACUUM t'), isTrue);
      expect(probe.isWriteCommand('vacuum "t"'), isTrue);
    });

    test('REINDEX 前缀语句被判定为写', () {
      expect(probe.isWriteCommand('REINDEX TABLE t'), isTrue);
    });

    test('ANALYZE 前缀语句被判定为写', () {
      expect(probe.isWriteCommand('ANALYZE t'), isTrue);
    });

    test('OPTIMIZE 前缀语句被判定为写', () {
      expect(probe.isWriteCommand('OPTIMIZE TABLE t'), isTrue);
    });

    test('只读语句不误判（SELECT/EXPLAIN/PRAGMA 读形态边界锚定）', () {
      expect(probe.isWriteCommand('SELECT 1'), isFalse);
      expect(probe.isWriteCommand('  SELECT * FROM t'), isFalse);
      // PRAGMA 读形态 = R4-a 评估结论的边界锚定：PRAGMA 写形态不可靠判别，
      // 整族不纳入关键字面（详见两处关键字面旁注释与任务回报）。
      expect(probe.isWriteCommand('PRAGMA user_version'), isFalse);
      expect(probe.isWriteCommand('PRAGMA table_info(t)'), isFalse);
    });
  });

  group('DatabaseService 只读闸门维护命令拦截（R4-a service 面，真 SQLite 库）',
      () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ServerConnection.resetForTesting();
      tempDir = await Directory.systemTemp.createTemp('dbt_t8_ro_gate');
      dbPath = '${tempDir.path}${Platform.pathSeparator}gate.db';
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    /// 注册 readOnly=true 的 sqlite 连接（真临时文件库）——service 闸门
    /// （executeQueryDetailed 首段 `server.readOnly && _isWriteQuery`）的
    /// 集成断言面；跨库型覆盖按任务书用 SQLite 本地文件真库（无需 WSL）。
    Future<DatabaseService> roService(String connectionId) async {
      final service = DatabaseService();
      final adapter = SQLiteAdapter();
      await adapter.connect(
        DatabaseConnection(
          id: connectionId,
          name: 'RO Gate',
          host: dbPath,
          port: 0,
          type: DatabaseType.sqlite,
          username: '',
          password: '',
          readOnly: true,
        ),
      );
      service.registerConnectedServerForTest(
        DbServer(
          id: connectionId,
          name: 'RO Gate',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          readOnly: true,
        ),
      );
      service.registerConnectedAdapterForTest(connectionId, adapter);
      return service;
    }

    test('VACUUM / REINDEX / ANALYZE 在只读连接上被 service 闸门拒绝', () async {
      final service = await roService('ro_gate');
      for (final sql in [
        'VACUUM',
        'REINDEX t',
        'ANALYZE',
      ]) {
        await expectLater(
          service.executeQuery(sql, connectionId: 'ro_gate'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('只读模式下禁止执行修改操作'),
            ),
          ),
          reason: '"$sql" 应被只读闸门拦截',
        );
      }
    });

    test('OPTIMIZE TABLE 同被拒绝（跨库型关键字面统一）', () async {
      final service = await roService('ro_gate');
      await expectLater(
        service.executeQuery('OPTIMIZE TABLE t', connectionId: 'ro_gate'),
        throwsA(isA<Exception>()),
      );
    });

    test('只读连接上 SELECT 正常放行（闸门不误杀读路径）', () async {
      final service = await roService('ro_gate');
      final rows = await service.executeQuery(
        'SELECT 1 AS one',
        connectionId: 'ro_gate',
      );
      expect(rows, isNotEmpty);
    });
  });
}
