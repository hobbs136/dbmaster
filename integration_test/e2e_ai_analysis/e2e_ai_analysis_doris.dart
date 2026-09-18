// ============================================================================
// Doris E2E AI Analysis Test - 真实数据库 + DeepSeek AI
//
// 覆盖 6 个 AI 分析场景
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/doris_adapter.dart';
import '../config/doris_test_config.dart';
import 'e2e_ai_analysis_helper.dart';
import '../helpers/mysql_gateway_e2e_helper.dart';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !DorisTestConfig.available) {
      // ignore: avoid_print
      print('DORIS_E2E_SKIP: DBMASTER_DORIS_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Doris E2E AI Analysis', () {
    late DorisAdapter adapter;
    late String testDbName;

    setUp(() async {
      testDbName = DorisTestConfig.generateTestDatabaseName();
      adapter = DorisAdapter();
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        await adapter.disconnect();
      } catch (_) {}
    });

    testWidgets('场景1 - 基础查询 + AI 分析', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'doris_e2e_test',
        name: 'Doris E2E AI Test',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.fePort,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to Doris');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS users (
          id INT,
          name STRING,
          email STRING,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      await adapter.executeQuery('''
        INSERT INTO users (id, name, email) VALUES
        (1, 'Alice', 'alice@example.com'),
        (2, 'Bob', 'bob@example.com'),
        (3, 'Charlie', 'charlie@example.com')
      ''');

      final sql = 'SELECT * FROM users';
      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have data');

      final prompt = generateQueryAnalysisPrompt(sql, {
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows.take(3).toList(),
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.doris);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景2 - 复杂查询 + AI 分析', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'doris_e2e_scenario2',
        name: 'Doris E2E AI Test Scenario 2',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.fePort,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to Doris');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS users (
          id INT,
          name STRING,
          email STRING
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS orders (
          id INT,
          user_id INT,
          product_name STRING,
          amount DECIMAL(10, 2),
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      await adapter.executeQuery("INSERT INTO users (id, name, email) VALUES (1, 'Alice', 'alice@example.com'), (2, 'Bob', 'bob@example.com'), (3, 'Charlie', 'charlie@example.com')");

      await adapter.executeQuery("INSERT INTO orders (id, user_id, product_name, amount) VALUES (1, 1, 'Product A', 100.00), (2, 1, 'Product B', 200.00), (3, 2, 'Product C', 150.00), (4, 3, 'Product D', 300.00)");

      final sql = '''SELECT u.name, u.email, COUNT(o.id) as order_count, SUM(o.amount) as total_amount
        FROM users u
        LEFT JOIN orders o ON u.id = o.user_id
        GROUP BY u.id, u.name, u.email
        HAVING total_amount > 100
        ORDER BY total_amount DESC''';

      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'queryType': 'JOIN with aggregation',
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.doris);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景3 - DML 操作 + AI 验证', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'doris_e2e_scenario3',
        name: 'Doris E2E AI Test Scenario 3',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.fePort,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to Doris');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS accounts (
          id INT,
          name STRING,
          balance DECIMAL(10, 2) DEFAULT 0.00
        )
        UNIQUE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      await adapter.executeQuery("INSERT INTO accounts (id, name, balance) VALUES (1, 'Account A', 1000.00), (2, 'Account B', 2000.00), (3, 'Account C', 3000.00)");

      await adapter.executeQuery("UPDATE accounts SET balance = balance + 500 WHERE name = 'Account A'");

      await adapter.executeQuery("DELETE FROM accounts WHERE name = 'Account C'");

      final result = await adapter.executeQuery('SELECT * FROM accounts ORDER BY name');

      final prompt = '''
请验证以下 DML 操作的正确性：

1. INSERT：插入 3 个账户，初始余额分别为 1000, 2000, 3000
2. UPDATE：Account A 余额增加 500
3. DELETE：删除 Account C

当前数据库状态：
${result.rows.map((row) => '- ${row['name']}: ${row['balance']}').join('\n')}

请分析：操作是否正确？数据是否一致？
''';

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.doris);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景4 - 大结果集 + AI 总结', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'doris_e2e_scenario4',
        name: 'Doris E2E AI Test Scenario 4',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.fePort,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to Doris');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS products (
          id INT,
          name STRING,
          category STRING,
          price DECIMAL(10, 2),
          stock INT
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 10
        PROPERTIES ("replication_num" = "1")
      ''');

      // 批量插入
      for (int i = 1; i <= 1000; i++) {
        final category = ['Electronics', 'Books', 'Clothing', 'Food', 'Sports'][i % 5];
        final price = (i * 1.0).toStringAsFixed(2);
        final stock = i % 100;
        await adapter.executeQuery("INSERT INTO products (id, name, category, price, stock) VALUES ($i, 'Product $i', '$category', $price, $stock)");
      }

      final sql = 'SELECT category, COUNT(*) as count, AVG(price) as avg_price, SUM(stock) as total_stock FROM products GROUP BY category';
      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'totalProducts': 1000,
        'categories': queryResult.rows,
        'analysis': 'Category-wise product distribution and pricing',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.doris);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景5 - 查询历史 + AI 分析', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'doris_e2e_scenario5',
        name: 'Doris E2E AI Test Scenario 5',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.fePort,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to Doris');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS events (
          id INT,
          event_type STRING,
          event_data STRING,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      final queries = [
        'SELECT COUNT(*) FROM events',
        'SELECT event_type, COUNT(*) FROM events GROUP BY event_type',
        'SELECT * FROM events WHERE created_at >= NOW() - INTERVAL 1 HOUR',
        'SELECT event_type, MAX(created_at) FROM events GROUP BY event_type',
        'SELECT COUNT(*) FROM events WHERE event_type = \'login\'',
      ];

      final queryHistory = <Map<String, dynamic>>[];
      for (final sql in queries) {
        await adapter.executeQuery(sql);
        queryHistory.add({
          'sql': sql,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      final prompt = generateHistoryAnalysisPrompt(queryHistory);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.doris);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景6 - Schema 信息 + AI 解释', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'doris_e2e_scenario6',
        name: 'Doris E2E AI Test Scenario 6',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.fePort,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to Doris');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS customers (
          id INT,
          name STRING NOT NULL,
          email STRING,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS products (
          id INT,
          name STRING NOT NULL,
          price DECIMAL(10, 2) NOT NULL,
          category STRING
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS orders (
          id INT,
          customer_id INT NOT NULL,
          order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
          total_amount DECIMAL(10, 2)
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS order_items (
          id INT,
          order_id INT NOT NULL,
          product_id INT NOT NULL,
          quantity INT NOT NULL DEFAULT 1,
          price DECIMAL(10, 2) NOT NULL
        )
        DUPLICATE KEY(id)
        DISTRIBUTED BY HASH(id) BUCKETS 1
        PROPERTIES ("replication_num" = "1")
      ''');

      final schema = {
        'tables': ['customers', 'products', 'orders', 'order_items'],
        'relationships': ['orders → customers', 'order_items → orders', 'order_items → products'],
        'distribution': 'All tables use HASH distribution with 1 bucket',
      };

      final prompt = generateSchemaExplanationPrompt(schema);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.doris);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });
  });
}
