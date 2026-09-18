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

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dbmaster/models/tdengine_models.dart';
import 'package:dbmaster/services/adapters/tdengine_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 成功响应的 mock HTTP client（REST 形状——T29 TDengine 批次后 connect 走
/// 网关端点，此响应会被判 ok:false 而短路；守卫在 readOnly=true 时于任何
/// 请求前抛 → 不依赖网络/网关语义）。
class _OkMockClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.fromIterable([
        utf8.encode('{"code":0,"column_meta":[],"data":[],"rows":0}'),
      ]),
      200,
    );
  }
}

void main() {
  setUp(() {
    // T29 TDengine 批次：壳 connect 首行 _requireServerSession——无会话直接
    // StateError。注入 embedded 握手（同 tdengine_gateway_adapter_test）。
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

  /// 构造一个 readOnly=true 的 TDengineAdapter（网关 connect 因 REST 形状
  /// 响应短路返回 false，但 _currentConnection 已带 readOnly——守卫可发）。
  Future<TDengineAdapter> roAdapter() async {
    final adapter = TDengineAdapter(httpClient: _OkMockClient());
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
}
