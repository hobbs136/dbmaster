// T02b 全 app 探针：真实应用树「第二冻结源」排查（T02a 遗留，已结案）。
//
// 背景：T02a 修复（Ctrl+V 拦截分流）后，最小树探针（仅挂 QueryEditorWidget）
// 的 real_ctrl_v_worst_frame 958K 565ms / 3MB 598ms 达标；但用户在含修复的
// release（09:21 构建）里实机粘贴大文本仍卡死 → 假设存在第二个冻结源，位于
// 探针未挂载的真实应用组件（sidebar/标签栏/面包屑/状态栏/编辑器外层等
// AppProvider 通知的下游——z0 层 watch 整个 AppProvider，任何 notify 全树重建）。
//
// 本探针启动完整真实 app（DbmasterApp，同 app_startup_test 模式），经真实
// 路径建立 SQLite 文件连接（本地文件，无网络依赖）→ 打开查询 tab → 在真实
// 树里跑七个场景分离变量：
//   A 程序设值      — EditableText 全文重排本身（最小树基线首帧 ~459ms）
//   C updateTabSql  — AppProvider 通知 → z0 全树重建（最小树基线 31ms）
//   B 真实 Ctrl+V   — 同内容重设（span 缓存命中路径）
//   D sidebar 折叠  — B 的对照（真实用户动作，缩小嫌疑面）
//   E Shift+Insert  — 框架 CUA 粘贴键（合成键事件在真实窗口 embedder 不达
//                     focus handler——环境限制；拦截正确性由单测
//                     query_editor_paste_shortcut_test.dart 直证）
//   F Ctrl+V 全新 1MB — 忠实的用户「首次粘贴」（缓存未命中）
//   G Ctrl+V 全新 3MB + 结果面板可见 — 线性放大上界 + 用户工作形态
// 慢帧（>300ms）由 FrameTiming 回调打印 build/raster 拆分。
//
// 2026-08-15 T02b 结案数据（profile AOT）：A 首帧 449-474ms；C 全树重建
// 38-39ms；粘贴后观察窗零 >300ms 慢帧（B/D/E/F/G 全部）；F 首帧 508-513ms；
// G 首帧 1497-1498ms（build 1343ms）——组件树内无第二冻结源，残余卡顿为
// EditableText 单段全文首排的固有线性成本（终局解 = re_editor 行式渲染）。
//
// 运行（profile，AOT）：
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/t02b_full_app_paste_test.dart -d windows --profile
//
// 输出行格式：[T02B] <场景> <动作>=<ms>ms

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/main.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/screens/home_screen.dart';
import 'package:dbmaster/services/pro_module.dart';

/// 与 t02_editor_large_text_perf_test.dart 同构的合成脚本生成器（~2.4KB/表）。
String _buildLargeScript(int tableCount) {
  final sb = StringBuffer();
  sb.writeln('-- DBMaster Database Export');
  sb.writeln('-- Database: t02b_probe');
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

  final slowFrames = <String>[];
  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      if (t.totalSpan.inMilliseconds > 300) {
        final line =
            'build=${t.buildDuration.inMilliseconds}ms '
            'raster=${t.rasterDuration.inMilliseconds}ms '
            'total=${t.totalSpan.inMilliseconds}ms';
        slowFrames.add(line);
        debugPrint('[T02B-FRAME] $line');
      }
    }
  });

  void dumpSlowFrames(String label) {
    debugPrint('[T02B] $label slow_frames(>300ms)=${slowFrames.length}');
    for (final l in slowFrames.take(12)) {
      debugPrint('[T02B]   $l');
    }
    if (slowFrames.length > 12) {
      debugPrint('[T02B]   ... 其余 ${slowFrames.length - 12} 帧略');
    }
    slowFrames.clear();
  }

  testWidgets('T02b 全 app · 958K 粘贴四场景', (tester) async {
    // —— 0. 确定性窗口尺寸（真实窗口侧栏展开阈值以上）——
    try {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
    } catch (_) {}

    // —— 1. 启动完整真实 app ——
    AppProvider.devBypassGates = true;
    await tester.pumpWidget(DbmasterApp(proModule: FreeProModule()));
    // 有界 settle：AI FAB 等常驻动画令 pumpAndSettle 永不结束。
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    debugPrint(
      '[T02B] app_booted dialogs='
      '${find.byType(AlertDialog).evaluate().length}',
    );

    final home = tester.element(find.byType(HomeScreen));
    final provider = home.read<AppProvider>();
    final layoutProvider = home.read<LayoutPreferencesProvider>();

    // —— 2. 真实 SQLite 文件连接（本地文件，无网络）——
    final src = File('../Chinook_Sqlite.sqlite');
    expect(src.existsSync(), isTrue, reason: '测试资源缺失：${src.absolute.path}');
    final tmp = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      't02b_full_probe.sqlite',
    );
    if (tmp.existsSync()) tmp.deleteSync();
    await src.copy(tmp.path);
    final connected = await provider.connection.openSqliteFile(tmp.path);
    expect(connected, isTrue, reason: 'SQLite 文件连接失败');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // —— 3. 打开查询 tab（真实路径：openQueryTab → EditorResultsSplit）——
    final conn = ConnectionProvider.findExistingSqlite(
      provider.connection.savedConnections,
      ConnectionProvider.normalizeSqlitePath(tmp.path),
    );
    expect(conn, isNotNull, reason: '保存的连接里找不到刚打开的 SQLite');
    await provider.tab.openQueryTab(
      connectionId: conn!.id,
      databaseName: 'main',
    );
    provider.setActiveTab(0);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final editorFinder = find.descendant(
      of: find.byType(QueryEditorWidget),
      matching: find.byType(TextField),
    );
    expect(editorFinder, findsOneWidget, reason: '真实树中未找到编辑器 TextField');
    final controller = tester.widget<TextField>(editorFinder).controller;
    expect(controller, isNotNull, reason: '编辑器 controller 未找到');

    Future<void> focusEditor() async {
      await tester.tapAt(tester.getCenter(editorFinder));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<int> observeWindow(String label, int frames) async {
      var worst = 0;
      final log = <int>[];
      for (var i = 0; i < frames; i++) {
        final sw = Stopwatch()..start();
        await tester.pump(const Duration(milliseconds: 500));
        final ms = sw.elapsedMilliseconds;
        log.add(ms);
        if (ms > worst) worst = ms;
      }
      debugPrint('[T02B] $label frames(500ms/格)=$log');
      debugPrint('[T02B] $label worst=${worst}ms');
      return worst;
    }

    final sql = _buildLargeScript(3000);
    debugPrint('[T02B] ===== sql=${sql.length} chars =====');

    // 空闲基线（若此处已有慢帧，说明常驻动画/轮询污染测量）。
    await observeWindow('idle_baseline', 2);
    dumpSlowFrames('idle_baseline');

    // —— 场景 A：程序设值（EditableText 全文重排本身，无剪贴板/无防抖链）——
    await focusEditor();
    controller!.clear();
    await tester.pump(const Duration(milliseconds: 500));
    slowFrames.clear();
    final swA = Stopwatch()..start();
    controller.text = sql;
    controller.selection = TextSelection.collapsed(offset: sql.length);
    await tester.pump();
    debugPrint(
      '[T02B] A programmatic_set_first_frame=${swA.elapsedMilliseconds}ms',
    );
    await observeWindow('A_programmatic_set', 10);
    dumpSlowFrames('A_programmatic_set');

    // —— 场景 C：同文本 updateTabSql（AppProvider 通知 → z0 全树重建）——
    // 最小树基线 31ms（2026-08-14 span 缓存修复后）。
    final swC = Stopwatch()..start();
    provider.updateTabSql(0, sql);
    await tester.pump();
    debugPrint('[T02B] C updateTabSql_rebuild=${swC.elapsedMilliseconds}ms');
    await observeWindow('C_update_tab_sql', 8);
    dumpSlowFrames('C_update_tab_sql');

    // —— 场景 B：真实 Ctrl+V（用户报告路径，走 T02a 拦截分流）——
    controller.clear();
    await tester.pump(const Duration(milliseconds: 500));
    slowFrames.clear();
    await Clipboard.setData(ClipboardData(text: sql));
    await focusEditor();
    final swB = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    debugPrint(
      '[T02B] B real_ctrl_v_first_frame=${swB.elapsedMilliseconds}ms',
    );
    final worstB = await observeWindow('B_real_ctrl_v', 10);
    dumpSlowFrames('B_real_ctrl_v');
    expect(controller.text.length, sql.length,
        reason: 'Ctrl+V 后文本长度应一致（真实粘贴路径）');

    // —— 场景 D：sidebar 折叠对照（真实用户动作，排除侧栏树重建嫌疑）——
    layoutProvider.setSidebarCollapsed(true);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    controller.clear();
    await tester.pump(const Duration(milliseconds: 500));
    slowFrames.clear();
    await Clipboard.setData(ClipboardData(text: sql));
    await focusEditor();
    final swD = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    debugPrint(
      '[T02B] D ctrl_v_sidebar_collapsed_first_frame='
      '${swD.elapsedMilliseconds}ms',
    );
    final worstD = await observeWindow('D_sidebar_collapsed_ctrl_v', 10);
    dumpSlowFrames('D_sidebar_collapsed_ctrl_v');

    // —— 场景 E：Shift+Insert 粘贴（框架 DefaultTextEditingShortcuts 也绑定
    //    insert+shift → PasteTextIntent，T02a 拦截器只拦 Ctrl/Cmd+V →
    //    疑似绕过路径，走框架 EditableText.paste 冻结路径）。
    //    用全新内容（3200 表）防 span 缓存命中，还原用户「首次粘贴」——
    //    上面 B 是同内容重设（缓存命中），不忠实于用户路径。——
    //    先恢复 sidebar 展开（D 折叠了），回到全树默认形态。
    layoutProvider.setSidebarCollapsed(false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final sqlE = _buildLargeScript(3200);
    controller.clear();
    await tester.pump(const Duration(milliseconds: 500));
    slowFrames.clear();
    await Clipboard.setData(ClipboardData(text: sqlE));
    await focusEditor();
    final swE = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.insert,
        physicalKey: PhysicalKeyboardKey.insert);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft,
        physicalKey: PhysicalKeyboardKey.shiftLeft);
    await tester.pump();
    debugPrint(
      '[T02B] E shift_insert_first_frame=${swE.elapsedMilliseconds}ms',
    );
    final worstE = await observeWindow('E_shift_insert', 10);
    dumpSlowFrames('E_shift_insert');
    if (controller.text.length == sqlE.length) {
      debugPrint('[T02B] E shift_insert 粘贴已生效（框架快捷键触发）');
    } else {
      debugPrint(
        '[T02B] E shift_insert 未触发粘贴（text=${controller.text.length}）——'
        '合成键盘事件对框架 Shortcuts 路径无效的环境限制，'
        '真实键入是否触发待人工验证（拦截器修复后此路径不再存在）',
      );
    }

    // —— 场景 F：Ctrl+V 粘贴全新内容（3300 表，拦截路径 + 缓存未命中，
    //    忠实的用户「首次粘贴」对照）——
    final sqlF = _buildLargeScript(3300);
    controller.clear();
    await tester.pump(const Duration(milliseconds: 500));
    slowFrames.clear();
    await Clipboard.setData(ClipboardData(text: sqlF));
    await focusEditor();
    final swF = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    debugPrint(
      '[T02B] F ctrl_v_fresh_first_frame=${swF.elapsedMilliseconds}ms',
    );
    final worstF = await observeWindow('F_ctrl_v_fresh', 10);
    dumpSlowFrames('F_ctrl_v_fresh');
    expect(controller.text.length, sqlF.length,
        reason: 'Ctrl+V 后文本长度应一致');

    // —— 场景 G：结果面板可见（先执行 SELECT 1）+ Ctrl+V 粘贴全新 3MB ——
    //    用户真实工作形态：跑过查询后结果区常驻（ResultsWidget + 子标签 +
    //    ExecutionStatusBar 均为 AppProvider 未收窄订阅），再粘贴大文本。
    await provider.executeCurrentQueryAndRecord(
      overrideSql: 'SELECT 1',
      skipDdlAnalysis: true,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final sqlG = _buildLargeScript(9300); // ≈3MB
    controller.clear();
    await tester.pump(const Duration(milliseconds: 500));
    slowFrames.clear();
    await Clipboard.setData(ClipboardData(text: sqlG));
    await focusEditor();
    final swG = Stopwatch()..start();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV,
        physicalKey: PhysicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pump();
    debugPrint(
      '[T02B] G ctrl_v_3mb_results_visible_first_frame='
      '${swG.elapsedMilliseconds}ms',
    );
    final worstG = await observeWindow('G_ctrl_v_3mb_results', 10);
    dumpSlowFrames('G_ctrl_v_3mb_results');
    expect(controller.text.length, sqlG.length, reason: '3MB 粘贴后长度应一致');

    // —— 汇总（对照最小树基线：A 首帧 ~459ms / C 31ms / B 565ms）——
    debugPrint('[T02B] ===== 汇总 =====');
    debugPrint(
      '[T02B] ctrl_v_worst: full_tree=${worstB}ms '
      'sidebar_collapsed=${worstD}ms（最小树修复后基线 565ms）',
    );
    debugPrint(
      '[T02B] 首次粘贴(缓存未命中): shift_insert=${worstE}ms / '
      'ctrl_v_1mb=${worstF}ms / ctrl_v_3mb_结果面板可见=${worstG}ms '
      '（内容 ${sqlE.length}/${sqlF.length}/${sqlG.length} 字符）',
    );

    // 探针目标是测量归因，门槛只卡「卡死量级」（>10s 单帧）。
    expect(worstB, lessThan(10000), reason: '真实树 Ctrl+V 粘贴出现卡死量级单帧');
    expect(worstD, lessThan(10000), reason: 'sidebar 折叠后仍卡死');
    expect(worstF, lessThan(10000), reason: 'Ctrl+V 全新 1MB 粘贴出现卡死量级单帧');
    expect(worstG, lessThan(10000), reason: '结果面板可见 3MB 粘贴出现卡死量级单帧');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
