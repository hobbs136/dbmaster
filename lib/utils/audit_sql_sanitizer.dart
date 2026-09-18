/// SQL 语句敏感信息脱敏工具（用于审计日志）
///
/// 在审计日志记录前对 SQL 进行脱敏处理，防止密码、密钥等敏感值
/// 以明文形式持久化存储。
class AuditSqlSanitizer {
  static final _sensitiveKeywords = [
    'password',
    'secret',
    'token',
    'api_key',
    'apikey',
    'api_secret',
    'auth',
    'credential',
  ];

  /// 脱敏敏感关键字后的字符串值
  ///
  /// 规则：
  /// - `password`, `secret`, `token`, `api_key`, `apikey`, `api_secret`, `auth`, `credential`
  ///   等关键字后跟 `=` 或 `:` 的字符串值替换为 `***`
  /// - 仅脱敏值部分，保留 SQL 结构
  static String sanitize(String sql) {
    if (sql.isEmpty) return sql;

    var result = sql;

    for (final keyword in _sensitiveKeywords) {
      // SQL 风格: keyword = 'value'（单引号）
      final singleQuotePattern = RegExp(
        "\\b$keyword\\s*=\\s*'[^']*'",
        caseSensitive: false,
      );
      result = result.replaceAllMapped(singleQuotePattern, (match) {
        final text = match.group(0)!;
        final eqIndex = text.indexOf('=');
        return "${text.substring(0, eqIndex)}= '***'";
      });

      // SQL 风格: keyword = "value"（双引号）
      final doubleQuotePattern = RegExp(
        '\\b$keyword\\s*=\\s"[^"]*"',
        caseSensitive: false,
      );
      result = result.replaceAllMapped(doubleQuotePattern, (match) {
        final text = match.group(0)!;
        final eqIndex = text.indexOf('=');
        return '${text.substring(0, eqIndex)}= "***"';
      });

      // JSON 风格: "keyword": "value"（双引号值）
      final jsonDoublePattern = RegExp(
        '"$keyword"\\s*:\\s*"[^"]*"',
        caseSensitive: false,
      );
      result = result.replaceAllMapped(jsonDoublePattern, (match) {
        return '"$keyword": "***"';
      });

      // JSON 风格: "keyword": 'value'（单引号值）
      final jsonSinglePattern = RegExp(
        "\"$keyword\"\\s*:\\s*'[^']*'",
        caseSensitive: false,
      );
      result = result.replaceAllMapped(jsonSinglePattern, (match) {
        return "\"$keyword\": '***'";
      });
    }

    return result;
  }
}
