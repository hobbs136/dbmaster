enum FilterOperator {
  equals,
  notEquals,
  contains,
  notContains,
  startsWith,
  endsWith,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  between,
  isNull,
  isNotNull,
  isEmpty,
  isNotEmpty,
}

extension FilterOperatorExtension on FilterOperator {
  String get label {
    switch (this) {
      case FilterOperator.equals:
        return '等于';
      case FilterOperator.notEquals:
        return '不等于';
      case FilterOperator.contains:
        return '包含';
      case FilterOperator.notContains:
        return '不包含';
      case FilterOperator.startsWith:
        return '开头为';
      case FilterOperator.endsWith:
        return '结尾为';
      case FilterOperator.greaterThan:
        return '大于';
      case FilterOperator.greaterThanOrEqual:
        return '大于等于';
      case FilterOperator.lessThan:
        return '小于';
      case FilterOperator.lessThanOrEqual:
        return '小于等于';
      case FilterOperator.between:
        return '介于';
      case FilterOperator.isNull:
        return '为空';
      case FilterOperator.isNotNull:
        return '不为空';
      case FilterOperator.isEmpty:
        return '为空字符串';
      case FilterOperator.isNotEmpty:
        return '不为空字符串';
    }
  }

  String get symbol {
    switch (this) {
      case FilterOperator.equals:
        return '=';
      case FilterOperator.notEquals:
        return '!=';
      case FilterOperator.contains:
        return 'LIKE %...%';
      case FilterOperator.notContains:
        return 'NOT LIKE %...%';
      case FilterOperator.startsWith:
        return 'LIKE ...%';
      case FilterOperator.endsWith:
        return 'LIKE %...';
      case FilterOperator.greaterThan:
        return '>';
      case FilterOperator.greaterThanOrEqual:
        return '>=';
      case FilterOperator.lessThan:
        return '<';
      case FilterOperator.lessThanOrEqual:
        return '<=';
      case FilterOperator.between:
        return 'BETWEEN';
      case FilterOperator.isNull:
        return 'IS NULL';
      case FilterOperator.isNotNull:
        return 'IS NOT NULL';
      case FilterOperator.isEmpty:
        return "= ''";
      case FilterOperator.isNotEmpty:
        return "!= ''";
    }
  }

  bool get requiresValue {
    switch (this) {
      case FilterOperator.isNull:
      case FilterOperator.isNotNull:
      case FilterOperator.isEmpty:
      case FilterOperator.isNotEmpty:
        return false;
      default:
        return true;
    }
  }

  bool get requiresTwoValues {
    return this == FilterOperator.between;
  }

  static List<FilterOperator> get stringOperators => [
    FilterOperator.equals,
    FilterOperator.notEquals,
    FilterOperator.contains,
    FilterOperator.notContains,
    FilterOperator.startsWith,
    FilterOperator.endsWith,
    FilterOperator.isNull,
    FilterOperator.isNotNull,
    FilterOperator.isEmpty,
    FilterOperator.isNotEmpty,
  ];

  static List<FilterOperator> get numericOperators => [
    FilterOperator.equals,
    FilterOperator.notEquals,
    FilterOperator.greaterThan,
    FilterOperator.greaterThanOrEqual,
    FilterOperator.lessThan,
    FilterOperator.lessThanOrEqual,
    FilterOperator.between,
    FilterOperator.isNull,
    FilterOperator.isNotNull,
  ];

  static List<FilterOperator> get dateTimeOperators => [
    FilterOperator.equals,
    FilterOperator.notEquals,
    FilterOperator.greaterThan,
    FilterOperator.greaterThanOrEqual,
    FilterOperator.lessThan,
    FilterOperator.lessThanOrEqual,
    FilterOperator.between,
    FilterOperator.isNull,
    FilterOperator.isNotNull,
  ];
}

enum ColumnDataType { string, numeric, dateTime, json }

class ColumnFilter {
  final String columnName;
  FilterOperator operator;
  String value;
  String valueEnd;
  bool isEnabled;

  ColumnFilter({
    required this.columnName,
    this.operator = FilterOperator.contains,
    this.value = '',
    this.valueEnd = '',
    this.isEnabled = true,
  });

  ColumnFilter copyWith({
    String? columnName,
    FilterOperator? operator,
    String? value,
    String? valueEnd,
    bool? isEnabled,
  }) {
    return ColumnFilter(
      columnName: columnName ?? this.columnName,
      operator: operator ?? this.operator,
      value: value ?? this.value,
      valueEnd: valueEnd ?? this.valueEnd,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  bool matches(Object? cellValue) {
    if (!isEnabled) return true;

    final strValue = cellValue?.toString() ?? '';

    switch (operator) {
      case FilterOperator.equals:
        return strValue.toLowerCase() == value.toLowerCase();
      case FilterOperator.notEquals:
        return strValue.toLowerCase() != value.toLowerCase();
      case FilterOperator.contains:
        return strValue.toLowerCase().contains(value.toLowerCase());
      case FilterOperator.notContains:
        return !strValue.toLowerCase().contains(value.toLowerCase());
      case FilterOperator.startsWith:
        return strValue.toLowerCase().startsWith(value.toLowerCase());
      case FilterOperator.endsWith:
        return strValue.toLowerCase().endsWith(value.toLowerCase());
      case FilterOperator.greaterThan:
        return _compareValues(strValue, value) > 0;
      case FilterOperator.greaterThanOrEqual:
        return _compareValues(strValue, value) >= 0;
      case FilterOperator.lessThan:
        return _compareValues(strValue, value) < 0;
      case FilterOperator.lessThanOrEqual:
        return _compareValues(strValue, value) <= 0;
      case FilterOperator.between:
        final compareStart = _compareValues(strValue, value);
        final compareEnd = _compareValues(strValue, valueEnd);
        return compareStart >= 0 && compareEnd <= 0;
      case FilterOperator.isNull:
        return cellValue == null;
      case FilterOperator.isNotNull:
        return cellValue != null;
      case FilterOperator.isEmpty:
        return strValue.isEmpty;
      case FilterOperator.isNotEmpty:
        return strValue.isNotEmpty;
    }
  }

  int _compareValues(String actual, String expected) {
    final numActual = num.tryParse(actual);
    final numExpected = num.tryParse(expected);
    if (numActual != null && numExpected != null) {
      return numActual.compareTo(numExpected);
    }
    final dateActual = _tryParseDateTime(actual);
    final dateExpected = _tryParseDateTime(expected);
    if (dateActual != null && dateExpected != null) {
      return dateActual.compareTo(dateExpected);
    }
    return actual.toLowerCase().compareTo(expected.toLowerCase());
  }

  DateTime? _tryParseDateTime(String value) {
    final patterns = [
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$'),
      RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$'),
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'),
      RegExp(r'^(\d{4})/(\d{2})/(\d{2})$'),
      RegExp(r'^(\d{2})/(\d{2})/(\d{4})$'),
    ];

    for (var pattern in patterns) {
      if (pattern.hasMatch(value)) {
        return DateTime.tryParse(value.replaceAll('/', '-'));
      }
    }

    return DateTime.tryParse(value);
  }

  Map<String, dynamic> toJson() {
    return {
      'columnName': columnName,
      'operator': operator.index,
      'value': value,
      'valueEnd': valueEnd,
      'isEnabled': isEnabled,
    };
  }

  factory ColumnFilter.fromJson(Map<String, dynamic> json) {
    return ColumnFilter(
      columnName: json['columnName'] as String,
      operator: FilterOperator.values[json['operator'] as int],
      value: json['value'] as String? ?? '',
      valueEnd: json['valueEnd'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }
}

class ResultFilterService {
  final Map<String, ColumnFilter> _filters = {};
  final Map<String, ColumnDataType> _columnTypes = {};

  Map<String, ColumnFilter> get filters => Map.unmodifiable(_filters);
  Map<String, ColumnDataType> get columnTypes => Map.unmodifiable(_columnTypes);

  bool get hasActiveFilters => _filters.values.any(
    (f) => f.isEnabled && (f.value.isNotEmpty || !f.operator.requiresValue),
  );

  int get activeFilterCount => _filters.values
      .where(
        (f) => f.isEnabled && (f.value.isNotEmpty || !f.operator.requiresValue),
      )
      .length;

  void setFilter(ColumnFilter filter) {
    _filters[filter.columnName] = filter;
  }

  void removeFilter(String columnName) {
    _filters.remove(columnName);
  }

  void clearFilters() {
    _filters.clear();
  }

  void toggleFilter(String columnName, bool enabled) {
    if (_filters.containsKey(columnName)) {
      _filters[columnName]!.isEnabled = enabled;
    }
  }

  void setColumnType(String columnName, ColumnDataType type) {
    _columnTypes[columnName] = type;
  }

  ColumnDataType getColumnType(String columnName) {
    return _columnTypes[columnName] ?? ColumnDataType.string;
  }

  static ColumnDataType detectColumnType(
    List<Map<String, dynamic>> data,
    String columnName, {
    Map<String, String>? columnTypes,
  }) {
    // T010 — check column type metadata first for JSON columns
    if (columnTypes != null) {
      final colType = columnTypes[columnName];
      if (colType == 'jsonb' || colType == 'json' || colType == 'json_detected') {
        return ColumnDataType.json;
      }
    }

    if (data.isEmpty) return ColumnDataType.string;

    // 类型推断只需统计显著性——宽表全行扫描（3000+ 行 × 列数）会让
    // 元数据延迟到秒级，导致依赖类型的 UI（数值右对齐等）明显跳变。
    // 前 500 行采样在保持推断准确性的同时把耗时降到毫秒级。
    const sampleLimit = 500;
    final sample = data.length > sampleLimit
        ? data.sublist(0, sampleLimit)
        : data;

    int numericCount = 0;
    int dateTimeCount = 0;
    int totalCount = 0;

    for (var row in sample) {
      final value = row[columnName];
      if (value == null) continue;

      totalCount++;

      if (value is num) {
        numericCount++;
        continue;
      }

      final strValue = value.toString();

      if (num.tryParse(strValue) != null) {
        numericCount++;
        continue;
      }

      if (_isDateTimeValue(strValue)) {
        dateTimeCount++;
        continue;
      }
    }

    if (totalCount == 0) return ColumnDataType.string;

    final numericRatio = numericCount / totalCount;
    final dateTimeRatio = dateTimeCount / totalCount;

    if (numericRatio > 0.8) return ColumnDataType.numeric;
    if (dateTimeRatio > 0.8) return ColumnDataType.dateTime;
    return ColumnDataType.string;
  }

  static bool _isDateTimeValue(String value) {
    final dateTimePatterns = [
      RegExp(r'^\d{4}-\d{2}-\d{2}$'),
      RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'),
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'),
      RegExp(r'^\d{4}/\d{2}/\d{2}$'),
      RegExp(r'^\d{2}/\d{2}/\d{4}$'),
      RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+$'),
    ];

    for (var pattern in dateTimePatterns) {
      if (pattern.hasMatch(value)) {
        return DateTime.tryParse(value.replaceAll('/', '-')) != null;
      }
    }

    return false;
  }

  List<FilterOperator> getOperatorsForColumn(String columnName) {
    final type = getColumnType(columnName);
    switch (type) {
      case ColumnDataType.numeric:
        return FilterOperatorExtension.numericOperators;
      case ColumnDataType.dateTime:
        return FilterOperatorExtension.dateTimeOperators;
      case ColumnDataType.string:
      case ColumnDataType.json:
        return FilterOperatorExtension.stringOperators;
    }
  }

  List<Map<String, dynamic>> applyFilters(List<Map<String, dynamic>> data) {
    if (!hasActiveFilters) return data;

    return data.where((row) {
      for (var filter in _filters.values) {
        if (!filter.isEnabled) continue;
        if (filter.value.isEmpty && filter.operator.requiresValue) continue;

        final cellValue = row[filter.columnName];
        if (!filter.matches(cellValue)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> applySorting(
    List<Map<String, dynamic>> data,
    String columnName,
    bool ascending,
  ) {
    final sortedData = List<Map<String, dynamic>>.from(data);
    sortedData.sort((a, b) {
      final valueA = a[columnName];
      final valueB = b[columnName];

      if (valueA == null && valueB == null) return 0;
      if (valueA == null) return ascending ? 1 : -1;
      if (valueB == null) return ascending ? -1 : 1;

      final strA = valueA.toString();
      final strB = valueB.toString();

      final numA = num.tryParse(strA);
      final numB = num.tryParse(strB);

      int result;
      if (numA != null && numB != null) {
        result = numA.compareTo(numB);
      } else {
        result = strA.toLowerCase().compareTo(strB.toLowerCase());
      }

      return ascending ? result : -result;
    });
    return sortedData;
  }
}

/// 行级搜索：保留任意列 toString 后包含 [query]（case-insensitive）的行。
///
/// 与 [ResultFilterService]（列级过滤）正交：本函数不关心列名，只看整行任意值。
/// [query] 为空时原样返回 [data]（不过滤）；null 值跳过不匹配。
///
/// 典型用法：在列级 `ResultFilterService.applyFilters` 之后再叠加一层，
/// 形成列过滤 ∩ 行搜索 的交集（见 spec 051-results-row-search）。
List<Map<String, dynamic>> applyRowSearch(
  List<Map<String, dynamic>> data,
  String query,
) {
  if (query.isEmpty) return data;
  final q = query.toLowerCase();
  return data.where((row) {
    for (final v in row.values) {
      if (v != null && v.toString().toLowerCase().contains(q)) return true;
    }
    return false;
  }).toList();
}
