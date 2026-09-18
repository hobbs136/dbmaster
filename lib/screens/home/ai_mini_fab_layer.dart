// ============================================================================
// z3 层（layout plan §3.1）：AI 面板关闭时显示的右下角迷你 FAB
// ============================================================================
//
// 独立 layer，仅订阅 [AppProvider.aiPanelOpen] 一个 bool——AI 开/关之外的
// 状态变化（查询执行、切 tab、结果流式）不会重建本层。
// 重构自 home_screen.dart Stack 第 4 个内联子项（原 AiMiniFab 直接展开）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../organisms/ai_panel/ai_mini_fab.dart';
import '../../providers/app_provider.dart';

class AiMiniFabLayer extends StatelessWidget {
  const AiMiniFabLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final aiOpen = context.select<AppProvider, bool>((p) => p.aiPanelOpen);
    if (aiOpen) return const SizedBox.shrink();
    final appProvider = context.read<AppProvider>();
    return AiMiniFab(
      onTap: () {
        appProvider.toggleAiPanel();
        appProvider.setAiPanelFullscreen(true);
      },
    );
  }
}
