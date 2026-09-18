import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../models/stored_procedure.dart';
import '../../services/stored_procedure_service.dart';
import '../../theme/app_theme.dart';
import '../connection/error_boundary.dart';
import 'procedure_editor_dialog.dart';
import 'procedure_executor_dialog.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

class StoredProceduresDialog extends StatefulWidget {
  final StoredProcedureService service;

  /// 目标库。null 时服务退回连接会话当前库（历史语义，现代流程常为空，
  /// 见 StoredProcedureService._schemaPredicateFor 注释）。
  final String? initialDatabase;

  const StoredProceduresDialog({
    super.key,
    required this.service,
    this.initialDatabase,
  });

  @override
  State<StoredProceduresDialog> createState() => _StoredProceduresDialogState();
}

class _StoredProceduresDialogState extends State<StoredProceduresDialog> {
  List<StoredProcedure> _procedures = [];
  List<StoredProcedure> _functions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _loadRoutines();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadRoutines() async {
    setState(() => _isLoading = true);

    try {
      final procedures = await widget.service.getStoredProcedures(
        database: widget.initialDatabase,
      );
      final functions = await widget.service.getFunctions(
        database: widget.initialDatabase,
      );

      setState(() {
        _procedures = procedures;
        _functions = functions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.loadFailed(e.toString()),
        );
      }
    }
  }

  List<StoredProcedure> _getFilteredProcedures() {
    if (_searchQuery.isEmpty) return _procedures;
    return _procedures
        .where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  List<StoredProcedure> _getFilteredFunctions() {
    if (_searchQuery.isEmpty) return _functions;
    return _functions
        .where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Future<void> _showCreateDialog({ProcedureType? type}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ProcedureEditorDialog(
        service: widget.service,
        procedure: StoredProcedure(
          name: '',
          type: type ?? ProcedureType.procedure,
        ),
      ),
    );

    if (result == true) {
      await _loadRoutines();
    }
  }

  Future<void> _showEditDialog(StoredProcedure procedure) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) =>
          ProcedureEditorDialog(service: widget.service, procedure: procedure),
    );

    if (result == true) {
      await _loadRoutines();
    }
  }

  Future<void> _showExecutorDialog(StoredProcedure procedure) async {
    await showDialog(
      context: context,
      builder: (_) => ProcedureExecutorDialog(
        service: widget.service,
        procedure: procedure,
      ),
    );
  }

  Future<void> _showDefinition(StoredProcedure procedure) async {
    try {
      final definition = await widget.service.getCreateStatement(
        procedure.name,
        procedure.type,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => _DefinitionViewer(
          title: procedure.name,
          type: procedure.type,
          definition: definition,
        ),
      );
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.loadFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _deleteProcedure(StoredProcedure procedure) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(l10n.confirmDelete),
        content: Text(
          l10n.routineDeleteConfirmation(
            procedure.type == ProcedureType.procedure
                ? l10n.sidebarProcedures
                : l10n.sidebarFunctions,
            procedure.name,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.service.drop(procedure.name, procedure.type);
        await _loadRoutines();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.commonSuccess),
              backgroundColor: context.themeColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            l10n.deleteFailed(e.toString()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 900,
        height: 600,
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 600),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space4,
                vertical: AppDesignSystem.space3,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppDesignSystem.radiusLg),
                  topRight: Radius.circular(AppDesignSystem.radiusLg),
                ),
                border: Border(
                  bottom: BorderSide(color: context.themeColors.borderLight),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.routineListTitle,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSize2xl,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _loadRoutines,
                        icon: const Icon(LucideIcons.refreshCw),
                        tooltip: l10n.commonRefresh,
                        color: context.themeColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      IconButton(
                        onPressed: () =>
                            _showCreateDialog(type: ProcedureType.procedure),
                        icon: const Icon(LucideIcons.plus),
                        tooltip: l10n.sidebarProcedures,
                        color: context.themeColors.success,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      IconButton(
                        onPressed: () =>
                            _showCreateDialog(type: ProcedureType.function),
                        icon: const Icon(LucideIcons.functionSquare),
                        tooltip: l10n.sidebarFunctions,
                        color: context.themeColors.accentPurple,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x),
                        color: context.themeColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space4,
                vertical: AppDesignSystem.space2,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary,
                border: Border(
                  bottom: BorderSide(color: context.themeColors.borderLight),
                ),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: l10n.searchPlaceholder,
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    borderSide: BorderSide(
                      color: context.themeColors.borderLight,
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space3,
                    vertical: AppDesignSystem.space2,
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ),
            DefaultTabController(
              length: 2,
              child: Expanded(
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: context.themeColors.borderLight,
                          ),
                        ),
                      ),
                      child: TabBar(
                        tabs: [
                          Tab(text: l10n.sidebarProcedures),
                          Tab(text: l10n.sidebarFunctions),
                        ],
                        labelColor: context.themeColors.textPrimary,
                        unselectedLabelColor: context.themeColors.textSecondary,
                        indicatorColor: context.themeColors.accentBlue,
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildRoutineList(
                            _getFilteredProcedures(),
                            ProcedureType.procedure,
                          ),
                          _buildRoutineList(
                            _getFilteredFunctions(),
                            ProcedureType.function,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineList(List<StoredProcedure> routines, ProcedureType type) {
    final l10n = AppLocalizations.of(context)!;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (routines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == ProcedureType.procedure
                  ? LucideIcons.code
                  : LucideIcons.functionSquare,
              size: 64,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(height: AppDesignSystem.space4),
            Text(
              type == ProcedureType.procedure
                  ? l10n.sidebarProcedures
                  : l10n.sidebarFunctions,
              style: TextStyle(
                fontSize: 16,
                color: context.themeColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            if (_searchQuery.isNotEmpty)
              Text(
                l10n.searchTryDifferentKeywords,
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textMuted,
                ),
              ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: routines.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: context.themeColors.borderLight),
      itemBuilder: (context, index) {
        return _RoutineTile(
          routine: routines[index],
          onTap: () => _showEditDialog(routines[index]),
          onEdit: () => _showEditDialog(routines[index]),
          onExecute: () => _showExecutorDialog(routines[index]),
          onDelete: () => _deleteProcedure(routines[index]),
          onViewDefinition: () => _showDefinition(routines[index]),
        );
      },
    );
  }
}

class _RoutineTile extends StatelessWidget {
  final StoredProcedure routine;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onExecute;
  final VoidCallback onDelete;
  final VoidCallback onViewDefinition;

  const _RoutineTile({
    required this.routine,
    required this.onTap,
    required this.onEdit,
    required this.onExecute,
    required this.onDelete,
    required this.onViewDefinition,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space4,
          vertical: AppDesignSystem.space3,
        ),
        child: Row(
          children: [
            Icon(
              routine.type == ProcedureType.procedure
                  ? LucideIcons.code
                  : LucideIcons.functionSquare,
              size: 20,
              color: routine.type == ProcedureType.procedure
                  ? context.themeColors.warning
                  : context.themeColors.accentPurple,
            ),
            const SizedBox(width: AppDesignSystem.space3),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space1),
                  Text(
                    _getParamSummary(l10n),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
                border: Border.all(color: context.themeColors.borderLight),
              ),
              child: Text(
                l10n.routineParameterCount(routine.parameters.length),
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space3),
            if (routine.returnType != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space1,
                ),
                decoration: BoxDecoration(
                  color: context.themeColors.bgTertiary,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: context.themeColors.borderLight),
                ),
                child: Text(
                  routine.returnType!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space3),
            ],
            Text(
              routine.modifiedAt != null
                  ? _formatDate(routine.modifiedAt!, l10n)
                  : '-',
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textMuted,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space3),
            PopupMenuButton<String>(
              icon: Icon(
                LucideIcons.ellipsisVertical,
                color: context.themeColors.textSecondary,
              ),
              color: context.themeColors.bgSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                    break;
                  case 'execute':
                    onExecute();
                    break;
                  case 'view':
                    onViewDefinition();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (ctx) => _buildPopupMenuItems(ctx, l10n),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildPopupMenuItems(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return [
      CompactPopupMenuItem(
        value: 'edit',
        child: Row(
          children: [
            Icon(
              LucideIcons.pencil,
              size: 16,
              color: context.themeColors.textSecondary,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(l10n.commonEdit),
          ],
        ),
      ),
      CompactPopupMenuItem(
        value: 'execute',
        child: Row(
          children: [
            Icon(
              LucideIcons.play,
              size: 16,
              color: context.themeColors.textSecondary,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(l10n.toolbarExecute),
          ],
        ),
      ),
      CompactPopupMenuItem(
        value: 'view',
        child: Row(
          children: [
            Icon(
              LucideIcons.code,
              size: 16,
              color: context.themeColors.textSecondary,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(l10n.createStatement),
          ],
        ),
      ),
      CompactPopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(
              LucideIcons.trash2,
              size: 16,
              color: context.themeColors.error,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              l10n.commonDelete,
              style: TextStyle(color: context.themeColors.error),
            ),
          ],
        ),
      ),
    ];
  }

  String _getParamSummary(AppLocalizations l10n) {
    if (routine.parameters.isEmpty) return l10n.commonNoData;
    if (routine.parameters.length <= 2) {
      return routine.parameters.map((p) => '${p.mode} ${p.name}').join(', ');
    }
    return '${routine.parameters.map((p) => '${p.mode} ${p.name}').take(2).join(', ')}, ...';
  }

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return l10n.timeAgoMinutes(diff.inMinutes);
      }
      return l10n.timeAgoHours(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.timeAgoDays(diff.inDays);
    } else {
      return '${date.month}/${date.day}';
    }
  }
}

class _DefinitionViewer extends StatelessWidget {
  final String title;
  final ProcedureType type;
  final String definition;

  const _DefinitionViewer({
    required this.title,
    required this.type,
    required this.definition,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 800,
        height: 500,
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 500),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space4,
                vertical: AppDesignSystem.space3,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppDesignSystem.radiusLg),
                  topRight: Radius.circular(AppDesignSystem.radiusLg),
                ),
                border: Border(
                  bottom: BorderSide(color: context.themeColors.borderLight),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.routineDefinitionTitle(
                      type == ProcedureType.procedure
                          ? l10n.sidebarProcedures
                          : l10n.sidebarFunctions,
                    ),
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSize2xl,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: definition));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.copiedToClipboard),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(LucideIcons.copy),
                        tooltip: l10n.menuCopy,
                        color: context.themeColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x),
                        color: context.themeColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDesignSystem.space4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  decoration: BoxDecoration(
                    color: context.themeColors.bgPrimary,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                    border: Border.all(color: context.themeColors.borderLight),
                  ),
                  child: SelectableText(
                    definition,
                    style: TextStyle(
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                      fontSize: 13,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
