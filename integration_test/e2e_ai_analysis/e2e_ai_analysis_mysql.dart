// ============================================================================
// MySQL E2E AI Analysis Test - 真实数据库 + DeepSeek AI
//
// 覆盖 6 个 AI 分析场景：
//   1. 基础查询 + AI 分析
//   2. 复杂查询（JOIN/子查询/视图）+ AI 分析
//   3. DML 操作 + AI 验证
//   4. 大结果集（1000+ 行）+ AI 总结
//   5. 查询历史 + AI 分析
//   6. Schema 信息 + AI 解释
//
// 环境变量：
//   DEEPSEEK_API_KEY - DeepSeek API Key（flash 版本）
//   DBMASTER_MYSQL_HOST - MySQL 主机地址
//   DBMASTER_MYSQL_PORT - MySQL 端口
//   DBMASTER_MYSQL_USER - MySQL 用户名
//   DBMASTER_MYSQL_PASSWORD - MySQL 密码
//
// 运行方式：
//   DEEPSEEK_API_KEY=sk-xxx flutter test integration_test/e2e_ai_analysis/e2e_ai_analysis_mysql.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import '../config/mysql_test_config.dart';
import 'e2e_ai_analysis_helper.dart';
import '../helpers/mysql_gateway_e2e_helper.dart';

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

  // ==========================================================================
  // 测试组：MySQL AI 分析 E2E
  // ==========================================================================

  group('MySQL E2E AI Analysis', () {
    late MySQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      // 生成唯一测试数据库名
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      adapter = MySQLAdapter();
    });

    tearDown(() async {
      try {
        // 清理：删除测试数据库并断开连接
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        await adapter.disconnect();
      } catch (_) {
        // 忽略清理错误
      }
    });

    // ==========================================================================
    // 场景 1：基础查询 + AI 分析
    // ==========================================================================

    testWidgets('场景1 - 基础查询 + AI 分析', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // 1. 初始化 adapter 并连接 MySQL
      final connection = DatabaseConnection(
        id: 'mysql_e2e_test',
        name: 'MySQL E2E AI Test',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');

      // 2. 创建测试数据库和表
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS users (
          id INT PRIMARY KEY AUTO_INCREMENT,
          name VARCHAR(100),
          email VARCHAR(100),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await adapter.executeQuery('''
        INSERT INTO users (name, email) VALUES
        ('Alice', 'alice@example.com'),
        ('Bob', 'bob@example.com'),
        ('Charlie', 'charlie@example.com')
      ''');

      // === 场景 1：基础查询 + AI 分析 ===

      // 3. 执行基础查询
      final sql = 'SELECT * FROM users';
      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have data');
      expect(queryResult.columns.length, equals(4), reason: 'Should have 4 columns');

      // 4. 调用 DeepSeek API 分析查询结果
      final prompt = generateQueryAnalysisPrompt(sql, {
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows.take(3).toList(),
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.mysql);

      // 5. 验证 AI 响应
      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue, reason: 'AI should return analysis');
      expect(aiResponse.content.contains('查询'), isTrue, reason: 'AI should mention query');
      expect(aiResponse.error, isNull, reason: 'Should not have errors');
    });

    // ==========================================================================
    // 场景 2：复杂查询（JOIN/子查询/视图）+ AI 分析
    // ==========================================================================

    testWidgets('场景2 - 复杂查询 + AI 分析', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'mysql_e2e_scenario2',
        name: 'MySQL E2E AI Test Scenario 2',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      // 创建多表结构
      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS users (
          id INT PRIMARY KEY AUTO_INCREMENT,
          name VARCHAR(100),
          email VARCHAR(100)
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS orders (
          id INT PRIMARY KEY AUTO_INCREMENT,
          user_id INT,
          product_name VARCHAR(100),
          amount DECIMAL(10, 2),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users(id)
        )
      ''');

      // 插入测试数据
      await adapter.executeQuery('''
        INSERT INTO users (id, name, email) VALUES
        (1, 'Alice', 'alice@example.com'),
        (2, 'Bob', 'bob@example.com'),
        (3, 'Charlie', 'charlie@example.com')
      ''');

      await adapter.executeQuery('''
        INSERT INTO orders (user_id, product_name, amount) VALUES
        (1, 'Product A', 100.00),
        (1, 'Product B', 200.00),
        (2, 'Product C', 150.00),
        (3, 'Product D', 300.00)
      ''');

      // 执行复杂 JOIN 查询
      final sql = '''
        SELECT u.name, u.email, COUNT(o.id) as order_count, SUM(o.amount) as total_amount
        FROM users u
        LEFT JOIN orders o ON u.id = o.user_id
        GROUP BY u.id
        HAVING total_amount > 100
        ORDER BY total_amount DESC
      ''';

      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have aggregated data');

      // 调用 DeepSeek API 分析复杂查询
      final prompt = generateQueryAnalysisPrompt(sql, {
        'queryType': 'JOIN with aggregation',
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.mysql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    // ==========================================================================
    // 场景 3：DML 操作 + AI 验证
    // ==========================================================================

    testWidgets('场景3 - DML 操作 + AI 验证', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'mysql_e2e_scenario3',
        name: 'MySQL E2E AI Test Scenario 3',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      // 创建表
      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS accounts (
          id INT PRIMARY KEY AUTO_INCREMENT,
          name VARCHAR(100),
          balance DECIMAL(10, 2) DEFAULT 0.00
        )
      ''');

      // INSERT
      await adapter.executeQuery('''
        INSERT INTO accounts (name, balance) VALUES
        ('Account A', 1000.00),
        ('Account B', 2000.00),
        ('Account C', 3000.00)
      ''');

      // UPDATE
      await adapter.executeQuery('''
        UPDATE accounts SET balance = balance + 500 WHERE name = 'Account A'
      ''');

      // DELETE
      await adapter.executeQuery('''DELETE FROM accounts WHERE name = 'Account C' ''');

      // 验证结果
      final result = await adapter.executeQuery('SELECT * FROM accounts ORDER BY name');
      expect(result.rows.length, equals(2), reason: 'Should have 2 accounts after delete');

      // 调用 DeepSeek API 验证 DML 操作
      final prompt = '''
请验证以下 DML 操作的正确性：

1. INSERT：插入 3 个账户，初始余额分别为 1000, 2000, 3000
2. UPDATE：Account A 余额增加 500
3. DELETE：删除 Account C

当前数据库状态：
${result.rows.map((row) => '- ${row['name']}: ${row['balance']}').join('\n')}

请分析：操作是否正确？数据是否一致？
''';

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.mysql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    // ==========================================================================
    // 场景 4：大结果集（1000+ 行）+ AI 总结
    // ==========================================================================

    testWidgets('场景4 - 大结果集 + AI 总结', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'mysql_e2e_scenario4',
        name: 'MySQL E2E AI Test Scenario 4',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      // 创建表
      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS products (
          id INT PRIMARY KEY AUTO_INCREMENT,
          name VARCHAR(100),
          category VARCHAR(50),
          price DECIMAL(10, 2),
          stock INT
        )
      ''');

      // 批量插入数据（使用存储过程加速）
      await adapter.executeQuery('DROP PROCEDURE IF EXISTS insert_products');
      await adapter.executeQuery('''
        CREATE PROCEDURE insert_products()
        BEGIN
          DECLARE i INT DEFAULT 1;
          WHILE i <= 1000 DO
            INSERT INTO products (name, category, price, stock) VALUES
              (CONCAT('Product ', i),
               CASE MOD(i, 5)
                 WHEN 0 THEN 'Electronics'
                 WHEN 1 THEN 'Books'
                 WHEN 2 THEN 'Clothing'
                 WHEN 3 THEN 'Food'
                 ELSE 'Sports'
               END,
               ROUND(RAND() * 1000, 2),
               FLOOR(RAND() * 100));
            SET i = i + 1;
          END WHILE;
        END
      ''');

      await adapter.executeQuery('CALL insert_products()');
      await adapter.executeQuery('DROP PROCEDURE IF EXISTS insert_products');

      // 查询所有数据
      final sql = 'SELECT category, COUNT(*) as count, AVG(price) as avg_price, SUM(stock) as total_stock FROM products GROUP BY category';
      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, equals(5), reason: 'Should have 5 categories');

      // 调用 DeepSeek API 总结大结果集
      final prompt = generateQueryAnalysisPrompt(sql, {
        'totalProducts': 1000,
        'categories': queryResult.rows,
        'analysis': 'Category-wise product distribution and pricing',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.mysql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    // ==========================================================================
    // 场景 5：查询历史 + AI 分析
    // ==========================================================================

    testWidgets('场景5 - 查询历史 + AI 分析', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'mysql_e2e_scenario5',
        name: 'MySQL E2E AI Test Scenario 5',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      // 创建表
      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS events (
          id INT PRIMARY KEY AUTO_INCREMENT,
          event_type VARCHAR(50),
          event_data TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      // 模拟查询历史（执行多个查询）
      final queries = [
        'SELECT COUNT(*) FROM events',
        'SELECT event_type, COUNT(*) FROM events GROUP BY event_type',
        'SELECT * FROM events WHERE created_at >= NOW() - INTERVAL 1 HOUR',
        'SELECT event_type, MAX(created_at) FROM events GROUP BY event_type',
        'SELECT COUNT(*) FROM events WHERE event_type = "login"',
      ];

      final queryHistory = <Map<String, dynamic>>[];
      for (final sql in queries) {
        await adapter.executeQuery(sql);
        queryHistory.add({
          'sql': sql,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      // 调用 DeepSeek API 分析查询历史
      final prompt = generateHistoryAnalysisPrompt(queryHistory);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.mysql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    // ==========================================================================
    // 场景 6：Schema 信息 + AI 解释
    // ==========================================================================

    testWidgets('场景6 - Schema 信息 + AI 解释', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'mysql_e2e_scenario6',
        name: 'MySQL E2E AI Test Scenario 6',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      // 创建复杂的 Schema
      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS customers (
          id INT PRIMARY KEY AUTO_INCREMENT,
          name VARCHAR(100) NOT NULL,
          email VARCHAR(100) UNIQUE,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS products (
          id INT PRIMARY KEY AUTO_INCREMENT,
          name VARCHAR(100) NOT NULL,
          price DECIMAL(10, 2) NOT NULL,
          category VARCHAR(50)
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS orders (
          id INT PRIMARY KEY AUTO_INCREMENT,
          customer_id INT NOT NULL,
          order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          total_amount DECIMAL(10, 2),
          FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE IF NOT EXISTS order_items (
          id INT PRIMARY KEY AUTO_INCREMENT,
          order_id INT NOT NULL,
          product_id INT NOT NULL,
          quantity INT NOT NULL DEFAULT 1,
          price DECIMAL(10, 2) NOT NULL,
          FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
          FOREIGN KEY (product_id) REFERENCES products(id)
        )
      ''');

      // 创建索引
      await adapter.executeQuery('CREATE INDEX idx_customer_email ON customers(email)');
      await adapter.executeQuery('CREATE INDEX idx_product_category ON products(category)');
      await adapter.executeQuery('CREATE INDEX idx_order_customer ON orders(customer_id)');
      await adapter.executeQuery('CREATE INDEX idx_order_date ON orders(order_date)');

      // 收集 Schema 信息
      final schema = {
        'tables': ['customers', 'products', 'orders', 'order_items'],
        'relationships': ['orders → customers', 'order_items → orders', 'order_items → products'],
        'indexes': ['customers.email', 'products.category', 'orders.customer_id', 'orders.order_date'],
      };

      // 调用 DeepSeek API 解释 Schema
      final prompt = generateSchemaExplanationPrompt(schema);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.mysql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });
  });
}
