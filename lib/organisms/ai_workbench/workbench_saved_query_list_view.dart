//! AI 工作台保存的查询抽屉共享视图（v2 先行批 A4，任务书 §6.4）。
//!
//! 双形态同源渲染（v2 §8-5）：rail「保存的查询」页 196 窄列
//! （[SavedQueryListView.narrow] = true）与舞台 savedQueries 单例 tab 全宽
//! （`WorkbenchStage._buildSlot`，narrow = false）同一组件。**本地段 only**
//! （团队查询段第二批，v2 §6-2）：数据源 = `effectiveWorkbenchContext`
//! （workbench_context_resolver.dart，与 shell/芯片同一解析入口）解析连接 →
//! 命中则 `AppProvider.savedQueriesForConnection(connectionId)`；未命中 /
//! 无上下文 → 列全部本地保存查询（`AppProvider.tab.savedQueries`）并在条目
//! 上标注连接名——载入不依赖连接（R-载入类不需要连接，v2 §2 总规则）。
//! T4 `save_saved_query` 工具写入的查询与本地同源（同一 `_savedQueries`
//! 存储），自然入列，无需特判。
//!
//! 只读消费：零写路径——无新建 / 编辑 / 删除 / 改名 / 运行入口（任务书
//! §5 纪律 6 / §6.4 禁止条款；「运行」次动作第二批，全部留经典），条目唯一
//! 动作 = Enter / 双击 / 行内「载入」图标 →
//! [SavedQueryListView.onLoadIntoEditor]（rail 页与舞台槽各绑
//! `WorkbenchStageController.openEditorSlot`；AC5.5 脏槽保护在 controller
//! 侧，本组件不感知）。载入不执行（AC5.2 同源语义）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../providers/tab_provider.dart' show QueryTab;
import '../../services/ai/workbench_context_resolver.dart';
import '../../theme/app_colors.dart';

/// 保存的查询抽屉共享视图（rail 保存的查询页 + 舞台 savedQueries 单例 tab
/// 双形态）。
class SavedQueryListView extends StatefulWidget {
  const SavedQueryListView({
    super.key,
    required this.onLoadIntoEditor,
    this.narrow = false,
  });

  /// 载入编辑器槽回调（参数 = 条目 SQL）。rail 页与舞台槽各绑
  /// `WorkbenchStageController.openEditorSlot`——本组件不感知舞台，载入
  /// 不执行（AC5.2 同源语义；AC5.5 脏槽保护在 controller 侧）。
  final void Function(String sql) onLoadIntoEditor;

  /// true = rail 196 窄列形态（注记收窄单行 ellipsis + tooltip 兜底）；
  /// false = 舞台全宽形态（注记分段铺开，更全不截断）。
  final bool narrow;

  @override
  State<SavedQueryListView> createState() => _SavedQueryListViewState();
}

class _SavedQueryListViewState extends State<SavedQueryListView> {
  /// 列表滚动位随舞台 IndexedStack 保活跨 tab 切换存活（keepScrollOffset，
  /// 同 QueryHistoryListView / SessionListView 语义）；Scrollbar 与列表共用
  /// 同一实例（桌面平台 thumbVisibility 要求显式 controller，否则 debug 断言）。
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: true,
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 数据源 = AppProvider facade（tab / aiPanel / sidebar / connection 通知
    // 均转发至 AppProvider，context.watch 跟随重建——MUST-8）。
    final provider = context.watch<AppProvider>();
    final resolved = _resolveQueries(provider);
    if (resolved.queries.isEmpty) return _buildEmptyState(context);
    return _buildList(context, provider, resolved);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 数据源（§6.4 条款 1）：上下文连接命中 → 按连接过滤；否则全量 + 连接名注记
  // ──────────────────────────────────────────────────────────────────────────

  _ResolvedSavedQueries _resolveQueries(AppProvider provider) {
    final ctx = effectiveWorkbenchContext(
      provider.aiPanel.sessionManager.currentSession,
      provider,
    );
    final connectionId = ctx.connectionId;
    if (connectionId != null && connectionId.isNotEmpty) {
      return _ResolvedSavedQueries(
        queries: provider.savedQueriesForConnection(connectionId),
        contextBound: true,
      );
    }
    return _ResolvedSavedQueries(
      queries: provider.tab.savedQueries,
      contextBound: false,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 空态（§6.4 条款 3）与列表
  // ──────────────────────────────────────────────────────────────────────────

  /// 空态三节点：bookmark 32 textMuted + 标题 + hint（A1 预登记 key）。
  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      key: const ValueKey('workbench_saved_queries_empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.bookmark, size: 32, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.workbenchSavedQueriesEmptyTitle,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            l10n.workbenchSavedQueriesEmptyHint,
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

  Widget _buildList(
    BuildContext context,
    AppProvider provider,
    _ResolvedSavedQueries resolved,
  ) {
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
                  final query = resolved.queries[index];
                  return _SavedQueryTile(
                    key: ValueKey('workbench_saved_query_entry_${query.id}'),
                    query: query,
                    narrow: widget.narrow,
                    contextBound: resolved.contextBound,
                    connectionName: resolved.contextBound
                        ? null
                        : _connectionNameOf(provider, query.connectionId),
                    onLoad: () => widget.onLoadIntoEditor(query.sql),
                  );
                },
                childCount: resolved.queries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 连接名解析：savedConnections 命中返回展示名，未命中以 id 兜底
  /// （§7.3 错误路径同 resolver 语义——不显示 null）。仅全量态注记用。
  String _connectionNameOf(AppProvider provider, String? connectionId) {
    if (connectionId == null || connectionId.isEmpty) return '';
    for (final server in provider.savedConnections) {
      if (server.id == connectionId) return server.name;
    }
    return connectionId;
  }
}

/// 数据源解析值（build 内私有）：命中上下文连接 = 按连接过滤（注记 = 库名）；
/// 未命中 = 全量平铺 + 连接名注记（任务书 §6.4 允许自决：平铺 + 注记最简）。
class _ResolvedSavedQueries {
  const _ResolvedSavedQueries({
    required this.queries,
    required this.contextBound,
  });

  final List<QueryTab> queries;

  /// true = 上下文连接命中（按连接过滤）；false = 全量（条目标注连接名）。
  final bool contextBound;
}

/// 保存查询条目：行 1 = 标题（w600 12 ellipsis + tooltip）+ 行内「载入」
/// 图标；行 2 = SQL 首行预览（mono 11 textMuted ellipsis + tooltip 全文）；
/// 行 3 = 注记（上下文命中 = 库名；全量态 = 连接名 + 库名）。
/// 动线：Enter / 双击 / 行内「载入」图标 → 载入编辑器槽。无任何执行 /
/// 数据面写手势（§5 纪律 6 / v2 §8-11）。
class _SavedQueryTile extends StatefulWidget {
  const _SavedQueryTile({
    super.key,
    required this.query,
    required this.narrow,
    required this.contextBound,
    required this.connectionName,
    required this.onLoad,
  });

  final QueryTab query;
  final bool narrow;

  /// true = 上下文连接命中（注记只呈现库名；[connectionName] 为 null）。
  final bool contextBound;

  /// 全量态的连接名注记（null = 上下文命中 / 条目无连接归属）。
  final String? connectionName;

  final VoidCallback onLoad;

  @override
  State<_SavedQueryTile> createState() => _SavedQueryTileState();
}

class _SavedQueryTileState extends State<_SavedQueryTile> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'workbench_saved_query_entry',
  );

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
    final query = widget.query;
    // SQL 首行预览（多语句脚本只呈现首行；全文走 tooltip）。
    final sqlFirstLine = query.sql.split('\n').first;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: InkWell(
        onTap: () => _focusNode.requestFocus(),
        onDoubleTap: widget.onLoad,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      // 196 窄列截断兜底：标题全文 tooltip。
                      message: query.title,
                      child: Text(
                        query.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppDesignSystem.fontSizeSm,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDesignSystem.space0_5),
                    Tooltip(
                      // 196 窄列截断兜底：SQL 全文 tooltip。
                      message: query.sql,
                      child: Text(
                        sqlFirstLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppDesignSystem.fontSizeXs,
                          fontFamily: AppDesignSystem.monoFontFamily,
                          fontFamilyFallback:
                              AppDesignSystem.monoFontFamilyFallback,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDesignSystem.space0_5),
                    _buildMetaLine(context),
                  ],
                ),
              ),
              _buildLoadButton(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 注记行：上下文命中 = 库名注记；全量态 = 连接名 + 库名（任务书 §6.4
  /// 条款 1「标注连接名」+ 条款 2「库名注记」）。无可用注记 → 不占位。
  Widget _buildMetaLine(BuildContext context) {
    final segments = _metaSegments();
    if (segments.isEmpty) return const SizedBox.shrink();
    final metaStyle = TextStyle(
      fontSize: AppDesignSystem.fontSizeXs,
      color: context.themeColors.textMuted,
    );
    if (widget.narrow) {
      // 196 宽收窄为单行：ellipsis + tooltip 兜底（§8-12 同源手法）。
      final text = segments.join(' · ');
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
    // 宽空间增强：注记分段铺开，不加 rail 没有的能力。
    return Wrap(
      spacing: AppDesignSystem.space1_5,
      children: [
        for (final segment in segments) Text(segment, style: metaStyle),
      ],
    );
  }

  List<String> _metaSegments() {
    final database = widget.query.databaseName;
    final connection = widget.connectionName;
    return [
      if (!widget.contextBound &&
          connection != null &&
          connection.isNotEmpty)
        connection,
      if (database != null && database.isNotEmpty) database,
    ];
  }

  /// 行内「载入」图标（主动作第三入口）：code 12 textMuted + tooltip
  /// （A1 预登记 `workbenchLoadIntoEditor`）。嵌套 InkWell 吸收点击，
  /// 不触发条目的双击判别（沿舞台 tab 关闭钮同款嵌套语法）。
  Widget _buildLoadButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Tooltip(
      message: l10n.workbenchLoadIntoEditor,
      child: InkWell(
        key: ValueKey('workbench_saved_query_load_${widget.query.id}'),
        onTap: widget.onLoad,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space1),
          child: Icon(LucideIcons.code, size: 12, color: colors.textMuted),
        ),
      ),
    );
  }
}
