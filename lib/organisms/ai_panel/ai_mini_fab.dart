// ============================================================================
// DbMaster AI Mini FAB — AI 面板迷你浮动按钮（固定位置）
// ============================================================================
//
// 从 home_screen.dart 拆分而来。2026-06 简化：
//   - 去掉拖拽移动 → 固定右下角（right: 24, bottom: 48）
//
// 在 AI 面板关闭时显示，点击可打开全屏浮层模式。
// ============================================================================

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// AI 面板关闭时显示的迷你浮动按钮（固定右下角）
class AiMiniFab extends StatelessWidget {
  final VoidCallback onTap;

  const AiMiniFab({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeColors = context.themeColors;

    return Positioned(
      right: AppDesignSystem.aiFabRightOffset,
      bottom: AppDesignSystem.aiFabBottomOffset,
      child: Tooltip(
        message: AppLocalizations.of(context)!.aiAssistantOpenTooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: AppDesignSystem.aiFabSize,
              height: AppDesignSystem.aiFabSize,
              decoration: BoxDecoration(
                color: themeColors.bgSecondary.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: themeColors.accentPurple.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: -5,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: AppDesignSystem.aiFabSize,
                    height: AppDesignSystem.aiFabSize,
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.wandSparkles,
                      size: 24,
                      color: themeColors.accentPurple,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
