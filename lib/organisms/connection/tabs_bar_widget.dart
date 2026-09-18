import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../providers/tab_provider.dart' show QueryTab, TabProvider;
import '../../providers/bulk_close_controller.dart' show BulkCloseDecision;
import '../../molecules/bulk_close_dialog.dart';
import '../../molecules/tab_close_confirm_dialog.dart'
    show TabCloseDecision, showTabCloseConfirmDialog;
import '../../models/database_models.dart' hide QueryTab;
import '../../l10n/app_localizations.dart';
import '../../molecules/compact_popup_menu_item.dart';

class TabsBarWidget extends StatefulWidget {
  const TabsBarWidget({super.key});

  @override
  State<TabsBarWidget> createState() => _TabsBarWidgetState();
}

class _TabsBarWidgetState extends State<TabsBarWidget> {
  final ScrollController _scrollController = ScrollController();

  /// Tab 近似宽度（min 120 / max 200，取中值 160 用于滚动定位）
  static const double _approxTabWidth = 160.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 将 [index] 位置的 Tab 滚动到可视区域内（居中呈现）
  void _scrollToIndex(int index, double viewportWidth) {
    if (!_scrollController.hasClients) return;
    final target =
        (index * _approxTabWidth - viewportWidth / AppDesignSystem.space1_5)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDesignSystem.tabBarHeight,
      // P0-3：标签栏底部 1px 结构分隔线（画在 tabBarHeight 内部，
      // 与 main_workspace 高度预留的 +1.0 像素一一对应）
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.dividerColor),
        ),
      ),
      child: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final l10n = AppLocalizations.of(context)!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              return Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: provider.tabs.length,
                      itemBuilder: (context, index) {
                        final tab = provider.tabs[index];
                        final server = tab.connectionId != null
                            ? provider.connection.savedConnections
                                  .cast<DbServer?>()
                                  .firstWhere(
                                    (c) => c?.id == tab.connectionId,
                                    orElse: () => null,
                                  )
                            : null;
                        return _TabItem(
                          title: _getDisplayTitle(
                            tab.title,
                            tab.isAutoTitle,
                            l10n,
                          ),
                          tooltip:
                              '${tab.databaseName ?? "?"}@${server?.name ?? tab.connectionId ?? "?"}',
                          isActive: index == provider.activeTabIndex,
                          isSaved: tab.isSaved,
                          isDifferentConnection:
                              tab.connectionId != provider.activeConnectionId,
                          environment: server?.environment,
                          dbType: server?.type,
                          onTap: () => provider.setActiveTab(index),
                          onClose: () async =>
                              _closeTabWithConfirm(context, provider, index),
                          onRename: () =>
                              _showRenameDialog(context, provider, index),
                          onContextMenu: (position) => _showTabContextMenu(
                            context,
                            provider,
                            index,
                            position,
                          ),
                        );
                      },
                    ),
                  ),
                  // 溢出下拉菜单（对标 VS Code "∨"），始终显示
                  if (provider.tabs.isNotEmpty)
                    _buildOverflowButton(
                      context,
                      provider,
                      l10n,
                      viewportWidth,
                    ),
                  _NewTabButton(
                    onPressed: () async => await provider.addNewTab(),
                    tooltip: l10n.tabNewTooltip,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 溢出按钮 —— 点击 ∨ 弹出全部 Tab 列表，选中后自动滚动至可见
  Widget _buildOverflowButton(
    BuildContext context,
    AppProvider provider,
    AppLocalizations l10n,
    double viewportWidth,
  ) {
    final colors = context.themeColors;

    return Tooltip(
      message: 'Open tabs',
      child: PopupMenuButton<int>(
        offset: const Offset(0, AppDesignSystem.tabBarHeight),
        // 浮层底色/描边统一走 popupMenuTheme（P1-1），不再硬编码
        onSelected: (index) {
          provider.setActiveTab(index);
          _scrollToIndex(index, viewportWidth);
        },
        itemBuilder: (_) => List.generate(provider.tabs.length, (index) {
          final tab = provider.tabs[index];
          final isActive = index == provider.activeTabIndex;
          // 例外：溢出项为 title+subtitle 双行内容，行高放宽为 40（非默认 26）
          return CompactPopupMenuItem<int>(
            value: index,
            height: 40,
            padding: EdgeInsets.zero,
            child: _OverflowMenuItem(
              title: _getDisplayTitleStatic(tab.title, tab.isAutoTitle, l10n),
              subtitle: tab.databaseName,
              isActive: isActive,
              isSaved: tab.isSaved,
              onClose: () async {
                Navigator.pop(context);
                await _closeTabWithConfirm(context, provider, index);
              },
            ),
          );
        }),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppDesignSystem.space1_5),
          height: AppDesignSystem.tabBarHeight,
          alignment: Alignment.center,
          child: Icon(
            LucideIcons.chevronsUpDown,
            size: 16,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }

  /// 静态版标题翻译
  static String _getDisplayTitleStatic(
    String title,
    bool isAutoTitle,
    AppLocalizations l10n,
  ) {
    if (!isAutoTitle) return title;
    final prefixes = [
      'Query ',
      '查询 ',
      '查詢 ',
      'Abfrage ',
      'Запрос ',
      'Interroger ',
      'Requête ',
    ];
    for (final prefix in prefixes) {
      if (title.startsWith(prefix)) {
        final suffix = title.substring(prefix.length);
        final count = int.tryParse(suffix);
        if (count != null) return l10n.tabNewQueryTitle(count);
        return l10n.queryTable(suffix);
      }
    }
    for (final prefix in ['查询', '查詢']) {
      if (title.startsWith(prefix)) {
        final suffix = title.substring(prefix.length);
        final count = int.tryParse(suffix);
        if (count != null) return l10n.tabNewQueryTitle(count);
        return l10n.queryTable(suffix);
      }
    }
    return title;
  }

  String _getDisplayTitle(
    String title,
    bool isAutoTitle,
    AppLocalizations l10n,
  ) => _getDisplayTitleStatic(title, isAutoTitle, l10n);

  static void _showRenameDialog(
    BuildContext context,
    AppProvider provider,
    int index,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: provider.tabs[index].title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          l10n.tabRenameTitle,
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: context.themeColors.textPrimary),
          decoration: InputDecoration(
            hintText: l10n.tabRenameHint,
            hintStyle: TextStyle(color: context.themeColors.textMuted),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.renameTab(index, controller.text);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  static Future<void> _closeTabWithConfirm(
    BuildContext context,
    AppProvider provider,
    int index,
  ) async {
    final tab = provider.tabs[index];
    if (!TabProvider.isTabUnsaved(tab)) {
      await provider.closeTab(index);
      return;
    }

    // 单 Tab 关闭用单 Tab 语义弹框；批量关闭（所有/其他/右侧）才用批量弹框。
    final l10n = AppLocalizations.of(context)!;
    final decision = await showTabCloseConfirmDialog(
      context,
      tabTitle: _getDisplayTitleStatic(tab.title, tab.isAutoTitle, l10n),
    );
    if (!context.mounted || decision == null) return;

    switch (decision) {
      case TabCloseDecision.save:
        await _saveAndCloseTab(context, provider, tab);
      case TabCloseDecision.discard:
        await _forceCloseTabById(provider, tab.id);
    }
  }

  /// 保存单个 Tab（必要时先弹 Save As 命名），保存成功后关闭；失败或取消则保持打开。
  static Future<void> _saveAndCloseTab(
    BuildContext context,
    AppProvider provider,
    QueryTab tab,
  ) async {
    var tabToSave = tab;
    if (_tabNeedsSaveAsTitle(tabToSave)) {
      final newTitle = await _promptForSaveAsTitle(context, tabToSave.title);
      if (!context.mounted) return;
      if (newTitle == null || newTitle.trim().isEmpty) {
        // User cancelled the save-as prompt; keep the tab open.
        return;
      }
      _renameTabById(provider, tabToSave.id, newTitle.trim());
      tabToSave = provider.tabs.firstWhere((t) => t.id == tabToSave.id);
    }

    final saved = await provider.saveQuery(tabToSave);
    if (saved) {
      await _forceCloseTabById(provider, tabToSave.id);
    }
  }

  static Future<void> _applyBulkCloseResult(
    BuildContext context,
    AppProvider provider,
    BulkCloseResult result,
  ) async {
    if (!result.confirmed) return;

    final tabsToSave = <QueryTab>[];
    final tabsToDiscard = <QueryTab>[];

    for (final entry in result.decisions.entries) {
      QueryTab? matchedTab;
      for (final tab in provider.tabs) {
        if (tab.id == entry.key) {
          matchedTab = tab;
          break;
        }
      }
      if (matchedTab == null) continue;

      switch (entry.value) {
        case BulkCloseDecision.save:
          tabsToSave.add(matchedTab);
        case BulkCloseDecision.discard:
          tabsToDiscard.add(matchedTab);
        case BulkCloseDecision.pending:
          break;
      }
    }

    // Save tabs first; closing happens after each successful save.
    for (final tab in tabsToSave) {
      if (!context.mounted) return;
      await _saveAndCloseTab(context, provider, tab);
    }

    // Close discarded tabs from highest index to lowest to keep indices valid.
    final discardIndices = tabsToDiscard
        .map((tab) => provider.tabs.indexOf(tab))
        .where((index) => index >= 0)
        .toList();
    discardIndices.sort((a, b) => b.compareTo(a));
    for (final index in discardIndices) {
      await provider.forceCloseTab(index);
    }
  }

  static Future<void> _forceCloseTabById(
    AppProvider provider,
    String tabId,
  ) async {
    final index = provider.tabs.indexWhere((tab) => tab.id == tabId);
    if (index >= 0) {
      await provider.forceCloseTab(index);
    }
  }

  static void _renameTabById(AppProvider provider, String tabId, String title) {
    final index = provider.tabs.indexWhere((tab) => tab.id == tabId);
    if (index >= 0) {
      provider.renameTab(index, title);
    }
  }

  static bool _tabNeedsSaveAsTitle(QueryTab tab) {
    return tab.title.trim().isEmpty || tab.isAutoTitle;
  }

  static Future<String?> _promptForSaveAsTitle(
    BuildContext context,
    String currentTitle,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentTitle);
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          l10n.tabRenameTitle,
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: context.themeColors.textPrimary),
          decoration: InputDecoration(
            hintText: l10n.tabRenameHint,
            hintStyle: TextStyle(color: context.themeColors.textMuted),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
            ),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  static List<QueryTab> _unsavedTabsExcluding(
    AppProvider provider,
    Set<String> excludedIds,
  ) {
    return provider.tabs
        .where(
          (tab) =>
              !excludedIds.contains(tab.id) && TabProvider.isTabUnsaved(tab),
        )
        .toList();
  }

  void _showTabContextMenu(
    BuildContext context,
    AppProvider provider,
    int index,
    Offset position,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final tabIndex = index;
    final totalTabs = provider.tabs.length;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(value: 'rename', child: Text(l10n.tabRename)),
        CompactPopupMenuItem(value: 'close', child: Text(l10n.tabClose)),
        CompactPopupMenuItem(
          value: 'close_others',
          enabled: totalTabs > 1,
          child: Text(
            l10n.tabCloseOthers,
            style: totalTabs > 1
                ? null
                : TextStyle(color: context.themeColors.textDisabled),
          ),
        ),
        CompactPopupMenuItem(
          value: 'close_to_right',
          enabled: tabIndex < totalTabs - 1,
          child: Text(
            l10n.tabCloseToRight,
            style: tabIndex < totalTabs - 1
                ? null
                : TextStyle(color: context.themeColors.textDisabled),
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(value: 'close_all', child: Text(l10n.tabCloseAll)),
        CompactPopupMenuItem(
          value: 'duplicate',
          child: Text(l10n.tabDuplicate),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      _handleTabAction(context, provider, index, value);
    });
  }

  Future<void> _handleTabAction(
    BuildContext context,
    AppProvider provider,
    int index,
    String action,
  ) async {
    switch (action) {
      case 'rename':
        _showRenameDialog(context, provider, index);
        break;
      case 'close':
        await _closeTabWithConfirm(context, provider, index);
        break;
      case 'close_others':
        await _closeOtherTabs(context, provider, index);
        break;
      case 'close_to_right':
        await _closeTabsToRight(context, provider, index);
        break;
      case 'close_all':
        await _closeAllTabs(context, provider);
        break;
      case 'duplicate':
        _duplicateTab(context, provider, index);
        break;
    }
  }

  Future<void> _closeOtherTabs(
    BuildContext context,
    AppProvider provider,
    int keepIndex,
  ) async {
    final keptTabId = provider.tabs[keepIndex].id;
    final unsavedTabs = _unsavedTabsExcluding(provider, {keptTabId});

    if (unsavedTabs.isEmpty) {
      await _forceCloseTabsByIndex(
        provider,
        List.generate(
          provider.tabs.length,
          (i) => i,
        ).where((i) => i != keepIndex),
      );
      return;
    }

    final result = await showBulkCloseDialog(context, tabs: unsavedTabs);
    if (!context.mounted) return;
    if (!result.confirmed) return;

    await _applyBulkCloseResult(context, provider, result);

    // Close any remaining tabs that had no unsaved changes.
    final remainingToClose = provider.tabs
        .where((tab) => tab.id != keptTabId && !TabProvider.isTabUnsaved(tab))
        .map((tab) => provider.tabs.indexOf(tab))
        .where((index) => index >= 0)
        .toList();
    remainingToClose.sort((a, b) => b.compareTo(a));
    for (final index in remainingToClose) {
      await provider.forceCloseTab(index);
    }
  }

  Future<void> _closeTabsToRight(
    BuildContext context,
    AppProvider provider,
    int fromIndex,
  ) async {
    final tabsToRight = provider.tabs
        .asMap()
        .entries
        .where((entry) => entry.key > fromIndex)
        .map((entry) => entry.value)
        .toList();
    await _closeTabsWithConfirmation(context, provider, tabsToRight);
  }

  Future<void> _closeAllTabs(BuildContext context, AppProvider provider) async {
    await _closeTabsWithConfirmation(context, provider, provider.tabs);
  }

  Future<void> _closeTabsWithConfirmation(
    BuildContext context,
    AppProvider provider,
    List<QueryTab> tabsToClose,
  ) async {
    final unsavedTabs = tabsToClose.where(TabProvider.isTabUnsaved).toList();

    if (unsavedTabs.isEmpty) {
      await _forceCloseTabsByIndex(
        provider,
        tabsToClose.map((tab) => provider.tabs.indexOf(tab)),
      );
      return;
    }

    final result = await showBulkCloseDialog(context, tabs: unsavedTabs);
    if (!context.mounted) return;
    if (!result.confirmed) return;

    await _applyBulkCloseResult(context, provider, result);

    // Close any remaining tabs that had no unsaved changes.
    final savedTabs = tabsToClose
        .where((tab) => !TabProvider.isTabUnsaved(tab))
        .toList();
    await _forceCloseTabsById(provider, savedTabs.map((tab) => tab.id));
  }

  static Future<void> _forceCloseTabsByIndex(
    AppProvider provider,
    Iterable<int> indices,
  ) async {
    final sortedIndices = indices.toList();
    sortedIndices.sort((a, b) => b.compareTo(a));
    for (final index in sortedIndices) {
      if (index >= 0 && index < provider.tabs.length) {
        await provider.forceCloseTab(index);
      }
    }
  }

  static Future<void> _forceCloseTabsById(
    AppProvider provider,
    Iterable<String> tabIds,
  ) async {
    final indices = tabIds
        .map((id) => provider.tabs.indexWhere((tab) => tab.id == id))
        .where((index) => index >= 0)
        .toList();
    await _forceCloseTabsByIndex(provider, indices);
  }

  void _duplicateTab(BuildContext context, AppProvider provider, int index) {
    final l10n = AppLocalizations.of(context)!;
    final tab = provider.tabs[index];
    provider.addTab(
      tab.copyWith(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        title: '${tab.title} ${l10n.copySuffix}',
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String title;
  final String? tooltip;
  final bool isActive;
  final bool isSaved;
  final bool isDifferentConnection;
  final ConnectionEnvironment? environment;

  /// 连接的数据库类型（C21：类型色圆点，brandColor 主题感知分发）。
  final DatabaseType? dbType;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onRename;
  final void Function(Offset position) onContextMenu;

  const _TabItem({
    required this.title,
    this.tooltip,
    required this.isActive,
    required this.isSaved,
    this.isDifferentConnection = false,
    this.environment,
    this.dbType,
    required this.onTap,
    required this.onClose,
    required this.onRename,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    // C21（原型 editor-workspace）：激活 tab = primaryContainer 底 + 单行标题；
    // 跨连接非激活弱化。库名上下文由工具栏上下文芯片承载（C21 M3），tab 面不再双行。
    final textColor = isDifferentConnection && !isActive
        ? colors.textMuted
        : (isActive ? colors.textPrimary : colors.textSecondary);

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
      onTertiaryTapDown: (_) => onRename(),
      child: Tooltip(
        message: tooltip ?? title,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: AppDesignSystem.durationNormal,
            curve: AppDesignSystem.curveDefault,
            height: AppDesignSystem.tabBarHeight,
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
            padding: EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: isActive ? colors.primaryContainer : Colors.transparent,
              border: Border(
                right: BorderSide(color: colors.dividerColor),
              ),
            ),
            child: Row(
              children: [
                // 类型色圆点（8px，brandColor 暗色提亮变体自动分发）
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dbType != null
                        ? colors.brandColor(dbType!)
                        : colors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeMd,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 已保存徽章（save 图标，成功色）
                if (isSaved) ...[
                  const SizedBox(width: AppDesignSystem.space1),
                  Icon(
                    LucideIcons.save,
                    size: 12,
                    color: colors.success,
                  ),
                ],
                if (environment != null) ...[
                  const SizedBox(width: AppDesignSystem.space1),
                  Tooltip(
                    message: environment!.displayName,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: environment!.badgeColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive
                              ? colors.primaryContainer
                              : colors.bgSecondary,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppDesignSystem.space1),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(
                    AppDesignSystem.radiusSm,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: isActive
                          ? colors.textSecondary
                          : colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 溢出菜单单项 —— 显示 Tab 标题、数据库名、激活态、保存状态和关闭按钮
class _OverflowMenuItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isActive;
  final bool isSaved;
  final VoidCallback onClose;

  const _OverflowMenuItem({
    required this.title,
    this.subtitle,
    required this.isActive,
    required this.isSaved,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      constraints: const BoxConstraints(minWidth: 260),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? context.themeColors.accentBlue.withValues(alpha: 0.12)
            : null,
        border: Border(
          left: BorderSide(
            color: isActive
                ? context.themeColors.accentBlue
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSaved ? LucideIcons.save : LucideIcons.filePen,
            size: 14,
            color: isSaved
                ? context.themeColors.success
                : (isActive
                      ? context.themeColors.accentBlue
                      : colors.textMuted),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: isActive
                        ? AppDesignSystem.fontWeightSemibold
                        : AppDesignSystem.fontWeightRegular,
                    color: isActive ? colors.textPrimary : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? context.themeColors.accentBlue.withValues(
                              alpha: 0.7,
                            )
                          : colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: Padding(
              padding: const EdgeInsets.all(AppDesignSystem.space1),
              child: Icon(LucideIcons.x, size: 14, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewTabButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const _NewTabButton({required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        hoverColor: context.themeColors.bgTertiary,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
          child: Icon(
            LucideIcons.plus,
            size: 18,
            color: context.themeColors.textMuted,
          ),
        ),
      ),
    );
  }
}
