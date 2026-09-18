//! 安全审查规则（B6 T12）：WHERE 互补 OR 恒真检测。
//!
//! dbx sql_risk 同款检测面：`x IS NULL OR x IS NOT NULL`、`x=1 OR x<>1`、
//! 单值 IN 互补（`x IN (1) OR x NOT IN (1)`）。互补 OR 使条件恒成立——
//! DELETE/UPDATE 借此波及全表，注入载荷借此绕过预期过滤。
//!
//! 实现走 `extractWhereClause`（cleanForAnalysis 产物：注释/字符串已剥离）
//! → 括号深度感知的顶层 OR 拆支 → 支间两两互补配对（OR 链中含一对
//! 互补即整条恒真）。
//!
//! 保守边界（宁可漏报不误报，v1 只做可确证形态，不做 low 分级）：
//! - 比较符互补仅认同列同值：`=`↔`<>`/`!=`、`<`↔`>=`、`>`↔`<=`；
//! - 字符串值不参与配对（清洗后 `'a'` 与 `'b'` 都折叠成 `' '`，原文
//!   不可分辨，归 SqlInjectionRule 检测面）；
//! - NULL 作值不配对（`x=NULL OR x<>NULL` 两支皆 unknown，非可确证恒真）；
//! - 多值 IN（`IN (1,2)`）v1 不认（补集关系复杂，误报面大）；
//! - 支内含 AND / 嵌套 OR（如 `(a=1 OR a<>1) AND b=2`）不是单谓词
//!   形状，直接跳过；
//! - OR 锚定的 `OR 1=1` 是 SqlInjectionRule 的检测面（`name='x' OR 1=1`
//!   非互补对，本规则不报）。
//! 互补恒真是引擎无关语义，无引擎门控。B1 引擎 UI 注册接线归 T14。

import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

class ComplementaryOrRule implements SafetyRule {
  @override
  final String id = 'complementary_or';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      final whereClause = SQLParserService.extractWhereClause(sql);
      if (whereClause == null) return [];

      final branches = _splitTopLevelOr(whereClause);
      if (branches.length < 2) return [];

      // 支间两两配对找互补对；命中即整条 WHERE 恒真。
      final hits = <String>[];
      for (var a = 0; a < branches.length; a++) {
        for (var b = a + 1; b < branches.length; b++) {
          if (_isComplementaryPair(branches[a], branches[b])) {
            hits.add('${branches[a].trim()} OR ${branches[b].trim()}');
          }
        }
      }
      if (hits.isEmpty) return [];

      final examples = hits.take(2).map((t) => '`$t`').join('、');
      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: 'WHERE 条件中存在 ${hits.length} 处互补 OR 恒真（如 $examples）',
          description: '互补 OR（如 x IS NULL OR x IS NOT NULL、x=1 OR x<>1）'
              '使条件恒成立：DELETE/UPDATE 会波及全表，注入载荷可借此绕过'
              '预期过滤。请确认该语句来源可信且影响范围符合预期。',
        ),
      ];
    } catch (_) {
      // 规则异常 → 返回空（引擎也兜底 catch）。
      return [];
    }
  }

  /// 括号深度感知的顶层 OR 拆分：括号内的 OR 不是拆分点。
  static List<String> _splitTopLevelOr(String text) {
    final items = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var i = 0;
    while (i < text.length) {
      final char = text[i];
      if (char == '(') depth++;
      if (char == ')' && depth > 0) depth--;

      if (depth == 0 && _matchesWord(text, i, 'OR')) {
        items.add(buffer.toString());
        buffer.clear();
        i += 2;
        continue;
      }
      buffer.write(char);
      i++;
    }
    items.add(buffer.toString());
    return items;
  }

  /// text[i] 起是否是独立关键字 word（前后均为词边界，大小写无关）。
  /// 词边界保证 `password` 内的 or 不被当成 OR。
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

  /// 两支是否构成互补对：同列 + 互补形态（IS NULL ↔ IS NOT NULL /
  /// 单值 IN ↔ NOT IN / 互补比较符）+ 值形态时同值。
  static bool _isComplementaryPair(String rawA, String rawB) {
    final pa = _parsePredicate(rawA);
    if (pa == null) return false;
    final pb = _parsePredicate(rawB);
    if (pb == null) return false;
    if (pa.column != pb.column) return false;

    // x IS NULL ↔ x IS NOT NULL。
    if ((pa.op == 'IS NULL' && pb.op == 'IS NOT NULL') ||
        (pa.op == 'IS NOT NULL' && pb.op == 'IS NULL')) {
      return true;
    }
    // 单值 IN ↔ NOT IN。
    if ((pa.op == 'IN' && pb.op == 'NOT IN') ||
        (pa.op == 'NOT IN' && pb.op == 'IN')) {
      return pa.value == pb.value;
    }
    // 互补比较符（同列同值）：= 对 <>/!=，< 对 >=，> 对 <=。
    const complements = <String, List<String>>{
      '=': ['<>', '!='],
      '<>': ['='],
      '!=': ['='],
      '<': ['>='],
      '>=': ['<'],
      '>': ['<='],
      '<=': ['>'],
    };
    return complements[pa.op]?.contains(pb.op) == true &&
        pa.value == pb.value;
  }

  /// 解析单支为可配对谓词；非可确证形状（复合条件 / 函数调用 / 字符串
  /// 值 / 多值 IN 等）返回 null（保守跳过）。
  static _Pred? _parsePredicate(String raw) {
    var text = raw.trim();
    // 剥掉包住整支的平衡外层括号：(x=1) OR (x<>1)。
    while (text.length >= 2 &&
        text.startsWith('(') &&
        text.endsWith(')') &&
        _outerParensWrapAll(text)) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.isEmpty) return null;
    final u = text.toUpperCase();

    // x IS [NOT] NULL
    final isMatch = _isForm.firstMatch(u);
    if (isMatch != null) {
      final column = _normalizeIdentifier(isMatch.group(1)!);
      if (column == null) return null;
      return _Pred(
        column,
        isMatch.group(2) != null ? 'IS NOT NULL' : 'IS NULL',
        null,
      );
    }

    // x [NOT] IN (单值，值区不含逗号——多值 IN v1 不认)
    final inMatch = _inForm.firstMatch(u);
    if (inMatch != null) {
      final column = _normalizeIdentifier(inMatch.group(1)!);
      final value = _normalizeValue(inMatch.group(3)!);
      if (column == null || value == null) return null;
      return _Pred(
        column,
        inMatch.group(2) != null ? 'NOT IN' : 'IN',
        value,
      );
    }

    // x <op> <值>
    final cmpMatch = _cmpForm.firstMatch(u);
    if (cmpMatch != null) {
      final column = _normalizeIdentifier(cmpMatch.group(1)!);
      final value = _normalizeValue(cmpMatch.group(3)!);
      if (column == null || value == null) return null;
      return _Pred(column, cmpMatch.group(2)!, value);
    }
    return null;
  }

  /// 谓词形态（在 toUpperCase 文本上匹配；列允许限定名与反引号）。
  static final RegExp _isForm =
      RegExp(r'^(`?\w+`?(?:\.`?\w+`?)*)\s+IS\s+(NOT\s+)?NULL$');
  static final RegExp _inForm =
      RegExp(r'^(`?\w+`?(?:\.`?\w+`?)*)\s+(NOT\s+)?IN\s*\(\s*([^,()]+?)\s*\)$');
  static final RegExp _cmpForm =
      RegExp(r'^(`?\w+`?(?:\.`?\w+`?)*)\s*(<>|!=|<=|>=|=|<|>)\s*(.+)$');

  /// item 是否以 ( 开头、) 结尾且这对括号包住全文（`(a) AND (b)` 的外层
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

  /// 归一化比较值：数字 → 数值相等归一（1 与 1.0 同值）；标识符形状 →
  /// 前缀 + 归一标识。字符串占位符 / NULL / 非标识符形状返回 null
  /// （保守不配对——NULL 作值时两支结果均 unknown，非可确证互补）。
  static String? _normalizeValue(String raw) {
    final t = raw.trim();
    final numValue = double.tryParse(t);
    if (numValue != null) return 'n:${numValue.toString()}';
    final ident = _normalizeIdentifier(t);
    if (ident == null) return null;
    if (ident == 'NULL' || ident == 'UNKNOWN') return null;
    return 'i:$ident';
  }
}

/// 一支解析后的谓词描述：归一列名 + 操作符 + 归一值（IS NULL 形态无值）。
class _Pred {
  final String column;
  final String op;
  final String? value;

  const _Pred(this.column, this.op, this.value);
}
