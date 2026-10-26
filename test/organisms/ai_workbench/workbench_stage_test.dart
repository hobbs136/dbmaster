// T24 WorkbenchStage 组件测试（ui 规格 design-ai-agent-ui.md §5.4 验收 +
// §5.2/§5.3 结构与语义）。
//
// 覆盖：
// - §5.4-1（舞台侧）：1024×768 无 overflow（三列几何探针归 T27 shell，见
//   各用例注释）；
// - §5.4-4：tab 条高 32 ±1；激活底 primaryContainer / 标签 textPrimary（色
//   断言，规格明示）；标签超 200 → ellipsis + tooltip 全 label；
// - §5.4-5：20 tab 横向滚动可用、新开 tab 自动滚入视口、←/→/Home/End
//   roving 键盘可达全部 tab；
// - §5.4-6（AC5.5）：关闭未保存编辑器槽 → 确认；确认前 tab 不消失；取消
//   保留 / 放弃关闭；openEditorSlot 槽策略（干净复用 / 脏新开）；
// - §5.4-7：空态三元素齐且无按钮；
// - §5.4-8（AC5.3）：图表不适配 → 内联错误 + [在经典中打开] 出口，无 dialog；
// - §5.3 打开时机：openXxx 开舞台 + 激活；pinArtifact 不改可见性（§6.3）；
// - §5.3 网格：0 行沿既有「No data」空态；有数据走注册表渲染器；
// - §5.3 结构卡：describe 四件分组与徽标渲染；
// - 编辑器槽：载入不执行（无执行入口）+ 载入文本可见。
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_focus_zones.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_mongo_schema_view.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_content.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/organisms/mongodb/schema_view/schema_nested_expander.dart';
import 'package:dbmaster/organisms/query_optimizer/query_plan_visualizer.dart';
import 'package:dbmaster/organisms/results/chart_view.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';
import 'package:dbmaster/theme/app_colors.dart';

Widget _wrap(Widget child, {double width = 1024, double height = 768}) =>
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
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

AgentResultRef _ref(
  String refId, {
  String sql = 'SELECT 1',
  List<String> columns = const ['id', 'name'],
  List<Map<String, dynamic>> rows = const [],
  int? rowCount,
}) => AgentResultRef(
  refId: refId,
  sql: sql,
  rowCount: rowCount ?? rows.length,
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
  foreignKeys: [
    ForeignKey(
      name: 'fk_customer',
      table: 'orders',
      column: 'customer_id',
      referencedTable: 'customers',
      referencedColumn: 'id',
    ),
  ],
  ddl: 'CREATE TABLE orders (id bigint NOT NULL PRIMARY KEY);',
);

/// 2b.3 报告样例（真实模型值对象直构，不走服务）：全表扫描计划 + 瓶颈 +
/// 带 DDL 的索引推荐（「应用此索引」按钮渲染判据）。[summary] 可变供
/// 复用刷新「载荷替换」断言区分新旧报告。
PerformanceReport _optimizationReport({String summary = 'sample summary'}) {
  return PerformanceReport(
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
        description: 'Table big_table is using a full table scan',
        affectedTable: 'big_table',
        severity: Severity.high,
      ),
    ],
    indexRecommendations: [
      IndexRecommendation(
        tableName: 'big_table',
        indexName: 'idx_big_table_val',
        columns: ['val'],
        reason: 'Full table scan detected',
        ddlStatement: 'CREATE INDEX idx_big_table_val ON big_table (val)',
      ),
    ],
    queryRewrites: const <QueryRewrite>[],
    summary: summary,
    analysisDuration: Duration.zero,
  );
}

/// 2b.2b 槽测试桩：镜像 AppProvider Mongo schema facade 三方法（2b.2a 测试
/// 同款桩口径）：记录 load 三参（载荷透传断言用）+ 自动落地种子 schema
/// （内容态断言用），loading 守卫语义同真实 facade（app_provider.dart:2898）。
class _FakeMongoStageAppProvider extends AppProvider {
  String? lastConnectionId;
  String? lastDatabase;
  String? lastCollection;

  Map<String, dynamic>? _schema;
  bool _loading = false;

  @override
  Map<String, dynamic>? getMongoDBSchema(
    String connectionId,
    String collectionName,
  ) => _schema;

  @override
  bool isLoadingMongoDBSchema(String connectionId, String collectionName) =>
      _loading;

  @override
  Future<void> loadMongoDBSchema(
    String connectionId,
    String databaseName,
    String collectionName, {
    int sampleSize = 100,
  }) async {
    lastConnectionId = connectionId;
    lastDatabase = databaseName;
    lastCollection = collectionName;
    if (_loading) return;
    _loading = true;
    notifyListeners();
    await Future<void>.microtask(() {});
    _schema = <String, dynamic>{
      'collectionName': collectionName,
      'totalSampled': 10,
      'fields': <String, dynamic>{
        'age': <String, dynamic>{'type': 'int', 'occurrence': 9},
        'name': <String, dynamic>{'type': 'String', 'occurrence': 10},
      },
    };
    _loading = false;
    notifyListeners();
  }
}

Future<void> _pump(
  WidgetTester tester,
  WorkbenchStageController controller, {
  double width = 1024,
  double height = 768,
  void Function(String sql)? onOpenInClassic,
  WorkbenchFocusZoneRegistry? zoneRegistry,
}) async {
  await tester.pumpWidget(
    _wrap(
      WorkbenchStage(
        controller: controller,
        onOpenInClassic: onOpenInClassic,
        zoneRegistry: zoneRegistry,
      ),
      width: width,
      height: height,
    ),
  );
  await tester.pumpAndSettle();
}

/// 当前聚焦的舞台 tab id（焦点节点 debugLabel = `stage_tab_<id>`）。
String? _focusedTabId() => FocusManager.instance.primaryFocus?.debugLabel
    ?.replaceFirst('stage_tab_', '');

/// 主焦点是否落在 [key] 元素（或其后代）内。
bool _focusWithinKey(Key key) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  for (final Element keyed in find.byKey(key).evaluate()) {
    if (identical(ctx, keyed)) return true;
    var found = false;
    (ctx as Element).visitAncestorElements((ancestor) {
      if (identical(ancestor, keyed)) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) return true;
  }
  return false;
}

/// 主焦点是否落在 [key] 元素的**子树**内（尾部两钮的 Focus 是 keyed 容器
/// 的父级——焦点节点 context = Focus 元素，keyed 元素在其后代方向；与
/// [_focusWithinKey] 的祖先链方向互补）。
bool _focusWithinKeySubtree(Key key) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  for (final Element keyed in find.byKey(key).evaluate()) {
    if (identical(ctx, keyed)) return true;
    var found = false;
    keyed.visitAncestorElements((ancestor) {
      if (identical(ancestor, ctx)) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) return true;
  }
  return false;
}

/// 成对发送按下/抬起（AGENTS.md §8-10：模拟键盘事件须遵循事件模型，
/// 缺抬起会触发 HardwareKeyboard 断言）。
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
}

void main() {
  late WorkbenchStageController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = WorkbenchStageController();
  });

  tearDown(() {
    controller.dispose();
  });

  group('§5.4-1（舞台侧）/ §5.4-4 tab 条几何与激活态', () {
    testWidgets('1024×768 下三类 tab 并存无 overflow；tab 条高 32', (tester) async {
      controller.openGrid(_ref('res_1', rows: _numericRows), '查询结果');
      controller.openStructure(_structure());
      controller.openEditorSlot('SELECT * FROM orders');
      await _pump(tester, controller);
      // 三列布局（会话栏 44/240、对话列 360、舞台 ≥480）归 T27 shell 装配；
      // 此处锁定舞台本体在最小窗口尺寸下零溢出。
      expect(tester.takeException(), isNull);
      final barRect = tester.getRect(find.byKey(WorkbenchStage.tabBarKey));
      expect(barRect.height, closeTo(AppDesignSystem.tabBarHeight, 1.0));
    });

    testWidgets(
      '激活 tab 底 primaryContainer + 标签 textPrimary；非激活 textSecondary',
      (tester) async {
        // 批3：tab 条标签恒为容器标签（同容器多 tab 标签同文——用 itemKey
        // descendant 定位各自标签，不以文本全局定位）。
        final t1 = controller.openGrid(_ref('res_1', rows: _numericRows), 'R1');
        controller.openGrid(_ref('res_2', rows: _numericRows), 'R2');
        controller.activateTab(0);
        await _pump(tester, controller);

        final ctx = tester.element(find.byKey(WorkbenchStage.tabBarKey));
        final colors = ctx.themeColors;

        // tab 项本体即带 itemKey 的 AnimatedContainer（§5.4-4 色断言）。
        final active = tester.widget<AnimatedContainer>(
          find.byKey(WorkbenchStage.tabItemKey(t1.id)),
        );
        final activeDecoration = active.decoration as BoxDecoration;
        expect(activeDecoration.color, colors.primaryContainer);

        final label = tester.widget<Text>(
          find.descendant(
            of: find.byKey(WorkbenchStage.tabItemKey(t1.id)),
            matching: find.byType(Text),
          ),
        );
        expect(label.style?.color, colors.textPrimary);
        expect(label.data, 'Data & Viz', reason: '容器标签（注册表单源）');

        final inactive = tester.widget<AnimatedContainer>(
          find.byKey(
            WorkbenchStage.tabItemKey(controller.tabs[1].id),
          ),
        );
        expect(
          (inactive.decoration as BoxDecoration).color,
          Colors.transparent,
        );
        final inactiveLabel = tester.widget<Text>(
          find.descendant(
            of: find.byKey(WorkbenchStage.tabItemKey(controller.tabs[1].id)),
            matching: find.byType(Text),
          ),
        );
        expect(inactiveLabel.style?.color, colors.textSecondary);
      },
    );

    testWidgets('tab 上限宽 200 + tooltip 承载容器标签（批3：标签恒容器级）', (tester) async {
      final tab = controller.openGrid(
        _ref('res_1', rows: _numericRows),
        'A very long artifact label that must be truncated somewhere',
      );
      await _pump(tester, controller);

      // tab 条显示容器标签（title 不再上 tab 条——产物芯片与重开菜单消费）。
      final label = tester.widget<Text>(find.text('Data & Viz'));
      expect(label.maxLines, 1);
      expect(find.byTooltip('Data & Viz'), findsOneWidget);
      final itemRect = tester.getRect(
        find.byKey(WorkbenchStage.tabItemKey(tab.id)),
      );
      expect(
        itemRect.width,
        lessThanOrEqualTo(AppDesignSystem.workbenchStageTabMaxWidth + 1),
      );
      // 长 title 不上 tab 条（容器收敛后条内零重名歧义）。
      expect(
        find.text('A very long artifact label that must be truncated somewhere'),
        findsNothing,
      );
    });
  });

  group('§5.4-5 溢出滚动与键盘', () {
    testWidgets('20 tab 横向滚动可用；新开 tab 自动滚入视口', (tester) async {
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        ids.add(
          controller.openGrid(_ref('res_$i', rows: _numericRows), 'Tab $i').id,
        );
      }
      await _pump(tester, controller);

      // 溢出 → 横向滚动可用（不换行、不做溢出下拉）。
      final scrollable = tester.widget<Scrollable>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.axisDirection, AxisDirection.right);
      final scrollPos = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollPos.position.maxScrollExtent, greaterThan(0));

      // 新开（第 21 个）tab 自动滚入视口（§5.2 溢出规则）。
      final fresh = controller.openGrid(
        _ref('res_new', rows: _numericRows),
        'Tab new',
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(WorkbenchStage.tabItemKey(fresh.id)),
      );
      expect(rect.right, lessThanOrEqualTo(1024));
      expect(rect.left, greaterThanOrEqualTo(0));
    });

    testWidgets('←/→/Home/End roving 键盘可达全部 tab；Enter 激活；尾部两钮入序列', (tester) async {
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        ids.add(
          controller.openGrid(_ref('res_$i', rows: _numericRows), 'Tab $i').id,
        );
      }
      await _pump(tester, controller);

      // 激活 tab（19）已被自动滚入视口：点它进入 tab 焦点组（onActivate 内
      // requestFocus）。批3：标签恒容器级——以 itemKey 定位点击。
      await tester.tap(find.byKey(WorkbenchStage.tabItemKey(ids[19])));
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[19]);

      // Home → 首个 tab（滚动跟随焦点）。
      await _press(tester, LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[0]);

      // End → 收起钮（S9 语义变更：条内最后一项 = 尾部收起钮，非末 tab）。
      await _press(tester, LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(_focusWithinKeySubtree(WorkbenchStage.collapseKey), isTrue);

      // ArrowLeft 从收起钮 → 重开钮（新增覆盖：尾部两钮相邻）。
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusWithinKeySubtree(WorkbenchStage.reopenButtonKey), isTrue);

      // ArrowLeft 从重开钮 → 末 tab。
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[19]);

      // 全程逐个可达（Home 后 19 次 → 到末位）。
      await _press(tester, LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[0]);
      for (var i = 0; i < 19; i++) {
        await _press(tester, LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      expect(_focusedTabId(), ids[19]);

      // Enter 激活（焦点在 19）。
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.activeTabIndex, 19);

      // ArrowRight 越过末 tab → 重开钮 → 收起钮（S9 序列尾部）。
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_focusWithinKeySubtree(WorkbenchStage.reopenButtonKey), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_focusWithinKeySubtree(WorkbenchStage.collapseKey), isTrue);

      // Enter 在收起钮 → 收起舞台（A1-6；舞台组件自身不入树语义由宿主
      // 决定——此处只断言 controller 可见性翻转）。
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.stageVisible, isFalse);
    });
  });

  group('§5.4-6（AC5.5）编辑器槽未保存保护', () {
    testWidgets('关闭未保存编辑器槽 → 确认；确认前 tab 不消失；取消保留', (tester) async {
      final tab = controller.openEditorSlot('SELECT 1');
      controller.markEditorDirty(tab.id, true);
      await _pump(tester, controller);

      expect(find.byKey(WorkbenchStage.dirtyDotKey(tab.id)), findsOneWidget);
      await tester.tap(find.byKey(WorkbenchStage.tabCloseKey(tab.id)));
      await tester.pumpAndSettle();

      // 确认对话框出现；确认前 tab 不消失（AC5.5 widget 用例）。
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(controller.tabs.length, 1);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.tabs.length, 1); // 取消：tab 保留
    });

    testWidgets('确认放弃 → tab 关闭；干净编辑器槽直接关（无确认）', (tester) async {
      final tab = controller.openEditorSlot('SELECT 1');
      controller.markEditorDirty(tab.id, true);
      await _pump(tester, controller);

      await tester.tap(find.byKey(WorkbenchStage.tabCloseKey(tab.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(controller.tabs, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);

      // 干净编辑器槽：关闭不确认。
      final clean = controller.openEditorSlot('SELECT 2');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WorkbenchStage.tabCloseKey(clean.id)));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.tabs, isEmpty);
    });

    test('openEditorSlot 槽策略：目标槽干净复用装载；有未保存修改新开槽（AC5.5）', () {
      final first = controller.openEditorSlot('SELECT a');
      expect(controller.tabs.length, 1);

      // 干净 → 复用同一槽（不新开）。
      controller.openEditorSlot('SELECT b');
      expect(controller.tabs.length, 1);
      expect(controller.tabs.single.id, first.id);
      expect(controller.tabs.single.initialSql, 'SELECT b');

      // 脏 → 新开槽；原槽保留的是最近装载内容 + dirty 标记。
      controller.markEditorDirty(first.id, true);
      final second = controller.openEditorSlot('SELECT c');
      expect(controller.tabs.length, 2);
      expect(second.id, isNot(first.id));
      expect(controller.tabs.first.initialSql, 'SELECT b');
      expect(controller.tabs.first.dirty, isTrue);
      expect(second.initialSql, 'SELECT c');
    });
  });

  group('§5.4-7 空态', () {
    testWidgets('三元素齐（图标 + 标题 + 说明）且无按钮；尾部收起钮恒渲染（A1-1）', (tester) async {
      await _pump(tester, controller);
      expect(find.byIcon(LucideIcons.panelRight), findsOneWidget);
      expect(find.text('Stage is empty'), findsOneWidget);
      expect(
        find.text('Results, charts, or editors opened by AI appear here'),
        findsOneWidget,
      );
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      // 空舞台（零 tab）tab 条右端收起钮恒在；重开钮禁用态也在树。
      expect(find.byKey(WorkbenchStage.collapseKey), findsOneWidget);
      expect(find.byKey(WorkbenchStage.reopenButtonKey), findsOneWidget);
    });
  });

  group('§5.4-8（AC5.3）图表', () {
    testWidgets('列型不适配 → 内联错误 + [在经典中打开]；无 dialog；出口回调透传 SQL', (tester) async {
      final opened = <String>[];
      final allString = _ref(
        'res_str',
        columns: const ['name', 'bio'],
        rows: const [
          {'name': 'a', 'bio': 'x'},
          {'name': 'b', 'bio': 'y'},
        ],
      );
      controller.openChart(allString, null);
      await _pump(tester, controller, onOpenInClassic: opened.add);

      expect(find.byKey(WorkbenchStage.chartMismatchKey), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
      expect(find.text('Data does not fit this chart type'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing); // 不弹窗（AC5.3）

      await tester.tap(find.byKey(WorkbenchStage.openInClassicButtonKey));
      await tester.pumpAndSettle();
      expect(opened, [allString.sql]);
    });

    testWidgets('适配电 → ChartView（chart_result_renderer 语义）', (tester) async {
      controller.openChart(
        _ref('res_ok', columns: const ['id', 'amount'], rows: _numericRows),
        null,
      );
      await _pump(tester, controller);
      expect(find.byType(ChartView), findsOneWidget);
      expect(find.byKey(WorkbenchStage.chartMismatchKey), findsNothing);
    });
  });

  group('§5.3 打开时机与 §6.3 pin 语义（controller；批3 容器口径）', () {
    test('openXxx 自动开舞台 + 激活；同 refId grid/chart 收敛单容器 tab'
        '（B-01 UI35-306a）', () {
      expect(controller.stageVisible, isFalse);
      controller.openGrid(_ref('res_1'), null);
      expect(controller.stageVisible, isTrue);
      expect(controller.activeTabIndex, 0);

      // 批3：同 refId chart → 复用同一 dataViz 容器 tab（切 chart 子态）。
      controller.openChart(_ref('res_1'), null);
      expect(controller.tabs.length, 1);
      expect(controller.activeTabIndex, 0);
      expect(controller.activeTab?.subKind, DataVizSubKind.chart);

      // 同 refId 网格重开 → 复用并切回 grid 子态。
      controller.openGrid(_ref('res_1'), '标题');
      expect(controller.tabs.length, 1);
      expect(controller.activeTab?.subKind, DataVizSubKind.grid);
      expect(controller.tabs.first.title, '标题');

      // 同表结构重开 → 复用。
      controller.openStructure(_structure());
      controller.openStructure(_structure());
      expect(
        controller.tabs.where(
          (t) => t.container == WorkbenchStageContainerKind.schema,
        ),
        hasLength(1),
      );
    });

    test('pinArtifact 不改舞台可见性；建 pinned dataViz tab；幂等', () {
      expect(controller.stageVisible, isFalse);
      final tab = controller.pinArtifact(_ref('res_1'), '产物 A');
      expect(controller.stageVisible, isFalse); // §6.3：钉入不开舞台
      expect(tab.pinned, isTrue);
      expect(tab.container, WorkbenchStageContainerKind.dataViz);
      expect(tab.subKind, DataVizSubKind.grid);
      expect(controller.pinnedTabs.map((t) => t.id), [tab.id]);

      // 同 ref 再钉 → 幂等（不建第二个）。
      controller.pinArtifact(_ref('res_1'), '产物 A');
      expect(controller.pinnedTabs, hasLength(1));

      // 取消钉住 → tab 仍在集合（§6.3 双向）。
      controller.setPinned(0, false);
      expect(controller.pinnedTabs, isEmpty);
      expect(controller.tabs.map((t) => t.id), [tab.id]);
    });

    test('closeTab 激活态补位；关闭 pinned tab → 产物项同步消失（§6.3）', () {
      final a = controller.openGrid(_ref('a'), 'A');
      final b = controller.openGrid(_ref('b'), 'B');
      controller.pinArtifact(_ref('a'), 'A');
      expect(controller.pinnedTabs.map((t) => t.id), [a.id]);

      controller.closeTab(1); // 关激活的 b（未钉）→ 激活补位；钉住项不受影响
      expect(controller.activeTabIndex, 0);
      expect(controller.tabs.map((t) => t.id), [a.id]);
      expect(b.id, isNot(a.id));
      expect(controller.pinnedTabs.map((t) => t.id), [a.id]);

      // 关闭 pinned tab → tab 销毁 → 产物项同步消失（用户显式关闭即显式丢）。
      controller.closeTab(0);
      expect(controller.tabs, isEmpty);
      expect(controller.pinnedTabs, isEmpty);
    });

    test('setStageVisible 开合语义（T27 shell 消费）', () {
      controller.setStageVisible(true);
      expect(controller.stageVisible, isTrue);
      controller.setStageVisible(true); // 幂等（同值不通知）
      controller.setStageVisible(false);
      expect(controller.stageVisible, isFalse);
    });

    test('isChartable：数值列 → true；纯字符串列 → false；空数据 → true（沿渲染器空态）', () {
      expect(
        WorkbenchStageController.isChartable(
          _ref('r', columns: const ['id', 'amount'], rows: _numericRows),
        ),
        isTrue,
      );
      expect(
        WorkbenchStageController.isChartable(
          _ref(
            'r',
            columns: const ['a'],
            rows: const [
              {'a': 'x'},
            ],
          ),
        ),
        isFalse,
      );
      expect(WorkbenchStageController.isChartable(_ref('r')), isTrue);
    });
  });

  group('§5.3 网格 / 结构卡 / 编辑器槽内容', () {
    testWidgets('网格：有数据走注册表渲染器；0 行沿既有「No data」空态', (tester) async {
      controller.openGrid(_ref('res_1', rows: _numericRows), 'G');
      await _pump(tester, controller);
      expect(find.byType(VirtualizedDataTable), findsOneWidget);

      controller.openGrid(_ref('res_empty'), 'E');
      controller.activateTab(1);
      await tester.pumpAndSettle();
      expect(find.text('No Data'), findsOneWidget);
    });

    testWidgets('Schema 容器：columns/indexes/ddl 三子段分段切换 + 徽标'
        '（批3：分段标签即子段标题，外键归并 indexes 子段）', (tester) async {
      controller.openStructure(_structure());
      await _pump(tester, controller);
      // 默认 columns 子段：分段三标签 + 列行 + PK/NN 徽标。
      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('Indexes'), findsOneWidget);
      expect(find.text('DDL'), findsOneWidget);
      expect(find.text('PK'), findsOneWidget);
      expect(find.text('NN'), findsOneWidget);
      expect(
        find.text('idx_status'),
        findsNothing,
        reason: '默认 columns 子段不渲染索引行',
      );

      // 切 indexes 子段：索引行 + 外键行（键族归并呈现）。
      await tester.tap(find.text('Indexes'));
      await tester.pumpAndSettle();
      expect(find.text('idx_status'), findsOneWidget);
      expect(find.text('customer_id → customers.id'), findsOneWidget);

      // 切 ddl 子段：CREATE TABLE 块。
      await tester.tap(find.text('DDL'));
      await tester.pumpAndSettle();
      expect(
        find.text('CREATE TABLE orders (id bigint NOT NULL PRIMARY KEY);'),
        findsOneWidget,
      );
      // 表名进 title（产物芯片/重开菜单消费），不上 tab 条（容器标签）。
      expect(find.text('orders'), findsNothing);
      expect(find.text('Schema'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('编辑器槽：载入 SQL 可见（ReSqlEditor），无自动执行入口', (tester) async {
      controller.openEditorSlot('SELECT 42 AS answer');
      await _pump(tester, controller);
      expect(find.byType(ReSqlEditor), findsOneWidget);
      // 载入不执行（AC5.2）：编辑器槽内无执行按钮（沿 queryExecute 文案检索）。
      expect(find.text('Execute'), findsNothing);
      // 用户修改 → dirty 点出现（AC5.5 判据链路）。
      final tab = controller.tabs.single;
      controller.markEditorDirty(tab.id, true);
      await tester.pumpAndSettle();
      expect(find.byKey(WorkbenchStage.dirtyDotKey(tab.id)), findsOneWidget);
    });

    testWidgets('tab 右键菜单：钉入 / 取消钉住 / 关闭（沿经典 tab 先例）', (tester) async {
      final tab = controller.openGrid(_ref('res_1', rows: _numericRows), 'G');
      await _pump(tester, controller);

      await tester.tap(
        find.byKey(WorkbenchStage.tabItemKey(tab.id)),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Pin to Artifacts'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Pin to Artifacts'));
      await tester.pumpAndSettle();
      expect(controller.pinnedTabs.map((t) => t.id), [tab.id]);

      // 取消钉住入口（同菜单）。
      await tester.tap(
        find.byKey(WorkbenchStage.tabItemKey(tab.id)),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();
      expect(controller.pinnedTabs, isEmpty);
      expect(controller.tabs.map((t) => t.id), [tab.id]);
    });
  });

  // 批3 B-01：sessionList/history/savedQueries 三组用例随舞台枚举退役删除
  // （三抽屉改由 rail 196 内容页唯一承载——组件面覆盖见
  // workbench_session_rail_test.dart；载入编辑器槽动线随 rail 既有用例）。

  group('diagnostics 容器 explainPlan 子态（execution 投影，批3 容器口径）', () {
    /// 混合批投影样例：done（写，行数缺失降级）/ failed（错误全文）/
    /// skipped（无指标）/ done（只读有行数）——覆盖三态与降级两形态。
    StageExecutionData batch({String tabKey = 'manual', String? title}) =>
        StageExecutionData(
          tabKey: tabKey,
          title: title ?? 'Execution 10:00:00',
          rows: const [
            StageExecutionRow(
              sql: 'INSERT INTO t VALUES (1)',
              status: StageExecutionStatus.done,
              durationMs: 12,
            ),
            StageExecutionRow(
              sql: 'UPDATE t SET a = 1 WHERE id = 2',
              status: StageExecutionStatus.failed,
              durationMs: 20,
              error: 'boom: duplicate key entry',
            ),
            StageExecutionRow(
              sql: 'DELETE FROM t WHERE id = 3',
              status: StageExecutionStatus.skipped,
            ),
            StageExecutionRow(
              sql: 'SELECT 1',
              status: StageExecutionStatus.done,
              affectedRows: 3,
              durationMs: 5,
            ),
          ],
        );

    test('openExecution：不可见 → 自动可见 + 激活；同 tabKey 复用刷新'
        '（tab 恒 1，载荷替换）；异 tabKey 新建（R4）', () {
      expect(controller.stageVisible, isFalse);
      final first = controller.openExecution(batch());
      expect(controller.stageVisible, isTrue);
      expect(controller.activeTabIndex, 0);
      expect(first.container, WorkbenchStageContainerKind.diagnostics);
      expect(first.subKind, DiagnosticsSubKind.explainPlan);

      // R4 复用刷新：同 tabKey → 同 tab，标题与数据载荷以新值为准。
      final second = controller.openExecution(
        const StageExecutionData(
          tabKey: 'manual',
          title: 'Execution 10:01:00',
          rows: [
            StageExecutionRow(
              sql: 'SELECT 9',
              status: StageExecutionStatus.done,
              durationMs: 3,
            ),
          ],
        ),
      );
      expect(second.id, first.id, reason: '同 tabKey 复用同一 tab');
      expect(controller.tabs, hasLength(1));
      expect(controller.tabs.single.title, 'Execution 10:01:00');
      expect(
        controller.tabs.single.execution?.rows.single.sql,
        'SELECT 9',
        reason:
            '复用 = 数据载荷替换刷新（既存复用语义只换 title/chartKind，'
            'execution 自写复用分支替换载荷）',
      );

      // 异 tabKey（计划链 planId 语义）→ 新建 tab。
      controller.openExecution(batch(tabKey: 'plan_1'));
      expect(controller.tabs, hasLength(2));
      expect(controller.activeTab?.execution?.tabKey, 'plan_1');
    });

    testWidgets('逐语句行渲染：摘要条三占位符 / 失败行置顶 / 状态图标 / 指标降级 / 零动作按钮', (tester) async {
      controller.openExecution(batch());
      await _pump(tester, controller);

      // 摘要条（en 模板三占位符展开；总耗时 = 12+20+5=37，skipped 无耗时）。
      expect(find.text('4 statements · 1 failed · 37 ms'), findsOneWidget);

      // 失败行置顶（展示序第 0 行 = 失败 UPDATE），组内保持原执行序。
      final row0 = find.byKey(const ValueKey('workbench_execution_row_0'));
      final row1 = find.byKey(const ValueKey('workbench_execution_row_1'));
      expect(row0, findsOneWidget);
      expect(
        find.descendant(
          of: row0,
          matching: find.text('UPDATE t SET a = 1 WHERE id = 2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row0,
          matching: find.byIcon(LucideIcons.triangleAlert),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row1,
          matching: find.text('INSERT INTO t VALUES (1)'),
        ),
        findsOneWidget,
        reason: '失败置顶后余下行保持原执行序',
      );
      expect(
        tester.getCenter(row0).dy,
        lessThan(tester.getCenter(row1).dy),
        reason: '失败行在纵向上置顶',
      );

      // 状态图标（done ×2 / skipped ×1；skipped = skipForward 弱化图标）。
      expect(find.byIcon(LucideIcons.circleCheckBig), findsNWidgets(2));
      expect(find.byIcon(LucideIcons.skipForward), findsOneWidget);

      // 指标呈现：只读行 3 rows + 5 ms；写语句行数缺失降级不显；skipped 无耗时。
      expect(find.text('3 rows'), findsOneWidget);
      expect(find.text('5 ms'), findsOneWidget);
      expect(
        find.text('0 rows'),
        findsNothing,
        reason: '行数缺失降级不显（facade 对写语句不回传行，不显示误导的 0）',
      );

      // tooltip 承载 SQL 全文（§0.4 截断兜底）。
      expect(find.byTooltip('DELETE FROM t WHERE id = 3'), findsOneWidget);

      // 纯只读投影：零动作按钮（无重跑/编辑/导出，v1 §4 守卫）。
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('失败行「详情」展开错误全文（可折块）；复用刷新内容以新值为准', (tester) async {
      controller.openExecution(batch());
      await _pump(tester, controller);

      // 初始收起：错误全文不在树。
      expect(find.text('boom: duplicate key entry'), findsNothing);

      // 展开（失败行置顶后展示序 0 的「详情」开关）。
      await tester.tap(
        find.byKey(const ValueKey('workbench_execution_detail_0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('boom: duplicate key entry'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workbench_execution_error_0')),
        findsOneWidget,
      );

      // 复用刷新：同 tabKey 新批次 → tab 恒 1 且内容替换为最新批次。
      controller.openExecution(
        const StageExecutionData(
          tabKey: 'manual',
          title: 'Execution 10:02:00',
          rows: [
            StageExecutionRow(
              sql: 'UPDATE t SET a = 9',
              status: StageExecutionStatus.done,
              durationMs: 7,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.tabs, hasLength(1));
      expect(find.text('UPDATE t SET a = 9'), findsOneWidget);
      expect(find.text('INSERT INTO t VALUES (1)'), findsNothing);
      expect(find.text('1 statements · 0 failed · 7 ms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('diagnostics 容器 liveMonitor 子态（observe 语义，批3 容器口径）', () {
    test('openObserve：不可见 → 自动可见 + 激活；重复打开复用（容器 tab 恒 1）', () {
      expect(controller.stageVisible, isFalse);
      final first = controller.openObserve();
      expect(
        controller.stageVisible,
        isTrue,
        reason: '§8-2：舞台不可见时打开 → 自动可见（沿 _openTab 既有语义）',
      );
      expect(controller.activeTabIndex, 0);

      // 重复打开（命令面板重复触发）→ 复用激活，不重复建。
      final again = controller.openObserve();
      expect(again.id, first.id, reason: 'match = kind 即命中：复用同一 tab');
      expect(controller.tabs, hasLength(1));

      // 与其它 kind 混合时仍单例，且重开即激活（observe 建于首位）。
      controller.openGrid(_ref('res_1'), null);
      expect(controller.tabs, hasLength(2));
      controller.openObserve();
      expect(
        controller.tabs.where(
          (t) => t.container == WorkbenchStageContainerKind.diagnostics,
        ),
        hasLength(1),
        reason: 'diagnostics 容器 tab 恒 1（observe 复用）',
      );
      expect(
        controller.activeTab?.subKind,
        DiagnosticsSubKind.liveMonitor,
      );
      expect(controller.activeTabIndex, 0, reason: '激活切回复用的 observe tab');
    });

    testWidgets('slot 渲染 WorkbenchObserveContent；未锁 = 无连接空态'
        '（byType 同源 + 空态文案）', (tester) async {
      controller.openObserve();
      final app = AppProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: app,
          child: _wrap(WorkbenchStage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorkbenchObserveContent), findsOneWidget);
      // 未锁连接（裸 AppProvider 无会话锁定/活动 tab/侧栏选择）→ 空态
      // 标题 + 零按钮（v2 §8-8 未锁态）。
      expect(find.text('No connection locked'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('schema 容器 Mongo 分支（openMongoStructure / 去重 / slot，批3 容器口径）', () {
    StageMongoStructureData mongo(
      String collection, {
      String connectionId = 'conn_mongo',
      String databaseName = 'mydb',
    }) => StageMongoStructureData(
      connectionId: connectionId,
      databaseName: databaseName,
      collectionName: collection,
    );

    test('openMongoStructure 建 schema 容器 tab：载荷完整 + title 默认 ='
        ' collectionName + 自动可见激活', () {
      expect(controller.stageVisible, isFalse);
      final tab = controller.openMongoStructure(mongo('users'));
      expect(controller.stageVisible, isTrue);
      expect(controller.activeTabIndex, 0);
      expect(tab.container, WorkbenchStageContainerKind.schema);
      expect(tab.subKind, SchemaSubKind.columns);
      expect(tab.structure, isNull, reason: 'mongo tab 的 structure 恒 null');
      expect(tab.mongoStructure?.connectionId, 'conn_mongo');
      expect(tab.mongoStructure?.databaseName, 'mydb');
      expect(tab.mongoStructure?.collectionName, 'users');
      expect(tab.title, 'users', reason: 'title 默认 = collectionName');
    });

    test('同集合 + 同连接重开 → 复用刷新（tab 恒 1，载荷替换）；异连接或'
        '异集合各开各的（tab 数断言）', () {
      final first = controller.openMongoStructure(mongo('users'));
      final again = controller.openMongoStructure(
        mongo('users', databaseName: 'other_db'),
      );
      expect(again.id, first.id, reason: '同连接同集合 → 复用同一 tab');
      expect(controller.tabs, hasLength(1));
      // 复用刷新 = 载荷替换（databaseName 以新值为准）。
      expect(controller.tabs.single.mongoStructure?.databaseName, 'other_db');

      // 同集合不同连接 → 各开各的。
      final otherConn = controller.openMongoStructure(
        mongo('users', connectionId: 'conn_other'),
      );
      expect(otherConn.id, isNot(first.id));
      expect(controller.tabs, hasLength(2));

      // 同连接不同集合 → 各开各的。
      final otherCol = controller.openMongoStructure(mongo('orders'));
      expect(otherCol.id, isNot(first.id));
      expect(otherCol.id, isNot(otherConn.id));
      expect(controller.tabs, hasLength(3));

      // 回开首个键 → 复用第一个 tab 并激活（互不干扰，tab 数不变）。
      final back = controller.openMongoStructure(mongo('users'));
      expect(back.id, first.id);
      expect(controller.tabs, hasLength(3));
      expect(controller.activeTabIndex, 0);
    });

    test('SQL 表与 Mongo 集合不串味：同表/集合名双键独立，各自复用不串', () {
      final sqlTab = controller.openStructure(_structure()); // tableName orders
      final mongoTab = controller.openMongoStructure(mongo('orders'));
      expect(controller.tabs, hasLength(2));
      expect(sqlTab.structure?.tableName, 'orders');
      expect(sqlTab.mongoStructure, isNull);
      expect(mongoTab.structure, isNull);
      expect(mongoTab.mongoStructure?.collectionName, 'orders');

      // SQL 重开只命中原 SQL tab（mongo tab 的 structure == null 天然互斥）。
      controller.openStructure(_structure());
      expect(controller.tabs, hasLength(2));
      // Mongo 重开只命中原 mongo tab（SQL tab 的 mongoStructure == null）。
      controller.openMongoStructure(mongo('orders'));
      expect(controller.tabs, hasLength(2));
    });

    testWidgets('slot byType：mongo tab 渲染 WorkbenchMongoSchemaView'
        '（三参透传正确，§8-5 同源）；SQL 分支仍 _StageStructureContent 原样', (tester) async {
      final fake = _FakeMongoStageAppProvider();
      controller.openMongoStructure(
        mongo('users', connectionId: 'conn_mongo', databaseName: 'mydb'),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: fake,
          child: _wrap(WorkbenchStage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorkbenchMongoSchemaView), findsOneWidget);
      // 载荷三参透传到内容件（首帧 load 调用参数记录）。
      expect(fake.lastConnectionId, 'conn_mongo');
      expect(fake.lastDatabase, 'mydb');
      expect(fake.lastCollection, 'users');
      // 内容渲染：头行集合名（视图内）+ schema 字段树。
      expect(
        find.descendant(
          of: find.byType(WorkbenchMongoSchemaView),
          matching: find.text('users'),
        ),
        findsOneWidget,
      );
      expect(find.byType(SchemaNestedExpander), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      // SQL 表分支零变化：另开 SQL structure tab 激活 → describe 四件原样。
      controller.openStructure(_structure());
      await tester.pumpAndSettle();
      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('Indexes'), findsOneWidget);
      expect(find.text('DDL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group(
    'sqlStudio 容器 diff 子态（optimization 投影，批3 容器口径）',
    () {
      StageOptimizationData opt(
        String sql, {
        String summary = 'sample summary',
      }) => StageOptimizationData(
        sql: sql,
        report: _optimizationReport(summary: summary),
      );

      test('openOptimization 建 tab：载荷完整 + title 缺省 null（类型标签回退）'
          ' + 自动可见激活', () {
        expect(controller.stageVisible, isFalse);
        final tab = controller.openOptimization(opt('SELECT * FROM big_table'));
        expect(controller.stageVisible, isTrue);
        expect(controller.activeTabIndex, 0);
        expect(tab.container, WorkbenchStageContainerKind.sqlStudio);
        expect(tab.subKind, SqlStudioSubKind.diff);
        expect(tab.optimization?.sql, 'SELECT * FROM big_table');
        expect(tab.optimization?.report, isNotNull);
        expect(tab.optimization?.report.executionPlan.steps, hasLength(1));
        expect(
          tab.title,
          isNull,
          reason: 'title 缺省回退类型标签 agentStageTabOptimization（注册表单源）',
        );
      });

      test('同 SQL 复用刷新（tab 恒 1，载荷替换）；异 SQL / 仅空白差异各开各的'
          '（R6 精确串去重）', () {
        final first = controller.openOptimization(
          opt('SELECT 1', summary: 'first'),
        );
        final again = controller.openOptimization(
          opt('SELECT 1', summary: 'second'),
        );
        expect(again.id, first.id, reason: '同 SQL 精确串 → 复用同一 tab');
        expect(controller.tabs, hasLength(1));
        expect(
          controller.tabs.single.optimization?.report.summary,
          'second',
          reason: '复用刷新 = 载荷替换（report 以新值为准）',
        );

        // 异 SQL → 各开各的。
        final other = controller.openOptimization(
          opt('SELECT 2', summary: 'other'),
        );
        expect(other.id, isNot(first.id));
        expect(controller.tabs, hasLength(2));
        expect(controller.activeTabIndex, 1);

        // 精确串语义：仅空白差异也是不同键（不去空白归一）。
        final spaced = controller.openOptimization(
          opt('SELECT 1 ', summary: 'spaced'),
        );
        expect(spaced.id, isNot(first.id));
        expect(controller.tabs, hasLength(3));
      });

      testWidgets('slot：SQL 头块（mono SelectableText）存在 + '
          'QueryPlanVisualizer 渲染 + tab 标签走注册表', (tester) async {
        controller.openOptimization(
          opt('SELECT * FROM big_table WHERE val = 1'),
        );
        await _pump(tester, controller);

        expect(find.byType(QueryPlanVisualizer), findsOneWidget);
        // SQL 上下文头：SelectableText 呈现原 SQL 精确串。
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SelectableText &&
                w.data == 'SELECT * FROM big_table WHERE val = 1',
          ),
          findsOneWidget,
        );
        // 批3：tab 条标签 = 容器标签（SQL Studio）；分段 Editor/Diff 可见。
        expect(find.text('SQL Studio'), findsOneWidget);
        expect(find.text('Diff'), findsOneWidget);
        expect(find.text('Editor'), findsOneWidget);
        // 报告含带 DDL 的索引推荐 → 「应用此索引」按钮在树（fill 不 execute）。
        expect(
          find.descendant(
            of: find.byType(QueryPlanVisualizer),
            matching: find.text('Apply This Index'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('onApplyDdl → openEditorSlot 收到 DDL 且零执行调用'
          '（填编辑器槽不执行，一票否决项）', (tester) async {
        controller.openOptimization(
          opt('SELECT * FROM big_table WHERE val = 1'),
        );
        await _pump(tester, controller);

        await tester.ensureVisible(find.text('Apply This Index'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply This Index'));
        await tester.pumpAndSettle();

        // 批3 容器收敛：DDL 落入同一 sqlStudio 容器 tab（edit 子态装载，
        // 载入不自动执行 AC5.2）——optimization 载荷与编辑槽同容器共存。
        final studioTab = controller.tabs.single;
        expect(
          studioTab.container,
          WorkbenchStageContainerKind.sqlStudio,
        );
        expect(studioTab.subKind, SqlStudioSubKind.edit);
        expect(
          studioTab.initialSql,
          'CREATE INDEX idx_big_table_val ON big_table (val)',
        );
        expect(controller.activeTabIndex, 0);
        // 零执行调用：编辑器槽内容组件无任何执行入口，widget 测试环境亦无
        // dbService 接入——「应用此索引」的唯一效果就是编辑器槽文本装载。
        expect(tester.takeException(), isNull);
      });
    },
  );

  group('走查修复批件②：最近关闭栈（controller，AI-WF-001~008）', () {
    /// 批3 B-01：4 容器全覆盖逐一 open（openSessions 等三 API 随枚举退役
    /// 删除；grid/chart 同 refId 收敛单 dataViz tab；observe 复用 execution
    /// 的 diagnostics tab；optimization 落地 editor 的 sqlStudio tab——
    /// 覆盖矩阵 = 每容器 ≥1 tab + 收敛/复用两语义）。
    void openAllContainers() {
      controller.openGrid(_ref('k_grid', rows: _numericRows), 'G'); // dataViz
      controller.openStructure(_structure()); // schema
      controller.openEditorSlot('SELECT 1'); // sqlStudio
      controller.openChart(_ref('k_chart'), null); // dataViz（异 refId 各开）
      controller.openExecution(
        const StageExecutionData(
          tabKey: 'manual',
          title: 'E',
          rows: [
            StageExecutionRow(sql: 'INSERT 1', status: StageExecutionStatus.done),
          ],
        ),
      ); // diagnostics
      controller.openObserve(); // 复用 diagnostics tab（liveMonitor）
      controller.openOptimization(
        StageOptimizationData(
          sql: 'SELECT * FROM big_table WHERE val = 1',
          report: _optimizationReport(),
        ),
      ); // 落地 sqlStudio tab（diff）
    }

    test('closeTab 压栈：被移除对象在栈顶；四容器全覆盖逐 tab 入栈无例外（A2-1 批3 口径）', () {
      openAllContainers();
      // 5 tab：dataViz ×2（grid + chart 异 refId）+ schema + sqlStudio（editor
      // 与 optimization 同容器）+ diagnostics（execution 与 observe 同容器）。
      expect(controller.tabs, hasLength(5));
      expect(
        controller.tabs.map((t) => t.container).toSet(),
        WorkbenchStageContainerKind.values.toSet(),
        reason: '4 容器全覆盖',
      );
      // 从末尾逐个关闭（下标稳定）。
      for (var i = 4; i >= 0; i--) {
        final victim = controller.tabs[i];
        controller.closeTab(i);
        expect(
          controller.recentlyClosedTabs.first.id,
          victim.id,
          reason: '被移除对象在栈顶（${victim.container.name}/${victim.subKind.runtimeType}）',
        );
      }
      expect(controller.recentlyClosedTabs, hasLength(5));
    });

    test('封顶 10：连关 11 tab → 栈长 10，最先关闭者被逐出栈底（A2-2）', () {
      final ids = <String>[
        for (var i = 0; i < 11; i++)
          controller.openGrid(_ref('cap_$i', rows: _numericRows), 'T$i').id,
      ];
      // 关闭序 = T10 最先 → T0 最后（降序下标）。
      for (var i = 10; i >= 0; i--) {
        controller.closeTab(i);
      }
      expect(controller.recentlyClosedTabs, hasLength(10));
      // 栈顶在前 = 最近关闭（T0）……栈底 = 最先关闭；T10 被逐出。
      expect(
        controller.recentlyClosedTabs.map((t) => t.id).toList(),
        ids.take(10).toList(),
      );
      expect(
        controller.recentlyClosedTabs.map((t) => t.id),
        isNot(contains(ids[10])),
        reason: '最先关闭者（T10）被逐出栈底',
      );
    });

    test('LIFO：依次关 A/B/C → 栈序 [C,B,A]；重开 C → 栈 [B,A]、_tabs 末尾为 C 且激活、舞台可见（A2-3）', () {
      final a = controller.openGrid(_ref('a'), 'A');
      final b = controller.openGrid(_ref('b'), 'B');
      final c = controller.openGrid(_ref('c'), 'C');
      controller.closeTab(0); // A
      controller.closeTab(0); // B（A 移除后 B 落 0）
      controller.closeTab(0); // C
      expect(controller.recentlyClosedTabs.map((t) => t.id), [c.id, b.id, a.id]);
      expect(controller.tabs, isEmpty);
      expect(controller.activeTabIndex, -1);

      final reopened = controller.reopenClosedTab(c.id);
      expect(reopened?.id, c.id);
      expect(controller.recentlyClosedTabs.map((t) => t.id), [b.id, a.id]);
      expect(controller.tabs.map((t) => t.id), [c.id]);
      expect(controller.activeTabIndex, 0, reason: '重开 = 追加末尾 + 激活');
      expect(controller.stageVisible, isTrue);
    });

    test('不去重并存：重开项与同 refId 新 tab 并存、对象身份不合并（A2-4）', () {
      // 并存路径 = 「先关 → 同 refId 新开（openXxx 语义原样）→ 重开」——
      // reopenClosedTab 自身不走去重路径（S6），同 refId 两 tab 得以并存。
      final original = controller.openGrid(
        _ref('dup_x', rows: _numericRows),
        'X',
      );
      controller.closeTab(0); // 栈 [original]
      final fresh = controller.openGrid(_ref('dup_x', rows: _numericRows), 'X2');
      expect(fresh.id, isNot(original.id), reason: '原 tab 已关，openGrid 新建');

      expect(controller.reopenClosedTab(original.id), isNotNull);
      expect(controller.tabs, hasLength(2));
      expect(
        controller.tabs.where((t) => t.resultRef?.refId == 'dup_x'),
        hasLength(2),
        reason: '同 refId 两 tab 并存（对象身份不合并）',
      );
      // 后续 openGrid 新 ref（新 refId，agent 新步语义）→ 各自独立 tab。
      final another = controller.openGrid(_ref('dup_y', rows: _numericRows), 'Y');
      expect(another.id, isNot(original.id));
      expect(another.id, isNot(fresh.id));
      expect(controller.tabs, hasLength(3));
    });

    test('重开按 id：非栈顶项出栈重开、其余保留；未知/空 id → null 且栈/列表零变化（A2-5）', () {
      final a = controller.openGrid(_ref('a'), 'A');
      final b = controller.openGrid(_ref('b'), 'B');
      final c = controller.openGrid(_ref('c'), 'C');
      controller.closeTab(2); // C（栈 [C]）
      controller.closeTab(1); // B（栈 [B, C]；a 仍开着）
      // 菜单点非栈顶的 C。
      expect(controller.reopenClosedTab(c.id), isNotNull);
      expect(controller.recentlyClosedTabs.map((t) => t.id), [b.id],
          reason: 'C 出栈，B 保留');
      expect(controller.tabs.map((t) => t.id), [a.id, c.id],
          reason: '重开 = 追加末尾');
      // 快照防御：未知 id / 空串 → null，栈与列表零变化。
      expect(controller.reopenClosedTab('stage_tab_999'), isNull);
      expect(controller.reopenClosedTab(''), isNull);
      expect(controller.recentlyClosedTabs.map((t) => t.id), [b.id]);
      expect(controller.tabs.map((t) => t.id), [a.id, c.id]);
    });

    test('pinned 关闭重开（controller 面）：另一 pinned 项不受影响；重开恢复 pinned 投影（A2-6）', () {
      final p1 = controller.pinArtifact(_ref('p1'), 'P1');
      final p2 = controller.pinArtifact(_ref('p2'), 'P2');
      expect(controller.pinnedTabs.map((t) => t.id), [p1.id, p2.id]);

      controller.closeTab(1); // 关闭 pinned p2
      expect(
        controller.pinnedTabs.map((t) => t.id),
        [p1.id],
        reason: '关闭 ≠ 取消钉住其它项',
      );
      final reopened = controller.reopenClosedTab(p2.id);
      expect(reopened?.pinned, isTrue, reason: '对象原样重开：pinned 标记保留');
      expect(
        controller.pinnedTabs.map((t) => t.id),
        [p1.id, p2.id],
        reason: '产物条条目自动重现（pinned 子集投影）',
      );
    });

    test('编辑器恢复：脏编辑器确认关闭 → 重开 → initialSql 原文恢复、dirty == false（A2-7）', () {
      final tab = controller.openEditorSlot('SELECT restore_me');
      controller.markEditorDirty(tab.id, true);
      // 关闭确认是 UI 语义——此处即确认「放弃」后的 controller 调用面。
      controller.closeTab(0);
      expect(
        controller.recentlyClosedTabs.single.dirty,
        isFalse,
        reason: '压栈前丢弃脏标记：复活对象不得带脏点',
      );
      final reopened = controller.reopenClosedTab(tab.id);
      expect(reopened?.initialSql, 'SELECT restore_me', reason: 'SQL 原文恢复');
      expect(reopened?.dirty, isFalse);
    });

    test('closeTab 越界静默忽略且不入栈（既有语义 + 栈防御）', () {
      controller.openGrid(_ref('a'), 'A');
      controller.closeTab(-1);
      controller.closeTab(5);
      expect(controller.recentlyClosedTabs, isEmpty);
      expect(controller.tabs, hasLength(1));
    });
  });

  group('走查修复批件①②：tab 条尾部控件簇（重开 / 收起，AI-WF-101~107）', () {
    testWidgets('空栈重开钮禁用态渲染：节点在树、降透明度、tooltip 照常；非空恢复正常态（A2-8）', (tester) async {
      await _pump(tester, controller);
      Opacity reopenOpacity() => tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(WorkbenchStage.reopenButtonKey),
          matching: find.byType(Opacity),
        ).first,
      );
      expect(find.byKey(WorkbenchStage.reopenButtonKey), findsOneWidget);
      expect(reopenOpacity().opacity, lessThan(1.0), reason: '降透明度不隐藏');
      expect(find.byTooltip('Reopen closed tab'), findsOneWidget,
          reason: '禁用态 tooltip 照常');
      // 收起钮恒可用态。
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.byKey(WorkbenchStage.collapseKey),
                matching: find.byType(Opacity),
              ).first,
            )
            .opacity,
        1.0,
      );

      // 非空栈：恢复正常态。
      controller.openGrid(_ref('r1'), 'R1');
      controller.closeTab(0);
      await tester.pumpAndSettle();
      expect(reopenOpacity().opacity, 1.0);
    });

    testWidgets('尾部两钮几何：重开 ≥28 / 收起 24 宽 × 条内区全高（批3 B-02，架构追认 2026-10-26：与条内 _StageBarAction 同形态）（A1-7）；收起钮 tap → stageVisible false（A1-2 组件面）', (tester) async {
      controller.openGrid(_ref('r1'), 'R1');
      await _pump(tester, controller);
      expect(controller.stageVisible, isTrue);

      final reopenRect = tester.getRect(
        find.byKey(WorkbenchStage.reopenButtonKey),
      );
      final collapseRect = tester.getRect(
        find.byKey(WorkbenchStage.collapseKey),
      );
      // 条内区高 = tabBarHeight 32 − 底部 1px divider = 31（Container 子区
      // 被 border 内缩，tab 项同款钳制）——两钮贴满条内区全高。
      expect(reopenRect.width, greaterThanOrEqualTo(28));
      expect(reopenRect.height, greaterThanOrEqualTo(31));
      // 批3 B-02（架构追认 2026-10-26）：收起钮迁容器 tab 条右端，
      // 24 宽 × 条全高条形动作钮（原 28 宽收窄；「24×24」判定为冻结尺寸
      // 简写不精确，追认条形读法——与条内 _StageBarAction 先例同形态）。
      expect(collapseRect.width, closeTo(24, 0.5));
      expect(collapseRect.height, greaterThanOrEqualTo(31));
      // 收起钮贴最右缘、重开在左（S2 布局）。
      expect(collapseRect.right, greaterThan(reopenRect.right));

      await tester.tap(find.byKey(WorkbenchStage.collapseKey));
      await tester.pumpAndSettle();
      expect(controller.stageVisible, isFalse);
    });

    testWidgets('重开菜单：项数 / LIFO 序 / 图标与标题回退 / 项 tap 重开出栈 / 重开后再关回栈顶（A2-9）', (tester) async {
      final tabA = controller.openGrid(_ref('mA', rows: _numericRows), 'MA');
      final tabStruct = controller.openStructure(_structure()); // title orders
      final tabObs = controller.openObserve(); // title null → 回退 Observe
      controller.closeTab(2); // obs 最先关（栈底）
      controller.closeTab(1); // struct
      controller.closeTab(0); // a 最后关（栈顶）
      await _pump(tester, controller);

      await tester.tap(find.byKey(WorkbenchStage.reopenButtonKey));
      await tester.pumpAndSettle();

      // 项数 = min(栈长,10) = 3。
      final itemA = find.byKey(WorkbenchStage.reopenItemKey(tabA.id));
      final itemStruct = find.byKey(WorkbenchStage.reopenItemKey(tabStruct.id));
      final itemObs = find.byKey(WorkbenchStage.reopenItemKey(tabObs.id));
      expect(itemA, findsOneWidget);
      expect(itemStruct, findsOneWidget);
      expect(itemObs, findsOneWidget);

      // LIFO 序：最近关闭（a）在最上。
      expect(
        tester.getCenter(itemA).dy,
        lessThan(tester.getCenter(itemStruct).dy),
      );
      expect(
        tester.getCenter(itemStruct).dy,
        lessThan(tester.getCenter(itemObs).dy),
      );

      // 批3：图标 = 注册表 container.icon；标题 = title ?? container.label
      //（observe tab → Diagnostics 容器 + squareTerminal 图标）。
      expect(
        find.descendant(
          of: itemObs,
          matching: find.byIcon(LucideIcons.squareTerminal),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: itemObs, matching: find.text('Diagnostics')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: itemStruct, matching: find.byIcon(LucideIcons.listTree)),
        findsOneWidget,
      );
      expect(find.descendant(of: itemStruct, matching: find.text('orders')),
          findsOneWidget);
      expect(
        find.descendant(of: itemA, matching: find.byIcon(LucideIcons.table)),
        findsOneWidget,
      );
      expect(find.descendant(of: itemA, matching: find.text('MA')),
          findsOneWidget);

      // 项 tap（栈顶的 a = 最近关闭）→ 重开并出栈。
      await tester.tap(itemA);
      await tester.pumpAndSettle();
      expect(controller.tabs.last.id, tabA.id, reason: '重开 = 追加末尾');
      expect(controller.activeTabIndex, controller.tabs.length - 1);
      expect(controller.stageVisible, isTrue);
      expect(
        controller.recentlyClosedTabs.map((t) => t.id).toList(),
        [tabStruct.id, tabObs.id],
        reason: 'a 出栈，其余保留',
      );

      // 重开后再关 → 回栈顶（一次机会语义）。
      controller.closeTab(controller.tabs.length - 1);
      expect(
        controller.recentlyClosedTabs.first.id,
        tabA.id,
        reason: '再关回栈顶',
      );
    });

    testWidgets('菜单 Esc / 遮罩关闭零副作用（栈与 _tabs 不变，A2-9）', (tester) async {
      final tabX = controller.openGrid(_ref('mx'), 'X');
      final tabY = controller.openGrid(_ref('my'), 'Y');
      controller.closeTab(1); // Y
      controller.closeTab(0); // X（栈 [X, Y]）
      await _pump(tester, controller);

      // Esc 关闭。
      await tester.tap(find.byKey(WorkbenchStage.reopenButtonKey));
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        controller.recentlyClosedTabs.map((t) => t.id).toList(),
        [tabX.id, tabY.id],
      );
      expect(controller.tabs, isEmpty);

      // 遮罩关闭（点菜单外）。
      await tester.tap(find.byKey(WorkbenchStage.reopenButtonKey));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(
        controller.recentlyClosedTabs.map((t) => t.id).toList(),
        [tabX.id, tabY.id],
      );
      expect(controller.tabs, isEmpty);
    });

    testWidgets('键盘：重开钮 Enter / ↓ 开菜单、菜单内 Enter 原生选中、空栈 Enter 空转（A2-10）', (tester) async {
      final tabK = controller.openGrid(_ref('mk'), 'K1');
      controller.closeTab(0);
      final registry = WorkbenchFocusZoneRegistry();
      await _pump(tester, controller, zoneRegistry: registry);

      // 空舞台 F6 入口 → 重开钮（死档①）。
      expect(registry.focus(WorkbenchFocusZone.stageTabBar), isTrue);
      await tester.pump();
      expect(_focusWithinKeySubtree(WorkbenchStage.reopenButtonKey), isTrue);

      // Enter 开菜单。
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(WorkbenchStage.reopenItemKey(tabK.id)),
        findsOneWidget,
      );

      // ↓ 关不掉也不炸（菜单内原生焦点面）；Esc 关菜单后 ↓ 在重开钮再开。
      await _press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        find.byKey(WorkbenchStage.reopenItemKey(tabK.id)),
        findsOneWidget,
        reason: '↓ 在重开钮 = 开菜单',
      );

      // 菜单内 Enter 原生选中 → 重开发生、栈出清、菜单关闭。
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.tabs.map((t) => t.id), [tabK.id]);
      expect(controller.recentlyClosedTabs, isEmpty);
      expect(
        find.byKey(WorkbenchStage.reopenItemKey(tabK.id)),
        findsNothing,
        reason: '菜单已关闭',
      );
      // 重开后重开钮回禁用态（栈空）。
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.byKey(WorkbenchStage.reopenButtonKey),
                matching: find.byType(Opacity),
              ).first,
            )
            .opacity,
        lessThan(1.0),
      );
    });

    testWidgets('空栈：点击 / Enter / ↓ 均空转不开菜单（A2-10 边界）', (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      await _pump(tester, controller, zoneRegistry: registry);
      // 每次现取 Navigator 状态（重 pump 会重建元素树，旧 state 失效）。
      bool menuRouteOpen() =>
          tester.state<NavigatorState>(find.byType(Navigator)).canPop();

      // 点击不开菜单。
      await tester.tap(find.byKey(WorkbenchStage.reopenButtonKey));
      await tester.pumpAndSettle();
      expect(menuRouteOpen(), isFalse, reason: '空栈点击不开菜单');

      // 聚焦后 Enter / ↓ 空转（空舞台 F6 入口直落重开钮）。
      expect(registry.focus(WorkbenchFocusZone.stageTabBar), isTrue);
      await tester.pump();
      expect(_focusWithinKeySubtree(WorkbenchStage.reopenButtonKey), isTrue);
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(menuRouteOpen(), isFalse, reason: '空栈 Enter 空转');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(menuRouteOpen(), isFalse, reason: '空栈 ↓ 空转');
    });

    testWidgets('480px 宽舞台 + 20 tab：尾部两钮恒在视口内且滚动区可用（A2-11）', (tester) async {
      for (var i = 0; i < 20; i++) {
        controller.openGrid(_ref('w_$i', rows: _numericRows), 'Tab $i');
      }
      await _pump(tester, controller, width: 480);
      expect(tester.takeException(), isNull);

      final stageRect = tester.getRect(find.byType(WorkbenchStage));
      expect(stageRect.width, 480);
      final reopenRect = tester.getRect(
        find.byKey(WorkbenchStage.reopenButtonKey),
      );
      final collapseRect = tester.getRect(
        find.byKey(WorkbenchStage.collapseKey),
      );
      expect(reopenRect.right, lessThanOrEqualTo(stageRect.right));
      expect(collapseRect.right, lessThanOrEqualTo(stageRect.right));
      // Rect.contains 右/下边界开区间——贴右缘的收起钮用逐边比较断言恒在
      // 舞台视口内。
      expect(collapseRect.left, greaterThanOrEqualTo(stageRect.left));
      expect(collapseRect.top, greaterThanOrEqualTo(stageRect.top));
      expect(collapseRect.bottom, lessThanOrEqualTo(stageRect.bottom));
      expect(reopenRect.left, greaterThanOrEqualTo(stageRect.left));
      expect(reopenRect.top, greaterThanOrEqualTo(stageRect.top));

      final scrollPos = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollPos.position.maxScrollExtent, greaterThan(0),
          reason: 'tab 滚动区仍可用');
    });
  });

  group('A5 焦点区注册（F6：舞台 tab 条 + 内容区）', () {
    testWidgets('挂载注册两区；tab 条入口 = 聚焦激活 tab；内容区入口 = 激活槽首个可聚焦元素', (tester) async {
      // 批3：sessionList 退役——改用 sqlStudio 容器（edit 子态）承载内容区
      // 入口断言。
      final registry = WorkbenchFocusZoneRegistry();
      controller.openEditorSlot('SELECT 1');
      await _pump(tester, controller, zoneRegistry: registry);

      expect(registry.isRegistered(WorkbenchFocusZone.stageTabBar), isTrue);
      expect(registry.isRegistered(WorkbenchFocusZone.stageContent), isTrue);

      // tab 条入口：聚焦激活 tab（debugLabel = stage_tab_<id>）。
      expect(registry.focus(WorkbenchFocusZone.stageTabBar), isTrue);
      await tester.pump();
      final String? activeTabId = controller.activeTab?.id;
      expect(activeTabId, isNotNull);
      expect(_focusedTabId(), activeTabId);

      // 内容区入口：sqlStudio 容器首个可聚焦元素（分段 Editor，顶部左首）。
      expect(registry.focus(WorkbenchFocusZone.stageContent), isTrue);
      await tester.pump();
      expect(
        _focusWithinKey(WorkbenchStage.contentAreaKey),
        isTrue,
        reason: '容器内容首可聚焦元素（分段控件）落在内容区内',
      );
    });

    testWidgets('空舞台：tab 条入口聚焦重开钮返回 true（死档①消除，A1-5）；内容区入口仍 false', (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      await _pump(tester, controller, zoneRegistry: registry);

      expect(registry.isRegistered(WorkbenchFocusZone.stageTabBar), isTrue);
      // 空舞台不再整区跳过：回退目标 = 重开钮（禁用态可聚焦）。
      expect(registry.focus(WorkbenchFocusZone.stageTabBar), isTrue);
      await tester.pump();
      expect(_focusWithinKeySubtree(WorkbenchStage.reopenButtonKey), isTrue);
      expect(registry.focus(WorkbenchFocusZone.stageContent), isFalse);
    });

    testWidgets('卸载 → 两区注销（挂载/卸载随子树生命周期）', (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      await _pump(tester, controller, zoneRegistry: registry);
      expect(registry.registeredZones, isNotEmpty);

      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(registry.isRegistered(WorkbenchFocusZone.stageTabBar), isFalse);
      expect(registry.isRegistered(WorkbenchFocusZone.stageContent), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 批3 T7 实现期补断言（红测文件申报的「实现期补」三项）：
  // AI 推测字段虚线框（UI35-307/308）/ 取数不重复（UI35-306 spy 等价）/
  // 编译级类型完备性（UI35-302~304——旧枚举删除只能编译期验证，此处补
  // 新枚举值集完备断言）。
  // ──────────────────────────────────────────────────────────────────────────

  group('批3 UI35-302~304 编译级类型完备性（新枚举值集）', () {
    test('四容器枚举值集 = 冻结契约（sqlStudio/dataViz/schema/diagnostics）', () {
      expect(
        WorkbenchStageContainerKind.values.map((v) => v.name).toList(),
        ['sqlStudio', 'dataViz', 'schema', 'diagnostics'],
        reason: 'B-01 冻结枚举逐字',
      );
    });

    test('四容器子态枚举值集逐字（edit/diff、grid/chart、columns/indexes/ddl、'
        'explainPlan/liveMonitor）', () {
      expect(
        SqlStudioSubKind.values.map((v) => v.name).toList(),
        ['edit', 'diff'],
      );
      expect(
        DataVizSubKind.values.map((v) => v.name).toList(),
        ['grid', 'chart'],
      );
      expect(
        SchemaSubKind.values.map((v) => v.name).toList(),
        ['columns', 'indexes', 'ddl'],
      );
      expect(
        DiagnosticsSubKind.values.map((v) => v.name).toList(),
        ['explainPlan', 'liveMonitor'],
      );
    });

    test('四容器子枚举统一实现 WorkbenchStageSubKind 标记接口（分段路由类型面）',
        () {
      for (final v in SqlStudioSubKind.values) {
        expect(v, isA<WorkbenchStageSubKind>());
      }
      for (final v in DataVizSubKind.values) {
        expect(v, isA<WorkbenchStageSubKind>());
      }
      for (final v in SchemaSubKind.values) {
        expect(v, isA<WorkbenchStageSubKind>());
      }
      for (final v in DiagnosticsSubKind.values) {
        expect(v, isA<WorkbenchStageSubKind>());
      }
    });
  });

  group('批3 UI35-306 取数不重复（chart 子态共享结果集 spy 等价）', () {
    testWidgets('grid→chart→grid 切换：resultRef 同一实例（同一数据源，不重新取数）', (
      tester,
    ) async {
      final shared = _ref(
        'res_shared_spy',
        columns: const ['id', 'amount'],
        rows: _numericRows,
      );
      controller.openGrid(shared, null);
      await _pump(tester, controller);
      final tab = controller.tabs.single;
      expect(identical(tab.resultRef, shared), isTrue, reason: '前置：同实例');

      // 切 chart 子态：分段回写 selectSubKind——载荷引用不变（不重新取数）。
      controller.selectSubKind(tab.id, DataVizSubKind.chart);
      await tester.pumpAndSettle();
      expect(find.byType(ChartView), findsOneWidget, reason: 'chart 子态渲染');
      expect(
        identical(controller.tabs.single.resultRef, shared),
        isTrue,
        reason: 'chart 切换不换数据源实例',
      );

      // 切回 grid：网格回归同一引用。
      controller.selectSubKind(tab.id, DataVizSubKind.grid);
      await tester.pumpAndSettle();
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      expect(identical(controller.tabs.single.resultRef, shared), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('批3 UI35-307/308 AI 推测字段虚线框（不写回）', () {
    testWidgets('aiInferredColumns 非空 → columns 子段虚线框 + 注记文案；'
        '零按钮零回调（不写回 schema）', (tester) async {
      controller.openStructure(
        StageStructureData(
          tableName: 'orders',
          columns: [
            DbColumn(
              name: 'id',
              type: 'bigint',
              isPrimaryKey: true,
              isNullable: false,
            ),
          ],
          indexes: const [],
          foreignKeys: const [],
          ddl: null,
          aiInferredColumns: [
            StageAiInferredColumn(
              column: DbColumn(name: 'tenant_id', type: 'bigint'),
              note: 'sampled 9/10 rows non-null',
            ),
          ],
        ),
      );
      await _pump(tester, controller);

      // 默认 columns 子段：实查列 + 虚线框推测列 + 注记文案。
      expect(find.text('id'), findsOneWidget);
      expect(find.text('tenant_id'), findsOneWidget, reason: '推测列在 columns 子段');
      expect(
        find.text('AI inferred: sampled 9/10 rows non-null'),
        findsOneWidget,
        reason: 'agentStageAiInferred 注记',
      );
      // 不写回：无任何动作按钮（虚线框纯展示，构造性零写路径）。
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
