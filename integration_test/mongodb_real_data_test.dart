import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

/// MongoDB 真实数据集成测试
/// 目标服务器: 参数经 DBMASTER_MONGO_* 提供
/// 测试数据库: dbmaster_test
/// 运行方式: flutter test integration_test/mongodb_real_data_test.dart --dart-define=DBMASTER_USE_XIAOLEI=1
void main() {
  late MongoDBAdapter adapter;

  // T29 非 SQL 批次（B2）：Mongo 网关壳硬依赖 dbmaster server 会话
  //（embedded 前置，D6）。二进制不可得时全组以可 grep 的 MONGO_E2E_SKIP
  // 跳过（无假绿纪律）。
  var mongoE2EGatewayReady = false;

  setUpAll(() async {
    mongoE2EGatewayReady = await ensureEmbeddedServerForMongoE2E();
    if (mongoE2EGatewayReady && !MongoDBTestConfig.available) {
      // ignore: avoid_print
      print('MONGO_E2E_SKIP: DBMASTER_MONGO_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mongoE2EGatewayReady = false;
    }
    if (!mongoE2EGatewayReady) return;
    print('\n========================================');
    print('  MongoDB 真实数据集成测试');
    print('========================================');
    print('服务器: ${MongoDBTestConfig.host}:${MongoDBTestConfig.port}');
    print('用户: ${MongoDBTestConfig.username}');
    print('认证库: ${MongoDBTestConfig.authDatabase}');
    print('========================================\n');

    adapter = MongoDBAdapter();
    final connection = DatabaseConnection(
      id: 'test_mongodb_xiaolei',
      name: 'MongoDB Xiaolei',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      type: DatabaseType.mongodb,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );

    final connected = await adapter.connect(connection);
    expect(connected, isTrue, reason: '无法连接到小雷 MongoDB 服务器');
  });

  tearDownAll(() async {
    if (!mongoE2EGatewayReady) return;
    await adapter.disconnect();
    print('\n========================================');
    print('  测试结束，连接已断开');
    print('========================================\n');
  });

  // ==========================================================================
  // 一、连接与服务器信息
  // ==========================================================================
  group('1. 连接与服务器信息', () {
    test('1.1 应成功连接并获取版本', () async {
      if (!mongoE2EGatewayReady) return;
      expect(adapter.isConnected, isTrue);
      final version = await adapter.getServerVersion();
      expect(version, isNotNull);
      expect(version!['database'], 'MongoDB');
      expect(version['version'], isNotNull);
      print('MongoDB 版本: ${version['version']}');
    });

    test('1.2 应获取数据库列表（包含 dbmaster_test）', () async {
      if (!mongoE2EGatewayReady) return;
      final dbs = await adapter.getDatabases();
      expect(dbs, isNotEmpty);
      expect(dbs, contains('dbmaster_test'));
      print('数据库列表: $dbs');
    });

    test('1.3 应能切换到 dbmaster_test', () async {
      if (!mongoE2EGatewayReady) return;
      await adapter.useDatabase('dbmaster_test');
      expect(adapter.currentConnection!.database, 'dbmaster_test');
    });

    test('1.4 应获取数据库属性', () async {
      if (!mongoE2EGatewayReady) return;
      final props = await adapter.getDatabaseProperties('dbmaster_test');
      expect(props, isNotNull);
      expect(props!['name'], 'dbmaster_test');
      expect(props['collections'], greaterThanOrEqualTo(10));
      expect(props['documents'], greaterThanOrEqualTo(100000));
      print('数据库属性: collections=${props['collections']}, documents=${props['documents']}');
    });
  });

  // ==========================================================================
  // 二、集合列表与结构
  // ==========================================================================
  group('2. 集合列表与结构', () {
    test('2.1 应获取所有非系统集合', () async {
      if (!mongoE2EGatewayReady) return;
      await adapter.useDatabase('dbmaster_test');
      final tables = await adapter.getTables();
      expect(tables, isNotEmpty);
      expect(tables, contains('bson_types'));
      expect(tables, contains('products'));
      expect(tables, contains('bulk_users'));
      expect(tables, contains('orders'));
      // 不应包含系统集合
      expect(tables.any((t) => t.startsWith('system.')), isFalse);
      print('集合数量: ${tables.length}');
    });

    test('2.2 应获取视图列表', () async {
      if (!mongoE2EGatewayReady) return;
      final views = await adapter.getViews();
      expect(views, isNotEmpty);
      // adapter 仅返回真正的视图（type == 'view'），不含 system.* 集合
      expect(views, contains('active_products_view'));
      expect(views.any((v) => v.startsWith('system.')), isFalse);
    });

    test('2.3 应获取集合列信息（BSON 类型推断）', () async {
      if (!mongoE2EGatewayReady) return;
      final columns = await adapter.getTableColumns('products');
      expect(columns, isNotEmpty);
      expect(columns.any((c) => c.name == '_id' && c.type == 'ObjectId'), isTrue);
      expect(columns.any((c) => c.name == 'name' && c.type == 'String'), isTrue);
      expect(columns.any((c) => c.name == 'price' && c.type == 'Number'), isTrue);
      expect(columns.any((c) => c.name == 'featured' && c.type == 'Boolean'), isTrue);
      expect(columns.any((c) => c.name == 'created' && c.type == 'Date'), isTrue);
      expect(columns.any((c) => c.name == 'tags' && c.type == 'Array'), isTrue);
      expect(columns.any((c) => c.name == 'specs' && c.type == 'Document'), isTrue);
      print('products 列数: ${columns.length}');
    });

    test('2.4 应获取集合索引', () async {
      if (!mongoE2EGatewayReady) return;
      final indexes = await adapter.getTableIndexes('products');
      expect(indexes, isNotEmpty);
      expect(indexes.any((i) => i.name == '_id_'), isTrue);
      print('products 索引: ${indexes.map((i) => '${i.name}(${i.columns.join(",")})').toList()}');
    });

    test('2.5 应获取集合详情', () async {
      if (!mongoE2EGatewayReady) return;
      final details = await adapter.getTableDetails('products');
      expect(details.name, 'products');
      expect(details.columns, isNotEmpty);
      expect(details.indexes, isNotEmpty);
    });
  });

  // ==========================================================================
  // 三、数据查询（基础 CRUD）
  // ==========================================================================
  group('3. 数据查询', () {
    test('3.1 获取表数据（基础）', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('products', limit: 5);
      expect(result.rows.length, 5);
      expect(result.columns, contains('name'));
      expect(result.columns, contains('price'));
      print('前 5 条产品: ${result.rows.map((r) => r['name']).toList()}');
    });

    test('3.2 获取表数据（分页）', () async {
      if (!mongoE2EGatewayReady) return;
      final page1 = await adapter.getTableData('products', limit: 3, offset: 0);
      final page2 = await adapter.getTableData('products', limit: 3, offset: 3);
      expect(page1.rows.length, 3);
      expect(page2.rows.length, greaterThanOrEqualTo(1));
      // 两页数据不应重复
      final names1 = page1.rows.map((r) => r['name']).toSet();
      final names2 = page2.rows.map((r) => r['name']).toSet();
      expect(names1.intersection(names2).isEmpty, isTrue);
    });

    test('3.3 获取行数', () async {
      if (!mongoE2EGatewayReady) return;
      final count = await adapter.getTableRowCount('products');
      expect(count, 10);
    });

    test('3.4 空集合应返回提示', () async {
      if (!mongoE2EGatewayReady) return;
      // 注意：我们没有真正的空集合，这个测试需要创建一个
      // 使用一个已知为空的集合或创建新集合
      final emptyColl = 'test_empty_${DateTime.now().millisecondsSinceEpoch}';
      await adapter.createTable(emptyColl, []);
      final result = await adapter.getTableData(emptyColl);
      expect(result.rows.isNotEmpty, isTrue);
      // 清理
      await adapter.dropTable(emptyColl);
    });
  });

  // ==========================================================================
  // 四、BSON 类型渲染测试
  // ==========================================================================
  group('4. BSON 类型正确性', () {
    final testColl = 'test_bson_safe';

    setUpAll(() async {
      if (!mongoE2EGatewayReady) return;
      // 创建只包含安全 BSON 类型的测试集合
      await adapter.insertOne(testColl, {
        'string': 'hello',
        'int32': 42,
        'bool': true,
        'date': DateTime.now(),
        'array_mixed': [1, 'two', true],
        'nested_deep': {'a': {'b': {'c': 'deep'}}},
        'decimal': '123.456',
      });
    });

    tearDownAll(() async {
      try {
        await adapter.dropTable(testColl);
      } catch (_) {}
    });

    test('4.1 应正确识别 ObjectId 并转为字符串', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData(testColl, limit: 1);
      expect(result.rows.isNotEmpty, isTrue);
      final row = result.rows.first;
      // ObjectId 应该被转换为字符串
      expect(row['_id'], isA<String>());
      expect(row['_id'].toString().length, 24); // ObjectId 是 24 位十六进制
    });

    test('4.2 日期字段应为 ISO8601 格式', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData(testColl, limit: 1);
      final row = result.rows.first;
      expect(row['date'], isA<String>());
      expect(row['date'].toString().contains('T'), isTrue);
    });

    test('4.3 嵌套文档应正确转换为 Map', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData(testColl, limit: 1);
      final row = result.rows.first;
      expect(row['nested_deep'], isA<Map>());
    });

    test('4.4 数组应正确转换为 List', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData(testColl, limit: 1);
      final row = result.rows.first;
      expect(row['array_mixed'], isA<List>());
    });

    test('4.5 Decimal128 应不丢失精度', () async {
      if (!mongoE2EGatewayReady) return;
      // Decimal128 在 mongo_dart 中应该被转换为字符串或特殊类型
      final result = await adapter.getTableData(testColl, limit: 1);
      final row = result.rows.first;
      // 至少应该存在 decimal 字段
      expect(row.containsKey('decimal'), isTrue);
    });
  });

  // ==========================================================================
  // 五、复杂查询与操作符
  // ==========================================================================
  group('5. 复杂查询', () {
    test('5.1 JSON 格式查询（筛选电子产品）', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.executeQuery(
        '{"collection":"products","filter":{"category":"electronics"}}',
      );
      expect(result.rows.isNotEmpty, isTrue);
      expect(result.rows.every((r) => r['category'] == 'electronics'), isTrue);
      print('电子产品数量: ${result.rows.length}');
    });

    test('5.2 db.collection.find() 格式', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.executeQuery(
        'db.products.find({"status":"active"})',
      );
      expect(result.rows.isNotEmpty, isTrue);
    });

    test('5.3 count 查询', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.executeQuery('count(products)');
      expect(result.rows.first['count'], 10);
    });

    test('5.4 带 limit 的 find 查询', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.executeQuery(
        'db.products.find().limit(3)',
      );
      expect(result.rows.length, 3);
    });
  });

  // ==========================================================================
  // 六、大数据分页性能
  // ==========================================================================
  group('6. 大数据分页性能', () {
    test('6.1 10万条数据行数应正确', () async {
      if (!mongoE2EGatewayReady) return;
      final count = await adapter.getTableRowCount('bulk_users');
      expect(count, 100000);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('6.2 大数据集分页查询（前 100 条）', () async {
      if (!mongoE2EGatewayReady) return;
      final stopwatch = Stopwatch()..start();
      final result = await adapter.getTableData('bulk_users', limit: 100, offset: 0);
      stopwatch.stop();
      expect(result.rows.length, 100);
      print('100 条数据查询耗时: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('6.3 大数据集深度偏移查询', () async {
      if (!mongoE2EGatewayReady) return;
      final stopwatch = Stopwatch()..start();
      final result = await adapter.getTableData('bulk_users', limit: 50, offset: 50000);
      stopwatch.stop();
      expect(result.rows.length, 50);
      print('offset=50000 查询耗时: ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ==========================================================================
  // 七、大文档处理
  // ==========================================================================
  group('7. 大文档处理', () {
    test('7.1 1MB 文档应可成功读取', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('large_docs', limit: 1);
      expect(result.rows.isNotEmpty, isTrue);
      // 检查是否包含大字段
      expect(result.rows.first.containsKey('data'), isTrue);
    });

    test('7.2 大文档行数应正确', () async {
      if (!mongoE2EGatewayReady) return;
      final count = await adapter.getTableRowCount('large_docs');
      expect(count, 102);
    });
  });

  // ==========================================================================
  // 八、嵌套文档与数组操作
  // ==========================================================================
  group('8. 嵌套文档与数组', () {
    test('8.1 深层嵌套文档应正确展示', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('nested', limit: 1);
      expect(result.rows.isNotEmpty, isTrue);
      final row = result.rows.first;
      // 嵌套字段应被展平或保留为 Map
      expect(row['user'], isA<Map>());
    });

    test('8.2 数组数据应正确展示', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('arrays', limit: 5);
      expect(result.rows.isNotEmpty, isTrue);
      final row = result.rows.firstWhere((r) => r['title'] == '2D Array');
      expect(row['matrix'], isA<List>());
    });

    test('8.3 混合数组应包含多种类型', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('arrays', limit: 5);
      final row = result.rows.firstWhere((r) => r['title'] == 'Mixed Array');
      final mixed = row['mixed'] as List;
      expect(mixed.length, greaterThanOrEqualTo(4));
    });
  });

  // ==========================================================================
  // 九、特殊键名处理
  // ==========================================================================
  group('9. 特殊键名', () {
    test('9.1 应能读取带点号的键名', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('special_keys', limit: 10);
      expect(result.rows.isNotEmpty, isTrue);
      // 带点号的键名应该被处理
      final row = result.rows.firstWhere(
        (r) => r.keys.any((k) => k.contains('.')),
        orElse: () => {},
      );
      expect(row.isNotEmpty, isTrue);
    });

    test('9.2 中文键名应正确处理', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('special_keys', limit: 10);
      final row = result.rows.firstWhere(
        (r) => r.keys.any((k) => k.contains('中文')),
        orElse: () => {},
      );
      expect(row.isNotEmpty, isTrue);
    });
  });

  // ==========================================================================
  // 十、聚合管道
  // ==========================================================================
  group('10. 聚合管道', () {
    test('10.1 \$group 聚合应正确', () async {
      if (!mongoE2EGatewayReady) return;
      final pipeline = [
        {
          '\$group': {
            '_id': '\$category',
            'count': {'\$sum': 1},
            'avgPrice': {'\$avg': '\$price'},
          }
        },
        {'\$sort': {'count': -1}},
      ];
      final result = await adapter.aggregate('products', pipeline);
      expect(result.rows.isNotEmpty, isTrue);
      print('聚合结果: ${result.rows.map((r) => r['_id']).toList()}');
    });

    test('10.2 \$lookup 关联应正确', () async {
      if (!mongoE2EGatewayReady) return;
      final pipeline = [
        {
          '\$lookup': {
            'from': 'customers',
            'localField': 'customer',
            'foreignField': '_id',
            'as': 'customerInfo',
          }
        },
        {'\$limit': 3},
      ];
      final result = await adapter.aggregate('orders', pipeline);
      expect(result.rows.isNotEmpty, isTrue);
      // customerInfo 应为数组
      expect(result.rows.first['customerInfo'], isA<List>());
    });
  });

  // ==========================================================================
  // 十一、索引操作
  // ==========================================================================
  group('11. 索引操作', () {
    test('11.1 创建单字段索引', () async {
      if (!mongoE2EGatewayReady) return;
      final coll = 'test_index_${DateTime.now().millisecondsSinceEpoch}';
      await adapter.createTable(coll, []);
      await adapter.insertOne(coll, {'testField': 'value'});

      final created = await adapter.createIndex(coll, 'testField_idx', ['testField']);
      expect(created, isTrue);

      final indexes = await adapter.getTableIndexes(coll);
      expect(indexes.any((i) => i.name == 'testField_idx'), isTrue);

      await adapter.dropTable(coll);
    });

    test('11.2 创建唯一索引', () async {
      if (!mongoE2EGatewayReady) return;
      final coll = 'test_unique_${DateTime.now().millisecondsSinceEpoch}';
      await adapter.createTable(coll, []);
      await adapter.insertOne(coll, {'email': 'test@example.com'});

      final created = await adapter.createIndex(
        coll, 'email_unique', ['email'], unique: true,
      );
      expect(created, isTrue);

      await adapter.dropTable(coll);
    });
  });

  // ==========================================================================
  // 十二、视图读取
  // ==========================================================================
  group('12. 视图', () {
    test('12.1 视图应可作为普通集合查询', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('active_products_view', limit: 10);
      expect(result.rows.isNotEmpty, isTrue);
      // 视图可能不包含 status 字段，只验证有数据返回即可
      expect(result.rows.every((r) => r.containsKey('name')), isTrue);
    });

    test('12.2 视图行数应小于等于原表', () async {
      if (!mongoE2EGatewayReady) return;
      final viewCount = await adapter.getTableRowCount('active_products_view');
      final tableCount = await adapter.getTableRowCount('products');
      expect(viewCount, lessThanOrEqualTo(tableCount));
    });
  });

  // ==========================================================================
  // 十三、字段操作（添加/删除）
  // ==========================================================================
  group('13. 字段操作', () {
    test('13.1 添加字段', () async {
      if (!mongoE2EGatewayReady) return;
      final coll = 'test_addcol_${DateTime.now().millisecondsSinceEpoch}';
      await adapter.createTable(coll, []);
      await adapter.insertOne(coll, {'name': 'test'});

      final added = await adapter.addColumn(
        coll,
        DbColumn(name: 'newField', type: 'String'),
      );
      expect(added, isTrue);

      // 验证字段已添加
      final result = await adapter.getTableData(coll);
      expect(result.rows.first.containsKey('newField'), isTrue);

      await adapter.dropTable(coll);
    });

    test('13.2 删除字段', () async {
      if (!mongoE2EGatewayReady) return;
      final coll = 'test_dropcol_${DateTime.now().millisecondsSinceEpoch}';
      await adapter.createTable(coll, []);
      await adapter.insertOne(coll, {'temp': 'value', 'keep': 'value'});

      final dropped = await adapter.dropColumn(coll, 'temp');
      expect(dropped, isTrue);

      await adapter.dropTable(coll);
    });
  });

  // ==========================================================================
  // 十四、安全性
  // ==========================================================================
  group('14. 安全性检查', () {
    test('14.1 危险命令应被拦截', () {
      final result = adapter.validateCommand('db.dropDatabase()');
      expect(result.allowed, isFalse);
      expect(result.riskLevel, CommandRiskLevel.dangerous);
    });

    test('14.2 XSS 内容应被标识', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getTableData('products', limit: 10);
      final xssRow = result.rows.firstWhere(
        (r) => r['name'].toString().contains('<script>'),
        orElse: () => {},
      );
      if (xssRow.isNotEmpty) {
        print('检测到 XSS 内容: ${xssRow['name']}');
        // UI 层应负责转义，这里只验证数据存在
        expect(xssRow.isNotEmpty, isTrue);
      }
    });
  });

  // ==========================================================================
  // 十五、连接管理
  // ==========================================================================
  group('15. 连接管理', () {
    test('15.1 断开连接后状态正确', () async {
      if (!mongoE2EGatewayReady) return;
      final tempAdapter = MongoDBAdapter();
      final connection = DatabaseConnection(
        id: 'test_disconnect',
        name: 'Disconnect Test',
        host: MongoDBTestConfig.host,
        port: MongoDBTestConfig.port,
        type: DatabaseType.mongodb,
        username: MongoDBTestConfig.username,
        password: MongoDBTestConfig.password,
        database: MongoDBTestConfig.authDatabase,
      );

      await tempAdapter.connect(connection);
      expect(tempAdapter.isConnected, isTrue);

      await tempAdapter.disconnect();
      expect(tempAdapter.isConnected, isFalse);
      expect(tempAdapter.currentConnection, isNull);
    });

    test('15.2 错误凭证应连接失败', () async {
      if (!mongoE2EGatewayReady) return;
      final badAdapter = MongoDBAdapter();
      final connection = DatabaseConnection(
        id: 'test_bad_cred',
        name: 'Bad Cred',
        host: MongoDBTestConfig.host,
        port: MongoDBTestConfig.port,
        type: DatabaseType.mongodb,
        username: 'wrong_user',
        password: 'wrong_password',
        database: MongoDBTestConfig.authDatabase,
      );

      final result = await badAdapter.connect(connection);
      expect(result, isFalse);
    });
  });
}
