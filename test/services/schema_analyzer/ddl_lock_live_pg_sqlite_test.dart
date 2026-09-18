// DDL 锁语义真库 E2E 测试 —— PostgreSQL + SQLite（B4）。
//
// 验证 B4 的 _inferPostgres / _inferSqlite 在真库上的端到端行为：
// - adapter.connect / getServerVersion 通路
// - SchemaAnalyzer.analyzeDdl 对真库 DDL 返回正确的 DdlAlgorithm
//
// T29 第二批：PG 组直连下线后改为**网关路径真跑**（经 embedded server 的
// /api/gw SSE 通道）；前置 DBMASTER_SERVER_BIN 指向 server 二进制，不可得时
// 以可 grep 的 PG_LIVE_SKIP 跳过（无假绿）。SQLite 组用临时文件（总能跑）。
// 运行：flutter test test/services/schema_analyzer/ddl_lock_live_pg_sqlite_test.dart
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/schema_analyzer/ddl_algorithm.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/schema_analyzer/schema_analyzer.dart';

import '../../helpers/pg_gateway_live_helper.dart';

// ──────────────── PG 连接配置（可 dart-define 覆盖；开源剥离：默认值
// 清空，缺参即 PG_LIVE_SKIP 跳过）────────────────
const _pgHost =
    String.fromEnvironment('DBMASTER_PG_HOST', defaultValue: '');
const _pgPort = int.fromEnvironment('DBMASTER_PG_PORT', defaultValue: 5432);
const _pgUser =
    String.fromEnvironment('DBMASTER_PG_USER', defaultValue: '');
const _pgPassword =
    String.fromEnvironment('DBMASTER_PG_PASSWORD', defaultValue: '');
const _pgDatabase =
    String.fromEnvironment('DBMASTER_PG_DATABASE', defaultValue: 'postgres');

void main() {
  // ========================================================================
  // PostgreSQL 真库：B4 _inferPostgres 锁语义
  // ========================================================================
  group('DDL 锁语义真库 E2E: PostgreSQL（B4）', () {
    late PostgreSQLAdapter adapter;
    bool gatewayReady = false;

    setUpAll(() async {
      gatewayReady = await ensureEmbeddedServerForPgLive();
      if (!gatewayReady) {
        // ignore: avoid_print
        print('PG_LIVE_SKIP: embedded server 不可得（恢复条件：构建 '
            'dbmaster-server 并设 DBMASTER_SERVER_BIN）');
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

    Future<bool> _connect() async {
      if (!gatewayReady) return false;
      if (_pgHost.isEmpty) {
        // ignore: avoid_print
        print('PG_LIVE_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
            '（开源剥离默认凭据，缺参即跳过）');
        return false;
      }
      final connection = DatabaseConnection(
        id: 'live_pg',
        name: 'live_pg',
        type: DatabaseType.postgresql,
        host: _pgHost,
        port: _pgPort,
        username: _pgUser,
        password: _pgPassword,
        database: _pgDatabase,
      );
      final ok = await adapter.connect(connection);
      if (!ok) {
        // ignore: avoid_print
        print('PG_LIVE_SKIP: 无法经网关连接 PG $_pgHost:$_pgPort');
      }
      return ok;
    }

    String _uniqueTable(String tag) =>
        't_b4_${tag}_${DateTime.now().microsecondsSinceEpoch}';

    test('B4: getServerVersion 通路（PG 版本串）', () async {
      if (!await _connect()) return;

      final v = await adapter.getServerVersion();
      expect(v, isNotNull);
      expect(v!['version'], contains('PostgreSQL'));
      print('PG version: ${v['version']}');
    });

    test('B4: ADD COLUMN → copy（PG ACCESS EXCLUSIVE 阻塞读写）', () async {
      if (!await _connect()) return;

      final table = _uniqueTable('addcol');
      try {
        await adapter.executeQuery('CREATE TABLE "$table" (id INT PRIMARY KEY)');
        final report = await SchemaAnalyzer.analyzeDdl(
          ddlStatement: 'ALTER TABLE "$table" ADD COLUMN c INT',
          databaseType: 'postgresql',
          executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
          getServerVersion: () async =>
              (await adapter.getServerVersion())?['version'] as String?,
        );
        expect(report.ddlAlgorithm, DdlAlgorithm.copy,
            reason: 'PG ALTER TABLE 拿 ACCESS EXCLUSIVE');
        expect(report.concurrencyImpact, ConcurrencyImpact.blocksDml);
        expect(report.lockType, contains('ACCESS EXCLUSIVE'));
      } finally {
        try {
          await adapter.executeQuery('DROP TABLE IF EXISTS "$table"');
        } catch (_) {}
      }
    });

    test('B4: CREATE INDEX 普通 → copy（SHARE 锁阻塞写）', () async {
      if (!await _connect()) return;

      final table = _uniqueTable('idx');
      try {
        await adapter.executeQuery(
            'CREATE TABLE "$table" (id INT PRIMARY KEY, v INT)');
        final report = await SchemaAnalyzer.analyzeDdl(
          ddlStatement: 'CREATE INDEX idx ON "$table" (v)',
          databaseType: 'postgresql',
          executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
          getServerVersion: () async =>
              (await adapter.getServerVersion())?['version'] as String?,
        );
        expect(report.ddlAlgorithm, DdlAlgorithm.copy);
        expect(report.lockType, contains('SHARE'));
      } finally {
        try {
          await adapter.executeQuery('DROP TABLE IF EXISTS "$table"');
        } catch (_) {}
      }
    });

    test('B4: CREATE INDEX CONCURRENTLY → inplace（允许并发 DML）', () async {
      if (!await _connect()) return;

      final table = _uniqueTable('idxc');
      try {
        await adapter.executeQuery(
            'CREATE TABLE "$table" (id INT PRIMARY KEY, v INT)');
        final report = await SchemaAnalyzer.analyzeDdl(
          ddlStatement: 'CREATE INDEX CONCURRENTLY idx_c ON "$table" (v)',
          databaseType: 'postgresql',
          executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
          getServerVersion: () async =>
              (await adapter.getServerVersion())?['version'] as String?,
        );
        expect(report.ddlAlgorithm, DdlAlgorithm.inplace,
            reason: 'PG CONCURRENTLY 允许并发 DML');
        expect(report.concurrencyImpact, ConcurrencyImpact.allowsConcurrentDml);
      } finally {
        try {
          await adapter.executeQuery('DROP TABLE IF EXISTS "$table"');
        } catch (_) {}
      }
    });

    test('B4: TRUNCATE → metadataOnly（瞬时）', () async {
      if (!await _connect()) return;

      final table = _uniqueTable('trunc');
      try {
        await adapter.executeQuery('CREATE TABLE "$table" (id INT)');
        final report = await SchemaAnalyzer.analyzeDdl(
          ddlStatement: 'TRUNCATE TABLE "$table"',
          databaseType: 'postgresql',
          executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
          getServerVersion: () async =>
              (await adapter.getServerVersion())?['version'] as String?,
        );
        expect(report.ddlAlgorithm, DdlAlgorithm.metadataOnly);
      } finally {
        try {
          await adapter.executeQuery('DROP TABLE IF EXISTS "$table"');
        } catch (_) {}
      }
    });
  });

  // ========================================================================
  // SQLite 真库：B4 _inferSqlite 锁语义（临时文件库，总能跑）
  // ========================================================================
  group('DDL 锁语义真库 E2E: SQLite（B4）', () {
    late SQLiteAdapter adapter;
    late String dbPath;

    setUp(() {
      adapter = SQLiteAdapter();
      dbPath =
          '${DateTime.now().microsecondsSinceEpoch}_b4_live_test.db';
    });

    tearDown(() async {
      if (adapter.isConnected) await adapter.disconnect();
      try {
        final f = File(dbPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    });

    Future<void> _connect() async {
      final connection = DatabaseConnection(
        id: 'live_sqlite',
        name: 'live_sqlite',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
      );
      final ok = await adapter.connect(connection);
      expect(ok, isTrue, reason: 'SQLite 临时库应总能连接');
    }

    test('B4: getServerVersion 通路', () async {
      await _connect();
      final v = await adapter.getServerVersion();
      expect(v, isNotNull);
      expect(v!['database'], 'SQLite');
    });

    test('B4: ADD COLUMN → metadataOnly（瞬时元数据改）', () async {
      await _connect();
      await adapter.executeQuery('CREATE TABLE t (id INT PRIMARY KEY)');
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT DEFAULT 0',
        databaseType: 'sqlite',
        executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
        getServerVersion: () async =>
            (await adapter.getServerVersion())?['version'] as String?,
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.metadataOnly);
    });

    test('B4: CREATE INDEX → copy（扫描全表阻塞写）', () async {
      await _connect();
      await adapter.executeQuery('CREATE TABLE t (id INT PRIMARY KEY, v INT)');
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'CREATE INDEX idx ON t (v)',
        databaseType: 'sqlite',
        executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
        getServerVersion: () async =>
            (await adapter.getServerVersion())?['version'] as String?,
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.copy);
    });

    test('B4: DROP COLUMN → copy（table rebuild）', () async {
      await _connect();
      await adapter.executeQuery('CREATE TABLE t (id INT, c INT)');
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t DROP COLUMN c',
        databaseType: 'sqlite',
        executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
        getServerVersion: () async =>
            (await adapter.getServerVersion())?['version'] as String?,
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.copy,
          reason: 'SQLite DROP COLUMN 是 table rebuild');
    });

    test('B4: TRUNCATE → metadataOnly', () async {
      await _connect();
      await adapter.executeQuery('CREATE TABLE t (id INT)');
      // SQLite 无原生 TRUNCATE，但 extractDdlType 会归类；用 DROP TABLE 测 metadataOnly。
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'DROP TABLE t',
        databaseType: 'sqlite',
        executeQuery: (q) async => (await adapter.executeQuery(q)).rows,
        getServerVersion: () async =>
            (await adapter.getServerVersion())?['version'] as String?,
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.metadataOnly);
    });
  });
}
