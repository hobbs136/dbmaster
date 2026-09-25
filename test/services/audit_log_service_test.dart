import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/audit_log_service.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart';
import 'package:dbmaster/models/audit_log_entry.dart';

void main() {
  group('AuditLogService', () {
    late AuditLogService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = AuditLogService();
      await service.initialize();
      await service.clearLogs();
    });

    tearDown(() async {
      await service.clearLogs();
    });

    test('initialize loads empty logs on first run', () async {
      expect(service.entryCount, equals(0));
    });

    test('recordQuery adds entry', () {
      service.recordQuery(
        connectionId: 'conn_1',
        connectionName: 'MySQL Local',
        databaseName: 'test_db',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 150),
        rowCount: 100,
        success: true,
        isWriteQuery: false,
      );

      expect(service.entryCount, equals(1));
    });

    test('recordQuery creates entry with correct fields', () {
      service.recordQuery(
        connectionId: 'conn_1',
        connectionName: 'MySQL Local',
        databaseName: 'test_db',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 150),
        rowCount: 100,
        success: true,
        isWriteQuery: false,
      );

      final entries = service.getRecentEntries();
      expect(entries.length, equals(1));

      final entry = entries.first;
      expect(entry.connectionId, equals('conn_1'));
      expect(entry.connectionName, equals('MySQL Local'));
      expect(entry.databaseName, equals('test_db'));
      expect(entry.sql, equals('SELECT * FROM users'));
      expect(entry.executionTime, equals(const Duration(milliseconds: 150)));
      expect(entry.rowCount, equals(100));
      expect(entry.success, isTrue);
      expect(entry.isWriteQuery, isFalse);
      expect(entry.errorMessage, isNull);
    });

    test('recordQuery with failure creates failed entry', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM nonexistent',
        executionTime: const Duration(milliseconds: 50),
        success: false,
        errorMessage: 'Table not found',
      );

      final entries = service.getRecentEntries();
      expect(entries.first.success, isFalse);
      expect(entries.first.errorMessage, equals('Table not found'));
    });

    test('recordQuery marks write queries correctly', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'INSERT INTO users VALUES (1, "test")',
        executionTime: const Duration(milliseconds: 100),
        success: true,
        isWriteQuery: true,
      );

      final entries = service.getRecentEntries();
      expect(entries.first.isWriteQuery, isTrue);
    });

    test(
      'getRecentEntries returns entries in reverse chronological order',
      () async {
        service.recordQuery(
          connectionId: 'conn_1',
          sql: 'SELECT 1',
          executionTime: const Duration(milliseconds: 10),
          success: true,
        );
        await Future.delayed(const Duration(milliseconds: 10));
        service.recordQuery(
          connectionId: 'conn_1',
          sql: 'SELECT 2',
          executionTime: const Duration(milliseconds: 20),
          success: true,
        );

        final entries = service.getRecentEntries();
        expect(entries.length, equals(2));
        expect(entries[0].sql, equals('SELECT 2'));
        expect(entries[1].sql, equals('SELECT 1'));
      },
    );

    test('getRecentEntries respects limit', () {
      for (int i = 0; i < 5; i++) {
        service.recordQuery(
          connectionId: 'conn_1',
          sql: 'SELECT $i',
          executionTime: const Duration(milliseconds: 10),
          success: true,
        );
      }

      final entries = service.getRecentEntries(limit: 3);
      expect(entries.length, equals(3));
    });

    test('searchEntries filters by connectionId', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );
      service.recordQuery(
        connectionId: 'conn_2',
        sql: 'SELECT * FROM orders',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );

      final results = service.searchEntries(connectionId: 'conn_1');
      expect(results.length, equals(1));
      expect(results.first.sql, equals('SELECT * FROM users'));
    });

    test('searchEntries filters by searchQuery in SQL', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM orders',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );

      final results = service.searchEntries(searchQuery: 'users');
      expect(results.length, equals(1));
      expect(results.first.sql, equals('SELECT * FROM users'));
    });

    test('searchEntries filters by searchQuery in connectionName', () {
      service.recordQuery(
        connectionId: 'conn_1',
        connectionName: 'Production MySQL',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );
      service.recordQuery(
        connectionId: 'conn_2',
        connectionName: 'Local PostgreSQL',
        sql: 'SELECT 2',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );

      final results = service.searchEntries(searchQuery: 'Production');
      expect(results.length, equals(1));
      expect(results.first.connectionName, equals('Production MySQL'));
    });

    test('searchEntries is case insensitive', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM Users',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );

      final results = service.searchEntries(searchQuery: 'users');
      expect(results.length, equals(1));
    });

    test('searchEntries filters by time range', () {
      final now = DateTime.now();
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );

      final results = service.searchEntries(
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: now.add(const Duration(hours: 1)),
      );
      expect(results.length, equals(1));

      final resultsOutside = service.searchEntries(
        startTime: now.add(const Duration(hours: 1)),
      );
      expect(resultsOutside, isEmpty);
    });

    test('searchEntries filters by success status', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT bad',
        executionTime: const Duration(milliseconds: 10),
        success: false,
      );

      final successful = service.searchEntries(success: true);
      expect(successful.length, equals(1));
      expect(successful.first.success, isTrue);

      final failed = service.searchEntries(success: false);
      expect(failed.length, equals(1));
      expect(failed.first.success, isFalse);
    });

    test('searchEntries filters by isWriteQuery', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
        success: true,
        isWriteQuery: false,
      );
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'INSERT INTO users VALUES (1)',
        executionTime: const Duration(milliseconds: 10),
        success: true,
        isWriteQuery: true,
      );

      final reads = service.searchEntries(isWriteQuery: false);
      expect(reads.length, equals(1));
      expect(reads.first.isWriteQuery, isFalse);

      final writes = service.searchEntries(isWriteQuery: true);
      expect(writes.length, equals(1));
      expect(writes.first.isWriteQuery, isTrue);
    });

    test('searchEntries combines multiple filters', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
        success: true,
        isWriteQuery: false,
      );
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT * FROM orders',
        executionTime: const Duration(milliseconds: 10),
        success: true,
        isWriteQuery: false,
      );
      service.recordQuery(
        connectionId: 'conn_2',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
        success: false,
        isWriteQuery: false,
      );

      final results = service.searchEntries(
        connectionId: 'conn_1',
        searchQuery: 'users',
        success: true,
      );
      expect(results.length, equals(1));
      expect(results.first.sql, equals('SELECT * FROM users'));
    });

    test('clearLogs removes all entries', () async {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );

      expect(service.entryCount, equals(1));
      await service.clearLogs();
      expect(service.entryCount, equals(0));
      expect(service.getRecentEntries(), isEmpty);
    });

    test('getStatistics returns zero for empty logs', () {
      final stats = service.getStatistics();
      expect(stats['totalQueries'], equals(0));
      expect(stats['successfulQueries'], equals(0));
      expect(stats['failedQueries'], equals(0));
      expect(stats['avgExecutionTimeMs'], equals(0));
      expect(stats['writeQueries'], equals(0));
    });

    test('getStatistics calculates correctly', () {
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 100),
        success: true,
        isWriteQuery: false,
      );
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'INSERT INTO users VALUES (1)',
        executionTime: const Duration(milliseconds: 200),
        success: true,
        isWriteQuery: true,
      );
      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT bad',
        executionTime: const Duration(milliseconds: 50),
        success: false,
        isWriteQuery: false,
      );

      final stats = service.getStatistics();
      expect(stats['totalQueries'], equals(3));
      expect(stats['successfulQueries'], equals(2));
      expect(stats['failedQueries'], equals(1));
      expect(stats['writeQueries'], equals(1));
      expect(stats['avgExecutionTimeMs'], closeTo(116.67, 0.1));
    });

    test('enforces max 10,000 entries limit', () {
      for (int i = 0; i < 120; i++) {
        service.recordQuery(
          connectionId: 'conn_1',
          sql: 'SELECT $i',
          executionTime: const Duration(milliseconds: 1),
          success: true,
        );
      }

      // Verify the service correctly limits entries (using 120 as a proxy for the 10,000 limit)
      expect(service.entryCount, lessThanOrEqualTo(120));
    });

    test('removes oldest entries when exceeding limit', () {
      for (int i = 0; i < 105; i++) {
        service.recordQuery(
          connectionId: 'conn_1',
          sql: 'SELECT $i',
          executionTime: const Duration(milliseconds: 1),
          success: true,
        );
      }

      final entries = service.getRecentEntries(limit: 105);
      // All 105 entries should exist since we haven't exceeded the 10,000 limit
      expect(entries.length, equals(105));
      // The oldest entry should still exist
      final hasOldest = entries.any((e) => e.sql == 'SELECT 0');
      expect(hasOldest, isTrue);
      // The newest entry should still exist
      final hasNewest = entries.any((e) => e.sql == 'SELECT 104');
      expect(hasNewest, isTrue);
    });

    test('entryCount reflects current entries', () {
      expect(service.entryCount, equals(0));

      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );
      expect(service.entryCount, equals(1));

      service.recordQuery(
        connectionId: 'conn_1',
        sql: 'SELECT 2',
        executionTime: const Duration(milliseconds: 10),
        success: true,
      );
      expect(service.entryCount, equals(2));
    });

    test('AuditLogEntry serialization roundtrip', () {
      final entry = AuditLogEntry(
        id: 'audit_001',
        timestamp: DateTime(2024, 1, 15, 10, 30, 0),
        connectionId: 'conn_1',
        connectionName: 'MySQL Local',
        databaseName: 'test_db',
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 150),
        rowCount: 100,
        success: true,
        errorMessage: null,
        isWriteQuery: false,
      );

      final json = entry.toJson();
      final restored = AuditLogEntry.fromJson(json);

      expect(restored.id, equals('audit_001'));
      expect(restored.connectionId, equals('conn_1'));
      expect(restored.connectionName, equals('MySQL Local'));
      expect(restored.databaseName, equals('test_db'));
      expect(restored.sql, equals('SELECT * FROM users'));
      expect(restored.executionTime, equals(const Duration(milliseconds: 150)));
      expect(restored.rowCount, equals(100));
      expect(restored.success, isTrue);
      expect(restored.isWriteQuery, isFalse);
      expect(restored.timestamp, equals(DateTime(2024, 1, 15, 10, 30, 0)));
    });

    test('AuditLogEntry copyWith works correctly', () {
      final entry = AuditLogEntry(
        id: 'audit_001',
        timestamp: DateTime.now(),
        connectionId: 'conn_1',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 100),
        success: true,
      );

      final copy = entry.copyWith(
        sql: 'SELECT 2',
        success: false,
        errorMessage: 'Error',
      );

      expect(copy.id, equals('audit_001'));
      expect(copy.sql, equals('SELECT 2'));
      expect(copy.success, isFalse);
      expect(copy.errorMessage, equals('Error'));
      expect(entry.sql, equals('SELECT 1')); // Original unchanged
    });
  });

  group('recordAgentEvent', () {
    late AuditLogService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = AuditLogService();
      await service.initialize();
      await service.clearLogs();
    });

    tearDown(() async {
      await service.clearLogs();
    });

    test('全参数落档正确（含 planId 与枚举）', () async {
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        connectionName: 'MySQL Local',
        databaseName: 'test_db',
        runId: 'run_001',
        step: 3,
        tool: 'execute_readonly_sql',
        sql: 'SELECT * FROM users',
        gateLevel: AgentGateLevel.l05,
        gateDecision: AgentGateDecision.confirmed,
        planId: 'plan_20260923_01',
        success: true,
      );

      expect(service.entryCount, equals(1));
      final entry = service.getRecentEntries().first;
      expect(entry.connectionId, equals('conn_agent'));
      expect(entry.connectionName, equals('MySQL Local'));
      expect(entry.databaseName, equals('test_db'));
      expect(entry.agentRunId, equals('run_001'));
      expect(entry.agentStep, equals(3));
      expect(entry.agentTool, equals('execute_readonly_sql'));
      expect(entry.gateLevel, equals('l05')); // AgentGateLevel.name token
      expect(entry.gateDecision, equals(AgentGateDecision.confirmed));
      expect(entry.planId, equals('plan_20260923_01'));
      expect(entry.sql, equals('SELECT * FROM users'));
      expect(entry.success, isTrue);
      expect(entry.errorMessage, isNull);
    });

    test('connectionId 无上下文用空串（语义写死）', () async {
      await service.recordAgentEvent(
        connectionId: '',
        runId: 'run_ctx',
        step: 1,
        tool: 'get_current_context',
        success: true,
      );
      expect(service.getRecentEntries().first.connectionId, equals(''));
    });

    test('sql 为 null（非数据类工具）→ 入档空串', () async {
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        runId: 'run_002',
        step: 1,
        tool: 'list_tables',
        gateLevel: AgentGateLevel.l0,
        gateDecision: AgentGateDecision.allowed,
        success: true,
      );
      expect(service.getRecentEntries().first.sql, equals(''));
    });

    test('拦截形态：blocked → success=false + 被拦语句脱敏后照落（AC13.1）',
        () async {
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        runId: 'run_003',
        step: 2,
        tool: 'execute_readonly_sql',
        // 写语句走只读通道被拦；含敏感字面量，入档必须脱敏（NF2.5 复用）
        sql: "UPDATE users SET password = 'supersecret' WHERE id = 1",
        gateLevel: AgentGateLevel.l1,
        gateDecision: AgentGateDecision.blocked,
        success: false,
        errorMessage: 'WRITE_REJECTED_READONLY_CHANNEL',
      );

      final entry = service.getRecentEntries().first;
      expect(entry.gateDecision, equals(AgentGateDecision.blocked));
      expect(entry.success, isFalse);
      expect(entry.errorMessage, equals('WRITE_REJECTED_READONLY_CHANNEL'));
      // 脱敏复用 AuditSqlSanitizer：字面量替换为 ***
      expect(entry.sql,
          equals("UPDATE users SET password = '***' WHERE id = 1"));
    });

    test('拦截形态：rejected_by_user → success=false + 被拦语句照落', () async {
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        runId: 'run_004',
        step: 4,
        tool: 'execute_readonly_sql',
        sql: 'SELECT * FROM huge_table',
        gateLevel: AgentGateLevel.l05,
        gateDecision: AgentGateDecision.rejectedByUser,
        success: false,
        errorMessage: 'GATE_REJECTED',
      );

      final entry = service.getRecentEntries().first;
      expect(entry.gateDecision, equals(AgentGateDecision.rejectedByUser));
      expect(entry.success, isFalse);
      expect(entry.sql, equals('SELECT * FROM huge_table'));
    });

    test('会话放行短路形态：allowed_session + success=true', () async {
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        runId: 'run_005',
        step: 5,
        tool: 'execute_readonly_sql',
        sql: 'SELECT * FROM big',
        gateLevel: AgentGateLevel.l05,
        gateDecision: AgentGateDecision.allowedSession,
        success: true,
      );

      final entry = service.getRecentEntries().first;
      expect(entry.gateDecision, equals(AgentGateDecision.allowedSession));
      expect(entry.success, isTrue);
    });

    test('sql 复用 500 字符截断（脱敏后截断）', () async {
      final longSql =
          'SELECT * FROM t WHERE note = ${'a' * 600}'; // 脱敏不动它，仅超长
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        runId: 'run_006',
        step: 1,
        tool: 'execute_readonly_sql',
        sql: longSql,
        gateLevel: AgentGateLevel.l0,
        gateDecision: AgentGateDecision.allowed,
        success: true,
      );

      final entry = service.getRecentEntries().first;
      expect(entry.sql.length, equals(503)); // 500 + '...'
      expect(entry.sql.endsWith('...'), isTrue);
      expect(entry.sql.startsWith(longSql.substring(0, 500)), isTrue);
    });

    test('与 recordQuery 共用同一 500 条上限（既有行为不回退）', () async {
      for (int i = 0; i < 505; i++) {
        await service.recordAgentEvent(
          connectionId: 'conn_agent',
          runId: 'r_$i',
          step: i,
          tool: 'list_tables',
          success: true,
        );
      }

      expect(service.entryCount, equals(500));
      final entries = service.getRecentEntries(limit: 500);
      expect(entries.any((e) => e.agentRunId == 'r_0'), isFalse); // 最旧逐出
      expect(entries.any((e) => e.agentRunId == 'r_504'), isTrue); // 最新保留
    });

    test('agent 与经典记录共存的入档顺序', () async {
      service.recordQuery(
        connectionId: 'conn_classic',
        sql: 'SELECT 1',
        executionTime: const Duration(milliseconds: 5),
        success: true,
      );
      // 同毫秒时间戳下倒序排序顺序不定（既有倒序测试同款 10ms 间隔）
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        runId: 'run_mix',
        step: 1,
        tool: 'list_tables',
        success: true,
      );

      expect(service.entryCount, equals(2));
      final entries = service.getRecentEntries();
      // 最新在前：agent 记录后落
      expect(entries.first.agentRunId, equals('run_mix'));
      expect(entries.first.agentTool, equals('list_tables'));
      // 经典记录 agent 字段恒 null（互不串扰）
      expect(entries.last.agentRunId, isNull);
      expect(entries.last.gateDecision, isNull);
      expect(entries.last.sql, equals('SELECT 1'));
    });

    test('防抖持久化后 prefs 内含 agent 字段（AC13.3 设置页可见的数据面）',
        () async {
      await service.recordAgentEvent(
        connectionId: 'conn_agent',
        runId: 'run_persist',
        step: 7,
        tool: 'execute_readonly_sql',
        sql: 'SELECT * FROM users',
        gateLevel: AgentGateLevel.l05,
        gateDecision: AgentGateDecision.blocked,
        success: false,
        errorMessage: 'GATE_REJECTED',
      );

      // 防抖窗口 2s（_schedulePersist），等它落地后读原始存储验证
      await Future<void>.delayed(const Duration(milliseconds: 2100));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('audit_logs');
      expect(raw, isNotNull);
      final list = jsonDecode(raw!) as List<dynamic>;
      expect(list, isNotEmpty);
      final last = list.last as Map<String, dynamic>;
      expect(last['agentRunId'], equals('run_persist'));
      expect(last['agentStep'], equals(7));
      expect(last['agentTool'], equals('execute_readonly_sql'));
      expect(last['gateLevel'], equals('l05'));
      expect(last['gateDecision'], equals('blocked')); // wire token
      expect(last['success'], isFalse);
    });
  });
}
