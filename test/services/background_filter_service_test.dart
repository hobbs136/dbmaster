import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/background_filter_service.dart';

void main() {
  group('BackgroundFilterService', () {
    late BackgroundFilterService service;

    setUp(() {
      service = BackgroundFilterService();
    });

    test('should filter data by equals operator', () async {
      final data = List.generate(
        10,
        (i) => {'id': i, 'value': i % 2 == 0 ? 'even' : 'odd'},
      );

      final filters = {
        'value': ColumnFilter(
          columnName: 'value',
          operator: FilterOperator.equals,
          value: 'even',
        ),
      };

      final result = await service.filterAndSort(data, filters, null);

      expect(result.length, 5);
      expect(result.every((row) => row['value'] == 'even'), true);
    });

    test('should filter data by contains operator', () async {
      final data = [
        {'id': 1, 'name': 'Alice'},
        {'id': 2, 'name': 'Bob'},
        {'id': 3, 'name': 'Charlie'},
      ];

      final filters = {
        'name': ColumnFilter(
          columnName: 'name',
          operator: FilterOperator.contains,
          value: 'a',
        ),
      };

      final result = await service.filterAndSort(data, filters, null);

      expect(result.length, 2);
      expect(result.any((row) => row['name'] == 'Alice'), true);
      expect(result.any((row) => row['name'] == 'Charlie'), true);
    });

    test('should sort data ascending', () async {
      final data = [
        {'id': 3, 'value': 30},
        {'id': 1, 'value': 10},
        {'id': 2, 'value': 20},
      ];

      final sortState = SortState(columnName: 'value', ascending: true);

      final result = await service.filterAndSort(data, {}, sortState);

      expect(result[0]['id'], 1);
      expect(result[1]['id'], 2);
      expect(result[2]['id'], 3);
    });

    test('should sort data descending', () async {
      final data = [
        {'id': 3, 'value': 30},
        {'id': 1, 'value': 10},
        {'id': 2, 'value': 20},
      ];

      final sortState = SortState(columnName: 'value', ascending: false);

      final result = await service.filterAndSort(data, {}, sortState);

      expect(result[0]['id'], 3);
      expect(result[1]['id'], 2);
      expect(result[2]['id'], 1);
    });

    test('should apply both filter and sort', () async {
      final data = [
        {'id': 1, 'value': 10, 'name': 'b'},
        {'id': 2, 'value': 20, 'name': 'a'},
        {'id': 3, 'value': 30, 'name': 'c'},
      ];

      final filters = {
        'value': ColumnFilter(
          columnName: 'value',
          operator: FilterOperator.greaterThan,
          value: 10,
        ),
      };

      final sortState = SortState(columnName: 'name', ascending: true);

      final result = await service.filterAndSort(data, filters, sortState);

      expect(result.length, 2);
      expect(result[0]['id'], 2);
      expect(result[1]['id'], 3);
    });
  });
}
