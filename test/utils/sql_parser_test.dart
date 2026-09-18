import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/sql_parser.dart';

void main() {
  group('SqlParser.parseForeignKeys', () {
    test('应解析基本外键约束', () {
      const sql = '''
CREATE TABLE orders (
  id INT PRIMARY KEY,
  user_id INT,
  CONSTRAINT `fk_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
);
''';
      final fks = SqlParser.parseForeignKeys(sql, 'orders');
      expect(fks.length, 1);
      expect(fks[0].name, 'fk_user');
      expect(fks[0].table, 'orders');
      expect(fks[0].column, 'user_id');
      expect(fks[0].referencedTable, 'users');
      expect(fks[0].referencedColumn, 'id');
      expect(fks[0].onDelete, isNull);
      expect(fks[0].onUpdate, isNull);
    });

    test('应解析带 ON DELETE 和 ON UPDATE 的外键', () {
      const sql = '''
CREATE TABLE orders (
  id INT PRIMARY KEY,
  user_id INT,
  CONSTRAINT `fk_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE SET NULL
);
''';
      final fks = SqlParser.parseForeignKeys(sql, 'orders');
      expect(fks.length, 1);
      expect(fks[0].onDelete?.toUpperCase(), 'CASCADE');
      expect(fks[0].onUpdate, 'SET NULL');
    });

    test('应解析多个外键', () {
      const sql = '''
CREATE TABLE order_items (
  id INT PRIMARY KEY,
  order_id INT,
  product_id INT,
  CONSTRAINT `fk_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`),
  CONSTRAINT `fk_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`)
);
''';
      final fks = SqlParser.parseForeignKeys(sql, 'order_items');
      expect(fks.length, 2);
      expect(fks[0].name, 'fk_order');
      expect(fks[1].name, 'fk_product');
    });

    test('无外键时应返回空列表', () {
      const sql = 'CREATE TABLE simple (id INT PRIMARY KEY);';
      final fks = SqlParser.parseForeignKeys(sql, 'simple');
      expect(fks, isEmpty);
    });

    test('应处理大小写不敏感', () {
      const sql = '''
CREATE TABLE orders (
  CONSTRAINT `fk_test` foreign key (`col`) references `tbl` (`id`) on delete cascade
);
''';
      final fks = SqlParser.parseForeignKeys(sql, 'orders');
      expect(fks.length, 1);
      expect(fks[0].name, 'fk_test');
      expect(fks[0].onDelete?.toUpperCase(), 'CASCADE');
    });

    test('空 SQL 应返回空列表', () {
      final fks = SqlParser.parseForeignKeys('', 'table');
      expect(fks, isEmpty);
    });
  });
}
