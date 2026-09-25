//! AI 工作台会话栏（design-ai-workbench §2.2 / §7.4 会话同源 / §8【二】布局）。
//!
//! 与经典面板「同一本账，两个投影」（D7）：数据消费
//! `aiPanel.aiConversationService`（AiSessionManager）既有只读面，
//! 新建 / 切换 / 删除 / 改名沿经典 `AiPanelWidgetState` 的回调语义
//! （createSession / switchSession / deleteSession / updateSessionTitle）。
//! 经典 `AiConversationList` 不复用不改（任务书约束；本组件为新写，
//! 删除即时 + 撤销 SnackBar 的经典交互语义在新写中保留）。
//!
//! 分组：今天 / 昨天 / 更早（复用既有 l10n key，按 updatedAt 日界分组，
//! 组头仅在组非空时出现；组内保持 manager 既有顺序）。
//!
//! 宽度（design §8【二】）：展开 = `workbenchSessionListWidth` 240 token；
//! shell 可用宽 < [collapseBreakpoint] 时收 [collapsedWidth] 44 图标 rail
//! （断点由 `AiWorkbenchShell` 的 LayoutBuilder 判定后经 [collapsed] 传入）。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_conversation_session.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../providers/app_provider.dart';
import '../../services/workbench_usage_stats_service.dart';
import '../../theme/app_colors.dart';

/// AI 工作台会话栏（新建 / 切换 / 删除 / 改名）。
class WorkbenchSessionRail extends StatefulWidget {
  const WorkbenchSessionRail({
    super.key,
    required this.collapsed,
  });

  /// 收窄断点（design §8【二】"workbenchSessionListWidth 240（<900 断点收
  /// 成 44）"）。判定对象是 shell 的可用宽（LayoutBuilder），非窗口宽。
  static const double collapseBreakpoint = 900;

  /// 收窄态宽度（design §8【二】，同上条目，M1 无独立 token）。
  static const double collapsedWidth = 44;

  /// true = 收成 44 图标 rail（窄工作区）；false = 展开 240 列表。
  final bool collapsed;

  @override
  State<WorkbenchSessionRail> createState() => _WorkbenchSessionRailState();
}

class _WorkbenchSessionRailState extends State<WorkbenchSessionRail> {
  // 会话列表滚动位随 Shell Offstage 保活跨模式存活（keepScrollOffset，同
  // workbench_chat_view AC1.4 语义）；Scrollbar 与列表共用同一实例
  // （桌面平台 thumbVisibility 要求显式 controller，否则 debug 断言）。
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: true,
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _createSession(BuildContext context) {
    context
        .read<AppProvider>()
        .aiPanel
        .aiConversationService
        .createSession(locale: Localizations.localeOf(context).languageCode);
    // 统计（design §6.4 字段 2）：工作台内经新建按钮建会话。首条消息的
    // 隐式建会话计数在 WorkbenchChatView._sendMessage（两处互斥不重复：
    // 按钮建会话后 hadSession 已为 true）。
    WorkbenchUsageStatsService.instance.recordSession();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) return _buildCollapsedRail(context);
    return _buildExpandedRail(context);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 展开态（240 列表）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildExpandedRail(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: AppDesignSystem.workbenchSessionListWidth,
      color: context.themeColors.bgSecondary,
      child: Column(
        children: [
          _buildHeader(context, l10n.workbenchSessionListTitle),
          Expanded(child: _buildSessionList(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: context.themeColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildNewSessionButton(context, l10n.workbenchNewSession),
        ],
      ),
    );
  }

  Widget _buildNewSessionButton(BuildContext context, String tooltip) {
    return IconButton(
      key: const ValueKey('workbench_new_session_button'),
      icon: const Icon(LucideIcons.plus, size: 16),
      color: context.themeColors.accentPurple,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: tooltip,
      onPressed: () => _createSession(context),
    );
  }

  Widget _buildSessionList(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final service = provider.aiPanel.aiConversationService;
    final sessions = service.sessions;
    if (sessions.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      return Center(
        child: Text(
          l10n.aiPanelNoSessions,
          style: TextStyle(
            fontSize: 12,
            color: context.themeColors.textMuted,
          ),
        ),
      );
    }

    final currentId = service.currentSession?.id;
    final active = sessions.where((s) => !s.isArchived).toList();
    final l10n = AppLocalizations.of(context)!;
    final rows = <Widget>[];
    for (final group in _groupSessions(active)) {
      rows.add(_buildGroupHeader(context, group.label(l10n)));
      for (final session in group.sessions) {
        rows.add(
          _SessionTile(
            key: ValueKey('workbench_session_${session.id}'),
            session: session,
            selected: session.id == currentId,
            onSelected: () =>
                context.read<AppProvider>().aiPanel.switchSession(session.id),
            onDeleted: () => _deleteSession(context, session),
            onRenamed: (newTitle) => context
                .read<AppProvider>()
                .aiPanel
                .aiConversationService
                .updateSessionTitle(session.id, newTitle),
          ),
        );
      }
    }

    // 滚动容器用 CustomScrollView（而非 ListView）：会话列表保持行虚拟化，
    // 同时避免与对话列消息流 ListView 在类型查找上撞车（z2 层 AC1.4 用例
    // 以 ListView 类型唯一定位消息流）。
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
                (context, index) => rows[index],
                childCount: rows.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space3,
        AppDesignSystem.space2,
        AppDesignSystem.space3,
        AppDesignSystem.space1,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: context.themeColors.textMuted,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 删除（沿经典语义：即时删除 + SnackBar 撤销）
  // ──────────────────────────────────────────────────────────────────────────

  void _deleteSession(BuildContext context, AiConversationSession session) {
    context
        .read<AppProvider>()
        .aiPanel
        .aiConversationService
        .deleteSession(session.id);
    final l10n = AppLocalizations.of(context)!;
    final title = session.title;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.aiPanelSessionDeleted(
            title.length > 40 ? '${title.substring(0, 40)}...' : title,
          ),
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: context.themeColors.bgTertiary,
        behavior: SnackBarBehavior.floating,
        persist: false, // 带 action 默认 persist=true 不自动消失（Flutter 3.41）
        action: SnackBarAction(
          label: l10n.commonUndo,
          textColor: context.themeColors.accentBlue,
          onPressed: () => context
              .read<AppProvider>()
              .aiPanel
              .aiConversationService
              .restoreSession(session),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 分组（今天 / 昨天 / 更早；复用既有 queryHistory 日期组 key）
  // ──────────────────────────────────────────────────────────────────────────

  List<_SessionDateGroup> _groupSessions(List<AiConversationSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final groups = <_SessionDateGroup>[
      _SessionDateGroup(_SessionDateKind.today, <AiConversationSession>[]),
      _SessionDateGroup(_SessionDateKind.yesterday, <AiConversationSession>[]),
      _SessionDateGroup(_SessionDateKind.earlier, <AiConversationSession>[]),
    ];
    for (final session in sessions) {
      final updated = session.updatedAt;
      final date = DateTime(updated.year, updated.month, updated.day);
      final _SessionDateKind kind;
      if (date == today) {
        kind = _SessionDateKind.today;
      } else if (date == yesterday) {
        kind = _SessionDateKind.yesterday;
      } else {
        kind = _SessionDateKind.earlier;
      }
      groups.firstWhere((g) => g.kind == kind).sessions.add(session);
    }
    return groups.where((g) => g.sessions.isNotEmpty).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 收窄态（44 图标 rail）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildCollapsedRail(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<AppProvider>();
    final service = provider.aiPanel.aiConversationService;
    final currentId = service.currentSession?.id;
    final active = service.sessions.where((s) => !s.isArchived).toList();

    return Container(
      width: WorkbenchSessionRail.collapsedWidth,
      color: context.themeColors.bgSecondary,
      child: Column(
        children: [
          _buildNewSessionButton(context, l10n.workbenchNewSession),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDesignSystem.space1,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final session = active[index];
                        final selected = session.id == currentId;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppDesignSystem.space0_5,
                          ),
                          child: Center(
                            child: IconButton(
                              key: ValueKey(
                                'workbench_session_icon_${session.id}',
                              ),
                              icon: const Icon(
                                LucideIcons.messageCircle,
                                size: 16,
                              ),
                              color: selected
                                  ? context.themeColors.accentPurple
                                  : context.themeColors.textMuted,
                              tooltip: session.title,
                              onPressed: () => context
                                  .read<AppProvider>()
                                  .aiPanel
                                  .switchSession(session.id),
                            ),
                          ),
                        );
                      },
                      childCount: active.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _SessionDateKind { today, yesterday, earlier }

class _SessionDateGroup {
  const _SessionDateGroup(this.kind, this.sessions);

  final _SessionDateKind kind;
  final List<AiConversationSession> sessions;

  String label(AppLocalizations l10n) {
    switch (kind) {
      case _SessionDateKind.today:
        return l10n.queryHistoryToday;
      case _SessionDateKind.yesterday:
        return l10n.queryHistoryYesterday;
      case _SessionDateKind.earlier:
        return l10n.queryHistoryOlder;
    }
  }
}

/// 会话条目（展开态）：标题 + 相对时间 + 改名/删除菜单（沿经典菜单语义）。
class _SessionTile extends StatelessWidget {
  const _SessionTile({
    super.key,
    required this.session,
    required this.selected,
    required this.onSelected,
    required this.onDeleted,
    required this.onRenamed,
  });

  final AiConversationSession session;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onDeleted;
  final ValueChanged<String> onRenamed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          color: selected
              ? context.themeColors.accentPurple.withValues(alpha: 0.1)
              : null,
          border: Border(
            left: BorderSide(
              width: 2,
              // 未选中态用条目底色占位（NF3.4：不引 Colors.xxx，视觉与
              // transparent 等价——条目底即 rail 的 bgSecondary）。
              color: selected
                  ? context.themeColors.accentPurple
                  : context.themeColors.bgSecondary,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.messageCircle,
              size: 14,
              color: selected
                  ? context.themeColors.accentPurple
                  : context.themeColors.textMuted,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: context.themeColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppDesignSystem.space0_5),
                  Text(
                    _formatDate(context, session.updatedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('workbench_session_menu_${session.id}'),
              icon: Icon(
                LucideIcons.ellipsisVertical,
                size: 14,
                color: context.themeColors.textMuted,
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (context) => [
                CompactPopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      const Icon(LucideIcons.pencil, size: 14),
                      const SizedBox(width: AppDesignSystem.space2),
                      Text(l10n.aiPanelRename),
                    ],
                  ),
                ),
                CompactPopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: context.themeColors.accentRed,
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      Text(
                        l10n.commonDelete,
                        style: TextStyle(
                          color: context.themeColors.accentRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    _showRenameDialog(context);
                  case 'delete':
                    onDeleted();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    // 控制器归对话框 State 所有（随对话框卸载 dispose），避免经典
    // 「.then 里 dispose」写法在退出动画期间提前释放控制器。
    showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialTitle: session.title),
    ).then((newTitle) {
      if (newTitle != null && newTitle.isNotEmpty) {
        onRenamed(newTitle);
      }
    });
  }

  String _formatDate(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return l10n.aiPanelJustNow;
    if (diff.inHours < 1) return l10n.aiPanelMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.aiPanelHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.aiPanelDaysAgo(diff.inDays);
    return '${date.month}/${date.day}';
  }
}

/// 改名对话框（私有辅助类）：控制器归 State 所有，随对话框卸载释放。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.aiPanelRenameSession),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.aiPanelSessionTitle),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          // 空白标题不提交（沿经典语义：newTitle 非空才回调）。
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
