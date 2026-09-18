// SidebarWidget（plan §3.4 拆分后）— 纯 UI 组装壳。
//
// 状态与行为已迁出：
// - 展开状态 / 键盘导航 / type-to-select / 懒加载 → sidebar_controller.dart
// - 可见节点 key 构建 → sidebar_visible_nodes.dart
// - 搜索框 UI → sidebar_search_field.dart
// 本文件只保留：controller 接线（创建/监听/释放）、折叠态与展开态布局、
// 需要 BuildContext 的对话框路由。
// 历史标记（T004~T020 / FR-007 / US1-4 / F-37 / plan §3.2/§3.5）随代码
// 迁移到对应文件。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../atoms/app_transitions.dart';
import '../l10n/app_localizations.dart';
import '../models/database_models.dart' show DatabaseType;
import '../providers/app_provider.dart';
import '../services/stored_procedure_service.dart';
import '../services/trigger_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive_helper.dart';
import 'connection/connection_dialog.dart';
import 'connection/er_diagram_dialog.dart';
import 'connection/password_prompt_dialog.dart';
import 'connection/settings_dialog.dart';
import 'dialogs/stored_procedures_dialog.dart';
import 'dialogs/triggers_dialog.dart';
import 'sidebar/capability/sidebar_capability_menu.dart';
import 'sidebar/mysql_process_panel.dart';
import 'sidebar/sidebar_connection_selector.dart';
import 'sidebar/sidebar_controller.dart';
import 'sidebar/sidebar_footer.dart';
import 'sidebar/sidebar_header.dart';
import 'sidebar/sidebar_search_field.dart';
import 'sidebar/sidebar_tree.dart';

class SidebarWidget extends StatefulWidget {
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const SidebarWidget({
    super.key,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  late final SidebarController _controller;
  final ScrollController _sidebarScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = SidebarController(
      appProvider: context.read<AppProvider>(),
      // 密码弹窗是控制器中唯一需要 BuildContext 的副作用，经回调注入
      // （闭包捕获 State.context，State 存活期内有效）。
      promptPassword: (server) =>
          PasswordPromptDialog.ensurePassword(context, server),
    );
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.loadExpandedState();
      _controller.subscribeToConnectionEvents();
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  double get _sidebarWidth {
    if (widget.isCollapsed) return AppDesignSystem.sidebarCollapsedWidth;
    return ResponsiveHelper.getSidebarWidth(context);
  }

  @override
  Widget build(BuildContext context) {
    // T011 — prune orphaned expanded database keys after DB drops
    final provider = context.watch<AppProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.pruneOrphanedExpandedDatabases(provider);
    });

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: _sidebarWidth,
      // C22-0（原型 aside border-r）：侧栏与主区以结构线分隔。
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          right: BorderSide(color: context.themeColors.dividerColor),
        ),
      ),
      child: widget.isCollapsed
          ? _buildCollapsedSidebar()
          : _buildExpandedSidebar(),
    );
  }

  // ==================== 折叠态 ====================

  Widget _buildCollapsedSidebar() {
    return Column(
      children: [
        _buildCollapsedHeader(),
        Expanded(child: _buildCollapsedTree()),
        _buildCollapsedFooter(),
      ],
    );
  }

  Widget _buildCollapsedHeader() {
    final colors = context.themeColors;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.dividerColor)),
      ),
      child: Center(
        child: IconButton(
          icon: const Icon(LucideIcons.panelLeftOpen, size: 18),
          onPressed: widget.onToggleCollapse,
          tooltip: AppLocalizations.of(context)!.sidebarExpand,
          color: colors.textSecondary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
      ),
    );
  }

  Widget _buildCollapsedTree() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final colors = context.themeColors;
        final activeTab = provider.tab.activeTab;
        final activeId =
            activeTab?.connectionId ?? provider.sidebar.selectedConnectionId;
        if (activeId == null && provider.savedConnections.isEmpty) {
          return _buildCollapsedEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
          itemCount: provider.savedConnections.length,
          itemBuilder: (context, index) {
            final conn = provider.savedConnections[index];
            final isActive = activeId == conn.id;
            final selectedDb =
                activeTab?.databaseName ??
                provider.sidebar.selectedDatabaseName;
            final tooltipMessage = isActive && selectedDb != null
                ? '${conn.name} > $selectedDb'
                : conn.name;

            // C22-0 换装：紧凑 32px 行 + active = primaryContainer 底
            //（对齐 C21 标签条激活语义），图标保持类型品牌色。
            return Tooltip(
              message: tooltipMessage,
              preferBelow: false,
              child: InkWell(
                onTap: () => _controller.handleConnectionTap(conn),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                hoverColor: colors.bgTertiary,
                child: Container(
                  height: 32,
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1,
                    vertical: AppDesignSystem.space0_5,
                  ),
                  decoration: BoxDecoration(
                    color: isActive ? colors.primaryContainer : null,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Center(
                    // emoji→矢量图标+品牌色（F-37）
                    child: Icon(
                      conn.type.typeIcon,
                      size: 18,
                      color: colors.brandColor(conn.type),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCollapsedEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      child: IconButton(
        icon: const Icon(LucideIcons.plus, size: 22),
        onPressed: () => _showConnectionDialog(),
        tooltip: l10n.connectionNewConnection,
        color: colors.textSecondary,
      ),
    );
  }

  Widget _buildCollapsedFooter() {
    final colors = context.themeColors;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.dividerColor)),
      ),
      child: Center(
        child: IconButton(
          icon: const Icon(LucideIcons.settings, size: 18),
          onPressed: () => _showSettings(),
          tooltip: AppLocalizations.of(context)!.sidebarSettings,
          color: colors.textSecondary,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
      ),
    );
  }

  // ==================== 展开态 ====================

  Widget _buildExpandedSidebar() {
    // Use watch (not read) so async data loads trigger sidebar rebuild
    final provider = context.watch<AppProvider>();
    _controller.rebuildVisibleNodeKeys(provider);
    // 仅在侧边栏首次挂载时请求焦点，不重复抢占
    _controller.ensureInitialTreeFocus();

    return Focus(
      focusNode: _controller.treeFocusNode,
      onKeyEvent: _controller.handleTreeKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _controller.treeFocusNode.requestFocus(),
        child: Column(
          children: [
            SidebarHeader(
              onToggleCollapse: widget.onToggleCollapse ?? () {},
              isCollapsed: widget.isCollapsed,
            ),
            // C22-0 — 顶部连接选择器（当前连接名 + 地址，快速切换/连接）
            SidebarConnectionSelector(
              onConnectionTap: _controller.handleConnectionTap,
              onManageConnections: _showConnectionManager,
            ),
            // Search filter bar
            SidebarSearchField(
              controller: _controller.searchController,
              focusNode: _controller.searchFocusNode,
              onQueryChanged: (v) =>
                  _controller.updateSearchQuery(v.trim().toLowerCase()),
              hasActiveQuery: _controller.searchQuery.isNotEmpty,
              onClear: () {
                _controller.searchController.clear();
                _controller.updateSearchQuery('');
              },
            ),
            Expanded(
              flex: 2,
              child: SidebarTree(
                // 稳定 key（plan §3.5）：SidebarTree 内部已按 searchQuery 过滤，
                // 动态 key 会导致每次搜索 dispose/create 整树、丢失滚动位置。
                key: const ValueKey('sidebar_tree'),
                searchQuery: _controller.searchQuery,
                serverSearchResults: _controller.serverSearchResults,
                scrollController: _sidebarScrollController,
                expandedItems: _controller.expandedItems,
                expandedDatabases: _controller.expandedDatabases,
                expandedTables: _controller.expandedTables,
                loadingDatabases: _controller.loadingDatabases,
                loadedTableSchemas: _controller.loadedTableSchemas,
                loadedTableForeignKeys: _controller.loadedTableForeignKeys,
                loadingTableSchemas: _controller.loadingTableSchemas,
                tableRowCounts: _controller.tableRowCounts,
                onLoadTableRowCounts: _controller.loadTableRowCountsForDb,
                onToggleExpand: _controller.toggleExpand,
                onToggleDatabase: _controller.toggleDatabase,
                onToggleTable: _controller.toggleTable,
                onLoadDatabaseInfo: _controller.loadDatabaseInfo,
                onLoadTableSchema: _controller.loadTableSchema,
                onShowConnectionManager: _showConnectionManager,
                onShowSettings: _showSettings,
                onShowERDiagram: _showERDiagramDialog,
                onShowStoredProcedures: _showStoredProceduresDialog,
                onShowTriggers: _showTriggersDialog,
                onCollapseAll: _controller.collapseAll,
                rightClickedNodeKey: _controller.rightClickedNodeKey,
                selectedNodeKey: _controller.selectedNodeKey,
                onSelectNode: _controller.selectNode,
                onRightClickTargetChanged: _controller.setRightClickedNodeKey,
              ),
            ),
            // C14 — 能力菜单（分组能力目录：插件合并 + port 门控；无活动
            // 连接时自隐藏，位于树与进程面板之间）
            const SidebarCapabilityMenu(),
            // T014 — MySQL process panel (between tree and footer)
            Consumer<AppProvider>(
              builder: (ctx, provider, _) {
                final server = provider.connection.currentServer;
                if (server == null || server.type != DatabaseType.mysql) {
                  return const SizedBox.shrink();
                }
                final perfKey = '${server.id}:performance';
                if (!_controller.expandedItems.contains(perfKey)) {
                  return const SizedBox.shrink();
                }
                return MysqlProcessPanel(connectionId: server.id);
              },
            ),
            // C22-1：全局动作随 AppHeader 下掉迁入 footer（AI/主题/设置）
            SidebarFooter(onShowSettings: _showSettings),
          ],
        ), // Column
      ), // GestureDetector
    ); // Focus
  }
  // ==================== 对话框路由（需要 BuildContext，留在 widget 层） ====================

  void _showConnectionManager() {
    context.showAnimatedDialog(builder: (_) => const ConnectionManagerDialog());
  }

  void _showConnectionDialog() {
    context.showAnimatedDialog(builder: (_) => const ConnectionDialog());
  }

  void _showSettings() {
    context.showAnimatedDialog(builder: (_) => const SettingsDialog());
  }

  void _showERDiagramDialog() {
    final provider = context.read<AppProvider>();
    final activeTab = provider.tab.activeTab;
    context.showAnimatedDialog(
      builder: (_) => ERDiagramDialog(
        initialConnectionId:
            activeTab?.connectionId ?? provider.sidebar.selectedConnectionId,
        initialDatabase:
            activeTab?.databaseName ?? provider.sidebar.selectedDatabaseName,
      ),
    );
  }

  void _showStoredProceduresDialog() {
    final provider = context.read<AppProvider>();
    final activeTab = provider.tab.activeTab;
    final service = StoredProcedureService(provider.dbService);
    showDialog(
      context: context,
      builder: (_) => StoredProceduresDialog(
        service: service,
        initialDatabase:
            activeTab?.databaseName ??
            provider.sidebar.selectedDatabaseName ??
            provider.connection.currentDatabase?.name,
      ),
    );
  }

  void _showTriggersDialog() {
    final provider = context.read<AppProvider>();
    final service = TriggerService(provider.dbService);
    showDialog(
      context: context,
      builder: (_) => TriggersDialog(service: service),
    );
  }
}
