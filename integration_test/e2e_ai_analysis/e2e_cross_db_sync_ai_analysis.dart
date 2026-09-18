// ============================================================================
// Cross-Database E2E AI Analysis Test - MySQL → Doris 数据同步 + AI 对比
//
// 测试场景：
//   1. MySQL 数据准备
//   2. Doris 数据准备
//   3. 执行数据同步（MySQL → Doris）
//   4. AI 对比分析两数据库的数据/结构差异
//
// 环境变量：
//   DEEPSEEK_API_KEY - DeepSeek API Key（flash 版本）
//   DBMASTER_MYSQL_HOST - MySQL 主机地址
//   DBMASTER_MYSQL_PORT - MySQL 端口
//   DBMASTER_MYSQL_USER - MySQL 用户名
//   DBMASTER_MYSQL_PASSWORD - MySQL 密码
//   DBMASTER_DORIS_HOST - Doris 主机地址
//   DBMASTER_DORIS_QUERY_PORT - Doris 查询端口
//   DBMASTER_DORIS_HTTP_PORT - Doris HTTP 端口
//   DBMASTER_DORIS_USER - Doris 用户名
//   DBMASTER_DORIS_PASSWORD - Doris 密码
//
// 运行方式：
//   DEEPSEEK_API_KEY=sk-xxx flutter test integration_test/e2e_ai_analysis/e2e_cross_db_sync_ai_analysis.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/doris_adapter.dart';
import '../config/mysql_test_config.dart';
import '../config/doris_test_config.dart';
import 'e2e_ai_analysis_helper.dart';
import '../helpers/mysql_gateway_e2e_helper.dart';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady &&
        (!MySQLTestConfig.available || !DorisTestConfig.available)) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* / DBMASTER_DORIS_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 检查环境变量
  final mysqlConfigured = MySQLTestConfig.isConfigured;
  final dorisConfigured = DorisTestConfig.isConfigured;

  if (!mysqlConfigured || !dorisConfigured) {
    print('⚠️  跨库测试跳过：未配置 DBMASTER_MYSQL_HOST 或 DBMASTER_DORIS_HOST');
    return;
  }

  group('Cross-Database E2E: MySQL → Doris Sync + AI Analysis', () {
    late MySQLAdapter mysqlAdapter;
    late DorisAdapter dorisAdapter;
    late String mysqlTestDbName;
    late String dorisTestDbName;

    setUp(() async {
      mysqlTestDbName = MySQLTestConfig.generateTestDatabaseName();
      dorisTestDbName = DorisTestConfig.generateTestDatabaseName();

      mysqlAdapter = MySQLAdapter();
      dorisAdapter = DorisAdapter();
    });

    tearDown(() async {
      try {
        await mysqlAdapter.executeQuery('DROP DATABASE IF EXISTS `$mysqlTestDbName`');
        await mysqlAdapter.disconnect();
        await dorisAdapter.executeQuery('DROP DATABASE IF EXISTS `$dorisTestDbName`');
        await dorisAdapter.disconnect();
      } catch (_) {}
    });

    testWidgets('MySQL → Doris 数据同步 + AI 对比分析', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // === 1. MySQL 数据准备 ===

      final mysqlConnection = DatabaseConnection(
        id: 'mysql_cross_db_test',
        name: 'MySQL Cross DB Test',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final mysqlConnected = await mysqlAdapter.connect(mysqlConnection);
      expect(mysqlConnected, isTrue, reason: 'Failed to connect to MySQL');

      await mysqlAdapter.createDatabase(mysqlTestDbName);
      await mysqlAdapter.useDatabase(mysqlTestDbName);

      await mysqlAdapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS products (
          id INT PRIMARY KEY AUTO_INCREMENT,
          name VARCHAR(100),
          category VARCHAR(50),
          price DECIMAL(10, 2),
          stock INT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      // 插入测试数据
      for (int i = 1; i <= 100; i++) {
        final category = ['Electronics', 'Books', 'Clothing', 'Food', 'Sports'][i % 5];
        await mysqlAdapter.executeQuery("INSERT INTO products (name, category, price, stock) VALUES ('Product $i', '$category', ${i * 1.0}, ${i % 50})");
      }

      // === 2. Doris 数据准备 ===

      final dorisConnection = DatabaseConnection(
        id: 'doris_cross_db_test',
        name: 'Doris Cross DB Test',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.fePort,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final dorisConnected = await dorisAdapter.connect(dorisConnection);
      expect(dorisConnected, isTrue, reason: 'Failed to connect to Doris');

      await dorisAdapter.createDatabase(dorisTestDbName);
      await dorisAdapter.useDatabase(dorisTestDbName);

      await dorisAdapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS products (
          id INT,
          name STRING,
          category STRING,
          price DECIMAL(10, 2),
          stock INT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        PRIMARY KEY (id)
        DISTRIBUTED BY HASH(id) BUCKETS 4
        PROPERTIES ("replication_num" = "1")
      ''');

      // === 3. 执行数据同步（MySQL → Doris）===

      // 从MySQL读取数据
      final mysqlResult = await mysqlAdapter.executeQuery('SELECT * FROM products');

      // 写入Doris
      for (final row in mysqlResult.rows) {
        await dorisAdapter.executeQuery('''
          INSERT INTO products (id, name, category, price, stock, created_at)
          VALUES (${row['id']}, '${row['name']}', '${row['category']}', ${row['price']}, ${row['stock']}, '${row['created_at']})
        ''');
      }

      // === 4. AI 对比分析两个数据库的数据/结构差异 ===

      // 从两个数据库查询数据用于对比
      final mysqlData = await mysqlAdapter.executeQuery('SELECT category, COUNT(*) as count, AVG(price) as avg_price FROM products GROUP BY category');
      final dorisData = await dorisAdapter.executeQuery('SELECT category, COUNT(*) as count, AVG(price) as avg_price FROM products GROUP BY category');

      // 构建AI分析提示词
      final prompt = '''
请对比分析两个数据库的数据同步结果：

源数据库（MySQL）统计：
${mysqlData.rows.map((row) => '- ${row['category']}: ${row['count']} 件，均价 ${row['avg_price']}').join('\n')}

目标数据库（Doris）统计：
${dorisData.rows.map((row) => '- ${row['category']}: ${row['count']} 件，均价 ${row['avg_price']}').join('\n')}

请分析：
1. 数据同步是否成功？数据量是否一致？
2. 统计结果是否匹配？
3. 如果有差异，可能的原因是什么？

源数据库类型：关系型数据库 MySQL
目标数据库类型：分析型数据库 Doris (MPP)
''';

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.mysql);

      // 验证AI响应
      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue, reason: 'AI should return analysis');
      expect(aiResponse.error, isNull, reason: 'Should not have errors');

      // 验证数据同步是否成功（数量应该一致）
      final mysqlCount = await mysqlAdapter.executeQuery('SELECT COUNT(*) as total FROM products');
      final dorisCount = await dorisAdapter.executeQuery('SELECT COUNT(*) as total FROM products');

      expect(mysqlCount.rows.first['total'], equals(dorisCount.rows.first['total']),
          reason: 'MySQL and Doris should have same row count after sync');

      // 打印AI分析结果（用于验证）
      print('=== 跨数据库同步 AI 分析结果 ===');
      print(aiResponse.content);
      print('MySQL 记录数: ${mysqlCount.rows.first['total']}');
      print('Doris 记录数: ${dorisCount.rows.first['total']}');
    });
  });
}
