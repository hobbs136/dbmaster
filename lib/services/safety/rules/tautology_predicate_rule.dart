//! 安全审查规则（B6 T11）：WHERE 恒真谓词检测。
//!
//! dbx sql_risk 同款检测面：`WHERE 1=1`、`WHERE TRUE`、自比较 `id = id`。
//! 恒真谓词使 WHERE 条件全部或部分恒成立——DELETE/UPDATE 借此波及全表，
//! 注入载荷借此绕过预期过滤。`WHERE 1=1` 也常见于动态拼接 SQL 的惯用
//! 写法，故 finding 提示用户确认意图而非直接定性。
//!
//! 实现走 `extractWhereClause`（cleanForAnalysis 产物：注释/字符串已剥离、
//! 可执行注释已解包）→ 括号深度感知的顶层 AND 拆分 → 逐项判恒真。
//!
//! 保守边界（宁可漏报不误报）：字符串比较（清洗后 `'x'='x'` 折叠成
//! `' ' = ' '`，原文形态归 SqlInjectionRule 检测）/ OR 锚定形态
//! （`OR 1=1` 是 SqlInjectionRule 的注入检测面）/ `NULL = NULL`（结果
//! unknown 非恒真）/ 限定名不同的比较（`a.id = b.id` 是 JOIN 常态）/
//! 子查询内 WHERE 与 HAVING（v1 只看顶层拆分产物）。
//! B1 引擎 UI 注册接线归 T14。

import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

class TautologyPredicateRule implements SafetyRule {
  @override
  final String id = 'tautology_predicate';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      final whereClause = SQLParserService.extractWhereClause(sql);
      if (whereClause == null) return [];

      final hits = <String>[];
      for (final item in _splitTopLevelAnd(whereClause)) {
        final hit = _tautologyText(item);
        if (hit != null) hits.add(hit);
      }
      if (hits.isEmpty) return [];

      final examples = hits.take(2).map((t) => '`$t`').join('、');
      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: 'WHERE 条件中存在 ${hits.length} 处恒真谓词（如 $examples）',
          description: '恒真谓词（如 1=1、col = col）使 WHERE 条件全部或'
              '部分恒成立：DELETE/UPDATE 会波及全表，注入载荷可借此绕过'
              '预期过滤。WHERE 1=1 也常见于动态拼接 SQL 的惯用写法——'
              '请确认该语句来源可信且影响范围符合预期。',
        ),
      ];
    } catch (_) {
      // 规则异常 → 返回空（引擎也兜底 catch）。
      return [];
    }
  }

  /// 括号深度感知的顶层 AND 拆分：括号内的 AND 不是拆分点。
  /// BETWEEN 等结构被误拆出的碎片（如 `d BETWEEN 1` / `5`）不匹配
  /// 恒真形态，不致误报。
  static List<String> _splitTopLevelAnd(String text) {
    final items = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var i = 0;
    while (i < text.length) {
      final char = text[i];
      if (char == '(') depth++;
      if (char == ')' && depth > 0) depth--;

      if (depth == 0 && _matchesWord(text, i, 'AND')) {
        items.add(buffer.toString());
        buffer.clear();
        i += 3;
        continue;
      }
      buffer.write(char);
      i++;
    }
    items.add(buffer.toString());
    return items;
  }

  /// text[i] 起是否是独立关键字 word（前后均为词边界，大小写无关）。
  /// 词边界保证 `android` 内的 and 不被当成 AND。
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

  /// 判定一个顶层谓词项是否恒真；是则返回该项文本（用于展示），否则 null。
  static String? _tautologyText(String rawItem) {
    var item = rawItem.trim();
    // 剥掉包住全文的平衡外层括号：(1=1) / ((TRUE))。
    while (item.length >= 2 &&
        item.startsWith('(') &&
        item.endsWith(')') &&
        _outerParensWrapAll(item)) {
      item = item.substring(1, item.length - 1).trim();
    }
    if (item.isEmpty) return null;

    if (item.toUpperCase() == 'TRUE') return item;

    // 相等形态：恰好一个顶层 `=`。比较符 / 三个以上 `=` 均不匹配。
    final sides = item.split('=');
    if (sides.length != 2) return null;
    final left = sides[0].trim();
    final right = sides[1].trim();

    // 同数字：1=1 / 2.5 = 2.5（数值比较，容忍 01 = 1 这类写法）。
    final leftNum = double.tryParse(left);
    final rightNum = double.tryParse(right);
    if (leftNum != null && rightNum != null) {
      return leftNum == rightNum ? item : null;
    }

    // 同标识符自比较：id = id / t.col = `t`.`col`（反引号与空白归一）。
    // 引号占位符（' '）与非标识符形状（函数调用、运算符残片）在此落空。
    final leftNorm = _normalizeIdentifier(left);
    final rightNorm = _normalizeIdentifier(right);
    if (leftNorm == null || rightNorm == null || leftNorm != rightNorm) {
      return null;
    }
    // NULL = NULL 结果是 unknown（恒不真），排除。
    final base = leftNorm.split('.').last;
    if (base == 'NULL' || base == 'UNKNOWN') return null;
    return item;
  }

  /// item 是否以 ( 开头、) 结尾且这对括号包住全文（`(a) OR (b)` 的外层
  /// 括号在中途已闭合，不可剥）。
  static bool _outerParensWrapAll(String item) {
    var depth = 0;
    for (var i = 0; i < item.length; i++) {
      if (item[i] == '(') depth++;
      if (item[i] == ')') {
        depth--;
        if (depth == 0 && i != item.length - 1) return false;
      }
    }
    return depth == 0;
  }

  /// 归一化标识符侧：去反引号与全部空白 → 大写。非标识符形状
  /// （word 或 qualifier.word，每段字母/下划线开头）返回 null。
  static String? _normalizeIdentifier(String side) {
    final norm = side
        .replaceAll('`', '')
        .replaceAll(RegExp(r'\s'), '')
        .toUpperCase();
    if (!RegExp(r'^[A-Z_]\w*(\.[A-Z_]\w*)*$').hasMatch(norm)) return null;
    return norm;
  }
}
