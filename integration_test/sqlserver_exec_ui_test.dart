// ============================================================================
// SQL Server EXEC-error UI-pipeline integration test
//
// 验证 EXEC 报错修复（feature 024 follow-up / 2026-07-15）：
//   运行一个会报错的存储过程（缺必填参数，服务器 error 201 / severity 16）时：
//   1. 不得断开连接（dbdead 探活替代字符串匹配误判）
//   2. 错误消息须含服务器正文（message handler 捕获），不再只剩通用「执行查询失败」
//   3. 连接仍可用（后续查询正常返回）
//
// 走 Run 按钮的真实 UI 管线：AppProvider.tab.executeCurrentQuery() → TabProvider →
// DatabaseService（DML 拦截器）→ SqlServerAdapter → FFI → message handler →
// ExecutionResult(errorMessage)。即「点 Run 后错误如何落到结果区」的完整代码路径。
//
// 为何无头（不 pump DbmasterApp）：DbmasterApp 的 build 会创建
// PurchaseProvider()..initialize()（main.dart:59），其 in_app_purchase Pigeon 通道
// 在 flutter_tester 里挂起。修复的 bug 在 adapter/管线层，不在 widget 渲染层
// （errorMessage 渲染即 Text(errorMessage)，非 bug 所在），故无头驱动管线即可覆盖。
//
// 运行：flutter test integration_test/sqlserver_exec_ui_test.dart -d windows
// 注意：flutter test 为 JIT，message handler 正常触发；release AOT 的回调行为另由
// 手动构建验证（见内部 bug 记录）。
// ============================================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'config/sqlserver_test_config.dart';
import 'helpers/ss_gateway_e2e_helper.dart';

// T28：SS 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
// 二进制不可得时全组以可 grep 的 SQLSERVER_E2E_SKIP 跳过（无假绿）。
void main() {
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

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SQL Server EXEC error (UI pipeline)', () {
    late SqlServerAdapter setupAdapter;
    late AppProvider appProvider;
    late String testDbName;
    const procName = 'p_needparam_ui';

    setUp(() async {
      // 独立 adapter 做 setup：建隔离 test DB + 带必填参数的 proc。
      // 绕过 app 的 DML/DDL 拦截器（CREATE PROCEDURE 会触发 DDL 确认）。
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      setupAdapter = SqlServerAdapter();
      final conn = DatabaseConnection(
        id: 'ss_exec_ui_setup',
        name: 'ss_exec_ui_setup',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );
      await setupAdapter.connect(conn);
      await setupAdapter.createDatabase(testDbName);
      await setupAdapter.useDatabase(testDbName);
      await setupAdapter.executeQuery(
        'CREATE PROCEDURE $procName @x int AS BEGIN SELECT @x AS v; END',
      );

      // 无头 AppProvider：不 pump DbmasterApp（避开 purchase Pigeon 挂起），
      // 直接构造走真实 UI 管线。
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
    });

    tearDown(() async {
      try {
        await appProvider.disconnectConnection();
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
      // 切回 master 再 DROP test DB，最后断开 setup adapter
      try {
        await setupAdapter.useDatabase('master');
        await setupAdapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
      } catch (_) {}
      try {
        await setupAdapter.disconnect();
      } catch (_) {}
    });

    testWidgets(
      'failing EXEC keeps connection alive & surfaces server error',
      (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
        // 最小 pump 仅满足 binding；AppProvider 不在 widget 树中，直接驱动。
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        );

        // app 连到 setup 已建好的 test DB（proc 所在库）
        final server = DbServer(
          id: 'ss_exec_ui',
          name: 'SS EXEC UI',
          type: DatabaseType.sqlserver,
          host: SQLServerTestConfig.host,
          port: SQLServerTestConfig.port,
          username: SQLServerTestConfig.username,
          password: SQLServerTestConfig.password,
          database: testDbName,
        );
        await appProvider.connection.saveConnection(server);
        final connected = await appProvider.connectToServer(server);
        expect(connected, isTrue, reason: 'app 应连上 test DB');
        await tester.pump(const Duration(seconds: 1));

        // 不带必填参数 EXEC → 服务器 error 201。
        // 用 overrideSql + 显式 connectionId/databaseName 自包含驱动（不依赖 tab.sql）。
        final results = await appProvider.tab.executeCurrentQuery(
          overrideSql: 'EXEC $procName',
          connectionId: server.id,
          databaseName: testDbName,
        );
        await tester.pump();

        expect(results, hasLength(1));
        expect(results.first.success, isFalse, reason: '缺参数 EXEC 应失败');

        // 修复不变量 1：错误消息须含服务器正文（过程名），
        // 不再只剩通用「执行查询失败」（message handler 捕获生效）
        expect(
          results.first.errorMessage.toString(),
          contains(procName),
          reason: '应浮现服务器错误详情，而非光秃秃的通用消息',
        );

        // 修复不变量 2：SQL 错误不得撕掉连接
        expect(
          appProvider.dbService.isConnected,
          isTrue,
          reason: '服务器侧 SQL 错误不得断开连接',
        );

        // 修复不变量 3：连接仍可用——后续查询正常返回
        final followUp = await appProvider.tab.executeCurrentQuery(
          overrideSql: 'SELECT 1 AS ok',
          connectionId: server.id,
          databaseName: testDbName,
        );
        await tester.pump();
        expect(
          followUp.first.success,
          isTrue,
          reason: '失败 EXEC 后连接须仍可用',
        );
        expect(followUp.first.data!.first['ok'].toString(), '1');
      },
      // 防御：若管线意外挂起（如 purchase/secure-storage），显式超时失败而非永久挂起
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
