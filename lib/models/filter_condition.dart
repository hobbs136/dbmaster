// spec 041: FilterBar 筛选条件值模型（US3）。

/// 值类型：决定 `buildFilteredSelect` 如何编码值。
/// - [string]：字符串字面值（`escapeString` 加引号）—— 文本/日期/enum 等。
/// - [boolean]：布尔，按 dbType 输出**裸值**（PG→TRUE/FALSE、其余→1/0，不加引号）。
///   由 FilterBar 对 boolean/bit 列产生；值限定 true/false，无注入面。
enum FilterValueKind { string, boolean }

/// FilterBar 单行筛选条件（会话内、不持久化、不进 `QueryTab.toJson`）。
///
/// 由 `FilterBarStrip` 编辑、`buildFilteredSelect` 只读消费。
/// 不可变值类：重写 `operator==`/`hashCode` 以支持精确比较/重建控制。
class FilterCondition {
  final String field;
  final FilterOperator op;
  final String value;
  final FilterValueKind kind;

  const FilterCondition({
    required this.field,
    required this.op,
    this.value = '',
    this.kind = FilterValueKind.string,
  });

  FilterCondition copyWith({
    String? field,
    FilterOperator? op,
    String? value,
    FilterValueKind? kind,
  }) {
    return FilterCondition(
      field: field ?? this.field,
      op: op ?? this.op,
      value: value ?? this.value,
      kind: kind ?? this.kind,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is FilterCondition &&
            other.field == field &&
            other.op == op &&
            other.value == value &&
            other.kind == kind);
  }

  @override
  int get hashCode => Object.hash(field, op, value, kind);
}

/// 比较符（MVP 子集）。
///
/// 完整操作符矩阵（IN / BETWEEN / 正则等）defer 到后续独立 spec。
/// [isNull] / [isNotNull] 不取 value（`buildFilteredSelect` 跳过取值）。
enum FilterOperator {
  eq,
  ne,
  gt,
  gte,
  lt,
  lte,
  like,
  notLike,
  isNull,
  isNotNull,
}

/// 多条件组合器。
enum FilterCombinator { and, or }
