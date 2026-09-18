// ============================================================================
// ResultSubTabBar 402 子标签基准 (B1/B2/B3)
// P3 长尾收口（2026-08-25）：「402 条执行产生 402 个结果子标签的 UI 渲染
// 开销未测量」（COMPLETED_LOG 2026-08-14「明确不做」段遗留）。
//
// 架构前提（调研实锤）：扇出单次 notify；ListView.builder 懒构建；内容区
// 仅活跃子标签单挂载——预期无急切渲染，本测试钉数值 + 防劣化回归线。
// 模式复用 virtualized_data_table_benchmark_test.dart：
//   DBMASTER_BENCH_STRICT=1 时按验收线硬断言；默认宽松回归线 + 数值记录。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/result_subtab_bar.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';

class _BenchReport {
  static final List<String> _lines = [];

  static void record(String id, String name, Duration elapsed, String detail) {
    final line = '[BENCH][$id] $name: ${elapsed.inMilliseconds} ms ($detail)';
    _lines.add(line);
    // ignore: avoid_print
    print(line);
  }

  static void summary() {
    // ignore: avoid_print
    print('================ RESULT SUBTAB BASELINE SUMMARY ================');
    for (final line in _lines) {
      // ignore: avoid_print
      print(line);
    }
    // ignore: avoid_print
    print('================================================================');
  }
}

bool get _strict =>
    const String.fromEnvironment('DBMASTER_BENCH_STRICT') == '1';

/// 2026-08-14 实测大脚本语句数（958K / 402 条 CREATE TABLE）。
const _subTabCount = 402;

List<ExecutionResult> _genResults(int n) {
  return List<ExecutionResult>.generate(
    n,
    (i) => ExecutionResult(
      statement: SQLStatement(
        index: i,
        sql: 'CREATE TABLE t$i (id int)',
        type: SQLType.ddl,
        lineStart: i + 1,
        lineEnd: i + 1,
      ),
      success: true,
      data: [
        {'id': i},
      ],
      executionTime: const Duration(milliseconds: 3),
    ),
  );
}

Widget _buildApp(AppProvider appProvider) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: appProvider,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const Scaffold(
        body: SizedBox(width: 1280, height: 28, child: ResultSubTabBar()),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(_BenchReport.summary);

  // ------------------------------------------------------------------
  // B1: 扇出 —— addResultToTab 插入 402 个子标签（含整批替换 + 单次 notify）
  // 宽松回归线 < 2000ms（Debug）；严格 < 200ms
  // ------------------------------------------------------------------
  testWidgets('B1: fan-out $_subTabCount results via addResultToTab', (
    tester,
  ) async {
    final appProvider = AppProvider();
    appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
    final results = _genResults(_subTabCount); // 生成不计入基准

    final watch = Stopwatch()..start();
    appProvider.tab.addResultToTab(
      't1',
      results,
      sql: '-- 402 statements',
      executionTime: const Duration(seconds: 5),
    );
    watch.stop();

    _BenchReport.record(
      'B1',
      'fan-out addResultToTab',
      watch.elapsed,
      'subTabs=$_subTabCount (Debug)',
    );

    expect(appProvider.tab.getResultsForTab('t1'), hasLength(_subTabCount));
    expect(
      watch.elapsed.inMilliseconds,
      lessThan(_strict ? 200 : 2000),
      reason: 'B1 回归线：402 扇出应在预算内（单次 notify）',
    );
  });

  // ------------------------------------------------------------------
  // B2: 子标签栏首帧 —— 402 子标签下 ResultSubTabBar build+layout
  // 宽松回归线 < 1000ms（Debug）；严格 < 100ms
  // ------------------------------------------------------------------
  testWidgets('B2: subtab bar first frame with $_subTabCount subtabs', (
    tester,
  ) async {
    final appProvider = AppProvider();
    appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
    appProvider.tab.addResultToTab(
      't1',
      _genResults(_subTabCount),
      sql: '-- 402 statements',
      executionTime: const Duration(seconds: 5),
    );

    final watch = Stopwatch()..start();
    await tester.pumpWidget(_buildApp(appProvider));
    watch.stop();

    _BenchReport.record(
      'B2',
      'subtab bar first frame',
      watch.elapsed,
      'subTabs=$_subTabCount (Debug，ListView.builder 懒构建应只建可见项)',
    );

    expect(find.byType(ResultSubTabBar), findsOneWidget);
    // 懒构建断言：402 子标签不应全部挂载（视口仅容 ~10-15 项）。
    expect(
      tester.widgetList(find.byType(RepaintBoundary)).length,
      lessThan(_subTabCount),
      reason: '懒构建：子标签项不应全部实例化',
    );
    expect(
      watch.elapsed.inMilliseconds,
      lessThan(_strict ? 100 : 1000),
      reason: 'B2 回归线：402 子标签首帧应在预算内',
    );
  });

  // ------------------------------------------------------------------
  // B3: 子标签切换 —— 活跃子标签 0 → 末位（401）单帧重建耗时
  // 宽松回归线 < 500ms（Debug）；严格 < 50ms
  // ------------------------------------------------------------------
  testWidgets('B3: switch active subtab 0 -> ${_subTabCount - 1}', (
    tester,
  ) async {
    final appProvider = AppProvider();
    appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
    appProvider.tab.addResultToTab(
      't1',
      _genResults(_subTabCount),
      sql: '-- 402 statements',
      executionTime: const Duration(seconds: 5),
    );
    await tester.pumpWidget(_buildApp(appProvider));

    final watch = Stopwatch()..start();
    appProvider.tab.setActiveResult('t1', _subTabCount - 1);
    await tester.pump();
    watch.stop();

    _BenchReport.record(
      'B3',
      'switch to last subtab frame',
      watch.elapsed,
      'subTabs=$_subTabCount (Debug)',
    );

    expect(appProvider.tab.activeResultIndex, _subTabCount - 1);
    expect(
      watch.elapsed.inMilliseconds,
      lessThan(_strict ? 50 : 500),
      reason: 'B3 回归线：子标签切换单帧应在预算内',
    );
  });
}
