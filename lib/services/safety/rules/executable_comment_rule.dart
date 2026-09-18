//! 安全审查规则（B6 T10）：MySQL 可执行注释检测。
//!
//! `/*! ... */`（含带版本前缀的 `/*!50003 ... */`）在 MySQL 协议族引擎上
//! 是**会被执行的语句**，在其他引擎上只是普通注释。攻击者可把写操作藏在
//! 看似无害的注释里，绕过目测检查和「剥注释后做关键字检测」的审查器
//! （cleanForAnalysis 曾把它们当噪音剥掉——正是本规则堵的盲区）。
//!
//! 检测在**原始** SQL 上做（split 后的语句文本保留可执行注释原样），
//! 并跳过字符串字面量 / 反引号标识符 / 行注释内的伪特征（那是数据，
//! 不是注释）。MariaDB 的 `/*M! ... */` 变体 v1 不覆盖。

import '../../../models/database_models.dart' show DatabaseType;
import '../safety_finding.dart';
import '../safety_rule.dart';

class ExecutableCommentRule implements SafetyRule {
  @override
  final String id = 'executable_comment';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      // 只在 MySQL 协议族上报：其它引擎把 /*! */ 当普通注释忽略，
      // 上报即误报（规则纪律：宁可漏报不误报）。MariaDB 类型落地后补入。
      final t = context.dbType;
      if (t != DatabaseType.mysql && t != DatabaseType.doris) return [];

      final count = _countExecutableComments(sql);
      if (count == 0) return [];

      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: '检测到 $count 处 MySQL 可执行注释（/*! ... */）',
          description: 'MySQL 会执行版本注释 /*! ... */ 内嵌的语句（其他数据库'
              '将其视为普通注释忽略）。语句可能借此藏在看似无害的注释中，'
              '绕过基于关键字的检查。请确认注释内的内容可信。',
        ),
      ];
    } catch (_) {
      // 规则异常 → 返回空（引擎也兜底 catch）。
      return [];
    }
  }

  /// 统计字符串/反引号/行注释之外、已闭合且去版本前缀后仍有内容的
  /// `/*! ... */` 数量。
  static int _countExecutableComments(String sql) {
    var count = 0;
    var i = 0;
    while (i < sql.length) {
      final char = sql[i];

      // 字符串字面量与反引号标识符内的是数据，不是注释。
      if (char == "'" || char == '"' || char == '`') {
        i = _skipQuoted(sql, i, char);
        continue;
      }

      // 行注释内的 /*! 是注释文字。
      if (char == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
        i += 2;
        while (i < sql.length && sql[i] != '\n') {
          i++;
        }
        continue;
      }
      if (char == '#') {
        i++;
        while (i < sql.length && sql[i] != '\n') {
          i++;
        }
        continue;
      }

      if (char == '/' &&
          i + 2 < sql.length &&
          sql[i + 1] == '*' &&
          sql[i + 2] == '!') {
        final end = sql.indexOf('*/', i + 3);
        // 未闭合：引擎会报语法错误，整个语句不会执行，不计。
        if (end < 0) break;
        final body = sql.substring(i + 3, end);
        // 去掉版本前缀后仍有内容才计（/*!50003*/ 不含语句）。
        final content = body.replaceFirst(RegExp(r'^\d+'), '').trim();
        if (content.isNotEmpty) count++;
        i = end + 2;
        continue;
      }

      i++;
    }
    return count;
  }

  /// 跳过一段引号文本（支持反斜杠转义与双写引号转义），返回右引号后位置。
  static int _skipQuoted(String sql, int start, String quote) {
    var i = start + 1;
    while (i < sql.length) {
      if (sql[i] == '\\') {
        i += 2;
        continue;
      }
      if (sql[i] == quote) {
        if (i + 1 < sql.length && sql[i + 1] == quote) {
          i += 2; // 双写引号转义
          continue;
        }
        return i + 1;
      }
      i++;
    }
    return i; // 未闭合引号——保守跳到末尾
  }
}
