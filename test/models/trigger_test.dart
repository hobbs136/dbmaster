import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/trigger.dart';

void main() {
  group('TriggerTiming', () {
    test('has 2 values', () {
      expect(TriggerTiming.values.length, 2);
    });

    test('value returns correct string', () {
      expect(TriggerTiming.before.value, 'BEFORE');
      expect(TriggerTiming.after.value, 'AFTER');
    });

    test('fromString parses correctly', () {
      expect(TriggerTimingExtension.fromString('BEFORE'), TriggerTiming.before);
      expect(TriggerTimingExtension.fromString('before'), TriggerTiming.before);
      expect(TriggerTimingExtension.fromString('AFTER'), TriggerTiming.after);
      expect(
        TriggerTimingExtension.fromString('unknown'),
        TriggerTiming.after,
      ); // default
    });
  });

  group('TriggerEvent', () {
    test('has 3 values', () {
      expect(TriggerEvent.values.length, 3);
    });

    test('value returns correct string', () {
      expect(TriggerEvent.insert.value, 'INSERT');
      expect(TriggerEvent.update.value, 'UPDATE');
      expect(TriggerEvent.delete.value, 'DELETE');
    });

    test('fromString parses single event', () {
      final events = TriggerEventExtension.fromString('INSERT');
      expect(events.length, 1);
      expect(events.first, TriggerEvent.insert);
    });

    test('fromString parses multiple events', () {
      final events = TriggerEventExtension.fromString('INSERT, UPDATE');
      expect(events.length, 2);
      expect(events, containsAll([TriggerEvent.insert, TriggerEvent.update]));
    });

    test('fromString is case-insensitive', () {
      final events = TriggerEventExtension.fromString('insert or delete');
      expect(events.length, 2);
    });
  });

  group('DatabaseTrigger', () {
    final trigger = DatabaseTrigger(
      name: 'before_insert_users',
      timing: TriggerTiming.before,
      events: [TriggerEvent.insert],
      tableName: 'users',
      definition:
          'CREATE TRIGGER before_insert_users BEFORE INSERT ON users ...',
      definer: 'admin@localhost',
      createdAt: DateTime(2026, 6, 1),
      modifiedAt: DateTime(2026, 6, 6),
      body: 'SET NEW.created_at = NOW();',
      enabled: true,
    );

    test('fields are correctly set', () {
      expect(trigger.name, 'before_insert_users');
      expect(trigger.timing, TriggerTiming.before);
      expect(trigger.events, [TriggerEvent.insert]);
      expect(trigger.tableName, 'users');
      expect(trigger.enabled, true);
      expect(trigger.definer, 'admin@localhost');
    });

    test('eventString formats correctly', () {
      expect(trigger.eventString, 'INSERT');

      final multiEvent = DatabaseTrigger(
        name: 't',
        timing: TriggerTiming.after,
        events: [TriggerEvent.insert, TriggerEvent.update, TriggerEvent.delete],
        tableName: 'users',
      );
      expect(multiEvent.eventString, 'INSERT OR UPDATE OR DELETE');
    });

    test('toString contains key info', () {
      final s = trigger.toString();
      expect(s, contains('before_insert_users'));
      expect(s, contains('users'));
    });

    test('copyWith preserves unchanged fields', () {
      final copied = trigger.copyWith();
      expect(copied.name, trigger.name);
      expect(copied.timing, trigger.timing);
    });

    test('copyWith updates specified fields', () {
      final copied = trigger.copyWith(
        name: 'after_update_users',
        timing: TriggerTiming.after,
        events: [TriggerEvent.update],
        enabled: false,
      );
      expect(copied.name, 'after_update_users');
      expect(copied.timing, TriggerTiming.after);
      expect(copied.events, [TriggerEvent.update]);
      expect(copied.enabled, false);
      expect(copied.tableName, 'users'); // unchanged
    });
  });
}
