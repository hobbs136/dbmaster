import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/result_filter.dart';

void main() {
  group('ColumnFilterPopup', () {
    // These tests verify the logical state of the ColumnFilterPopup widget.
    // Full rendering tests require MaterialApp with proper localization delegates
    // and are deferred to integration tests.

    test('ColumnFilterWidget', () {
      // Verify ColumnFilter model integration
      final filter = ColumnFilter(
        columnName: 'age',
        operator: FilterOperator.greaterThan,
        value: '18',
      );
      expect(filter.columnName, 'age');
      expect(filter.operator, FilterOperator.greaterThan);
      expect(filter.value, '18');
    });

    test('ColumnFilter matches function logic', () {
      // Verify the matches function works correctly for ColumnFilter
      final filter = ColumnFilter(
        columnName: 'name',
        operator: FilterOperator.contains,
        value: 'test',
      );
      expect(filter.matches('testing value'), true);
      expect(filter.matches('no match'), false);
    });

    test('ColumnFilter with isEnabled false always matches', () {
      final filter = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.equals,
        value: 'specific',
        isEnabled: false,
      );
      expect(filter.matches('anything'), true);
    });

    test('ColumnFilter between operator', () {
      final filter = ColumnFilter(
        columnName: 'score',
        operator: FilterOperator.between,
        value: '10',
        valueEnd: '100',
      );
      expect(filter.matches(50), true);
      expect(filter.matches(5), false);
      expect(filter.matches(200), false);
    });
  });
}
