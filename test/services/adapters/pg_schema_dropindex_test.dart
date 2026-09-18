// T063 — live verification that PostgreSQL dropIndex resolves a
// schema-qualified index name (the fix), and that the pre-fix bare-name form
// fails for a non-default schema (the bug).
//
// T29 第二批：直连下线后改为**网关路径真跑**——经 embedded server 的
// /api/gw SSE 通道打真实 PG（连接参数经 --dart-define=DBMASTER_PG* 提供，
// 缺参即跳过）。前置：
// `DBMASTER_SERVER_BIN` 指向 dbmaster-server 二进制（cargo build 产物）；
// 不可得时全组以可 grep 的 PG_LIVE_SKIP 跳过（无假绿）。
//
// Run: flutter test test/services/adapters/pg_schema_dropindex_test.dart
//      （需 DBMASTER_SERVER_BIN=<path-to-dbmaster-server>）

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';

import '../../helpers/pg_gateway_live_helper.dart';

void main() {
  // T063 — connection params; override via -D / env if needed.
  // 开源剥离：默认值清空，缺参（host 为空）整组跳过。
  const host = String.fromEnvironment('DBMASTER_PG_HOST', defaultValue: '');
  const port = int.fromEnvironment('DBMASTER_PG_PORT', defaultValue: 5432);
  const user = String.fromEnvironment('DBMASTER_PG_USER', defaultValue: '');
  const password = String.fromEnvironment('DBMASTER_PG_PASSWORD', defaultValue: '');
  const database = String.fromEnvironment('DBMASTER_PG_DATABASE', defaultValue: 'postgres');

  late PostgreSQLAdapter adapter;
  bool gatewayReady = false;

  setUpAll(() async {
    gatewayReady = await ensureEmbeddedServerForPgLive();
    if (!gatewayReady) {
      // ignore: avoid_print
      print('PG_LIVE_SKIP: embedded server 不可得（恢复条件：构建 '
          'dbmaster-server 并设 DBMASTER_SERVER_BIN）');
    } else if (host.isEmpty) {
      gatewayReady = false;
      // ignore: avoid_print
      print('PG_LIVE_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
    }
  });

  tearDownAll(() async {
    await stopEmbeddedServerForPgLive();
  });

  setUp(() => adapter = PostgreSQLAdapter());

  tearDown(() async {
    try {
      if (adapter.isConnected) await adapter.disconnect();
    } catch (_) {}
  });

  test('T063: dropIndex drops a non-default-schema index via qualified name (the fix); bare name fails (the bug)', () async {
    if (!gatewayReady) return;

    final connection = DatabaseConnection(
      id: 't063_pg',
      name: 'T063 PG',
      type: DatabaseType.postgresql,
      host: host,
      port: port,
      username: user,
      password: password,
      database: database,
    );

    final connected = await adapter.connect(connection);
    if (!connected) {
      // T063 — skip (not fail) when the test DB is unreachable, so this
      // remains a live-when-possible check rather than a CI blocker.
      // ignore: avoid_print
      print('PG_LIVE_SKIP: could not connect to $host:$port via gateway');
      return;
    }

    // Unique, non-default schema (NOT on the default search_path "$user",public).
    final schema = 't063_${DateTime.now().millisecondsSinceEpoch}';
    final table = 't';
    final idx = 'idx_email';
    final qualifiedIndex = '$schema.$idx';

    try {
      // Setup: create schema, table, index in the non-default schema.
      await adapter.executeQuery('DROP SCHEMA IF EXISTS "$schema" CASCADE');
      await adapter.executeQuery('CREATE SCHEMA "$schema"');
      await adapter.executeQuery('CREATE TABLE "$schema"."$table" (id int, email text)');
      await adapter.executeQuery('CREATE INDEX "$idx" ON "$schema"."$table" (email)');
      expect(await _indexExists(adapter, schema, idx), isTrue, reason: 'setup: index should exist');

      // 1) THE BUG (pre-fix form): bare index name → DROP INDEX "idx_email" →
      //    resolves against search_path → not found → adapter returns false.
      final bareResult = await adapter.dropIndex(table, idx);
      expect(bareResult, isFalse, reason: 'bare index name should fail to resolve off search_path');
      expect(await _indexExists(adapter, schema, idx), isTrue, reason: 'bug: index must still exist after bare drop');

      // 2) THE FIX: qualified index name (what _showIndexMenu now passes) →
      //    DROP INDEX "schema"."idx_email" → resolves → dropped.
      final fixedResult = await adapter.dropIndex(table, qualifiedIndex);
      expect(fixedResult, isTrue, reason: 'qualified index name should drop successfully');
      expect(await _indexExists(adapter, schema, idx), isFalse, reason: 'fix: index must be gone after qualified drop');

      // 3) CREATE via qualified table (EditIndexDialog's create step): PG
      //    createIndex qualifies the table internally → ON "schema"."t".
      final createOk = await adapter.createIndex('$schema.$table', 'idx_new', ['email']);
      expect(createOk, isTrue, reason: 'createIndex via qualified table should succeed');
      expect(await _indexExists(adapter, schema, 'idx_new'), isTrue, reason: 'new index should exist after qualified create');
    } finally {
      try {
        await adapter.executeQuery('DROP SCHEMA IF EXISTS "$schema" CASCADE');
      } catch (_) {}
    }
  });
}

/// Returns true iff the given index exists in the given schema.
Future<bool> _indexExists(PostgreSQLAdapter adapter, String schema, String idx) async {
  final result = await adapter.executeQuery(
    "SELECT 1 FROM pg_indexes WHERE schemaname = '$schema' AND indexname = '$idx' LIMIT 1",
  );
  return result.rows.isNotEmpty;
}
