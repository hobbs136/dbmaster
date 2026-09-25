// ============================================================================
// T01 性能探针：工具卡快照行数 N 定值（gate 任务，M1 第一任务）
//
// 依据：.specs/design-ai-workbench.md §10（探针实现方案）+ §8【二】N 的探针规则
//
// 场景：不依赖工作台卡组件——以「header 34 + 内容上限 360 内部滚动 +
//       真实 ResultSnapshotTable 组件」的最小复刻卡 × 50 张 × N 行 × 8 列合成
//       展示字符串数据（不连库），置于滚动列表；ScrollController 程序驱动全程
//       滚动 ×3 轮；SchedulerBinding.addTimingsCallback 收集 FrameTiming 算 P95
//       （build+raster 合计口径）；ProcessInfo.currentRss 采样 0→25→50 卡对照。
//       R1 复跑（2026-09-22，design §14 R1）：表格载体由 VirtualizedDataTable
//       换为真实 ResultSnapshotTable（与首轮直接用真实 VDT 同方法论），判定
//       规则与其余口径（滚动驱动/采样）逐字不变；首轮 VDT 数据存档 design §10。
//
// gate（判定规则，逐条执行）：
//   P95 ≤ 8ms      → 保持或放宽 N（本探针保持当前档，不主动放宽：
//                     快照行数越大会话文件体积越大，design §9 风险 7）
//   P95 > 16.7ms   → N 减半重测（20→10→5）
//   下限 5 / 上限 50
//   内存判据 = 卡数翻倍 RSS 增量不超线性（操作化：25→50 卡增量 ≤ 2× 0→25 卡增量）
//   N=5 仍 > 16.7ms → 停止升级裁决（本脚本原样输出数据，不自行改设计）
//
// 运行：
//   flutter test -d windows integration_test/perf/tool_card_probe_test.dart
//   （debug 模式数值仅相对参考；结论以 profile 为准）
//   flutter drive --profile -d windows \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf/tool_card_probe_test.dart
//
// 探针是一次性定值动作 + 按需复跑（design §10「明确不做」：不进 CI 常驻门槛）。
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_snapshot_table.dart';
import 'package:dbmaster/theme/app_colors.dart';

// ---- 探针参数（任务书允许自决清单：滚动驱动参数 / 复刻卡最小实现细节 / RSS 采样时机）----

/// 卡数（N 规则固定 50 卡对照；上限亦为 50）
const int _cardCount = 50;

/// 内存对照卡数（翻倍前）
const int _memoryHalfCards = 25;

/// N 阶梯（20→10→5，判定规则固定）
const List<int> _nLadder = <int>[20, 10, 5];

// 复刻卡几何（R1 复跑：消费 T02 已落库的真实 token，对齐真实卡形态，
// 替换首轮「token 由 T02 落库，探针自持常量」的过渡做法；数值同为 34/360/760）
const double _cardHeaderHeight = AppDesignSystem.toolCardHeaderHeight;
const double _cardContentMaxHeight = AppDesignSystem.toolCardContentMaxHeight;
const double _chatColumnWidth = AppDesignSystem.workbenchChatMaxWidth;

// 行高/表头高 = ResultSnapshotTable 组件常量（design §8【二】R1：沿用 VDT
// 默认 26/28 作为组件常量，不新增 token；组件无底栏，自然高 = 表头 28 + N×26）

/// 滚动驱动：全程 ×3 轮；每轮 = 下探（easeOutCubic，fling 快起形态）+ 回卷（easeInCubic）
const int _rounds = 3;
const Duration _legDuration = Duration(milliseconds: 1200);

/// gate 阈值（N 的探针规则原文数值）
const double _gateRelaxMs = 8.0;
const double _gateHalveMs = 16.7;

/// 线性判据余量系数（25→50 卡增量相对 0→25 卡增量的允许倍数，留一倍噪声余量）
const double _memoryLinearitySlack = 2.0;

/// RSS 采样：中位数口径降噪
const int _rssSamples = 5;
const Duration _rssSampleInterval = Duration(milliseconds: 100);

void _log(Object message) {
  // ignore: avoid_print
  print(message);
}

// ---- 数据合成（不连库）----

/// 8 列固定列名（const，避免滚动热路径每帧生成）
const List<String> _columns = <String>[
  'col0',
  'col1',
  'col2',
  'col3',
  'col4',
  'col5',
  'col6',
  'col7',
];

/// 合成展示字符串行（与 [_columns] 按下标对齐；ResultSnapshotTable 入参约定：
/// 卡侧已完成 payload → 展示字符串转换，组件零转换——探针按同约定预转换）。
List<List<String>> _makeRows(int rows) {
  return List<List<String>>.generate(rows, (r) {
    return <String>[
      for (var c = 0; c < _columns.length; c++)
        c == 0 ? '$r' : 'value_${r}_$c',
    ];
  });
}

/// 每卡独立数据集（真实语义：各卡持各自快照本体，内存对照含快照数据）
List<List<List<String>>> _makeCardDatasets(int cardCount, int rowsPerCard) {
  return List<List<List<String>>>.generate(
    cardCount,
    (_) => _makeRows(rowsPerCard),
  );
}

// ---- 复刻卡（最小实现：几何对齐 design §8【三】，不依赖工作台卡组件）----

class _ProbeToolCard extends StatelessWidget {
  final List<List<String>> rows;

  const _ProbeToolCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    // ResultSnapshotTable 高度自带钳（LayoutBuilder：min(父高, token 360)），
    // 传入「表头 28 + N×26」自然高与 360 上限取小的有界高度，保持首轮探针的
    // cap 语义（行少时收拢，行多时 360 内部滚动）。RepaintBoundary 由组件内部
    // 自持（整表单一重绘边界，R1 性能不变式），探针不再外包。
    final natural = ResultSnapshotTable.headerHeight +
        rows.length * ResultSnapshotTable.rowHeight;
    final contentHeight =
        natural <= _cardContentMaxHeight ? natural : _cardContentMaxHeight;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: context.themeColors.borderLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // header 34 恒显（最小复刻：图标 + 标题 + chevron；视觉细节非本探针对象）
          SizedBox(
            height: _cardHeaderHeight,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(
                  Icons.table_chart,
                  size: 16,
                  color: context.themeColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'probe_result_card',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: context.themeColors.textMuted,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          // content：上限 360 内部滚动（design §8【三】展开态；重绘边界在组件内）
          SizedBox(
            height: contentHeight,
            child: ResultSnapshotTable(columns: _columns, rows: rows),
          ),
        ],
      ),
    );
  }
}

// ---- 场景宿主：1280×800 视口 + 760 宽对话列 + 卡滚动列表 ----

Widget _buildProbeApp({
  Key? appKey,
  required ScrollController scrollController,
    required List<List<List<String>>> cardDatasets,
}) {
  return MaterialApp(
    key: appKey,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF161616),
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _chatColumnWidth,
          child: ListView.builder(
            controller: scrollController,
            itemCount: cardDatasets.length,
            itemBuilder: (context, i) => _ProbeToolCard(rows: cardDatasets[i]),
          ),
        ),
      ),
    ),
  );
}

// ---- 帧采集与统计 ----

class _FrameCollector {
  /// build + raster 合计帧耗时（ms），design §10 口径
  final List<double> frameMs = <double>[];

  /// 分量诊断：build / raster 各自的帧耗时（ms）。
  /// gate 口径仍为合计（frameMs）；分量仅用于判读瓶颈归属
  /// （raster 主导 → 环境伪影嫌疑：RDP/WARP 软件光栅与合成 back-pressure；
  /// build 主导 → 卡构建真实成本）。
  final List<double> buildMs = <double>[];
  final List<double> rasterMs = <double>[];

  /// 每轮结束时的帧计数标记（轮切面，用于轮级 P95 分解）
  final List<int> roundMarks = <int>[0];

  void onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      frameMs.add(
        (timing.buildDuration.inMicroseconds +
                timing.rasterDuration.inMicroseconds) /
            1000.0,
      );
      buildMs.add(timing.buildDuration.inMicroseconds / 1000.0);
      rasterMs.add(timing.rasterDuration.inMicroseconds / 1000.0);
    }
  }

  void markRoundEnd() => roundMarks.add(frameMs.length);
}

double _percentile(List<double> values, double p) {
  if (values.isEmpty) {
    return 0.0;
  }
  final sorted = List<double>.of(values)..sort();
  var idx = (p * sorted.length).ceil() - 1;
  if (idx < 0) {
    idx = 0;
  }
  if (idx >= sorted.length) {
    idx = sorted.length - 1;
  }
  return sorted[idx];
}

class _LevelResult {
  final int n;
  final int frameCount;
  final double p50Ms;
  final double p95Ms;
  final double maxMs;
  final double avgMs;

  /// 分量诊断（gate 判定不使用）：build / raster 各自的 P95 与 P50
  final double p95BuildMs;
  final double p50BuildMs;
  final double p95RasterMs;
  final double p50RasterMs;
  final List<double> roundP95Ms;

  const _LevelResult({
    required this.n,
    required this.frameCount,
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
    required this.avgMs,
    required this.p95BuildMs,
    required this.p50BuildMs,
    required this.p95RasterMs,
    required this.p50RasterMs,
    required this.roundP95Ms,
  });
}

/// 驱动一段程序滚动动画（easeOutCubic 快起承载 fling 形态）。
///
/// 实现注记（挂起根因，勿改回裸 await）：live binding
/// （IntegrationTestWidgetsFlutterBinding）下帧只在 pump() 调用时产出，
/// `await controller.animateTo(...)` 的完成 future 等不到帧驱动、必然挂起
/// （首次运行实测）。因此启动动画后不 await，改为按帧步进泵动直至滚动
/// 活动结束；安全上限按真实时钟计（debug 慢机余量），超限则 jumpTo 落位。
Future<void> _pumpDrivenLeg(
  WidgetTester tester,
  _FrameCollector collector,
  ScrollController controller,
  double target,
  Curve curve,
  String label,
) async {
  final animation = controller.animateTo(
    target,
    duration: _legDuration,
    curve: curve,
  );
  const step = Duration(milliseconds: 16);
  final watch = Stopwatch()..start();
  final capMs = 3 * _legDuration.inMilliseconds + 2000;
  bool legDone() => !controller.position.isScrollingNotifier.value;
  while (!legDone() && watch.elapsedMilliseconds < capMs) {
    await tester.pump(step);
  }
  if (!legDone()) {
    controller.jumpTo(target);
    await tester.pump(step);
  }
  await animation;
  _log('probe: $label done, frames=${collector.frameMs.length}');
}

/// 冲账补泵：FrameTiming 由引擎随下一帧滞后批量上报（实测：不补泵时尾部
/// 帧永不入账），泵帧 + 真实延时直至计数稳定，保证 round 切面标记对齐。
Future<void> _flushFrameTimings(
  WidgetTester tester,
  _FrameCollector collector,
) async {
  var lastCount = -1;
  for (var i = 0; i < 30 && collector.frameMs.length != lastCount; i++) {
    lastCount = collector.frameMs.length;
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// 构建场景并执行 3 轮全程滚动，返回该 N 档的帧统计
Future<_LevelResult> _runLevel(WidgetTester tester, int n) async {
  final controller = ScrollController();
  _createdControllers.add(controller);
  await tester.pumpWidget(
    _buildProbeApp(
      appKey: UniqueKey(),
      scrollController: controller,
      cardDatasets: _makeCardDatasets(_cardCount, n),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));

  final maxExtent = controller.position.maxScrollExtent;
  expect(maxExtent, greaterThan(0), reason: '50 张卡应产生可滚动区域');

  final collector = _FrameCollector();
  SchedulerBinding.instance.addTimingsCallback(collector.onTimings);
  for (var round = 0; round < _rounds; round++) {
    await _pumpDrivenLeg(
      tester,
      collector,
      controller,
      maxExtent,
      Curves.easeOutCubic,
      'N=$n round ${round + 1} leg-down',
    );
    await _pumpDrivenLeg(
      tester,
      collector,
      controller,
      0,
      Curves.easeInCubic,
      'N=$n round ${round + 1} leg-up',
    );
    await _flushFrameTimings(tester, collector);
    collector.markRoundEnd();
  }
  await _flushFrameTimings(tester, collector);
  SchedulerBinding.instance.removeTimingsCallback(collector.onTimings);

  expect(collector.frameMs.length, greaterThan(60), reason: '3 轮全程滚动应采集到足够帧样本');

  final frames = collector.frameMs;
  final roundP95 = <double>[];
  for (var i = 0; i < collector.roundMarks.length - 1; i++) {
    final start = collector.roundMarks[i];
    final end = collector.roundMarks[i + 1];
    roundP95.add(_percentile(frames.sublist(start, end), 0.95));
  }

  return _LevelResult(
    n: n,
    frameCount: frames.length,
    p50Ms: _percentile(frames, 0.50),
    p95Ms: _percentile(frames, 0.95),
    maxMs: frames.reduce((a, b) => a > b ? a : b),
    avgMs: frames.reduce((a, b) => a + b) / frames.length,
    p95BuildMs: _percentile(collector.buildMs, 0.95),
    p50BuildMs: _percentile(collector.buildMs, 0.50),
    p95RasterMs: _percentile(collector.rasterMs, 0.95),
    p50RasterMs: _percentile(collector.rasterMs, 0.50),
    roundP95Ms: roundP95,
  );
}

// ---- RSS 采样（内存判据）----

Future<double> _sampleRssMedianMb() async {
  final values = <int>[];
  for (var i = 0; i < _rssSamples; i++) {
    values.add(ProcessInfo.currentRss);
    await Future<void>.delayed(_rssSampleInterval);
  }
  values.sort();
  return values[_rssSamples ~/ 2] / (1024 * 1024);
}

/// 构建指定卡数场景，settle 后返回 RSS 中位数（MB）
Future<double> _pumpAndSampleRss(
  WidgetTester tester,
  int cardCount,
  int rowsPerCard,
) async {
  final controller = ScrollController();
  await tester.pumpWidget(
    _buildProbeApp(
      appKey: UniqueKey(),
      scrollController: controller,
      cardDatasets: _makeCardDatasets(cardCount, rowsPerCard),
    ),
  );
  await tester.pumpAndSettle();
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final rssMb = await _sampleRssMedianMb();
  _createdControllers.add(controller);
  return rssMb;
}

/// 场景 ScrollController 暂存（测试末尾统一释放，避免 dispose 时仍挂接活动树）
final List<ScrollController> _createdControllers = <ScrollController>[];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mode = kDebugMode
      ? 'debug（数值仅相对参考）'
      : kProfileMode
      ? 'profile（gate 结论口径）'
      : kReleaseMode
      ? 'release'
      : 'unknown';

  testWidgets('T01 tool card snapshot rows probe: N ladder 20→10→5 + RSS 0→25→50', (
    tester,
  ) async {
    _log('==================== T01 TOOL CARD PROBE ====================');
    _log('MODE: $mode');
    _log(
      'scenario: $_cardCount cards × N rows × ${_columns.length} cols, '
      'chat column width $_chatColumnWidth, viewport 1280×800',
    );
    _log(
      'driving: $_rounds rounds × (down ${_legDuration.inMilliseconds}ms '
      'easeOutCubic → up ${_legDuration.inMilliseconds}ms easeInCubic)',
    );

    // ---- 阶段 1：P95 阶梯（gate 主判定，逐条执行）----
    final results = <int, _LevelResult>{};
    _LevelResult? passing;
    for (final n in _nLadder) {
      final result = await _runLevel(tester, n);
      results[n] = result;
      _log('---- level N=$n (50 cards) ----');
      _log(
        'frames=${result.frameCount} '
        'p50=${result.p50Ms.toStringAsFixed(2)}ms '
        'p95=${result.p95Ms.toStringAsFixed(2)}ms '
        'avg=${result.avgMs.toStringAsFixed(2)}ms '
        'max=${result.maxMs.toStringAsFixed(2)}ms',
      );
      _log(
        'split p95: build=${result.p95BuildMs.toStringAsFixed(2)}ms '
        '(p50 ${result.p50BuildMs.toStringAsFixed(2)}) '
        'raster=${result.p95RasterMs.toStringAsFixed(2)}ms '
        '(p50 ${result.p50RasterMs.toStringAsFixed(2)})',
      );
      _log(
        'round p95: ${result.roundP95Ms.asMap().entries.map((e) => 'r${e.key + 1}=${e.value.toStringAsFixed(2)}ms').join(' ')}',
      );
      if (result.p95Ms <= _gateHalveMs) {
        passing = result;
        _log(
          'gate: p95 ${result.p95Ms.toStringAsFixed(2)}ms ≤ $_gateHalveMs ms → 停止减半，N=$n 入选',
        );
        break;
      }
      _log(
        'gate: p95 ${result.p95Ms.toStringAsFixed(2)}ms > $_gateHalveMs ms → N 减半重测',
      );
    }

    // ---- 阶段 2：RSS 内存判据（卡数翻倍对照，在入选 N 档执行）----
    final memoryN = passing?.n ?? _nLadder.last;
    _log(
      '---- memory check at N=$memoryN (empty/$_memoryHalfCards/$_cardCount cards) ----',
    );
    final rssEmptyMb = await _pumpAndSampleRss(tester, 0, memoryN);
    final rssHalfMb = await _pumpAndSampleRss(
      tester,
      _memoryHalfCards,
      memoryN,
    );
    final rssFullMb = await _pumpAndSampleRss(tester, _cardCount, memoryN);
    final firstHalfMb = rssHalfMb - rssEmptyMb;
    final secondHalfMb = rssFullMb - rssHalfMb;
    final memorySuperLinear =
        secondHalfMb >
        _memoryLinearitySlack * (firstHalfMb <= 0 ? 1.0 : firstHalfMb);
    _log(
      'rss: empty=${rssEmptyMb.toStringAsFixed(1)}MB '
      '$_memoryHalfCards=${rssHalfMb.toStringAsFixed(1)}MB '
      '$_cardCount=${rssFullMb.toStringAsFixed(1)}MB',
    );
    _log(
      'increments: 0→$_memoryHalfCards=${firstHalfMb.toStringAsFixed(1)}MB '
      '$_memoryHalfCards→$_cardCount=${secondHalfMb.toStringAsFixed(1)}MB '
      '(linear if second ≤ $_memoryLinearitySlack× first)',
    );

    // ---- 收尾：卸载场景树，释放暂存 controller（组件级资源纪律）----
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    for (final controller in _createdControllers) {
      controller.dispose();
    }
    _createdControllers.clear();

    // ---- 结论（gate 判定规则落款）----
    _log('==================== CONCLUSION ====================');
    if (passing != null) {
      final verdict = passing.p95Ms <= _gateRelaxMs
          ? 'P95 ≤ $_gateRelaxMs ms → 保持（如需可放宽，上限 $_cardCount；'
                '本探针保持保守值：快照行数与会话文件体积正相关，design §9 风险 7）'
          : '$_gateRelaxMs ms < P95 ≤ $_gateHalveMs ms → 保持 N（不放宽、不减半）';
      _log('toolCardSnapshotRows = ${passing.n}');
      _log(
        'gate verdict: N=${passing.n}, p95=${passing.p95Ms.toStringAsFixed(2)}ms '
        '(frames=${passing.frameCount}), memory=${memorySuperLinear ? "超线性 ⚠" : "线性内 ✓"} — $verdict',
      );
      if (memorySuperLinear) {
        _log('⚠ 内存判据未过（RSS 增量超线性）——需随任务回报升级复核');
      }
    } else {
      final worst = results[_nLadder.last];
      _log(
        'ESCALATION: N=5 仍 p95=${worst?.p95Ms.toStringAsFixed(2) ?? "N/A"} ms > $_gateHalveMs ms '
        '→ 极端情况：停止，升级回主对话重新裁决卡体系形态（设计需修订），不自行改设计',
      );
    }
    _log('=====================================================');
  });
}
