import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

void main() {
  late MongoDBAdapter adapter;
  late String testDbName;
  late String testPrefix;

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
    print('MongoDB 测试配置:');
    print('  主机: ${MongoDBTestConfig.host}');
    print('  端口: ${MongoDBTestConfig.port}');
    print('  用户: ${MongoDBTestConfig.username}');
    print('  认证数据库: ${MongoDBTestConfig.authDatabase}');

    adapter = MongoDBAdapter();
    final connection = DatabaseConnection(
      id: 'test_mongodb',
      name: 'MongoDB Test',
      host: MongoDBTestConfig.host,
      port: MongoDBTestConfig.port,
      type: DatabaseType.mongodb,
      username: MongoDBTestConfig.username,
      password: MongoDBTestConfig.password,
      database: MongoDBTestConfig.authDatabase,
    );

    final connected = await adapter.connect(connection);
    expect(connected, isTrue, reason: '无法连接到 MongoDB 服务器');
  });

  tearDownAll(() async {
    if (!mongoE2EGatewayReady) return;
    await adapter.disconnect();
  });

  setUp(() {
    testDbName = MongoDBTestConfig.generateTestDatabaseName();
    testPrefix = MongoDBTestConfig.generateTestCollectionPrefix();
  });

  tearDown(() async {
    // 清理测试集合
    try {
      final collections = await adapter.getTables();
      for (final coll in collections) {
        if (coll.startsWith('test_')) {
          await adapter.dropTable(coll);
        }
      }
    } catch (_) {}
  });

  group('MongoDB Connection', () {
    test('should connect to MongoDB server successfully', () async {
      if (!mongoE2EGatewayReady) return;
      expect(adapter.isConnected, isTrue);
      expect(adapter.currentConnection, isNotNull);
      expect(adapter.currentConnection!.host, MongoDBTestConfig.host);
    });

    test('should fail to connect with wrong credentials', () async {
      if (!mongoE2EGatewayReady) return;
      final badAdapter = MongoDBAdapter();
      final connection = DatabaseConnection(
        id: 'test_mongo_bad',
        name: 'MongoDB Bad',
        host: MongoDBTestConfig.host,
        port: MongoDBTestConfig.port,
        type: DatabaseType.mongodb,
        username: 'wrong_user',
        password: 'wrong_password',
        database: MongoDBTestConfig.authDatabase,
      );

      // 连接失败 UX 重构 T9b：connect 失败不再 return false，改抛
      // AdapterConnectException。server 有稳定码时 kind=authFailed
      // （AUTH_DENIED）；旧 server/无码 envelope 回落 unknown——errorCode
      // 两种形态下均非空。
      await expectLater(
        badAdapter.connect(connection),
        throwsA(
          isA<AdapterConnectException>()
              .having(
                (e) =>
                    e.failure.kind == ConnectionFailureKind.authFailed ||
                    e.failure.kind == ConnectionFailureKind.unknown,
                'kind',
                isTrue,
              )
              .having((e) => e.failure.errorCode, 'errorCode', isNotEmpty)
              .having(
                (e) => e.failure.target,
                'target',
                '${MongoDBTestConfig.host}:${MongoDBTestConfig.port}',
              ),
        ),
      );
      expect(badAdapter.isConnected, isFalse);
    });

    test('should test connection successfully', () async {
      if (!mongoE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'test_mongo_test',
        name: 'MongoDB Test Conn',
        host: MongoDBTestConfig.host,
        port: MongoDBTestConfig.port,
        type: DatabaseType.mongodb,
        username: MongoDBTestConfig.username,
        password: MongoDBTestConfig.password,
        database: MongoDBTestConfig.authDatabase,
      );

      final result = await adapter.testConnection(connection);
      expect(result, isNull);
    });
  });

  group('MongoDB Database Operations', () {
    test('should get all databases', () async {
      if (!mongoE2EGatewayReady) return;
      final dbs = await adapter.getDatabases();
      expect(dbs, isNotEmpty);
      expect(dbs, contains('admin'));
    });

    test('should create a database', () async {
      if (!mongoE2EGatewayReady) return;
      final created = await adapter.createDatabase(testDbName);
      expect(created, isTrue);
      expect(adapter.currentConnection!.database, testDbName);
    });

    test('should switch to a database', () async {
      if (!mongoE2EGatewayReady) return;
      await adapter.useDatabase('admin');
      expect(adapter.currentConnection!.database, 'admin');
    });

    test('should get database properties', () async {
      if (!mongoE2EGatewayReady) return;
      final props = await adapter.getDatabaseProperties('admin');
      expect(props, isNotNull);
      expect(props!['name'], 'admin');
    });
  });

  group('MongoDB Collection Operations', () {
    test('should create a collection implicitly', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_implicit';
      final created = await adapter.createTable(collectionName, []);
      expect(created, isTrue);

      // MongoDB 是惰性创建集合的，需要插入一条数据才能真正创建
      await adapter.insertOne(collectionName, {'init': true});

      final tables = await adapter.getTables();
      expect(tables, contains(collectionName));
    });

    test('should drop a collection', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_drop';
      await adapter.createTable(collectionName, []);

      final dropped = await adapter.dropTable(collectionName);
      expect(dropped, isTrue);

      final tables = await adapter.getTables();
      expect(tables, isNot(contains(collectionName)));
    });

    test('should truncate a collection', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_truncate';
      await adapter.insertOne(collectionName, {'name': 'test', 'value': 1});

      final truncated = await adapter.truncateTable(collectionName);
      expect(truncated, isTrue);

      final count = await adapter.countDocuments(collectionName);
      expect(count, 0);
    });

    test('should rename a collection', () async {
      if (!mongoE2EGatewayReady) return;
      final oldName = '${testPrefix}_old';
      final newName = '${testPrefix}_new';
      await adapter.insertOne(oldName, {'data': 'test'});

      final renamed = await adapter.renameTable(oldName, newName);
      expect(renamed, isTrue);

      // 验证新集合存在，旧集合不存在
      final collections = await adapter.getTables();
      expect(collections.contains(newName), isTrue);
      expect(collections.contains(oldName), isFalse);
    });

    test('should get table row count', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_count';
      await adapter.insertOne(collectionName, {'a': 1});
      await adapter.insertOne(collectionName, {'b': 2});

      final count = await adapter.getTableRowCount(collectionName);
      expect(count, 2);
    });

    test('should get collection stats', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_stats';
      await adapter.insertOne(collectionName, {'data': 'test'});

      final stats = await adapter.getCollectionStats(collectionName);
      expect(stats, isNotNull);
      expect(stats['documentCount'], greaterThanOrEqualTo(1));
    });

    test('should list collections with details', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_list';
      await adapter.insertOne(collectionName, {'data': 'test'});

      final collections = await adapter.listCollections('admin');
      expect(collections, isNotEmpty);
    });
  });

  group('MongoDB CRUD Operations', () {
    test('should insert one document', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_insert_one';
      final doc = {'name': 'Alice', 'age': 30, 'email': 'alice@example.com'};

      final result = await adapter.insertOne(collectionName, doc);
      expect(result, isTrue);

      final count = await adapter.countDocuments(collectionName);
      expect(count, 1);
    });

    test('should insert many documents', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_insert_many';
      final docs = [
        {'name': 'User1', 'score': 100},
        {'name': 'User2', 'score': 200},
        {'name': 'User3', 'score': 300},
      ];

      final result = await adapter.insertMany(collectionName, docs);
      expect(result, isTrue);

      final count = await adapter.countDocuments(collectionName);
      expect(count, 3);
    });

    test('should update one document', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_update_one';
      await adapter.insertOne(collectionName, {'name': 'Bob', 'status': 'active'});

      final updated = await adapter.updateOne(
        collectionName,
        {'name': 'Bob'},
        {'\$set': {'status': 'inactive'}},
      );
      expect(updated, greaterThanOrEqualTo(0));
    });

    test('should update many documents', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_update_many';
      await adapter.insertMany(collectionName, [
        {'category': 'A', 'count': 1},
        {'category': 'A', 'count': 2},
        {'category': 'B', 'count': 3},
      ]);

      final updated = await adapter.updateMany(
        collectionName,
        {'category': 'A'},
        {'\$set': {'updated': true}},
      );
      expect(updated, greaterThanOrEqualTo(0));
    });

    test('should delete one document', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_delete_one';
      await adapter.insertMany(collectionName, [
        {'id': 1, 'data': 'keep'},
        {'id': 2, 'data': 'delete'},
      ]);

      final deleted = await adapter.deleteOne(collectionName, {'id': 2});
      expect(deleted, greaterThanOrEqualTo(0));

      final count = await adapter.countDocuments(collectionName);
      expect(count, greaterThanOrEqualTo(1));
    });

    test('should delete many documents', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_delete_many';
      await adapter.insertMany(collectionName, [
        {'type': 'temp', 'data': 'a'},
        {'type': 'temp', 'data': 'b'},
        {'type': 'perm', 'data': 'c'},
      ]);

      final deleted = await adapter.deleteMany(collectionName, {'type': 'temp'});
      expect(deleted, greaterThanOrEqualTo(0));
    });

    test('should count documents with filter', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_count_filter';
      await adapter.insertMany(collectionName, [
        {'status': 'active'},
        {'status': 'active'},
        {'status': 'inactive'},
      ]);

      final count = await adapter.countDocuments(collectionName, filter: {'status': 'active'});
      expect(count, 2);
    });
  });

  group('MongoDB Query Execution', () {
    test('should execute JSON query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_json_query';
      await adapter.insertMany(collectionName, [
        {'product': 'A', 'price': 100},
        {'product': 'B', 'price': 200},
      ]);

      // 使用 db.collection.find() 语法，更可靠
      final result = await adapter.executeQuery(
        'db.$collectionName.find()',
      );
      expect(result.rows.length, 2);
      expect(result.columns, contains('product'));
      expect(result.columns, contains('price'));
    });

    test('should execute simple find query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_simple_find';
      await adapter.insertMany(collectionName, [
        {'name': 'item1', 'value': 10},
        {'name': 'item2', 'value': 20},
      ]);

      final result = await adapter.executeQuery('db.$collectionName.find()');
      expect(result.rows.length, 2);
    });

    test('should execute find with filter', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_find_filter';
      await adapter.insertMany(collectionName, [
        {'category': 'electronics', 'name': 'phone'},
        {'category': 'clothing', 'name': 'shirt'},
      ]);

      final result = await adapter.executeQuery(
        'db.$collectionName.find({"category":"electronics"})',
      );
      expect(result.rows.length, 1);
      expect(result.rows.first['name'], 'phone');
    });

    test('should execute count query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_count_query';
      await adapter.insertMany(collectionName, [
        {'x': 1},
        {'x': 2},
        {'x': 3},
      ]);

      final result = await adapter.executeQuery('count($collectionName)');
      expect(result.rows.first['count'], 3);
    });
  });

  group('MongoDB Index Operations', () {
    test('should create an index', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_index_create';
      await adapter.insertOne(collectionName, {'email': 'test@example.com'});

      final created = await adapter.createIndex(collectionName, 'email_idx', ['email']);
      expect(created, isTrue);

      final indexes = await adapter.getTableIndexes(collectionName);
      final hasEmailIndex = indexes.any((idx) => idx.name == 'email_idx');
      expect(hasEmailIndex, isTrue);
    });

    test('should create unique index', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_unique_index';
      await adapter.insertOne(collectionName, {'username': 'admin'});

      final created = await adapter.createIndex(
        collectionName,
        'username_unique',
        ['username'],
        unique: true,
      );
      expect(created, isTrue);
    });

    test('should drop an index', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_index_drop';
      await adapter.insertOne(collectionName, {'field': 'value'});
      await adapter.createIndex(collectionName, 'field_idx', ['field']);

      final dropped = await adapter.dropIndex(collectionName, 'field_idx');
      expect(dropped, isTrue);
    });

    test('should get table indexes', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_get_indexes';
      await adapter.insertOne(collectionName, {'a': 1, 'b': 2});

      final indexes = await adapter.getTableIndexes(collectionName);
      expect(indexes, isNotEmpty);
      // MongoDB 自动创建 _id 索引
      final hasIdIndex = indexes.any((idx) => idx.columns.contains('_id'));
      expect(hasIdIndex, isTrue);
    });
  });

  group('MongoDB Schema Operations', () {
    test('should get table columns from sample document', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_columns';
      await adapter.insertOne(collectionName, {
        'name': 'Test',
        'age': 25,
        'active': true,
        'tags': ['a', 'b'],
        'metadata': {'created': '2024-01-01'},
      });

      final columns = await adapter.getTableColumns(collectionName);
      expect(columns, isNotEmpty);
      expect(columns.any((c) => c.name == '_id'), isTrue);
      expect(columns.any((c) => c.name == 'name'), isTrue);
      expect(columns.any((c) => c.name == 'age'), isTrue);
    });

    test('should get table details', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_details';
      await adapter.insertOne(collectionName, {'field1': 'value1'});

      final details = await adapter.getTableDetails(collectionName);
      expect(details.name, collectionName);
      expect(details.columns, isNotEmpty);
    });

    test('should infer document schema', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_schema';
      await adapter.insertMany(collectionName, [
        {'name': 'Doc1', 'type': 'A', 'count': 10},
        {'name': 'Doc2', 'type': 'B', 'count': 20},
      ]);

      final schema = await adapter.inferDocumentSchema(collectionName, sampleSize: 10);
      expect(schema['collectionName'], collectionName);
      expect(schema['totalSampled'], 2);
      expect((schema['fields'] as Map).isNotEmpty, isTrue);
    });
  });

  group('MongoDB Table Data Operations', () {
    test('should get table data with pagination', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_pagination';
      for (int i = 0; i < 10; i++) {
        await adapter.insertOne(collectionName, {'index': i, 'data': 'item$i'});
      }

      final data = await adapter.getTableData(collectionName, limit: 5, offset: 0);
      expect(data.rows.length, 5);

      final data2 = await adapter.getTableData(collectionName, limit: 5, offset: 5);
      expect(data2.rows.length, 5);
    });

    test('should get table data from empty collection', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_empty';
      await adapter.createTable(collectionName, []);

      final data = await adapter.getTableData(collectionName);
      expect(data.rows.isNotEmpty, isTrue); // 返回默认行
    });
  });

  group('MongoDB Aggregation', () {
    test('should execute aggregation pipeline', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_aggregate';
      await adapter.insertMany(collectionName, [
        {'category': 'A', 'amount': 100},
        {'category': 'A', 'amount': 200},
        {'category': 'B', 'amount': 150},
      ]);

      final pipeline = [
        {'\$group': {
          '_id': '\$category',
          'total': {'\$sum': '\$amount'},
        }},
      ];

      final result = await adapter.aggregate(collectionName, pipeline);
      expect(result.rows.isNotEmpty, isTrue);
    });
  });

  group('MongoDB Server Information', () {
    test('should get server version', () async {
      if (!mongoE2EGatewayReady) return;
      final version = await adapter.getServerVersion();
      expect(version, isNotNull);
      expect(version!['version'], isNotNull);
      expect(version['database'], 'MongoDB');
    });

    test('should get server status', () async {
      if (!mongoE2EGatewayReady) return;
      final status = await adapter.getServerStatus();
      expect(status, isNotNull);
      expect(status['version'], isNotNull);
      expect(status['ok'], isTrue);
    });

    test('should get build info', () async {
      if (!mongoE2EGatewayReady) return;
      final info = await adapter.getBuildInfo();
      expect(info, isNotNull);
      expect(info['version'], isNotNull);
    });
  });

  group('MongoDB GridFS', () {
    test('should get GridFS buckets', () async {
      if (!mongoE2EGatewayReady) return;
      final buckets = await adapter.getGridFSBuckets();
      expect(buckets, isA<List>());
    });
  });

  group('MongoDB ReplicaSet & Sharding', () {
    test('should get replica set status', () async {
      if (!mongoE2EGatewayReady) return;
      final status = await adapter.getReplicaSetStatus();
      // 如果不是副本集可能返回 null
      expect(status == null || status['members'] != null, isTrue);
    });

    test('should get sharding status', () async {
      if (!mongoE2EGatewayReady) return;
      final status = await adapter.getShardingStatus();
      // 如果不是分片集群可能返回 null
      expect(status == null || status['shards'] != null, isTrue);
    });
  });

  group('MongoDB Security', () {
    test('should validate dangerous commands', () {
      final result = adapter.validateCommand('dropDatabase()');
      expect(result.allowed, isFalse);
      expect(result.riskLevel, CommandRiskLevel.dangerous);
    });

    test('should validate write commands', () {
      final result = adapter.validateCommand('insert users');
      expect(result.allowed, isTrue);
      expect(result.riskLevel, CommandRiskLevel.warning);
    });

    test('should allow read commands', () {
      final result = adapter.validateCommand('find users');
      expect(result.allowed, isTrue);
      expect(result.riskLevel, CommandRiskLevel.safe);
    });
  });

  group('MongoDB Export', () {
    test('should export database structure', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_export';
      await adapter.insertOne(collectionName, {'test': 'data'});

      final export = await adapter.exportDatabaseStructure('admin');
      expect(export, isNotNull);
      expect(export.contains('MongoDB Database Export'), isTrue);
    });
  });

  group('MongoDB Explain Plan', () {
    test('should return explain info', () async {
      if (!mongoE2EGatewayReady) return;
      final result = await adapter.getExplainPlan('find users');
      expect(result.rows.isNotEmpty, isTrue);
    });
  });

  group('MongoDB Charsets', () {
    test('should get charsets', () async {
      if (!mongoE2EGatewayReady) return;
      final charsets = await adapter.getCharsets();
      expect(charsets, isNotEmpty);
      expect(charsets.first, 'UTF-8');
    });

    test('should get collations', () async {
      if (!mongoE2EGatewayReady) return;
      final collations = await adapter.getCollations();
      expect(collations, isEmpty);
    });
  });

  group('MongoDB Views & Procedures', () {
    test('should get views', () async {
      if (!mongoE2EGatewayReady) return;
      final views = await adapter.getViews();
      expect(views, isA<List>());
    });

    test('should get procedures', () async {
      if (!mongoE2EGatewayReady) return;
      final procedures = await adapter.getProcedures();
      expect(procedures, isEmpty);
    });

    test('should get functions', () async {
      if (!mongoE2EGatewayReady) return;
      final functions = await adapter.getFunctions();
      expect(functions, isEmpty);
    });
  });

  group('MongoDB Column Operations', () {
    test('should add a column to all documents', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_add_col';
      await adapter.insertOne(collectionName, {'existing': 'value'});

      final result = await adapter.addColumn(
        collectionName,
        DbColumn(name: 'new_col', type: 'STRING'),
      );
      expect(result, isTrue);

      // 验证新字段已添加
      final data = await adapter.getTableData(collectionName, limit: 1);
      expect(data.rows.isNotEmpty, isTrue);
      expect(data.rows.first.containsKey('new_col'), isTrue);
    });

    test('should drop a column from all documents', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_drop_col';
      await adapter.insertOne(collectionName, {
        'existing': 'value',
        'to_remove': 'value',
      });

      final result = await adapter.dropColumn(collectionName, 'to_remove');
      expect(result, isTrue);

      // 验证字段已删除
      final data = await adapter.getTableData(collectionName, limit: 1);
      expect(data.rows.isNotEmpty, isTrue);
      expect(data.rows.first.containsKey('to_remove'), isFalse);
    });

    test('should modify a column name', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_mod_col';
      await adapter.insertOne(collectionName, {'old_name': 'value'});

      final result = await adapter.modifyColumn(
        collectionName,
        'old_name',
        DbColumn(name: 'new_name', type: 'STRING'),
      );
      expect(result, isTrue);

      // 验证字段已重命名
      final data = await adapter.getTableData(collectionName, limit: 1);
      expect(data.rows.isNotEmpty, isTrue);
      expect(data.rows.first.containsKey('new_name'), isTrue);
      expect(data.rows.first.containsKey('old_name'), isFalse);
    });
  });

  group('MongoDB Connection Management', () {
    test('should disconnect cleanly', () async {
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
  });

  group('MongoDB Advanced Query Execution', () {
    test('should execute findOne query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_findone';
      await adapter.insertMany(collectionName, [
        {'name': 'Alice', 'age': 30},
        {'name': 'Bob', 'age': 25},
      ]);

      final result = await adapter.executeQuery(
        'db.$collectionName.findOne({"name":"Alice"})',
      );
      expect(result.rows.length, 1);
      expect(result.rows.first['name'], 'Alice');
    });

    test('should execute aggregate via query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_agg_query';
      await adapter.insertMany(collectionName, [
        {'category': 'A', 'amount': 100},
        {'category': 'A', 'amount': 200},
        {'category': 'B', 'amount': 150},
      ]);

      final result = await adapter.executeQuery(
        'db.$collectionName.aggregate([{"\$group":{"_id":"\$category","total":{"\$sum":"\$amount"}}}])',
      );
      expect(result.rows.isNotEmpty, isTrue);
    });

    test('should execute distinct query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_distinct';
      await adapter.insertMany(collectionName, [
        {'city': 'Beijing', 'country': 'China'},
        {'city': 'Shanghai', 'country': 'China'},
        {'city': 'Beijing', 'country': 'China'},
      ]);

      final result = await adapter.executeQuery(
        'db.$collectionName.distinct("city")',
      );
      expect(result.rows.isNotEmpty, isTrue);
      final cities = result.rows.map((r) => r['city']).toSet();
      expect(cities, contains('Beijing'));
      expect(cities, contains('Shanghai'));
    });

    test('should execute countDocuments query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_countdocs';
      await adapter.insertMany(collectionName, [
        {'status': 'active'},
        {'status': 'active'},
        {'status': 'inactive'},
      ]);

      final result = await adapter.executeQuery(
        'db.$collectionName.countDocuments({"status":"active"})',
      );
      expect(result.rows.first['count'], 2);
    });

    test('should execute estimatedDocumentCount query', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_estcount';
      await adapter.insertMany(collectionName, [
        {'x': 1}, {'x': 2}, {'x': 3},
      ]);

      final result = await adapter.executeQuery(
        'db.$collectionName.estimatedDocumentCount()',
      );
      expect(result.rows.first['count'], greaterThanOrEqualTo(3));
    });
  });

  group('MongoDB Database Switching', () {
    test('should switch database and perform operations', () async {
      if (!mongoE2EGatewayReady) return;
      final dbName = MongoDBTestConfig.generateTestDatabaseName();
      await adapter.createDatabase(dbName);
      await adapter.useDatabase(dbName);

      final collectionName = '${testPrefix}_switched';
      await adapter.insertOne(collectionName, {'test': true});

      final collections = await adapter.getTables();
      expect(collections.contains(collectionName), isTrue);

      // 切换回 admin
      await adapter.useDatabase('admin');
      expect(adapter.currentConnection!.database, 'admin');
    });
  });

  group('MongoDB Execute Script', () {
    test('should execute script with multiple queries', () async {
      if (!mongoE2EGatewayReady) return;
      final collectionName = '${testPrefix}_script';
      await adapter.insertOne(collectionName, {'script_test': true});

      final result = await adapter.executeSqlScript("find($collectionName)");
      expect(result, isTrue);
    });
  });
}
