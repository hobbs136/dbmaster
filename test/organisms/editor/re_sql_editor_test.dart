// T17/T18 · re_editor 新编辑器组件单测。
//
// 覆盖：ReSqlEditorController 门面语义（程序化设值静默 / 用户编辑回调 /
// loadText 清 undo / 选区与光标 API）、ReAutocompleteBridge 桥接
// （片段触发、token 扫描、异步刷新代际守卫、prompts 非空不变量）、
// ReSqlEditorTheme 主题映射（单语言注册）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:dbmaster/models/code_snippet.dart' show SnippetDbFamily;
import 'package:dbmaster/organisms/editor/re_code_autocomplete.dart';
import 'package:dbmaster/organisms/editor/re_editor_theme.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor_controller.dart';
import 'package:dbmaster/services/sql_autocomplete_service.dart';

void main() {
  group('ReSqlEditorController 门面', () {
    test('text 设值可读回且光标落文末', () {
      final c = ReSqlEditorController();
      c.text = 'SELECT 1\nFROM t';
      expect(c.text, 'SELECT 1\nFROM t');
      expect(c.codeController.selection.extentIndex, 1);
      expect(c.codeController.selection.extentOffset, 'FROM t'.length);
      c.dispose();
    });

    test('相同文本重复设值为 no-op', () {
      final c = ReSqlEditorController(text: 'A');
      var notified = 0;
      c.codeController.addListener(() => notified++);
      c.text = 'A';
      expect(notified, 0);
      c.dispose();
    });

    test('程序化设值不触发 text-change 回调（onChanged 平价）', () {
      final c = ReSqlEditorController();
      var fired = 0;
      c.addTextChangeListener((_) => fired++);
      c.text = 'SELECT 1';
      expect(fired, 0, reason: 'facade.text= 是程序化设值，应静默');
      c.loadText('SELECT 2');
      expect(fired, 0, reason: 'loadText 是程序化设值，应静默');
      c.dispose();
    });

    test('用户编辑（内部控制器写入）触发 text-change 回调', () {
      final c = ReSqlEditorController(text: 'abc');
      var lastText = '';
      c.addTextChangeListener((t) => lastText = t);
      // 模拟用户编辑路径：绕过门面 flag 的内层写入（undo/IME/键盘均走此层）。
      c.codeController.text = 'abcdef';
      expect(lastText, 'abcdef');
      c.dispose();
    });

    test('loadText 清空 undo 历史（tab 切换防跨 tab 撤销）', () {
      final c = ReSqlEditorController();
      c.text = 'SELECT 1';
      expect(c.codeController.canUndo, isTrue, reason: 'text= 是可撤销操作');
      c.loadText('SELECT 2');
      expect(c.codeController.canUndo, isFalse, reason: 'loadText 应清空 undo');
      c.dispose();
    });

    test('选区 API：selectAll / selectedText / hasSelection', () {
      final c = ReSqlEditorController(text: 'SELECT 1\nFROM t');
      expect(c.hasSelection, isFalse);
      c.selectAll();
      expect(c.hasSelection, isTrue);
      expect(c.selectedText, 'SELECT 1\nFROM t');
      c.dispose();
    });

    test('insertAtCursor 在光标处插入并落位', () {
      final c = ReSqlEditorController(text: 'SELECT 1');
      c.codeController.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 8,
      );
      c.insertAtCursor(' WHERE x');
      expect(c.text, 'SELECT 1 WHERE x');
      expect(c.codeController.selection.extentOffset, 'SELECT 1 WHERE x'.length);
      c.dispose();
    });

    test('cursorLine / cursorColumn / cursorAbsoluteOffset', () {
      final c = ReSqlEditorController(text: 'SELECT 1\nFROM t');
      c.codeController.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 3,
      );
      expect(c.cursorLine, 2);
      expect(c.cursorColumn, 4);
      expect(c.cursorAbsoluteOffset, 'SELECT 1\n'.length + 3);
      c.dispose();
    });
  });

  group('ReAutocompleteBridge', () {
    testWidgets('片段触发：/trigger 返回片段 prompts，input 含斜杠', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        builder: (context, _) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ));
      final controller = ReSqlEditorController();
      final bridge = ReAutocompleteBridge(controller: controller)
        ..snippetsEnabled = true
        ..snippetFamily = SnippetDbFamily.sql
        ..enabled = true;

      final value = bridge.build(
        ctx,
        const CodeLine('SELECT * /sel'),
        const CodeLineSelection.collapsed(index: 0, offset: 13),
      );
      expect(value, isNotNull);
      expect(value!.input, contains('/'), reason: 'input 应覆盖 "/sel" 整段触发词');
      expect(
        value.prompts.whereType<ReSnippetPrompt>(),
        isNotEmpty,
        reason: '应返回片段命令（sel → SELECT 语句）',
      );
      final selPrompt = value.prompts
          .whereType<ReSnippetPrompt>()
          .firstWhere((p) => p.command.command == 'sel');
      expect(selPrompt.autocomplete.word, contains('SELECT'));
      controller.dispose();
    });

    testWidgets('无片段触发且禁用补全时返回 null', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        builder: (context, _) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ));
      final controller = ReSqlEditorController();
      final bridge = ReAutocompleteBridge(controller: controller)
        ..snippetsEnabled = false
        ..enabled = false;

      expect(
        bridge.build(
          ctx,
          const CodeLine('SELECT * FROM t'),
          const CodeLineSelection.collapsed(index: 0, offset: 10),
        ),
        isNull,
      );
      controller.dispose();
    });

    testWidgets('token 扫描 + prompts 非空不变量（resolver 空结果回退占位）', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        builder: (context, _) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ));
      final controller = ReSqlEditorController(text: 'SELECT * FROM us');
      controller.codeController.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 16,
      );
      final bridge = ReAutocompleteBridge(controller: controller)
        ..snippetsEnabled = false
        ..enabled = true
        ..resolver = (text, cursor) async {
          return const <Suggestion>[];
        };

      final value = bridge.build(
        ctx,
        const CodeLine('SELECT * FROM us'),
        const CodeLineSelection.collapsed(index: 0, offset: 16),
      );
      expect(value, isNotNull);
      expect(value!.input, 'us', reason: 'token = 光标前连续词');
      expect(value.prompts, isNotEmpty, reason: 'prompts 恒非空（键盘导航安全）');
      expect(value.prompts.first, isA<RePendingPrompt>());
      controller.dispose();
    });

    testWidgets('异步刷新经 notifier 原位更新 prompts', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        builder: (context, _) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ));
      final controller = ReSqlEditorController(text: 'SELECT * FROM us');
      controller.codeController.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 16,
      );
      final bridge = ReAutocompleteBridge(controller: controller)
        ..snippetsEnabled = false
        ..enabled = true
        ..resolver = (text, cursor) async {
          expect(text, 'SELECT * FROM us');
          expect(cursor, 16);
          return [
            Suggestion(text: 'users', type: SuggestionType.table),
          ];
        };

      final value = bridge.build(
        ctx,
        const CodeLine('SELECT * FROM us'),
        const CodeLineSelection.collapsed(index: 0, offset: 16),
      );
      // 模拟弹窗视图（_ReAutocompleteViewState）持有 notifier 拉取刷新。
      final notifier = ValueNotifier<CodeAutocompleteEditingValue>(value!);
      await bridge.refreshSuggestions(notifier);

      expect(
        notifier.value.prompts.first,
        isA<ReSuggestionPrompt>(),
        reason: '视图拉取后原位刷新为真实建议',
      );
      expect(
        (notifier.value.prompts.first as ReSuggestionPrompt).suggestion.text,
        'users',
      );

      // 空结果保持占位（非空不变量）。
      bridge.resolver = (text, cursor) async => const <Suggestion>[];
      final notifier2 = ValueNotifier<CodeAutocompleteEditingValue>(
        bridge.build(
          ctx,
          const CodeLine('SELECT * FROM xy'),
          const CodeLineSelection.collapsed(index: 0, offset: 16),
        )!,
      );
      await bridge.refreshSuggestions(notifier2);
      expect(notifier2.value.prompts.first, isA<RePendingPrompt>());

      notifier.dispose();
      notifier2.dispose();
      controller.dispose();
    });
  });

  group('ReSqlEditorTheme', () {
    testWidgets('单语言注册（避免 highlightAuto 误判）', (tester) async {
      late BuildContext dark;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, _) {
          dark = context;
          return const SizedBox.shrink();
        },
      ));
      final theme = ReSqlEditorTheme.highlightTheme(dark, 'sql');
      expect(theme.languages.keys, ['sql']);
      expect(theme.theme['keyword'], isNotNull);
      expect(theme.theme['string'], isNotNull);
      expect(theme.theme['comment']!.fontStyle, FontStyle.italic);

      final style = ReSqlEditorTheme.style(dark, 'sql');
      expect(style.codeTheme, isNotNull);
      expect(style.fontSize, 13.0);
    });
  });
}
