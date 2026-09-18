//! SQL 安全审查 — SafetyRule trait + SafetyContext（ADR-0003 Part A）。
//!
//! 加新审查规则 = 实现一个 [SafetyRule]，注册到 [SafetyReviewService]，
//! 不改核心引擎代码。

import '../../models/database_models.dart' show Database, DatabaseType;
import 'safety_finding.dart';

/// 审查时可用的 schema 元数据。规则从这里拿表/列/行数信息。
///
/// [schemaCache] 是侧边栏展开时加载的 [Database] 对象（可能为 null——
/// 未展开侧边栏、非 MySQL/Doris、或审查异常时）。规则应 null-safe：
/// schemaCache 为 null 时跳过依赖它的检查（返回空 findings），不误报。
class SafetyContext {
  final String connectionId;
  final String? database;
  final DatabaseType dbType;

  /// 已加载的 schema（来自侧边栏展开时的 getDatabaseInfo 缓存）。
  /// 查表/列存在性时用这个，不额外查库。null = 未加载，规则跳过。
  final Database? schemaCache;

  /// 查表行数。先查缓存，无缓存时实时查（可能返回 null = 跳过规则）。
  final Future<int?> Function(String tableName) getRowCount;

  /// 查表的所有列名（从 schemaCache 或实时查）。null = 无法获取，跳过。
  final Future<List<String>?> Function(String tableName) getColumns;

  /// 查询 EXPLAIN 执行计划（第三阶段）。返回原始行数据（List<Map>），
  /// 规则自行调 `ExplainParser.parse` 解析。
  /// null = 不支持 EXPLAIN（非 SQL 库 / 未注入），EXPLAIN 规则跳过。
  final Future<List<Map<String, dynamic>>>? Function(String sql)?
      getExplainPlan;

  /// EXPLAIN 调用超时秒数（默认 3）。超时则 EXPLAIN 规则静默跳过。
  final int explainTimeoutSeconds;

  const SafetyContext({
    required this.connectionId,
    required this.dbType,
    this.database,
    this.schemaCache,
    required this.getRowCount,
    required this.getColumns,
    this.getExplainPlan,
    this.explainTimeoutSeconds = 3,
  });
}

/// 一条安全审查规则。加新规则 = 实现此接口。
///
/// 规则应保持**保守**——不确定时返回空 findings（不误报），而不是
/// 猜测。误报会降低用户对审查的信任。
abstract class SafetyRule {
  /// 规则的唯一 ID（如 'schema_compat'），用于开关/日志/审计。
  String get id;

  /// 检查一条 SQL，返回 findings（空列表 = 无问题）。
  ///
  /// 实现应 catch 自身的异常并返回空列表（引擎也会兜底 catch，但规则
  /// 内处理能提供更精确的日志）。
  Future<List<SafetyFinding>> check(String sql, SafetyContext context);
}
