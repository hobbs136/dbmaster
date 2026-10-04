// T25 WorkbenchArtifactStrip 组件测试（ui 规格 design-ai-agent-ui.md §6.4 验收 +
// §6.1/§6.2/§6.3 结构与语义）。
//
// 覆盖：
// - §6.4-1：条高 32 ±1；舞台开/关两态均常驻（findsNothing 为空）；空态呈现；
// - §6.4-2：pin_artifact 后 3 帧内条内出现该项，且舞台可见性不变；
// - §6.4-3：条内 × 后项消失、对应舞台 tab 仍在（集合断言）；关闭 tab 后
//   条内项消失（双向）；
// - §6.4-4：项顺序 == 舞台 tab 时间序 pinned 子集（非钉入动作序）；
// - §6.4-5：标签超 160 → ellipsis + tooltip 全 label；10 项横向滚动可用、
//   不换行（条高恒 32）、新项自动滚入视口；
// - §6.4-6：结构增删无动画（无活跃 Ticker）；激活项底色过渡存在（200ms）+
//   激活/非激活色对（规格明示的色断言）；
// - §6.4-7：键盘 roving（←/→）+ Enter 开舞台并激活 + Delete 取消钉住 +
//   × 可 Tab 到达（Enter 取消钉住）；
// - §6.1/§6.3 开关语义：翻转 stageVisible、图标与标签同步、收起时条照常 +
//   点项重开舞台。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_artifact_strip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_focus_zones.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';
import 'package:dbmaster/theme/app_colors.dart';

/// 挂载形态贴近生产（shell 底部全宽常驻条）：宽度紧约束铺满、高度松约束
/// （条高由自身 `artifactStripHeight` 决定）。不能把条直接塞进
/// `SizedBox(width, height)`——紧高度会覆盖条自身的 32（§6.4-1 断言前提）。
Widget _wrap(Widget child) => MaterialApp(
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
      child: SizedBox(width: double.infinity, child: child),
    ),
  ),
);

AgentResultRef _ref(String refId) => AgentResultRef(
  refId: refId,
  sql: 'SELECT 1',
  rowCount: 1,
  columns: const ['id'],
  rows: const [
    {'id': 1},
  ],
);

Future<void> _pump(
  WidgetTester tester,
  WorkbenchStageController controller, {
  WorkbenchFocusZoneRegistry? zoneRegistry,
}) async {
  // ui 规格 §6.4 验收窗口 1024×768。
  await tester.binding.setSurfaceSize(const Size(1024, 768));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _wrap(
      WorkbenchArtifactStrip(
        controller: controller,
        zoneRegistry: zoneRegistry,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 当前聚焦的产物项 tab id（焦点节点 debugLabel = `artifact_item_<id>`；
/// 焦点在 × 钮等其它节点上时返回 null）。
String? _focusedItemTabId() {
  final label = FocusManager.instance.primaryFocus?.debugLabel;
  if (label == null || !label.startsWith('artifact_item_')) return null;
  return label.replaceFirst('artifact_item_', '');
}

/// 主焦点是否落在某项的取消钉住钮（×）上。InkWell 内部 Focus 是 keyed
/// InkWell 的**后代**，故从焦点上下文沿祖先链查找 keyed 元素。
bool _focusIsWithinUnpin(String tabId) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final matches = find
      .byKey(WorkbenchArtifactStrip.itemUnpinKey(tabId))
      .evaluate();
  if (matches.isEmpty) return false;
  final keyed = matches.first;
  if (identical(ctx, keyed)) return true;
  var found = false;
  (ctx as Element).visitAncestorElements((ancestor) {
    if (identical(ancestor, keyed)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// 主焦点是否落在展开钮（toggleKey）上（同 `_focusIsWithinUnpin` 祖先链
/// 口径；F6 死档②回退断言用）。
bool _focusIsWithinToggle() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final matches = find.byKey(WorkbenchArtifactStrip.toggleKey).evaluate();
  if (matches.isEmpty) return false;
  final keyed = matches.first;
  if (identical(ctx, keyed)) return true;
  var found = false;
  (ctx as Element).visitAncestorElements((ancestor) {
    if (identical(ancestor, keyed)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// 成对发送按下/抬起（组件级 §8-10：缺抬起会触发 HardwareKeyboard 断言）。
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

  group('§6.4-1 常驻与几何', () {
    testWidgets('空舞台：条常驻、高 32±1、空态文案呈现', (tester) async {
      await _pump(tester, controller);
      expect(find.byKey(WorkbenchArtifactStrip.stripKey), findsOneWidget);
      final rect = tester.getRect(find.byKey(WorkbenchArtifactStrip.stripKey));
      expect(rect.height, closeTo(AppDesignSystem.artifactStripHeight, 1.0));
      final empty = tester.widget<Text>(
        find.byKey(WorkbenchArtifactStrip.emptyKey),
      );
      expect(empty.data, 'No pinned artifacts');
    });

    testWidgets('舞台开/关两态条均常驻（findsNothing 为空）', (tester) async {
      final tab = controller.pinArtifact(_ref('res_1'), 'R1');
      await _pump(tester, controller);

      controller.setStageVisible(true);
      await tester.pumpAndSettle();
      expect(find.byKey(WorkbenchArtifactStrip.stripKey), findsOneWidget);

      controller.setStageVisible(false);
      await tester.pumpAndSettle();
      expect(find.byKey(WorkbenchArtifactStrip.stripKey), findsOneWidget);
      // 收起时产物项照常显示（§6.3）
      expect(
        find.byKey(WorkbenchArtifactStrip.itemKey(tab.id)),
        findsOneWidget,
      );
    });
  });

  group('§6.4-2 pin 投影', () {
    testWidgets('pinArtifact 后 3 帧内条内出现该项且舞台可见性不变', (tester) async {
      await _pump(tester, controller);
      expect(controller.stageVisible, isFalse);

      final tab = controller.pinArtifact(_ref('res_1'), '查询结果');
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(
        find.byKey(WorkbenchArtifactStrip.itemKey(tab.id)),
        findsOneWidget,
      );
      // pin 不改舞台可见性（§6.3 行为表）
      expect(controller.stageVisible, isFalse);
    });

    testWidgets('未 pinned 的舞台 tab 不进条', (tester) async {
      final tab = controller.openGrid(_ref('res_1'), 'R1'); // 不 pinned
      await _pump(tester, controller);
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(tab.id)), findsNothing);
      expect(find.byKey(WorkbenchArtifactStrip.emptyKey), findsOneWidget);
    });
  });

  group('§6.4-3 × 双向集合断言', () {
    testWidgets('条内 × 取消钉住：项消失、对应舞台 tab 仍在（pinned=false）', (tester) async {
      final keep = controller.pinArtifact(_ref('res_1'), 'R1');
      final drop = controller.pinArtifact(_ref('res_2'), 'R2');
      await _pump(tester, controller);

      await tester.tap(
        find.byKey(WorkbenchArtifactStrip.itemUnpinKey(drop.id)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(WorkbenchArtifactStrip.itemKey(drop.id)), findsNothing);
      expect(
        find.byKey(WorkbenchArtifactStrip.itemKey(keep.id)),
        findsOneWidget,
      );
      // tab 保留（§6.3：× 只取消钉住，不销毁 tab）
      expect(controller.tabs.length, 2);
      expect(
        controller.tabs.firstWhere((t) => t.id == drop.id).pinned,
        isFalse,
      );
    });

    testWidgets('关闭舞台 tab → 条内项同步消失（双向）', (tester) async {
      final tab = controller.pinArtifact(_ref('res_1'), 'R1');
      await _pump(tester, controller);

      final index = controller.tabs.indexWhere((t) => t.id == tab.id);
      controller.closeTab(index);
      await tester.pumpAndSettle();

      expect(find.byKey(WorkbenchArtifactStrip.itemKey(tab.id)), findsNothing);
      expect(controller.tabs, isEmpty);
      expect(find.byKey(WorkbenchArtifactStrip.emptyKey), findsOneWidget);
    });

    testWidgets('pinned tab 关闭 → 重开 → 条目自动重现（投影语义，走查修复批 A2-6，AI-WF-202）', (tester) async {
      final p1 = controller.pinArtifact(_ref('rp1'), 'P1');
      final p2 = controller.pinArtifact(_ref('rp2'), 'P2');
      await _pump(tester, controller);
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(p2.id)), findsOneWidget);

      // 关闭 pinned p2 → 项消失；另一 pinned 项不受影响（关闭 ≠ 取消钉住）。
      controller.closeTab(1);
      await tester.pumpAndSettle();
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(p2.id)), findsNothing);
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(p1.id)), findsOneWidget);

      // 重开 → 条目自动重现（pinned 标记随对象原样恢复）。
      controller.reopenClosedTab(p2.id);
      await tester.pumpAndSettle();
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(p2.id)), findsOneWidget);
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(p1.id)), findsOneWidget);
    });
  });

  group('§6.4-4 顺序', () {
    testWidgets('条内顺序 == 舞台 tab 时间序 pinned 子集（非钉入动作序）', (tester) async {
      controller.openGrid(_ref('res_a'), 'A');
      final b = controller.openGrid(_ref('res_b'), 'B');
      final c = controller.openGrid(_ref('res_c'), 'C');
      // 钉入动作序：C 先、B 后 → 条内仍应为 B、C（tab 时间序，§6.1）
      controller.setPinned(2, true);
      controller.setPinned(1, true);
      await _pump(tester, controller);

      final rectB = tester.getRect(
        find.byKey(WorkbenchArtifactStrip.itemKey(b.id)),
      );
      final rectC = tester.getRect(
        find.byKey(WorkbenchArtifactStrip.itemKey(c.id)),
      );
      expect(rectB.left, lessThan(rectC.left));
    });
  });

  group('§6.4-5 标签与溢出', () {
    testWidgets('标签超 160 → ellipsis + tooltip 全 label + 项宽不超上限', (
      tester,
    ) async {
      final longLabel = 'A very long artifact label that must be truncated';
      final tab = controller.pinArtifact(_ref('res_1'), longLabel);
      await _pump(tester, controller);

      final label = tester.widget<Text>(find.text(longLabel));
      expect(label.overflow, TextOverflow.ellipsis);
      expect(label.maxLines, 1);
      // tooltip 承载被截断的全文（§0.4）
      expect(find.byTooltip(longLabel), findsOneWidget);
      final rect = tester.getRect(
        find.byKey(WorkbenchArtifactStrip.itemKey(tab.id)),
      );
      expect(
        rect.width,
        lessThanOrEqualTo(AppDesignSystem.artifactStripItemMaxWidth + 1),
      );
    });

    testWidgets('10 项横向滚动可用、不换行（条高恒 32）、新项自动滚入视口', (tester) async {
      for (var i = 0; i < 10; i++) {
        controller.pinArtifact(_ref('res_$i'), 'Artifact label $i');
      }
      await _pump(tester, controller);

      final scrollable = tester.widget<Scrollable>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.axisDirection, AxisDirection.right);
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(state.position.maxScrollExtent, greaterThan(0));
      // 不换行：条高恒 32（§6.1 溢出规则）
      expect(
        tester.getRect(find.byKey(WorkbenchArtifactStrip.stripKey)).height,
        closeTo(AppDesignSystem.artifactStripHeight, 1.0),
      );

      // 新项（第 11 个）自动滚入视口：滚动偏移前移
      final fresh = controller.pinArtifact(_ref('res_new'), 'Artifact label z');
      await tester.pumpAndSettle();
      expect(state.position.pixels, greaterThan(0));
      // 滚入视口：新项完整落在条视口宽度内
      final rect = tester.getRect(
        find.byKey(WorkbenchArtifactStrip.itemKey(fresh.id)),
      );
      expect(rect.right, lessThanOrEqualTo(1024));
    });
  });

  group('§6.4-6 动效', () {
    testWidgets('结构增删零动效（无活跃 Ticker）；激活项底色 200ms 过渡存在', (tester) async {
      final t1 = controller.pinArtifact(_ref('res_1'), 'R1');
      final t2 = controller.pinArtifact(_ref('res_2'), 'R2');
      await _pump(tester, controller);

      // 插入（未溢出，不触发滚动动画）→ 无活跃 Ticker（§6.2 结构增删零动效）
      final t3 = controller.pinArtifact(_ref('res_3'), 'R3');
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      // 移除（取消钉住）→ 无活跃 Ticker
      controller.setPinned(controller.tabs.indexOf(t3), false);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      // 激活切换 → 底色过渡存在（AnimatedContainer 200ms）
      controller.activateTab(controller.tabs.indexOf(t2));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();

      // 激活项 bgTertiary + 标签 textPrimary；非激活透明 + textSecondary
      final ctx = tester.element(find.byKey(WorkbenchArtifactStrip.stripKey));
      final colors = ctx.themeColors;
      final activeContainer = tester.widget<AnimatedContainer>(
        find.byKey(WorkbenchArtifactStrip.itemKey(t2.id)),
      );
      expect(
        (activeContainer.decoration as BoxDecoration).color,
        colors.bgTertiary,
      );
      final activeLabel = tester.widget<Text>(
        find.descendant(
          of: find.byKey(WorkbenchArtifactStrip.itemKey(t2.id)),
          matching: find.text('R2'),
        ),
      );
      expect(activeLabel.style?.color, colors.textPrimary);

      final inactiveContainer = tester.widget<AnimatedContainer>(
        find.byKey(WorkbenchArtifactStrip.itemKey(t1.id)),
      );
      expect(
        (inactiveContainer.decoration as BoxDecoration).color,
        Colors.transparent,
      );
      final inactiveLabel = tester.widget<Text>(
        find.descendant(
          of: find.byKey(WorkbenchArtifactStrip.itemKey(t1.id)),
          matching: find.text('R1'),
        ),
      );
      expect(inactiveLabel.style?.color, colors.textSecondary);
    });
  });

  group('§6.4-7 键盘', () {
    testWidgets('roving ←/→ 移动；Enter 开舞台并激活对应 tab', (tester) async {
      final t1 = controller.pinArtifact(_ref('res_1'), 'R1');
      final t2 = controller.pinArtifact(_ref('res_2'), 'R2');
      expect(controller.stageVisible, isFalse);
      await _pump(tester, controller);

      // 点项聚焦（同时回开舞台——§6.3 点项重开舞台）；再收起，聚焦保持
      await tester.tap(find.byKey(WorkbenchArtifactStrip.itemKey(t1.id)));
      await tester.pumpAndSettle();
      expect(controller.stageVisible, isTrue);
      controller.setStageVisible(false);
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focusedItemTabId(), t2.id);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_focusedItemTabId(), t1.id);

      // Enter = 开舞台并激活对应 tab（§6.1 键盘）
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.stageVisible, isTrue);
      expect(controller.activeTabIndex, controller.tabs.indexOf(t1));
    });

    testWidgets('Delete 取消钉住：项消失、tab 保留', (tester) async {
      final t1 = controller.pinArtifact(_ref('res_1'), 'R1');
      final t2 = controller.pinArtifact(_ref('res_2'), 'R2');
      await _pump(tester, controller);

      await tester.tap(find.byKey(WorkbenchArtifactStrip.itemKey(t2.id)));
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(find.byKey(WorkbenchArtifactStrip.itemKey(t2.id)), findsNothing);
      expect(controller.tabs.length, 2);
      expect(controller.tabs.firstWhere((t) => t.id == t2.id).pinned, isFalse);
      // 其余项不受影响
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(t1.id)), findsOneWidget);
    });

    testWidgets('× 独立可聚焦：Tab 到达后 Enter 取消钉住', (tester) async {
      final t1 = controller.pinArtifact(_ref('res_1'), 'R1');
      await _pump(tester, controller);

      await tester.tap(find.byKey(WorkbenchArtifactStrip.itemKey(t1.id)));
      await tester.pumpAndSettle();
      // Tab → ×（组内显式定序：项 → ×）
      await _press(tester, LogicalKeyboardKey.tab);
      expect(_focusIsWithinUnpin(t1.id), isTrue);

      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(t1.id)), findsNothing);
      expect(controller.tabs.firstWhere((t) => t.id == t1.id).pinned, isFalse);
    });
  });

  group('§6.1/§6.3 舞台开合开关', () {
    testWidgets('开合语义收窄（走查修复批件①）：展开钮仅收起态渲染；收起改走舞台 tab 条右端收起钮', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 舞台与产物条同树共享 controller：收起钮在舞台 tab 条右端，组件面
      // 需两件同挂才能走完整开合回路。
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 400,
            child: Column(
              children: [
                Expanded(child: WorkbenchStage(controller: controller)),
                WorkbenchArtifactStrip(controller: controller),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stripFinder = find.byType(WorkbenchArtifactStrip);
      final separatorFinder = find.descendant(
        of: find.byType(WorkbenchArtifactStrip),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints ==
                  const BoxConstraints.tightFor(width: 1.0, height: 16.0),
        ),
      );

      // 收起态：strip 左端展开钮（panelRight 图标 + 「Stage」文案，tooltip
      // 同步，A1-3）+ 分隔线在。
      expect(
        find.descendant(of: stripFinder, matching: find.text('Stage')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stripFinder,
          matching: find.byIcon(LucideIcons.panelRight),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Stage'), findsOneWidget);
      expect(separatorFinder, findsOneWidget);

      // tap 展开钮 → stageVisible == true（A1-3）。
      await tester.tap(find.byKey(WorkbenchArtifactStrip.toggleKey));
      await tester.pumpAndSettle();
      expect(controller.stageVisible, isTrue);

      // 展开态：strip 内 toggle 与分隔线一并消失（A1-1）；「收起」语义在
      // 舞台收起钮，strip 子树无「Collapse Stage」（A1-8：件①零新增 key）。
      expect(find.byKey(WorkbenchArtifactStrip.toggleKey), findsNothing);
      expect(separatorFinder, findsNothing);
      expect(
        find.descendant(of: stripFinder, matching: find.text('Collapse Stage')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: stripFinder,
          matching: find.byIcon(LucideIcons.panelRightClose),
        ),
        findsNothing,
      );
      expect(find.byKey(WorkbenchStage.collapseKey), findsOneWidget);

      // 「收起」改走 collapseKey → 回收起态，strip 展开钮重现
      // （panelRight + 「Stage」，A1-3）。
      await tester.tap(find.byKey(WorkbenchStage.collapseKey));
      await tester.pumpAndSettle();
      expect(controller.stageVisible, isFalse);
      expect(find.byKey(WorkbenchArtifactStrip.toggleKey), findsOneWidget);
      expect(
        find.descendant(of: stripFinder, matching: find.text('Stage')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stripFinder,
          matching: find.byIcon(LucideIcons.panelRight),
        ),
        findsOneWidget,
      );
    });

    testWidgets('舞台收起时条照常；点项重开舞台并激活该 tab', (tester) async {
      final t1 = controller.pinArtifact(_ref('res_1'), 'R1');
      final t2 = controller.pinArtifact(_ref('res_2'), 'R2');
      controller.setStageVisible(false);
      await _pump(tester, controller);

      expect(find.byKey(WorkbenchArtifactStrip.itemKey(t1.id)), findsOneWidget);
      expect(find.byKey(WorkbenchArtifactStrip.itemKey(t2.id)), findsOneWidget);

      await tester.tap(find.byKey(WorkbenchArtifactStrip.itemKey(t2.id)));
      await tester.pumpAndSettle();
      expect(controller.stageVisible, isTrue);
      expect(controller.activeTabIndex, controller.tabs.indexOf(t2));
    });
  });

  group('A5 焦点区注册（F6：产物条）', () {
    testWidgets('条挂载注册产物条区；入口 = 聚焦首个条目（pinned 时间序首位）',
        (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      final t1 = controller.pinArtifact(_ref('res_1'), 'R1');
      controller.pinArtifact(_ref('res_2'), 'R2');
      await _pump(tester, controller, zoneRegistry: registry);

      expect(registry.isRegistered(WorkbenchFocusZone.artifactStrip), isTrue);
      expect(registry.focus(WorkbenchFocusZone.artifactStrip), isTrue);
      await tester.pump();
      expect(_focusedItemTabId(), t1.id);
    });

    testWidgets('零 pinned 且舞台收起：区入口聚焦展开钮返回 true（死档②消除，A1-5，AI-WF-201）',
        (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      await _pump(tester, controller, zoneRegistry: registry);

      expect(registry.isRegistered(WorkbenchFocusZone.artifactStrip), isTrue);
      expect(controller.stageVisible, isFalse);
      expect(registry.focus(WorkbenchFocusZone.artifactStrip), isTrue);
      await tester.pump();
      expect(_focusIsWithinToggle(), isTrue);
    });

    testWidgets('零 pinned 且舞台可见：区入口返回 false（轮转动态跳过）',
        (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      controller.setStageVisible(true);
      await _pump(tester, controller, zoneRegistry: registry);

      expect(registry.isRegistered(WorkbenchFocusZone.artifactStrip), isTrue);
      expect(registry.focus(WorkbenchFocusZone.artifactStrip), isFalse);
    });

    testWidgets('卸载 → 注销（挂载/卸载随子树生命周期）', (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      controller.pinArtifact(_ref('res_1'), 'R1');
      await _pump(tester, controller, zoneRegistry: registry);
      expect(registry.isRegistered(WorkbenchFocusZone.artifactStrip), isTrue);

      await tester.pumpWidget(
        _wrap(const SizedBox.shrink()),
      );
      await tester.pumpAndSettle();
      expect(registry.isRegistered(WorkbenchFocusZone.artifactStrip), isFalse);
    });
  });
}
