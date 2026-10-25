// UIRV-B4 · 启动骨架屏 + 阶段状态（任务书 `.specs/tasks-ui-review-fixes.md` §UIRV-B4）。
//
// 红测先行：以下用例从验收条款 1~7 直译，不从实现反推。
// BootShell 为纯表现层独立组件（MUST NOT #7：单测禁 import main.dart），
// 换壳/初始化序列在 main.dart 的 _BootRoot 中，widget 测试不覆盖（真机走查归批末）。
//
// 用例编号 UI-B4-xxx，登记 docs/test/unified_test_spec.md §6.23。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/screens/boot/boot_shell.dart';
import 'package:dbmaster/services/layout_preferences_service.dart';
import 'package:dbmaster/theme/design_system.dart';
Widget _host({
  required BootStage stage,
  String? errorDetail,
  VoidCallback? onRetry,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: BootShell(
        stage: stage,
        errorDetail: errorDetail,
        onRetry: onRetry,
      ),
    ),
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required BootStage stage,
  String? errorDetail,
  VoidCallback? onRetry,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    _host(
      stage: stage,
      errorDetail: errorDetail,
      onRetry: onRetry,
      disableAnimations: disableAnimations,
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

List<String> _allTexts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
}

void main() {
  testWidgets('UI-B4-101 AC1 · 启动态首帧：品牌 Logo + 「正在准备工作区」+ 不定态指示器 + 结构骨架，无错误卡', (
    tester,
  ) async {
    await _pumpShell(tester, stage: BootStage.generic);

    // 品牌区：Logo 图标 + DbMaster 字标 + 通用准备文案。
    expect(find.byIcon(LucideIcons.database), findsOneWidget);
    expect(find.text('DbMaster'), findsOneWidget);
    expect(find.text('Preparing your workspace…'), findsOneWidget);
    // 不定态指示器（结构特征：CircularProgressIndicator）存在。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 结构骨架存在（KeyedSubtree 定位骨架容器）。
    expect(find.byKey(const ValueKey('uirvBootSkeleton')), findsOneWidget);
    // 启动态不出现错误卡。
    expect(find.text('Startup problem'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('UI-B4-102 AC2 · 阶段文案接真实初始化步骤：至少 3 档可区分，无事件时停留通用文案', (
    tester,
  ) async {
    const stages = [
      BootStage.generic,
      BootStage.logger,
      BootStage.extensions,
      BootStage.telemetry,
      BootStage.server,
      BootStage.session,
    ];
    const preparing = 'Preparing your workspace…';
    // 阶段行 = 除品牌字标与通用准备文案外出现的文本（generic 时应为空集，
    // 即停留通用文案；其余阶段各自有专属文案）。
    final stageLines = <BootStage, Set<String>>{};
    for (final stage in stages) {
      await _pumpShell(tester, stage: stage);
      stageLines[stage] = _allTexts(
        tester,
      ).where((t) => t.isNotEmpty && t != 'DbMaster' && t != preparing).toSet();
    }
    expect(
      stageLines[BootStage.generic],
      isEmpty,
      reason: '无阶段事件时应停留通用文案（不显示具体阶段行）',
    );
    final distinct = stageLines.entries
        .where((e) => e.key != BootStage.generic)
        .map((e) => e.value)
        .toSet();
    expect(
      distinct.length,
      greaterThanOrEqualTo(3),
      reason: '阶段文案应至少区分 3 档，实际: $stageLines',
    );
  });

  testWidgets('UI-B4-103 AC2 · 任何状态下不出现百分比文本（不伪造进度）', (tester) async {
    for (final stage in BootStage.values) {
      await _pumpShell(
        tester,
        stage: stage,
        errorDetail: stage == BootStage.values.last ? 'boom' : null,
      );
      for (final t in _allTexts(tester)) {
        expect(t.contains('%'), isFalse, reason: '阶段 $stage 出现百分比文本: $t');
      }
    }
  });

  testWidgets('UI-B4-104 AC3 · 错误卡：标题 + 详情文本 + 重试按钮；点重试回调重跑初始化', (
    tester,
  ) async {
    var retries = 0;
    await _pumpShell(
      tester,
      stage: BootStage.server,
      errorDetail: 'HandshakeException: connection reset',
      onRetry: () => retries++,
    );

    expect(find.text('Startup problem'), findsOneWidget);
    expect(find.textContaining('HandshakeException'), findsOneWidget);
    final retryButton = find.widgetWithText(ElevatedButton, 'Retry');
    expect(retryButton, findsOneWidget);

    await tester.tap(retryButton);
    await tester.pump();
    expect(retries, 1, reason: '重试按钮应触发初始化序列重跑回调');
  });

  testWidgets('UI-B4-105 AC5 · 系统减少动态效果：停用循环动画（指示器不转、骨架不闪）', (tester) async {
    await _pumpShell(tester, stage: BootStage.generic, disableAnimations: true);

    // 无不定态转圈（静态替代物承担「正在进行」表达）。
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 推进时间后无任何调度中的动画 tick（无循环动画在跑）。
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'reduced-motion 下不应存在循环动画回调',
    );
  });

  testWidgets('UI-B4-106 AC7 · BootShell 独立文件可单独 pump（不 import main.dart）', (
    tester,
  ) async {
    // 本测试文件即证据：仅 import boot_shell.dart 与本地化 delegate，
    // 泵入最小 MaterialApp 即可渲染，不触碰 main.dart。
    await _pumpShell(tester, stage: BootStage.generic);
    expect(find.byType(BootShell), findsOneWidget);
  });

  testWidgets('UI-B4-107 · 结构性回归锁：BootShellHost（生产启动壳宿主）下 BootShell 正常渲染不抛', (
    tester,
  ) async {
    // 返工口径：测试与生产走同一宿主——直接 pump main.dart `_BootRoot` 所用
    // 的 BootShellHost（单源持有 delegates/supportedLocales/主题）。宿主漏配
    // delegates 时本用例与真机同红（BootShell 消费 AppLocalizations.of，无
    // delegates 返 null → build 抛错）；不 import main.dart（MUST NOT #7）。
    await tester.pumpWidget(
      const BootShellHost(stage: BootStage.generic),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(BootShell), findsOneWidget);
    expect(find.text('DbMaster'), findsOneWidget);
    expect(find.text('Preparing your workspace…'), findsOneWidget);
    expect(find.text('Startup problem'), findsNothing);
  });

  testWidgets('UI35-151 AC1 · 骨架侧栏宽跟随注入的 sidebarWidth；默认回落 LayoutPreferencesService.defaultSidebarWidth', (
    tester,
  ) async {
    // 注入 300（非 260/280 任意写死值）：骨架侧栏宽度应跟随。
    await _pumpShellWithSidebar(tester, sidebarWidth: 300);
    final sidebar = find.byKey(const ValueKey('uirvBootSidebarSkeleton'));
    expect(sidebar, findsOneWidget);
    expect(
      tester.getSize(sidebar).width,
      300,
      reason: '骨架侧栏宽应等于注入的 sidebarWidth（宽度真相 = LayoutPreferencesProvider.sidebarWidth）',
    );

    // 未注入时回落服务层默认宽（provider 未加载完成的回落路径）。
    await _pumpShell(tester, stage: BootStage.generic);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('uirvBootSidebarSkeleton')))
          .width,
      LayoutPreferencesService.defaultSidebarWidth,
    );
  });

  testWidgets('UI35-152 AC2 · 底部 24px 状态栏骨架：3 个 6px 色块', (tester) async {
    await _pumpShell(tester, stage: BootStage.generic);
    final strip = find.byKey(const ValueKey('uirvBootStatusbarSkeleton'));
    expect(strip, findsOneWidget);
    expect(
      tester.getSize(strip).height,
      AppDesignSystem.statusHeight,
      reason: '状态栏骨架高度 = statusHeight token（24）',
    );
    final containerFinder = find.descendant(
      of: strip,
      matching: find.byType(Container),
    );
    final sixPxBlocks = containerFinder
        .evaluate()
        .map((e) => e.size)
        .whereType<Size>()
        .where((s) => s.height == 6)
        .toList();
    expect(sixPxBlocks.length, 3, reason: '状态栏骨架应为 3 个 6px 高色块');
  });

  testWidgets('UI35-153 AC3 · 中心状态区位于主区中心：x = sidebarWidth + (W − sidebarWidth)/2', (
    tester,
  ) async {
    // 固定窗口 800×600（默认测试面），注入 sidebarWidth=300 → 期望中心 x = 550。
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpShellWithSidebar(tester, sidebarWidth: 300);

    final region = find.byKey(const ValueKey('uirvBootStatusRegion'));
    expect(region, findsOneWidget);
    final centerX = tester.getCenter(region).dx;
    const windowWidth = 800.0;
    expect(
      centerX,
      300 + (windowWidth - 300) / 2,
      reason: '状态区应与 400 宽欢迎卡同坐标（主区中心），不再用窗口 Center',
    );
  });
}

/// 注入侧栏宽的宿主（BootShell 直接构造；生产路径经 BootShellHost 解析
/// LayoutPreferencesProvider 后透传同参）。
Future<void> _pumpShellWithSidebar(
  WidgetTester tester, {
  required double sidebarWidth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(),
        child: BootShell(sidebarWidth: sidebarWidth),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
