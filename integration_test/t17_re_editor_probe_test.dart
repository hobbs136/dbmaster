// T17 · re_editor 迁移探针：大文本性能 + 真键内建快捷键验证。
//
// 背景：widget 测试发现合成键事件触发不了 re_editor 内层 Shortcuts
// （其 Focus 节点不在外部焦点节点祖先链上；外层包装正常）。本探针在
// 集成环境（真实 Windows 窗口 + 真实键分发）验证：
//   1. 958K 装载首帧 + settle 窗口最差单帧（行式渲染性能关卡）
//   2. 真键 Ctrl+A 全选（re_editor 内建快捷键链真机有效性）
//   3. 真键 Ctrl+Z 撤销（undo 语义）
//   4. 打字触发补全弹窗（CodeAutocomplete 链路）
//   5. 程序化 loadText（tab 切换语义）
//
// 离线运行（无需数据库连接）：
//   flutter test -d windows integration_test/t17_re_editor_probe_test.dart --profile
//
// 输出行格式：[T17-PROBE] <场景> <动作>=<ms>ms / [T17-VERIFY] <断言>

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// 与 t02 探针同构的合成脚本生成器（~2.4KB/表，含中文 COMMENT）。
String _buildLargeScript(int tableCount) {
  final sb = StringBuffer();
  sb.writeln('-- DBMaster Database Export');
  sb.writeln('-- Database: t17_probe');
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      if (t.totalSpan.inMilliseconds > 300) {
        debugPrint(
          '[T17-FRAME] build=${t.buildDuration.inMilliseconds}ms '
          'raster=${t.rasterDuration.inMilliseconds}ms '
          'total=${t.totalSpan.inMilliseconds}ms');
      }
    }
  });

  testWidgets('T17 探针：re_editor 大文本 + 真键内建快捷键', (tester) async {
    final sql = _buildLargeScript(3000); // t02 口径：958K（975,831 字符）
    debugPrint('[T17-PROBE] text_length=${sql.length}');

    AppProvider.devBypassGates = true;
    final provider = AppProvider();
    await provider.tab.openQueryTab(
      connectionId: 't17_probe_offline',
      databaseName: 't17_probe',
    );
    provider.setActiveTab(0);

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
          ),
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ],
        child: MaterialApp(
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(themeProvider.accentColorValue),
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 800,
              child: const QueryEditorWidget(tabIndex: 0),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final state = tester.state<QueryEditorWidgetState>(
      find.byType(QueryEditorWidget),
    );
    final editor = state.controller;

    // ── 动作 1：大文本装载首帧 + settle 窗口 ──
    final swLoad = Stopwatch()..start();
    editor.text = sql;
    await tester.pump();
    debugPrint('[T17-PROBE] load_first_frame=${swLoad.elapsedMilliseconds}ms');

    var worstFrameMs = 0;
    for (var i = 0; i < 8; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 500));
      final ms = sw.elapsedMilliseconds;
      if (ms > worstFrameMs) worstFrameMs = ms;
    }
    debugPrint('[T17-PROBE] settle_window_worst_frame=${worstFrameMs}ms');

    // ── 动作 1b：清空后真实 Ctrl+V 粘贴（用户原始「卡死」路径）──
    editor.loadText('');
    await tester.pump();
    await Clipboard.setData(ClipboardData(text: sql));
    await tester.tapAt(tester.getCenter(find.byType(ReSqlEditor)));
    await tester.pump(const Duration(milliseconds: 300));
    final swVPaste = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    debugPrint('[T17-PROBE] real_ctrl_v_first_frame=${swVPaste.elapsedMilliseconds}ms');
    var vWorst = 0;
    for (var i = 0; i < 8; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 500));
      final ms = sw.elapsedMilliseconds;
      if (ms > vWorst) vWorst = ms;
    }
    debugPrint('[T17-PROBE] real_ctrl_v_settle_worst=${vWorst}ms');
    debugPrint('[T17-VERIFY] after_paste_len=${editor.text.length}');
    expect(editor.text.length, sql.length, reason: '真实 Ctrl+V 应完整粘入 958K');

    // ── 动作 2：聚焦 + 真键 Ctrl+A（re_editor 内建快捷键链验证）──
    final editorCenter = tester.getCenter(find.byType(ReSqlEditor));
    await tester.tapAt(editorCenter);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA,
        physicalKey: PhysicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 300));
    final selectedLen = editor.selectedText.length;
    debugPrint('[T17-VERIFY] ctrl_a_selected_len=$selectedLen '
        '(text=${sql.length})');
    expect(selectedLen, sql.length,
        reason: '真键 Ctrl+A 应触发 re_editor 内建 selectAll');

    // ── 动作 3：真键 Ctrl+Z 撤销 programmatic 设值（facade.text= 可撤销）──
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ,
        physicalKey: PhysicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('[T17-VERIFY] after_undo_len=${editor.text.length}');
    expect(editor.text.length, 0,
        reason: '真键 Ctrl+Z 应撤销 958K 装载（facade.text= 进 undo 历史）');

    // ── 动作 4：IME 入口文本管线（edit() = TextInput 客户端更新路径）──
    // 集成环境无法注入平台 IME 增量（TestTextInput 在 live binding 不挂载、
    // 合成键事件不产生文本），补全弹窗视觉链路（定位/键盘导航/IME 避让）
    // 由 re_editor 内建 + re_sql_editor_test 单测覆盖，真机打字归人工清单。
    // 此处验证可自动化的一半：edit() → 门面 text-change → 防抖 → 持久化。
    await tester.tapAt(tester.getCenter(find.byType(ReSqlEditor)));
    await tester.pump(const Duration(milliseconds: 300));
    editor.codeController.edit(const TextEditingValue(
      text: 'se',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange.empty,
    ));
    await tester.pump(const Duration(milliseconds: 800));
    debugPrint('[T17-VERIFY] ime_text_after_edit=\\"${editor.text}\\"');
    expect(editor.text, 'se');
    await tester.pump(const Duration(milliseconds: 500));
    final tabSql = provider.tabs[0].sql;
    debugPrint('[T17-VERIFY] provider_tab_sql_after_edit=\\"$tabSql\\"');
    expect(tabSql, 'se',
        reason: 'edit() 路径的文本变更应经门面回调进入 updateTabSql 防抖管线');

    // ── 动作 5：程序化 loadText（tab 切换语义）+ 光标归零 ──
    editor.loadText('SELECT 1\nFROM t');
    await tester.pump();
    debugPrint('[T17-VERIFY] load_text=${editor.text.length} chars');
    expect(editor.text, 'SELECT 1\nFROM t');
    expect(editor.codeController.selection.extentIndex, 0);

    debugPrint('[T17-PROBE] done');
  });
}
