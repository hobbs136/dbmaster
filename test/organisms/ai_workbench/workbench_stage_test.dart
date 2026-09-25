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

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/organisms/results/chart_view.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
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

Future<void> _pump(
  WidgetTester tester,
  WorkbenchStageController controller, {
  double width = 1024,
  double height = 768,
  void Function(String sql)? onOpenInClassic,
}) async {
  await tester.pumpWidget(
    _wrap(
      WorkbenchStage(controller: controller, onOpenInClassic: onOpenInClassic),
      width: width,
      height: height,
    ),
  );
  await tester.pumpAndSettle();
}

/// 当前聚焦的舞台 tab id（焦点节点 debugLabel = `stage_tab_<id>`）。
String? _focusedTabId() => FocusManager.instance.primaryFocus?.debugLabel
    ?.replaceFirst('stage_tab_', '');

/// 成对发送按下/抬起（AGENTS.md §8-10：模拟键盘事件须遵循事件模型，
/// 缺抬起会触发 HardwareKeyboard 断言）。
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
}

void main() {
  late WorkbenchStageController controller;

  setUp(() {
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
            matching: find.text('R1'),
          ),
        );
        expect(label.style?.color, colors.textPrimary);

        final inactiveLabel = tester.widget<Text>(find.text('R2'));
        expect(inactiveLabel.style?.color, colors.textSecondary);
      },
    );

    testWidgets('标签超 200 → ellipsis 且 tooltip 为全 label', (tester) async {
      final longLabel = 'A very long stage tab label that must be truncated';
      final tab = controller.openGrid(
        _ref('res_1', rows: _numericRows),
        longLabel,
      );
      await _pump(tester, controller);

      final label = tester.widget<Text>(find.text(longLabel));
      expect(label.overflow, TextOverflow.ellipsis);
      expect(label.maxLines, 1);
      // tooltip 承载被截断的全文（§0.4）。
      expect(find.byTooltip(longLabel), findsOneWidget);
      final itemRect = tester.getRect(
        find.byKey(WorkbenchStage.tabItemKey(tab.id)),
      );
      expect(
        itemRect.width,
        lessThanOrEqualTo(AppDesignSystem.workbenchStageTabMaxWidth + 1),
      );
    });
  });

  group('§5.4-5 溢出滚动与键盘', () {
    testWidgets('20 tab 横向滚动可用；新开 tab 自动滚入视口', (tester) async {
      for (var i = 0; i < 20; i++) {
        controller.openGrid(_ref('res_$i', rows: _numericRows), 'Tab $i');
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

    testWidgets('←/→/Home/End roving 键盘可达全部 tab；Enter 激活', (tester) async {
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        ids.add(
          controller.openGrid(_ref('res_$i', rows: _numericRows), 'Tab $i').id,
        );
      }
      await _pump(tester, controller);

      // 激活 tab（19）已被自动滚入视口：点它进入 tab 焦点组（onActivate 内
      // requestFocus）。
      await tester.tap(find.text('Tab 19'));
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[19]);

      // Home → 首个 tab（滚动跟随焦点）。
      await _press(tester, LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[0]);

      // End → 最后一个 tab。
      await _press(tester, LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[19]);

      // 相邻移动：← 回到 18。
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedTabId(), ids[18]);

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
    testWidgets('三元素齐（图标 + 标题 + 说明）且无按钮', (tester) async {
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

  group('§5.3 打开时机与 §6.3 pin 语义（controller）', () {
    test('openXxx 自动开舞台 + 激活新 tab；同 refId 网格/图表去重', () {
      expect(controller.stageVisible, isFalse);
      controller.openGrid(_ref('res_1'), null);
      expect(controller.stageVisible, isTrue);
      expect(controller.activeTabIndex, 0);

      controller.openChart(_ref('res_1'), null);
      expect(controller.tabs.length, 2);
      expect(controller.activeTabIndex, 1);

      // 同 refId 网格重开 → 复用激活。
      controller.openGrid(_ref('res_1'), '标题');
      expect(controller.tabs.length, 2);
      expect(controller.activeTabIndex, 0);
      expect(controller.tabs.first.title, '标题');

      // 同表结构重开 → 复用。
      controller.openStructure(_structure());
      controller.openStructure(_structure());
      expect(
        controller.tabs.where((t) => t.kind == WorkbenchStageTabKind.structure),
        hasLength(1),
      );
    });

    test('pinArtifact 不改舞台可见性；建 pinned 网格 tab；幂等', () {
      expect(controller.stageVisible, isFalse);
      final tab = controller.pinArtifact(_ref('res_1'), '产物 A');
      expect(controller.stageVisible, isFalse); // §6.3：钉入不开舞台
      expect(tab.pinned, isTrue);
      expect(tab.kind, WorkbenchStageTabKind.grid);
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

    testWidgets('结构卡：describe 四件分组 + PK/NN 徽标 + 表名标签', (tester) async {
      controller.openStructure(_structure());
      await _pump(tester, controller);
      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('Indexes'), findsOneWidget);
      expect(find.text('Foreign Keys'), findsOneWidget);
      expect(find.text('DDL'), findsOneWidget);
      expect(find.text('PK'), findsOneWidget);
      expect(find.text('NN'), findsOneWidget);
      expect(find.text('idx_status'), findsOneWidget);
      expect(find.text('customer_id → customers.id'), findsOneWidget);
      expect(
        find.text('CREATE TABLE orders (id bigint NOT NULL PRIMARY KEY);'),
        findsOneWidget,
      );
      // 表名即 tab 标签。
      expect(find.text('orders'), findsOneWidget);
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
}
