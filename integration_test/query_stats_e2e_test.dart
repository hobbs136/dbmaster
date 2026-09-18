// reports-M1（#29）· 慢查询捕获 + 读端点 embedded 真库 E2E。
//
// 全链路（embedded 主场景）：embedded server（隔离数据目录）→ 注册 MySQL
// 真库连接（gw vault）→ 经 /api/db/:id/query 执行慢查询（SLEEP）→
// QueryStatsApiService 轮询 summary 直到捕获可见 → 断言聚合与明细（明文
// 默认开启）。embedded 二进制不可得时整组以 QS_E2E_SKIP 跳过（无假绿）。
//
// 运行（Windows，server exe 由 cargo build 产出）：
// ```sh
// DBMASTER_SERVER_BIN=<dbmaster-server>/target/debug/dbmaster-server.exe \
// flutter test integration_test/query_stats_e2e_test.dart
// ```

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/query_stats_models.dart';
import 'package:dbmaster/services/query_stats_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

import 'config/mysql_test_config.dart';
import 'helpers/query_stats_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  var gatewayReady = false;
  setUpAll(() async {
    gatewayReady = await ensureEmbeddedServerForQueryStatsE2E();
    if (gatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      gatewayReady = false;
    }
  });

  testWidgets('slow query via embedded server is captured and readable',
      (tester) async {
    if (!gatewayReady) return;

    final conn = ServerConnection();
    final baseUrl = conn.serverUrl!;
    final token = await conn.getAccessToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    // ── 注册 MySQL 真库连接（gw vault，与网关适配器同注册面）──
    final reg = await http.post(
      Uri.parse('$baseUrl/api/gw/connections'),
      headers: headers,
      body: jsonEncode({
        'name': 'qs-e2e-embedded',
        'dbType': 'mysql',
        'host': MySQLTestConfig.host,
        'port': MySQLTestConfig.port,
        'username': MySQLTestConfig.username,
        'password': MySQLTestConfig.password,
      }),
    );
    expect(reg.statusCode, anyOf(200, 201),
        reason: 'gw register failed: ${reg.body}');
    // gw 注册返回 {"serverConnId": id}（非信封形状）。
    final connId =
        (jsonDecode(reg.body) as Map<String, dynamic>)['serverConnId']
            as String;

    try {
      // ── 慢查询（同步路径，embedded 数据面）──
      final q = await http.post(
        Uri.parse('$baseUrl/api/db/$connId/query'),
        headers: headers,
        body: jsonEncode({'sql': 'SELECT SLEEP(1.5)', 'limit': 10}),
      );
      expect(q.statusCode, 200, reason: 'query failed: ${q.body}');
      // /api/db/:id/query 响应是 {ok, data:{...含 executionTimeMs}, error} 信封。
      final qBody = jsonDecode(q.body) as Map<String, dynamic>;
      final qData = qBody['data'] as Map<String, dynamic>;
      final elapsed = qData['executionTimeMs'];
      expect((elapsed as num) >= 1500, isTrue);

      // ── 轮询 summary 直到捕获可见（fire-and-forget spawn 异步窗口）──
      final api = QueryStatsApiService();
      QueryStatsSummary? summary;
      for (var i = 0; i < 100; i++) {
        final s = await api.fetchSummary(window: QueryStatsWindow.week);
        if (s.items.any((e) => e.digest == 'SELECT SLEEP(?)')) {
          summary = s;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(summary, isNotNull, reason: '捕获超时未出现在 summary');
      final item = summary!.items
          .firstWhere((e) => e.digest == 'SELECT SLEEP(?)');
      expect(item.dbKind, 'mysql');
      expect(item.count, greaterThanOrEqualTo(1));
      expect(item.totalMs, greaterThanOrEqualTo(1500));
      expect(item.sampleSqlText, contains('SLEEP'));

      // ── 明细下钻（明文默认开启）──
      final page = await api.fetchDetail(
        window: QueryStatsWindow.week,
        connId: connId,
        digest: item.digest,
      );
      expect(page.items, isNotEmpty);
      final row = page.items.first;
      expect(row.entry, 'sync_query');
      expect(row.sqlText, contains('SLEEP'));
      expect(row.source, 'gateway');

      // ── 口径 meta（UI 横幅数据源）──
      expect(summary.meta.thresholdMs, 1000);
      expect(summary.meta.storeSql, isTrue);
    } finally {
      // 清理：删除测试连接（隔离数据目录随 stop 自动清理）。
      await http.delete(
        Uri.parse('$baseUrl/api/gw/connections/$connId'),
        headers: headers,
      );
    }
  });
}
