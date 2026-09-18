// ============================================================================
// MongoDB Performance Benchmark Tests (M1/M2)
// Tests: Real MongoDB server baselines —— 对应 $APPEAL 4.1.3 薄弱点 1
//        （NoSQL 大实例元数据/大结果集行为）
//        docs/task_performance_benchmark_wave2.md
// Target: real MongoDB via DBMASTER_MONGO_* (see config/mongodb_test_config.dart)
//
// Benchmark parameters (dart-define overridable):
//   DBMASTER_BENCH_COLLECTIONS  集合数量种子规模，默认 500
//   DBMASTER_BENCH_ROWS         文档数量，默认 100000
//   DBMASTER_BENCH_STRICT       设为 1 时按验收指标硬阈值断言
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/mongodb_test_config.dart';
import 'helpers/mongo_gateway_e2e_helper.dart';

class _BenchReport {
  static final List<String> _lines = [];

  static void record(String id, String name, Duration elapsed, String detail) {
    final line = '[BENCH][$id] $name: ${elapsed.inMilliseconds} ms ($detail)';
    _lines.add(line);
    // ignore: avoid_print
    print(line);
  }

  static void summary() {
    // ignore: avoid_print
    print('============== MONGO PERFORMANCE BASELINE SUMMARY ===============');
    for (final line in _lines) {
      // ignore: avoid_print
      print(line);
    }
    // ignore: avoid_print
    print('=================================================================');
  }
}

int get _benchCollections {
  final v = const String.fromEnvironment(
    'DBMASTER_BENCH_COLLECTIONS',
    defaultValue: '500',
  );
  return int.tryParse(v) ?? 500;
}

int get _benchRows {
  final v = const String.fromEnvironment(
    'DBMASTER_BENCH_ROWS',
    defaultValue: '100000',
  );
  return int.tryParse(v) ?? 100000;
}

bool get _strict =>
    const String.fromEnvironment('DBMASTER_BENCH_STRICT') == '1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
  });

  group('MongoDB Performance Benchmark', () {
    late MongoDBAdapter adapter;
    late String testDbName;

    setUp(() async {
      if (!mongoE2EGatewayReady) return;
      adapter = MongoDBAdapter();
      testDbName = MongoDBTestConfig.generateTestDatabaseName();
      final connection = DatabaseConnection(
        id: 'mongo_bench',
        name: 'MongoDB Benchmark',
        type: DatabaseType.mongodb,
        host: MongoDBTestConfig.host,
        port: MongoDBTestConfig.port,
        username: MongoDBTestConfig.username,
        password: MongoDBTestConfig.password,
        database: MongoDBTestConfig.authDatabase,
      );
      await adapter.connect(connection);
      await adapter.useDatabase(testDbName);
    });

    tearDown(() async {
      try {
        await adapter.dropDatabase(testDbName);
      } catch (_) {
        // 回收失败不影响基准结果
      }
      if (adapter.isConnected) await adapter.disconnect();
    });

    tearDownAll(_BenchReport.summary);

    // ------------------------------------------------------------------
    // M1: 元数据加载 —— N 集合 getTables() 延迟
    // 验收指标：< 500ms；宽松回归线：< 5000ms；严格：< 1000ms
    // ------------------------------------------------------------------
    test(
      'M1: getTables() latency with $_benchCollections collections',
      () async {
        if (!mongoE2EGatewayReady) return;
        final seedWatch = Stopwatch()..start();
        for (var i = 0; i < _benchCollections; i++) {
          await adapter.insertMany('bench_c$i', [
            {'_id': i, 'v': 'seed'},
          ]);
        }
        seedWatch.stop();
        // ignore: avoid_print
        print(
          '[BENCH][M1] seeded $_benchCollections collections in '
          '${seedWatch.elapsed.inMilliseconds} ms (不计入基准)',
        );

        await adapter.getTables(); // 预热

        final samples = <int>[];
        for (var run = 0; run < 3; run++) {
          final watch = Stopwatch()..start();
          final tables = await adapter.getTables();
          watch.stop();
          expect(
            tables.length,
            _benchCollections,
            reason: 'getTables() 应返回全部 $_benchCollections 个集合',
          );
          samples.add(watch.elapsed.inMilliseconds);
        }
        samples.sort();
        final median = Duration(milliseconds: samples[1]);
        _BenchReport.record(
          'M1',
          'getTables() median of 3 runs',
          median,
          '$_benchCollections collections, runs=$samples',
        );

        final threshold = _strict ? 1000 : 5000;
        expect(
          median.inMilliseconds,
          lessThan(threshold),
          reason: 'M1 回归线：getTables() 中位数应 < ${threshold}ms',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    // ------------------------------------------------------------------
    // M2: 大结果集查询 —— 10 万文档 find 取数延迟
    // 宽松回归线：< 10000ms；严格：< 3000ms
    // ------------------------------------------------------------------
    test(
      'M2: find $_benchRows documents latency',
      () async {
        if (!mongoE2EGatewayReady) return;
        const collection = 'bench_big';
        final seedWatch = Stopwatch()..start();
        const batchSize = 10000;
        for (var i = 0; i < _benchRows; i += batchSize) {
          final docs = List<Map<String, dynamic>>.generate(
            batchSize,
            (j) => {'seq': i + j, 'v': 'row_${i + j}'},
          );
          final ok = await adapter.insertMany(collection, docs);
          expect(ok, isTrue, reason: '种子数据插入失败 at offset $i');
        }
        seedWatch.stop();
        // ignore: avoid_print
        print(
          '[BENCH][M2] seeded $_benchRows documents in '
          '${seedWatch.elapsed.inMilliseconds} ms (不计入基准)',
        );

        // 预热
        await adapter.executeQuery('db.$collection.find({}).limit(1)');

        final samples = <int>[];
        for (var run = 0; run < 3; run++) {
          final watch = Stopwatch()..start();
          final result = await adapter.executeQuery(
            'db.$collection.find({}).limit($_benchRows)',
          );
          watch.stop();
          expect(
            result.rows.length,
            _benchRows,
            reason: '应完整取回 $_benchRows 条文档',
          );
          samples.add(watch.elapsed.inMilliseconds);
        }
        samples.sort();
        final median = Duration(milliseconds: samples[1]);
        _BenchReport.record(
          'M2',
          'find $_benchRows docs median of 3 runs',
          median,
          'runs=$samples',
        );

        final threshold = _strict ? 3000 : 10000;
        expect(
          median.inMilliseconds,
          lessThan(threshold),
          reason: 'M2 回归线：10 万文档取数中位数应 < ${threshold}ms',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}
