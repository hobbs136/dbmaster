// ============================================================================
// MySQL JSON columnTypes E2E（跨库验证）
// MySQL: result.cols type=0xf5 → json。验证 MySQL JSON 列被识别。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

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

  group('MySQL JSON columnTypes E2E（T031）', () {
    late MySQLAdapter adapter;
    late String dbName;
    late String tableName;

    setUp(() async {
      adapter = MySQLAdapter();
      final ts = DateTime.now().millisecondsSinceEpoch;
      dbName = 'dbmaster_json_e2e_$ts';
      tableName = 'json_test_$ts';

      final conn = DatabaseConnection(
        id: 'mysql_json_e2e',
        name: 'MySQL JSON E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      final connected = await adapter.connect(conn);
      expect(connected, isTrue, reason: '无法连接 MySQL 测试库');

      await adapter.createDatabase(dbName);
      await adapter.useDatabase(dbName);

      // 造表：含 JSON 列（MySQL 原生 JSON 类型）+ 普通文本列
      await adapter.executeQuery(
        'CREATE TABLE `$tableName` ('
        'id INT PRIMARY KEY AUTO_INCREMENT, '
        'profile JSON, '
        'name VARCHAR(100)'
        ')',
      );
      await adapter.executeQuery(
        "INSERT INTO `$tableName` (profile, name) VALUES "
        "('{\"age\": 30, \"city\": \"Shanghai\"}', 'Alice'), "
        "('{\"age\": 25, \"city\": \"Beijing\"}', 'Bob')",
      );
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$dbName`');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
    });

    test('T031: MySQL JSON 列识别为 json', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery(
        'SELECT id, profile, name FROM `$tableName`',
      );
      expect(result.columnTypes, isNotNull, reason: '应返回 columnTypes');
      expect(result.columnTypes!['profile'], 'json',
          reason: 'profile 是 MySQL JSON 类型 → 应识别为 json');
      // name 是 VARCHAR，不应识别为 JSON
      expect(result.columnTypes!['name'], isNot('json'));
      print('MySQL columnTypes: ${result.columnTypes}');
    });

    test('T031: MySQL isJsonColumn 对 JSON 列返回 true', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final isJson = await adapter.isJsonColumn(tableName, 'profile');
      expect(isJson, isTrue, reason: 'profile 应识别为 JSON 列');
      final notJson = await adapter.isJsonColumn(tableName, 'name');
      expect(notJson, isFalse, reason: 'name 不应识别为 JSON 列');
    });

    test('T031: US4 MySQL JSON_EXTRACT SQL 真实执行', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // 验证 MySQL 的 JSON_EXTRACT 语法能真实执行
      final sql =
          "SELECT id, profile, JSON_EXTRACT(profile, '\$.age') AS age FROM `$tableName`";
      final result = await adapter.executeQuery(sql);
      expect(result.rows.length, 2);
      // 提取的 age 值
      expect(result.rows.first['age'], isNotNull);
      print('MySQL JSON_EXTRACT 第一行 age: ${result.rows.first['age']}');
    });
  });
}
