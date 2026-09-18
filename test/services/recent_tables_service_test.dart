import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/recent_tables_service.dart';

void main() {
  group('RecentTablesService', () {
    late RecentTablesService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = RecentTablesService();
    });

    tearDown(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        await prefs.remove(key);
      }
    });

    // =====================================================================
    // 空状态测试
    // =====================================================================

    test('getRecentTables returns empty list when prefs empty', () async {
      final entries = await service.getRecentTables();
      expect(entries, isEmpty);
    });

    // =====================================================================
    // 记录与读取测试
    // =====================================================================

    test(
      'recordTableAccess persists entry and getRecentTables returns it',
      () async {
        await service.recordTableAccess(
          connectionId: 'conn_1',
          databaseName: 'db_a',
          tableName: 'users',
        );

        final entries = await service.getRecentTables();
        expect(entries.length, equals(1));
        expect(entries.first.connectionId, equals('conn_1'));
        expect(entries.first.databaseName, equals('db_a'));
        expect(entries.first.tableName, equals('users'));
      },
    );

    // =====================================================================
    // 去重测试
    // =====================================================================

    test('recordTableAccess dedupes same table and moves to front', () async {
      await service.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );

      await Future.delayed(const Duration(milliseconds: 10));

      await service.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'orders',
      );

      await Future.delayed(const Duration(milliseconds: 10));

      await service.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );

      final entries = await service.getRecentTables();
      expect(entries.length, equals(2));
      expect(entries.first.tableName, equals('users'));
      expect(entries.last.tableName, equals('orders'));
    });

    // =====================================================================
    // 上限测试
    // =====================================================================

    test('recordTableAccess trims to max 20 entries', () async {
      for (var i = 0; i < 25; i++) {
        await service.recordTableAccess(
          connectionId: 'conn_1',
          databaseName: 'db_a',
          tableName: 'table_$i',
        );
      }

      final entries = await service.getRecentTables();
      expect(entries.length, equals(20));
      // Most recent should be table_24
      expect(entries.first.tableName, equals('table_24'));
      // Oldest should be table_5 (0-4 were pushed out)
      expect(entries.last.tableName, equals('table_5'));
    });

    // =====================================================================
    // 多库隔离测试
    // =====================================================================

    test('entries from different connection/db are kept separately', () async {
      await service.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );
      await service.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_b',
        tableName: 'users',
      );
      await service.recordTableAccess(
        connectionId: 'conn_2',
        databaseName: 'db_a',
        tableName: 'users',
      );

      final entries = await service.getRecentTables();
      expect(entries.length, equals(3));
    });

    // =====================================================================
    // 清理测试
    // =====================================================================

    test('clear removes all entries', () async {
      await service.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );

      await service.clear();

      final entries = await service.getRecentTables();
      expect(entries, isEmpty);
    });

    // =====================================================================
    // RecentTableEntry 模型测试
    // =====================================================================

    group('RecentTableEntry', () {
      test('toJson / fromJson roundtrip', () {
        final entry = RecentTableEntry(
          connectionId: 'conn_1',
          databaseName: 'db_a',
          tableName: 'users',
          accessedAt: DateTime(2026, 6, 1, 12, 0, 0),
        );

        final json = entry.toJson();
        final restored = RecentTableEntry.fromJson(json);

        expect(restored.connectionId, equals(entry.connectionId));
        expect(restored.databaseName, equals(entry.databaseName));
        expect(restored.tableName, equals(entry.tableName));
        expect(restored.accessedAt, equals(entry.accessedAt));
      });

      test('key getter formats correctly', () {
        final entry = RecentTableEntry(
          connectionId: 'conn_1',
          databaseName: 'db_a',
          tableName: 'users',
          accessedAt: DateTime.now(),
        );

        expect(entry.key, equals('conn_1:db_a:users'));
      });

      test('fromJson parses valid JSON', () {
        final json = {
          'connectionId': 'conn_1',
          'databaseName': 'db_a',
          'tableName': 'users',
          'accessedAt': '2026-06-01T12:00:00.000',
        };

        final entry = RecentTableEntry.fromJson(json);
        expect(entry.connectionId, equals('conn_1'));
        expect(entry.accessedAt, equals(DateTime(2026, 6, 1, 12, 0, 0)));
      });
    });

    // =====================================================================
    // 异常恢复测试
    // =====================================================================

    test(
      'getRecentTables returns empty list when stored JSON is corrupted',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('recent_tables', 'not-valid-json');

        final entries = await service.getRecentTables();
        expect(entries, isEmpty);
      },
    );

    test(
      'getRecentTables returns empty list when stored JSON is not a list',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('recent_tables', jsonEncode({'foo': 'bar'}));

        final entries = await service.getRecentTables();
        expect(entries, isEmpty);
      },
    );
  });
}
