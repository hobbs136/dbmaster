//! AI 工作台查询历史抽屉共享视图（v2 先行批 A3，任务书 §6.3）。
//!
//! 双形态同源渲染（v2 §8-5）：rail「历史」页 196 窄列（[QueryHistoryListView.narrow]
//! = true）与舞台 history 单例 tab 全宽（`WorkbenchStage._buildSlot`，narrow
//! = false）同一组件——宽空间增强 = 元信息列更全（库名注记 + 分段不截断），
//! 不加 rail 没有的能力（v2 §3 双形态规则）。
//!
//! 只读消费 `AppProvider.queryHistory` facade（app_provider.dart:62）——零写
//! 路径：无任何形式的执行 / 删除 / 清空 / 改名入口（任务书 §5 纪律 6 /
//! v2 §8-11，全部留经典），条目唯一动作 = Enter / 双击 →
//! [QueryHistoryListView.onLoadIntoEditor]（rail 页与舞台槽各绑
//! `WorkbenchStageController.openEditorSlot`；AC5.5 脏槽保护在 controller 侧，
//! 本组件不感知）。单击 = 行内展开 SQL 全文预览块（上限高内滚，沿
//! sql_tool_card 内容区语法：codeBlockBg / mono 11 / SelectableText）。
//!
//! 顶行搜索框即时过滤（无防抖，历史量级 ≤500），驱动
//! `QueryHistoryProvider.searchQueryHistory`（query_history_provider.dart:217）。
//! 空态 = 图标 + 标题 + hint 三节点，搜索框**禁用不隐藏**（v2 §3 状态覆盖表
//! / §8-8）；`isLoading` 首读以 SkeletonText 形态呈现。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/query_history.dart' show QueryHistory, QueryHistorySource;
import '../../molecules/skeleton_loader.dart' show SkeletonText;
import '../../providers/app_provider.dart';
import '../../providers/query_history_provider.dart' show QueryHistoryProvider;
import '../../theme/app_colors.dart';

/// 查询历史抽屉共享视图（rail 历史页 + 舞台 history 单例 tab 双形态）。
class QueryHistoryListView extends StatefulWidget {
  const QueryHistoryListView({
    super.key,
    required this.onLoadIntoEditor,
    this.narrow = false,
  });

  /// 载入编辑器槽回调（参数 = 条目 SQL）。rail 页与舞台槽各绑
  /// `WorkbenchStageController.openEditorSlot`——本组件不感知舞台，载入
  /// 不执行（AC5.2 同源语义；AC5.5 脏槽保护在 controller 侧）。
  final void Function(String sql) onLoadIntoEditor;

  /// true = rail 196 窄列形态（元信息收窄单行 ellipsis + tooltip 兜底）；
  /// false = 舞台全宽形态（元信息分段铺开 + 库名注记，更全不截断）。
  final bool narrow;

  @override
  State<QueryHistoryListView> createState() => _QueryHistoryListViewState();
}

class _QueryHistoryListViewState extends State<QueryHistoryListView> {
  final TextEditingController _searchController = TextEditingController();

  /// 列表滚动位随舞台 IndexedStack 保活跨 tab 切换存活（keepScrollOffset，
  /// 同 SessionListView 语义）；Scrollbar 与列表共用同一实例（桌面平台
  /// thumbVisibility 要求显式 controller，否则 debug 断言）。
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: true,
  );

  String _searchQuery = '';

  /// 行内展开的条目 id（null = 全部收起；单击切换，同时只展开一条）。
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 数据源 = AppProvider facade（AppProvider 转发 queryHistory 通知，
    // context.watch 跟随重建——MUST-8）。
    final provider = context.watch<AppProvider>().queryHistory;
    final entries = provider.searchQueryHistory(_searchQuery);
    return Column(
      children: [
        _buildSearchField(
          context,
          l10n,
          hasHistory: provider.queryHistory.isNotEmpty,
        ),
        Expanded(child: _buildBody(context, provider, entries)),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 顶行搜索框（空态禁用不隐藏——状态可解释，v2 §3 状态覆盖表）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildSearchField(
    BuildContext context,
    AppLocalizations l10n, {
    required bool hasHistory,
  }) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space3,
        AppDesignSystem.space2,
        AppDesignSystem.space3,
        AppDesignSystem.space1,
      ),
      child: TextField(
        key: const ValueKey('workbench_history_search'),
        controller: _searchController,
        enabled: hasHistory,
        style: TextStyle(fontSize: AppDesignSystem.fontSizeSm, color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: l10n.workbenchHistorySearchHint,
          prefixIcon: Icon(LucideIcons.search, size: 14, color: colors.textMuted),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          isDense: true,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 内容（isLoading 首读 skeleton → 空态 → 搜索无命中 → 列表）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    QueryHistoryProvider provider,
    List<QueryHistory> entries,
  ) {
    if (provider.isLoading) return _buildSkeleton(context);
    if (provider.queryHistory.isEmpty) return _buildEmptyState(context);
    if (entries.isEmpty) return _buildNoMatch(context);
    return _buildList(context, entries);
  }

  /// 首读骨架（molecules/skeleton_loader.dart 的 SkeletonText 形态）。
  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 6; i++) ...[
            const SkeletonText(height: 12),
            const SizedBox(height: AppDesignSystem.space2),
          ],
        ],
      ),
    );
  }

  /// 空态三节点：history 32 textMuted + 标题 + hint（§8-8；无按钮）。
  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      key: const ValueKey('workbench_history_empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.history, size: 32, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.workbenchHistoryEmptyTitle,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            l10n.workbenchHistoryEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索无命中（历史非空但过滤为空）：沿舞台「No Data」空态文案；
  /// 搜索框保持可用（用户可改写检索词）。
  Widget _buildNoMatch(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      key: const ValueKey('workbench_history_no_match'),
      child: Text(
        l10n.commonNoData,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeSm,
          color: context.themeColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<QueryHistory> entries) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: false,
      thickness: 5.0,
      radius: const Radius.circular(AppDesignSystem.radiusSm),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDesignSystem.space1,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = entries[index];
                  return _QueryHistoryTile(
                    key: ValueKey('workbench_history_entry_${entry.id}'),
                    entry: entry,
                    narrow: widget.narrow,
                    expanded: _expandedId == entry.id,
                    onToggleExpanded: () => setState(() {
                      _expandedId = _expandedId == entry.id ? null : entry.id;
                    }),
                    onLoad: () => widget.onLoadIntoEditor(entry.sql),
                  );
                },
                childCount: entries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 历史条目：行 1 = agent 徽标（source==agent）+ 失败图标（error 非空）+
/// SQL 首行预览（mono 12 ellipsis + tooltip 全文）；行 2 = 元信息（相对时间 /
/// 连接名 / 影响行数 / 耗时；窄列单行收窄，宽形态分段铺开 + 库名注记）。
/// 动线：Enter / 双击 → 载入编辑器；单击 = 展开行内 SQL 全文预览块。
/// 状态语义只由图形件承载（error 徽标 12 error 色），文字恒 textPrimary /
/// textMuted（对比度红线，v1 §3.6 同源结论）。
class _QueryHistoryTile extends StatefulWidget {
  const _QueryHistoryTile({
    super.key,
    required this.entry,
    required this.narrow,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onLoad,
  });

  final QueryHistory entry;
  final bool narrow;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onLoad;

  @override
  State<_QueryHistoryTile> createState() => _QueryHistoryTileState();
}

class _QueryHistoryTileState extends State<_QueryHistoryTile> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'workbench_history_entry');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Enter（含小键盘）= 载入编辑器（主动作；无任何执行键位）。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isActivate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (isActivate) {
      widget.onLoad();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final entry = widget.entry;
    final errorText = entry.error;
    // SQL 首行预览（多语句脚本只呈现首行；全文走 tooltip / 展开块）。
    final sqlFirstLine = entry.sql.split('\n').first;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: InkWell(
        onTap: () {
          _focusNode.requestFocus();
          widget.onToggleExpanded();
        },
        onDoubleTap: widget.onLoad,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (entry.source == QueryHistorySource.agent)
                    _buildAgentBadge(context),
                  if (errorText != null) ...[
                    Tooltip(
                      message: errorText,
                      child: Icon(
                        LucideIcons.triangleAlert,
                        size: 12,
                        color: colors.error,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space1),
                  ],
                  Expanded(
                    child: Tooltip(
                      // 196 窄列截断兜底：SQL 全文 tooltip。
                      message: entry.sql,
                      child: Text(
                        sqlFirstLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppDesignSystem.fontSizeSm,
                          fontFamily: AppDesignSystem.monoFontFamily,
                          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space0_5),
              _buildMetaLine(context),
              if (widget.expanded) _buildPreviewBlock(context),
            ],
          ),
        ),
      ),
    );
  }

  /// agent 来源徽标：bot 图标 12 textMuted + tooltip（workbenchAgentSourceBadge，
  /// A1 预登记 key）——T1 落地的 agent 来源记录可辨识。
  Widget _buildAgentBadge(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(right: AppDesignSystem.space1),
      child: Tooltip(
        message: l10n.workbenchAgentSourceBadge,
        child: Icon(
          LucideIcons.bot,
          size: 12,
          color: context.themeColors.textMuted,
        ),
      ),
    );
  }

  /// 元信息行：相对时间 / 连接名 / 影响行数 / 耗时（+ 宽形态库名注记）。
  /// 影响行数消费 A1 预登记 `workbenchExecutionAffectedRows`；耗时沿经典
  /// 历史表技术读数格式（result_history_table.dart:196）。
  Widget _buildMetaLine(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final entry = widget.entry;
    final connection = entry.connectionName;
    final database = entry.database;
    final metaStyle = TextStyle(
      fontSize: AppDesignSystem.fontSizeXs,
      color: colors.textMuted,
    );
    if (widget.narrow) {
      // 196 宽收窄为单行：ellipsis + tooltip 兜底（§8-12 同源手法）。
      final text = _narrowMetaText(l10n);
      return Tooltip(
        message: text,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: metaStyle,
        ),
      );
    }
    // 宽空间增强：元信息分段铺开（含库名注记），不加 rail 没有的能力。
    return Wrap(
      spacing: AppDesignSystem.space1_5,
      children: [
        Text(_formatRelativeTime(context, entry.timestamp), style: metaStyle),
        if (connection != null && connection.isNotEmpty)
          Text(connection, style: metaStyle),
        if (database != null && database.isNotEmpty)
          Text(database, style: metaStyle),
        Text(
          l10n.workbenchExecutionAffectedRows(entry.affectedRows),
          style: metaStyle,
        ),
        Text('${entry.executionTime}ms', style: metaStyle),
      ],
    );
  }

  /// 窄列单行元信息文本（relative · connection · rows · duration）。
  String _narrowMetaText(AppLocalizations l10n) {
    final entry = widget.entry;
    final connection = entry.connectionName;
    return [
      _formatRelativeTime(context, entry.timestamp),
      if (connection != null && connection.isNotEmpty) connection,
      l10n.workbenchExecutionAffectedRows(entry.affectedRows),
      '${entry.executionTime}ms',
    ].join(' · ');
  }

  /// 展开态 SQL 全文预览块（沿 sql_tool_card 内容区语法：上限 360 内部滚动
  /// 不截断 / codeBlockBg / mono 11 / SelectableText）；tooltip = 主动作提示
  /// （Enter / 双击载入编辑器，A1 预登记 `workbenchLoadIntoEditor`）。
  Widget _buildPreviewBlock(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesignSystem.space1),
      child: Tooltip(
        message: l10n.workbenchLoadIntoEditor,
        child: ConstrainedBox(
          key: ValueKey('workbench_history_preview_${widget.entry.id}'),
          constraints: const BoxConstraints(
            maxHeight: AppDesignSystem.toolCardContentMaxHeight,
          ),
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              decoration: BoxDecoration(
                color: colors.codeBlockBg,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: SelectableText(
                widget.entry.sql,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  height: 1.4,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return l10n.aiPanelJustNow;
    if (diff.inHours < 1) return l10n.aiPanelMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.aiPanelHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.aiPanelDaysAgo(diff.inDays);
    return '${date.month}/${date.day}';
  }
}
