import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/recent_tables_provider.dart';

void main() {
  group('RecentTablesProvider', () {
    late RecentTablesProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = RecentTablesProvider();
    });

    tearDown(() async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        await prefs.remove(key);
      }
    });

    // =====================================================================
    // 初始状态
    // =====================================================================

    test('initial state is empty and not loaded', () {
      expect(provider.entries, isEmpty);
      expect(provider.isLoaded, equals(false));
    });

    // =====================================================================
    // load() 测试
    // =====================================================================

    test('load reads persisted entries and sets isLoaded', () async {
      // Pre-populate via service
      final service = provider
          .entries; // just to access service indirectly, but we use prefs directly
      // Actually let's pre-populate through the provider itself
      await provider.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );

      // Create a fresh provider to test load()
      final freshProvider = RecentTablesProvider();
      expect(freshProvider.isLoaded, equals(false));

      await freshProvider.load();

      expect(freshProvider.isLoaded, equals(true));
      expect(freshProvider.entries.length, equals(1));
      expect(freshProvider.entries.first.tableName, equals('users'));
    });

    test('load notifies listeners', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.load();

      expect(notified, equals(true));
    });

    // =====================================================================
    // recordTableAccess 测试
    // =====================================================================

    test('recordTableAccess updates entries and notifies listeners', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );

      expect(notified, equals(true));
      expect(provider.entries.length, equals(1));
      expect(provider.entries.first.tableName, equals('users'));
    });

    test('recordTableAccess dedupes within provider state', () async {
      await provider.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );
      await provider.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'orders',
      );
      await provider.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );

      expect(provider.entries.length, equals(2));
      expect(provider.entries.first.tableName, equals('users'));
      expect(provider.entries.last.tableName, equals('orders'));
    });

    // =====================================================================
    // clear 测试
    // =====================================================================

    test('clear empties entries and notifies listeners', () async {
      await provider.recordTableAccess(
        connectionId: 'conn_1',
        databaseName: 'db_a',
        tableName: 'users',
      );

      var notified = false;
      provider.addListener(() => notified = true);

      await provider.clear();

      expect(notified, equals(true));
      expect(provider.entries, isEmpty);
    });

    test('clear on already empty provider still notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.clear();

      expect(notified, equals(true));
      expect(provider.entries, isEmpty);
    });

    // =====================================================================
    // entries 不可变性
    // =====================================================================

    test('entries returns unmodifiable list', () {
      expect(
        () => provider.entries.add(null as dynamic),
        throwsA(isA<Error>()),
      );
    });
  });
}
