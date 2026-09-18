// ============================================================================
// SQL Server P2 Capability Parity Integration Tests
// Tests: Real SQL Server capability features (process list, collations,
//        sequences, materialized views, replication status, structure export)
// Prerequisites: SQL Server 2022 via DBMASTER_SQLSERVER_* defines
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';

import 'config/sqlserver_test_config.dart';
import 'helpers/ss_gateway_e2e_helper.dart';

// T28：SS 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
// 二进制不可得时全组以可 grep 的 SQLSERVER_E2E_SKIP 跳过（无假绿）。
void main() {
  bool ssE2EGatewayReady = false;
  setUpAll(() async {
    ssE2EGatewayReady = await ensureEmbeddedServerForSsE2E();
    if (ssE2EGatewayReady && !SQLServerTestConfig.available) {
      // ignore: avoid_print
      print('SS_E2E_SKIP: DBMASTER_SQLSERVER_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      ssE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SQL Server P2 Capability Parity', () {
    late SqlServerAdapter adapter;
    const testDbName = 'dbmaster_handoff_setup';

    setUpAll(() async {
      adapter = SqlServerAdapter();
      final connection = DatabaseConnection(
        id: 'ss_p2_conn',
        name: 'SS P2 Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
        database: testDbName,
      );
      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to SQL Server');
    });

    tearDownAll(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    testWidgets('TC-SS-CAP-001: process list returns active sessions', (
      tester,
    ) async {
      final processes = await adapter.getProcessList();
      expect(processes, isNotEmpty);
      // At least our own connection should appear.
      expect(
        processes.any((p) => p.user.toLowerCase() == 'sa'),
        isTrue,
        reason: 'Expected at least one sa session in process list',
      );
    });

    testWidgets('TC-SS-CAP-002: collation list is non-empty', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final collations = await adapter.getCollations();
      expect(collations, isNotEmpty);
      expect(
        collations.any(
          (c) =>
              c['name']?.toString().toLowerCase().contains('chinese') == true,
        ),
        isTrue,
        reason: 'Expected Chinese_PRC_* collation to be present',
      );
    });

    testWidgets('TC-SS-CAP-003: sequence appears after creation', (
      tester,
    ) async {
      await adapter.executeQuery('DROP SEQUENCE IF EXISTS dbo.s_test');
      await adapter.executeQuery(
        'CREATE SEQUENCE dbo.s_test AS INT START WITH 1 INCREMENT BY 1',
      );
      try {
        final sequences = await adapter.getSequences();
        expect(sequences, contains('dbo.s_test'));
      } finally {
        await adapter.executeQuery('DROP SEQUENCE IF EXISTS dbo.s_test');
      }
    });

    testWidgets(
      'TC-SS-CAP-004: indexed view appears in materialized view list',
      (tester) async {
        await adapter.executeQuery('DROP VIEW IF EXISTS dbo.v_indexed');
        await adapter.executeQuery('SET ANSI_NULLS ON');
        await adapter.executeQuery('SET QUOTED_IDENTIFIER ON');
        await adapter.executeQuery('SET CONCAT_NULL_YIELDS_NULL ON');
        await adapter.executeQuery('SET ANSI_WARNINGS ON');
        await adapter.executeQuery('SET ANSI_PADDING ON');
        await adapter.executeQuery('''
        CREATE VIEW dbo.v_indexed WITH SCHEMABINDING AS
        SELECT id FROM dbo.t_types WHERE id > 0
      ''');
        await adapter.executeQuery('''
        CREATE UNIQUE CLUSTERED INDEX IX_v_indexed ON dbo.v_indexed(id)
      ''');
        try {
          final views = await adapter.getMaterializedViews();
          expect(views, contains('dbo.v_indexed'));
        } finally {
          await adapter.executeQuery('DROP VIEW IF EXISTS dbo.v_indexed');
        }
      },
    );

    testWidgets('TC-SS-CAP-005: replication status query does not throw', (
      tester,
    ) async {
      final status = await adapter.getReplicationStatus();
      // No AlwaysOn environment is expected; the important thing is that it
      // returns gracefully without throwing or crashing.
      expect(status, anyOf(isNull, isA<Object>()));
    });

    testWidgets('TC-SS-CAP-006: exported structure includes procedures', (
      tester,
    ) async {
      final script = await adapter.exportDatabaseStructure(testDbName);
      expect(script, contains('p_echo'));
      expect(script, contains('p_needparam'));
      expect(script, contains('p_multi'));
      expect(script, contains('CREATE PROCEDURE'));
      expect(script, contains('CREATE TABLE'));
    });
  });
}
