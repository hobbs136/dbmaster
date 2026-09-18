//! 安全审查规则（B6 T12）：可写 CTE 检测。
//!
//! dbx sql_risk 同款检测面：`WITH t AS (DELETE FROM logs RETURNING id)
//! SELECT * FROM t` 类——写操作（DELETE/UPDATE/INSERT/MERGE）藏在 CTE
//! 体内，语句表面是查询，执行却修改数据，绕过「看首关键词判读写」的
//! 目测与审查习惯。
//!
//! 实现走 cleanForAnalysis 清洗产物（注释/字符串已剥离——字符串内的
//! 伪 CTE 特征天然不误报；MySQL 可执行注释内容保留，藏进注释的写
//! 操作仍可见）：语句以 WITH 开头才继续 → 线性扫每个 `AS (` 的平衡
//! 括号体 → 体首关键词命中 DELETE/INSERT/UPDATE/MERGE 即计。检查完
//! 一个体后**不跳过**、从体内继续线性扫——嵌套 WITH / 子查询内的
//! CTE 因此天然覆盖（等价于递归下钻）。
//!
//! 保守边界：`WITH ... AS (SELECT ...)` 普通 CTE 绝不报；RETURNING
//! 子句不是必要条件（MySQL 不支持 RETURNING，INSERT...SELECT CTE
//! 同样命中）；`AS` 后不跟括号（`COUNT(*) AS c`）不触发；未闭合括号
//! 停止扫描（引擎报语法错误，语句不会执行）；WITH 开头但主语句是写
//! 操作（`WITH t AS (SELECT 1) DELETE ...`）不是 CTE 体内写，归其它
//! 读写判定，本规则不报。无引擎门控（语法形态各引擎一致）。B1 注册
//! 接线归 T14。

import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

class WritableCteRule implements SafetyRule {
  @override
  final String id = 'writable_cte';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      final cleaned = SQLParserService.cleanForAnalysis(sql);
      // 仅 WITH 开头的语句继续（词边界防 WITHIN 类前缀误入）。
      if (!RegExp(r'^WITH\b', caseSensitive: false).hasMatch(cleaned.trim())) {
        return [];
      }

      final heads = _writableHeads(cleaned);
      if (heads.isEmpty) return [];

      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.medium,
          title: '检测到 ${heads.length} 个可写 CTE'
              '（${heads.toSet().join('/')} 藏在 WITH 体内）',
          description: 'WITH ... AS (DELETE/UPDATE/INSERT/MERGE ...) 把写'
              '操作藏在看似查询的语句里，执行时会实际修改数据。请确认该'
              '语句来源可信、写操作的影响范围符合预期。',
        ),
      ];
    } catch (_) {
      // 规则异常 → 返回空（引擎也兜底 catch）。
      return [];
    }
  }

  /// 线性扫描所有 `AS (` 的平衡括号体，返回体首关键词命中写操作的列表。
  /// 检查完一个体后从体内继续扫（不跳过）——嵌套 WITH / 子查询内的
  /// CTE 天然覆盖。
  static List<String> _writableHeads(String cleaned) {
    final heads = <String>[];
    var i = 0;
    while (i < cleaned.length) {
      if (_matchesWord(cleaned, i, 'AS')) {
        var j = i + 2;
        while (j < cleaned.length && _isWhitespace(cleaned[j])) {
          j++;
        }
        if (j < cleaned.length && cleaned[j] == '(') {
          // 找这对括号的平衡闭括号，切出 CTE 体。
          var depth = 1;
          var k = j + 1;
          var closed = false;
          while (k < cleaned.length) {
            if (cleaned[k] == '(') depth++;
            if (cleaned[k] == ')') {
              depth--;
              if (depth == 0) {
                closed = true;
                break;
              }
            }
            k++;
          }
          if (!closed) break; // 未闭合：引擎报语法错误，语句不会执行。
          final head = _headKeyword(cleaned.substring(j + 1, k));
          if (head != null) heads.add(head);
          i = j + 1; // 从体内继续线性扫（嵌套 CTE 覆盖点）。
          continue;
        }
      }
      i++;
    }
    return heads;
  }

  /// CTE 体首关键词（去前导空白后取首词，词边界防 DELETED 误命中）；
  /// 命中 DELETE/INSERT/UPDATE/MERGE 返回关键词（大写），否则 null。
  /// 在 toUpperCase 文本上匹配（大小写无关）。
  static String? _headKeyword(String body) {
    final match = RegExp(r'^\s*(DELETE|INSERT|UPDATE|MERGE)\b')
        .firstMatch(body.toUpperCase());
    return match?.group(1);
  }

  /// text[i] 起是否是独立关键字 word（前后均为词边界，大小写无关）。
  /// 词边界保证 CASE / ASIN( 内的 as 不被当成 AS。
  static bool _matchesWord(String text, int i, String word) {
    if (i + word.length > text.length) return false;
    for (var k = 0; k < word.length; k++) {
      if (text[i + k].toUpperCase() != word[k]) return false;
    }
    final beforeOk = i == 0 || !_isWordChar(text[i - 1]);
    final end = i + word.length;
    final afterOk = end >= text.length || !_isWordChar(text[end]);
    return beforeOk && afterOk;
  }

  static bool _isWordChar(String char) =>
      char == '_' || RegExp(r'\w').hasMatch(char);

  static bool _isWhitespace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == '\r';
}
