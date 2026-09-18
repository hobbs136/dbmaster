import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('ConnectionEvent hierarchy', () {
    test('ConnectionEstablished has correct fields', () {
      final server = DbServer(
        id: 'srv-1',
        name: 'Test Server',
        type: DatabaseType.mysql,
        host: 'localhost',
        port: 3306,
      );
      final event = ConnectionEstablished('conn-1', server);
      expect(event.connectionId, 'conn-1');
      expect(event.server.name, 'Test Server');
      expect(event is ConnectionEvent, true);
    });

    test('ConnectionDisconnected has correct fields', () {
      final event = ConnectionDisconnected('conn-1', null);
      expect(event.connectionId, 'conn-1');
      expect(event.server, isNull);
    });

    test('DatabaseSwitched has correct fields', () {
      final event = DatabaseSwitched('conn-1', 'test_db');
      expect(event.connectionId, 'conn-1');
      expect(event.databaseName, 'test_db');
    });

    test('ConnectionInfoLoaded has correct fields', () {
      final db = Database(
        name: 'test_db',
        tables: [],
        views: [],
        procedures: [],
        triggers: [],
        events: [],
      );
      final event = ConnectionInfoLoaded('conn-1', db);
      expect(event.connectionId, 'conn-1');
      expect(event.database.name, 'test_db');
    });

    test('TransactionRolledBack has correct fields', () {
      final event = TransactionRolledBack('conn-1', 'deadlock detected');
      expect(event.connectionId, 'conn-1');
      expect(event.reason, 'deadlock detected');
    });

    test('SessionRestored has correct fields', () {
      final event = SessionRestored(
        'conn-1',
        databaseName: 'test_db',
        wasInTransaction: true,
        restoredItems: ['temp_table_1'],
        failedItems: [],
      );
      expect(event.connectionId, 'conn-1');
      expect(event.databaseName, 'test_db');
      expect(event.wasInTransaction, true);
      expect(event.restoredItems, ['temp_table_1']);
      expect(event.failedItems, isEmpty);
    });

    test('pattern matching on sealed class', () {
      final event = DatabaseSwitched('conn-1', 'db');
      final name = switch (event) {
        DatabaseSwitched(databaseName: final db) => db,
        _ => 'unknown',
      };
      expect(name, 'db');
    });
  });
}
