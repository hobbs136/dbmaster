import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/ai_conversation_session.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/compact_popup_menu_item.dart';

class AiConversationList extends StatefulWidget {
  final List<AiConversationSession> sessions;
  final String? currentSessionId;
  final Function(String sessionId) onSessionSelected;
  final Function(String sessionId) onSessionDeleted;
  final Function(List<String> sessionIds) onSessionsDeleted;
  final Function(AiConversationSession session) onSessionRestored;
  final Function(String sessionId) onSessionArchived;
  final Function(String sessionId, String newTitle) onSessionRenamed;
  final VoidCallback onNewSession;
  final VoidCallback? onBack;
  final bool isFullPanel;

  const AiConversationList({
    super.key,
    required this.sessions,
    this.currentSessionId,
    required this.onSessionSelected,
    required this.onSessionDeleted,
    required this.onSessionsDeleted,
    required this.onSessionRestored,
    required this.onSessionArchived,
    required this.onSessionRenamed,
    required this.onNewSession,
    this.onBack,
    this.isFullPanel = false,
  });

  @override
  State<AiConversationList> createState() => _AiConversationListState();
}

class _AiConversationListState extends State<AiConversationList> {
  String _searchQuery = '';
  bool _isBatchMode = false;
  final Set<String> _selectedIds = {};

  List<AiConversationSession> get _filteredSessions {
    if (_searchQuery.isEmpty) return widget.sessions;
    final query = _searchQuery.toLowerCase();
    return widget.sessions
        .where((s) => s.title.toLowerCase().contains(query))
        .toList();
  }

  void _toggleBatchMode() {
    setState(() {
      _isBatchMode = !_isBatchMode;
      if (!_isBatchMode) _selectedIds.clear();
    });
  }

  void _toggleSelection(String sessionId) {
    setState(() {
      if (_selectedIds.contains(sessionId)) {
        _selectedIds.remove(sessionId);
      } else {
        _selectedIds.add(sessionId);
      }
    });
  }

  // ═══ 即时删除 + SnackBar 撤销 ═══

  void _deleteInstant(AiConversationSession session) {
    widget.onSessionDeleted(session.id);
    _showUndoSnackBar(session.title, () {
      widget.onSessionRestored(session);
    });
  }

  void _batchDeleteInstant() {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    final count = ids.length;
    widget.onSessionsDeleted(ids);
    setState(() {
      _isBatchMode = false;
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.aiPanelSessionsDeletedCount(count),
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: context.themeColors.bgTertiary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showUndoSnackBar(String title, VoidCallback onUndo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.aiPanelSessionDeleted(
            title.length > 40 ? '${title.substring(0, 40)}...' : title,
          ),
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: context.themeColors.bgTertiary,
        behavior: SnackBarBehavior.floating,
        persist: false, // 带 action 默认 persist=true 不自动消失（Flutter 3.41）
        action: SnackBarAction(
          label: AppLocalizations.of(context)!.commonUndo,
          textColor: context.themeColors.accentBlue,
          onPressed: onUndo,
        ),
      ),
    );
  }

  // ═══ Dialogs ═══

  void _showRenameDialog(AiConversationSession session) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aiPanelRenameSession),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.aiPanelSessionTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                widget.onSessionRenamed(session.id, newTitle);
              }
              Navigator.of(context).pop();
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Widget _buildSessionItem(AiConversationSession session) {
    final isSelected = session.id == widget.currentSessionId;
    final isChecked = _selectedIds.contains(session.id);
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: _isBatchMode
          ? () => _toggleSelection(session.id)
          : () => widget.onSessionSelected(session.id),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2_5,
        ),
        decoration: BoxDecoration(
          color: isSelected && !_isBatchMode
              ? context.themeColors.accentPurple.withValues(alpha: 0.1)
              : null,
          border: Border(
            left: BorderSide(
              width: 2,
              color: isSelected && !_isBatchMode
                  ? context.themeColors.accentPurple
                  : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            if (_isBatchMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (_) => _toggleSelection(session.id),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              )
            else
              Icon(
                session.isArchived
                    ? LucideIcons.archive
                    : LucideIcons.messageCircle,
                size: 14,
                color: isSelected
                    ? context.themeColors.accentPurple
                    : context.themeColors.textMuted,
              ),
            if (!_isBatchMode) const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected && !_isBatchMode
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: context.themeColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppDesignSystem.space0_5),
                  Text(
                    _formatDate(session.updatedAt, l10n),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isBatchMode)
              PopupMenuButton<String>(
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
                    value: 'archive',
                    child: Row(
                      children: [
                        const Icon(LucideIcons.archive, size: 14),
                        const SizedBox(width: AppDesignSystem.space2),
                        Text(
                          session.isArchived
                              ? l10n.aiPanelUnarchive
                              : l10n.aiPanelArchive,
                        ),
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
                      _showRenameDialog(session);
                    case 'archive':
                      widget.onSessionArchived(session.id);
                    case 'delete':
                      _deleteInstant(session);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = _filteredSessions.where((s) => !s.isArchived).toList();
    final archived = _filteredSessions.where((s) => s.isArchived).toList();

    return Container(
      width: widget.isFullPanel ? double.infinity : 100,
      color: context.themeColors.bgSecondary,
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.themeColors.borderLight),
              ),
            ),
            child: Row(
              children: [
                if (widget.isFullPanel &&
                    widget.onBack != null &&
                    !_isBatchMode) ...[
                  InkWell(
                    onTap: widget.onBack,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.arrowLeft,
                        size: 18,
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                ],
                Text(
                  _isBatchMode
                      ? l10n.aiPanelSelectSessions
                      : l10n.aiPanelSessions,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (_isBatchMode) ...[
                  if (_selectedIds.isNotEmpty)
                    TextButton(
                      onPressed: _batchDeleteInstant,
                      style: TextButton.styleFrom(
                        foregroundColor: context.themeColors.accentRed,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        l10n.commonDeleteWithCount(_selectedIds.length),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  TextButton(
                    onPressed: _toggleBatchMode,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      l10n.commonDone,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ] else ...[
                  InkWell(
                    onTap: _toggleBatchMode,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        l10n.commonSelect,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.themeColors.accentPurple,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  InkWell(
                    onTap: widget.onNewSession,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.plus,
                        size: 18,
                        color: context.themeColors.accentPurple,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: l10n.aiPanelSearchSessions,
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textMuted,
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 16,
                  color: context.themeColors.textMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppDesignSystem.space2,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  borderSide: BorderSide(
                    color: context.themeColors.borderLight,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  borderSide: BorderSide(
                    color: context.themeColors.borderLight,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  borderSide: BorderSide(
                    color: context.themeColors.accentPurple,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: widget.sessions.isEmpty
                ? Center(
                    child: Text(
                      l10n.aiPanelNoSessions,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.themeColors.textMuted,
                      ),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    trackVisibility: false,
                    thickness: 5.0,
                    radius: const Radius.circular(AppDesignSystem.radiusSm),
                    child: ListView(
                      physics: const BouncingScrollPhysics(
                        decelerationRate: ScrollDecelerationRate.fast,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDesignSystem.space1,
                      ),
                      children: [
                        if (active.isNotEmpty) ...active.map(_buildSessionItem),
                        if (archived.isNotEmpty)
                          ExpansionTile(
                            title: Text(
                              l10n.aiPanelArchivedSessions(archived.length),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.themeColors.textMuted,
                              ),
                            ),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: AppDesignSystem.space3,
                            ),
                            childrenPadding: EdgeInsets.zero,
                            initiallyExpanded: active.isEmpty,
                            children: archived.map(_buildSessionItem).toList(),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return l10n.aiPanelJustNow;
    if (diff.inHours < 1) return l10n.aiPanelMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.aiPanelHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.aiPanelDaysAgo(diff.inDays);
    return '${date.month}/${date.day}';
  }
}
