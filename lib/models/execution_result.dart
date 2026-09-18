import 'package:flutter/foundation.dart';
import 'result_data_shape.dart';
import 'sql_statement.dart';

@immutable
class ExecutionResult {
  final SQLStatement statement;
  final bool success;
  final List<Map<String, dynamic>>? data;
  final int? affectedRows;
  final Duration executionTime;
  final String? errorMessage;
  final String? errorCode;
  final bool isTruncated;
  final int? limitValue;
  final Map<String, String>? columnTypes;
  // 被 (max)→capped CAST 截断的列名集合（列级；真长度不可知）。
  final Set<String> truncatedColumns;

  /// 结果数据形态（C12）：决定结果面板的渲染器集合。null = sqlRows
  /// （历史结果 / 未标记路径的默认，见 ResultDataShape.shapeForDatabaseType）。
  final ResultDataShape? dataShape;

  const ExecutionResult({
    required this.statement,
    required this.success,
    this.data,
    this.affectedRows,
    required this.executionTime,
    this.errorMessage,
    this.errorCode,
    this.isTruncated = false,
    this.limitValue,
    this.columnTypes,
    this.truncatedColumns = const <String>{},
    this.dataShape,
  });

  static const _dmlTypes = {SQLType.insert, SQLType.update, SQLType.delete};

  bool get isSelect => statement.type == SQLType.select;
  bool get isDML => _dmlTypes.contains(statement.type);
  bool get hasData => data != null && data!.isNotEmpty;

  ExecutionResult copyWith({
    SQLStatement? statement,
    bool? success,
    List<Map<String, dynamic>>? data,
    int? affectedRows,
    Duration? executionTime,
    String? errorMessage,
    String? errorCode,
    bool? isTruncated,
    int? limitValue,
    Map<String, String>? columnTypes,
    Set<String>? truncatedColumns,
    ResultDataShape? dataShape,
  }) {
    return ExecutionResult(
      statement: statement ?? this.statement,
      success: success ?? this.success,
      data: data ?? this.data,
      affectedRows: affectedRows ?? this.affectedRows,
      executionTime: executionTime ?? this.executionTime,
      errorMessage: errorMessage ?? this.errorMessage,
      errorCode: errorCode ?? this.errorCode,
      isTruncated: isTruncated ?? this.isTruncated,
      limitValue: limitValue ?? this.limitValue,
      columnTypes: columnTypes ?? this.columnTypes,
      truncatedColumns: truncatedColumns ?? this.truncatedColumns,
      dataShape: dataShape ?? this.dataShape,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'statement': statement.toJson(),
      'success': success,
      'data': data,
      'affectedRows': affectedRows,
      'executionTimeMs': executionTime.inMilliseconds,
      'errorMessage': errorMessage,
      'errorCode': errorCode,
      'isTruncated': isTruncated,
      'limitValue': limitValue,
      'columnTypes': columnTypes,
      'truncatedColumns': truncatedColumns.toList(),
      if (dataShape != null) 'dataShape': dataShape!.name,
    };
  }

  factory ExecutionResult.fromJson(Map<String, dynamic> json) {
    return ExecutionResult(
      statement: SQLStatement.fromJson(
        Map<String, dynamic>.from(json['statement']),
      ),
      success: json['success'] as bool,
      data: (json['data'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList(),
      affectedRows: json['affectedRows'] as int?,
      executionTime: Duration(
        milliseconds: (json['executionTimeMs'] as num?)?.toInt() ?? 0,
      ),
      errorMessage: json['errorMessage'] as String?,
      errorCode: json['errorCode'] as String?,
      isTruncated: json['isTruncated'] as bool? ?? false,
      limitValue: json['limitValue'] as int?,
      columnTypes: json['columnTypes'] != null
          ? Map<String, String>.from(json['columnTypes'])
          : null,
      truncatedColumns: json['truncatedColumns'] != null
          ? Set<String>.from(json['truncatedColumns'] as List)
          : const <String>{},
      // 历史记录无形态 → null（宿主回退 sqlRows）。
      dataShape: json['dataShape'] is String
          ? ResultDataShape.values.asNameMap()[json['dataShape'] as String]
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExecutionResult &&
        other.statement == statement &&
        other.success == success &&
        other.executionTime == executionTime &&
        other.data?.length == data?.length;
  }

  @override
  int get hashCode =>
      Object.hash(statement, success, executionTime, data?.length);

  @override
  String toString() {
    return 'ExecutionResult(statement: ${statement.index}, success: $success, time: ${executionTime.inMilliseconds}ms, ${hasData ? "${data!.length} rows" : (affectedRows != null ? "$affectedRows affected" : "")}${isTruncated ? ", truncated" : ""})';
  }
}
