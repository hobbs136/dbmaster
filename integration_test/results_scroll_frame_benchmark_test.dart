// ============================================================================
// Profile 模式帧率基准（US2 验收依据，contracts C3）
//
// 运行方式（Debug 构建无 --profile，必须用 flutter drive）：
//   flutter drive --profile -d windows \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/results_scroll_frame_benchmark_test.dart
// 结果输出：build/integration_response_data.json
//
// 参数：
//   DBMASTER_BENCH_ROWS    行数，默认 100000
//   DBMASTER_BENCH_STRICT  设为 1 时按验收线硬断言（滚动帧 ≤33ms、首帧 ≤380ms）
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/organisms/results/virtualized_data_table.dart';

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
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() {
    final data = binding.reportData;
    if (data != null) {
      // ignore: avoid_print
      print('================ PROFILE FRAME REPORT ================');
      for (final entry in data.entries) {
        // ignore: avoid_print
        print('[FRAME][${entry.key}] ${entry.value}');
      }
      // ignore: avoid_print
      print('======================================================');
    }
  });

  testWidgets('first frame and scroll frame perf with $_benchRows rows', (
    tester,
  ) async {
    final data = _generateData(_benchRows); // 生成不计入基准

    // ---- 首帧（first_frame_100k）----
    await binding.watchPerformance(() async {
      await tester.pumpWidget(_buildApp(data));
    }, reportKey: 'first_frame_100k');

    // ---- 滚动帧（scroll_100k）----
    final vertical = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.axis == Axis.vertical);
    final maxExtent = vertical.position.maxScrollExtent;
    expect(maxExtent, greaterThan(0), reason: '10 万行应产生可滚动区域');

    await binding.watchPerformance(() async {
      // 连续 fling 滚动（稳态滚动帧）
      for (var i = 0; i < 5; i++) {
        await tester.fling(
          find.byType(ListView).last,
          const Offset(0, -2000),
          8000,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }
    }, reportKey: 'scroll_100k');

    // 深跳单独测量（跳帧是卡顿主场景，不能被稳态平均稀释）
    for (var i = 0; i < 3; i++) {
      await binding.watchPerformance(() async {
        for (final fraction in [0.25, 0.5, 0.75, 0.95]) {
          vertical.position.jumpTo(maxExtent * fraction);
          await tester.pump();
        }
      }, reportKey: 'jump_100k');
    }

    // ---- 阈值断言（strict 模式）----
    final report = binding.reportData;
    if (_strict && report != null) {
      final firstFrame = report['first_frame_100k'] as Map<String, dynamic>?;
      final scroll = report['scroll_100k'] as Map<String, dynamic>?;
      if (firstFrame != null) {
        final firstMs = (firstFrame['average_frame_build_time_millis'] as num)
            .toDouble();
        expect(
          firstMs,
          lessThanOrEqualTo(380),
          reason: '首帧 build 应 ≤380ms，实测 ${firstMs}ms',
        );
      }
      if (scroll != null) {
        final avgMs = (scroll['average_frame_build_time_millis'] as num)
            .toDouble();
        expect(
          avgMs,
          lessThanOrEqualTo(33),
          reason: '滚动帧平均 build 应 ≤33ms，实测 ${avgMs}ms',
        );
      }
    }
  });
}
