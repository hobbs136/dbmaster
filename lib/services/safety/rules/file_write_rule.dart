//! 安全审查规则（B6 T11）：SQL 文件系统访问检测。
//!
//! dbx sql_risk 同款检测面：`INTO OUTFILE / DUMPFILE`（把查询结果写入
//! 数据库服务器文件——数据外带原语）与 `LOAD_FILE()`（把服务器文件读进
//! 结果集）。两者均为 MySQL 语法/函数，非 MySQL 协议族引擎上无从执行，
//! 上报即误报，故门控 mysql/doris（同 ExecutableCommentRule 的门控纪律）。
//!
//! 在 cleanForAnalysis 产物上做正则——字符串/注释里的伪特征已被剥离，
//! 而可执行注释内的载荷因 T10 解包保留仍可见（纵深防御）。
//! PG 的 `COPY ... TO` 语义等价，但不在方案 §2.3 检测面内，v1 不做。
//! B1 引擎 UI 注册接线归 T14。

import '../../../models/database_models.dart' show DatabaseType;
import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

class FileWriteRule implements SafetyRule {
  @override
  final String id = 'file_write';

  static final _intoFile = RegExp(
    r'\bINTO\s+(?:OUTFILE|DUMPFILE)\b',
    caseSensitive: false,
  );
  static final _loadFile = RegExp(
    r'\bLOAD_FILE\s*\(',
    caseSensitive: false,
  );

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      // 只在 MySQL 协议族上报：INTO OUTFILE/LOAD_FILE 是 MySQL 语法，
      // 其它引擎直接报语法错误，语句不会执行。
      final t = context.dbType;
      if (t != DatabaseType.mysql && t != DatabaseType.doris) return [];

      final cleaned = SQLParserService.cleanForAnalysis(sql);
      final count =
          _intoFile.allMatches(cleaned).length + _loadFile.allMatches(cleaned).length;
      if (count == 0) return [];

      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: '检测到 $count 处文件系统访问（INTO OUTFILE/DUMPFILE、LOAD_FILE）',
          description: 'INTO OUTFILE/DUMPFILE 会把查询结果写入数据库服务器'
              '的文件，LOAD_FILE() 则把服务器文件读进结果集——是数据外带'
              '（exfiltration）的典型原语，需要 FILE 权限且受 '
              'secure_file_priv 限制。请确认语句来源可信、目标路径合规。',
        ),
      ];
    } catch (_) {
      // 规则异常 → 返回空（引擎也兜底 catch）。
      return [];
    }
  }
}
