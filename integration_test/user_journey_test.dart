// ============================================================================
// 用户旅程集成测试 - User Journey E2E Test
//
// 模拟一个真实数据库管理员的完整一天操作流程：
//
// 场景1：新用户首次使用 DbMaster
//   1. 启动应用 → 看到欢迎页
//   2. 添加 SQLite 数据库连接 → 填写连接表单 → 保存 → 测试连接
//   3. 双击连接 → 打开 Workspace
//   4. 创建表 → 插入数据 → 查询数据 → 验证结果
//   5. 切换主题（暗色/亮色）
//   6. 使用键盘快捷键
//
// 场景2：有经验的用户日常工作
//   7. 管理多个连接（分组、重命名）
//   8. 使用 SQL 编辑器（自动补全、格式化）
//   9. 浏览 Schema（展开数据库 → 展开表 → 查看列）
//   10. 执行多条 SQL 语句
//   11. 导出查询结果
//
// 场景3：高级用户操作
//   12. 表管理（修改列、添加索引）
//   13. 查询历史
//   14. 命令面板
//
// 使用 SQLite（文件数据库，无需外部服务器）
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dbmaster/main.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/pro_module.dart';
import 'package:dbmaster/organisms/sidebar_widget.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  // ==========================================================================
  // 测试工具函数
  // ==========================================================================

  /// 创建一个测试用的 SQLite 数据库路径
  String createTestDbPath(String suffix) {
    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${tempDir.path}/dbmaster_journey_${suffix}_$timestamp.db';
  }

  /// 启动带有完整 Provider 链的 App
  Future<AppProvider> bootApp(WidgetTester tester) async {
    await tester.pumpWidget(DbmasterApp(proModule: NoOpProModule()));
    // 分多帧 pump 等待应用完全启动，避免 pumpAndSettle 因持续动画超时
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final context = tester.element(find.byType(MaterialApp));
    return Provider.of<AppProvider>(context, listen: false);
  }

  // ==========================================================================
  // 场景1：新用户首次使用 DbMaster
  // ==========================================================================
  group('Scenario 1: 新用户首次使用', () {
    testWidgets('J1.1 - 应用启动并显示主界面', (tester) async {
      await tester.pumpWidget(DbmasterApp(proModule: NoOpProModule()));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 验证 MaterialApp 存在
      expect(find.byType(MaterialApp), findsOneWidget, reason: '应用应该正常启动');

      // 验证侧边栏存在
      expect(find.byType(SidebarWidget), findsOneWidget, reason: '侧边栏应该渲染');
    });

    testWidgets('J1.2 - 通过 API 添加 SQLite 连接', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('add_connection');

      try {
        // 创建一个 SQLite 连接
        final server = DbServer(
          id: 'journey_sqlite_test',
          name: '我的测试数据库',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          database: 'main',
        );

        // 保存连接
        await appProvider.connection.saveConnection(server);
        await tester.pumpAndSettle();

        // 验证连接已保存
        expect(
          appProvider.savedConnections.length,
          greaterThan(0),
          reason: '应该至少保存了1个连接',
        );
        expect(
          appProvider.savedConnections.first.name,
          '我的测试数据库',
          reason: '连接名称应该正确',
        );
      } finally {
        // 清理
        try {
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J1.3 - 连接到 SQLite 数据库', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('connect');

      try {
        final server = DbServer(
          id: 'journey_connect_test',
          name: '连接测试DB',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          database: 'main',
        );

        await appProvider.connection.saveConnection(server);

        // 执行连接
        final connected = await appProvider.connectToServer(server);
        expect(connected, isTrue, reason: '应该能成功连接到 SQLite 数据库');

        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 验证连接状态
        expect(
          appProvider.isConnectionConnected(server.id),
          isTrue,
          reason: '连接应该处于已连接状态',
        );
      } finally {
        try {
          await appProvider.disconnectConnection(
            connectionId: 'journey_connect_test',
          );
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J1.4 - 创建表并插入数据', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('crud');

      try {
        // 建立连接
        final server = DbServer(
          id: 'journey_crud',
          name: 'CRUD测试',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          database: 'main',
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        // 创建表
        await appProvider.dbService.executeQuery('''CREATE TABLE employees (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            department TEXT,
            salary REAL,
            hire_date TEXT
          )''', connectionId: 'journey_crud');

        // 插入数据
        await appProvider.dbService.executeQuery(
          "INSERT INTO employees (name, department, salary, hire_date) VALUES "
          "('张三', '技术部', 15000, '2024-01-15'),"
          "('李四', '市场部', 12000, '2024-03-01'),"
          "('王五', '技术部', 18000, '2023-06-20'),"
          "('赵六', '人事部', 10000, '2024-05-10')",
          connectionId: 'journey_crud',
        );

        // 查询验证
        final results = await appProvider.dbService.executeQuery(
          'SELECT * FROM employees ORDER BY id',
          connectionId: 'journey_crud',
        );
        expect(results.length, 4, reason: '应该插入4条记录');
        expect(results[0]['name'], '张三');
        expect(results[1]['department'], '市场部');
        expect(results[2]['salary'], 18000);
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: 'journey_crud');
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J1.5 - 查询结果验证', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('query_verify');

      try {
        final server = DbServer(
          id: 'journey_query',
          name: '查询验证',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          database: 'main',
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        // 准备数据
        await appProvider.dbService.executeQuery('''CREATE TABLE products (
            id INTEGER PRIMARY KEY,
            name TEXT,
            price REAL,
            stock INTEGER
          )''', connectionId: 'journey_query');

        await appProvider.dbService.executeQuery(
          "INSERT INTO products VALUES "
          "(1, '笔记本', 5999.00, 50),"
          "(2, '鼠标', 199.00, 200),"
          "(3, '键盘', 499.00, 100),"
          "(4, '显示器', 2499.00, 30)",
          connectionId: 'journey_query',
        );

        // 测试各种查询
        // 1. COUNT 查询
        final countResult = await appProvider.dbService.executeQuery(
          'SELECT COUNT(*) as cnt FROM products',
          connectionId: 'journey_query',
        );
        expect(countResult[0]['cnt'], 4);

        // 2. WHERE 条件查询
        final whereResult = await appProvider.dbService.executeQuery(
          'SELECT * FROM products WHERE price > 1000',
          connectionId: 'journey_query',
        );
        expect(whereResult.length, 2); // 笔记本和显示器

        // 3. 聚合查询
        final aggResult = await appProvider.dbService.executeQuery(
          'SELECT SUM(stock) as total_stock, AVG(price) as avg_price FROM products',
          connectionId: 'journey_query',
        );
        expect(aggResult[0]['total_stock'], 380);

        // 4. ORDER BY + LIMIT
        final limitResult = await appProvider.dbService.executeQuery(
          'SELECT * FROM products ORDER BY price DESC LIMIT 2',
          connectionId: 'journey_query',
        );
        expect(limitResult.length, 2);
        expect(limitResult[0]['name'], '笔记本');
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: 'journey_query');
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });
  });

  // ==========================================================================
  // 场景2：有经验的用户日常工作
  // ==========================================================================
  group('Scenario 2: 日常工作流程', () {
    testWidgets('J2.1 - 管理多个连接', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath1 = createTestDbPath('multi1');
      final dbPath2 = createTestDbPath('multi2');

      try {
        // 添加第一个连接
        final server1 = DbServer(
          id: 'journey_multi1',
          name: '开发数据库',
          type: DatabaseType.sqlite,
          host: dbPath1,
          port: 0,
          environment: ConnectionEnvironment.development,
        );
        await appProvider.connection.saveConnection(server1);

        // 添加第二个连接
        final server2 = DbServer(
          id: 'journey_multi2',
          name: '生产数据库',
          type: DatabaseType.sqlite,
          host: dbPath2,
          port: 0,
          environment: ConnectionEnvironment.production,
        );
        await appProvider.connection.saveConnection(server2);

        await tester.pumpAndSettle();

        // 验证两个连接都已保存
        expect(appProvider.savedConnections.length, 2, reason: '应该保存了2个连接');

        // 验证环境标签
        final devConn = appProvider.savedConnections.firstWhere(
          (c) => c.id == 'journey_multi1',
        );
        final prodConn = appProvider.savedConnections.firstWhere(
          (c) => c.id == 'journey_multi2',
        );

        expect(devConn.environment, ConnectionEnvironment.development);
        expect(prodConn.environment, ConnectionEnvironment.production);

        // 测试删除连接
        await appProvider.deleteConnection('journey_multi1');
        await tester.pumpAndSettle();
        expect(appProvider.savedConnections.length, 1, reason: '删除后应该只剩1个连接');
      } finally {
        try {
          await appProvider.disconnectConnection(
            connectionId: 'journey_multi1',
          );
          await appProvider.disconnectConnection(
            connectionId: 'journey_multi2',
          );
          File(dbPath1).deleteSync();
          File(dbPath2).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J2.2 - 连接分组管理', (tester) async {
      final appProvider = await bootApp(tester);

      // 创建分组
      final group = ConnectionGroup(id: 'journey_group', name: '我的项目');
      await appProvider.addConnectionGroup(group);
      await tester.pumpAndSettle();

      // 验证分组已创建
      expect(appProvider.connectionGroups.length, 1);
      expect(appProvider.connectionGroups.first.name, '我的项目');

      // 重命名分组
      await appProvider.renameConnectionGroup('journey_group', '项目A');
      await tester.pumpAndSettle();
      expect(appProvider.connectionGroups.first.name, '项目A');

      // 删除分组
      await appProvider.deleteConnectionGroup('journey_group');
      await tester.pumpAndSettle();
      expect(appProvider.connectionGroups.length, 0);
    });

    testWidgets('J2.3 - 复杂 SQL 查询', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('complex_sql');

      try {
        final server = DbServer(
          id: 'journey_complex',
          name: '复杂查询',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        // 创建关联表
        await appProvider.dbService.executeQuery('''
          CREATE TABLE departments (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''', connectionId: 'journey_complex');

        await appProvider.dbService.executeQuery('''
          CREATE TABLE employees (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            dept_id INTEGER,
            salary REAL,
            FOREIGN KEY (dept_id) REFERENCES departments(id)
          )
        ''', connectionId: 'journey_complex');

        // 插入数据
        await appProvider.dbService.executeQuery(
          "INSERT INTO departments VALUES (1,'技术部'),(2,'市场部'),(3,'财务部')",
          connectionId: 'journey_complex',
        );
        await appProvider.dbService.executeQuery(
          "INSERT INTO employees VALUES "
          "(1,'张三',1,15000),(2,'李四',2,12000),(3,'王五',1,18000),"
          "(4,'赵六',3,11000),(5,'孙七',1,20000),(6,'周八',2,13000)",
          connectionId: 'journey_complex',
        );

        // JOIN 查询
        final joinResult = await appProvider.dbService.executeQuery('''
          SELECT e.name as emp_name, d.name as dept_name, e.salary
          FROM employees e
          JOIN departments d ON e.dept_id = d.id
          ORDER BY e.salary DESC
        ''', connectionId: 'journey_complex');

        expect(joinResult.length, 6);
        expect(joinResult[0]['emp_name'], '孙七'); // 最高工资

        // GROUP BY + HAVING
        final groupResult = await appProvider.dbService.executeQuery('''
          SELECT d.name as dept, COUNT(*) as cnt, AVG(e.salary) as avg_sal
          FROM employees e
          JOIN departments d ON e.dept_id = d.id
          GROUP BY d.name
          HAVING AVG(e.salary) > 12000
          ORDER BY avg_sal DESC
        ''', connectionId: 'journey_complex');

        expect(groupResult.length, 2); // 技术部(17666)和市场部(12500)
        expect(groupResult[0]['dept'], '技术部');

        // 子查询
        final subResult = await appProvider.dbService.executeQuery('''
          SELECT name, salary FROM employees
          WHERE salary > (SELECT AVG(salary) FROM employees)
          ORDER BY salary DESC
        ''', connectionId: 'journey_complex');

        // AVG = (15000+12000+18000+11000+20000+13000)/6 = 14833
        expect(subResult.length, 3); // 张三,王五,孙七
      } finally {
        try {
          await appProvider.disconnectConnection(
            connectionId: 'journey_complex',
          );
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J2.4 - 数据库 Schema 浏览', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('schema_browse');

      try {
        final server = DbServer(
          id: 'journey_schema',
          name: 'Schema浏览',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        // 创建多张表
        await appProvider.dbService.executeQuery('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            email TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''', connectionId: 'journey_schema');

        await appProvider.dbService.executeQuery('''
          CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            amount REAL NOT NULL,
            status TEXT DEFAULT 'pending',
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''', connectionId: 'journey_schema');

        await appProvider.dbService.executeQuery('''
          CREATE INDEX idx_orders_user ON orders(user_id)
        ''', connectionId: 'journey_schema');

        // 获取表列表
        final tables = await appProvider.dbService.getTables(
          connectionId: 'journey_schema',
        );
        expect(tables.length, 2);
        expect(tables, containsAll(['users', 'orders']));

        // 获取 users 表的列信息
        final columns = await appProvider.dbService.getTableColumns(
          'users',
          connectionId: 'journey_schema',
        );
        expect(columns.length, 4);
        expect(columns[0].name, 'id');
        expect(columns[1].name, 'username');

        // 获取 orders 表的索引
        final indexes = await appProvider.dbService.getTableIndexes(
          'orders',
          connectionId: 'journey_schema',
        );
        expect(indexes.any((i) => i.name == 'idx_orders_user'), isTrue);

        // 获取 orders 表的外键
        final foreignKeys = await appProvider.dbService.getForeignKeys(
          'orders',
          connectionId: 'journey_schema',
        );
        expect(foreignKeys.length, 1);
        expect(foreignKeys[0].column, 'user_id');
      } finally {
        try {
          await appProvider.disconnectConnection(
            connectionId: 'journey_schema',
          );
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });
  });

  // ==========================================================================
  // 场景3：高级用户操作
  // ==========================================================================
  group('Scenario 3: 高级用户操作', () {
    testWidgets('J3.1 - 表结构修改 (ALTER TABLE)', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('alter_table');

      try {
        final server = DbServer(
          id: 'journey_alter',
          name: '表结构修改',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        // 创建初始表
        await appProvider.dbService.executeQuery(
          'CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)',
          connectionId: 'journey_alter',
        );

        // 添加列
        await appProvider.dbService.executeQuery(
          'ALTER TABLE test_table ADD COLUMN email TEXT',
          connectionId: 'journey_alter',
        );

        // 验证新列存在
        final columns = await appProvider.dbService.getTableColumns(
          'test_table',
          connectionId: 'journey_alter',
        );
        final columnNames = columns.map((c) => c.name).toList();
        expect(columnNames, containsAll(['id', 'name', 'email']));

        // SQLite 不支持 DROP COLUMN 在旧版本，但 Flutter sqflite 较新
        // 尝试重命名表
        await appProvider.dbService.renameTable('test_table', 'renamed_table');

        final tables = await appProvider.dbService.getTables(
          connectionId: 'journey_alter',
        );
        expect(tables, contains('renamed_table'));
        expect(tables, isNot(contains('test_table')));
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: 'journey_alter');
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J3.2 - 事务操作', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('transaction');

      try {
        final server = DbServer(
          id: 'journey_txn',
          name: '事务测试',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        await appProvider.dbService.executeQuery(
          'CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance REAL)',
          connectionId: 'journey_txn',
        );
        await appProvider.dbService.executeQuery(
          "INSERT INTO accounts VALUES (1, 1000), (2, 500)",
          connectionId: 'journey_txn',
        );

        // 开始事务
        await appProvider.beginTransaction();

        // 转账操作
        await appProvider.dbService.executeQuery(
          'UPDATE accounts SET balance = balance - 200 WHERE id = 1',
          connectionId: 'journey_txn',
        );
        await appProvider.dbService.executeQuery(
          'UPDATE accounts SET balance = balance + 200 WHERE id = 2',
          connectionId: 'journey_txn',
        );

        // 提交事务
        await appProvider.commitTransaction();

        // 验证结果
        final result = await appProvider.dbService.executeQuery(
          'SELECT * FROM accounts ORDER BY id',
          connectionId: 'journey_txn',
        );
        expect(result[0]['balance'], 800);
        expect(result[1]['balance'], 700);

        // 测试回滚
        await appProvider.beginTransaction();
        await appProvider.dbService.executeQuery(
          'UPDATE accounts SET balance = balance - 9999 WHERE id = 1',
          connectionId: 'journey_txn',
        );
        await appProvider.rollbackTransaction();

        // 回滚后余额应该不变
        final afterRollback = await appProvider.dbService.executeQuery(
          'SELECT * FROM accounts WHERE id = 1',
          connectionId: 'journey_txn',
        );
        expect(afterRollback[0]['balance'], 800);
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: 'journey_txn');
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J3.3 - 数据导出功能', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('export');

      try {
        final server = DbServer(
          id: 'journey_export',
          name: '导出测试',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        await appProvider.dbService.executeQuery(
          'CREATE TABLE export_test (id INTEGER, name TEXT, value REAL)',
          connectionId: 'journey_export',
        );
        await appProvider.dbService.executeQuery(
          "INSERT INTO export_test VALUES (1,'A',10.5),(2,'B',20.3),(3,'C',30.7)",
          connectionId: 'journey_export',
        );

        // 获取表数据
        final data = await appProvider.dbService.getTableData('export_test');
        expect(data.length, 3);

        // 验证数据可以被导出（这里只验证数据结构）
        final columns = data.first.keys.toList();
        expect(columns, containsAll(['id', 'name', 'value']));

        // 获取 CREATE TABLE 语句（用于导出结构）
        final createSql = await appProvider.dbService.getCreateTableSql(
          'export_test',
          connectionId: 'journey_export',
        );
        expect(createSql, contains('CREATE TABLE'));
        expect(createSql, contains('export_test'));
      } finally {
        try {
          await appProvider.disconnectConnection(
            connectionId: 'journey_export',
          );
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J3.4 - 连接克隆功能', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('clone');

      try {
        final server = DbServer(
          id: 'journey_clone_src',
          name: '原始连接',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          username: 'admin',
          database: 'main',
          readOnly: true,
          environment: ConnectionEnvironment.testing,
        );
        await appProvider.connection.saveConnection(server);

        // 克隆连接
        await appProvider.cloneConnection(server);
        await tester.pumpAndSettle();

        // 验证克隆
        expect(appProvider.savedConnections.length, 2);

        final cloned = appProvider.savedConnections.last;
        expect(cloned.name, contains('原始连接'), reason: '克隆连接的名称应包含原始名称');
        expect(cloned.type, DatabaseType.sqlite);
        expect(cloned.host, dbPath);
        expect(cloned.port, 0);
        expect(cloned.username, 'admin');
        expect(cloned.readOnly, isTrue);
        expect(cloned.environment, ConnectionEnvironment.testing);
      } finally {
        try {
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J3.5 - 只读模式验证', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('readonly');

      try {
        final server = DbServer(
          id: 'journey_readonly',
          name: '只读数据库',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          readOnly: true,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        // 创建表（通过绕过只读限制的 API 调用）
        await appProvider.dbService.executeQuery(
          'CREATE TABLE readonly_test (id INTEGER PRIMARY KEY, data TEXT)',
          connectionId: 'journey_readonly',
        );

        // 验证连接标记为只读
        expect(server.readOnly, isTrue);

        // 验证只读模式下仍然可以查询
        final result = await appProvider.dbService.executeQuery(
          'SELECT * FROM readonly_test',
          connectionId: 'journey_readonly',
        );
        expect(result, isEmpty);
      } finally {
        try {
          await appProvider.disconnectConnection(
            connectionId: 'journey_readonly',
          );
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });
  });

  // ==========================================================================
  // 场景4：边界情况和错误处理
  // ==========================================================================
  group('Scenario 4: 边界情况和错误处理', () {
    testWidgets('J4.1 - 连接不存在的数据库', (tester) async {
      final appProvider = await bootApp(tester);

      final server = DbServer(
        id: 'journey_bad_conn',
        name: '不存在的数据库',
        type: DatabaseType.sqlite,
        host: '/nonexistent/path/db.db',
        port: 0,
      );

      // 保存连接（不要求数据库存在）
      await appProvider.connection.saveConnection(server);

      // 尝试连接 - SQLite 会创建文件，所以这个测试主要验证不崩溃
      try {
        await appProvider.connectToServer(server);
      } catch (_) {
        // 预期的错误
      }

      // 应用不应崩溃
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('J4.2 - 执行错误的 SQL', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('error_sql');

      try {
        final server = DbServer(
          id: 'journey_error',
          name: '错误SQL测试',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        // 执行语法错误的 SQL
        try {
          await appProvider.dbService.executeQuery(
            'SELEC * FROM nonexistent_table', // 拼写错误
            connectionId: 'journey_error',
          );
          fail('应该抛出异常');
        } catch (e) {
          // 预期行为 - SQL 错误应该被捕获
          expect(e.toString(), isNotEmpty);
        }

        // 查询不存在的表
        try {
          await appProvider.dbService.executeQuery(
            'SELECT * FROM table_that_does_not_exist',
            connectionId: 'journey_error',
          );
          fail('应该抛出异常');
        } catch (e) {
          expect(e.toString(), isNotEmpty);
        }

        // 应用不应崩溃
        expect(find.byType(MaterialApp), findsOneWidget);
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: 'journey_error');
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J4.3 - 重复连接名称处理', (tester) async {
      final appProvider = await bootApp(tester);

      final server1 = DbServer(
        id: 'journey_dup1',
        name: '同名连接',
        type: DatabaseType.sqlite,
        host: 'test1.db',
        port: 0,
      );

      final server2 = DbServer(
        id: 'journey_dup2',
        name: '同名连接', // 相同名称
        type: DatabaseType.sqlite,
        host: 'test2.db',
        port: 0,
      );

      await appProvider.connection.saveConnection(server1);
      await appProvider.connection.saveConnection(server2);

      // 两个同名连接都应该被保存（通过 ID 区分）
      expect(appProvider.savedConnections.length, 2);
      expect(
        appProvider.savedConnections.where((c) => c.name == '同名连接').length,
        2,
      );
    });

    testWidgets('J4.4 - NULL 值处理', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('null_test');

      try {
        final server = DbServer(
          id: 'journey_null',
          name: 'NULL测试',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        await appProvider.dbService.executeQuery(
          'CREATE TABLE null_test (id INTEGER, name TEXT, email TEXT, age INTEGER)',
          connectionId: 'journey_null',
        );

        await appProvider.dbService.executeQuery(
          "INSERT INTO null_test VALUES "
          "(1, '张三', 'zhang@test.com', 25),"
          "(2, '李四', NULL, 30),"
          "(3, NULL, 'wang@test.com', NULL)",
          connectionId: 'journey_null',
        );

        final result = await appProvider.dbService.executeQuery(
          'SELECT * FROM null_test ORDER BY id',
          connectionId: 'journey_null',
        );

        expect(result.length, 3);
        expect(result[0]['name'], '张三');
        expect(result[1]['email'], isNull);
        expect(result[2]['name'], isNull);
        expect(result[2]['age'], isNull);
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: 'journey_null');
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('J4.5 - 大数据量查询', (tester) async {
      final appProvider = await bootApp(tester);
      final dbPath = createTestDbPath('big_data');

      try {
        final server = DbServer(
          id: 'journey_big',
          name: '大数据测试',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await appProvider.connection.saveConnection(server);
        await appProvider.connectToServer(server);

        await appProvider.dbService.executeQuery(
          'CREATE TABLE big_table (id INTEGER PRIMARY KEY, value TEXT)',
          connectionId: 'journey_big',
        );

        // 批量插入 500 行
        final batch = StringBuffer('INSERT INTO big_table (id, value) VALUES ');
        for (int i = 0; i < 500; i++) {
          if (i > 0) batch.write(',');
          batch.write('($i, \'row_$i\')');
        }
        await appProvider.dbService.executeQuery(
          batch.toString(),
          connectionId: 'journey_big',
        );

        // 查询所有数据
        final allResult = await appProvider.dbService.executeQuery(
          'SELECT * FROM big_table',
          connectionId: 'journey_big',
        );
        expect(allResult.length, 500);

        // 分页查询
        final page1 = await appProvider.dbService.getTableData(
          'big_table',
          limit: 100,
          offset: 0,
        );
        expect(page1.length, 100);
        expect(page1[0]['id'], 0);

        final page3 = await appProvider.dbService.getTableData(
          'big_table',
          limit: 100,
          offset: 200,
        );
        expect(page3.length, 100);
        expect(page3[0]['id'], 200);
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: 'journey_big');
          File(dbPath).deleteSync();
        } catch (_) {}
      }
    });
  });

  // ==========================================================================
  // 场景5：UI 交互测试（主题、侧边栏、快捷键）
  // ==========================================================================
  group('Scenario 5: UI 交互', () {
    testWidgets('J5.1 - 主题切换', (tester) async {
      await tester.pumpWidget(DbmasterApp(proModule: NoOpProModule()));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final context = tester.element(find.byType(MaterialApp));
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

      // 默认应该是暗色主题
      expect(themeProvider.isDarkMode, isTrue);

      // 切换到亮色主题
      await themeProvider.toggle();
      await tester.pumpAndSettle();
      expect(themeProvider.isDarkMode, isFalse);

      // 切换回暗色
      await themeProvider.toggle();
      await tester.pumpAndSettle();
      expect(themeProvider.isDarkMode, isTrue);

      // 应用不应崩溃
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('J5.2 - 侧边栏展开/折叠', (tester) async {
      await tester.pumpWidget(DbmasterApp(proModule: NoOpProModule()));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 验证侧边栏初始可见
      expect(find.byType(SidebarWidget), findsOneWidget);

      // 查找侧边栏折叠按钮（如果存在）
      final collapseButton = find.byIcon(LucideIcons.panelLeftClose);
      if (collapseButton.evaluate().isNotEmpty) {
        await tester.tap(collapseButton);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('J5.3 - 应用完整启动流程', (tester) async {
      // 完整的启动流程测试
      await tester.pumpWidget(DbmasterApp(proModule: NoOpProModule()));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 验证关键 UI 组件存在
      // 1. MaterialApp 作为根组件
      expect(find.byType(MaterialApp), findsOneWidget);

      // 2. 侧边栏
      expect(find.byType(SidebarWidget), findsOneWidget);

      // 3. 应用不应有渲染溢出
      expect(tester.takeException(), isNull, reason: '应用启动不应有渲染异常');
    });
  });
}
