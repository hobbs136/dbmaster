import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/editable_data.dart';

void main() {
  group('EditMode', () {
    test('has 2 values', () {
      expect(EditMode.values.length, 2);
    });
  });

  group('CellEditState', () {
    test('hasChanged detects changes', () {
      final controller = TextEditingController(text: 'new_value');
      final state = CellEditState(
        rowIndex: 0,
        columnName: 'name',
        originalValue: 'old_value',
        currentValue: 'new_value',
        controller: controller,
      );
      expect(state.hasChanged, true);
      controller.dispose();
    });

    test('hasChanged false when no change', () {
      final controller = TextEditingController(text: 'same');
      final state = CellEditState(
        rowIndex: 0,
        columnName: 'name',
        originalValue: 'same',
        currentValue: 'same',
        controller: controller,
      );
      expect(state.hasChanged, false);
      controller.dispose();
    });
  });

  group('EditResult', () {
    test('success factory creates correct result', () {
      final r = EditResult.success(sql: 'UPDATE t SET x=1', rows: 5);
      expect(r.success, true);
      expect(r.generatedSql, 'UPDATE t SET x=1');
      expect(r.affectedRows, 5);
      expect(r.errorMessage, isNull);
    });

    test('error factory creates correct result', () {
      final r = EditResult.error('Cannot update primary key');
      expect(r.success, false);
      expect(r.errorMessage, 'Cannot update primary key');
      expect(r.generatedSql, isNull);
    });
  });

  group('PendingCellChange', () {
    test('hasChanged detects changes', () {
      final change = PendingCellChange(
        rowIndex: 5,
        columnName: 'email',
        originalValue: 'old@test.com',
        newValue: 'new@test.com',
      );
      expect(change.hasChanged, true);
      expect(change.cellKey, '5_email');
    });

    test('hasChanged false when same value', () {
      final change = PendingCellChange(
        rowIndex: 1,
        columnName: 'id',
        originalValue: 100,
        newValue: 100,
      );
      expect(change.hasChanged, false);
    });
  });
}
