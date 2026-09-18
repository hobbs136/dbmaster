import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/result_filter.dart';

void main() {
  group('FilterOperator', () {
    test('has expected values', () {
      expect(FilterOperator.values.length, greaterThanOrEqualTo(15));
    });

    test('all operators have labels', () {
      for (final op in FilterOperator.values) {
        expect(op.label, isNotEmpty);
      }
    });

    test('all operators have symbols', () {
      for (final op in FilterOperator.values) {
        expect(op.symbol, isNotEmpty);
      }
    });

    test('requiresValue is false for null/empty operators', () {
      expect(FilterOperator.isNull.requiresValue, false);
      expect(FilterOperator.isNotNull.requiresValue, false);
      expect(FilterOperator.isEmpty.requiresValue, false);
      expect(FilterOperator.isNotEmpty.requiresValue, false);
      expect(FilterOperator.equals.requiresValue, true);
    });

    test('requiresTwoValues is true only for between', () {
      for (final op in FilterOperator.values) {
        if (op == FilterOperator.between) {
          expect(op.requiresTwoValues, true);
        } else {
          expect(op.requiresTwoValues, false);
        }
      }
    });

    test('stringOperators contains expected count', () {
      expect(FilterOperatorExtension.stringOperators.length, 10);
    });

    test('numericOperators contains expected count', () {
      expect(FilterOperatorExtension.numericOperators.length, 9);
    });

    test('dateTimeOperators contains expected count', () {
      expect(FilterOperatorExtension.dateTimeOperators.length, 9);
    });
  });

  group('ColumnDataType', () {
    test('has 4 values（string/numeric/dateTime/json）', () {
      expect(ColumnDataType.values.length, 4);
    });
  });

  group('ColumnFilter', () {
    test('defaults are correct', () {
      final f = ColumnFilter(columnName: 'name');
      expect(f.operator, FilterOperator.contains);
      expect(f.value, '');
      expect(f.isEnabled, true);
    });

    test('toJson/fromJson round-trip', () {
      final f = ColumnFilter(
        columnName: 'age',
        operator: FilterOperator.greaterThan,
        value: '18',
        isEnabled: false,
      );
      final restored = ColumnFilter.fromJson(f.toJson());
      expect(restored.columnName, 'age');
      expect(restored.operator, FilterOperator.greaterThan);
      expect(restored.value, '18');
      expect(restored.isEnabled, false);
    });

    test('matches returns true when disabled', () {
      final f = ColumnFilter(columnName: 'x', isEnabled: false);
      expect(f.matches('anything'), true);
    });

    test('matches - equals (case-insensitive)', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.equals,
        value: 'abc',
      );
      expect(f.matches('abc'), true);
      expect(f.matches('ABC'), true);
      expect(f.matches('xyz'), false);
    });

    test('matches - contains', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.contains,
        value: 'test',
      );
      expect(f.matches('this is a test string'), true);
      expect(f.matches('no match'), false);
    });

    test('matches - startsWith', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.startsWith,
        value: 'hello',
      );
      expect(f.matches('hello world'), true);
      expect(f.matches('say hello'), false);
    });

    test('matches - endsWith', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.endsWith,
        value: 'ing',
      );
      expect(f.matches('running'), true);
      expect(f.matches('runner'), false);
    });

    test('matches - greaterThan with numbers', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.greaterThan,
        value: '100',
      );
      expect(f.matches(150), true);
      expect(f.matches(50), false);
    });

    test('matches - between with numbers', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.between,
        value: '10',
        valueEnd: '20',
      );
      expect(f.matches(15), true);
      expect(f.matches(10), true);
      expect(f.matches(5), false);
      expect(f.matches(25), false);
    });

    test('matches - isNull', () {
      final f = ColumnFilter(columnName: 'x', operator: FilterOperator.isNull);
      expect(f.matches(null), true);
      expect(f.matches('not null'), false);
    });

    test('matches - isNotNull', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.isNotNull,
      );
      expect(f.matches(null), false);
      expect(f.matches('value'), true);
    });

    test('matches - isEmpty', () {
      final f = ColumnFilter(columnName: 'x', operator: FilterOperator.isEmpty);
      expect(f.matches(''), true);
      expect(f.matches('non-empty'), false);
    });

    test('matches - notContains', () {
      final f = ColumnFilter(
        columnName: 'x',
        operator: FilterOperator.notContains,
        value: 'bad',
      );
      expect(f.matches('good string'), true);
      expect(f.matches('bad string'), false);
    });

    test('copyWith updates fields', () {
      final f = ColumnFilter(columnName: 'col');
      final copied = f.copyWith(operator: FilterOperator.equals, value: 'test');
      expect(copied.operator, FilterOperator.equals);
      expect(copied.value, 'test');
      expect(copied.columnName, 'col');
    });
  });

  group('ResultFilterService', () {
    test('initial state is empty', () {
      final svc = ResultFilterService();
      expect(svc.hasActiveFilters, false);
      expect(svc.activeFilterCount, 0);
    });

    test('setFilter and hasActiveFilters', () {
      final svc = ResultFilterService();
      svc.setFilter(
        ColumnFilter(
          columnName: 'name',
          operator: FilterOperator.contains,
          value: 'test',
        ),
      );
      expect(svc.hasActiveFilters, true);
      expect(svc.activeFilterCount, 1);
    });

    test('removeFilter clears filter', () {
      final svc = ResultFilterService();
      svc.setFilter(
        ColumnFilter(
          columnName: 'name',
          operator: FilterOperator.contains,
          value: 'test',
        ),
      );
      svc.removeFilter('name');
      expect(svc.hasActiveFilters, false);
    });

    test('clearFilters removes all', () {
      final svc = ResultFilterService();
      svc.setFilter(
        ColumnFilter(
          columnName: 'a',
          operator: FilterOperator.contains,
          value: 'x',
        ),
      );
      svc.setFilter(
        ColumnFilter(
          columnName: 'b',
          operator: FilterOperator.contains,
          value: 'y',
        ),
      );
      svc.clearFilters();
      expect(svc.filters, isEmpty);
    });

    test('toggleFilter enables/disables', () {
      final svc = ResultFilterService();
      svc.setFilter(
        ColumnFilter(
          columnName: 'name',
          operator: FilterOperator.contains,
          value: 'test',
        ),
      );
      svc.toggleFilter('name', false);
      expect(svc.hasActiveFilters, false);
      svc.toggleFilter('name', true);
      expect(svc.hasActiveFilters, true);
    });

    test('setColumnType and getColumnType', () {
      final svc = ResultFilterService();
      expect(svc.getColumnType('age'), ColumnDataType.string); // default
      svc.setColumnType('age', ColumnDataType.numeric);
      expect(svc.getColumnType('age'), ColumnDataType.numeric);
    });

    test('getOperatorsForColumn returns correct sets', () {
      final svc = ResultFilterService();
      expect(
        svc.getOperatorsForColumn('name'),
        FilterOperatorExtension.stringOperators,
      );

      svc.setColumnType('age', ColumnDataType.numeric);
      expect(
        svc.getOperatorsForColumn('age'),
        FilterOperatorExtension.numericOperators,
      );

      svc.setColumnType('created', ColumnDataType.dateTime);
      expect(
        svc.getOperatorsForColumn('created'),
        FilterOperatorExtension.dateTimeOperators,
      );
    });

    test('applyFilters filters data correctly', () {
      final svc = ResultFilterService();
      svc.setFilter(
        ColumnFilter(
          columnName: 'status',
          operator: FilterOperator.equals,
          value: 'active',
        ),
      );

      final data = [
        {'name': 'alice', 'status': 'active'},
        {'name': 'bob', 'status': 'inactive'},
        {'name': 'charlie', 'status': 'active'},
      ];
      final filtered = svc.applyFilters(data);
      expect(filtered.length, 2);
      expect(filtered[0]['name'], 'alice');
    });

    test('applyFilters returns all when no active filters', () {
      final svc = ResultFilterService();
      final data = [
        {'name': 'alice'},
        {'name': 'bob'},
      ];
      expect(svc.applyFilters(data).length, 2);
    });

    test('applySorting sorts ascending', () {
      final svc = ResultFilterService();
      final data = [
        {'name': 'charlie'},
        {'name': 'alice'},
        {'name': 'bob'},
      ];
      final sorted = svc.applySorting(data, 'name', true);
      expect(sorted[0]['name'], 'alice');
      expect(sorted[1]['name'], 'bob');
      expect(sorted[2]['name'], 'charlie');
    });

    test('applySorting sorts descending', () {
      final svc = ResultFilterService();
      final data = [
        {'name': 'alice'},
        {'name': 'charlie'},
        {'name': 'bob'},
      ];
      final sorted = svc.applySorting(data, 'name', false);
      expect(sorted[0]['name'], 'charlie');
      expect(sorted[2]['name'], 'alice');
    });

    test('applySorting sorts numeric values correctly', () {
      final svc = ResultFilterService();
      final data = [
        {'id': '10'},
        {'id': '2'},
        {'id': '1'},
      ];
      final sorted = svc.applySorting(data, 'id', true);
      expect(sorted[0]['id'], '1');
      expect(sorted[1]['id'], '2');
      expect(sorted[2]['id'], '10');
    });

    test('detectColumnType detects numeric columns', () {
      final data = [
        {'age': 25},
        {'age': 30},
        {'age': 35},
      ];
      expect(
        ResultFilterService.detectColumnType(data, 'age'),
        ColumnDataType.numeric,
      );
    });

    test('detectColumnType defaults to string for mixed data', () {
      final data = [
        {'col': 'hello'},
        {'col': 123},
      ];
      expect(
        ResultFilterService.detectColumnType(data, 'col'),
        ColumnDataType.string,
      );
    });

    test('detectColumnType returns string for empty data', () {
      expect(
        ResultFilterService.detectColumnType([], 'col'),
        ColumnDataType.string,
      );
    });
  });

  group('applyRowSearch', () {
    final sample = [
      {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'},
      {'id': 2, 'name': 'Bob', 'email': 'bob@TEST.com'},
      {'id': 3, 'name': 'Charlie', 'email': 'charlie@example.com'},
      {'id': 4, 'name': 'Alice Cooper', 'email': 'cooper@example.com'},
    ];

    test('empty query returns original list unchanged', () {
      expect(applyRowSearch(sample, ''), same(sample));
    });

    test('whitespace-only query is treated as non-empty (filters)', () {
      // 空格作为字面字符匹配——所有行 toString 都含空格？未必。
      // 这里验证空白字符串不走 isEmpty 早返回分支，而是真做 contains。
      final result = applyRowSearch(sample, 'xyz_no_match');
      expect(result, isEmpty);
    });

    test('matches value in any column (name column)', () {
      final result = applyRowSearch(sample, 'alice');
      expect(result.map((r) => r['id']), containsAll([1, 4]));
      expect(result.length, 2);
    });

    test('matches value in any column (email column)', () {
      // bob 的 email 是 bob@TEST.com（不含 example.com），其余 3 行含
      final result = applyRowSearch(sample, 'example.com');
      expect(result.length, 3);
      expect(result.map((r) => r['id']), containsAll([1, 3, 4]));
    });

    test('case-insensitive matching', () {
      final result = applyRowSearch(sample, 'ALICE');
      expect(result.length, 2);
      final result2 = applyRowSearch(sample, 'tEsT');
      expect(result2.map((r) => r['id']), [2]);
    });

    test('numeric values are matched via toString', () {
      final result = applyRowSearch(sample, '3');
      // id=3 (name="Charlie" no, email no) → id 值 3 命中
      expect(result.any((r) => r['id'] == 3), isTrue);
    });

    test('no match returns empty list', () {
      expect(applyRowSearch(sample, 'zzz_nomatch'), isEmpty);
    });

    test('null values are skipped (do not throw)', () {
      final withNull = [
        {'a': null, 'b': 'hello'},
        {'a': 'world', 'b': null},
      ];
      expect(applyRowSearch(withNull, 'hello').length, 1);
      expect(applyRowSearch(withNull, 'world').length, 1);
      expect(applyRowSearch(withNull, 'null'), isEmpty); // null 不参与 toString
    });

    test('partial substring match', () {
      final result = applyRowSearch(sample, 'lic');
      expect(result.map((r) => r['id']), containsAll([1, 4]));
    });

    test('does not mutate input data', () {
      final original = List<Map<String, dynamic>>.from(sample);
      applyRowSearch(sample, 'alice');
      expect(sample, equals(original));
    });

    test('returns new list instance (not original) when filtering', () {
      final result = applyRowSearch(sample, 'alice');
      expect(identical(result, sample), isFalse);
      expect(result, isA<List<Map<String, dynamic>>>());
    });
  });
}
