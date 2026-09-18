// ============================================================================
// 通用数据库 Agent · 反向外键 + 只读查询工具 真实库集成测试
//
// 覆盖（acceptance 场景 = 用户原始诉求「删除 SELECT 查出的数据前找关联」）：
// - MySQL：getReferencingForeignKeys 经 information_schema 快路径反查
//   引用父表的子表（含 ON DELETE 动作）；run_readonly_query 白名单放行 /
//   写语句被拒（真实网关通道）；get_table_relationships 工具全链输出；
// - PostgreSQL：同款反查（referential_constraints 规则列）；
// - SQLite：PRAGMA 全表扫描默认实现。
//
// 每库自建自删专用库（generateTestDatabaseName），不污染共享状态。
// MySQL 族网关壳硬依赖 embedded server：不可得时打印 *_E2E_SKIP 跳过。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/pro/ai/ai_agent_service.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/mysql_test_config.dart';
import 'config/postgresql_test_config.dart';
import 'config/sqlite_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  var gatewayReady = false;
  setUpAll(() async {
    gatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (gatewayReady &&
        (!MySQLTestConfig.available || !PostgreSQLTestConfig.available)) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* / DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      gatewayReady = false;
    }
  });

  group('MySQL 反向外键 + 只读工具（真实库）', () {
    late MySQLAdapter adapter;
    late String dbName;

    setUp(() {
      adapter = MySQLAdapter();
      dbName = MySQLTestConfig.generateTestDatabaseName();
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$dbName`');
          await adapter.disconnect();
        }
      } catch (_) {
        // 清理尽力而为
      }
    });

    testWidgets('反查引用 tasks 的子表 + 工具全链 + 只读写拒', (tester) async {
      if (!gatewayReady) {
        // ignore: avoid_print
        print('MYSQL_E2E_SKIP: embedded server not available');
        return;
      }

      final ok = await adapter.connect(
        DatabaseConnection(
          id: 'ai_agent_fk_mysql',
          name: 'AI Agent FK MySQL',
          type: DatabaseType.mysql,
          host: MySQLTestConfig.host,
          port: MySQLTestConfig.port,
          username: MySQLTestConfig.username,
          password: MySQLTestConfig.password,
          database: MySQLTestConfig.database,
        ),
      );
      expect(ok, isTrue, reason: '连接测试库失败');

      await adapter.executeQuery('CREATE DATABASE `$dbName`');
      await adapter.useDatabase(dbName);
      await adapter.executeQuery('''
        CREATE TABLE projects (
          id INT PRIMARY KEY
        ) ENGINE=InnoDB
      ''');
      await adapter.executeQuery('''
        CREATE TABLE tasks (
          id INT PRIMARY KEY,
          project_id INT NOT NULL,
          assignee_id INT NOT NULL,
          iteration_id INT NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects(id)
        ) ENGINE=InnoDB
      ''');
      await adapter.executeQuery('''
        CREATE TABLE task_comments (
          id INT PRIMARY KEY,
          task_id INT NOT NULL,
          FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
        ) ENGINE=InnoDB
      ''');

      // --- 反向外键：谁引用 tasks ---
      final refs = await adapter.getReferencingForeignKeys('tasks');
      expect(refs, hasLength(1), reason: 'task_comments 应被反查到');
      expect(refs.first.table, 'task_comments');
      expect(refs.first.column, 'task_id');
      expect(refs.first.referencedColumn, 'id');
      expect(refs.first.onDelete, 'CASCADE');

      // --- get_table_relationships 工具全链（agent 工具分发 → adapter）---
      final agent = AiAgentService(adapter: adapter, selectedDatabase: dbName);
      final rel = await agent.executeToolForTesting('get_table_relationships', {
        'table': 'tasks',
      });
      expect(rel.success, isTrue);
      expect(rel.output, contains('task_comments'));
      expect(rel.output, contains('CASCADE'));
      expect(rel.output, contains('projects'));

      // --- run_readonly_query：白名单放行（真库真数据）---
      await adapter.executeQuery("INSERT INTO tasks VALUES (1, 1, 7, 4)");
      final readonly = await agent.executeToolForTesting('run_readonly_query', {
        'sql':
            'SELECT COUNT(*) AS n FROM tasks WHERE assignee_id = 7 AND iteration_id = 4',
      });
      expect(readonly.success, isTrue);
      expect(readonly.output, contains('1'));

      // --- run_readonly_query：写语句拒绝（不触达数据库）---
      final denied = await agent.executeToolForTesting('run_readonly_query', {
        'sql': 'DELETE FROM tasks WHERE assignee_id = 7',
      });
      expect(denied.success, isFalse);
      expect(denied.output, contains('read-only guard'));
      final stillThere = await adapter.executeQuery(
        'SELECT COUNT(*) AS n FROM tasks',
      );
      expect(stillThere.rows.first['n'], 1, reason: '数据应未被删除');
    });
  });

  group('PostgreSQL 反向外键（真实库）', () {
    late PostgreSQLAdapter adapter;
    late String dbName;

    setUp(() {
      adapter = PostgreSQLAdapter();
      dbName = PostgreSQLTestConfig.generateTestDatabaseName();
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          await adapter.disconnect();
        }
      } catch (_) {
        // 清理尽力而为
      }
    });

    testWidgets('referential_constraints 反查子表与 ON DELETE', (tester) async {
      if (!gatewayReady) {
        // ignore: avoid_print
        print('MYSQL_E2E_SKIP: embedded server not available (PG 网关同样依赖)');
        return;
      }

      final ok = await adapter.connect(
        DatabaseConnection(
          id: 'ai_agent_fk_pg',
          name: 'AI Agent FK PG',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: PostgreSQLTestConfig.database,
        ),
      );
      expect(ok, isTrue, reason: '连接测试库失败');

      await adapter.executeQuery('CREATE DATABASE "$dbName"');
      await adapter.disconnect();
      final okDb = await adapter.connect(
        DatabaseConnection(
          id: 'ai_agent_fk_pg',
          name: 'AI Agent FK PG',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: dbName,
        ),
      );
      expect(okDb, isTrue);

      try {
        await adapter.executeQuery(
          'CREATE TABLE projects (id INT PRIMARY KEY)',
        );
        await adapter.executeQuery('''
          CREATE TABLE tasks (
            id INT PRIMARY KEY,
            project_id INT NOT NULL REFERENCES projects(id)
          )
        ''');
        await adapter.executeQuery('''
          CREATE TABLE task_comments (
            id INT PRIMARY KEY,
            task_id INT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE
          )
        ''');

        final refs = await adapter.getReferencingForeignKeys('tasks');
        expect(refs, hasLength(1));
        expect(refs.first.table, 'task_comments');
        expect(refs.first.onDelete, 'CASCADE');

        final agent = AiAgentService(
          adapter: adapter,
          selectedDatabase: dbName,
        );
        final rel = await agent.executeToolForTesting(
          'get_table_relationships',
          {'table': 'tasks'},
        );
        expect(rel.success, isTrue);
        expect(rel.output, contains('task_comments'));
      } finally {
        // 回到管理库删测试库（PG 不允许删当前连接库）
        await adapter.disconnect();
        final admin = PostgreSQLAdapter();
        await admin.connect(
          DatabaseConnection(
            id: 'ai_agent_fk_pg_admin',
            name: 'AI Agent FK PG Admin',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: PostgreSQLTestConfig.database,
          ),
        );
        await admin.executeQuery('DROP DATABASE IF EXISTS "$dbName"');
        await admin.disconnect();
      }
    });
  });

  group('SQLite 反向外键（本地文件，默认扫描实现）', () {
    testWidgets('PRAGMA 扫描反查子表', (tester) async {
      final dbPath = SQLiteTestConfig.generateTestDatabasePath();
      addTearDown(() async {
        await SQLiteTestConfig.cleanupDatabase(dbPath);
      });

      final adapter = SQLiteAdapter();
      final ok = await adapter.connect(
        DatabaseConnection(
          id: 'ai_agent_fk_sqlite',
          name: 'AI Agent FK SQLite',
          type: DatabaseType.sqlite,
          host: 'localhost',
          port: 0,
          username: '',
          password: '',
          database: dbPath,
        ),
      );
      expect(ok, isTrue);

      await adapter.executeQuery('''
        CREATE TABLE projects (id INTEGER PRIMARY KEY)
      ''');
      await adapter.executeQuery('''
        CREATE TABLE tasks (
          id INTEGER PRIMARY KEY,
          project_id INTEGER NOT NULL REFERENCES projects(id)
        )
      ''');
      await adapter.executeQuery('''
        CREATE TABLE task_comments (
          id INTEGER PRIMARY KEY,
          task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE
        )
      ''');

      final refs = await adapter.getReferencingForeignKeys('tasks');
      expect(refs, hasLength(1));
      expect(refs.first.table, 'task_comments');
      expect(refs.first.onDelete, 'CASCADE');

      final agent = AiAgentService(adapter: adapter, selectedDatabase: dbPath);
      // SQLite 的 PRAGMA 只读名单放行
      final pragma = await agent.executeToolForTesting('run_readonly_query', {
        'sql': 'PRAGMA foreign_key_list(task_comments)',
      });
      expect(pragma.success, isTrue);
      expect(pragma.output, contains('tasks'));

      await adapter.disconnect();
    });
  });
}
