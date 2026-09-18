import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/layout/effective_layout.dart';
import 'package:dbmaster/theme/design_system.dart';

/// `computeEffectiveLayout` 纯函数单测——面板降级的逻辑核心。
///
/// 数值对齐 AppDesignSystem / 默认 layout 偏好：
/// sidebarWidth=240 / collapsedWidth=44 / aiPanelWidth=360 / ecWidth=360 / min=480。
void main() {
  const sidebarWidth = AppDesignSystem.sidebarWidth; // 240
  const aiPanelWidth = AppDesignSystem.aiPanelWidth; // 360
  const ecWidth = 360.0;

  EffectiveLayout compute({
    required double totalWidth,
    bool sidebarCollapsed = false,
    bool aiOpen = false,
    bool aiFullscreen = false,
    bool ecOpen = false,
    bool ecPinned = false,
  }) =>
      computeEffectiveLayout(
        totalWidth: totalWidth,
        sidebarWidth: sidebarWidth,
        aiPanelWidth: aiPanelWidth,
        ecWidth: ecWidth,
        sidebarCollapsed: sidebarCollapsed,
        aiOpen: aiOpen,
        aiFullscreen: aiFullscreen,
        ecOpen: ecOpen,
        ecPinned: ecPinned,
      );

  group('computeEffectiveLayout', () {
    test('宽度充足——三面板全开不降级', () {
      // 240+360+360+480 = 1440；total=1500 → workspace=540≥480
      final r = compute(
        totalWidth: 1500,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isFalse);
      expect(r.aiAsOverlay, isFalse);
      expect(r.ecAsFloating, isFalse);
    });

    test('第一级：折叠 sidebar 后达标', () {
      // total=1300: 展开 workspace=340<480；折叠后 1300-44-360-360=536≥480
      final r = compute(
        totalWidth: 1300,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isTrue);
      expect(r.aiAsOverlay, isFalse);
      expect(r.ecAsFloating, isFalse);
    });

    test('第二级：折叠 sidebar 不够，AI 改浮层后达标', () {
      // total=1100: 折叠 workspace=336<480；AI 浮层后 1100-44-0-360=696≥480
      final r = compute(
        totalWidth: 1100,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isTrue);
      expect(r.aiAsOverlay, isTrue);
      expect(r.ecAsFloating, isFalse);
    });

    test('第三级：折叠+AI 浮层不够，EC 改浮层后达标', () {
      // total=700: AI 浮层 workspace=296<480；EC 浮层后 700-44-0-0=656≥480
      final r = compute(
        totalWidth: 700,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isTrue);
      expect(r.aiAsOverlay, isTrue);
      expect(r.ecAsFloating, isTrue);
    });

    test('极端窄窗：三级全降仍不够，仍返回三级全降（不再降）', () {
      // total=400: EC 浮层后 workspace=400-44=356<480，但已无更多级可降
      final r = compute(
        totalWidth: 400,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isTrue);
      expect(r.aiAsOverlay, isTrue);
      expect(r.ecAsFloating, isTrue);
    });

    test('面板关闭组合：只开 sidebar 窗口够→不降级', () {
      // total=800: workspace=800-240=560≥480
      final r = compute(totalWidth: 800);
      expect(r.collapseSidebar, isFalse);
    });

    test('面板关闭组合：sidebar+AI 窗口不够→只折叠 sidebar（AI 不必浮层）', () {
      // total=900: workspace=900-240-360=300<480；折叠后 900-44-360=496≥480
      final r = compute(totalWidth: 900, aiOpen: true);
      expect(r.collapseSidebar, isTrue);
      expect(r.aiAsOverlay, isFalse);
    });

    test('面板关闭组合：sidebar 展开 + EC，窗口够→不降级', () {
      // sidebar(240) + EC(360)，total=1200: workspace=1200-240-360=600≥480
      final r = compute(totalWidth: 1200, ecOpen: true, ecPinned: true);
      expect(r.collapseSidebar, isFalse);
      expect(r.ecAsFloating, isFalse);
    });

    test('持久态已折叠 sidebar：宽度够时不触发额外降级', () {
      // 持久 sidebarCollapsed=true，三面板全开，total=1500 → workspace=736≥480
      final r = compute(
        totalWidth: 1500,
        sidebarCollapsed: true,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isTrue); // = 持久态，非降级触发
      expect(r.aiAsOverlay, isFalse);
      expect(r.ecAsFloating, isFalse);
    });

    test('持久态 AI 全屏：aiAsOverlay 初始 true，宽度够不触发其他降级', () {
      final r = compute(
        totalWidth: 1500,
        aiOpen: true,
        aiFullscreen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.aiAsOverlay, isTrue); // = 持久态 fullscreen
      expect(r.collapseSidebar, isFalse);
      expect(r.ecAsFloating, isFalse);
    });

    test('持久态 EC 未 pin：ecAsFloating 初始 true', () {
      final r = compute(
        totalWidth: 1500,
        aiOpen: true,
        ecOpen: true,
        ecPinned: false,
      );
      expect(r.ecAsFloating, isTrue); // = 持久态 !pinned
    });

    test('边界：workspace 恰好 = min 不降级', () {
      // 三面板全开，total=240+360+360+480=1440 → workspace=480=min → 不降级
      final r = compute(
        totalWidth: 1440,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isFalse);
      expect(r.aiAsOverlay, isFalse);
      expect(r.ecAsFloating, isFalse);
    });

    test('边界：workspace = min-1 触发第一级（折叠 sidebar）', () {
      // total=1439 → workspace=479<480 → 折叠后 1439-44-360-360=675≥480
      final r = compute(
        totalWidth: 1439,
        aiOpen: true,
        ecOpen: true,
        ecPinned: true,
      );
      expect(r.collapseSidebar, isTrue);
      expect(r.aiAsOverlay, isFalse); // 折叠 sidebar 已够
    });

    test('AI 关闭时：第二级跳过 AI（无 AI 可降），直接到 EC', () {
      // total=800, EC pinned(无 AI): 展开 workspace=800-240-360=200<480；
      // 折叠 sidebar: 800-44-360=396<480；AI 关 → 跳过第二级；
      // EC 浮层: 800-44-0=756≥480
      final r = compute(totalWidth: 800, ecOpen: true, ecPinned: true);
      expect(r.collapseSidebar, isTrue);
      expect(r.aiAsOverlay, isFalse); // AI 没开，本就 false
      expect(r.ecAsFloating, isTrue);
    });
  });
}
