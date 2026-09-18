/// SQL 多语句脚本执行失败（U08）。
///
/// 逐条执行脚本时定位失败语句：序号 + 原脚本行号范围（网关/GO 批等路径
/// 可能拿不到行号，为 null）、底层错误，以及失败前已执行生效的条数——
/// 脚本逐条执行没有整体事务，中途失败 = 部分提交，必须让用户知道库里
/// 已经落了多少条、后面还有多少没跑。
///
/// [toString] 直接面向用户（snackbar / 查询历史原样展示），保持中文与
/// 服务层既有错误文案一致；结构化字段留给后续 l10n（U17）。
class SqlScriptExecutionException implements Exception {
  /// 失败语句的 0-based 序号。
  final int statementIndex;

  /// 失败语句在原脚本中的起始行（1-based）；未知为 null。
  final int? lineStart;

  /// 失败语句在原脚本中的结束行（1-based）；未知为 null。
  final int? lineEnd;

  /// 失败语句文本。
  final String statementSql;

  /// 底层错误消息。
  final String cause;

  /// 失败前已执行生效的语句条数。
  final int committedCount;

  const SqlScriptExecutionException({
    required this.statementIndex,
    this.lineStart,
    this.lineEnd,
    required this.statementSql,
    required this.cause,
    required this.committedCount,
  });

  @override
  String toString() {
    final position = lineStart == null
        ? '第 ${statementIndex + 1} 条语句'
        : lineEnd != null && lineEnd != lineStart
        ? '第 ${statementIndex + 1} 条语句（第 $lineStart-$lineEnd 行）'
        : '第 ${statementIndex + 1} 条语句（第 $lineStart 行）';
    final committed = committedCount > 0 ? '；前 $committedCount 条已执行生效，其后的语句未执行' : '';
    return 'SQL 脚本执行失败：$position：$cause$committed';
  }
}
