// ============================================================================
// z1 层（layout plan §3.1）：执行中心浮动模式 overlay
// ============================================================================
//
// 仅当 `ec.isOpen && (!ec.isPinned || effective.ecAsFloating)` 时渲染
// scrim（点按关闭）+ 右侧 [ExecutionCenterPanel]。
// 重构自 home_screen.dart Stack 第 2 个内联子项（原为 scrim + panel 两项展开）。
//
// 因单 widget 层只能返回一个子项，用 [Positioned.fill] 包裹内层 Stack，
// 使 scrim/panel 相对外层 Stack 占满同一矩形——视觉与原直接展开逐字一致。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../layout/effective_layout.dart';
import '../../organisms/execution_center/execution_center_panel.dart';
import '../../providers/app_provider.dart';
import '../../providers/execution_center_provider.dart';
import '../../providers/layout_preferences_provider.dart';

class ExecutionCenterOverlay extends StatelessWidget {
  final BoxConstraints constraints;

  const ExecutionCenterOverlay({super.key, required this.constraints});

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
          final show = ec.isOpen && (!ec.isPinned || effective.ecAsFloating);
          if (!show) return const SizedBox.shrink();
          return Positioned.fill(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: ec.close,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: ec.width,
                  child: const ExecutionCenterPanel(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
