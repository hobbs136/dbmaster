// ============================================================================
// ClickHouse Integration Tests（T29 第三批，/api/gw 网关壳真库链路）
//
// 前提：dbmaster server 二进制（DBMASTER_SERVER_BIN 或 exe 同目录）+
// 真实 ClickHouse（参数经 DBMASTER_CH_* 提供，MySQL 兼容口 9004，测试账号
// 无 DROP 授权——种子表固定名 + TRUNCATE 清理，见
// config/clickhouse_test_config.dart）。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/clickhouse_adapter.dart';
import 'config/clickhouse_test_config.dart';
import 'helpers/ch_gateway_e2e_helper.dart';

/// 本套件的种子表（固定名，无 DROP 授权——TRUNCATE 清理）。
const _kSeedTable = 'flutter_ch_e2e';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // CH 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 CH_E2E_SKIP 跳过（无假绿）。
  var chE2EReady = false;
  setUpAll(() async {
    chE2EReady = await ensureEmbeddedServerForChE2E();
    if (chE2EReady && !ClickhouseTestConfig.available) {
      // ignore: avoid_print
      print('CH_E2E_SKIP: DBMASTER_CH_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      chE2EReady = false;
    }
  });

  DatabaseConnection makeConn({String id = 'test_ch_conn'}) =>
      DatabaseConnection(
        id: id,
        name: 'Test CH Connection',
        type: DatabaseType.clickhouse,
        host: ClickhouseTestConfig.host,
        port: ClickhouseTestConfig.port,
        username: ClickhouseTestConfig.username,
        password: ClickhouseTestConfig.password,
        database: ClickhouseTestConfig.database,
      );

  group('ClickHouse Connection', () {
    late ClickhouseAdapter adapter;

    setUp(() {
      adapter = ClickhouseAdapter();
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) await adapter.disconnect();
      } catch (_) {}
    });

    testWidgets('connect 成功（三段式：映射/草稿 test/注册）', (tester) async {
      if (!chE2EReady) return;
      final result = await adapter.connect(makeConn());
      expect(result, isTrue,
          reason:
              'connect ${ClickhouseTestConfig.host}:${ClickhouseTestConfig.port} failed');
      expect(adapter.isConnected, isTrue);
    });

    testWidgets('错误凭据 → connect false（草稿 test 语义）', (tester) async {
      if (!chE2EReady) return;
      final bad = DatabaseConnection(
        id: 'test_ch_conn_bad',
        name: 'bad',
        type: DatabaseType.clickhouse,
        host: ClickhouseTestConfig.host,
        port: ClickhouseTestConfig.port,
        username: 'wrong_user',
        password: 'wrong_password',
      );
      final result = await adapter.connect(bad);
      expect(result, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('testConnection 单发草稿端点 → null', (tester) async {
      if (!chE2EReady) return;
      final error = await adapter.testConnection(makeConn(id: 'test_ch_t'));
      expect(error, isNull);
    });
  });

  group('ClickHouse Browse + Query（真库经 /api/gw）', () {
    late ClickhouseAdapter adapter;

    setUp(() async {
      adapter = ClickhouseAdapter();
      if (!chE2EReady) return;
      expect(await adapter.connect(makeConn()), isTrue);
      // 种子表（幂等建 + 清 + 插两行）。
      await adapter.executeQuery(
        'CREATE TABLE IF NOT EXISTS $_kSeedTable '
        '(id UInt32, name String, amount Decimal(10,2), d Date) '
        'ENGINE = MergeTree ORDER BY id',
      );
      await adapter.executeQuery('TRUNCATE TABLE $_kSeedTable');
      await adapter.executeQuery(
        "INSERT INTO $_kSeedTable VALUES "
        "(1, 'a', 1.50, '2026-08-26'), (2, 'b', 2.50, '2026-08-27')",
      );
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          await adapter.executeQuery('TRUNCATE TABLE $_kSeedTable');
          await adapter.disconnect();
        }
      } catch (_) {}
    });

    testWidgets('getDatabases 含默认库且滤 information_schema 噪音',
        (tester) async {
      if (!chE2EReady) return;
      final dbs = await adapter.getDatabases();
      expect(dbs, contains(ClickhouseTestConfig.database));
      expect(dbs, isNot(contains('information_schema')));
      expect(dbs, isNot(contains('INFORMATION_SCHEMA')));
      expect(dbs, isNot(contains('system_metadata')));
    });

    testWidgets('useDatabase record-only + getTables 经 database 路由',
        (tester) async {
      if (!chE2EReady) return;
      await adapter.useDatabase(ClickhouseTestConfig.database);
      final tables = await adapter.getTables();
      expect(tables, contains(_kSeedTable));
    });

    testWidgets('executeQuery：位置数组行 + 类型到达形态', (tester) async {
      if (!chE2EReady) return;
      final r = await adapter.executeQuery(
        'SELECT id, name, amount, d FROM $_kSeedTable ORDER BY id',
      );
      expect(r.columns, ['id', 'name', 'amount', 'd']);
      expect(r.rows.length, 2);
      expect(r.rows[0]['id'], 1);
      expect(r.rows[0]['name'], 'a');
      // Decimal → 保精度字符串（server rust_decimal 臂）。
      expect(r.rows[0]['amount'].toString(), startsWith('1.5'));
      // Date → SQL 惯例字符串（server chrono 臂，2026-08-27 修复；
      // 实机钉定于 server gw_clickhouse 类型矩阵）。
      expect(r.rows[0]['d'], '2026-08-26');
      expect(r.rows[1]['d'], '2026-08-27');
    });

    testWidgets('getTableData / getTableRowCount', (tester) async {
      if (!chE2EReady) return;
      final data = await adapter.getTableData(_kSeedTable, limit: 10);
      expect(data.rows.length, 2);
      expect(await adapter.getTableRowCount(_kSeedTable), 2);
    });

    testWidgets('坏 SQL → ClickhouseGatewayException(DB_ERROR) 上抛',
        (tester) async {
      if (!chE2EReady) return;
      await expectLater(
        adapter.executeQuery('SELECT * FROM no_such_table_e2e'),
        throwsA(
          isA<ClickhouseGatewayException>()
              .having((e) => e.code, 'code', 'DB_ERROR'),
        ),
      );
    });

    testWidgets('事务 fail-loud（CH 无事务，防假回滚）', (tester) async {
      if (!chE2EReady) return;
      await expectLater(
          adapter.beginTransaction(), throwsA(isA<UnsupportedError>()));
      expect(adapter.isInTransaction, isFalse);
    });
  });
}
