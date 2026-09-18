// 第四阶段 DDL 锁分析 E2E 测试（requirements-phase4.md R13-R18）。
//
// 连真实 MySQL 8.0.46（支持 INSTANT）+ MySQL 5.7（3307，不支持 INSTANT），
// 验证 SchemaAnalyzer.analyzeDdl 的锁语义推断 + TRUNCATE 识别 + 评级修正端到端流转。
// 连接参数经 --dart-define=DBMASTER_MYSQL*（8.0）/ DBMASTER_MYSQL57*（5.7）
// 提供；连不上/缺参则跳过（CI 友好）。
//
// 运行：flutter test -d windows integration_test/ddl_lock_analysis_e2e_test.dart
//
// 覆盖：
// - R13: MySQL 8.0 ADD COLUMN 末尾 → INSTANT；MySQL 5.7 → INPLACE
// - R14: ImpactReport 锁字段（ddlAlgorithm/lockType/concurrencyImpact/algorithmNote）
// - R15: 评级结合 algorithm（INSTANT→low、COPY 大表→high）
// - R18: TRUNCATE TABLE 识别 + high 评级（之前落 UNKNOWN→medium bug）
// - 向后兼容：不传 getServerVersion → unknown

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/schema_analyzer/ddl_algorithm.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/schema_analyzer/schema_analyzer.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

late MySQLAdapter adapter;
late String testDbName;
bool _connected = false;

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

  group('DDL 锁分析 E2E（真实 MySQL 8.0）', () {
    setUp(() async {
      adapter = MySQLAdapter();
      testDbName =
          'ddl_lock_e2e_${DateTime.now().millisecondsSinceEpoch}';

      final connection = DatabaseConnection(
        id: 'ddl_lock_e2e_${DateTime.now().millisecondsSinceEpoch}',
        name: 'DDL Lock E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port, // 8.0.46
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: '',
      );

      try {
        final ok = await adapter.connect(connection);
        if (!ok || !adapter.isConnected) return;
        _connected = true;
        await adapter.createDatabase(testDbName);
        await adapter.useDatabase(testDbName);
      } catch (_) {
        _connected = false;
      }
    });

    tearDown(() async {
      if (_connected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        try {
          await adapter.disconnect();
        } catch (_) {}
      }
    });

    /// 辅助：执行查询（返回 List<Map>，适配 analyzeDdl 的 executeQuery 签名）。
    Future<List<Map<String, dynamic>>> executeQuery(String sql) async {
      final result = await adapter.executeQuery(sql);
      return result.rows;
    }

    /// 辅助：获取服务器版本。
    Future<String?> getServerVersion() async {
      final v = await adapter.getServerVersion();
      return v?['version'] as String?;
    }

    // ────────────────────────────────────────────────────────
    // R13 + R14：锁语义推断（MySQL 8.0 INSTANT 支持）
    // ────────────────────────────────────────────────────────
    test('R13/R14: MySQL 8.0 ADD COLUMN（末尾）→ INSTANT + low', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) {
        print('跳过：未连上 MySQL');
        return;
      }
      // 建基础表（带数据，验证 INSTANT 不论表大小都是 low）。
      await executeQuery(
        'CREATE TABLE `t_instant` (id INT PRIMARY KEY, name VARCHAR(64))',
      );
      await executeQuery(
        "INSERT INTO `t_instant` VALUES (1,'a'),(2,'b'),(3,'c')",
      );

      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t_instant ADD COLUMN age INT',
        databaseType: 'mysql',
        executeQuery: executeQuery,
        getServerVersion: getServerVersion,
      );

      expect(report.ddlAlgorithm, DdlAlgorithm.instant,
          reason: 'MySQL 8.0.46 应推断 INSTANT');
      expect(report.concurrencyImpact, ConcurrencyImpact.none);
      expect(report.lockType, isNotNull);
      expect(report.algorithmNote, contains('INSTANT'));
      expect(report.riskLevel, RiskLevel.low);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('R13: MySQL 8.0 ADD COLUMN AFTER → INPLACE（INSTANT 不支持指定位置）',
        () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) {
        print('跳过：未连上 MySQL');
        return;
      }
      await executeQuery(
        'CREATE TABLE `t_after` (id INT PRIMARY KEY, name VARCHAR(64))',
      );

      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t_after ADD COLUMN age INT AFTER id',
        databaseType: 'mysql',
        executeQuery: executeQuery,
        getServerVersion: getServerVersion,
      );

      expect(report.ddlAlgorithm, DdlAlgorithm.inplace);
      expect(report.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('R13: MySQL 8.0 MODIFY COLUMN（改类型）→ COPY', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) {
        print('跳过：未连上 MySQL');
        return;
      }
      await executeQuery(
        'CREATE TABLE `t_copy` (id INT PRIMARY KEY, val INT)',
      );
      await executeQuery('INSERT INTO `t_copy` VALUES (1, 100)');

      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t_copy MODIFY COLUMN val BIGINT',
        databaseType: 'mysql',
        executeQuery: executeQuery,
        getServerVersion: getServerVersion,
      );

      expect(report.ddlAlgorithm, DdlAlgorithm.copy);
      expect(report.concurrencyImpact, ConcurrencyImpact.blocksDml);
      expect(report.lockType, contains('全表锁'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    // ────────────────────────────────────────────────────────
    // R18：TRUNCATE TABLE 识别 + 评级修复
    // ────────────────────────────────────────────────────────
    test('R18: TRUNCATE TABLE → TRUNCATE_TABLE + metadataOnly + high', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) {
        print('跳过：未连上 MySQL');
        return;
      }
      await executeQuery(
        'CREATE TABLE `t_trunc` (id INT PRIMARY KEY)',
      );
      await executeQuery('INSERT INTO `t_trunc` VALUES (1),(2)');

      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'TRUNCATE TABLE t_trunc',
        databaseType: 'mysql',
        executeQuery: executeQuery,
        getServerVersion: getServerVersion,
      );

      // R18 bug 修复：之前落 UNKNOWN。
      expect(report.ddlType, 'TRUNCATE_TABLE');
      expect(report.ddlAlgorithm, DdlAlgorithm.metadataOnly);
      expect(report.concurrencyImpact, ConcurrencyImpact.none);
      // R18 评级修复：之前兜底 medium，现正确归 high。
      expect(report.riskLevel, RiskLevel.high);
    }, timeout: const Timeout(Duration(seconds: 30)));

    // ────────────────────────────────────────────────────────
    // R14 向后兼容：不传 getServerVersion → unknown
    // ────────────────────────────────────────────────────────
    test('向后兼容：不传 getServerVersion → 锁字段 unknown', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) {
        print('跳过：未连上 MySQL');
        return;
      }
      await executeQuery(
        'CREATE TABLE `t_compat` (id INT PRIMARY KEY)',
      );

      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t_compat ADD COLUMN c INT',
        databaseType: 'mysql',
        executeQuery: executeQuery,
        // 不传 getServerVersion
      );

      expect(report.ddlAlgorithm, DdlAlgorithm.unknown);
      expect(report.concurrencyImpact, ConcurrencyImpact.unknown);
      // 既有行为不变。
      expect(report.riskLevel, RiskLevel.low);
    }, timeout: const Timeout(Duration(seconds: 30)));

    // ────────────────────────────────────────────────────────
    // R13：破坏性操作（DROP TABLE）即使 metadataOnly 也 high
    // ────────────────────────────────────────────────────────
    test('R15: DROP TABLE → metadataOnly + high（数据丢失维度优先）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) {
        print('跳过：未连上 MySQL');
        return;
      }
      await executeQuery(
        'CREATE TABLE `t_drop` (id INT PRIMARY KEY)',
      );

      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'DROP TABLE t_drop',
        databaseType: 'mysql',
        executeQuery: executeQuery,
        getServerVersion: getServerVersion,
      );

      expect(report.ddlAlgorithm, DdlAlgorithm.metadataOnly);
      expect(report.riskLevel, RiskLevel.high); // 数据丢失优先，不走 instant→low
    }, timeout: const Timeout(Duration(seconds: 30)));

    // ────────────────────────────────────────────────────────
    // R13：真实版本探测验证
    // ────────────────────────────────────────────────────────
    test('真实版本探测：getServerVersion 返回有效版本字符串', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) {
        print('跳过：未连上 MySQL');
        return;
      }
      final version = await getServerVersion();
      expect(version, isNotNull);
      expect(version!, startsWith('8.0.'),
          reason: '小雷服务器 3306 应是 MySQL 8.0.46');
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  // ────────────────────────────────────────────────────────
  // MySQL 5.7 对比组（3307，不支持 INSTANT）
  // ────────────────────────────────────────────────────────
  group('DDL 锁分析 E2E（真实 MySQL 5.7 对比）', () {
    late MySQLAdapter adapter57;
    late String testDbName57;
    bool connected57 = false;

    setUp(() async {
      adapter57 = MySQLAdapter();
      testDbName57 =
          'ddl_lock57_${DateTime.now().millisecondsSinceEpoch}';

      // 从服务器 5.7（3307 root）：连接参数经 DBMASTER_MYSQL57_* 提供
      //（收敛自内联凭据——开源剥离，见 mysql_test_config.dart）。
      if (!MySQLTestConfig.isLegacy57Configured) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'ddl_lock57_${DateTime.now().millisecondsSinceEpoch}',
        name: 'DDL Lock 57',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.legacy57Host,
        port: MySQLTestConfig.legacy57Port,
        username: MySQLTestConfig.legacy57Username,
        password: MySQLTestConfig.legacy57Password,
        database: '',
      );

      try {
        final ok = await adapter57.connect(connection);
        if (!ok || !adapter57.isConnected) return;
        connected57 = true;
        await adapter57.createDatabase(testDbName57);
        await adapter57.useDatabase(testDbName57);
      } catch (_) {
        connected57 = false;
      }
    });

    tearDown(() async {
      if (connected57) {
        try {
          await adapter57.executeQuery(
              'DROP DATABASE IF EXISTS `$testDbName57`');
        } catch (_) {}
        try {
          await adapter57.disconnect();
        } catch (_) {}
      }
    });

    Future<List<Map<String, dynamic>>> executeQuery57(String sql) async {
      final result = await adapter57.executeQuery(sql);
      return result.rows;
    }

    test('R13: MySQL 5.7 ADD COLUMN → INPLACE（不支持 INSTANT）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!connected57) {
        print('跳过：未连上 MySQL 5.7');
        return;
      }
      await executeQuery57(
        'CREATE TABLE `t57` (id INT PRIMARY KEY, name VARCHAR(64))',
      );

      final version = (await adapter57.getServerVersion())?['version'];
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t57 ADD COLUMN age INT',
        databaseType: 'mysql',
        executeQuery: executeQuery57,
        getServerVersion: () async => version as String?,
      );

      // 5.7 不支持 INSTANT → INPLACE。
      expect(report.ddlAlgorithm, DdlAlgorithm.inplace);
      expect(report.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
