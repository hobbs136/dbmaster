// ============================================================================
// PostgreSQL E2E AI Analysis Test - 真实数据库 + DeepSeek AI
//
// 覆盖 6 个 AI 分析场景
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import '../config/postgresql_test_config.dart';
import '../helpers/pg_gateway_e2e_helper.dart';
import 'e2e_ai_analysis_helper.dart';

void main() {

  // T29 第二批：PG 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 PG_E2E_SKIP 跳过（无假绿）。
  bool pgE2EGatewayReady = false;
  setUpAll(() async {
    pgE2EGatewayReady = await ensureEmbeddedServerForPgE2E();
    if (pgE2EGatewayReady && !PostgreSQLTestConfig.available) {
      // ignore: avoid_print
      print('PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      pgE2EGatewayReady = false;
    }
  });
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('PostgreSQL E2E AI Analysis', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      adapter = PostgreSQLAdapter();
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP SCHEMA IF EXISTS `$testDbName` CASCADE');
        await adapter.disconnect();
      } catch (_) {}
    });

    testWidgets('场景1 - 基础查询 + AI 分析', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      // 先连接到默认数据库创建测试库
      final connection = DatabaseConnection(
        id: 'postgresql_e2e_test',
        name: 'PostgreSQL E2E AI Test',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database.isEmpty ? 'postgres' : PostgreSQLTestConfig.database,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');

      // 创建并切换到测试数据库
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100), email VARCHAR(100), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)');
      await adapter.executeQuery("INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com'), ('Bob', 'bob@example.com'), ('Charlie', 'charlie@example.com')");

      final sql = 'SELECT * FROM users';
      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have data');

      final prompt = generateQueryAnalysisPrompt(sql, {
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows.take(3).toList(),
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.postgresql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景2 - 复杂查询 + AI 分析', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'postgresql_e2e_scenario2',
        name: 'PostgreSQL E2E AI Test Scenario 2',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database.isEmpty ? 'postgres' : PostgreSQLTestConfig.database,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100), email VARCHAR(100))');
      await adapter.executeQuery('CREATE TABLE orders (id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id), product_name VARCHAR(100), amount DECIMAL(10, 2), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)');
      await adapter.executeQuery("INSERT INTO users (id, name, email) VALUES (1, 'Alice', 'alice@example.com'), (2, 'Bob', 'bob@example.com'), (3, 'Charlie', 'charlie@example.com')");
      await adapter.executeQuery("INSERT INTO orders (user_id, product_name, amount) VALUES (1, 'Product A', 100.00), (1, 'Product B', 200.00), (2, 'Product C', 150.00), (3, 'Product D', 300.00)");

      final sql = '''SELECT u.name, u.email, COUNT(o.id) as order_count, SUM(o.amount) as total_amount
        FROM users u
        LEFT JOIN orders o ON u.id = o.user_id
        GROUP BY u.id, u.name, u.email
        HAVING SUM(o.amount) > 100
        ORDER BY total_amount DESC''';

      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'queryType': 'JOIN with aggregation',
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.postgresql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景3 - DML 操作 + AI 验证', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'postgresql_e2e_scenario3',
        name: 'PostgreSQL E2E AI Test Scenario 3',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database.isEmpty ? 'postgres' : PostgreSQLTestConfig.database,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('CREATE TABLE accounts (id SERIAL PRIMARY KEY, name VARCHAR(100), balance DECIMAL(10, 2) DEFAULT 0.00)');
      await adapter.executeQuery("INSERT INTO accounts (name, balance) VALUES ('Account A', 1000.00), ('Account B', 2000.00), ('Account C', 3000.00)");
      await adapter.executeQuery("UPDATE accounts SET balance = balance + 500 WHERE name = 'Account A'");
      await adapter.executeQuery('''DELETE FROM accounts WHERE name = 'Account C' ''');

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

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.postgresql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景4 - 大结果集 + AI 总结', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'postgresql_e2e_scenario4',
        name: 'PostgreSQL E2E AI Test Scenario 4',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database.isEmpty ? 'postgres' : PostgreSQLTestConfig.database,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('CREATE TABLE products (id SERIAL PRIMARY KEY, name VARCHAR(100), category VARCHAR(50), price DECIMAL(10, 2), stock INT)');

      // PostgreSQL 使用批量插入更高效
      for (int i = 1; i <= 1000; i++) {
        final category = ['Electronics', 'Books', 'Clothing', 'Food', 'Sports'][i % 5];
        final price = (i * 1.0).toStringAsFixed(2);
        final stock = i % 100;
        await adapter.executeQuery("INSERT INTO products (name, category, price, stock) VALUES ('Product $i', '$category', $price, $stock)");
      }

      final sql = 'SELECT category, COUNT(*) as count, AVG(price) as avg_price, SUM(stock) as total_stock FROM products GROUP BY category';
      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'totalProducts': 1000,
        'categories': queryResult.rows,
        'analysis': 'Category-wise product distribution and pricing',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.postgresql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景5 - 查询历史 + AI 分析', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'postgresql_e2e_scenario5',
        name: 'PostgreSQL E2E AI Test Scenario 5',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database.isEmpty ? 'postgres' : PostgreSQLTestConfig.database,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('CREATE TABLE events (id SERIAL PRIMARY KEY, event_type VARCHAR(50), event_data TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)');

      final queries = [
        'SELECT COUNT(*) FROM events',
        'SELECT event_type, COUNT(*) FROM events GROUP BY event_type',
        'SELECT * FROM events WHERE created_at >= NOW() - INTERVAL \'1 hour\'',
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

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.postgresql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景6 - Schema 信息 + AI 解释', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'postgresql_e2e_scenario6',
        name: 'PostgreSQL E2E AI Test Scenario 6',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database.isEmpty ? 'postgres' : PostgreSQLTestConfig.database,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');

      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('CREATE TABLE customers (id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL, email VARCHAR(100) UNIQUE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)');
      await adapter.executeQuery('CREATE TABLE products (id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL, price DECIMAL(10, 2) NOT NULL, category VARCHAR(50))');
      await adapter.executeQuery('CREATE TABLE orders (id SERIAL PRIMARY KEY, customer_id INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE, order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP, total_amount DECIMAL(10, 2))');
      await adapter.executeQuery('CREATE TABLE order_items (id SERIAL PRIMARY KEY, order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE, product_id INT NOT NULL REFERENCES products(id), quantity INT NOT NULL DEFAULT 1, price DECIMAL(10, 2) NOT NULL)');
      await adapter.executeQuery('CREATE INDEX idx_customer_email ON customers(email)');
      await adapter.executeQuery('CREATE INDEX idx_product_category ON products(category)');
      await adapter.executeQuery('CREATE INDEX idx_order_customer ON orders(customer_id)');
      await adapter.executeQuery('CREATE INDEX idx_order_date ON orders(order_date)');

      final schema = {
        'tables': ['customers', 'products', 'orders', 'order_items'],
        'relationships': ['orders → customers', 'order_items → orders', 'order_items → products'],
        'indexes': ['customers.email', 'products.category', 'orders.customer_id', 'orders.order_date'],
      };

      final prompt = generateSchemaExplanationPrompt(schema);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.postgresql);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });
  });
}
