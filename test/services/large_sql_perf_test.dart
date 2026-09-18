/// 大 SQL 脚本性能回归守卫。
///
/// 背景（2026-08-14 生产 bug）：把 ~1MB 建表脚本粘贴进编辑器再执行，
/// UI 冻结数分钟。根因有二：
/// 1. `SQLParserService.split` 的 `_isDelimiterDirective` 对每个字符执行
///    `sql.substring(i).toUpperCase()`——每字符拷贝整个剩余文本，O(n²)。
///    执行链上至少 3 处同步调用 split（执行门 / TabProvider / DML 拦截器）。
/// 2. `SQLValidatorService.validate` 的关键词拼写检查在循环内逐字符构造
///    RegExp，且对长「词」（引号内整段中文 COMMENT）跑全关键词表 Levenshtein
///    DP——958K 字符耗时 4.6s（粘贴后 500ms 在 UI isolate 同步触发）。
///
/// 修复后（同机 958K 实测）：split 34ms / validate 408ms（validate 另在
/// 编辑器侧对 >20K 文本挪入后台 isolate）。
///
/// 本测试合成含注释/引号串/反引号的大脚本（解析器全路径覆盖），用宽松
/// 上限断言防 O(n²) 复发（宽松到慢 CI 也不误报，但远低于回归后的量级）。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_parser_service.dart';
import 'package:dbmaster/services/sql_validator_service.dart';

String _buildLargeScript(int tableCount) {
  final sb = StringBuffer();
  sb.writeln('-- DBMaster Database Export');
  sb.writeln('-- Database: perf_guard');
  for (var t = 0; t < tableCount; t++) {
    sb.writeln('-- Table: perf_table_$t');
    sb.writeln('CREATE TABLE `perf_table_$t` (');
    sb.writeln('  `id` bigint NOT NULL AUTO_INCREMENT COMMENT \'自增主键\',');
    sb.writeln('  `name` varchar(64) NOT NULL COMMENT \'名称: user/assistant/tool\',');
    sb.writeln('  `payload` text COMMENT \'消息内容\',');
    sb.writeln('  `create_time` datetime DEFAULT CURRENT_TIMESTAMP,');
    sb.writeln('  PRIMARY KEY (`id`)');
    sb.writeln(') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;');
    sb.writeln();
  }
  return sb.toString();
}

void main() {
  test('split 大脚本保持线性（O(n²) 回归守卫）', () {
    final sql = _buildLargeScript(500); // ~55K chars，回归时此规模需 >30s
    final sw = Stopwatch()..start();
    final statements = SQLParserService.split(sql);
    final elapsed = sw.elapsedMilliseconds;

    expect(statements.length, 500, reason: '语句切分数量应正确');
    expect(
      elapsed < 2000,
      isTrue,
      reason: 'split 55K 字符应在 2s 内完成（修复前 O(n²) 需数十秒），'
          '实际 ${elapsed}ms',
    );
  });

  test('validate 大脚本保持可承受（长词 Levenshtein 回归守卫）', () {
    final sql = _buildLargeScript(500);
    final sw = Stopwatch()..start();
    SQLValidatorService.validate(sql);
    final elapsed = sw.elapsedMilliseconds;

    expect(
      elapsed < 2000,
      isTrue,
      reason: 'validate 55K 字符应在 2s 内完成（修复前同规模数秒级），'
          '实际 ${elapsed}ms',
    );
  });

  test('DELIMITER 指令解析语义不变（大小写无关）', () {
    // _isDelimiterDirective 从 substring+toUpperCase 改为逐字符比较，
    // 此处守卫大小写无关语义与正常切分不被破坏。
    final sql = 'SELECT 1;\ndelimiter \$\$\nSELECT 2\$\$\nDELIMITER ;\nSELECT 3;';
    final statements = SQLParserService.split(sql);

    expect(statements.map((s) => s.sql.trim()), contains('SELECT 1'));
    expect(statements.map((s) => s.sql.trim()), contains('SELECT 2'));
    expect(statements.map((s) => s.sql.trim()), contains('SELECT 3'));
  });
}
