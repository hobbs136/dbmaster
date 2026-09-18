//! 安全审查规则 R7（Pro）：SQL 注入风险检测。
//!
//! 保守检测明确的注入特征。所有 finding 都是 high 严重度。
//!
//! 关键约束：部分检测必须在 **原始未清洗** SQL 上做——cleanForAnalysis
//! 会删除注释 + 把 'x'='x' 变成 ' '=' '，破坏注入特征。
//! - 永真式：raw SQL（cleaned 会把 'x'='x' 剥成 ' '=' '）
//! - 注释截断：raw SQL（cleaned 会删除注释）
//! - 可疑 hex：cleaned SQL（字符串内的 hex 是数据，应被剥离）

import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

/// Pro 规则 R7：SQL 注入风险检测。
///
/// 保守策略：只匹配明确的注入 payload 模式，不做启发式猜测。
/// 误报会直接降低用户信任——注入指控比性能问题更重，宁可漏报不误报。
class SqlInjectionRule implements SafetyRule {
  @override
  final String id = 'sql_injection';

  /// hex 串长度阈值（>= 此长度才报）。
  /// 默认 16，过滤正常的短 hex（0xFF / 0xFFFF 等）。
  final int hexLengthThreshold;

  SqlInjectionRule({this.hexLengthThreshold = 16});

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      final findings = <SafetyFinding>[];

      // 模式 1：永真式 —— 在 **原始** SQL 上检测。
      // cleanForAnalysis 会把 'x'='x' 剥成 ' '=' '，破坏该特征。
      // 匹配：OR 1=1 / OR 'x'='x' / OR true / OR 1（单独数字）
      final tautology = RegExp(
        r"\bOR\s+(?:\d+\s*=\s*\d+|'[^']*'\s*=\s*'[^']*'|true\b|\d+\b)",
        caseSensitive: false,
      );
      if (tautology.hasMatch(sql)) {
        findings.add(SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: '检测到永真式（OR 1=1 类）——可能的注入特征',
          description: 'WHERE 条件中的永真式（如 OR 1=1）会使条件恒成立，'
              '是 SQL 注入绕过认证的经典手法。请确认此 SQL 来源可信。',
        ));
      }

      // 模式 2：注释截断 —— 在 **原始** SQL 上检测（cleaned 会删除注释）。
      // 锚定引号/分号/右括号后跟注释：'; -- 、 ') # 、 /* ... */
      // 区分正常行注释（-- 查询用户 无此前缀）。
      // 用 \x27/\x22 在 raw string 里表示引号，避免转义冲突。
      final commentTruncation = RegExp(
        r"[\x27\x22);]\s*(?:--|#)|/\*.*?\*/",
      );
      if (commentTruncation.hasMatch(sql)) {
        findings.add(SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: '检测到注释截断特征——可能的注入',
          description: 'SQL 中出现引号/分号/括号后紧跟注释（-- / # / /* */），'
              '这是注释截断原查询语义的注入手法。请确认 SQL 来源可信。',
        ));
      }

      // 模式 3：可疑 hex 编码 —— 在 **cleaned** SQL 上检测。
      // 字符串内的 hex 是数据（如 WHERE note='0xabc'），cleaned 会剥离它们。
      // 裸露在 SQL 中的长 hex 串（0x + 长位）常用于编码绕过。
      final cleaned = SQLParserService.cleanForAnalysis(sql);
      final hex = RegExp('0x[0-9a-fA-F]{$hexLengthThreshold,}');
      if (hex.hasMatch(cleaned)) {
        findings.add(SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: '检测到长十六进制编码——可能的注入载荷',
          description: 'SQL 中的长 hex 串（0x...）常用于绕过过滤传递编码 payload。'
              '请确认此值用途。',
        ));
      }

      return findings;
    } catch (_) {
      // 规则异常 → 返回空（引擎也兜底 catch）。
      return [];
    }
  }
}
