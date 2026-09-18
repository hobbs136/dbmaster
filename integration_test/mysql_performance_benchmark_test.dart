// ============================================================================
// MySQL Performance Benchmark Tests (P1/P2/P3)
// Tests: Real MySQL server performance baselines for the $APPEAL Performance
//        dimension
// Target: real MySQL via DBMASTER_MYSQL_* (see config/mysql_test_config.dart)
//
// Benchmark parameters (dart-define overridable):
//   DBMASTER_BENCH_TABLES  表数量种子规模，默认 1000（文档目标值 5000）
//   DBMASTER_BENCH_ROWS    大表行数，默认 100000
//   DBMASTER_BENCH_STRICT  设为 1 时按验收指标硬阈值断言，否则走宽松回归线
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// 基准结果记录与汇总输出（集成测试允许 print）。
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
    print('================ PERFORMANCE BASELINE SUMMARY ================');
    for (final line in _lines) {
      // ignore: avoid_print
      print(line);
    }
    // ignore: avoid_print
    print('==============================================================');
  }
}

int get _benchTables {
  final v = const String.fromEnvironment(
    'DBMASTER_BENCH_TABLES',
    defaultValue: '1000',
  );
  return int.tryParse(v) ?? 1000;
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

DatabaseConnection _conn(String idSuffix) {
  return DatabaseConnection(
    id: 'bench_$idSuffix',
    name: 'Benchmark Connection $idSuffix',
    type: DatabaseType.mysql,
    host: MySQLTestConfig.host,
    port: MySQLTestConfig.port,
    username: MySQLTestConfig.username,
    password: MySQLTestConfig.password,
  );
}

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

  group('MySQL Performance Benchmark', () {
    late MySQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      await adapter.connect(_conn('seed'));
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('USE mysql');
        await adapter.dropDatabase(testDbName);
      } catch (_) {
        // 回收失败不影响基准结果
      }
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    tearDownAll(_BenchReport.summary);

    // ------------------------------------------------------------------
    // P1: 元数据加载 —— N 表实例 getTables() 延迟
    // 验收指标（$APPEAL 4.1.2）：展开单库节点 < 500ms
    // 宽松回归线：< 5000ms；严格模式：< 1000ms（适配器层参考值）
    // ------------------------------------------------------------------
    test(
      'P1: getTables() latency with $_benchTables tables',
      () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        final seedWatch = Stopwatch()..start();
        for (var i = 0; i < _benchTables; i++) {
          await adapter.executeQuery(
            'CREATE TABLE `bench_t$i` (id INT PRIMARY KEY, v VARCHAR(32))',
          );
        }
        seedWatch.stop();
        // ignore: avoid_print
        print(
          '[BENCH][P1] seeded $_benchTables tables in '
          '${seedWatch.elapsed.inSeconds} s (不计入基准)',
        );

        // 预热一次，排除首个连接的元数据缓存构建成本
        await adapter.getTables();

        final samples = <int>[];
        for (var run = 0; run < 3; run++) {
          final watch = Stopwatch()..start();
          final tables = await adapter.getTables();
          watch.stop();
          expect(
            tables.length,
            _benchTables,
            reason: 'getTables() 应返回全部 $_benchTables 张表',
          );
          samples.add(watch.elapsed.inMilliseconds);
        }
        samples.sort();
        final median = Duration(milliseconds: samples[1]);
        _BenchReport.record(
          'P1',
          'getTables() median of 3 runs',
          median,
          '$_benchTables tables, runs=$samples',
        );

        final threshold = _strict ? 1000 : 5000;
        expect(
          median.inMilliseconds,
          lessThan(threshold),
          reason: 'P1 回归线：getTables() 中位数应 < ${threshold}ms',
        );
      },
      timeout: const Timeout(Duration(minutes: 15)),
    );

    // ------------------------------------------------------------------
    // P2: 大数据量查询 —— 10 万行 SELECT 执行+取数延迟
    // 验收指标（$APPEAL 4.1.2）：首屏渲染 < 1s（取数延迟是其输入基线）
    // 宽松回归线：< 10000ms；严格模式：< 3000ms
    // ------------------------------------------------------------------
    test(
      'P2: SELECT $_benchRows rows latency',
      () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await adapter.executeQuery(
          'CREATE TABLE `bench_big` (id INT PRIMARY KEY, v VARCHAR(64))',
        );
        final insertWatch = Stopwatch()..start();
        await adapter.executeQuery(
          // T29：网关每语句独立连接，SET SESSION 不跨语句保持——改用语句级
          // optimizer hint SET_VAR。
          'INSERT /*+ SET_VAR(cte_max_recursion_depth = ${_benchRows + 1000}) */ '
          'INTO `bench_big` (id, v) '
          'WITH RECURSIVE seq AS ('
          '  SELECT 1 AS n '
          '  UNION ALL SELECT n + 1 FROM seq WHERE n < $_benchRows'
          ') SELECT n, CONCAT(\'row_\', n) FROM seq',
        );
        insertWatch.stop();
        // ignore: avoid_print
        print(
          '[BENCH][P2] seeded $_benchRows rows in '
          '${insertWatch.elapsed.inMilliseconds} ms (不计入基准)',
        );

        // 预热
        await adapter.executeQuery('SELECT * FROM `bench_big` LIMIT 1');

        final samples = <int>[];
        for (var run = 0; run < 3; run++) {
          final watch = Stopwatch()..start();
          final result = await adapter.executeQuery(
            'SELECT * FROM `bench_big` LIMIT $_benchRows',
          );
          watch.stop();
          expect(result.rows.length, _benchRows, reason: '应完整取回 $_benchRows 行');
          samples.add(watch.elapsed.inMilliseconds);
        }
        samples.sort();
        final median = Duration(milliseconds: samples[1]);
        _BenchReport.record(
          'P2',
          'SELECT $_benchRows rows median of 3 runs',
          median,
          'runs=$samples',
        );

        final threshold = _strict ? 3000 : 10000;
        expect(
          median.inMilliseconds,
          lessThan(threshold),
          reason: 'P2 回归线：10 万行取数中位数应 < ${threshold}ms',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    // ------------------------------------------------------------------
    // P3: 查询控制 —— KILL QUERY 取消响应延迟
    // 验收指标（$APPEAL 4.1.2）：取消 → 服务端收到 KILL < 1s
    // 宽松回归线：< 5000ms；严格模式：< 1000ms
    // ------------------------------------------------------------------
    test('P3: KILL QUERY cancel latency', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final victim = MySQLAdapter();
      final killer = MySQLAdapter();
      await victim.connect(_conn('victim'));
      await killer.connect(_conn('killer'));

      try {
        // 受害连接上挂起 60s 慢查询
        final victimWatch = Stopwatch()..start();
        Object? victimError;
        final victimFuture = victim
            .executeQuery('SELECT SLEEP(60)')
            .then((_) => null)
            .catchError((Object e) {
              victimError = e;
              return null;
            });

        // 等慢查询真正进入 SLEEP 状态
        await Future<void>.delayed(const Duration(seconds: 1));

        // 从 killer 连接定位受害线程并 KILL
        final killWatch = Stopwatch()..start();
        final idResult = await killer.executeQuery(
          "SELECT ID FROM information_schema.PROCESSLIST "
          "WHERE INFO LIKE 'SELECT SLEEP(60)%' "
          "AND USER = SUBSTRING_INDEX(CURRENT_USER(), '@', 1)",
        );
        expect(
          idResult.rows,
          isNotEmpty,
          reason: 'PROCESSLIST 中应能找到受害 SLEEP 查询',
        );
        final threadId = idResult.rows.first['ID'];
        await killer.executeQuery('KILL QUERY $threadId');

        // 等待受害查询返回（被杀）
        await victimFuture.timeout(const Duration(seconds: 10));
        killWatch.stop();
        victimWatch.stop();

        _BenchReport.record(
          'P3',
          'KILL QUERY → 慢查询终止',
          killWatch.elapsed,
          'victim error: ${victimError ?? '无异常返回'}',
        );

        final threshold = _strict ? 1000 : 5000;
        expect(
          killWatch.elapsed.inMilliseconds,
          lessThan(threshold),
          reason: 'P3 回归线：KILL 到查询终止应 < ${threshold}ms',
        );
      } finally {
        if (victim.isConnected) await victim.disconnect();
        if (killer.isConnected) await killer.disconnect();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
