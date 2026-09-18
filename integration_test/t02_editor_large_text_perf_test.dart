// T02 自动化探针：大文本粘贴/重建/全选复制/点击 的真实帧耗时测量。
//
// 背景：用户 T02 手工实测报告「复制大文本直接卡死」。已知记档遗留项
// （COMPLETED_LOG 2026-08-14 明确不做段）提示单编辑器的一次性首排
// （958K 真机 debug 1-3s）是固有开销；「点击行号全量扫描」已随
// re_editor 迁移（76bd284e）根治（extentIndex 行索引 O(1)，见
// test/organisms/editor/re_sql_editor_perf_test.dart 守卫）。
// 2026-08-25 适配：探针从旧 TextField 迁移到 ReSqlEditor/CodeEditor。
// 本探针在集成测试环境（真实 Windows 字体 + 真实时间线）自动复现四个
// 动作并输出耗时，用于区分「一次性长卡（固有）」vs「反复/永久卡死（bug）」。
//
// 离线运行（无需数据库连接）：
//   flutter test -d windows integration_test/t02_editor_large_text_perf_test.dart
//   （Flutter 3.41 的 flutter test 已无 --profile 选项，桌面端 Debug JIT 运行；
//   探针目的是区分「固有长卡」vs「永久卡死」的量级，Debug 耗时记录即可）
//
// 输出行格式：[T02-PROBE] <场景> <动作>=<ms>ms

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor_controller.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

/// 与 test/services/large_sql_perf_test.dart 同构的合成脚本生成器
/// （注释/引号串/反引号/中文 COMMENT 全路径覆盖）。~2.4KB/表。
String _buildLargeScript(int tableCount) {
  final sb = StringBuffer();
  sb.writeln('-- DBMaster Database Export');
  sb.writeln('-- Database: t02_probe');
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

  // 帧级归因（profile 模式可用）：>300ms 的帧打印 build/raster 拆分。
  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      if (t.totalSpan.inMilliseconds > 300) {
        debugPrint(
          '[T02-FRAME] build=${t.buildDuration.inMilliseconds}ms '
          'raster=${t.rasterDuration.inMilliseconds}ms '
          'total=${t.totalSpan.inMilliseconds}ms');
      }
    }
  });

  Future<void> runScenario(WidgetTester tester, String label, String sql) async {
    debugPrint('[T02-PROBE] ===== $label (${sql.length} chars) =====');

    AppProvider.devBypassGates = true;
    final provider = AppProvider();
    await provider.tab.openQueryTab(
      connectionId: 't02_probe_offline',
      databaseName: 't02_probe',
    );
    provider.setActiveTab(0);

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    Widget buildHarness(Widget child) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
          ),
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ],
        child: Consumer2<LocaleProvider, ThemeProvider>(
          builder: (context, locale, theme, _) {
            return MaterialApp(
              locale: locale.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(theme.accentColorValue),
              home: Scaffold(
                body: SizedBox(width: 1280, height: 800, child: child),
              ),
            );
          },
        ),
      );
    }

    // 空编辑器首帧。
    provider.updateTabSql(0, '');
    await tester.pumpWidget(buildHarness(const QueryEditorWidget(tabIndex: 0)));
    await tester.pump(const Duration(seconds: 2));

    ReSqlEditorController? editorController() {
      final editor = tester.widget<ReSqlEditor>(
        find
            .descendant(
              of: find.byType(QueryEditorWidget),
              matching: find.byType(ReSqlEditor),
            )
            .first,
      );
      return editor.controller;
    }

    final controller = editorController();
    expect(controller, isNotNull, reason: '编辑器 ReSqlEditor controller 未找到');

    // ── 动作 1：粘贴（等价 setText：空编辑器整段插入）──
    final swPaste = Stopwatch()..start();
    controller!.text = sql;
    await tester.pump(); // 首帧 build+layout+paint
    final firstFrameMs = swPaste.elapsedMilliseconds;
    debugPrint('[T02-PROBE] $label paste_first_frame=${firstFrameMs}ms');

    // 防抖链观察窗（updateTabSql 200ms + validate 500ms + isolate 往返）。
    // 不用 pumpAndSettle：聚焦编辑器后光标闪烁会令其永不 settle。
    // 逐帧泵 4s，记录最差单帧——若 UI 冻结，单帧泵会阻塞并暴露。
    var worstFrameMs = 0;
    for (var i = 0; i < 8; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 500));
      final ms = sw.elapsedMilliseconds;
      if (ms > worstFrameMs) worstFrameMs = ms;
    }
    debugPrint('[T02-PROBE] $label settle_window_worst_frame=${worstFrameMs}ms');

    // ── 动作 1c（T02a 控制实验）：程序设值 + 聚焦 + 末尾光标（无剪贴板）──
    controller.clear();
    await tester.pump();
    controller.text = sql; // text= 语义：可撤销整体替换，光标自动落文末
    final editorCenter0 = tester.getCenter(
      find
          .descendant(
            of: find.byType(QueryEditorWidget),
            matching: find.byType(ReSqlEditor),
          )
          .first,
    );
    await tester.tapAt(editorCenter0); // 聚焦
    var cWorst = 0;
    final cLog = <int>[];
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 500));
      final ms = sw.elapsedMilliseconds;
      cLog.add(ms);
      if (ms > cWorst) cWorst = ms;
    }
    debugPrint('[T02-PROBE] $label programmatic_set+focus+caret_frames=$cLog');
    debugPrint('[T02-PROBE] $label programmatic_set+focus+caret_worst=${cWorst}ms');

    // ── 动作 1b：真实剪贴板粘贴（用户报告路径）——清空后经 Ctrl+V 恢复 ──
    controller.clear();
    await tester.pump();
    await Clipboard.setData(ClipboardData(text: sql));
    final editorCenter = tester.getCenter(
      find
          .descendant(
            of: find.byType(QueryEditorWidget),
            matching: find.byType(ReSqlEditor),
          )
          .first,
    );
    await tester.tapAt(editorCenter);
    await tester.pump(const Duration(milliseconds: 300));
    final swVPaste = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    final vPasteFrameMs = swVPaste.elapsedMilliseconds;
    debugPrint('[T02-PROBE] $label real_ctrl_v_first_frame=${vPasteFrameMs}ms');
    var vWorst = 0;
    final frameLog = <int>[];
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 500));
      final ms = sw.elapsedMilliseconds;
      frameLog.add(ms);
      if (ms > vWorst) vWorst = ms;
    }
    debugPrint('[T02-PROBE] $label real_ctrl_v_frames(500ms/格)=$frameLog');
    debugPrint('[T02-PROBE] $label real_ctrl_v_worst_frame=${vWorst}ms');
    expect(controller.text.length, sql.length,
        reason: 'Ctrl+V 后文本长度应一致（真实粘贴路径）');

    // ── 动作 2：同文本重建（2026-08-14 二轮卡死的触发形态：
    //    notifyListeners 重建但文本不变——span 缓存应吸收）──
    final swRebuild = Stopwatch()..start();
    provider.updateTabSql(0, sql);
    await tester.pump();
    final rebuildMs = swRebuild.elapsedMilliseconds;
    swRebuild.stop();
    debugPrint('[T02-PROBE] $label rebuild_same_text=${rebuildMs}ms');

    // ── 动作 3：点击文本中部（旧「行号全量扫描」路径；re_editor 后
    //    行号走 extentIndex 行索引 O(1)，此处验证点击无卡顿回归）──
    final editorBox = tester.renderObject<RenderBox>(
      find
          .descendant(
            of: find.byType(QueryEditorWidget),
            matching: find.byType(ReSqlEditor),
          )
          .first,
    );
    final center = editorBox.localToGlobal(Offset.zero) +
        Offset(editorBox.size.width / 2, editorBox.size.height / 2);
    final swTap = Stopwatch()..start();
    await tester.tapAt(center);
    await tester.pump();
    debugPrint('[T02-PROBE] $label tap_middle=${swTap.elapsedMilliseconds}ms');
    await tester.pump(const Duration(seconds: 2));

    // ── 动作 4：全选 + 复制（Ctrl+A / Ctrl+C，用户报告的「复制大文本」）──
    final tfCenter = tester.getRect(
      find
          .descendant(
            of: find.byType(QueryEditorWidget),
            matching: find.byType(ReSqlEditor),
          )
          .first,
    ).center;
    await tester.tapAt(tfCenter); // 确保编辑器持焦（Ctrl+A/C 作用于编辑器）
    await tester.pump();
    final swSelectAll = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA,
        physicalKey: PhysicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    debugPrint('[T02-PROBE] $label select_all=${swSelectAll.elapsedMilliseconds}ms');

    final swCopy = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC,
        physicalKey: PhysicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    debugPrint('[T02-PROBE] $label copy_clipboard=${swCopy.elapsedMilliseconds}ms');
    await tester.pump(const Duration(seconds: 2));

    final clipboardContent = await Clipboard.getData('text/plain');
    debugPrint(
      '[T02-PROBE] $label clipboard_len=${clipboardContent?.text?.length ?? 0}',
    );

    // 验收断言：无动作进入「永久卡死」量级（>30s 单步）。固有的一次性
    // 首排允许长（正是 T02 要量的数据），但每步必须能在 30s 内返回。
    expect(firstFrameMs, lessThan(30000), reason: '首帧 >30s：超出已知固有开销量级');
    expect(vPasteFrameMs, lessThan(30000), reason: 'Ctrl+V 首帧 >30s：真实粘贴路径疑似冻结');
    expect(rebuildMs, lessThan(3000),
        reason: '同文本重建 >3s：span 缓存疑似失效（二轮 bug 形态）');

    try {
      provider.dispose();
    } catch (_) {}
  }

  testWidgets('T02 探针 · 958K（≈testdb.txt 体量）', (tester) async {
    await runScenario(tester, '958K', _buildLargeScript(3000));
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('T02 探针 · 3MB（T02 合成脚本上限）', (tester) async {
    await runScenario(tester, '3MB', _buildLargeScript(9300));
  }, timeout: const Timeout(Duration(minutes: 8)));
}
