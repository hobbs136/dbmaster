// ============================================================================
// Redis E2E AI Analysis Test - 真实数据库 + DeepSeek AI
//
// 覆盖 6 个 NoSQL 适配的 AI 分析场景（键值存储数据库）
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import '../config/redis_test_config.dart';
import 'e2e_ai_analysis_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Redis E2E AI Analysis', () {
    late RedisAdapter adapter;
    late String testKeyPrefix;

    setUp(() async {
      testKeyPrefix = RedisTestConfig.generateTestKeyPrefix();
      adapter = RedisAdapter();
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('FLUSHDB'); // 清空当前数据库
        await adapter.disconnect();
      } catch (_) {}
    });

    testWidgets('场景1 - 基础查询 + AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'redis_e2e_test',
        name: 'Redis E2E AI Test',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        username: '',
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to Redis（DBMASTER_REDIS_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      // 使用 Hash 存储用户数据
      await adapter.executeQuery('HSET user:1 name "Alice" email "alice@example.com"');
      await adapter.executeQuery('HSET user:2 name "Bob" email "bob@example.com"');
      await adapter.executeQuery('HSET user:3 name "Charlie" email "charlie@example.com"');

      final query = 'HGETALL user:1';
      final queryResult = await adapter.executeQuery(query);

      expect(queryResult.rows.length, greaterThan(0), reason: 'Should have hash data');

      final prompt = generateQueryAnalysisPrompt(query, {
        'rowCount': 1,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
        'databaseType': 'NoSQL Key-Value Store (Redis Hash)',
        'dataType': 'Hash',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.redis);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景2 - 复杂查询（Redis 脚本）+ AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'redis_e2e_scenario2',
        name: 'Redis E2E AI Test Scenario 2',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        username: '',
        password: RedisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to Redis（DBMASTER_REDIS_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      // 使用 Sorted Set 存储订单数据
      await adapter.executeQuery('ZADD orders 100 user1:ProductA');
      await adapter.executeQuery('ZADD orders 200 user1:ProductB');
      await adapter.executeQuery('ZADD orders 150 user2:ProductC');
      await adapter.executeQuery('ZADD orders 300 user3:ProductD');

      // 复杂查询：使用 ZRANGE 获取某个用户的数据
      final query = 'ZRANGE orders 0 0 WITHSCORES';
      final queryResult = await adapter.executeQuery(query);

      final prompt = generateQueryAnalysisPrompt(query, {
        'queryType': 'Redis Sorted Set range query with scores',
        'rowCount': queryResult.rows.length,
        'columns': queryResult.columns,
        'sampleRows': queryResult.rows,
        'explanation': 'Using Sorted Set to store user orders with scores',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.redis);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景3 - DML 操作 + AI 验证', (tester) async {
      final connection = DatabaseConnection(
        id: 'redis_e2e_scenario3',
        name: 'Redis E2E AI Test Scenario 3',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        username: '',
        password: RedisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to Redis（DBMASTER_REDIS_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      // 使用 Hash 存储账户
      await adapter.executeQuery('HSET ${testKeyPrefix}:account:A name "Account A" balance 1000');
      await adapter.executeQuery('HSET ${testKeyPrefix}:account:B name "Account B" balance 2000');
      await adapter.executeQuery('HINCRBY ${testKeyPrefix}:account:A balance 500'); // UPDATE: 增加500
      await adapter.executeQuery('DEL ${testKeyPrefix}:account:C'); // DELETE: 如果存在则删除

      final result = await adapter.executeQuery('HGETALL account:A');

      final prompt = '''
请验证以下 Redis DML 操作的正确性：

1. HSET：插入账户数据，初始余额为 1000
2. HINCRBY：Account A 余额增加 500
3. DEL：删除 Account C（如果存在）

当前数据库状态：
${result.rows.map((row) => '- ${row.entries.map((e) => '${e.key}: ${e.value}').join(', ')}').join('\n')}

请分析：操作是否正确？数据是否一致？
''';

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.redis);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景4 - 大结果集 + AI 总结', (tester) async {
      final connection = DatabaseConnection(
        id: 'redis_e2e_scenario4',
        name: 'Redis E2E AI Test Scenario 4',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        username: '',
        password: RedisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to Redis（DBMASTER_REDIS_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      // 批量插入1000个产品到 List
      for (int i = 1; i <= 1000; i++) {
        final category = ['Electronics', 'Books', 'Clothing', 'Food', 'Sports'][i % 5];
        final value = 'Product:$i:$category:${i * 1.0}:${i % 100}';
        await adapter.executeQuery('LPUSH products $value');
      }

      // 使用 LRANGE 获取所有产品
      final query = 'LRANGE products 0 999';
      final queryResult = await adapter.executeQuery(query);

      final prompt = generateQueryAnalysisPrompt(query, {
        'totalProducts': 1000,
        'listLength': queryResult.rows.length,
        'dataType': 'Redis List',
        'analysis': 'Product data stored in Redis List structure',
      });

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.redis);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景5 - 查询历史 + AI 分析', (tester) async {
      final connection = DatabaseConnection(
        id: 'redis_e2e_scenario5',
        name: 'Redis E2E AI Test Scenario 5',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        username: '',
        password: RedisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to Redis（DBMASTER_REDIS_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      final queries = [
        'DBSIZE',
        'KEYS user:*',
        'SCAN 0 COUNT 1000',
        'TYPE user:1',
        'TTL user:1',
      ];

      final queryHistory = <Map<String, dynamic>>[];
      for (final query in queries) {
        await adapter.executeQuery(query);
        queryHistory.add({
          'query': query,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      final prompt = generateHistoryAnalysisPrompt(queryHistory);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.redis);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });

    testWidgets('场景6 - Schema 信息 + AI 解释', (tester) async {
      final connection = DatabaseConnection(
        id: 'redis_e2e_scenario6',
        name: 'Redis E2E AI Test Scenario 6',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        username: '',
        password: RedisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      if (!connected) {
        markTestSkipped(
            'Failed to connect to Redis（DBMASTER_REDIS_* 未通过 --dart-define 提供？开源剥离默认凭据）');
        return;
      }

      // 创建不同数据结构示例
      await adapter.executeQuery('SET customer:1:name "Alice"');
      await adapter.executeQuery('HSET product:1 name "Laptop" price 999');
      await adapter.executeQuery('LPUSH orders:1 order_data_1');
      await adapter.executeQuery('SADD categories electronics books');
      await adapter.executeQuery('ZADD leaderboard 100 "player1" 200 "player2"');

      final schema = {
        'dataStructures': {
          'String': 'customer:1:name',
          'Hash': 'product:1 (name, price)',
          'List': 'orders:1',
          'Set': 'categories',
          'Sorted Set': 'leaderboard',
        },
        'keyPatterns': {
          'customers': 'customer:*',
          'products': 'product:*',
          'orders': 'orders:*',
          'categories': 'categories',
          'leaderboard': 'leaderboard',
        },
        'designPattern': 'Multi-data-type schema using Redis native structures',
      };

      final prompt = generateSchemaExplanationPrompt(schema);

      final aiResponse = await callDeepSeekAPI(prompt, databaseType: DatabaseType.redis);

      expect(aiResponse.success, isTrue, reason: 'AI analysis should succeed');
      expect(aiResponse.content.isNotEmpty, isTrue);
      expect(aiResponse.error, isNull);
    });
  });
}
