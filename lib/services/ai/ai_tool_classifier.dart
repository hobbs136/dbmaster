/// AI Agent 工具分类器。
///
/// 单一真相源：判断某个工具调用是否属于写操作，以及 SQL 语句的统计
/// 粗分类（[opClassOf]，design-ai-workbench §6.4 三分类判定）。
///
/// [WorkbenchOpClass] 直接复用工作台统计服务的三分类枚举（语义定义的
/// 单一来源），不在本文件再造平行枚举。
library;

import '../workbench_usage_stats_service.dart' show WorkbenchOpClass;

class AiToolClassifier {
  AiToolClassifier._();

  static const _writeToolNames = <String>{
    'smart_import',
    'execute_import',
    'create_export_task',
    'generate_test_data',
    'execute_sql',
    'run_sql',
    'modify_data',
    'insert_data',
    'update_data',
    'delete_data',
    'drop_collection',
    'drop_table',
  };

  /// 判断给定工具调用是否为写操作。
  static bool isWriteTool(String name, Map<String, dynamic> args) {
    if (_writeToolNames.contains(name)) return true;

    // 对于通用 SQL 执行工具，根据 SQL 内容判断。
    if (name == 'execute_sql' || name == 'run_sql') {
      final sql = args['sql'] as String? ?? '';
      return _isWriteSql(sql);
    }

    return false;
  }

  /// 判断给定 SQL 是否为写操作的公开包装。
  ///
  /// 供外部消费方（如工作台工具卡）复用同一判定语义，避免另造第二套判定；
  /// 基线行为与 [_isWriteSql] 一致：SELECT/SHOW/DESCRIBE/EXPLAIN 开头
  /// （忽略首尾空白与大小写）为只读，其余（含空串）为写。
  ///
  /// 例外特判（仅在本公开包装层；[_isWriteSql] 本体与 [isWriteTool] 维持
  /// T06 约束不动）：`EXPLAIN ANALYZE|ANALYSE <写语句>` 在 PG/MySQL 会
  /// **真实执行**其中的写语句，`DESCRIBE/DESC` 亦可能后随写语句形态——
  /// 前缀判读为只读属 fail-open，此处改判写（写关键字词边界匹配，防
  /// `EXPLAINSELECT` 类粘连与表名前缀误命中）。
  static bool isWriteSql(String sql) {
    final upper = sql.trim().toUpperCase();
    if (_explainDescribeWritePrefix.hasMatch(upper)) return true;
    return _isWriteSql(sql);
  }

  /// [isWriteSql] 特判用：`EXPLAIN ANALYZE|ANALYSE` 与 `DESCRIBE|DESC`
  /// 后随写关键字（`\s+` 覆盖任意空白/换行变体；末尾 `\b` 词边界收口）。
  static final RegExp _explainDescribeWritePrefix = RegExp(
    r'^(EXPLAIN\s+ANALYZE|EXPLAIN\s+ANALYSE|DESCRIBE|DESC)\s+'
    r'(CREATE|DROP|ALTER|INSERT|UPDATE|DELETE|TRUNCATE|REPLACE|GRANT|REVOKE)\b',
  );

  /// 统计三分类判定（design-ai-workbench §6.4 / R8 字段 4）：按**语句自身
  /// 类型**逐条分类，批量维度不参与——
  /// - 只读（[isWriteSql] 判 false：SELECT/SHOW/DESCRIBE/EXPLAIN 安全形态，
  ///   含上面的 EXPLAIN ANALYZE 特判）→ [WorkbenchOpClass.queryGen]；
  /// - DML 写（词边界命中 INSERT/UPDATE/DELETE/REPLACE——首关键字与 CTE
  ///   内嵌形态 `WITH ... INSERT` 同计，与 `DatabaseService._isWriteQuery`
  ///   的前缀+词边界口径一致）→ [WorkbenchOpClass.bulkMaint]；
  /// - 其余写（CREATE/DROP/ALTER/TRUNCATE/RENAME/GRANT/REVOKE 等 DDL/
  ///   权限类）→ [WorkbenchOpClass.ddlPerm]。
  ///
  /// 粗分类为统计口径而非安全闸门：`CREATE TRIGGER ... AFTER DELETE` 类
  /// 语句会因词内 DELETE 命中而计入 bulkMaint——与 `_isWriteQuery` 同款
  /// 已知容忍（宁可多计 DML，不漏计写）。
  static WorkbenchOpClass opClassOf(String sql) {
    if (!isWriteSql(sql)) return WorkbenchOpClass.queryGen;
    if (_dmlKeywordPattern.hasMatch(sql.toUpperCase())) {
      return WorkbenchOpClass.bulkMaint;
    }
    return WorkbenchOpClass.ddlPerm;
  }

  /// DML 写语句关键字（统计三分类 bulkMaint 桶；词边界同时覆盖语句首关键
  /// 字与 CTE 内嵌形态）。
  static final RegExp _dmlKeywordPattern = RegExp(
    r'\b(INSERT|UPDATE|DELETE|REPLACE)\b',
  );

  static bool _isWriteSql(String sql) {
    final upper = sql.trim().toUpperCase();
    if (upper.startsWith('SELECT') ||
        upper.startsWith('SHOW') ||
        upper.startsWith('DESCRIBE') ||
        upper.startsWith('EXPLAIN')) {
      return false;
    }
    return true;
  }
}
