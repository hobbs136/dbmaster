import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

/// QueryEditorStatusBar - 查询编辑器底部状态栏（C21 重写，原型
/// editor-workspace.html / editor-executing.html 底部状态条）。
///
/// 三段布局（24px）：
/// - 左：状态 —— 就绪（success ✓）/ 执行中（warning spinner + 已耗时）
/// - 中：光标 行, 列（[cursorPosition] ValueListenable 局部重建，
///   光标移动不重建编辑器）
/// - 右：UTF-8 | {语言} | {数据库类型显示名}
///
/// 执行中已耗时由 [elapsed] ValueListenable 提供（宿主 1s tick）。
class QueryEditorStatusBar extends StatelessWidget {
  /// 当前光标位置（1 基逻辑行列）。
  final ValueListenable<({int line, int column})> cursorPosition;

  final bool isExecuting;

  /// 执行中已耗时；null = 空闲。
  final ValueListenable<Duration?> elapsed;

  /// 编辑器语言标签（技术字符串：SQL / JavaScript）。
  final String languageLabel;

  /// 数据库类型显示名（DatabaseType.displayName；null = 无连接上下文）。
  final String? dbTypeLabel;

  const QueryEditorStatusBar({
    super.key,
    required this.cursorPosition,
    required this.isExecuting,
    required this.elapsed,
    required this.languageLabel,
    this.dbTypeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(top: BorderSide(color: context.themeColors.borderLight)),
      ),
      child: Row(
        children: [
          // 左：执行状态
          if (isExecuting)
            ValueListenableBuilder<Duration?>(
              valueListenable: elapsed,
              builder: (context, value, _) => Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.themeColors.warning,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  Text(
                    value == null
                        ? l10n.statusBarExecuting
                        : l10n.statusBarElapsed(_formatElapsed(value)),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.warning,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Icon(
                  LucideIcons.circleCheckBig,
                  size: 12,
                  color: context.themeColors.success,
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Text(
                  l10n.statusBarReady,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ],
            ),
          // 中：光标行列
          Expanded(
            child: Center(
              child: ValueListenableBuilder<({int line, int column})>(
                valueListenable: cursorPosition,
                builder: (context, pos, _) => Text(
                  l10n.statusBarLineCol(pos.line, pos.column),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          // 右：编码 | 语言 | 数据库类型
          Text(
            dbTypeLabel == null
                ? 'UTF-8 | $languageLabel'
                : 'UTF-8 | $languageLabel | $dbTypeLabel',
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// 原型 tabular-nums 风格：mm:ss.d（<1min 显示 0:00.0 起步）。
  static String _formatElapsed(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final tenths = (d.inMilliseconds % 1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }
}
