import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/layout_preferences_provider.dart';
import '../../molecules/toolbar_button.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

/// QueryEditorToolbar - 查询编辑器工具栏
///
/// 布局（C21 M3 换装，原型 editor-workspace.html）：
/// ┌─ 执行 ─┬─ 文件 ─┬─ 工具 ───────────┬─ 事务 ─┬─ 分栏 ┤…┌─ 上下文芯片 ─────┐
/// │ ▶ 运行│ 💾     │ code 🧹 📊 🛡️ 🔒  │  TX    │   ⊞   ││ conn db LIMIT ⏱ ⌘K │
/// └────────┴────────┴─────────────────┴────────┴────────┘└────────────────────┘
/// 主按钮位状态化：空闲 = filled「运行」；执行中 = danger「停止」（取消能力
/// 保留于同一位）。只读连接显示 lock 状态 chip（非交互）。
///
/// 上下文芯片（C21 v1 边界项收口）位于工具栏右端——连接/库选择器从左侧
/// 迁来 + LIMIT/超时芯片，取代 BreadcrumbBar 的连接/库显示（消解双显，
/// 原型无面包屑）；命令面板入口随面包屑退役一并迁入（⌘K）。
///
/// 组间用 12px 间距分隔（与 AppHeader 统一，P0-2）。
/// 窄窗口自适应：左/中组（执行/文件/工具/事务）包在水平滚动的
/// SingleChildScrollView 里，右侧芯片集群 + 分栏按钮固定右端不被裁掉——
/// 最小窗口（main.dart 800×600）下工具栏内容宽于可用宽度时靠滚动兜底。
class QueryEditorToolbar extends StatelessWidget {
  final bool isExecuting;

  /// 多语句执行进度（如 "12/402"）；null = 单语句/未执行。ValueNotifier
  /// 局部监听——逐条推进时不重建工具栏其余部分与编辑器。
  final ValueListenable<String?>? execProgress;
  final bool isSaving;
  final SplitMode splitMode;
  final bool isInTransaction;
  final bool supportsTransaction;
  final bool isReadOnly;
  final bool supportsFormat;

  final VoidCallback onExecute;
  final VoidCallback onStop;
  final VoidCallback onFormat;
  final VoidCallback onSave;
  final VoidCallback? onSaveToTeamLibrary;
  final VoidCallback? onSubmitForApproval;
  final VoidCallback? onSmartImport;
  final VoidCallback? onShowPIISettings;
  final VoidCallback? onQueryPlan;
  final VoidCallback? onBeginTransaction;
  final VoidCallback? onCommitTransaction;
  final VoidCallback? onRollbackTransaction;

  final VoidCallback onSplitHorizontal;
  final VoidCallback onSplitVertical;
  final VoidCallback onCloseSplit;

  final Widget connectionSelector;
  final Widget databaseSelector;

  /// LIMIT 芯片（连接级覆盖选择器，C21 M3）。
  final Widget limitSelector;

  /// 超时芯片（连接级覆盖选择器，C21 M3）。
  final Widget timeoutSelector;

  /// 命令面板入口按钮（随 BreadcrumbBar 退役从面包屑迁入，C21 M3）。
  final Widget commandPaletteButton;

  const QueryEditorToolbar({
    super.key,
    required this.isExecuting,
    this.execProgress,
    required this.isSaving,
    required this.splitMode,
    this.isInTransaction = false,
    this.supportsTransaction = false,
    this.isReadOnly = false,
    this.supportsFormat = false,
    required this.onExecute,
    required this.onStop,
    required this.onFormat,
    required this.onSave,
    this.onSaveToTeamLibrary,
    this.onSubmitForApproval,
    this.onSmartImport,
    this.onShowPIISettings,
    this.onQueryPlan,
    this.onBeginTransaction,
    this.onCommitTransaction,
    this.onRollbackTransaction,
    required this.onSplitHorizontal,
    required this.onSplitVertical,
    required this.onCloseSplit,
    required this.connectionSelector,
    required this.databaseSelector,
    required this.limitSelector,
    required this.timeoutSelector,
    required this.commandPaletteButton,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isWorkspaceMode = connectionSelector is SizedBox;

    return Container(
      height: AppDesignSystem.toolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      color: context.themeColors.bgSecondary,
      child: Row(
        children: [
          // ═══ 左/中组：执行/文件/工具/事务，窄窗口下水平滚动兜底 ═══
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // ═══ 组 1: 执行 / 停止（C21：单主按钮位，空闲=运行 filled、
                  // 执行中=停止 danger——原型 editor-workspace/executing 主按钮
                  // 状态化，取消能力保留于同一位）═══
                  isExecuting
                      ? ToolbarButton(
                          icon: LucideIcons.square,
                          label: l10n.toolbarStop,
                          variant: ToolbarButtonVariant.danger,
                          onPressed: onStop,
                          tooltip: l10n.toolbarStop,
                        )
                      : ToolbarButton(
                          icon: LucideIcons.play,
                          label: l10n.toolbarExecute,
                          variant: ToolbarButtonVariant.filled,
                          onPressed: onExecute,
                          tooltip: l10n.shortcutExecuteQuery,
                        ),
                  if (isExecuting && execProgress != null)
                    ValueListenableBuilder<String?>(
                      valueListenable: execProgress!,
                      builder: (context, label, _) {
                        if (label == null || label.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(
                            left: AppDesignSystem.space2,
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: AppDesignSystem.monoFontFamily,
                              fontFamilyFallback:
                                  AppDesignSystem.monoFontFamilyFallback,
                              color: context.themeColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(width: AppDesignSystem.space3),

                  // ═══ 组 3: 文件操作 ═══
                  ToolbarButton(
                    icon: LucideIcons.save,
                    color: context.themeColors.textSecondary,
                    onPressed: isSaving ? null : onSave,
                    isLoading: isSaving,
                    tooltip: l10n.shortcutSaveQuery,
                  ),
                  if (onSaveToTeamLibrary != null)
                    ToolbarButton(
                      icon: LucideIcons.cloudUpload,
                      color: context.themeColors.accentBlue,
                      onPressed: onSaveToTeamLibrary!,
                      tooltip: l10n.saveToTeamTooltip,
                    ),
                  if (onSubmitForApproval != null)
                    ToolbarButton(
                      icon: LucideIcons.clipboardCheck,
                      color: context.themeColors.accentBlue,
                      onPressed: onSubmitForApproval!,
                      tooltip: l10n.submitApprovalTooltip,
                    ),
                  const SizedBox(width: AppDesignSystem.space3),

                  // ═══ 组 4: 工具按钮 ═══
                  if (supportsFormat)
                    ToolbarButton(
                      icon: LucideIcons.code,
                      color: context.themeColors.info,
                      onPressed: onFormat,
                      tooltip: l10n.shortcutFormatSql,
                    ),
                  if (onSmartImport != null)
                    ToolbarButton(
                      icon: LucideIcons.fileDown,
                      label: l10n.smartImportTitle,
                      color: context.themeColors.accentBlue,
                      onPressed: onSmartImport!,
                      tooltip: l10n.smartImportTitle,
                    ),
                  if (onQueryPlan != null)
                    ToolbarButton(
                      icon: LucideIcons.network,
                      label: AppLocalizations.of(context)!.toolbarQueryPlan,
                      color: context.themeColors.accentPurple,
                      onPressed: onQueryPlan!,
                      tooltip: AppLocalizations.of(context)!.toolbarQueryPlan,
                    ),
                  if (onShowPIISettings != null)
                    ToolbarButton(
                      icon: LucideIcons.shield,
                      label: AppLocalizations.of(context)!.toolbarPiiMasking,
                      color: context.themeColors.accentPurple,
                      onPressed: onShowPIISettings!,
                      tooltip: AppLocalizations.of(context)!.toolbarPiiMasking,
                    ),
                  if (supportsTransaction && !isReadOnly) ...[
                    const SizedBox(width: 4),
                    _TransactionButtons(
                      isInTransaction: isInTransaction,
                      onBegin: onBeginTransaction,
                      onCommit: onCommitTransaction,
                      onRollback: onRollbackTransaction,
                    ),
                  ],

                  // ═══ 只读状态 chip（C21：连接 readOnly 时的视觉提示，
                  // 原型 editor-workspace「只读」按钮位；非交互——readOnly 是
                  // 连接属性，切换入口在连接编辑表单）═══
                  if (isReadOnly) ...[
                    const SizedBox(width: AppDesignSystem.space2),
                    _ReadOnlyChip(label: l10n.toolbarReadOnlyChip),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(width: AppDesignSystem.space2),

          // ═══ 组 5: 上下文芯片集群（C21 M3，原型右端；连接/库选择器从
          // 左侧迁来消解与 BreadcrumbBar 的双显——面包屑已退役，命令面板
          // 入口一并迁入）═══
          if (!isWorkspaceMode) ...[
            connectionSelector,
            const SizedBox(width: AppDesignSystem.space1),
            databaseSelector,
            const SizedBox(width: AppDesignSystem.space1),
            limitSelector,
            const SizedBox(width: AppDesignSystem.space1),
            timeoutSelector,
            const SizedBox(width: AppDesignSystem.space2),
          ],
          commandPaletteButton,
          const SizedBox(width: AppDesignSystem.space2),

          // ═══ 组 6: 分栏（合并了 Orientation Toggle）═══
          _buildSplitButton(context),
        ],
      ),
    );
  }

  Widget _buildSplitButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<LayoutPreferencesProvider>(
      builder: (context, layout, _) {
        final isVertical =
            layout.editorResultsOrientation ==
            EditorResultsOrientation.vertical;
        return PopupMenuButton<SplitMode>(
          tooltip: l10n.splitButton,
          offset: const Offset(0, 36),
          color: context.themeColors.bgTertiary,
          icon: Icon(
            isVertical ? LucideIcons.arrowRightLeft : LucideIcons.arrowUpDown,
            size: 18,
            color: splitMode != SplitMode.none
                ? context.themeColors.accentBlue
                : context.themeColors.textSecondary,
          ),
          onSelected: (mode) {
            switch (mode) {
              case SplitMode.horizontal:
                onSplitHorizontal();
              case SplitMode.vertical:
                onSplitVertical();
              case SplitMode.none:
                onCloseSplit();
              case SplitMode.toggle:
                layout.toggleEditorResultsOrientation();
            }
          },
          itemBuilder: (context) => [
            CompactPopupMenuItem(
              value: SplitMode.horizontal,
              child: _SplitMenuItem(
                icon: LucideIcons.columns2,
                label: l10n.horizontalSplit,
                isSelected: splitMode == SplitMode.horizontal,
              ),
            ),
            CompactPopupMenuItem(
              value: SplitMode.vertical,
              child: _SplitMenuItem(
                icon: LucideIcons.columns2,
                label: l10n.verticalSplit,
                isSelected: splitMode == SplitMode.vertical,
              ),
            ),
            const PopupMenuDivider(height: 6),
            CompactPopupMenuItem(
              value: SplitMode.toggle,
              child: _SplitMenuItem(
                icon: isVertical
                    ? LucideIcons.arrowRightLeft
                    : LucideIcons.arrowUpDown,
                label: isVertical
                    ? 'Switch to side-by-side'
                    : 'Switch to stacked',
              ),
            ),
            if (splitMode != SplitMode.none) ...[
              const PopupMenuDivider(height: 6),
              CompactPopupMenuItem(
                value: SplitMode.none,
                child: _SplitMenuItem(
                  icon: LucideIcons.x,
                  label: l10n.toolbarCloseSplit,
                  color: context.themeColors.error,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SplitMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color? color;

  const _SplitMenuItem({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ??
        (isSelected
            ? context.themeColors.accentBlue
            : context.themeColors.textSecondary);

    return Row(
      children: [
        Icon(icon, size: 16, color: effectiveColor),
        const SizedBox(width: AppDesignSystem.space2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected && color == null
                ? context.themeColors.accentBlue
                : context.themeColors.textPrimary,
          ),
        ),
        if (isSelected && color == null) ...[
          const Spacer(),
          Icon(
            LucideIcons.check,
            size: 14,
            color: context.themeColors.accentBlue,
          ),
        ],
      ],
    );
  }
}

enum SplitMode { none, horizontal, vertical, toggle }

/// 只读状态 chip —— 原型 editor-workspace「只读」位（lock + 文案，
/// text-tertiary 弱化样式，非交互）。
class _ReadOnlyChip extends StatelessWidget {
  final String label;

  const _ReadOnlyChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.lock,
            size: 14,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            label,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              color: context.themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 事务控制按钮组
class _TransactionButtons extends StatelessWidget {
  final bool isInTransaction;
  final VoidCallback? onBegin;
  final VoidCallback? onCommit;
  final VoidCallback? onRollback;

  const _TransactionButtons({
    required this.isInTransaction,
    this.onBegin,
    this.onCommit,
    this.onRollback,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space1),
      decoration: BoxDecoration(
        color: isInTransaction
            ? context.themeColors.warning.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: isInTransaction
            ? Border.all(
                color: context.themeColors.warning.withValues(alpha: 0.3),
                width: 1,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isInTransaction)
            ToolbarButton(
              icon: LucideIcons.circlePlay,
              color: context.themeColors.success,
              onPressed: onBegin,
              tooltip: AppLocalizations.of(context)!.toolbarBeginTransaction,
            )
          else ...[
            ToolbarButton(
              icon: LucideIcons.circleCheckBig,
              color: context.themeColors.success,
              onPressed: onCommit,
              tooltip: AppLocalizations.of(context)!.toolbarCommit,
            ),
            ToolbarButton(
              icon: LucideIcons.circleX,
              color: context.themeColors.error,
              onPressed: onRollback,
              tooltip: AppLocalizations.of(context)!.toolbarRollback,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: context.themeColors.warning,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              'TX',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.themeColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
