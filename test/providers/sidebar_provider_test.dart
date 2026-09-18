import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/providers/sidebar_provider.dart';

void main() {
  group('SidebarProvider', () {
    late SidebarProvider provider;

    setUp(() {
      provider = SidebarProvider();
    });

    group('初始状态', () {
      test('selectedConnectionId 应为 null', () {
        expect(provider.selectedConnectionId, isNull);
      });

      test('selectedDatabaseName 应为 null', () {
        expect(provider.selectedDatabaseName, isNull);
      });

      test('expandedConnectionId 应为 null', () {
        expect(provider.expandedConnectionId, isNull);
      });

      test('favoriteTables 应为空', () {
        expect(provider.favoriteTables, isEmpty);
      });
    });

    group('selectConnection', () {
      test('应更新 selectedConnectionId', () {
        provider.selectConnection('conn_1');
        expect(provider.selectedConnectionId, 'conn_1');
      });

      test('应同时更新 expandedConnectionId', () {
        provider.selectConnection('conn_1');
        expect(provider.expandedConnectionId, 'conn_1');
      });

      test('重复选择同一连接不应触发 notifyListeners', () {
        provider.selectConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.selectConnection('conn_1');
        expect(notified, isFalse);
      });

      test('选择不同连接应触发 notifyListeners', () {
        provider.selectConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.selectConnection('conn_2');
        expect(notified, isTrue);
      });

      test('应支持设为 null', () {
        provider.selectConnection('conn_1');
        provider.selectConnection(null);
        expect(provider.selectedConnectionId, isNull);
      });
    });

    group('selectDatabase', () {
      test('应更新 selectedDatabaseName', () {
        provider.selectDatabase('mydb');
        expect(provider.selectedDatabaseName, 'mydb');
      });

      test('重复选择同一数据库不应触发 notifyListeners', () {
        provider.selectDatabase('mydb');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.selectDatabase('mydb');
        expect(notified, isFalse);
      });

      test('应支持设为 null', () {
        provider.selectDatabase('mydb');
        provider.selectDatabase(null);
        expect(provider.selectedDatabaseName, isNull);
      });
    });

    group('expandConnection', () {
      test('应更新 expandedConnectionId', () {
        provider.expandConnection('conn_1');
        expect(provider.expandedConnectionId, 'conn_1');
      });

      test('重复展开同一连接不应触发 notifyListeners', () {
        provider.expandConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.expandConnection('conn_1');
        expect(notified, isFalse);
      });
    });

    group('toggleFavoriteTable', () {
      test('应添加收藏', () {
        provider.toggleFavoriteTable('conn_1.mydb.users');
        expect(provider.isFavoriteTable('conn_1.mydb.users'), isTrue);
      });

      test('再次切换应取消收藏', () {
        provider.toggleFavoriteTable('conn_1.mydb.users');
        provider.toggleFavoriteTable('conn_1.mydb.users');
        expect(provider.isFavoriteTable('conn_1.mydb.users'), isFalse);
      });

      test('应触发 notifyListeners', () {
        var notified = false;
        provider.addListener(() => notified = true);
        provider.toggleFavoriteTable('conn_1.mydb.users');
        expect(notified, isTrue);
      });

      test('多个收藏应独立管理', () {
        provider.toggleFavoriteTable('table_a');
        provider.toggleFavoriteTable('table_b');
        expect(provider.isFavoriteTable('table_a'), isTrue);
        expect(provider.isFavoriteTable('table_b'), isTrue);
        expect(provider.favoriteTables.length, 2);
      });
    });

    group('clearSelection', () {
      test('应重置所有选择状态', () {
        provider.selectConnection('conn_1');
        provider.selectDatabase('mydb');
        provider.expandConnection('conn_2');

        provider.clearSelection();

        expect(provider.selectedConnectionId, isNull);
        expect(provider.selectedDatabaseName, isNull);
        expect(provider.expandedConnectionId, isNull);
      });

      test('不应清除收藏', () {
        provider.toggleFavoriteTable('table_a');
        provider.clearSelection();
        expect(provider.isFavoriteTable('table_a'), isTrue);
      });

      test('应触发 notifyListeners', () {
        provider.selectConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.clearSelection();
        expect(notified, isTrue);
      });
    });

    group('favoriteTables 不可变性', () {
      test('返回的集合不应可被外部修改', () {
        provider.toggleFavoriteTable('table_a');
        final favorites = provider.favoriteTables;
        // 尝试修改返回的集合不应影响内部状态
        // 但由于是 unmodifiable，尝试添加会抛出异常
        expect(() => favorites.add('table_b'), throwsUnsupportedError);
      });
    });
  });
}
