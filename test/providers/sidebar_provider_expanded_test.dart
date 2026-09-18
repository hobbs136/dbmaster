import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/sidebar_provider.dart';

void main() {
  group('SidebarProvider 展开状态持久化', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('保存后加载展开状态一致', () async {
      final provider = SidebarProvider();

      await provider.saveExpandedState(
        items: {'conn_1', 'conn_1:mysql_server'},
        databases: {'conn_1:mydb', 'conn_1:testdb'},
        tables: {'conn_1:mydb:users'},
      );

      final state = await provider.loadExpandedState();
      expect(state.items, contains('conn_1'));
      expect(state.items, contains('conn_1:mysql_server'));
      expect(state.databases, contains('conn_1:mydb'));
      expect(state.databases, contains('conn_1:testdb'));
      expect(state.tables, contains('conn_1:mydb:users'));
    });

    test('空状态加载返回空集合', () async {
      final provider = SidebarProvider();
      await provider.saveExpandedState(items: {}, databases: {}, tables: {});

      final state = await provider.loadExpandedState();
      expect(state.items, isEmpty);
      expect(state.databases, isEmpty);
      expect(state.tables, isEmpty);
    });
  });

  group('SidebarProvider 选择状态', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('selectConnection 自动设置 expandedConnectionId', () {
      final provider = SidebarProvider();
      provider.selectConnection('conn_1');
      expect(provider.selectedConnectionId, 'conn_1');
      expect(provider.expandedConnectionId, 'conn_1');
    });

    test('clearSelection 清除所有选择', () {
      final provider = SidebarProvider();
      provider.selectConnection('conn_1');
      provider.selectDatabase('mydb');
      provider.clearSelection();
      expect(provider.selectedConnectionId, isNull);
      expect(provider.selectedDatabaseName, isNull);
      expect(provider.expandedConnectionId, isNull);
    });

    test('toggleFavoriteTable 切换收藏状态', () {
      final provider = SidebarProvider();
      expect(provider.isFavoriteTable('conn_1:mydb:users'), isFalse);
      provider.toggleFavoriteTable('conn_1:mydb:users');
      expect(provider.isFavoriteTable('conn_1:mydb:users'), isTrue);
      provider.toggleFavoriteTable('conn_1:mydb:users');
      expect(provider.isFavoriteTable('conn_1:mydb:users'), isFalse);
    });
  });
}
