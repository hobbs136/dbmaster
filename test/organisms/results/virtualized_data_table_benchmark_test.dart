// ============================================================================
// VirtualizedDataTable UI 渲染基准 (U1/U2)
// 对应 $APPEAL 4.1.6 结论：P2 的 UI 渲染层验证（10 万行首帧 < 1s 预算内
// 渲染部分建议 < 380ms；滚动 30fps → 帧预算 33ms）
// docs/task_performance_benchmark_wave2.md
//
// 说明：widget 测试测量 Debug 环境的 build+layout 成本（不含光栅化），
// 阈值相应放宽；数值记录为主，回归线防劣化。
//   DBMASTER_BENCH_ROWS    行数，默认 100000
//   DBMASTER_BENCH_STRICT  设为 1 时按验收线硬断言
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';

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
    print('================ UI RENDER BASELINE SUMMARY ================');
    for (final line in _lines) {
      // ignore: avoid_print
      print(line);
    }
    // ignore: avoid_print
    print('============================================================');
  }
}

int get _benchRows {
  final v = const String.fromEnvironment(
    'DBMASTER_BENCH_ROWS',
    defaultValue: '100000',
  );
  return int.tryParse(v) ?? 100000;
}

bool get _strict =>
    const String.fromEnvironment('DBMASTER_BENCH_STRICT') == '1';

List<String> get _columns => List<String>.generate(6, (i) => 'col$i');

List<Map<String, dynamic>> _generateData(int rows) {
  return List<Map<String, dynamic>>.generate(rows, (i) {
    return <String, dynamic>{
      for (var c = 0; c < 6; c++) 'col$c': c == 0 ? i : 'value_${i}_$c',
    };
  });
}

Widget _buildApp(List<Map<String, dynamic>> data) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 1280,
        height: 800,
        child: VirtualizedDataTable(columns: _columns, data: data),
      ),
    ),
  );
}

void main() {
  tearDownAll(_BenchReport.summary);

  // ------------------------------------------------------------------
  // U1: 首帧渲染 —— 10 万行数据下首帧 build+layout 耗时
  // 验收输入：P2 总预算 1s 中取数 ~620ms → 渲染建议 < 380ms
  // 宽松回归线：< 2000ms（Debug）；严格：< 380ms
  // ------------------------------------------------------------------
  testWidgets('U1: first frame build+layout with $_benchRows rows', (
    tester,
  ) async {
    final data = _generateData(_benchRows); // 生成不计入基准

    final watch = Stopwatch()..start();
    await tester.pumpWidget(_buildApp(data));
    watch.stop();

    _BenchReport.record(
      'U1',
      'first frame build+layout',
      watch.elapsed,
      'rows=$_benchRows, cols=6 (Debug 环境，不含光栅化)',
    );

    expect(find.byType(VirtualizedDataTable), findsOneWidget);

    final threshold = _strict ? 380 : 2000;
    expect(
      watch.elapsed.inMilliseconds,
      lessThan(threshold),
      reason: 'U1 回归线：首帧渲染应 < ${threshold}ms',
    );
  });

  // ------------------------------------------------------------------
  // U2: 滚动帧耗时 —— 跳转到 25%/50%/75%/95% 深处，逐次测量重绘帧耗时
  // 30fps → 帧预算 33ms。
  // ⚠️ 首次基线（2026-07-21, Debug）：中位 241ms，未达 33ms 帧预算，
  //    确认为 Performance 风险点（见 appeal_product_analysis §4.1.6）。
  //    宽松回归线 < 500ms 按基线 ×2 校准防劣化；严格模式 < 33ms。
  // ------------------------------------------------------------------
  testWidgets('U2: scroll frame cost at depth with $_benchRows rows', (
    tester,
  ) async {
    final data = _generateData(_benchRows);
    await tester.pumpWidget(_buildApp(data));

    // 找到垂直方向的 Scrollable（内部还有一个水平滚动）
    final vertical = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.axis == Axis.vertical);
    final maxExtent = vertical.position.maxScrollExtent;
    expect(maxExtent, greaterThan(0), reason: '10 万行应产生可滚动区域');

    final samples = <int>[];
    for (final fraction in [0.25, 0.5, 0.75, 0.95]) {
      vertical.position.jumpTo(maxExtent * fraction);
      final watch = Stopwatch()..start();
      await tester.pump();
      watch.stop();
      samples.add(watch.elapsed.inMilliseconds);
    }
    samples.sort();
    final median = Duration(milliseconds: samples[samples.length ~/ 2]);
    _BenchReport.record(
      'U2',
      'scroll frame cost median of 4 depths',
      median,
      'maxExtent=${maxExtent.toStringAsFixed(0)}px, runs=$samples',
    );

    final threshold = _strict ? 33 : 500;
    expect(
      median.inMilliseconds,
      lessThan(threshold),
      reason: 'U2 回归线：滚动帧中位数应 < ${threshold}ms',
    );
  });
}
