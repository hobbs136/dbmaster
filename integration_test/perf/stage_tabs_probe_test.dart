// ============================================================================
// B1 批级性能探针：舞台 tab 打开/切换帧时延（AI 工作台先行批 W6 收口任务，
// 任务书 tasks-workbench-first-batch.md §6.8 探针口径，v1 §5-6 扩展定案）
//
// 场景（两场景，N=10 取 P95，门 = ≤16.7ms，profile 模式判定）：
//   ① openGrid 打开至首帧（3000 行行限载荷）——每次迭代在既有舞台
//     （编辑器槽激活）上打开一个新 3000 行网格 tab，采集打开后首帧的
//     build+raster 合计帧耗时为样本，迭代间复位（关 tab 回编辑器槽）。
//   ② 20 tab 混合集合逐个激活切换帧时延——grid×6（各 3000 行载荷）/
//     chart×4 / structure×2 / editor×1 / sessionList / history /
//     savedQueries / execution×4 凑足 20，10 轮 × 逐 tab 激活，每次切换
//     的首帧为样本（200 样本取 P95）。
//   RSS 增量记录入档不设门（列表类 tab 轻量；网格/图表内存沿
//   AgentResultRef 行限语义既有）。
//
// gate（判定规则）：
//   两场景各自 P95 ≤ 16.7ms——profile 模式下硬断言（批级门）；
//   debug 模式只记录不断言（JIT 数值仅相对参考）。
//
// 运行（对齐 tool_card_probe_test.dart 既有探针）：
//   flutter test -d windows integration_test/perf/stage_tabs_probe_test.dart
//   （debug 模式数值仅相对参考；结论以 profile 为准）
//   flutter drive --profile -d windows \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf/stage_tabs_probe_test.dart
//
// 探针是批级门 + 按需复跑（沿 T01 先例：不进 CI 常驻门槛）。
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
// hide：models 的 ProcessInfo（T002 进程列表模型）与 dart:io ProcessInfo
// 撞名——本探针的 RSS 采样用后者。
import 'package:dbmaster/models/database_models.dart' hide ProcessInfo;
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';

import '../helpers/ai_session_isolation_helper.dart';

// ---- 探针参数（任务书 §6.8 口径锁定：两场景 / N=10 / 门 16.7ms / 20 tab）----

/// 迭代轮数（两场景各自 N=10）。
const int _rounds = 10;

/// 场景①网格载荷行数（行限口径）。
const int _gridRows = 3000;

/// 场景②混合集合 tab 数（任务书锁定 20）。
const int _mixedTabCount = 20;

/// 帧时延门（P95，build+raster 合计）。
const double _gateP95Ms = 16.7;

/// 舞台探测区几何（真实舞台并置态宽度量级：≥480 下限以上取 860×820）。
const double _stageWidth = 860;
const double _stageHeight = 820;

void _log(Object message) {
  // ignore: avoid_print
  print(message);
}

// ---- 数据合成（不连库）----

/// 8 列固定列名（const，避免测量路径每帧生成）。
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

/// 合成网格行（map 形态，AgentResultRef 契约）。
List<Map<String, dynamic>> _makeGridRows(int rows) {
  return List<Map<String, dynamic>>.generate(rows, (r) {
    return <String, dynamic>{
      for (var c = 0; c < _columns.length; c++)
        _columns[c]: c == 0 ? r : 'value_${r}_$c',
    };
  });
}

/// 网格结果引用（[rowCount] 保留全量口径，rows = 行限内载荷）。
AgentResultRef _gridRef(String refId, int rows) => AgentResultRef(
  refId: refId,
  sql: 'SELECT * FROM probe_big',
  rowCount: rows,
  columns: _columns,
  rows: _makeGridRows(rows),
);

/// 图表结果引用（小体量数值行；chart 槽的真实渲染载荷）。
AgentResultRef _chartRef(String refId) => AgentResultRef(
  refId: refId,
  sql: 'SELECT id, amount FROM probe_chart',
  rowCount: 200,
  columns: const ['id', 'amount'],
  rows: List<Map<String, dynamic>>.generate(
    200,
    (r) => <String, dynamic>{'id': r, 'amount': r * 3},
  ),
);

/// 结构卡数据（describe 四件小体量形态）。
StageStructureData _structureData(String table) => StageStructureData(
  tableName: table,
  columns: [
    for (var i = 0; i < 8; i++)
      DbColumn(
        name: 'col_$i',
        type: i == 0 ? 'bigint' : 'varchar(64)',
        isPrimaryKey: i == 0,
        isNullable: i != 0,
      ),
  ],
  indexes: [
    DbIndex(name: 'idx_col_1', columns: const ['col_1'], isUnique: false),
    DbIndex(name: 'uk_col_2', columns: const ['col_2'], isUnique: true),
  ],
  foreignKeys: [
    ForeignKey(
      name: 'fk_probe',
      table: table,
      column: 'col_1',
      referencedTable: 'probe_parent',
      referencedColumn: 'id',
    ),
  ],
  ddl: 'CREATE TABLE $table (col_0 bigint NOT NULL PRIMARY KEY);',
);

/// execution tab 数据（40 语句混合批形态：done/failed/skipped 三态齐备，
/// 失败行置顶 + 错误块形态的真实载荷）。
StageExecutionData _executionData(String tabKey) => StageExecutionData(
  tabKey: tabKey,
  title: 'Execution probe $tabKey',
  rows: [
    for (var i = 0; i < 40; i++)
      StageExecutionRow(
        sql: i % 7 == 3
            ? "UPDATE probe_t SET label = 'x' WHERE id = $i LIMIT 1"
            : "INSERT INTO probe_t (id, label) VALUES ($i, 'v$i')",
        status: i % 7 == 3
            ? StageExecutionStatus.failed
            : (i % 11 == 10
                  ? StageExecutionStatus.skipped
                  : StageExecutionStatus.done),
        affectedRows: i % 7 == 3 ? null : 1,
        durationMs: i % 7 == 3 ? null : 3 + (i % 5),
        error: i % 7 == 3
            ? "boom: duplicate key entry 'v$i' for key 'PRIMARY' "
                  "(engine error text sample, statement $i)"
            : null,
      ),
  ],
);

// ---- 帧采集（tool_card_probe 同款口径：build+raster 合计，滞后上报补泵）----

class _FrameCollector {
  /// build + raster 合计帧耗时（ms，与 tool_card 探针 gate 同口径）。
  final List<double> frameMs = <double>[];

  void onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      frameMs.add(
        (timing.buildDuration.inMicroseconds +
                timing.rasterDuration.inMicroseconds) /
            1000.0,
      );
    }
  }
}

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.of(values)..sort();
  var idx = (p * sorted.length).ceil() - 1;
  if (idx < 0) idx = 0;
  if (idx >= sorted.length) idx = sorted.length - 1;
  return sorted[idx];
}

/// 采集「一次动作的首帧」：挂回调 → [action] → pump 一帧 → 补泵泄放滞后
/// 上报 → 摘回调；返回首帧耗时（ms）。补泵帧在首帧之后入账，不影响
/// 「首帧」样本（FrameTiming 随后续帧滞后批量上报，tool_card 探针实测坑——
/// 不补泵首帧永不入账）。
Future<double> _measureFirstFrameMs(
  WidgetTester tester,
  void Function() action,
) async {
  final collector = _FrameCollector();
  SchedulerBinding.instance.addTimingsCallback(collector.onTimings);
  action();
  await tester.pump();
  // 补泵泄放（真实延时驱动引擎上报）。
  for (var i = 0; i < 6 && collector.frameMs.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  SchedulerBinding.instance.removeTimingsCallback(collector.onTimings);
  expect(collector.frameMs, isNotEmpty, reason: '首帧样本应入账（补泵后）');
  return collector.frameMs.first;
}

// ---- 场景宿主 ----

Widget _buildProbeApp(WorkbenchStageController controller, AppProvider app) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: app,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _stageWidth,
            height: _stageHeight,
            child: WorkbenchStage(controller: controller),
          ),
        ),
      ),
    ),
  );
}

/// RSS 采样（中位数口径降噪，tool_card 探针同款；记录入档不设门）。
Future<double> _sampleRssMedianMb() async {
  final values = <int>[];
  for (var i = 0; i < 5; i++) {
    values.add(ProcessInfo.currentRss);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  values.sort();
  return values[2] / (1024 * 1024);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mode = kDebugMode
      ? 'debug（数值仅相对参考，gate 不断言）'
      : kProfileMode
      ? 'profile（gate 结论口径）'
      : 'release';

  testWidgets(
    'B1 stage tabs probe: openGrid first-frame (3000 rows) + 20-tab switching',
    (tester) async {
      _log('==================== B1 STAGE TABS PROBE ====================');
      _log('MODE: $mode');
      _log(
        'scenarios: ① openGrid first frame ($_gridRows rows) ×$_rounds; '
        '② $_mixedTabCount-tab mixed set switching ×$_rounds rounds',
      );

      tester.view.physicalSize = const Size(1360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Fix-H 同款隔离：会话管理器落临时目录，不污染真实存储。
      final app = AppProvider(
        aiSessionManager: createIsolatedAiSessionManager(),
      );
      addTearDown(app.dispose);

      final rssBaselineMb = await _sampleRssMedianMb();

      // ── 场景①：openGrid 打开至首帧（3000 行行限载荷）──────────────────
      final controller1 = WorkbenchStageController();
      addTearDown(controller1.dispose);
      // 基线舞台：编辑器槽激活（打开网格的对比基准态）。
      controller1.openEditorSlot('SELECT 1');
      await tester.pumpWidget(_buildProbeApp(controller1, app));
      await tester.pumpAndSettle();

      // 预热一次（字体/渲染器注册表首载不入样）。
      final warmup = controller1.openGrid(_gridRef('warmup', 64), 'warmup');
      await tester.pumpAndSettle();
      controller1.closeTab(
        controller1.tabs.indexWhere((t) => t.id == warmup.id),
      );
      controller1.activateTab(0);
      await tester.pumpAndSettle();

      final firstFrameSamples = <double>[];
      for (var i = 0; i < _rounds; i++) {
        late final WorkbenchStageTab opened;
        final sample = await _measureFirstFrameMs(tester, () {
          opened = controller1.openGrid(_gridRef('probe_open_$i', _gridRows), 'P$i');
        });
        firstFrameSamples.add(sample);
        // 复位（不采样）：关网格 tab、回激活编辑器槽。
        controller1.closeTab(
          controller1.tabs.indexWhere((t) => t.id == opened.id),
        );
        controller1.activateTab(0);
        await tester.pumpAndSettle();
      }
      final openP50 = _percentile(firstFrameSamples, 0.50);
      final openP95 = _percentile(firstFrameSamples, 0.95);
      final openMax = firstFrameSamples.reduce((a, b) => a > b ? a : b);
      _log(
        'scenario ① openGrid first frame ($_gridRows rows): '
        'p50=${openP50.toStringAsFixed(2)}ms '
        'p95=${openP95.toStringAsFixed(2)}ms '
        'max=${openMax.toStringAsFixed(2)}ms '
        'samples=${firstFrameSamples.length}',
      );

      final rssAfterOpenMb = await _sampleRssMedianMb();

      // ── 场景②：20 tab 混合集合逐个激活切换帧时延 ─────────────────────
      final controller2 = WorkbenchStageController();
      addTearDown(controller2.dispose);
      // 配比（任务书 §6.8）：grid×6（各 3000 行）/ chart×4 / structure×2 /
      // editor×1 / sessionList / history / savedQueries / execution×4 = 20。
      for (var i = 0; i < 6; i++) {
        controller2.openGrid(_gridRef('mix_grid_$i', _gridRows), 'Grid $i');
      }
      for (var i = 0; i < 4; i++) {
        controller2.openChart(_chartRef('mix_chart_$i'), null);
      }
      controller2.openStructure(_structureData('probe_a'));
      controller2.openStructure(_structureData('probe_b'));
      controller2.openEditorSlot('SELECT * FROM probe_editor');
      controller2.openSessions();
      controller2.openHistory();
      controller2.openSavedQueries();
      for (var i = 0; i < 4; i++) {
        controller2.openExecution(_executionData('mix_exec_$i'));
      }
      expect(
        controller2.tabs,
        hasLength(_mixedTabCount),
        reason: '混合集合凑足 20 tab（任务书口径）',
      );

      await tester.pumpWidget(_buildProbeApp(controller2, app));
      await tester.pumpAndSettle();
      // 列表类槽位（历史/保存的查询/会话）异步装载泄放后再测量。
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final rssMixedMb = await _sampleRssMedianMb();

      final switchSamples = <double>[];
      for (var round = 0; round < _rounds; round++) {
        for (var index = 0; index < _mixedTabCount; index++) {
          final sample = await _measureFirstFrameMs(tester, () {
            controller2.activateTab(index);
          });
          switchSamples.add(sample);
        }
      }
      final switchP50 = _percentile(switchSamples, 0.50);
      final switchP95 = _percentile(switchSamples, 0.95);
      final switchMax = switchSamples.reduce((a, b) => a > b ? a : b);
      _log(
        'scenario ② $_mixedTabCount-tab switching: '
        'p50=${switchP50.toStringAsFixed(2)}ms '
        'p95=${switchP95.toStringAsFixed(2)}ms '
        'max=${switchMax.toStringAsFixed(2)}ms '
        'samples=${switchSamples.length} ($_rounds rounds × $_mixedTabCount)',
      );

      final rssFinalMb = await _sampleRssMedianMb();

      // 收尾：卸载场景树（资源纪律）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // ---- RSS 记录入档（不设门）----
      _log(
        'rss: baseline=${rssBaselineMb.toStringAsFixed(1)}MB '
        'after-scenario-①=${rssAfterOpenMb.toStringAsFixed(1)}MB '
        'mixed-20-tab=${rssMixedMb.toStringAsFixed(1)}MB '
        'final=${rssFinalMb.toStringAsFixed(1)}MB',
      );

      // ---- 结论（gate 判定：profile 硬门 / debug 仅记录）----
      _log('==================== CONCLUSION ====================');
      _log(
        'gate p95 ≤ ${_gateP95Ms}ms: ① open=${openP95.toStringAsFixed(2)}ms '
        '${openP95 <= _gateP95Ms ? "PASS" : "FAIL"} · '
        '② switch=${switchP95.toStringAsFixed(2)}ms '
        '${switchP95 <= _gateP95Ms ? "PASS" : "FAIL"}',
      );
      _log('=====================================================');
      if (kProfileMode) {
        expect(
          openP95,
          lessThanOrEqualTo(_gateP95Ms),
          reason: '批级门：场景① openGrid 首帧 P95 超 16.7ms（profile）',
        );
        expect(
          switchP95,
          lessThanOrEqualTo(_gateP95Ms),
          reason: '批级门：场景② 20 tab 切换 P95 超 16.7ms（profile）',
        );
      }
    },
  );
}
