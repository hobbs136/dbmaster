import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/backup_models.dart';
import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../atoms/app_loading.dart';
import '../../utils/app_logger.dart';
import '../../molecules/dialog_connection_selector.dart';
import 'error_boundary.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

class BackupDialog extends StatefulWidget {
  final String? initialConnectionId;
  final String? initialDatabase;

  const BackupDialog({
    super.key,
    this.initialConnectionId,
    this.initialDatabase,
  });

  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late BackupService _backupService;
  StreamSubscription<BackupProgress>? _progressSubscription;
  List<BackupFile> _backups = [];
  BackupProgress _progress = BackupProgress();
  bool _isLoading = false;
  String? _error;
  String? _previewContent;
  BackupFile? _selectedBackup;

  final _backupOptions = BackupOptions();
  final _descriptionController = TextEditingController();
  final _whereClauseController = TextEditingController();
  List<String> _availableTables = [];
  final Set<String> _selectedTables = {};
  int? _limit;

  String? _selectedConnectionId;
  String? _selectedDatabase;
  List<String> _dialogDatabases = [];

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedConnectionId = widget.initialConnectionId;
    _selectedDatabase = widget.initialDatabase;
    if (_selectedConnectionId != null) {
      _loadDatabasesForConnection(_selectedConnectionId!);
    }
    _initBackupService();
  }

  Future<void> _loadDatabasesForConnection(String connectionId) async {
    final provider = context.read<AppProvider>();
    final databases = await provider.connection.dbService.getDatabases(
      connectionId: connectionId,
    );
    if (mounted) {
      setState(() {
        _dialogDatabases = databases;
        if (_selectedDatabase != null &&
            !databases.contains(_selectedDatabase) &&
            databases.isNotEmpty) {
          _selectedDatabase = databases.first;
        }
      });
    }
  }

  void _initBackupService() {
    final provider = context.read<AppProvider>();
    _backupService = BackupService(provider.connection.dbService);
    _progressSubscription = _backupService.progressStream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _progress = progress;
          });
        }
      },
      onError: (error, stackTrace) {
        AppLogger.e('BackupDialog', 'Progress stream error', error, stackTrace);
      },
    );
    _loadBackups();
    _loadAvailableTables();
  }

  Future<void> _reloadService() async {
    final connectionId = _selectedConnectionId;
    if (connectionId == null) return;

    final provider = context.read<AppProvider>();

    _backupService = BackupService(provider.connection.dbService);
    await provider.connection.withConnection(
      connectionId,
      _selectedDatabase,
      () async {
        _loadBackups();
        _loadAvailableTables();
      },
    );
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final backups = await _backupService.getBackupList();
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '${l10n.loadBackupListFailed}: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadAvailableTables() async {
    final provider = context.read<AppProvider>();
    final dbService = provider.connection.dbService;
    if (!dbService.isConnected) return;

    try {
      final tables = await dbService.getTables(
        connectionId: _selectedConnectionId,
      );
      if (mounted) {
        setState(() {
          _availableTables = tables;
        });
      }
    } catch (e) {
      AppLogger.d('BackupDialog', '${l10n.loadBackupListFailed}: $e');
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _tabController.dispose();
    _descriptionController.dispose();
    _whereClauseController.dispose();
    _backupService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 900,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DialogConnectionSelector(
              selectedConnectionId: _selectedConnectionId,
              selectedDatabase: _selectedDatabase,
              databases: _dialogDatabases,
              onConnectionChanged: (connectionId) {
                setState(() {
                  _selectedConnectionId = connectionId;
                  _selectedDatabase = null;
                });
                if (connectionId != null) {
                  _loadDatabasesForConnection(connectionId);
                } else {
                  setState(() {
                    _dialogDatabases = [];
                  });
                }
                _reloadService();
              },
              onDatabaseChanged: (database) {
                setState(() {
                  _selectedDatabase = database;
                });
                _reloadService();
              },
            ),
            const SizedBox(height: AppDesignSystem.space4),
            _buildHeader(),
            const SizedBox(height: AppDesignSystem.space4),
            _buildTabBar(),
            const SizedBox(height: AppDesignSystem.space4),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildBackupListTab(), _buildCreateBackupTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          LucideIcons.databaseBackup,
          color: context.themeColors.accentBlue,
          size: 28,
        ),
        const SizedBox(width: AppDesignSystem.space3),
        Expanded(
          child: Text(
            l10n.backupManagement,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.x, color: context.themeColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: context.themeColors.accentBlue,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: context.themeColors.textSecondary,
        tabs: [
          Tab(icon: const Icon(LucideIcons.folderOpen), text: l10n.backupList),
          Tab(
            icon: const Icon(LucideIcons.circlePlus),
            text: l10n.createBackup,
          ),
        ],
      ),
    );
  }

  Widget _buildBackupListTab() {
    if (_isLoading) {
      return Center(
        child: AppBrandedLoading(size: 32, label: l10n.backupListLoading),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: context.themeColors.error.withOpacity(0.5),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            SelectableText(
              _error!,
              style: TextStyle(color: context.themeColors.textMuted),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            ElevatedButton(onPressed: _loadBackups, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    if (_backups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.folderOpen,
              size: 64,
              color: context.themeColors.textMuted.withOpacity(0.3),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            Text(
              l10n.noBackupFiles,
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              l10n.clickCreateBackupTab,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildBackupListToolbar(),
              const SizedBox(height: AppDesignSystem.space2),
              Expanded(child: _buildBackupList()),
            ],
          ),
        ),
        const SizedBox(width: AppDesignSystem.space4),
        Expanded(
          flex: 3,
          child: _selectedBackup != null
              ? _buildBackupDetail()
              : _buildEmptyDetail(),
        ),
      ],
    );
  }

  Widget _buildBackupListToolbar() {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: _importBackup,
          icon: const Icon(LucideIcons.fileUp, size: 16),
          label: Text(l10n.importBackup),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.success,
            foregroundColor: Colors.white,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: _loadBackups,
          icon: const Icon(LucideIcons.refreshCw, size: 20),
          tooltip: l10n.commonRefresh,
        ),
      ],
    );
  }

  Widget _buildBackupList() {
    return ListView.separated(
      itemCount: _backups.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: context.themeColors.dividerColor),
      itemBuilder: (context, index) {
        final backup = _backups[index];
        final isSelected = _selectedBackup?.id == backup.id;

        return ListTile(
          selected: isSelected,
          selectedTileColor: context.themeColors.accentBlue.withOpacity(0.1),
          leading: Icon(
            _getIconForType(backup.type),
            color: isSelected
                ? context.themeColors.accentBlue
                : context.themeColors.textSecondary,
          ),
          title: Text(
            backup.name,
            style: TextStyle(
              color: isSelected
                  ? context.themeColors.textPrimary
                  : context.themeColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${backup.database} · ${backup.sizeFormatted} · ${_formatDate(backup.createdAt)}',
            style: TextStyle(
              color: isSelected
                  ? context.themeColors.textSecondary
                  : context.themeColors.textMuted,
              fontSize: 12,
            ),
          ),
          onTap: () => _selectBackup(backup),
          trailing: PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
            onSelected: (value) => _handleBackupAction(backup, value),
            itemBuilder: (context) => [
              CompactPopupMenuItem(
                value: 'preview',
                child: Text(l10n.previewContent),
              ),
              CompactPopupMenuItem(
                value: 'export',
                child: Text(l10n.exportFile),
              ),
              CompactPopupMenuItem(
                value: 'restore',
                child: Text(l10n.restoreBackup),
              ),
              const PopupMenuDivider(height: 6),
              CompactPopupMenuItem(
                value: 'delete',
                child: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: context.themeColors.error),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyDetail() {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.info,
              size: 48,
              color: context.themeColors.textMuted.withOpacity(0.3),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            Text(
              l10n.selectBackupToView,
              style: TextStyle(color: context.themeColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupDetail() {
    final backup = _selectedBackup!;

    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.themeColors.dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getIconForType(backup.type),
                      color: context.themeColors.accentBlue,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Expanded(
                      child: Text(
                        backup.name,
                        style: TextStyle(
                          color: context.themeColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space3),
                _buildInfoRow(l10n.database, backup.database),
                _buildInfoRow(l10n.backupType, backup.typeDisplay),
                _buildInfoRow(l10n.backupSize, backup.sizeFormatted),
                _buildInfoRow(
                  l10n.createdAt,
                  _formatDateTime(backup.createdAt),
                ),
                _buildInfoRow(l10n.tableCount, '${backup.tables.length}'),
                if (backup.description != null)
                  _buildInfoRow(l10n.description, backup.description!),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.themeColors.dividerColor),
              ),
            ),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _restoreBackup(backup),
                  icon: const Icon(LucideIcons.history, size: 16),
                  label: Text(l10n.restoreBackup),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.themeColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                OutlinedButton.icon(
                  onPressed: () => _exportBackup(backup),
                  icon: const Icon(LucideIcons.fileDown, size: 16),
                  label: Text(l10n.export),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.themeColors.textPrimary,
                    side: BorderSide(color: context.themeColors.borderColor),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _previewBackup(backup),
                  icon: const Icon(LucideIcons.eye, size: 16),
                  label: Text(l10n.preview),
                ),
              ],
            ),
          ),
          if (_previewContent != null)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppDesignSystem.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.previewContent,
                          style: TextStyle(
                            color: context.themeColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _previewContent = null),
                          icon: const Icon(LucideIcons.x, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDesignSystem.space2),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(AppDesignSystem.space3),
                        decoration: BoxDecoration(
                          color: context.themeColors.bgSecondary,
                          borderRadius: BorderRadius.circular(
                            AppDesignSystem.radiusSm,
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _previewContent!,
                            style: TextStyle(
                              color: context.themeColors.textPrimary,
                              fontFamily: AppDesignSystem.monoFontFamily,

                              fontFamilyFallback:
                                  AppDesignSystem.monoFontFamilyFallback,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateBackupTab() {
    final dbService = context.read<AppProvider>().connection.dbService;
    if (!dbService.isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.unlink,
              size: 64,
              color: context.themeColors.textMuted.withOpacity(0.3),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            Text(
              l10n.pleaseConnectDatabase,
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(l10n.backupFormat),
                _buildFormatSelector(),
                const SizedBox(height: AppDesignSystem.space5),
                _buildSectionTitle(l10n.backupContent),
                _buildContentOptions(),
                const SizedBox(height: AppDesignSystem.space5),
                _buildSectionTitle(l10n.selectTablesHint),
                _buildTableSelector(),
                const SizedBox(height: AppDesignSystem.space5),
                _buildSectionTitle(l10n.advancedOptions),
                _buildAdvancedOptions(),
                const SizedBox(height: AppDesignSystem.space5),
                _buildSectionTitle(l10n.description),
                _buildDescriptionInput(),
                const SizedBox(height: AppDesignSystem.space5),
                _buildCreateButton(),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space4),
        Expanded(flex: 2, child: _buildProgressPanel()),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      child: Text(
        title,
        style: TextStyle(
          color: context.themeColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFormatSelector() {
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
          value: 'sql',
          label: Text(AppLocalizations.of(context)!.formatSqlInsert),
          icon: Icon(LucideIcons.code),
        ),
        ButtonSegment(
          value: 'json',
          label: Text(AppLocalizations.of(context)!.formatJSON),
          icon: Icon(LucideIcons.braces),
        ),
        ButtonSegment(
          value: 'csv',
          label: Text(AppLocalizations.of(context)!.formatCSV),
          icon: Icon(LucideIcons.table2),
        ),
      ],
      selected: {_backupOptions.format},
      onSelectionChanged: (value) {
        setState(() {
          _backupOptions.copyWith(format: value.first);
        });
      },
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return context.themeColors.accentBlue;
          }
          return context.themeColors.bgTertiary;
        }),
      ),
    );
  }

  Widget _buildContentOptions() {
    return Column(
      children: [
        CheckboxListTile(
          title: Text(
            l10n.includeStructure,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
          subtitle: Text(
            l10n.includeStructureDesc,
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 12,
            ),
          ),
          value: _backupOptions.includeStructure,
          onChanged: (value) {
            setState(() {
              _backupOptions.copyWith(includeStructure: value ?? true);
            });
          },
          activeColor: context.themeColors.accentBlue,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          title: Text(
            l10n.includeData,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
          subtitle: Text(
            l10n.includeDataDesc,
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 12,
            ),
          ),
          value: _backupOptions.includeData,
          onChanged: (value) {
            setState(() {
              _backupOptions.copyWith(includeData: value ?? true);
            });
          },
          activeColor: context.themeColors.accentBlue,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }

  Widget _buildTableSelector() {
    if (_availableTables.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppDesignSystem.space4),
        decoration: BoxDecoration(
          color: context.themeColors.bgPrimary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(color: context.themeColors.borderLight),
        ),
        child: Text(
          l10n.noTablesAvailable,
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.themeColors.dividerColor),
              ),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedTables.addAll(_availableTables);
                    });
                  },
                  child: Text(l10n.selectAll),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedTables.clear();
                    });
                  },
                  child: Text(l10n.deselectAll),
                ),
                const Spacer(),
                Text(
                  l10n.tablesSelected(_selectedTables.length),
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _availableTables.length,
              itemBuilder: (context, index) {
                final table = _availableTables[index];
                final isSelected = _selectedTables.contains(table);

                return CheckboxListTile(
                  title: Text(
                    table,
                    style: TextStyle(
                      color: context.themeColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedTables.add(table);
                      } else {
                        _selectedTables.remove(table);
                      }
                    });
                  },
                  activeColor: context.themeColors.accentBlue,
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space3,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedOptions() {
    return Column(
      children: [
        if (_backupOptions.format == 'sql') ...[
          CheckboxListTile(
            title: Text(
              l10n.addDropTable,
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
            value: _backupOptions.addDropTable,
            onChanged: (value) {
              setState(() {
                _backupOptions.copyWith(addDropTable: value ?? true);
              });
            },
            activeColor: context.themeColors.accentBlue,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          CheckboxListTile(
            title: Text(
              l10n.useExtendedInsert,
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
            subtitle: Text(
              l10n.useExtendedInsertDesc,
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 12,
              ),
            ),
            value: _backupOptions.extendedInsert,
            onChanged: (value) {
              setState(() {
                _backupOptions.copyWith(extendedInsert: value ?? true);
              });
            },
            activeColor: context.themeColors.accentBlue,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: InputDecoration(
                  labelText: l10n.rowLimitPerTable,
                  hintText: l10n.leaveEmptyForNoLimit,
                ),
                style: TextStyle(color: context.themeColors.textPrimary),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    _limit = int.tryParse(value);
                  });
                },
              ),
            ),
            const SizedBox(width: AppDesignSystem.space4),
            Expanded(
              child: TextFormField(
                controller: _whereClauseController,
                decoration: InputDecoration(
                  labelText: l10n.whereCondition,
                  hintText: l10n.whereConditionExample,
                ),
                style: TextStyle(color: context.themeColors.textPrimary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDescriptionInput() {
    return TextFormField(
      controller: _descriptionController,
      decoration: InputDecoration(hintText: l10n.enterBackupDescription),
      style: TextStyle(color: context.themeColors.textPrimary),
      maxLines: 2,
    );
  }

  Widget _buildCreateButton() {
    final bool isRunning = _progress.status == 'running';

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isRunning ? null : _createBackup,
        icon: isRunning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.databaseBackup),
        label: Text(isRunning ? '${l10n.startBackup}...' : l10n.startBackup),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.themeColors.accentBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space4),
        ),
      ),
    );
  }

  Widget _buildProgressPanel() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.backupProgress,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          if (_progress.status == 'idle')
            Center(
              child: Text(
                l10n.waitingToStartBackup,
                style: TextStyle(color: context.themeColors.textMuted),
              ),
            )
          else if (_progress.status == 'running') ...[
            LinearProgressIndicator(
              value: _progress.progress,
              backgroundColor: context.themeColors.bgTertiary,
              valueColor: AlwaysStoppedAnimation(
                context.themeColors.accentBlue,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              '${l10n.currentTable}: ${_progress.currentTable}',
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 12,
              ),
            ),
            Text(
              '${l10n.progressPercent}: ${(_progress.progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 12,
              ),
            ),
          ] else if (_progress.status == 'completed')
            Center(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.circleCheckBig,
                    color: context.themeColors.success,
                    size: 48,
                  ),
                  const SizedBox(height: AppDesignSystem.space3),
                  Text(
                    l10n.backupComplete,
                    style: TextStyle(color: context.themeColors.success),
                  ),
                ],
              ),
            )
          else if (_progress.status == 'error')
            Center(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    color: context.themeColors.error,
                    size: 48,
                  ),
                  const SizedBox(height: AppDesignSystem.space3),
                  SelectableText(
                    '${l10n.backupFailed}: ${_progress.error}',
                    style: TextStyle(color: context.themeColors.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _selectBackup(BackupFile backup) {
    setState(() {
      _selectedBackup = backup;
      _previewContent = null;
    });
  }

  Future<void> _handleBackupAction(BackupFile backup, String action) async {
    switch (action) {
      case 'preview':
        await _previewBackup(backup);
        break;
      case 'export':
        await _exportBackup(backup);
        break;
      case 'restore':
        await _restoreBackup(backup);
        break;
      case 'delete':
        await _deleteBackup(backup);
        break;
    }
  }

  Future<void> _previewBackup(BackupFile backup) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final content = await _backupService.getBackupPreview(backup.id);
      setState(() {
        _previewContent = content;
        _selectedBackup = backup;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('${l10n.previewFailed}: $e');
    }
  }

  Future<void> _exportBackup(BackupFile backup) async {
    try {
      final path = await _backupService.exportBackup(backup.id);
      _showSuccess('${l10n.exportedTo}: $path');
    } catch (e) {
      _showError('${l10n.exportFailed}: $e');
    }
  }

  Future<void> _restoreBackup(BackupFile backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.triangleAlert, color: context.themeColors.warning),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              l10n.confirmRestore,
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          l10n.confirmRestoreMessage(backup.name),
          style: TextStyle(color: context.themeColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.warning,
            ),
            child: Text(l10n.confirmRestore),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _backupService.restoreBackup(backup.id);
      setState(() {
        _isLoading = false;
      });
      _showSuccess(l10n.backupRestoreSuccess);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('${l10n.restoreFailed}: $e');
    }
  }

  Future<void> _deleteBackup(BackupFile backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.trash2, color: context.themeColors.error),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              l10n.confirmDelete,
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          l10n.confirmDeleteMessage(backup.name),
          style: TextStyle(color: context.themeColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _backupService.deleteBackup(backup.id);
      _loadBackups();
      setState(() {
        if (_selectedBackup?.id == backup.id) {
          _selectedBackup = null;
          _previewContent = null;
        }
      });
      _showSuccess(l10n.backupDeleted);
    } catch (e) {
      _showError('${l10n.deleteFailed}: $e');
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['sql', 'json', 'csv'],
        dialogTitle: l10n.selectBackupFile,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.first.path;
      if (filePath == null) return;

      setState(() {
        _isLoading = true;
      });

      await _backupService.importBackup(filePath);
      await _loadBackups();

      setState(() {
        _isLoading = false;
      });

      _showSuccess(l10n.backupImportSuccess);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('${l10n.importFailed}: $e');
    }
  }

  Future<void> _createBackup() async {
    final options = _backupOptions.copyWith(
      tables: _selectedTables.toList(),
      description: _descriptionController.text.isEmpty
          ? null
          : _descriptionController.text,
      limit: _limit,
      whereClause: _whereClauseController.text.isEmpty
          ? null
          : _whereClauseController.text,
    );

    if (!options.includeStructure && !options.includeData) {
      _showError(l10n.selectAtLeastOneOption);
      return;
    }

    try {
      await _backupService.createBackup(options);
      await _loadBackups();
    } catch (e) {
      _showError('${l10n.backupFailedError}: $e');
    }
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'sql':
        return LucideIcons.code;
      case 'json':
        return LucideIcons.braces;
      case 'csv':
        return LucideIcons.table2;
      default:
        return LucideIcons.file;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    AppErrorHandler.showErrorSnackBar(context, message);
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.themeColors.success,
      ),
    );
  }
}
