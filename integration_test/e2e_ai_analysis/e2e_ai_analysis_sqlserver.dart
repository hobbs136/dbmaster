// ============================================================================
// SQL Server E2E AI Analysis Test - 真实数据库 + DeepSeek AI
//
// 覆盖 6 个 AI 分析场景
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import '../config/sqlserver_test_config.dart';
import 'e2e_ai_analysis_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SQL Server E2E AI Analysis', () {
    late DatabaseAdapter adapter;
    late String testDbName;

    setUp(() async {
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      adapter = SqlServerAdapter();
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('IF EXISTS (SELECT name FROM sys.databases WHERE name = \'$testDbName\') DROP DATABASE [$testDbName]');
        await adapter.disconnect();
      } catch (_) {}
    });

    testWidgets('场景1 - 基础查询 + AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlserver_e2e_test',
        name: 'SQL Server E2E AI Test',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to SQL Server（DBMASTER_SQLSERVER_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      await adapter.executeQuery('CREATE DATABASE [$testDbName]');
      await adapter.executeQuery('USE [$testDbName]');

      await adapter.executeQuery('''
        CREATE TABLE [users] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [name] NVARCHAR(100),
          [email] NVARCHAR(100),
          [created_at] DATETIME DEFAULT GETDATE()
        )
      ''');

      await adapter.executeQuery("INSERT INTO [users] ([name], [email]) VALUES (N'Alice', N'alice@example.com'), (N'Bob', N'bob@example.com'), (N'Charlie', N'charlie@example.com')");

      final sql = 'SELECT * FROM [users]';
      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have data');

      final prompt = generateQueryAnalysisPrompt(sql, {
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows.take(3).toList(),
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlserver);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景2 - 复杂查询 + AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlserver_e2e_scenario2',
        name: 'SQL Server E2E AI Test Scenario 2',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to SQL Server（DBMASTER_SQLSERVER_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      await adapter.executeQuery('CREATE DATABASE [$testDbName]');
      await adapter.executeQuery('USE [$testDbName]');

      await adapter.executeQuery('''
        CREATE TABLE [users] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [name] NVARCHAR(100),
          [email] NVARCHAR(100)
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE [orders] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [user_id] INT FOREIGN KEY REFERENCES [users]([id]),
          [product_name] NVARCHAR(100),
          [amount] DECIMAL(10, 2),
          [created_at] DATETIME DEFAULT GETDATE()
        )
      ''');

      await adapter.executeQuery("SET IDENTITY_INSERT [users] ON");
      await adapter.executeQuery("INSERT INTO [users] ([id], [name], [email]) VALUES (1, N'Alice', N'alice@example.com'), (2, N'Bob', N'bob@example.com'), (3, N'Charlie', N'charlie@example.com')");
      await adapter.executeQuery("SET IDENTITY_INSERT [users] OFF");

      await adapter.executeQuery("INSERT INTO [orders] ([user_id], [product_name], [amount]) VALUES (1, N'Product A', 100.00), (1, N'Product B', 200.00), (2, N'Product C', 150.00), (3, N'Product D', 300.00)");

      final sql = '''SELECT u.[name], u.[email], COUNT(o.[id]) as [order_count], SUM(o.[amount]) as [total_amount]
        FROM [users] u
        LEFT JOIN [orders] o ON u.[id] = o.[user_id]
        GROUP BY u.[id], u.[name], u.[email]
        HAVING SUM(o.[amount]) > 100
        ORDER BY [total_amount] DESC''';

      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'queryType': 'JOIN with aggregation',
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlserver);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景3 - DML 操作 + AI 验证', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlserver_e2e_scenario3',
        name: 'SQL Server E2E AI Test Scenario 3',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to SQL Server（DBMASTER_SQLSERVER_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      await adapter.executeQuery('CREATE DATABASE [$testDbName]');
      await adapter.executeQuery('USE [$testDbName]');

      await adapter.executeQuery('''
        CREATE TABLE [accounts] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [name] NVARCHAR(100),
          [balance] DECIMAL(10, 2) DEFAULT 0.00
        )
      ''');

      await adapter.executeQuery("INSERT INTO [accounts] ([name], [balance]) VALUES (N'Account A', 1000.00), (N'Account B', 2000.00), (N'Account C', 3000.00)");

      await adapter.executeQuery("UPDATE [accounts] SET [balance] = [balance] + 500 WHERE [name] = N'Account A'");

      await adapter.executeQuery("DELETE FROM [accounts] WHERE [name] = N'Account C'");

      final result = await adapter.executeQuery('SELECT * FROM [accounts] ORDER BY [name]');

      final prompt = '''
请验证以下 DML 操作的正确性：

1. INSERT：插入 3 个账户，初始余额分别为 1000, 2000, 3000
2. UPDATE：Account A 余额增加 500
3. DELETE：删除 Account C

当前数据库状态：
${result.rows.map((row) => '- ${row['name']}: ${row['balance']}').join('\n')}

请分析：操作是否正确？数据是否一致？
''';

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlserver);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景4 - 大结果集 + AI 总结', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlserver_e2e_scenario4',
        name: 'SQL Server E2E AI Test Scenario 4',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to SQL Server（DBMASTER_SQLSERVER_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      await adapter.executeQuery('CREATE DATABASE [$testDbName]');
      await adapter.executeQuery('USE [$testDbName]');

      await adapter.executeQuery('''
        CREATE TABLE [products] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [name] NVARCHAR(100),
          [category] NVARCHAR(50),
          [price] DECIMAL(10, 2),
          [stock] INT
        )
      ''');

      // 批量插入1000条记录
      for (int i = 1; i <= 1000; i++) {
        final category = ['Electronics', 'Books', 'Clothing', 'Food', 'Sports'][i % 5];
        final price = (i * 1.0).toStringAsFixed(2);
        final stock = i % 100;
        await adapter.executeQuery("INSERT INTO [products] ([name], [category], [price], [stock]) VALUES (N'Product $i', N'$category', $price, $stock)");
      }

      final sql = 'SELECT [category], COUNT(*) as [count], AVG([price]) as [avg_price], SUM([stock]) as [total_stock] FROM [products] GROUP BY [category]';
      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'totalProducts': 1000,
        'categories': queryResult.rows,
        'analysis': 'Category-wise product distribution and pricing',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlserver);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景5 - 查询历史 + AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlserver_e2e_scenario5',
        name: 'SQL Server E2E AI Test Scenario 5',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to SQL Server（DBMASTER_SQLSERVER_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      await adapter.executeQuery('CREATE DATABASE [$testDbName]');
      await adapter.executeQuery('USE [$testDbName]');

      await adapter.executeQuery('''
        CREATE TABLE [events] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [event_type] NVARCHAR(50),
          [event_data] NVARCHAR(MAX),
          [created_at] DATETIME DEFAULT GETDATE()
        )
      ''');

      final queries = [
        'SELECT COUNT(*) FROM [events]',
        'SELECT [event_type], COUNT(*) FROM [events] GROUP BY [event_type]',
        'SELECT * FROM [events] WHERE [created_at] >= DATEADD(hour, -1, GETDATE())',
        'SELECT [event_type], MAX([created_at]) FROM [events] GROUP BY [event_type]',
        'SELECT COUNT(*) FROM [events] WHERE [event_type] = N\'login\'',
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

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlserver);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景6 - Schema 信息 + AI 解释', (tester) async {
      final connection = DatabaseConnection(
        id: 'sqlserver_e2e_scenario6',
        name: 'SQL Server E2E AI Test Scenario 6',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to SQL Server（DBMASTER_SQLSERVER_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      await adapter.executeQuery('CREATE DATABASE [$testDbName]');
      await adapter.executeQuery('USE [$testDbName]');

      await adapter.executeQuery('''
        CREATE TABLE [customers] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [name] NVARCHAR(100) NOT NULL,
          [email] NVARCHAR(100) UNIQUE,
          [created_at] DATETIME DEFAULT GETDATE()
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE [products] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [name] NVARCHAR(100) NOT NULL,
          [price] DECIMAL(10, 2) NOT NULL,
          [category] NVARCHAR(50)
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE [orders] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [customer_id] INT NOT NULL FOREIGN KEY REFERENCES [customers]([id]) ON DELETE CASCADE,
          [order_date] DATETIME DEFAULT GETDATE(),
          [total_amount] DECIMAL(10, 2)
        )
      ''');

      await adapter.executeQuery('''
        CREATE TABLE [order_items] (
          [id] INT IDENTITY(1,1) PRIMARY KEY,
          [order_id] INT NOT NULL FOREIGN KEY REFERENCES [orders]([id]) ON DELETE CASCADE,
          [product_id] INT NOT NULL FOREIGN KEY REFERENCES [products]([id]),
          [quantity] INT NOT NULL DEFAULT 1,
          [price] DECIMAL(10, 2) NOT NULL
        )
      ''');

      await adapter.executeQuery('CREATE INDEX [idx_customer_email] ON [customers]([email])');
      await adapter.executeQuery('CREATE INDEX [idx_product_category] ON [products]([category])');
      await adapter.executeQuery('CREATE INDEX [idx_order_customer] ON [orders]([customer_id])');
      await adapter.executeQuery('CREATE INDEX [idx_order_date] ON [orders]([order_date])');

      final schema = {
        'tables': ['customers', 'products', 'orders', 'order_items'],
        'relationships': ['orders → customers', 'order_items → orders', 'order_items → products'],
        'indexes': ['customers.email', 'products.category', 'orders.customer_id', 'orders.order_date'],
      };

      final prompt = generateSchemaExplanationPrompt(schema);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.sqlserver);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });
  });
}
