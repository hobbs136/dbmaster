import 'package:flutter/foundation.dart';

import '../../theme/design_system.dart';

/// 工作台卡类型（design-ai-workbench §4.4）。
///
/// JSON 分发不直接消费本枚举——T12 workbench_card_host 按
/// `toolResultData['workbench']['kind']` 字符串（各 payload 类的 [WorkbenchSqlCardPayload.kind]
/// / [WorkbenchResultCardPayload.kind]）分发；本枚举为类型面的契约预留。
enum WorkbenchCardKind { sqlCard, resultCard }

// ============================================================================
// C-2 扩展注记（对本文件两类 payload 均适用，design §4.4/C-2）：
// M2 审批/审计语义（如 approval?: {...}）作为同级新字段追加；旧读方忽略
// 未知键（Map 读取天然向前兼容）——fromJson 只取已知键，不整型校验，
// 严禁把「未知键存在」当错误。
// ============================================================================

/// SQL 工具卡 payload（R4，design §4.4）。
///
/// 挂载形态：`AiMessage.toolResultData['workbench'] = payload.toJson()`
/// （'workbench' 键由建卡方 T13 组装，payload 本体不嵌套该键）。
/// [isWrite] 是建卡时 `AiToolClassifier.isWriteSql` 的判定快照；执行时
/// T13 以 effectiveWorkbenchContext 复核上下文，不信任 [connectionId]/
/// [databaseName] 快照（生成时上下文仅作展示参考）。
@immutable
class WorkbenchSqlCardPayload {
  static const String kind = 'sql_card';

  final String sql;

  /// 语句类型（SELECT/INSERT/...，header 徽标用）。
  final String statementType;

  /// 写操作判定快照（header 危险徽标用，AC4 判定来源 = classifier）。
  final bool isWrite;

  /// 生成时上下文（展示参考；执行时以 effective context 复核）。
  final String? connectionId;
  final String? databaseName;

  const WorkbenchSqlCardPayload({
    required this.sql,
    required this.statementType,
    required this.isWrite,
    this.connectionId,
    this.databaseName,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'sql': sql,
    'statementType': statementType,
    'isWrite': isWrite,
    'connectionId': connectionId,
    'databaseName': databaseName,
  };

  /// 从 `toolResultData['workbench']` 反序列化；kind 不匹配或关键字段
  /// 畸形返回 null（C-2：未知键忽略，向前兼容）。
  static WorkbenchSqlCardPayload? fromJson(Map<String, dynamic> json) {
    if (json['kind'] != kind) return null;
    final sql = json['sql'];
    final statementType = json['statementType'];
    if (sql is! String || statementType is! String) return null;
    final connectionId = json['connectionId'];
    final databaseName = json['databaseName'];
    final isWrite = json['isWrite'];
    return WorkbenchSqlCardPayload(
      sql: sql,
      statementType: statementType,
      isWrite: isWrite is bool ? isWrite : false,
      connectionId: connectionId is String ? connectionId : null,
      databaseName: databaseName is String ? databaseName : null,
    );
  }
}

/// 结果表格卡 payload（R5，design §4.4/§5.2）。
///
/// 快照即持久化本体：建卡时 `rows.take(N)`（N 唯一来源 =
/// [AppDesignSystem.toolCardSnapshotRows]，探针定值，勿引字面值），take 保留
/// 行 Map 原引用不复制值；完整结果集不入卡（「在网格中打开」时经 SQL 重执行
/// 取得，卡数据结构里不存在全量字段）。会话文件因此天然限界 ≤ N 行。
@immutable
class WorkbenchResultCardPayload {
  static const String kind = 'result_card';

  final String sql;

  /// 完整行数 M（可能 > snapshotRows.length）。
  final int rowCount;

  final int durationMs;

  final List<String> columns;

  /// ≤ N 行快照（行 Map 为执行结果原引用）。
  final List<Map<String, dynamic>> snapshotRows;

  /// 执行管线产物（_QueryExecutionResult.columnTypes）；null = 管线未提供。
  final Map<String, String>? columnTypes;

  /// rowCount > snapshotRows.length（M>N 时表尾截断提示 + 「在网格中打开」，
  /// 仅 M>N 出现该动作，AC5.2/5.4）。
  final bool isTruncated;

  /// rowCount == 0（空态，AC5.6）。
  final bool isEmpty;

  /// [rows] 传入原始执行结果行（可为全量）；构造时在此执行 take(N) 截断，
  /// 保证 [snapshotRows] ≤ N 的不变式落在数据结构自身（调用方无法绕过）。
  factory WorkbenchResultCardPayload({
    required String sql,
    required int rowCount,
    required int durationMs,
    required List<String> columns,
    required List<Map<String, dynamic>> rows,
    Map<String, String>? columnTypes,
  }) {
    final snapshot = rows
        .take(AppDesignSystem.toolCardSnapshotRows)
        .toList(growable: false);
    return WorkbenchResultCardPayload._(
      sql: sql,
      rowCount: rowCount,
      durationMs: durationMs,
      columns: List.unmodifiable(columns),
      snapshotRows: List.unmodifiable(snapshot),
      columnTypes: columnTypes == null ? null : Map.unmodifiable(columnTypes),
      isTruncated: rowCount > snapshot.length,
      isEmpty: rowCount == 0,
    );
  }

  const WorkbenchResultCardPayload._({
    required this.sql,
    required this.rowCount,
    required this.durationMs,
    required this.columns,
    required this.snapshotRows,
    required this.columnTypes,
    required this.isTruncated,
    required this.isEmpty,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind,
    'sql': sql,
    'rowCount': rowCount,
    'durationMs': durationMs,
    'columns': columns,
    'snapshotRows': snapshotRows,
    if (columnTypes != null) 'columnTypes': columnTypes,
    'isTruncated': isTruncated,
    'isEmpty': isEmpty,
  };

  /// 从 `toolResultData['workbench']` 反序列化；kind 不匹配或关键字段畸形
  /// 返回 null（C-2：未知键忽略）。历史快照按落盘原样恢复、**不做 N 再
  /// 裁剪**——AC2.2「历史会话重开后卡片所见 = 当初快照」：探针复跑后 N
  /// 变小时，旧会话卡片仍显示当初写入的行数。
  static WorkbenchResultCardPayload? fromJson(Map<String, dynamic> json) {
    if (json['kind'] != kind) return null;
    final sql = json['sql'];
    if (sql is! String) return null;
    final rowCount = json['rowCount'];
    final durationMs = json['durationMs'];
    if (rowCount is! int || durationMs is! int) return null;
    final columnsRaw = json['columns'];
    if (columnsRaw is! List) return null;
    final columns = columnsRaw.whereType<String>().toList(growable: false);
    final rowsRaw = json['snapshotRows'];
    if (rowsRaw is! List) return null;
    final rows = rowsRaw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
    final typesRaw = json['columnTypes'];
    final columnTypes = typesRaw is Map
        ? typesRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : null;
    final isTruncated = json['isTruncated'];
    final isEmpty = json['isEmpty'];
    return WorkbenchResultCardPayload._(
      sql: sql,
      rowCount: rowCount,
      durationMs: durationMs,
      columns: List.unmodifiable(columns),
      snapshotRows: List.unmodifiable(rows),
      columnTypes: columnTypes == null ? null : Map.unmodifiable(columnTypes),
      isTruncated: isTruncated is bool ? isTruncated : rowCount > rows.length,
      isEmpty: isEmpty is bool ? isEmpty : rowCount == 0,
    );
  }
}
