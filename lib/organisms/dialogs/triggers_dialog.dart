import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../models/trigger.dart';
import '../../services/trigger_service.dart';
import '../../theme/app_theme.dart';
import 'trigger_editor_dialog.dart';
import '../connection/definition_view_dialog.dart';
import '../connection/error_boundary.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

class TriggersDialog extends StatefulWidget {
  final TriggerService service;

  const TriggersDialog({super.key, required this.service});

  @override
  State<TriggersDialog> createState() => _TriggersDialogState();
}

class _TriggersDialogState extends State<TriggersDialog> {
  List<DatabaseTrigger> _triggers = [];
  bool _isLoading = true;
  final bool _isGrouped = false;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _menuKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadTriggers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTriggers() async {
    setState(() => _isLoading = true);
    try {
      final triggers = await widget.service.getTriggers();
      setState(() => _triggers = triggers);
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.triggerFailedToLoad(e.toString()),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<DatabaseTrigger> get _filteredTriggers {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return _triggers;
    return _triggers
        .where((t) => t.name.toLowerCase().contains(query))
        .toList();
  }

  Map<String, List<DatabaseTrigger>> get _groupedTriggers {
    final grouped = <String, List<DatabaseTrigger>>{};
    for (final trigger in _filteredTriggers) {
      grouped.putIfAbsent(trigger.tableName, () => []).add(trigger);
    }
    return grouped;
  }

  Future<void> _showCreateDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TriggerEditorDialog(service: widget.service),
    );
    if (result == true) {
      _loadTriggers();
    }
  }

  Future<void> _showEditDialog(DatabaseTrigger trigger) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TriggerEditorDialog(
        service: widget.service,
        existingTrigger: trigger,
      ),
    );
    if (result == true) {
      _loadTriggers();
    }
  }

  Future<void> _showDefinition(DatabaseTrigger trigger) async {
    final definition = await widget.service.getCreateStatement(trigger.name);
    if (mounted && definition.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => DefinitionViewDialog(
          title: AppLocalizations.of(context)!.triggerDefinition(trigger.name),
          definition: definition,
        ),
      );
    } else {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.triggerFailedToLoadDefinition,
        );
      }
    }
  }

  Future<void> _deleteTrigger(DatabaseTrigger trigger) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(
          AppLocalizations.of(context)!.triggerDeleteTitle,
          style: TextStyle(color: context.themeColors.textPrimary),
        ),
        content: Text(
          AppLocalizations.of(context)!.triggerDeleteConfirm(trigger.name),
          style: TextStyle(color: context.themeColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.error,
            ),
            child: Text(AppLocalizations.of(context)!.commonDelete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.service.drop(trigger.name);
        _loadTriggers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.triggerDeleted(trigger.name),
              ),
              backgroundColor: context.themeColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            AppLocalizations.of(context)!.triggerDeleteFailed(e.toString()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.zap,
                color: context.themeColors.warning,
                size: 24,
              ),
              const SizedBox(width: AppDesignSystem.space3),
              Text(
                AppLocalizations.of(context)!.triggerTitle,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSize2xl,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  LucideIcons.refreshCw,
                  color: context.themeColors.textMuted,
                ),
                onPressed: _loadTriggers,
                tooltip: AppLocalizations.of(context)!.commonRefresh,
              ),
              IconButton(
                icon: Icon(LucideIcons.x, color: context.themeColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.themeColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.triggerSearchHint,
                    hintStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 14,
                      color: context.themeColors.textMuted,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? InkWell(
                            onTap: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            child: Icon(
                              LucideIcons.x,
                              size: 14,
                              color: context.themeColors.textMuted,
                            ),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space2_5,
                      vertical: AppDesignSystem.space1_5,
                    ),
                    filled: true,
                    fillColor: context.themeColors.bgTertiary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      borderSide: BorderSide(
                        color: context.themeColors.borderLight,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      borderSide: BorderSide(
                        color: context.themeColors.borderLight,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: context.themeColors.accentBlue),
      );
    }

    if (_triggers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.zap,
              size: 48,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              AppLocalizations.of(context)!.triggerNoTriggers,
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            ElevatedButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(AppLocalizations.of(context)!.triggerCreate),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space4,
                  vertical: AppDesignSystem.space2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isGrouped) {
      return _buildGroupedView();
    }

    return _buildListView();
  }

  Widget _buildListView() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      itemCount: _filteredTriggers.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: context.themeColors.borderLight),
      itemBuilder: (context, index) {
        return _buildTriggerItem(_filteredTriggers[index]);
      },
    );
  }

  Widget _buildGroupedView() {
    final grouped = _groupedTriggers;
    final tables = grouped.keys.toList()..sort();

    return ListView.separated(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      itemCount: tables.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: AppDesignSystem.space4),
      itemBuilder: (context, index) {
        final tableName = tables[index];
        final tableTriggers = grouped[tableName]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTableHeader(tableName),
            const SizedBox(height: AppDesignSystem.space2),
            ...List.generate(tableTriggers.length, (i) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: i < tableTriggers.length - 1 ? 8 : 0,
                ),
                child: _buildTriggerItem(tableTriggers[i], showTable: false),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildTableHeader(String tableName) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.table2,
            size: 14,
            color: context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Text(
            tableName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggerItem(DatabaseTrigger trigger, {bool showTable = true}) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(trigger, details.globalPosition),
      child: Container(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: context.themeColors.bgTertiary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.zap, size: 16, color: context.themeColors.warning),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trigger.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space1),
                  Row(
                    children: [
                      _buildTimingBadge(trigger.timing),
                      const SizedBox(width: AppDesignSystem.space1_5),
                      _buildEventBadge(trigger.events),
                      if (showTable) ...[
                        const SizedBox(width: AppDesignSystem.space1_5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDesignSystem.space1_5,
                            vertical: AppDesignSystem.space0_5,
                          ),
                          decoration: BoxDecoration(
                            color: context.themeColors.info.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppDesignSystem.radiusSm,
                            ),
                          ),
                          child: Text(
                            trigger.tableName,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.info,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              key: _menuKey,
              icon: Icon(
                LucideIcons.ellipsisVertical,
                size: 18,
                color: context.themeColors.textMuted,
              ),
              onPressed: () {
                final RenderBox? renderBox =
                    _menuKey.currentContext?.findRenderObject() as RenderBox?;
                if (renderBox != null) {
                  final offset = renderBox.localToGlobal(Offset.zero);
                  _showContextMenu(trigger, offset + Offset(0, 40));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingBadge(TriggerTiming timing) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: timing == TriggerTiming.before
            ? context.themeColors.warning.withValues(alpha: 0.2)
            : context.themeColors.accentPurple.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        timing.value,
        style: TextStyle(
          fontSize: 11,
          color: timing == TriggerTiming.before
              ? context.themeColors.warning
              : context.themeColors.accentPurple,
        ),
      ),
    );
  }

  Widget _buildEventBadge(List<TriggerEvent> events) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.accentBlue.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        events.map((e) => e.value).join(' OR '),
        style: TextStyle(fontSize: 11, color: context.themeColors.accentBlue),
      ),
    );
  }

  void _showContextMenu(DatabaseTrigger trigger, Offset position) {
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
        CompactPopupMenuItem(
          value: 'edit',
          child: Text(AppLocalizations.of(context)!.commonEdit),
        ),
        CompactPopupMenuItem(
          value: 'view',
          child: Text(AppLocalizations.of(context)!.triggerViewDefinition),
        ),
        CompactPopupMenuItem(
          value: 'copy_name',
          child: Text(AppLocalizations.of(context)!.triggerCopyName),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'delete',
          child: Text(
            AppLocalizations.of(context)!.commonDelete,
            style: TextStyle(color: context.themeColors.error),
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'edit':
          _showEditDialog(trigger);
          break;
        case 'view':
          _showDefinition(trigger);
          break;
        case 'copy_name':
          Clipboard.setData(ClipboardData(text: trigger.name));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.triggerCopied(trigger.name),
                ),
                backgroundColor: context.themeColors.success,
              ),
            );
          }
          break;
        case 'delete':
          _deleteTrigger(trigger);
          break;
      }
    });
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.themeColors.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            AppLocalizations.of(context)!.triggerCount(_triggers.length),
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 12,
            ),
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.themeColors.textSecondary,
                  side: BorderSide(color: context.themeColors.borderLight),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space4,
                    vertical: AppDesignSystem.space2,
                  ),
                ),
                child: Text(AppLocalizations.of(context)!.commonClose),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: Text(AppLocalizations.of(context)!.triggerNew),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.accentBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space4,
                    vertical: AppDesignSystem.space2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
