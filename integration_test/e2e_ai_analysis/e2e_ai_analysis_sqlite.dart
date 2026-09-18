// ============================================================================
// SQLite E2E AI Analysis Test - 真实数据库 + DeepSeek AI
//
// 覆盖 6 个 AI 分析场景（本地文件数据库）
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'e2e_ai_analysis_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SQLite E2E AI Analysis', () {
    late SQLiteAdapter adapter;
    late String testDbPath;

    setUpAll(() async {
      // 创建临时数据库文件路径
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      testDbPath = path.join(tempDir.path, 'dbmaster_test_$timestamp.db');
      adapter = SQLiteAdapter();
    });

    tearDownAll(() async {
      try {
        await adapter.disconnect();
        // 删除临时数据库文件
        if (File(testDbPath).existsSync()) {
          File(testDbPath).deleteSync();
        }
      } catch (_) {}
    });

    testWidgets('场景1 - 基础查询 + AI 分析', (tester) async {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testDbPath = path.join(tempDir.path, 'dbmaster_test_${timestamp}_1.db');

      final connection = DatabaseConnection(
        id: 'sqlite_e2e_test',
        name: 'SQLite E2E AI Test',
        type: DatabaseType.sqlite,
        host: '',
        port: 0,
        username: '',
        password: '',
        database: testDbPath,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to create SQLite database');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)');
      await adapter.executeQuery("INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com'), ('Bob', 'bob@example.com'), ('Charlie', 'charlie@example.com')");

      // 清理：删除数据库文件
      addTearDown(() async {
        try {
          if (File(testDbPath).existsSync()) {
            File(testDbPath).deleteSync();
          }
        } catch (_) {}
      });

      final sql = 'SELECT * FROM users';
      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have data');

      final prompt = generateQueryAnalysisPrompt(sql, {
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows.take(3).toList(),
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlite);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景2 - 复杂查询 + AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlite_e2e_scenario2',
        name: 'SQLite E2E AI Test Scenario 2',
        type: DatabaseType.sqlite,
        host: '',
        port: 0,
        username: '',
        password: '',
        database: testDbPath,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to create SQLite database');

      // 清理：删除可能存在的表
      await adapter.executeQuery('DROP TABLE IF EXISTS orders');
      await adapter.executeQuery('DROP TABLE IF EXISTS users');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, product_name TEXT, amount REAL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (user_id) REFERENCES users(id))');
      await adapter.executeQuery("INSERT INTO users (id, name, email) VALUES (1, 'Alice', 'alice@example.com'), (2, 'Bob', 'bob@example.com'), (3, 'Charlie', 'charlie@example.com')");
      await adapter.executeQuery("INSERT INTO orders (user_id, product_name, amount) VALUES (1, 'Product A', 100.00), (1, 'Product B', 200.00), (2, 'Product C', 150.00), (3, 'Product D', 300.00)");

      final sql = '''SELECT u.name, u.email, COUNT(o.id) as order_count, SUM(o.amount) as total_amount
        FROM users u
        LEFT JOIN orders o ON u.id = o.user_id
        GROUP BY u.id
        HAVING total_amount > 100
        ORDER BY total_amount DESC''';

      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'queryType': 'JOIN with aggregation',
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlite);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景3 - DML 操作 + AI 验证', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlite_e2e_scenario3',
        name: 'SQLite E2E AI Test Scenario 3',
        type: DatabaseType.sqlite,
        host: '',
        port: 0,
        username: '',
        password: '',
        database: testDbPath,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to create SQLite database');

      // 清理：删除可能存在的表
      await adapter.executeQuery('DROP TABLE IF EXISTS accounts');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, balance REAL DEFAULT 0.0)');
      await adapter.executeQuery("INSERT INTO accounts (name, balance) VALUES ('Account A', 1000.0), ('Account B', 2000.0), ('Account C', 3000.0)");
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

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlite);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景4 - 大结果集 + AI 总结', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlite_e2e_scenario4',
        name: 'SQLite E2E AI Test Scenario 4',
        type: DatabaseType.sqlite,
        host: '',
        port: 0,
        username: '',
        password: '',
        database: testDbPath,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to create SQLite database');

      // 清理：删除可能存在的表
      await adapter.executeQuery('DROP TABLE IF EXISTS products');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, category TEXT, price REAL, stock INTEGER)');

      for (int i = 1; i <= 1000; i++) {
        final category = ['Electronics', 'Books', 'Clothing', 'Food', 'Sports'][i % 5];
        final price = i * 1.0;
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

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlite);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景5 - 查询历史 + AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlite_e2e_scenario5',
        name: 'SQLite E2E AI Test Scenario 5',
        type: DatabaseType.sqlite,
        host: '',
        port: 0,
        username: '',
        password: '',
        database: testDbPath,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to create SQLite database');

      // 清理：删除可能存在的表
      await adapter.executeQuery('DROP TABLE IF EXISTS events');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT, event_data TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)');

      final queries = [
        'SELECT COUNT(*) FROM events',
        'SELECT event_type, COUNT(*) FROM events GROUP BY event_type',
        "SELECT * FROM events WHERE created_at >= datetime('now', '-1 hour')",
        'SELECT event_type, MAX(created_at) FROM events GROUP BY event_type',
        "SELECT COUNT(*) FROM events WHERE event_type = 'login'",
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

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlite);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景6 - Schema 信息 + AI 解释', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlite_e2e_scenario6',
        name: 'SQLite E2E AI Test Scenario 6',
        type: DatabaseType.sqlite,
        host: '',
        port: 0,
        username: '',
        password: '',
        database: testDbPath,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to create SQLite database');

      // 清理：删除可能存在的表和索引
      await adapter.executeQuery('DROP INDEX IF EXISTS idx_order_date');
      await adapter.executeQuery('DROP INDEX IF EXISTS idx_order_customer');
      await adapter.executeQuery('DROP INDEX IF EXISTS idx_product_category');
      await adapter.executeQuery('DROP INDEX IF EXISTS idx_customer_email');
      await adapter.executeQuery('DROP TABLE IF EXISTS order_items');
      await adapter.executeQuery('DROP TABLE IF EXISTS orders');
      await adapter.executeQuery('DROP TABLE IF EXISTS products');
      await adapter.executeQuery('DROP TABLE IF EXISTS customers');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT UNIQUE, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)');
      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, price REAL NOT NULL, category TEXT)');
      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER NOT NULL, order_date DATETIME DEFAULT CURRENT_TIMESTAMP, total_amount REAL, FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE)');
      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL, product_id INTEGER NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, price REAL NOT NULL, FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE, FOREIGN KEY (product_id) REFERENCES products(id))');
      await adapter.executeQuery('CREATE INDEX IF NOT EXISTS idx_customer_email ON customers(email)');
      await adapter.executeQuery('CREATE INDEX IF NOT EXISTS idx_product_category ON products(category)');
      await adapter.executeQuery('CREATE INDEX IF NOT EXISTS idx_order_customer ON orders(customer_id)');
      await adapter.executeQuery('CREATE INDEX IF NOT EXISTS idx_order_date ON orders(order_date)');

      final schema = {
        'tables': ['customers', 'products', 'orders', 'order_items'],
        'relationships': ['orders → customers', 'order_items → orders', 'order_items → products'],
        'indexes': ['customers.email', 'products.category', 'orders.customer_id', 'orders.order_date'],
      };

      final prompt = generateSchemaExplanationPrompt(schema);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlite);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });
  });
}
