// ============================================================================
// z2 层（layout plan §3.1）：AI 全屏 / 浮层
// ============================================================================
//
// 仅当 `aiPanelOpen && (aiFullscreen || effective.aiAsOverlay)` 时渲染
// [AiPanelOverlay]。effective 由本层各自重算（纯函数，便宜）。
// 重构自 home_screen.dart Stack 第 3 个内联子项。
//
// 仅订阅布局相关切片：appProvider 的 (aiOpen, aiFullscreen) +
// LayoutPreferencesProvider（宽度 / sidebarCollapsed）+ ExecutionCenterProvider
// （影响 effective）。查询执行 / 切 tab / 结果流式不重建本层。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../layout/effective_layout.dart';
import '../../organisms/ai_panel/ai_panel_overlay.dart';
import '../../organisms/ai_panel/ai_panel_widget.dart';
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

          // 全屏 = 真铺满工作区（覆盖侧栏/编辑器）。退出：面板 header
          // minimize 按钮 / Ctrl+Shift+F / footer AI 键。
          // ⚠ 用 SizedBox.expand（自撑满的非定位子项）而非 Positioned.fill：
          // 全屏态 z0/z1/z3 兄弟层全部 shrink 成 0×0，Stack（loose fit）
          // 自身宽度会塌成 0——Positioned.fill 只能铺满一个 0 宽的 Stack，
          // 面板实际渲染 0×N「直接消失」（2026-08-22 用户走查反馈，
          // e2e 复现见 ai_fullscreen_e2e_test.dart）。SizedBox.expand
          // 自身就是满尺寸非定位子项，把 Stack 尺寸一并撑回，不依赖
          // 兄弟层状态。
          if (ai.open && ai.fs) {
            return SizedBox.expand(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: const AiPanelWidget(isFullscreen: true),
              ),
            );
          }

          // 浮窗模式（窗口过窄等布局降级，非全屏态）
          if (!ai.open || !effective.aiAsOverlay) {
            return const SizedBox.shrink();
          }
          return AiPanelOverlay(
            onClose: () => context.read<AppProvider>().toggleAiPanel(),
            onToggleDock: onToggleFullscreen,
          );
        },
      ),
    );
  }
}
