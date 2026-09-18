// ============================================================================
// z0 层（layout plan §3.1）：主工作区 Row
// ============================================================================
//
// 渲染底层 Row：sidebar（折叠/展开 + resizer）+ workspace（MainWorkspace 模板）
// + 执行中心 docked（钉住模式）+ AI sidebar（docked）。AI 全屏时本层整体跳过
// （`SizedBox.shrink()`）——浮层遮住整个工作区，构建是浪费。
// 重构自 home_screen.dart Stack 第 1 个内联子项（原 Row + _buildWorkspace +
// _buildAiPanelSidebar）。
//
// 仅订阅布局相关切片：appProvider 的 (aiOpen, aiFullscreen) +
// LayoutPreferencesProvider（宽度 / sidebarCollapsed）+ ExecutionCenterProvider
// （dock 态 / 宽度）。workspace 内部的 tab/editor/results 各自订阅，不在此层。
//
// State 字段（_isResizing* / GlobalKey）从 _HomeScreenState 下沉至此——已核实
// GlobalKey 无 lib/ 内外部读取，安全。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../layout/effective_layout.dart';
import '../../molecules/resizer_widgets.dart';
import '../../organisms/ai_panel/ai_panel_widget.dart'
    show AiPanelWidget, AiPanelWidgetState;
import '../../organisms/execution_center/execution_center_panel.dart';
import '../../organisms/results/results_widget.dart' show ResultsWidgetState;
import '../../organisms/sidebar_widget.dart';
import '../../providers/app_provider.dart';
import '../../providers/execution_center_provider.dart';
import '../../providers/layout_preferences_provider.dart';
import '../../templates/main_workspace.dart';
import '../../theme/app_colors.dart';

class MainWorkspaceLayer extends StatefulWidget {
  final BoxConstraints constraints;
  final VoidCallback onToggleSidebar;
  final VoidCallback onShowConnectionDialog;
  final VoidCallback onShowConnectionManager;
  final VoidCallback onOpenSqliteFile;
  // 命令面板入口（C22-1：经 MainWorkspace 透传给 BreadcrumbBar）
  final VoidCallback onCommandPalette;

  const MainWorkspaceLayer({
    super.key,
    required this.constraints,
    required this.onToggleSidebar,
    required this.onShowConnectionDialog,
    required this.onShowConnectionManager,
    required this.onOpenSqliteFile,
    required this.onCommandPalette,
  });

  @override
  State<MainWorkspaceLayer> createState() => _MainWorkspaceLayerState();
}

class _MainWorkspaceLayerState extends State<MainWorkspaceLayer> {
  final GlobalKey<ResultsWidgetState> _resultsWidgetKey =
      GlobalKey<ResultsWidgetState>();
  final GlobalKey<AiPanelWidgetState> _aiPanelKey =
      GlobalKey<AiPanelWidgetState>();
  bool _isResizingSidebar = false;
  bool _isResizingEditorResults = false;
  bool _isResizingAiPanel = false;

  void _onSidebarResizeUpdate(double delta) {
    final lp = context.read<LayoutPreferencesProvider>();
    lp.setSidebarWidth(lp.sidebarWidth + delta);
  }

  void _onAiPanelResizeUpdate(double delta) {
    final lp = context.read<LayoutPreferencesProvider>();
    lp.setAiPanelWidth(lp.aiPanelWidth - delta);
  }

  Widget _buildWorkspace() {
    return MainWorkspace(
      isResizingEditorResults: _isResizingEditorResults,
      onResizeEditorStart: () =>
          setState(() => _isResizingEditorResults = true),
      onResizeEditorEnd: () => setState(() => _isResizingEditorResults = false),
      resultsWidgetKey: _resultsWidgetKey,
      onNewConnection: widget.onShowConnectionDialog,
      onOpenConnectionManager: widget.onShowConnectionManager,
      onOpenSqliteFile: widget.onOpenSqliteFile,
      onCommandPalette: widget.onCommandPalette,
    );
  }

  @override
  Widget build(BuildContext context) {
    // §3.1：薄壳化后 z0 承担原 HomeScreen 的 AppProvider 订阅职责。z0 子树
    // （SidebarWidget / MainWorkspace 等）历史上依赖父级 watch 触发重建——
    // 它们混用 context.read（非订阅）与局部 watch/Consumer，多处结构态靠父级
    // 重建刷新。让 z0 watch 整个 AppProvider 以保持子树行为字节级不变；z1/z2/z3
    // 仍用窄 Selector 隔离（overlay / FAB 不随 workspace 活动重建——真正收益所在）。
    final appProvider = context.watch<AppProvider>();
    final aiOpen = appProvider.aiPanelOpen;
    final aiFullscreen = appProvider.aiPanelFullscreen;
    // AI 全屏时完全跳过构建——浮层遮住整个工作区，构建是浪费。
    if (aiOpen && aiFullscreen) return const SizedBox.shrink();

    return Consumer<LayoutPreferencesProvider>(
      builder: (context, lp, _) => Consumer<ExecutionCenterProvider>(
        builder: (context, ec, _) {
          final effective = computeEffectiveLayout(
            totalWidth: widget.constraints.maxWidth,
            sidebarWidth: lp.sidebarWidth,
            aiPanelWidth: lp.aiPanelWidth,
            ecWidth: ec.width,
            sidebarCollapsed: lp.sidebarCollapsed,
            aiOpen: aiOpen,
            aiFullscreen: aiFullscreen,
            ecOpen: ec.isOpen,
            ecPinned: ec.isPinned,
          );
          final shouldCollapseSidebar =
              widget.constraints.maxWidth <
                      AppDesignSystem.sidebarAutoCollapseBreakpoint ||
                  lp.sidebarCollapsed ||
                  effective.collapseSidebar;
          return Row(
            children: [
              // Sidebar
              if (shouldCollapseSidebar)
                SidebarWidget(
                  isCollapsed: true,
                  onToggleCollapse: widget.onToggleSidebar,
                )
              else
                SizedBox(
                  width: lp.sidebarWidth,
                  child: SidebarWidget(
                    isCollapsed: false,
                    onToggleCollapse: widget.onToggleSidebar,
                  ),
                ),
              if (!shouldCollapseSidebar)
                SidebarResizer(
                  isResizing: _isResizingSidebar,
                  onResizeStart: () =>
                      setState(() => _isResizingSidebar = true),
                  onResizeUpdate: _onSidebarResizeUpdate,
                  onResizeEnd: () =>
                      setState(() => _isResizingSidebar = false),
                ),
              // Workspace（Resizer 的 grab bar 已提供视觉分隔）
              Expanded(child: _buildWorkspace()),
              // 执行中心——右侧 docked（钉住模式）：钉住时 workspace 横向收缩；
              // 浮动模式则作为 z1 overlay。EC 经 shell 层注入，此处直接 const。
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: (ec.isOpen && ec.isPinned && !effective.ecAsFloating)
                    ? SizedBox(
                        width: ec.width,
                        child: const ExecutionCenterPanel(),
                      )
                    : const SizedBox.shrink(),
              ),
              // 侧边栏 AI 面板（Resizer 的 grab bar 已提供视觉分隔）
              if (aiOpen && !aiFullscreen && !effective.aiAsOverlay)
                SizedBox(
                  width: lp.aiPanelWidth,
                  child: Row(
                    children: [
                      AiPanelResizer(
                        isResizing: _isResizingAiPanel,
                        onResizeStart: () =>
                            setState(() => _isResizingAiPanel = true),
                        onResizeUpdate: _onAiPanelResizeUpdate,
                        onResizeEnd: () =>
                            setState(() => _isResizingAiPanel = false),
                      ),
                      Expanded(child: AiPanelWidget(key: _aiPanelKey)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
