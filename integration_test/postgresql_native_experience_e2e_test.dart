// ============================================================================
// PG 原生体验 E2E
// 覆盖：US1 扩展浏览器 / US2 pgvector（有则测）/ US3 JSONB columnTypes /
//       US4 JSON 字段提取 SQL 真实可执行
// 连真实 PostgreSQL（config/postgresql_test_config.dart），连不上 fail。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/organisms/results/json_field_picker.dart';
import 'config/postgresql_test_config.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

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

  group('PG 原生体验 E2E', () {
    late PostgreSQLAdapter adapter;
    late String testTable;

    setUp(() async {
      if (!pgE2EGatewayReady) {
        return;
      }
      adapter = PostgreSQLAdapter();
      final conn = DatabaseConnection(
        id: 'pg_native_e2e',
        name: 'PG Native E2E',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
      final connected = await adapter.connect(conn);
      expect(connected, isTrue, reason: '无法连接测试 PG 库');

      // 造唯一临时表（JSONB 列）
      testTable = 'pg_native_e2e_${DateTime.now().millisecondsSinceEpoch}';
      await adapter.executeQuery('''
        CREATE TABLE "$testTable" (
          id SERIAL PRIMARY KEY,
          profile JSONB NOT NULL,
          name TEXT
        )
      ''');
      await adapter.executeQuery("""
        INSERT INTO "$testTable" (profile, name) VALUES
        ('{"age": 30, "city": "Shanghai", "active": true}', 'Alice'),
        ('{"age": 25, "city": "Beijing", "active": false}', 'Bob'),
        ('{"age": 35, "city": "Shenzhen"}', 'Charlie')
      """);
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP TABLE IF EXISTS "$testTable"');
        await adapter.disconnect();
      } catch (_) {}
    });

    // ============================================================
    // US1: 扩展浏览器
    // ============================================================
    group('US1 扩展浏览器', () {
      test('getExtensions 返回已安装扩展列表', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        final exts = await adapter.getExtensions();
        expect(exts, isNotEmpty, reason: 'PG 库应至少有一个已安装扩展');
        // 标准库总有 pg_catalog 等；每个扩展应有 name + version
        for (final ext in exts) {
          expect(ext.name, isNotEmpty);
        }
        print('US1: 已安装扩展 ${exts.map((e) => '${e.name}@${e.version}').toList()}');
      });

      test('扩展成员查询返回分类列表', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        final exts = await adapter.getExtensions();
        if (exts.isEmpty) return;
        // 取第一个扩展查成员（不强制非空——某些扩展可能无注册成员）
        final members = await adapter.getExtensionMembers(exts.first.name);
        expect(members, contains('types'));
        expect(members, contains('functions'));
        expect(members, contains('operators'));
      });
    });

    // ============================================================
    // US2: pgvector（有 vector 扩展才测，否则 skip）
    // ============================================================
    group('US2 pgvector', () {
      test('getVectorIndexes（无 pgvector 时返回空，有则返回索引列表）', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        final exts = await adapter.getExtensions();
        final hasPgvector = exts.any((e) => e.name == 'vector');
        if (!hasPgvector) {
          print('US2: SKIP — 测试库未安装 pgvector');
          return;
        }
        final indexes = await adapter.getVectorIndexes();
        // 不强制非空（可能无 vector 索引），但调用不应抛
        print('US2: pgvector 已安装，vector 索引 ${indexes.length} 个');
        for (final vi in indexes) {
          expect(vi.name, isNotEmpty);
          expect(vi.tableName, isNotEmpty);
        }
      });
    });

    // ============================================================
    // US3: JSONB columnTypes
    // ============================================================
    group('US3 JSONB columnTypes', () {
      test('executeQuery 返回的 columnTypes 标注 JSONB 列', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        final result = await adapter.executeQuery('SELECT id, profile, name FROM "$testTable"');
        expect(result.columnTypes, isNotNull, reason: '应返回 columnTypes 映射');
        expect(result.columnTypes!['profile'], equals('jsonb'),
            reason: 'profile 列应识别为 jsonb');
        // 非 JSON 列不在 columnTypes 里（或不是 json）
        expect(result.columnTypes!['id'], isNot(equals('jsonb')));
      });

      test('isJsonColumn 对 JSONB 列返回 true', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        final isJson = await adapter.isJsonColumn(testTable, 'profile');
        expect(isJson, isTrue, reason: 'profile 应识别为 JSON 列');
        final notJson = await adapter.isJsonColumn(testTable, 'name');
        expect(notJson, isFalse, reason: 'name 应识别为非 JSON 列');
      });
    });

    // ============================================================
    // US4: JSON 字段提取 SQL 真实可执行
    // ============================================================
    group('US4 JSON 字段提取 SQL', () {
      test('PG 单层字段提取 SQL 真实执行', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        final sql = JsonExtractionSql.generate(
          columnName: 'profile',
          fieldPath: 'age',
          databaseType: DatabaseType.postgresql,
          sourceTable: testTable,
          originalColumns: ['id', 'profile', 'name'],
        );
        // sql 形如 SELECT "id","profile","name", "profile"->>'age' AS "age" FROM <t>
        print('US4 生成 SQL: $sql');
        final result = await adapter.executeQuery(sql);
        expect(result.rows.length, 3);
        // 提取的 age 列应存在且为文本
        for (final row in result.rows) {
          expect(row.containsKey('age'), isTrue, reason: '应含提取的 age 列');
          // age 字段值（->> 取 text）
          expect(row['age'], isNotNull);
        }
      });

      test('PG 嵌套字段提取 SQL 真实执行', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        // 造嵌套 JSON 数据
        await adapter.executeQuery("""
          UPDATE "$testTable" SET profile = '{"contact": {"email": "a@b.c"}}' WHERE id = 1
        """);
        final sql = JsonExtractionSql.generate(
          columnName: 'profile',
          fieldPath: 'contact.email',
          databaseType: DatabaseType.postgresql,
          sourceTable: testTable,
          originalColumns: ['id', 'profile'],
        );
        print('US4 嵌套 SQL: $sql');
        final result = await adapter.executeQuery(sql);
        expect(result.rows.length, 3);
        // id=1 的行应能取出 email（其它行无此字段→null）
        final row1 = result.rows.firstWhere((r) => r['id'] == 1);
        expect(row1['email'], 'a@b.c');
      });

      test('保留所有原列（FR-018）', () async {
        if (!pgE2EGatewayReady) {
          return;
        }
        final sql = JsonExtractionSql.generate(
          columnName: 'profile',
          fieldPath: 'city',
          databaseType: DatabaseType.postgresql,
          sourceTable: testTable,
          originalColumns: ['id', 'profile', 'name'],
        );
        final result = await adapter.executeQuery(sql);
        final firstRow = result.rows.first;
        // 原列 + 提取列都应在
        expect(firstRow.containsKey('id'), isTrue);
        expect(firstRow.containsKey('profile'), isTrue);
        expect(firstRow.containsKey('name'), isTrue);
        expect(firstRow.containsKey('city'), isTrue);
      });
    });
  });
}
