import 'dart:isolate';

class ColumnFilter {
  final String columnName;
  final FilterOperator operator;
  final dynamic value;

  ColumnFilter({
    required this.columnName,
    required this.operator,
    required this.value,
  });

  bool matches(dynamic dataValue) {
    switch (operator) {
      case FilterOperator.equals:
        return dataValue == value;
      case FilterOperator.notEquals:
        return dataValue != value;
      case FilterOperator.contains:
        return dataValue.toString().toLowerCase().contains(
          value.toString().toLowerCase(),
        );
      case FilterOperator.notContains:
        return !dataValue.toString().toLowerCase().contains(
          value.toString().toLowerCase(),
        );
      case FilterOperator.greaterThan:
        return _compareNumbers(dataValue, value) > 0;
      case FilterOperator.lessThan:
        return _compareNumbers(dataValue, value) < 0;
      case FilterOperator.greaterThanOrEqual:
        return _compareNumbers(dataValue, value) >= 0;
      case FilterOperator.lessThanOrEqual:
        return _compareNumbers(dataValue, value) <= 0;
      case FilterOperator.isEmpty:
        return dataValue == null || dataValue.toString().isEmpty;
      case FilterOperator.isNotEmpty:
        return dataValue != null && dataValue.toString().isNotEmpty;
      case FilterOperator.regex:
        return RegExp(value.toString()).hasMatch(dataValue.toString());
    }
  }

  int _compareNumbers(dynamic a, dynamic b) {
    final numA = a is num ? a : num.tryParse(a.toString()) ?? 0;
    final numB = b is num ? b : num.tryParse(b.toString()) ?? 0;
    return numA.compareTo(numB);
  }
}

class SortState {
  final String columnName;
  final bool ascending;

  SortState({required this.columnName, required this.ascending});
}

enum FilterOperator {
  equals,
  notEquals,
  contains,
  notContains,
  greaterThan,
  lessThan,
  greaterThanOrEqual,
  lessThanOrEqual,
  isEmpty,
  isNotEmpty,
  regex,
}

class BackgroundFilterService {
  Future<List<Map<String, dynamic>>> filterAndSort(
    List<Map<String, dynamic>> data,
    Map<String, ColumnFilter> filters,
    SortState? sortState,
  ) async {
    if (data.length < 1000) {
      return _processData(data, filters, sortState);
    }

    return _processInIsolate(data, filters, sortState);
  }

  List<Map<String, dynamic>> _processData(
    List<Map<String, dynamic>> data,
    Map<String, ColumnFilter> filters,
    SortState? sortState,
  ) {
    var result = List<Map<String, dynamic>>.from(data);

    for (var filter in filters.values) {
      result = result
          .where((row) => filter.matches(row[filter.columnName]))
          .toList();
    }

    if (sortState != null) {
      result.sort((a, b) {
        final valueA = a[sortState.columnName];
        final valueB = b[sortState.columnName];
        final comparison = _compareValues(valueA, valueB);
        return sortState.ascending ? comparison : -comparison;
      });
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _processInIsolate(
    List<Map<String, dynamic>> data,
    Map<String, ColumnFilter> filters,
    SortState? sortState,
  ) async {
    final receivePort = ReceivePort();

    try {
      await Isolate.spawn(
        _filterAndSortIsolate,
        _FilterParams(
          sendPort: receivePort.sendPort,
          data: data,
          filters: filters,
          sortState: sortState,
        ),
      );

      return await receivePort.first as List<Map<String, dynamic>>;
    } finally {
      receivePort.close();
    }
  }

  static void _filterAndSortIsolate(_FilterParams params) {
    var result = List<Map<String, dynamic>>.from(params.data);

    for (var filter in params.filters.values) {
      result = result
          .where((row) => filter.matches(row[filter.columnName]))
          .toList();
    }

    if (params.sortState != null) {
      result.sort((a, b) {
        final valueA = a[params.sortState!.columnName];
        final valueB = b[params.sortState!.columnName];
        final comparison = _compareValues(valueA, valueB);
        return params.sortState!.ascending ? comparison : -comparison;
      });
    }

    params.sendPort.send(result);
  }

  static int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;

    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);

    return a.toString().compareTo(b.toString());
  }
}

class _FilterParams {
  final SendPort sendPort;
  final List<Map<String, dynamic>> data;
  final Map<String, ColumnFilter> filters;
  final SortState? sortState;

  _FilterParams({
    required this.sendPort,
    required this.data,
    required this.filters,
    required this.sortState,
  });
}
