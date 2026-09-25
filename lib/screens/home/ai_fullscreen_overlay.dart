// ============================================================================
// z2 层（layout plan §3.1）：AI 工作台（全屏）/ 浮层
// ============================================================================
//
// 仅当 `aiPanelOpen && (aiFullscreen || effective.aiAsOverlay)` 时渲染
// [AiPanelOverlay]。effective 由本层各自重算（纯函数，便宜）。
// 重构自 home_screen.dart Stack 第 3 个内联子项。
//
// 仅订阅布局相关切片：appProvider 的 (aiOpen, aiFullscreen) +
// LayoutPreferencesProvider（宽度 / sidebarCollapsed）+ ExecutionCenterProvider
// （影响 effective）。查询执行 / 切 tab / 结果流式不重建本层。
//
// 全屏态 = AI 工作台（design-ai-workbench D2 收敛：AI 全屏 = 工作台，
// 旧「经典面板全屏」形态退役）。z2 本体改返回 Stack：
// [Offstage 常驻挂载的 AiWorkbenchShell（D4 保活）, 浮窗（分支逻辑不变）]。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../layout/effective_layout.dart';
import '../../organisms/ai_panel/ai_panel_overlay.dart';
import '../../organisms/ai_workbench/ai_workbench_shell.dart';
import '../../providers/app_provider.dart';
import '../../providers/execution_center_provider.dart';
import '../../providers/layout_preferences_provider.dart';

class AiFullscreenOverlay extends StatelessWidget {
  final BoxConstraints constraints;
  final VoidCallback onToggleFullscreen;

  const AiFullscreenOverlay({
    super.key,
    required this.constraints,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final ai = context.select<AppProvider, ({bool open, bool fs})>(
      (p) => (open: p.aiPanelOpen, fs: p.aiPanelFullscreen),
    );
    return Consumer<LayoutPreferencesProvider>(
      builder: (context, lp, _) => Consumer<ExecutionCenterProvider>(
        builder: (context, ec, _) {
          final effective = computeEffectiveLayout(
            totalWidth: constraints.maxWidth,
            sidebarWidth: lp.sidebarWidth,
            aiPanelWidth: lp.aiPanelWidth,
            ecWidth: ec.width,
            sidebarCollapsed: lp.sidebarCollapsed,
            aiOpen: ai.open,
            aiFullscreen: ai.fs,
            ecOpen: ec.isOpen,
            ecPinned: ec.isPinned,
          );

          // 浮窗模式（窗口过窄等布局降级，非全屏态）——分支逻辑不变；
          // fs 态下浮窗不出现（与改造前全屏分支早返回的互斥语义一致）。
          final overlayVisible = ai.open && effective.aiAsOverlay && !ai.fs;

          return Stack(
            children: [
              // 全屏 = 工作台真铺满工作区（覆盖侧栏/编辑器）。退出：shell
              // 顶栏退出按钮 / Ctrl+Shift+G / 命令面板。
              //
              // D4 保活：Offstage + TickerMode 常驻挂载——退出工作台仅
              // 隐藏不销毁（会话/输入草稿/滚动位跨模式存活，AC1.4）。
              //
              // ⚠ 用 SizedBox.expand（自撑满的非定位子项）而非 Positioned.fill：
              // 全屏态 z0/z1/z3 兄弟层全部 shrink 成 0×0，Stack（loose fit）
              // 自身宽度会塌成 0——Positioned.fill 只能铺满一个 0 宽的 Stack，
              // 面板实际渲染 0×N「直接消失」（2026-08-22 用户走查反馈，
              // e2e 复现见 ai_fullscreen_e2e_test.dart）。SizedBox.expand
              // 自身就是满尺寸非定位子项，把 Stack 尺寸一并撑回，不依赖
              // 兄弟层状态。
              Offstage(
                offstage: !(ai.open && ai.fs),
                child: TickerMode(
                  enabled: ai.open && ai.fs,
                  child: SizedBox.expand(
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const AiWorkbenchShell(),
                    ),
                  ),
                ),
              ),
              if (overlayVisible)
                AiPanelOverlay(
                  onClose: () => context.read<AppProvider>().toggleAiPanel(),
                  onToggleDock: onToggleFullscreen,
                ),
            ],
          );
        },
      ),
    );
  }
}
