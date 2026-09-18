// ============================================================================
// #30 SS-TIMEOUT-301 结案守卫（live E2E · T28 网关链路）。
// ----------------------------------------------------------------------------
// 原 FFI live 守卫（test/services/adapters/sqlserver_golden_disconnect_test.dart）
// 随 FFI/sybdb 整体下线删除。本文件是其网关语义后继：
// - SS-TIMEOUT-301：WAITFOR 35s vs 连接级 timeout 30s → 必须以
//   SqlServerGatewayException(TIMEOUT) 上抛（FFI 版缺陷：dbsettime 被多连接
//   覆盖 → 超时静默成功）。server 侧 statement_timeout 语义已在 T28 server
//   半边验证（sys.dm_exec_requests 零残留）；此处锁客户端壳层不复发。
// - 断连语义：网关注册被 server 侧删除后，后续查询 NOT_FOUND 上抛并触发
//   onDisconnect（替代原「KILL 会话后 FFI 死连接触发回调」场景）。
//
// 前置：embedded dbmaster-server（DBMASTER_SERVER_BIN）+ 测试库
// 真实 SQL Server 可达（DBMASTER_SQLSERVER_* 提供）；缺任一则以可 grep 的 SQLSERVER_E2E_SKIP 跳过。
// ============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'config/sqlserver_test_config.dart';
import 'helpers/ss_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool ssE2EGatewayReady = false;
  setUpAll(() async {
    ssE2EGatewayReady = await ensureEmbeddedServerForSsE2E();
    if (ssE2EGatewayReady && !SQLServerTestConfig.available) {
      // ignore: avoid_print
      print('SS_E2E_SKIP: DBMASTER_SQLSERVER_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      ssE2EGatewayReady = false;
    }
  });

  testWidgets('SS-TIMEOUT-301: gateway statement_timeout aborts WAITFOR (not silent success)', (tester) async {
    if (!ssE2EGatewayReady) {
      return;
    }
    final adapter = SqlServerAdapter();
    final connection = DatabaseConnection(
      id: 'ss_gw_timeout',
      name: 'ss_gw_timeout',
      type: DatabaseType.sqlserver,
      host: SQLServerTestConfig.host,
      port: SQLServerTestConfig.port,
      username: SQLServerTestConfig.username,
      password: SQLServerTestConfig.password,
      database: 'master',
      // 连接级 30s 超时（extra['timeout'] → 网关 timeoutMs；与 FFI 版同源）。
      extra: const {'timeout': 30},
    );

    try {
      await adapter.connect(connection);
    } catch (e) {
      // ignore: avoid_print
      print('SQLSERVER_E2E_SKIP: SS-TIMEOUT-301 — connect failed: $e');
      return;
    }

    try {
      final watch = Stopwatch()..start();
      Object? error;
      try {
        // 60s 服务器端等待 vs 30s 超时：server statement_timeout 中断并以
        // error(TIMEOUT) 事件返回 → 壳上抛。FFI 版在同场景静默成功（缺陷）。
        // 注：测试库虚机时钟比本机快 ~19%——WAITFOR 按
        // 虚机钟到期时真实仅过 ~84% 时长，35s 组合实际等不满 30s 真实超时
        // （实测 29.4s 正常完成）。取 60s 保漂移下余量（实测漂移下 ~50s
        // 仍 > 30s deadline）。
        await adapter.executeQuery('WAITFOR DELAY \'00:01:00\'');
      } catch (e) {
        error = e;
      }
      watch.stop();

      expect(
        error,
        isA<SqlServerGatewayException>()
            .having((e) => e.code, 'code', 'TIMEOUT'),
        reason: 'WAITFOR 60s with 30s timeout must throw TIMEOUT, not run to '
            'success; elapsed=${watch.elapsed}',
      );
      // 超时应在 ~30s 附近（钳制带宽 25-60s，同原守卫口径）。
      expect(
        watch.elapsed.inSeconds,
        inInclusiveRange(25, 60),
        reason: 'abort should happen near the 30s timeout, took ${watch.elapsed}',
      );
    } finally {
      try {
        await adapter.disconnect();
      } catch (_) {}
    }
  });

  testWidgets('SS-GW-DISC: gateway NOT_FOUND fires onDisconnect', (tester) async {
    if (!ssE2EGatewayReady) {
      return;
    }
    final adapter = SqlServerAdapter();
    final connection = DatabaseConnection(
      id: 'ss_gw_disc',
      name: 'ss_gw_disc',
      type: DatabaseType.sqlserver,
      host: SQLServerTestConfig.host,
      port: SQLServerTestConfig.port,
      username: SQLServerTestConfig.username,
      password: SQLServerTestConfig.password,
      database: 'master',
    );

    try {
      await adapter.connect(connection);
    } catch (e) {
      // ignore: avoid_print
      print('SQLSERVER_E2E_SKIP: SS-GW-DISC — connect failed: $e');
      return;
    }

    var fired = false;
    adapter.onDisconnect = () => fired = true;

    try {
      // server 侧删除注册（等价原场景的「外部 KILL 会话」——底层资源消失）。
      final conn = ServerConnection();
      final token = await conn.getAccessToken();
      final headers = {
        if (token != null) 'Authorization': 'Bearer $token',
      };
      // 经注册列表反查本连接注册 id（connect 用 connection.name 注册）。
      final listResp = await http
          .get(Uri.parse('${conn.serverUrl}/api/gw/connections'), headers: headers)
          .timeout(const Duration(seconds: 15));
      expect(listResp.statusCode, 200);
      String? targetId;
      for (final row in (jsonDecode(listResp.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()) {
        if (row['name'] == 'ss_gw_disc') targetId = row['id'] as String?;
      }
      expect(targetId, isNotNull, reason: 'connect 应已在网关注册本连接');

      final delResp = await http.delete(
        Uri.parse('${conn.serverUrl}/api/gw/connections/$targetId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      expect(delResp.statusCode, anyOf(200, 204));

      // 后续查询：NOT_FOUND 上抛 + onDisconnect 触发。
      Object? error;
      try {
        await adapter.executeQuery('SELECT 1 AS x');
      } catch (e) {
        error = e;
      }
      expect(
        error,
        isA<SqlServerGatewayException>()
            .having((e) => e.code, 'code', 'NOT_FOUND'),
      );
      await Future.delayed(const Duration(milliseconds: 300));
      expect(fired, isTrue, reason: 'onDisconnect must fire when the gateway '
          'registration is gone');
    } finally {
      try {
        await adapter.disconnect();
      } catch (_) {}
    }
  });
}
