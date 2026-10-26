// 批3 T7-R 红测先行：工作台 10 kind → 4 容器收敛（.specs/tasks-v3.5-ui.md
// §3-B01/B02 + §4-P3，UI35-301/305/306/307/309/311~315）。
//
// 方法论约束（任务书）：新枚举（WorkbenchStageContainerKind 等）尚不存在，
// 本文件**禁止引用新类型名**（编译红无法取证）——全部断言用文本 / l10n /
// ValueKey / 几何表达目标行为。当前运行必然收集到断言级红态；实现落地后
// 本文件转绿（连同旧行为用例的适配归实现批处理）。
//
// 明确申报为「实现期编译红 / 不可构造」的项（不在本文件断言）：
// - UI35-302/303/304：容器枚举 / 子态枚举类型断言与「不保留旧枚举」——
//   类型级检查只能实现期编译验证；
// - UI35-307/308 的 AI 推测字段虚线框：StageStructureData 无「AI 推测」
//   字段位，数据无法构造（agentStageAiInferred 渲染前提不存在）——实现批
//   扩数据模型后补断言；
// - UI35-306 的「切 chart 子态不重新取数」spy：今日 grid/chart 是两个独立
//   kind tab（无「切子态」入口），无取数调用面可注入 spy；本文件以
//   「同结果引用收敛为单容器 tab」断言（UI35-306a）表达共享语义，取数
//   计数 spy 在实现批具备切子态入口后补。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_artifact_strip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';
import 'package:dbmaster/theme/design_system.dart';

AgentResultRef _ref(
  String refId, {
  List<Map<String, dynamic>> rows = const [],
  List<String> columns = const ['id', 'name'],
}) => AgentResultRef(
  refId: refId,
  sql: 'SELECT 1',
  rowCount: rows.length,
  columns: columns,
  rows: rows,
);

const _numericRows = <Map<String, dynamic>>[
  {'id': 1, 'amount': 100},
  {'id': 2, 'amount': 200},
];

StageStructureData _structure() => StageStructureData(
  tableName: 'orders',
  columns: [
    DbColumn(name: 'id', type: 'bigint', isPrimaryKey: true, isNullable: false),
    DbColumn(name: 'status', type: 'varchar(20)', isNullable: true),
  ],
  indexes: [
    DbIndex(name: 'idx_status', columns: ['status'], isUnique: false),
  ],
  foreignKeys: const [],
  ddl: 'CREATE TABLE orders (id bigint NOT NULL PRIMARY KEY);',
);

StageExecutionData _executionData(String tabKey) => StageExecutionData(
  tabKey: tabKey,
  title: StageExecutionData.titleWithTimestamp('Execution', DateTime(2026, 1, 1, 12)),
  rows: const [
    StageExecutionRow(sql: 'CREATE INDEX idx ON t (c)', status: StageExecutionStatus.done),
  ],
);

StageOptimizationData _optimizationData() => StageOptimizationData(
  sql: 'SELECT * FROM big_table WHERE val = 1',
  report: PerformanceReport(
    executionPlan: ExecutionPlan(
      databaseType: 'mysql',
      originalQuery: 'SELECT * FROM big_table WHERE val = 1',
      steps: [
        PlanStep(
          id: 1,
          selectType: 'SIMPLE',
          table: 'big_table',
          scanType: ScanType.fullTable,
          estimatedRows: 12000,
        ),
      ],
      rawData: const <String, dynamic>{},
      analyzedAt: DateTime(2026, 1, 1),
    ),
    bottlenecks: [
      Bottleneck(
        type: BottleneckType.fullTableScan,
        description: 'Full table scan',
        affectedTable: 'big_table',
        severity: Severity.high,
      ),
    ],
    indexRecommendations: const [],
    queryRewrites: const <QueryRewrite>[],
    summary: 'sample summary',
    analysisDuration: Duration.zero,
  ),
);

/// 舞台 + 产物条同树（shell 底部形态；条高由自身 token 决定，不紧高度包裹）。
/// observe 槽消费 AppProvider（WorkbenchObserveContent），统一外层注入。
Widget _wrap(WorkbenchStageController controller, AppProvider app) =>
  ChangeNotifierProvider<AppProvider>.value(
    value: app,
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 1024,
            height: 768,
            child: Column(
              children: [
                Expanded(child: WorkbenchStage(controller: controller)),
                WorkbenchArtifactStrip(controller: controller),
              ],
            ),
          ),
        ),
      ),
    ),
  );

Future<void> _pumpStage(
  WidgetTester tester,
  WorkbenchStageController controller,
  AppProvider app,
) async {
  await tester.pumpWidget(_wrap(controller, app));
  await tester.pumpAndSettle();
}

Finder _tabBarText(String text) => find.descendant(
  of: find.byKey(WorkbenchStage.tabBarKey),
  matching: find.text(text),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorkbenchStageController controller;
  late AppProvider app;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = WorkbenchStageController();
    app = AppProvider();
  });

  tearDown(() {
    controller.dispose();
    app.dispose();
  });

  group('UI35-311~313 产物槽三态（B-02）', () {
    test('UI35-311a token：artifactStripHeight == 36（唯一 token 覆盖式改值）', () {
      expect(
        AppDesignSystem.artifactStripHeight,
        36.0,
        reason: 'B-02：design_system.dart artifactStripHeight 32→36',
      );
    });

    testWidgets('UI35-311b 有 pin：条高 == artifactStripHeight（token 引用）', (
      tester,
    ) async {
      controller.pinArtifact(_ref('res_1'), 'R1');
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: WorkbenchArtifactStrip(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byKey(WorkbenchArtifactStrip.stripKey)).height,
        closeTo(AppDesignSystem.artifactStripHeight, 1.0),
      );
    });

    testWidgets('UI35-312 零 pin 且舞台可见：条 0px 不参与布局', (tester) async {
      controller.setStageVisible(true);
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: WorkbenchArtifactStrip(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 实现可二选一：条 widget 卸载（findsNothing）或保留 0 高占位；
      // 布局语义断言 = 占位高度 0（现红：条恒 32 参与布局）。
      final strip = find.byKey(WorkbenchArtifactStrip.stripKey);
      final height = strip.evaluate().isEmpty
          ? 0.0
          : tester.getRect(strip).height;
      expect(
        height,
        0.0,
        reason: 'B-02：舞台可见且 pinned=0 → 条 0px 不参与布局',
      );
    });

    testWidgets('UI35-313 舞台收起态：展开入口条保留（agentStageToggle）', (tester) async {
      // 零 pin + 舞台收起（默认）→ 收起态展开入口条不 0px。
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: WorkbenchArtifactStrip(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.stageVisible, isFalse);
      expect(find.byKey(WorkbenchArtifactStrip.toggleKey), findsOneWidget);
      expect(find.text('Stage'), findsOneWidget);
    });
  });

  group('UI35-314 舞台开合钮宿主（容器 tab 条右端）', () {
    testWidgets('tooltip workbenchCollapseStage 的控件宿主 = 舞台 tab 条右端；'
        '产物条子树无该钮', (tester) async {
      controller.openGrid(_ref('res_1', rows: _numericRows), null);
      await _pumpStage(tester, controller, app);

      // 新 tooltip 文案（workbenchCollapseStage = "Collapse stage"，小写 s）。
      final collapse = find.byTooltip('Collapse stage');
      expect(
        collapse,
        findsOneWidget,
        reason: 'B-02：开合钮 tooltip 迁 workbenchCollapseStage'
            '（现 tooltip = agentStageCollapse "Collapse Stage"）',
      );
      // 宿主 = 舞台 tab 条（祖先 finder）。
      expect(
        find.ancestor(
          of: collapse,
          matching: find.byKey(WorkbenchStage.tabBarKey),
        ),
        findsOneWidget,
        reason: 'B-02：开合钮宿主 = 容器 tab 条',
      );
      // 贴右缘（右端 24×24 簇）。
      final barRect = tester.getRect(find.byKey(WorkbenchStage.tabBarKey));
      final btnRect = tester.getRect(collapse.first);
      expect(
        barRect.right - btnRect.right,
        lessThan(48.0),
        reason: '开合钮贴 tab 条右缘',
      );
      // 旧文案（agentStageCollapse = "Collapse Stage"）退役。
      expect(
        find.byTooltip('Collapse Stage'),
        findsNothing,
        reason: '旧 agentStageCollapse tooltip 不再使用',
      );
      // 产物条子树无开合钮（钮已迁出产物条）。
      expect(
        find.descendant(
          of: find.byType(WorkbenchArtifactStrip),
          matching: find.byTooltip('Collapse stage'),
        ),
        findsNothing,
      );
    });
  });

  group('UI35-301/309 容器标签（文本级，B-01）', () {
    testWidgets('四容器同台：tab 条出现 SQL Studio / Data & Viz / Schema / '
        'Diagnostics；旧 10 kind 标签退出 tab 条', (tester) async {
      controller.pinArtifact(_ref('res_grid', rows: _numericRows), null); // Data&Viz
      controller.openStructure(_structure()); // Schema
      controller.openEditorSlot('SELECT * FROM orders'); // SQL Studio
      controller.openExecution(_executionData('plan_1')); // Diagnostics
      await _pumpStage(tester, controller, app);

      expect(_tabBarText('SQL Studio'), findsOneWidget);
      expect(_tabBarText('Data & Viz'), findsOneWidget);
      expect(_tabBarText('Schema'), findsOneWidget);
      expect(_tabBarText('Diagnostics'), findsOneWidget);

      // 旧 kind 标签退出 tab 条（B-01：不保留旧枚举，Dart 编译期完备迁移）。
      for (final old in const [
        'Grid',
        'Structure',
        'Editor',
        'Execution',
        'Sessions',
        'History',
        'Saved queries',
        'Observe',
        'Optimization',
        'Chart',
      ]) {
        expect(
          _tabBarText(old),
          findsNothing,
          reason: '旧 kind 标签「$old」不应出现在容器 tab 条',
        );
      }
    });

    testWidgets('UI35-309 execution + observe 同归 Diagnostics 容器：'
        'Explain Plan / Live Monitor 子态分段共存', (tester) async {
      controller.openExecution(_executionData('plan_1'));
      controller.openObserve();
      await _pumpStage(tester, controller, app);

      expect(_tabBarText('Diagnostics'), findsOneWidget);
      expect(find.text('Explain Plan'), findsOneWidget);
      expect(find.text('Live Monitor'), findsOneWidget);
      // 旧独立容器级标签退出。
      expect(_tabBarText('Execution'), findsNothing);
      expect(_tabBarText('Observe'), findsNothing);
    });
  });

  group('UI35-305 SQL Studio Edit/Diff 分段', () {
    testWidgets('optimization 数据 → SQL Studio 容器 + Diff 子态；Editor 可回', (
      tester,
    ) async {
      controller.openOptimization(_optimizationData());
      await _pumpStage(tester, controller, app);

      expect(_tabBarText('SQL Studio'), findsOneWidget);
      expect(_tabBarText('Optimization'), findsNothing);
      // 子态分段：Diff（agentStageSegDiff）+ 可切回的编辑子态
      // （标签沿既有 agentStageTabEditor = "Editor"）。
      expect(find.text('Diff'), findsOneWidget);
      expect(find.text('Editor'), findsOneWidget);
    });
  });

  group('UI35-306a Data & Viz 共享结果集（单容器收敛）', () {
    testWidgets('同结果引用 grid + chart → 收敛为单个 Data & Viz 容器 tab', (
      tester,
    ) async {
      final shared = _ref('res_shared', rows: _numericRows);
      controller.openGrid(shared, null);
      controller.openChart(shared, null);
      await _pumpStage(tester, controller, app);

      expect(_tabBarText('Data & Viz'), findsOneWidget);
      expect(_tabBarText('Grid'), findsNothing);
      expect(_tabBarText('Chart'), findsNothing);
      // 「切子态不重新取数」spy 申报为不可构造（见文件头）——共享结果集语义
      // 由单容器收敛 + 数据挂 tab 载荷表达；实现批具备子态切换入口后补计数
      // 断言。
    });
  });

  group('UI35-307/308 Schema 容器', () {
    testWidgets('structure 数据 → Schema 容器标签；旧 Structure 标签退出', (
      tester,
    ) async {
      controller.openStructure(_structure());
      await _pumpStage(tester, controller, app);

      expect(_tabBarText('Schema'), findsOneWidget);
      expect(_tabBarText('Structure'), findsNothing);
      // 三子段文本（Columns/Indexes/DDL，agentStageSchemaColumns 等）。
      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('Indexes'), findsOneWidget);
      expect(find.text('DDL'), findsOneWidget);
      // AI 推测字段虚线框（agentStageAiInferred）申报为不可构造：数据模型
      // 无 AI 推测字段位（见文件头），实现批扩 StageStructureData 后补断言。
    });
  });

  group('UI35-315 产物芯片路由（container + subKind）', () {
    testWidgets('pinned 执行产物芯片 → 点击 → Diagnostics 容器 + Explain Plan '
        '子态', (tester) async {
      final tab = controller.openExecution(_executionData('plan_1'));
      controller.setPinned(0, true);
      await _pumpStage(tester, controller, app);

      // 芯片在产物条；点击 = 开舞台并路由容器 + 子态。
      await tester.tap(
        find.byKey(WorkbenchArtifactStrip.itemKey(tab.id)),
      );
      await tester.pumpAndSettle();

      expect(controller.stageVisible, isTrue);
      expect(_tabBarText('Diagnostics'), findsOneWidget);
      expect(_tabBarText('Execution'), findsNothing);
      expect(find.text('Explain Plan'), findsOneWidget);
    });
  });
}
