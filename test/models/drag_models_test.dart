import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/drag_models.dart';

void main() {
  group('TableDragData', () {
    test('selectStatement generates correct SQL', () {
      final drag = TableDragData(
        tableName: 'users',
        databaseName: 'test_db',
        connectionId: 'conn-1',
      );
      expect(drag.selectStatement, 'SELECT * FROM "users" LIMIT 100');
    });

    test('fields are correctly set', () {
      final drag = TableDragData(
        tableName: 'orders',
        databaseName: 'production',
        connectionId: 'conn-prod',
      );
      expect(drag.tableName, 'orders');
      expect(drag.databaseName, 'production');
      expect(drag.connectionId, 'conn-prod');
    });

    test('selectStatement wraps table name in double quotes', () {
      final drag = TableDragData(
        tableName: 'my-special-table',
        databaseName: 'db',
        connectionId: 'c',
      );
      expect(
        drag.selectStatement,
        'SELECT * FROM "my-special-table" LIMIT 100',
      );
    });
  });
}
