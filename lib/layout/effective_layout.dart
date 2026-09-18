import '../theme/design_system.dart';

/// 面板降级计算结果（显示态，**不改持久态**）。
///
/// 当 sidebar + AI + 执行中心同时占位导致 editor 可用宽度 <
/// [AppDesignSystem.minWorkspaceComfortWidth] 时，逐级把面板切换为占位更小的
/// 形态（纯渲染层覆盖）。窗口放大后自然回退到持久态——无需恢复逻辑。
///
/// 降级形态全部复用现有组件：
/// - sidebar → collapsed icon rail（[AppDesignSystem.sidebarCollapsedWidth]）
/// - AI → `AiPanelOverlay` 浮层（可缩放，非真全屏）
/// - 执行中心 → floating overlay（已有 `!isPinned` 态）
class EffectiveLayout {
  const EffectiveLayout({
    required this.collapseSidebar,
    required this.aiAsOverlay,
    required this.ecAsFloating,
  });

  /// sidebar 显示为 collapsed（icon rail）。
  final bool collapseSidebar;

  /// AI 面板显示为 `AiPanelOverlay` 浮层（非 docked sidebar）。
  final bool aiAsOverlay;

  /// 执行中心显示为 floating overlay（非 docked）。
  final bool ecAsFloating;

  @override
  String toString() =>
      'EffectiveLayout(collapseSidebar=$collapseSidebar, aiAsOverlay=$aiAsOverlay, ecAsFloating=$ecAsFloating)';
}

/// 计算面板降级后的显示态。纯函数——不依赖 BuildContext / Provider，可单测。
///
/// 降级优先级（让位顺序，从低到高）：
/// 1. 折叠 sidebar
/// 2. AI 改浮层
/// 3. 执行中心改浮层
///
/// 每级降级后重新计算 editor 可用宽度，达到 [AppDesignSystem.minWorkspaceComfortWidth]
/// 即停。输入的 [sidebarWidth] / [aiPanelWidth] / [ecWidth] 应为持久态实际值（已 clamp）。
EffectiveLayout computeEffectiveLayout({
  required double totalWidth,
  required double sidebarWidth,
  required double aiPanelWidth,
  required double ecWidth,
  required bool sidebarCollapsed,
  required bool aiOpen,
  required bool aiFullscreen,
  required bool ecOpen,
  required bool ecPinned,
}) {
  // 初始 effective 显示态 = 持久态映射
  var collapseSidebar = sidebarCollapsed;
  var aiAsOverlay = aiFullscreen;
  var ecAsFloating = !ecPinned;

  double workspaceWidth() {
    final sidebarW = collapseSidebar
        ? AppDesignSystem.sidebarCollapsedWidth
        : sidebarWidth;
    final aiW = (aiOpen && !aiAsOverlay) ? aiPanelWidth : 0.0;
    final ecW = (ecOpen && !ecAsFloating) ? ecWidth : 0.0;
    return totalWidth - sidebarW - aiW - ecW;
  }

  const min = AppDesignSystem.minWorkspaceComfortWidth;

  EffectiveLayout snapshot() => EffectiveLayout(
        collapseSidebar: collapseSidebar,
        aiAsOverlay: aiAsOverlay,
        ecAsFloating: ecAsFloating,
      );

  // 宽度充足——无需降级。
  if (workspaceWidth() >= min) return snapshot();

  // 第一级：折叠 sidebar（240 → 44）。
  if (!collapseSidebar) collapseSidebar = true;
  if (workspaceWidth() >= min) return snapshot();

  // 第二级：AI 改浮层（docked sidebar 宽度 → 0）。
  if (aiOpen && !aiAsOverlay) aiAsOverlay = true;
  if (workspaceWidth() >= min) return snapshot();

  // 第三级：执行中心改浮层（docked 宽度 → 0）。
  if (ecOpen && !ecAsFloating) ecAsFloating = true;
  return snapshot();
}
