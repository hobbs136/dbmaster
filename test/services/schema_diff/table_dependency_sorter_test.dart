import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/schema_diff/table_dependency_sorter.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('TableDependencySorter', () {
    group('sortByCreateOrder', () {
      test('无依赖的表应按原始顺序返回', () {
        final sqls = {
          'users': 'CREATE TABLE users (id INT PRIMARY KEY)',
          'orders': 'CREATE TABLE orders (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(result, containsAll(['users', 'orders']));
      });

      test('应将被引用表排在引用表之前', () {
        final sqls = {
          'orders':
              'CREATE TABLE orders (user_id INT, FOREIGN KEY (user_id) REFERENCES `users` (id))',
          'users': 'CREATE TABLE users (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(result.indexOf('users'), lessThan(result.indexOf('orders')));
      });

      test('应处理多级依赖链', () {
        final sqls = {
          'items':
              'CREATE TABLE items (order_id INT, FOREIGN KEY (order_id) REFERENCES `orders` (id))',
          'orders':
              'CREATE TABLE orders (user_id INT, FOREIGN KEY (user_id) REFERENCES `users` (id))',
          'users': 'CREATE TABLE users (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(result.indexOf('users'), lessThan(result.indexOf('orders')));
        expect(result.indexOf('orders'), lessThan(result.indexOf('items')));
      });

      test('应处理空 map', () {
        final result = TableDependencySorter.sortByCreateOrder({});
        expect(result, isEmpty);
      });

      test('应处理双引号引用的 REFERENCES', () {
        final sqls = {
          'orders':
              'CREATE TABLE orders (user_id INT, FOREIGN KEY (user_id) REFERENCES "users" (id))',
          'users': 'CREATE TABLE users (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(result.indexOf('users'), lessThan(result.indexOf('orders')));
      });

      test('应处理 schema 前缀的 REFERENCES', () {
        final sqls = {
          'orders':
              'CREATE TABLE orders (user_id INT, FOREIGN KEY (user_id) REFERENCES `mydb`.`users` (id))',
          'users': 'CREATE TABLE users (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(result.indexOf('users'), lessThan(result.indexOf('orders')));
      });

      // 多 schema——表名为限定 key（schema.table），DDL 的裸 REFERENCES
      // 应解析回同 schema 的限定 key。
      test('限定名表 + 同 schema 裸 REFERENCES 应正确排序', () {
        final sqls = {
          'app.orders':
              'CREATE TABLE "app"."orders" (user_id INT, FOREIGN KEY (user_id) REFERENCES "users" (id))',
          'app.users': 'CREATE TABLE "app"."users" (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(
          result.indexOf('app.users'),
          lessThan(result.indexOf('app.orders')),
        );
      });

      test('限定名 REFERENCES（schema.table）应正确排序', () {
        final sqls = {
          'app.orders':
              'CREATE TABLE "app"."orders" (user_id INT, FOREIGN KEY (user_id) REFERENCES "app"."users" (id))',
          'app.users': 'CREATE TABLE "app"."users" (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(
          result.indexOf('app.users'),
          lessThan(result.indexOf('app.orders')),
        );
      });

      test('不应将自引用视为依赖', () {
        final sqls = {
          'categories':
              'CREATE TABLE categories (parent_id INT, FOREIGN KEY (parent_id) REFERENCES `categories` (id))',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(result, ['categories']);
      });

      test('应处理多个表引用同一个表', () {
        final sqls = {
          'orders':
              'CREATE TABLE orders (user_id INT, FOREIGN KEY (user_id) REFERENCES `users` (id))',
          'reviews':
              'CREATE TABLE reviews (user_id INT, FOREIGN KEY (user_id) REFERENCES `users` (id))',
          'users': 'CREATE TABLE users (id INT PRIMARY KEY)',
        };
        final result = TableDependencySorter.sortByCreateOrder(sqls);
        expect(result.indexOf('users'), lessThan(result.indexOf('orders')));
        expect(result.indexOf('users'), lessThan(result.indexOf('reviews')));
      });
    });

    group('sortByDropOrder', () {
      test('DROP 顺序应是 CREATE 顺序的反转', () {
        final sqls = {
          'items':
              'CREATE TABLE items (order_id INT, FOREIGN KEY (order_id) REFERENCES `orders` (id))',
          'orders':
              'CREATE TABLE orders (user_id INT, FOREIGN KEY (user_id) REFERENCES `users` (id))',
          'users': 'CREATE TABLE users (id INT PRIMARY KEY)',
        };
        final createOrder = TableDependencySorter.sortByCreateOrder(sqls);
        final dropOrder = TableDependencySorter.sortByDropOrder(sqls);
        expect(dropOrder, createOrder.reversed.toList());
      });
    });

    group('sortByCreateOrderFromFKs', () {
      test('应使用预解析的外键信息排序', () {
        final tableNames = ['orders', 'users', 'items'];
        final foreignKeysMap = {
          'users': <ForeignKey>[],
          'orders': [
            ForeignKey(
              name: 'fk_user',
              table: 'orders',
              column: 'user_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ],
          'items': [
            ForeignKey(
              name: 'fk_order',
              table: 'items',
              column: 'order_id',
              referencedTable: 'orders',
              referencedColumn: 'id',
            ),
          ],
        };
        final result = TableDependencySorter.sortByCreateOrderFromFKs(
          tableNames,
          foreignKeysMap,
        );
        expect(result.indexOf('users'), lessThan(result.indexOf('orders')));
        expect(result.indexOf('orders'), lessThan(result.indexOf('items')));
      });

      test('无 FK 的表应保留在结果中', () {
        final tableNames = ['a', 'b', 'c'];
        final foreignKeysMap = <String, List<ForeignKey>>{};
        final result = TableDependencySorter.sortByCreateOrderFromFKs(
          tableNames,
          foreignKeysMap,
        );
        expect(result, containsAll(['a', 'b', 'c']));
      });

      test('应忽略指向表列表外的外键', () {
        final tableNames = ['orders'];
        final foreignKeysMap = {
          'orders': [
            ForeignKey(
              name: 'fk_user',
              table: 'orders',
              column: 'user_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ],
        };
        final result = TableDependencySorter.sortByCreateOrderFromFKs(
          tableNames,
          foreignKeysMap,
        );
        expect(result, ['orders']);
      });
    });
  });
}
