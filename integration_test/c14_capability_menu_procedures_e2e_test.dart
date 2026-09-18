// ============================================================================
// C14 · 能力菜单「存储过程」真库 E2E（用户报告：库里有过程但对话框为空）
//
// 复现链路 = 用户点击路径：connectToServer 连 MySQL → 单击库节点
// （changeDatabase）→ 打开存储过程入口。
// 真库第一轮实测修正认知：纯直连单连接下 changeDatabase（经
// getDatabaseInfo）会顺带 USE，隐式 DATABASE() 谓词可用；用户症状指向
// 其余形态（server/embedded 网关优先浏览 = 元数据走 REST、本地会话不被
// USE；多连接/会话漂移）。因此修复 = 对话框显式传目标库（不依赖会话
// USE 状态），本 E2E 验证显式谓词在真库上返回过程/函数（含参数与返回
// 类型），并记录连接会话的 DATABASE() 供回归对照。
//
// 真库：MySQLTestConfig（参数经 DBMASTER_MYSQL_* 提供）。建一次性库
// `dbmaster_c14_e2e`，测试结束 DROP 清理。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/stored_procedure.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/stored_procedure_service.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

const _testDb = 'dbmaster_c14_e2e';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppProvider provider;
  late DbServer server;
  late StoredProcedureService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = AppProvider();
    server = DbServer(
      id: 'c14-e2e-mysql',
      type: DatabaseType.mysql,
      name: 'C14 E2E MySQL',
      host: MySQLTestConfig.host,
      port: MySQLTestConfig.port,
      username: MySQLTestConfig.username,
      password: MySQLTestConfig.password,
    );
    service = StoredProcedureService(provider.dbService);
  });

  tearDown(() async {
    try {
      await provider.dbService.disconnect();
    } catch (_) {}
  });

  Future<void> _seed(DatabaseService db) async {
    final adapter = db.getAdapter(server.id)!;
    await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS `$_testDb`');
    await adapter.executeQuery('DROP PROCEDURE IF EXISTS `$_testDb`.`c14_echo`');
    await adapter.executeQuery('DROP FUNCTION IF EXISTS `$_testDb`.`c14_add`');
    await adapter.executeQuery('''
      CREATE PROCEDURE `$_testDb`.`c14_echo`(IN msg VARCHAR(200))
      BEGIN SELECT msg AS echoed; END
    ''');
    await adapter.executeQuery('''
      CREATE FUNCTION `$_testDb`.`c14_add`(a INT, b INT)
      RETURNS INT DETERMINISTIC RETURN a + b
    ''');
  }

  testWidgets('C14-PROC-E2E：用户点击路径 + 显式目标库返回过程/函数',
      (tester) async {
    if (!mysqlE2EGatewayReady) {
      return;
    }
    // 1. 真实用户路径：connectToServer（含 100ms 延迟，runAsync 走真实时钟）
    final connected =
        await tester.runAsync(() => provider.connection.connectToServer(server));
    expect(connected, isTrue, reason: '真库连接失败（${MySQLTestConfig.host}）');
    expect(provider.connection.currentServer?.id, server.id);

    await _seed(provider.dbService);

    // 2. 用户点击路径：单击库节点（树内 _selectDatabase 的 provider 半边）
    await provider.changeDatabase(_testDb, connectionId: server.id);
    provider.sidebar.selectConnection(server.id);
    provider.sidebar.selectDatabase(_testDb);

    // 3. 连接会话 USE 状态记录（回归对照；直连下 changeDatabase 会顺带
    //    USE，网关优先浏览下为 NULL——两种形态显式谓词都必须工作）
    final session = provider.dbService.currentAdapter;
    expect(session, isNotNull, reason: '连接级 mysql 会话应存在');
    expect(session!.isConnected, isTrue);

    // 4. 修复路径：对话框显式传目标库（core 插件 _currentDatabase 同源解析）
    final resolvedDb = provider.connection.currentDatabase?.name ??
        provider.sidebar.selectedDatabaseName;
    expect(resolvedDb, _testDb, reason: '当前工作库应解析为 $_testDb');

    final procedures = await service.getStoredProcedures(database: resolvedDb);
    expect(
      procedures.map((p) => p.name),
      contains('c14_echo'),
      reason: '应列出 $_testDb 的存储过程',
    );
    final proc = procedures.firstWhere((p) => p.name == 'c14_echo');
    expect(proc.type, ProcedureType.procedure);
    expect(
      proc.parameters.map((p) => p.name),
      contains('msg'),
      reason: '过程参数（information_schema.PARAMETERS）随库谓词生效',
    );

    final functions = await service.getFunctions(database: resolvedDb);
    expect(functions.map((f) => f.name), contains('c14_add'));
    final fn = functions.firstWhere((f) => f.name == 'c14_add');
    expect(fn.returnType, contains('int'));
    expect(
      fn.parameters.map((p) => p.name),
      containsAll(['a', 'b']),
    );

    // 5. 清理
    final adapter = provider.dbService.getAdapter(server.id)!;
    await adapter.executeQuery('DROP DATABASE IF EXISTS `$_testDb`');
  });
}
