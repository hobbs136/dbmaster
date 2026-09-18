/// Doris 表模型探测 —— 解析 `SHOW CREATE TABLE` 判断 Doris 表的数据模型，
/// 用于 UPDATE 守卫（仅 UNIQUE / PRIMARY KEY 模型支持 UPDATE）。
library;

/// Doris 表的数据模型（决定是否支持 UPDATE/DELETE）。
enum DorisTableModel {
  /// 明细模型，仅追加，不支持 UPDATE。
  duplicate,

  /// 聚合模型，不支持 UPDATE。
  aggregate,

  /// 主键去重模型，支持 UPDATE/DELETE。
  unique,

  /// 主键模型（Unique 的 Merge-on-Write 升级），支持 UPDATE/DELETE。
  primaryKey;

  /// 该模型是否支持 SQL UPDATE。
  bool get supportsUpdate =>
      this == DorisTableModel.unique || this == DorisTableModel.primaryKey;
}

/// 通过解析 `SHOW CREATE TABLE` 输出推断 Doris 表模型。
///
/// Doris 的表模型在建表语句中以关键字声明：
/// `DUPLICATE KEY(...)` / `AGGREGATE KEY(...)` / `UNIQUE KEY(...)` / `PRIMARY KEY(...)`。
/// 本探测不依赖 `information_schema`（无现成模型列），解析 SHOW CREATE TABLE 最可靠。
class DorisTableModelDetector {
  DorisTableModelDetector._();

  /// 执行 `SHOW CREATE TABLE` 并解析模型；任何失败返回 null（调用方应降级为不守卫）。
  static Future<DorisTableModel?> detect(
    String tableName,
    Future<List<Map<String, dynamic>>> Function(String) executeQuery,
  ) async {
    try {
      final escaped = tableName.replaceAll('`', '``');
      final rows = await executeQuery('SHOW CREATE TABLE `$escaped`');
      if (rows.isEmpty) return null;
      final createSql = rows.first['Create Table']?.toString() ?? '';
      return parseCreateTable(createSql);
    } catch (_) {
      // 探测失败 → 降级（不守卫），不阻断用户操作
      return null;
    }
  }

  /// 从 `SHOW CREATE TABLE` 文本解析模型关键字。
  /// 无法识别时返回 null（保守起见不假定为 DUP/AGG，避免误警）。
  static DorisTableModel? parseCreateTable(String createSql) {
    if (createSql.isEmpty) return null;
    final upper = createSql.toUpperCase();
    // DEFENSIVE-NOTE: 顺序敏感——PRIMARY/UNIQUE 优先于 AGG/DUP 判定，
    // 避免被 KEY 子句中的其它字串误匹配。
    if (upper.contains('PRIMARY KEY')) return DorisTableModel.primaryKey;
    if (upper.contains('UNIQUE KEY')) return DorisTableModel.unique;
    if (upper.contains('AGGREGATE KEY')) return DorisTableModel.aggregate;
    if (upper.contains('DUPLICATE KEY')) return DorisTableModel.duplicate;
    return null;
  }
}
