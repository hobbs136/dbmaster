// ============================================================================
// re_editor 行号换算性能守卫（P3 长尾核销实证，2026-08-25）
//
// 旧 TextField 编辑器时代「点击大文档 → _calculateCurrentLine 全文字符扫描
// ~百ms」是已知 P3 遗留（COMPLETED_LOG 2026-08-14「明确不做」段）。
// re_editor 迁移（76bd284e）后该路径已被根治：行号 = selection.extentIndex
// （逻辑行索引 O(1)）→ index2lineIndex 段级缓存折算（微秒级，整数加法）。
// 本测试钉死该性质，防未来有人退回全文字符扫描。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:dbmaster/organisms/editor/re_sql_editor_controller.dart';

void main() {
  // 12,849 行 = 2026-08-14 大脚本卡死实测规模（958K 字符 / 402 表）。
  const lineCount = 12849;

  String buildDoc() => List<String>.generate(
        lineCount,
        (i) => 'CREATE TABLE perf_t_$i (id bigint NOT NULL);',
      ).join('\n');

  group('re_editor 行号换算（大文档）', () {
    test('末行点击：index2lineIndex 百次换算总耗时 < 50ms（实测微秒级）', () {
      final c = ReSqlEditorController(text: buildDoc());
      // 模拟点击文末：选区落到最后一行中段。
      c.codeController.selection = const CodeLineSelection.collapsed(
        index: lineCount - 1,
        offset: 10,
      );

      final sw = Stopwatch()..start();
      var line = 0;
      for (var i = 0; i < 100; i++) {
        // 与 re_sql_editor._handleSelectionChange 同路径。
        line = c.codeController.index2lineIndex(
              c.codeController.selection.extentIndex,
            ) +
            1;
      }
      sw.stop();

      expect(line, lineCount, reason: '末行行号应为 $lineCount');
      expect(
        sw.elapsedMilliseconds,
        lessThan(50),
        reason: '100 次末行行号换算应远低于旧全量扫描单次成本（~百ms）；'
            '若劣化说明有人退回了全文字符扫描',
      );
      c.dispose();
    });

    test('cursorLine 门面 O(1)：千次访问 < 50ms', () {
      final c = ReSqlEditorController(text: buildDoc());
      c.codeController.selection = const CodeLineSelection.collapsed(
        index: lineCount - 1,
        offset: 0,
      );

      final sw = Stopwatch()..start();
      var sum = 0;
      for (var i = 0; i < 1000; i++) {
        sum += c.cursorLine;
      }
      sw.stop();

      expect(sum, lineCount * 1000);
      expect(sw.elapsedMilliseconds, lessThan(50));
      c.dispose();
    });

    test('首行/中行/末行跳转行号正确（段边界）', () {
      final c = ReSqlEditorController(text: buildDoc());
      for (final target in [0, 256, 6000, lineCount - 1]) {
        c.codeController.selection = CodeLineSelection.collapsed(
          index: target,
          offset: 0,
        );
        expect(c.cursorLine, target + 1);
        expect(
          c.codeController.index2lineIndex(target) + 1,
          target + 1,
          reason: '无软换行时视觉行号 = 逻辑行号',
        );
      }
      c.dispose();
    });
  });
}
