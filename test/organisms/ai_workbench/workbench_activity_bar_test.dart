// AI 工作台活动条组件测试（v2 结果面板第一批 A1，
// brainstorm-workbench-results-panel-v2 §6-1.1 / §8-1 / §8-10）。
//
// 覆盖：44 token 宽（§8-1 总宽 240 = 44 + 196 的活动条项）/ 会话页图标 +
// ValueKey + tooltip 渲染 / onPageSelected 行为上报。
// A5 追加：roving 键盘（↑/↓ 相邻、Home/End 首末、越界钳制）+ Enter 触发
// onPageSelected + 注册为 F6 第一区（入口聚焦选中页图标）+ 页列表缩减的
// 焦点节点清理。收窄态点击路由不断言（A2 接线）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_activity_bar.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_focus_zones.dart';
import 'package:dbmaster/theme/design_system.dart';

void main() {
  /// 泵独立活动条（组件面）。
  Future<void> pumpBar(
    WidgetTester tester, {
    List<WorkbenchRailPage> pages = const [WorkbenchRailPage.sessions],
    WorkbenchRailPage currentPage = WorkbenchRailPage.sessions,
    ValueChanged<WorkbenchRailPage>? onPageSelected,
    WorkbenchFocusZoneRegistry? zoneRegistry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 400,
              child: WorkbenchActivityBar(
                pages: pages,
                currentPage: currentPage,
                onPageSelected: onPageSelected ?? (_) {},
                zoneRegistry: zoneRegistry,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 当前聚焦的页面 id（焦点节点 debugLabel = `workbench_activity_<pageId>`）。
  String? _focusedPageId() => FocusManager.instance.primaryFocus?.debugLabel
      ?.replaceFirst('workbench_activity_', '');

  /// 成对发送按下/抬起（AGENTS.md §8-10：缺抬起会触发 HardwareKeyboard
  /// 断言）。
  Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
  }

  group('WorkbenchActivityBar（v2 A1）', () {
    testWidgets('宽度 = workbenchRailActivityBarWidth 44（§8-1 rail 44+196=240）',
        (tester) async {
      await pumpBar(tester);

      final size = tester.getSize(find.byType(WorkbenchActivityBar));
      expect(size.width, AppDesignSystem.workbenchRailActivityBarWidth);
    });

    testWidgets('会话页：图标 + ValueKey + tooltip（六语 key 消费，en 锁定）',
        (tester) async {
      await pumpBar(tester);

      expect(
        find.byKey(const ValueKey('workbench_activity_sessions')),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);
      expect(find.byTooltip('Sessions'), findsOneWidget,
          reason: 'tooltip 消费预登记 key workbenchActivitySessions');
    });

    testWidgets('点击图标 → onPageSelected 上报对应页', (tester) async {
      WorkbenchRailPage? reported;
      await pumpBar(
        tester,
        onPageSelected: (page) => reported = page,
      );

      await tester.tap(
        find.byKey(const ValueKey('workbench_activity_sessions')),
      );
      await tester.pumpAndSettle();

      expect(reported, WorkbenchRailPage.sessions);
    });
  });

  group('A5 roving 键盘 + F6 第一区注册（v2 §8-6）', () {
    const List<WorkbenchRailPage> allPages = [
      WorkbenchRailPage.sessions,
      WorkbenchRailPage.savedQueries,
      WorkbenchRailPage.history,
    ];

    testWidgets('注册为 F6 第一区（activityBar）；入口聚焦当前选中页图标',
        (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      await pumpBar(
        tester,
        pages: allPages,
        currentPage: WorkbenchRailPage.savedQueries,
        zoneRegistry: registry,
      );

      expect(
        registry.isRegistered(WorkbenchFocusZone.activityBar),
        isTrue,
      );
      expect(registry.focus(WorkbenchFocusZone.activityBar), isTrue);
      await tester.pump();
      expect(_focusedPageId(), 'savedQueries',
          reason: '入口 = 聚焦当前选中页图标（对齐舞台 tab 条「聚焦激活 tab」）');
    });

    testWidgets('↑/↓ 相邻移动、Home/End 首末、越界钳制不回绕', (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      await pumpBar(tester, pages: allPages, zoneRegistry: registry);

      expect(registry.focus(WorkbenchFocusZone.activityBar), isTrue);
      await tester.pump();
      expect(_focusedPageId(), 'sessions');

      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedPageId(), 'savedQueries');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedPageId(), 'history');
      // 末位再 ↓ → 钳制（不回绕，沿舞台 tab 条语义）。
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedPageId(), 'history');

      await _press(tester, LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_focusedPageId(), 'savedQueries');

      await _press(tester, LogicalKeyboardKey.home);
      await tester.pump();
      expect(_focusedPageId(), 'sessions');
      await _press(tester, LogicalKeyboardKey.home);
      await tester.pump();
      expect(_focusedPageId(), 'sessions', reason: '首位再 Home → 钳制');

      await _press(tester, LogicalKeyboardKey.end);
      await tester.pump();
      expect(_focusedPageId(), 'history');
    });

    testWidgets('Enter 触发 onPageSelected（↑/↓ roving 后逐页可达）', (tester) async {
      final reported = <WorkbenchRailPage>[];
      final registry = WorkbenchFocusZoneRegistry();
      await pumpBar(
        tester,
        pages: allPages,
        onPageSelected: reported.add,
        zoneRegistry: registry,
      );

      expect(registry.focus(WorkbenchFocusZone.activityBar), isTrue);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(reported, [WorkbenchRailPage.sessions]);

      // ↓↓ 移到 history → Enter。
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedPageId(), 'history');
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(reported.last, WorkbenchRailPage.history);
    });

    testWidgets('页列表缩减 → 失页焦点节点清理，余页 roving 不受扰', (tester) async {
      final registry = WorkbenchFocusZoneRegistry();
      await pumpBar(tester, pages: allPages, zoneRegistry: registry);

      // 页列表缩减为仅 sessions（同一注册表实例；rail 未来页序变化清理路径）。
      await pumpBar(
        tester,
        pages: const [WorkbenchRailPage.sessions],
        zoneRegistry: registry,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workbench_activity_history')),
        findsNothing,
      );
      expect(
        registry.isRegistered(WorkbenchFocusZone.activityBar),
        isTrue,
        reason: '缩减后注册保持（同实例重登记）',
      );

      // 缩减后 roving 仍工作（clamp 到唯一页）。
      expect(registry.focus(WorkbenchFocusZone.activityBar), isTrue);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedPageId(), 'sessions', reason: '单页越界钳制');
    });
  });
}
