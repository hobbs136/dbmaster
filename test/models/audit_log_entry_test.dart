import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/audit_log_entry.dart';

void main() {
  group('AuditLogEntry', () {
    final now = DateTime(2026, 6, 1, 12, 0);
    final entry = AuditLogEntry(
      id: 'log-1',
      timestamp: now,
      connectionId: 'conn-1',
      connectionName: 'My MySQL',
      databaseName: 'test_db',
      sql: 'SELECT * FROM users',
      executionTime: const Duration(milliseconds: 45),
      rowCount: 100,
      success: true,
      isWriteQuery: false,
    );

    test('toJson produces correct map', () {
      final json = entry.toJson();
      expect(json['id'], 'log-1');
      expect(json['timestamp'], now.toIso8601String());
      expect(json['connectionName'], 'My MySQL');
      expect(json['executionTimeMs'], 45);
      expect(json['rowCount'], 100);
      expect(json['success'], true);
      expect(json['isWriteQuery'], false);
    });

    test('fromJson creates correct object', () {
      final json = entry.toJson();
      final restored = AuditLogEntry.fromJson(json);
      expect(restored.id, 'log-1');
      expect(restored.timestamp, now);
      expect(restored.connectionId, 'conn-1');
      expect(restored.connectionName, 'My MySQL');
      expect(restored.databaseName, 'test_db');
      expect(restored.sql, 'SELECT * FROM users');
      expect(restored.executionTime.inMilliseconds, 45);
      expect(restored.rowCount, 100);
      expect(restored.success, true);
      expect(restored.isWriteQuery, false);
    });

    test('fromJson handles missing optional fields', () {
      final restored = AuditLogEntry.fromJson({
        'id': 'minimal',
        'timestamp': '2026-06-01T12:00:00.000',
        'connectionId': 'conn-min',
        'sql': 'SELECT 1',
        'executionTimeMs': 10,
        'success': true,
      });
      expect(restored.id, 'minimal');
      expect(restored.connectionName, isNull);
      expect(restored.databaseName, isNull);
      expect(restored.rowCount, isNull);
      expect(restored.errorMessage, isNull);
      expect(restored.isWriteQuery, false);
    });

    test('fromJson handles error log entry', () {
      final errorEntry = AuditLogEntry.fromJson({
        'id': 'err-1',
        'timestamp': '2026-06-01T12:00:00.000',
        'connectionId': 'conn-err',
        'sql': 'DROP TABLE users',
        'executionTimeMs': 0,
        'success': false,
        'errorMessage': 'Permission denied',
        'isWriteQuery': true,
      });
      expect(errorEntry.success, false);
      expect(errorEntry.errorMessage, 'Permission denied');
      expect(errorEntry.isWriteQuery, true);
    });

    test('copyWith preserves unchanged fields', () {
      final copied = entry.copyWith();
      expect(copied.id, entry.id);
      expect(copied.timestamp, entry.timestamp);
      expect(copied.sql, entry.sql);
    });

    test('copyWith updates specified fields', () {
      final copied = entry.copyWith(databaseName: 'new_db', rowCount: 200);
      expect(copied.databaseName, 'new_db');
      expect(copied.rowCount, 200);
      expect(copied.id, entry.id); // unchanged
      expect(copied.sql, entry.sql); // unchanged
    });
  });

  group('AgentGateDecision', () {
    test('wireName 值集合锁定（design §5.3，只加不改）', () {
      expect(AgentGateDecision.values.length, equals(6));
      expect(AgentGateDecision.allowed.wireName, equals('allowed'));
      expect(AgentGateDecision.confirmed.wireName, equals('confirmed'));
      expect(AgentGateDecision.allowedSession.wireName,
          equals('allowed_session'));
      expect(
          AgentGateDecision.rejectedByUser.wireName, equals('rejected_by_user'));
      expect(AgentGateDecision.blocked.wireName, equals('blocked'));
      expect(AgentGateDecision.na.wireName, equals('na'));
    });

    test('tryParse 全值往返', () {
      for (final decision in AgentGateDecision.values) {
        expect(AgentGateDecision.tryParse(decision.wireName), equals(decision));
      }
    });

    test('tryParse 未知 token / 非字符串 → null（前向容忍）', () {
      expect(AgentGateDecision.tryParse('made_up_value'), isNull);
      expect(AgentGateDecision.tryParse('Allowed'), isNull); // 大小写敏感
      expect(AgentGateDecision.tryParse(null), isNull);
      expect(AgentGateDecision.tryParse(3), isNull);
    });
  });

  group('AuditLogEntry agent 扩展字段', () {
    final now = DateTime(2026, 6, 1, 12, 0);
    final plainEntry = AuditLogEntry(
      id: 'plain-1',
      timestamp: now,
      connectionId: 'conn-1',
      sql: 'SELECT 1',
      executionTime: const Duration(milliseconds: 10),
      success: true,
    );
    final agentEntry = AuditLogEntry(
      id: 'agent-log-1',
      timestamp: now,
      connectionId: '',
      sql: "UPDATE users SET password = 'x' WHERE id = 1",
      executionTime: Duration.zero,
      success: false,
      errorMessage: 'WRITE_REJECTED_READONLY_CHANNEL',
      agentRunId: 'run_001',
      agentStep: 3,
      agentTool: 'execute_readonly_sql',
      gateLevel: 'l05',
      gateDecision: AgentGateDecision.rejectedByUser,
      planId: 'plan_20260923_01',
    );

    test('toJson 序列化 agent 字段（gateDecision 用锁定 wire token）', () {
      final json = agentEntry.toJson();
      expect(json['agentRunId'], equals('run_001'));
      expect(json['agentStep'], equals(3));
      expect(json['agentTool'], equals('execute_readonly_sql'));
      expect(json['gateLevel'], equals('l05'));
      expect(json['gateDecision'], equals('rejected_by_user'));
      expect(json['planId'], equals('plan_20260923_01'));
    });

    test('fromJson 全字段往返还原', () {
      final restored = AuditLogEntry.fromJson(agentEntry.toJson());
      expect(restored.agentRunId, equals('run_001'));
      expect(restored.agentStep, equals(3));
      expect(restored.agentTool, equals('execute_readonly_sql'));
      expect(restored.gateLevel, equals('l05'));
      expect(restored.gateDecision, equals(AgentGateDecision.rejectedByUser));
      expect(restored.planId, equals('plan_20260923_01'));
    });

    test('fromJson 旧档（无任何 agent 键）→ 六字段全 null 不炸', () {
      final restored = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 'legacy-1',
        'timestamp': '2026-06-01T12:00:00.000',
        'connectionId': 'conn-legacy',
        'sql': 'SELECT 1',
        'executionTimeMs': 10,
        'success': true,
        'connectionName': 'Old MySQL',
        'databaseName': 'old_db',
      });
      expect(restored.agentRunId, isNull);
      expect(restored.agentStep, isNull);
      expect(restored.agentTool, isNull);
      expect(restored.gateLevel, isNull);
      expect(restored.gateDecision, isNull);
      expect(restored.planId, isNull);
      // 既有字段照常读入（加法，不回退既有解析行为）
      expect(restored.id, equals('legacy-1'));
      expect(restored.connectionName, equals('Old MySQL'));
    });

    test('fromJson 未知 gateDecision token → null，其余 agent 字段不受影响', () {
      final restored = AuditLogEntry.fromJson(<String, dynamic>{
        'id': 'future-1',
        'timestamp': '2026-06-01T12:00:00.000',
        'connectionId': 'conn-future',
        'sql': 'SELECT 1',
        'executionTimeMs': 10,
        'success': true,
        'agentRunId': 'run_x',
        'gateLevel': 'l9',
        'gateDecision': 'future_decision_kind',
      });
      expect(restored.gateDecision, isNull);
      expect(restored.agentRunId, equals('run_x'));
      expect(restored.gateLevel, equals('l9')); // 档 token 未知也宽容透传
    });

    test('非 agent 条目 toJson 仍含新键且值为 null（键集形状稳定）', () {
      final json = plainEntry.toJson();
      expect(json.containsKey('agentRunId'), isTrue);
      expect(json['agentRunId'], isNull);
      expect(json['agentStep'], isNull);
      expect(json['agentTool'], isNull);
      expect(json['gateLevel'], isNull);
      expect(json['gateDecision'], isNull);
      expect(json['planId'], isNull);
    });

    test('copyWith 保留与更新 agent 字段', () {
      final copied = agentEntry.copyWith(
        agentStep: 4,
        gateDecision: AgentGateDecision.allowedSession,
      );
      expect(copied.agentStep, equals(4));
      expect(copied.gateDecision, equals(AgentGateDecision.allowedSession));
      // 未指定字段原样保留
      expect(copied.agentRunId, equals('run_001'));
      expect(copied.agentTool, equals('execute_readonly_sql'));
      expect(copied.gateLevel, equals('l05'));
      expect(copied.planId, equals('plan_20260923_01'));
      expect(copied.success, isFalse);
    });
  });
}
