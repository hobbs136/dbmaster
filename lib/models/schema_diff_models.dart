import 'database_models.dart';

/// Schema Diff 功能的数据模型
/// 用于表示数据库 Schema 的快照、差异和同步操作

/// 差异类型
enum DiffType {
  added, // 新增
  removed, // 删除
  modified, // 修改
  unchanged, // 无变化
}

/// Schema 快照 - 某个时刻的数据库完整结构
class SchemaSnapshot {
  final String connectionId;
  final String connectionName;
  final String databaseName;
  final DateTime capturedAt;
  final List<DbTable> tables;
  final List<String> views;
  final List<String> procedures; // 存储过程/函数名称列表
  final Map<String, String> createStatements; // tableName -> CREATE TABLE SQL
  final Map<String, String> viewCreateStatements; // viewName -> CREATE VIEW SQL
  final Map<String, String>
  procedureCreateStatements; // procedureName -> CREATE PROCEDURE/FUNCTION SQL
  final List<String> captureErrors; // errors during per-table capture

  SchemaSnapshot({
    required this.connectionId,
    required this.connectionName,
    required this.databaseName,
    required this.capturedAt,
    required this.tables,
    this.views = const [],
    this.procedures = const [],
    this.createStatements = const {},
    this.viewCreateStatements = const {},
    this.procedureCreateStatements = const {},
    this.captureErrors = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'connectionId': connectionId,
      'connectionName': connectionName,
      'databaseName': databaseName,
      'capturedAt': capturedAt.toIso8601String(),
      'tables': tables.map((t) => _tableToJson(t)).toList(),
      'views': views,
      'procedures': procedures,
      'createStatements': createStatements,
      'viewCreateStatements': viewCreateStatements,
      'procedureCreateStatements': procedureCreateStatements,
      'captureErrors': captureErrors,
    };
  }

  factory SchemaSnapshot.fromJson(Map<String, dynamic> json) {
    return SchemaSnapshot(
      connectionId: json['connectionId'] as String,
      connectionName: json['connectionName'] as String,
      databaseName: json['databaseName'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      tables: (json['tables'] as List<dynamic>)
          .map((t) => _tableFromJson(t as Map<String, dynamic>))
          .toList(),
      views: (json['views'] as List<dynamic>?)?.cast<String>() ?? [],
      procedures: (json['procedures'] as List<dynamic>?)?.cast<String>() ?? [],
      createStatements:
          (json['createStatements'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          {},
      viewCreateStatements:
          (json['viewCreateStatements'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          {},
      procedureCreateStatements:
          (json['procedureCreateStatements'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          {},
      captureErrors:
          (json['captureErrors'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  static Map<String, dynamic> _tableToJson(DbTable table) {
    return {
      'name': table.name,
      'columns': table.columns
          .map(
            (c) => {
              'name': c.name,
              'type': c.type,
              'isPrimaryKey': c.isPrimaryKey,
              'isNullable': c.isNullable,
              'defaultValue': c.defaultValue,
            },
          )
          .toList(),
      'indexes': table.indexes
          .map(
            (i) => {
              'name': i.name,
              'columns': i.columns,
              'isUnique': i.isUnique,
            },
          )
          .toList(),
    };
  }

  static DbTable _tableFromJson(Map<String, dynamic> json) {
    return DbTable(
      name: json['name'] as String,
      columns: (json['columns'] as List<dynamic>)
          .map(
            (c) => DbColumn(
              name: c['name'] as String,
              type: c['type'] as String,
              isPrimaryKey: c['isPrimaryKey'] as bool? ?? false,
              isNullable: c['isNullable'] as bool? ?? true,
              defaultValue: c['defaultValue'] as String?,
            ),
          )
          .toList(),
      indexes: (json['indexes'] as List<dynamic>)
          .map(
            (i) => DbIndex(
              name: i['name'] as String,
              columns: (i['columns'] as List<dynamic>).cast<String>(),
              isUnique: i['isUnique'] as bool? ?? false,
            ),
          )
          .toList(),
    );
  }
}

/// 列差异
class ColumnDiff {
  final String name;
  final DiffType type;
  final DbColumn? sourceColumn; // 源（旧）列定义
  final DbColumn? targetColumn; // 目标（新）列定义

  ColumnDiff({
    required this.name,
    required this.type,
    this.sourceColumn,
    this.targetColumn,
  });
}

/// 索引差异
class IndexDiff {
  final String name;
  final DiffType type;
  final DbIndex? sourceIndex;
  final DbIndex? targetIndex;

  IndexDiff({
    required this.name,
    required this.type,
    this.sourceIndex,
    this.targetIndex,
  });
}

/// 表差异
class TableDiff {
  final String name;
  final DiffType type;
  final List<ColumnDiff> columnDiffs;
  final List<IndexDiff> indexDiffs;
  final String? sourceCreateSql; // 源 CREATE TABLE
  final String? targetCreateSql; // 目标 CREATE TABLE

  TableDiff({
    required this.name,
    required this.type,
    this.columnDiffs = const [],
    this.indexDiffs = const [],
    this.sourceCreateSql,
    this.targetCreateSql,
  });

  bool get hasChanges =>
      type != DiffType.unchanged ||
      columnDiffs.any((c) => c.type != DiffType.unchanged) ||
      indexDiffs.any((i) => i.type != DiffType.unchanged);

  int get changeCount =>
      (type != DiffType.unchanged ? 1 : 0) +
      columnDiffs.where((c) => c.type != DiffType.unchanged).length +
      indexDiffs.where((i) => i.type != DiffType.unchanged).length;
}

/// 存储过程差异
class ProcedureDiff {
  final String name;
  final DiffType type;
  final String? createStatement; // CREATE PROCEDURE/FUNCTION SQL

  ProcedureDiff({required this.name, required this.type, this.createStatement});
}

/// 完整的 Schema 差异报告
class SchemaDiffReport {
  final String sourceConnection;
  final String targetConnection;
  final String sourceDatabase;
  final String targetDatabase;
  final DateTime generatedAt;
  final List<TableDiff> tableDiffs;
  final List<ViewDiff> viewDiffs;
  final List<ProcedureDiff> procedureDiffs;
  final List<String> captureErrors; // errors from snapshot capture

  SchemaDiffReport({
    required this.sourceConnection,
    required this.targetConnection,
    required this.sourceDatabase,
    required this.targetDatabase,
    required this.generatedAt,
    this.tableDiffs = const [],
    this.viewDiffs = const [],
    this.procedureDiffs = const [],
    this.captureErrors = const [],
  });

  int get addedTables =>
      tableDiffs.where((t) => t.type == DiffType.added).length;
  int get removedTables =>
      tableDiffs.where((t) => t.type == DiffType.removed).length;
  int get modifiedTables =>
      tableDiffs.where((t) => t.type == DiffType.modified).length;
  int get unchangedTables =>
      tableDiffs.where((t) => t.type == DiffType.unchanged).length;

  int get totalTableChanges => addedTables + removedTables + modifiedTables;
  int get totalColumnChanges => tableDiffs.fold(
    0,
    (sum, t) =>
        sum + t.columnDiffs.where((c) => c.type != DiffType.unchanged).length,
  );
  int get totalIndexChanges => tableDiffs.fold(
    0,
    (sum, t) =>
        sum + t.indexDiffs.where((i) => i.type != DiffType.unchanged).length,
  );

  bool get hasChanges =>
      totalTableChanges > 0 ||
      totalColumnChanges > 0 ||
      totalIndexChanges > 0 ||
      viewDiffs.isNotEmpty ||
      procedureDiffs.isNotEmpty;
}

class ViewDiff {
  final String name;
  final DiffType type;
  final String? createStatement; // CREATE VIEW SQL

  ViewDiff({required this.name, required this.type, this.createStatement});
}

/// 同步操作 - 单个 DDL 变更
class SyncOperation {
  final String id;
  final String description;
  final String sql;
  final DiffType type;
  final String targetTable;
  final bool isExecuted;
  final String? error;

  SyncOperation({
    required this.id,
    required this.description,
    required this.sql,
    required this.type,
    required this.targetTable,
    this.isExecuted = false,
    this.error,
  });

  SyncOperation copyWith({
    String? id,
    String? description,
    String? sql,
    DiffType? type,
    String? targetTable,
    bool? isExecuted,
    String? error,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      description: description ?? this.description,
      sql: sql ?? this.sql,
      type: type ?? this.type,
      targetTable: targetTable ?? this.targetTable,
      isExecuted: isExecuted ?? this.isExecuted,
      error: error ?? this.error,
    );
  }
}

/// 同步计划 - 一组有序的同步操作
class SyncPlan {
  final String sourceSnapshot;
  final String targetSnapshot;
  final List<SyncOperation> operations;
  final bool isDryRun;

  SyncPlan({
    required this.sourceSnapshot,
    required this.targetSnapshot,
    required this.operations,
    this.isDryRun = true,
  });

  int get totalOperations => operations.length;
  int get executedCount => operations.where((o) => o.isExecuted).length;
  int get failedCount => operations.where((o) => o.error != null).length;
  bool get isComplete => executedCount == totalOperations;
  bool get hasAllAttempted => (executedCount + failedCount) == totalOperations;
}

// Phase A — New models for schema diff E2E (ignore rules, sync execution, snapshots)

/// 忽略规则目标类型
enum DiffIgnoreTarget {
  columnDefault,
  comment,
  collation,
  autoIncrement,
  indexName,
}

/// 单条忽略规则 — 匹配特定差异模式并将其过滤
class DiffIgnoreRule {
  final String id;
  final String name;
  final DiffIgnoreTarget target;
  final String? pattern; // 可选正则表达式
  final bool enabled;

  const DiffIgnoreRule({
    required this.id,
    required this.name,
    required this.target,
    this.pattern,
    this.enabled = true,
  });

  DiffIgnoreRule copyWith({
    String? id,
    String? name,
    DiffIgnoreTarget? target,
    String? pattern,
    bool? enabled,
  }) {
    return DiffIgnoreRule(
      id: id ?? this.id,
      name: name ?? this.name,
      target: target ?? this.target,
      pattern: pattern ?? this.pattern,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target.name,
        'pattern': pattern,
        'enabled': enabled,
      };

  factory DiffIgnoreRule.fromJson(Map<String, dynamic> json) {
    return DiffIgnoreRule(
      id: json['id'] as String,
      name: json['name'] as String,
      target: DiffIgnoreTarget.values.firstWhere(
        (t) => t.name == json['target'],
        orElse: () => DiffIgnoreTarget.autoIncrement,
      ),
      pattern: json['pattern'] as String?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// 忽略规则集合 — 可按名称保存/加载
class DiffProfile {
  final String id;
  final String name;
  final List<DiffIgnoreRule> rules;

  const DiffProfile({
    required this.id,
    required this.name,
    this.rules = const [],
  });

  /// 创建默认 Profile（不过滤任何差异）
  factory DiffProfile.defaults() {
    return DiffProfile(id: 'default', name: 'Default', rules: []);
  }

  List<DiffIgnoreRule> get enabledRules =>
      rules.where((r) => r.enabled).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rules': rules.map((r) => r.toJson()).toList(),
      };

  factory DiffProfile.fromJson(Map<String, dynamic> json) {
    return DiffProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      rules: (json['rules'] as List<dynamic>?)
              ?.map(
                (r) => DiffIgnoreRule.fromJson(r as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

/// 差异分类 — 用于筛选器
enum DiffCategory {
  all,
  added,
  modified,
  removed,
  tables,
  indexes,
  views,
  procedures,
}

/// 同步步骤状态
enum SyncStepStatus {
  pending,
  running,
  success,
  failed,
  skipped,
}

/// 同步执行阶段
enum SyncExecutionPhase {
  validating,
  executing,
  rollingBack,
  completed,
  failed,
}

/// 单步执行跟踪
class SyncStep {
  final SyncOperation operation;
  final SyncStepStatus status;
  final String? error;
  final Duration? duration;

  const SyncStep({
    required this.operation,
    this.status = SyncStepStatus.pending,
    this.error,
    this.duration,
  });

  SyncStep copyWith({
    SyncOperation? operation,
    SyncStepStatus? status,
    String? error,
    Duration? duration,
  }) {
    return SyncStep(
      operation: operation ?? this.operation,
      status: status ?? this.status,
      error: error,
      duration: duration ?? this.duration,
    );
  }
}

/// 同步执行进度 — 通过 Stream 发射
class SyncProgress {
  final int currentStep;
  final int totalSteps;
  final SyncStep? currentOperation;
  final List<SyncStep> completedSteps;
  final SyncExecutionPhase phase;
  final String? error;

  const SyncProgress({
    required this.currentStep,
    required this.totalSteps,
    this.currentOperation,
    this.completedSteps = const [],
    this.phase = SyncExecutionPhase.validating,
    this.error,
  });

  double get percentComplete =>
      totalSteps > 0 ? currentStep / totalSteps : 0.0;

  int get successCount =>
      completedSteps.where((s) => s.status == SyncStepStatus.success).length;
  int get failureCount =>
      completedSteps.where((s) => s.status == SyncStepStatus.failed).length;
  int get skippedCount =>
      completedSteps.where((s) => s.status == SyncStepStatus.skipped).length;
}

/// 同步执行结果摘要
class SyncResult {
  final int successCount;
  final int failureCount;
  final int skippedCount;
  final List<SyncStep> steps;
  final Duration totalDuration;
  final bool didRollback;
  final String? rollbackScript;

  const SyncResult({
    required this.successCount,
    required this.failureCount,
    required this.skippedCount,
    required this.steps,
    this.totalDuration = Duration.zero,
    this.didRollback = false,
    this.rollbackScript,
  });

  bool get isPerfect => failureCount == 0;
  int get totalCount => successCount + failureCount + skippedCount;
}

/// 持久化快照元数据
class PersistedSnapshot {
  final String id;
  final String name;
  final String connectionName;
  final String databaseName;
  final String dbType;
  final DateTime capturedAt;
  final int tableCount;
  final int viewCount;
  final int procedureCount;
  final int fileSizeBytes;
  final String filePath;
  final SchemaSnapshot snapshot;

  const PersistedSnapshot({
    required this.id,
    required this.name,
    required this.connectionName,
    required this.databaseName,
    required this.dbType,
    required this.capturedAt,
    required this.tableCount,
    this.viewCount = 0,
    this.procedureCount = 0,
    required this.fileSizeBytes,
    required this.filePath,
    required this.snapshot,
  });

  factory PersistedSnapshot.fromSchemaSnapshot({
    required String id,
    required String name,
    required String filePath,
    required SchemaSnapshot snapshot,
    String? dbType,
  }) {
    return PersistedSnapshot(
      id: id,
      name: name,
      connectionName: snapshot.connectionName,
      databaseName: snapshot.databaseName,
      dbType: dbType ?? '',
      capturedAt: snapshot.capturedAt,
      tableCount: snapshot.tables.length,
      viewCount: snapshot.views.length,
      procedureCount: snapshot.procedures.length,
      fileSizeBytes: 0, // 由服务层计算
      filePath: filePath,
      snapshot: snapshot,
    );
  }

  PersistedSnapshot copyWithFileSize(int newSize) {
    return PersistedSnapshot(
      id: id,
      name: name,
      connectionName: connectionName,
      databaseName: databaseName,
      dbType: dbType,
      capturedAt: capturedAt,
      tableCount: tableCount,
      viewCount: viewCount,
      procedureCount: procedureCount,
      fileSizeBytes: newSize,
      filePath: filePath,
      snapshot: snapshot,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'connectionName': connectionName,
        'databaseName': databaseName,
        'dbType': dbType,
        'capturedAt': capturedAt.toIso8601String(),
        'tableCount': tableCount,
        'viewCount': viewCount,
        'procedureCount': procedureCount,
        'fileSizeBytes': fileSizeBytes,
        'filePath': filePath,
        'snapshot': snapshot.toJson(),
      };

  factory PersistedSnapshot.fromJson(Map<String, dynamic> json) {
    return PersistedSnapshot(
      id: json['id'] as String,
      name: json['name'] as String,
      connectionName: json['connectionName'] as String,
      databaseName: json['databaseName'] as String,
      dbType: json['dbType'] as String? ?? '',
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      tableCount: json['tableCount'] as int,
      viewCount: json['viewCount'] as int? ?? 0,
      procedureCount: json['procedureCount'] as int? ?? 0,
      fileSizeBytes: json['fileSizeBytes'] as int,
      filePath: json['filePath'] as String,
      snapshot: SchemaSnapshot.fromJson(
        json['snapshot'] as Map<String, dynamic>,
      ),
    );
  }
}
