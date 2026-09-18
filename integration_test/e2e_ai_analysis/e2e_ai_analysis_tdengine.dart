// ============================================================================
// TDengine E2E AI Analysis Test - 真实数据库 + DeepSeek AI
//
// 覆盖 6 个 AI 分析场景（时序数据库）
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/tdengine_adapter.dart';
import '../config/tdengine_test_config.dart';
import '../helpers/td_gateway_e2e_helper.dart';
import 'e2e_ai_analysis_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // T29 TDengine 批次：TDengine 网关壳硬依赖 dbmaster server 会话（embedded
  // 前置，D6）。二进制不可得时全组以可 grep 的 TD_E2E_SKIP 跳过（对齐
  // e2e_ai_analysis_mongodb）；AI 调用另需 DEEPSEEK_API_KEY（helper 抛错）。
  var tdE2EGatewayReady = false;
  setUpAll(() async {
    tdE2EGatewayReady = await ensureEmbeddedServerForTdE2E();
    if (tdE2EGatewayReady && !TDengineTestConfig.available) {
      // ignore: avoid_print
      print('TD_E2E_SKIP: DBMASTER_TDENGINE_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      tdE2EGatewayReady = false;
    }
  });

  group('TDengine E2E AI Analysis', () {
    late TDengineAdapter adapter;
    late String testDbName;

    setUp(() async {
      testDbName = TDengineTestConfig.generateTestDatabaseName();
      adapter = TDengineAdapter();
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
        await adapter.disconnect();
      } catch (_) {}
    });

    testWidgets('场景1 - 基础查询 + AI 分析', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'tdengine_e2e_test',
        name: 'TDengine E2E AI Test',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to TDengine');

      await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS $testDbName');
      await adapter.useDatabase(testDbName);

      // 创建超级表
      await adapter.executeQuery('''
        CREATE STABLE IF NOT EXISTS meters (
          ts TIMESTAMP,
          current FLOAT,
          voltage INT,
          phase FLOAT
        ) TAGS (location BINARY(64), groupId INT)
      ''');

      // 创建子表并插入数据
      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS d1001 USING meters TAGS ("Beijing.Chaoyang", 2)');
      await adapter.executeQuery('INSERT INTO d1001 VALUES (NOW, 11.5, 219, 0.32)');
      await adapter.executeQuery('INSERT INTO d1001 VALUES (NOW + 1s, 12.6, 218, 0.33)');
      await adapter.executeQuery('INSERT INTO d1001 VALUES (NOW + 2s, 13.7, 217, 0.34)');

      final sql = 'SELECT * FROM d1001';
      final queryResult = await adapter.executeQuery(sql);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have data');

      final prompt = generateQueryAnalysisPrompt(sql, {
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows.take(3).toList(),
        'databaseType': 'Time Series Database',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.tdengine);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景2 - 复杂查询 + AI 分析', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'tdengine_e2e_scenario2',
        name: 'TDengine E2E AI Test Scenario 2',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to TDengine');

      await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS $testDbName');
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE STABLE IF NOT EXISTS device_data (
          ts TIMESTAMP,
          temperature FLOAT,
          humidity FLOAT
        ) TAGS (device_type BINARY(64), location BINARY(64))
      ''');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS device1 USING device_data TAGS ("sensor", "room_a")');
      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS device2 USING device_data TAGS ("sensor", "room_b")');

      await adapter.executeQuery('INSERT INTO device1 VALUES (NOW, 22.5, 45.0)');
      await adapter.executeQuery('INSERT INTO device1 VALUES (NOW + 1s, 23.0, 46.0)');
      await adapter.executeQuery('INSERT INTO device2 VALUES (NOW, 21.0, 50.0)');
      await adapter.executeQuery('INSERT INTO device2 VALUES (NOW + 1s, 21.5, 51.0)');

      final sql = '''SELECT location, AVG(temperature) as avg_temp, AVG(humidity) as avg_humidity
        FROM device_data
        WHERE ts >= NOW - INTERVAL 1 HOUR
        GROUP BY location''';

      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'queryType': 'Time series aggregation',
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.tdengine);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景3 - DML 操作 + AI 验证', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'tdengine_e2e_scenario3',
        name: 'TDengine E2E AI Test Scenario 3',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to TDengine');

      await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS $testDbName');
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE STABLE IF NOT EXISTS metrics (
          ts TIMESTAMP,
          value DOUBLE
        ) TAGS (metric_name BINARY(64))
      ''');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS metric1 USING metrics TAGS ("cpu_usage")');

      await adapter.executeQuery('INSERT INTO metric1 VALUES (NOW, 50.0)');
      await adapter.executeQuery('INSERT INTO metric1 VALUES (NOW + 1s, 60.0)');
      await adapter.executeQuery('INSERT INTO metric1 VALUES (NOW + 2s, 70.0)');

      final result = await adapter.executeQuery('SELECT AVG(value) as avg_value FROM metric1');

      final prompt = '''
请验证以下 TDengine 时序数据操作：

1. 插入了3条时序数据，值分别为 50.0, 60.0, 70.0
2. 查询计算平均值

当前查询结果：
${result.rows.map((row) => '- Average value: ${row['avg_value']}').join('\n')}

请分析：操作是否正确？平均值计算是否准确？
''';

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.tdengine);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景4 - 大结果集 + AI 总结', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'tdengine_e2e_scenario4',
        name: 'TDengine E2E AI Test Scenario 4',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to TDengine');

      await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS $testDbName');
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE STABLE IF NOT EXISTS sensor_readings (
          ts TIMESTAMP,
          value FLOAT
        ) TAGS (sensor_id INT)
      ''');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS sensor1 USING sensor_readings TAGS (1)');

      // 批量插入1000条时序数据
      for (int i = 0; i < 1000; i++) {
        final value = (20.0 + (i % 10)).toStringAsFixed(2);
        await adapter.executeQuery("INSERT INTO sensor1 VALUES (NOW + ${i}m, $value)");
      }

      final sql = 'SELECT COUNT(*) as reading_count, AVG(value) as avg_value, MAX(value) as max_value FROM sensor_readings WHERE ts >= NOW - INTERVAL 1 DAY';
      final queryResult = await adapter.executeQuery(sql);

      final prompt = generateQueryAnalysisPrompt(sql, {
        'totalReadings': 1000,
        'aggregation': queryResult.rows,
        'analysis': 'Time series data aggregation',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.tdengine);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景5 - 查询历史 + AI 分析', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'tdengine_e2e_scenario5',
        name: 'TDengine E2E AI Test Scenario 5',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to TDengine');

      await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS $testDbName');
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE STABLE IF NOT EXISTS logs (
          ts TIMESTAMP,
          level BINARY(10),
          message BINARY(200)
        ) TAGS (service BINARY(64))
      ''');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS log1 USING logs TAGS ("api_service")');

      final queries = [
        'SELECT COUNT(*) FROM logs WHERE ts >= NOW - INTERVAL 1 HOUR',
        'SELECT level, COUNT(*) FROM logs WHERE ts >= NOW - INTERVAL 1 HOUR GROUP BY level',
        'SELECT * FROM logs WHERE ts >= NOW - INTERVAL 10 MINUTES LIMIT 10',
        'SELECT service, COUNT(*) FROM logs WHERE ts >= NOW - INTERVAL 1 HOUR GROUP BY service',
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

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.tdengine);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景6 - Schema 信息 + AI 解释', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'tdengine_e2e_scenario6',
        name: 'TDengine E2E AI Test Scenario 6',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to TDengine');

      await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS $testDbName');
      await adapter.useDatabase(testDbName);

      await adapter.executeQuery('''
        CREATE STABLE IF NOT EXISTS temperature_stable (
          ts TIMESTAMP,
          temp FLOAT
        ) TAGS (location BINARY(64), device_id BINARY(64))
      ''');

      await adapter.executeQuery('CREATE STABLE IF NOT EXISTS humidity_stable (ts TIMESTAMP, humidity FLOAT) TAGS (location BINARY(64))');

      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS temp_sensor1 USING temperature_stable TAGS ("building_a", "sensor_001")');
      await adapter.executeQuery('CREATE TABLE IF NOT EXISTS humid_sensor1 USING humidity_stable TAGS ("building_a")');

      final schema = {
        'stables': ['temperature_stable', 'humidity_stable'],
        'subtables': ['temp_sensor1', 'humid_sensor1'],
        'tags': {
          'temperature_stable': ['location', 'device_id'],
          'humidity_stable': ['location'],
        },
        'columns': {
          'temperature_stable': ['ts TIMESTAMP', 'temp FLOAT'],
          'humidity_stable': ['ts TIMESTAMP', 'humidity FLOAT'],
        },
      };

      final prompt = '''
请解释以下 TDengine 时序数据库 Schema：

数据库类型：时序数据库 (Time Series Database)

超级表（STABLE）：
${(schema['stables'] as List).map((s) => '- $s').join('\n')}

子表：
${(schema['subtables'] as List).map((s) => '- $s').join('\n')}

标签（TAGS）：
${(schema['tags'] as Map).entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}

数据列：
${(schema['columns'] as Map).entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}

请分析：
1. 超级表设计是否合理？
2. 标签选择是否适合时序查询？
3. 数据模型是否优化？
''';

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.tdengine);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });
  });
}
