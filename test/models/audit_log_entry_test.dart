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
}
