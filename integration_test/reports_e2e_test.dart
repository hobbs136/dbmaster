// reports-M2（#29）· 周报 embedded 真库 E2E。
//
// 全链路（embedded 主场景）：embedded server（隔离数据目录）→ 注册 MySQL
// 真库 → 慢查询捕获（M1 链路）→ POST /api/reports/generate（手动触发）→
// 报告中心读路径（listReports/getReport）断言 content v1 形状与聚合数值。
// embedded 二进制不可得时整组以 QS_E2E_SKIP 跳过（无假绿）。
//
// 运行（Windows，server exe 由 cargo build 产出）：
// ```sh
// DBMASTER_SERVER_BIN=<dbmaster-server>/target/debug/dbmaster-server.exe \
// flutter test -d windows integration_test/reports_e2e_test.dart
// ```

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/report_models.dart';
import 'package:dbmaster/services/reports_api_service.dart';
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

  testWidgets('capture → generate → reports hub roundtrip (embedded)',
      (tester) async {
    if (!gatewayReady) return;

    final conn = ServerConnection();
    final baseUrl = conn.serverUrl!;
    final token = await conn.getAccessToken();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    // ── 注册 MySQL 真库连接 ──
    final reg = await http.post(
      Uri.parse('$baseUrl/api/gw/connections'),
      headers: headers,
      body: jsonEncode({
        'name': 'rep-e2e-embedded',
        'dbType': 'mysql',
        'host': MySQLTestConfig.host,
        'port': MySQLTestConfig.port,
        'username': MySQLTestConfig.username,
        'password': MySQLTestConfig.password,
      }),
    );
    expect(reg.statusCode, anyOf(200, 201), reason: 'gw register: ${reg.body}');
    final connId =
        (jsonDecode(reg.body) as Map<String, dynamic>)['serverConnId'] as String;

    try {
      // ── 慢查询（M1 捕获链路）──
      final q = await http.post(
        Uri.parse('$baseUrl/api/db/$connId/query'),
        headers: headers,
        body: jsonEncode({'sql': 'SELECT SLEEP(1.5)', 'limit': 10}),
      );
      expect(q.statusCode, 200, reason: 'query: ${q.body}');

      // ── 手动生成周报（幂等：第二次 created=false）──
      final reports = ReportsApiService();
      final g1 = await reports.generateWeekly();
      expect(g1.created, isTrue);
      final g2 = await reports.generateWeekly();
      expect(g2.created, isFalse);
      expect(g2.id, g1.id);

      // ── 报告中心列表 + 类型过滤 ──
      final page = await reports.listReports(reportType: 'slow_query_weekly');
      expect(page.total, 1);
      expect(page.items, hasLength(1));
      final row = page.items.first;
      expect(row.id, g1.id);
      expect(row.taskId, isNull);
      expect(row.title, contains('W'));

      // ── typed content：捕获样本计入聚合 ──
      final report = await reports.getReport(g1.id);
      final typed = SlowQueryWeeklyReport.fromDecoded(report.contentDecoded!);
      expect(typed, isNotNull);
      expect(typed!.contentVersion, 1);
      expect(typed.summary.totalSamples, greaterThanOrEqualTo(1));
      expect(typed.summary.totalMs, greaterThanOrEqualTo(1500));
      expect(
        typed.top.any((t) => t.digest == 'SELECT SLEEP(?)'),
        isTrue,
        reason: '捕获的 SLEEP digest 应进 Top 列表: ${typed.top.map((t) => t.digest)}',
      );
      expect(typed.byConnection, isNotEmpty);
      expect(typed.byDay, isNotEmpty);
    } finally {
      await http.delete(
        Uri.parse('$baseUrl/api/gw/connections/$connId'),
        headers: headers,
      );
    }
  });
}
