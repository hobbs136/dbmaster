import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../models/database_models.dart';
import '../../../utils/app_logger.dart';
import '../../../l10n/app_localizations.dart';
import '../error_boundary.dart';
import '../../sidebar/builders/tree_utils.dart' show getIndexIconInfo;
import '../../../theme/app_colors.dart';

class TablePropertiesDialog extends StatefulWidget {
  final String tableName;
  final String dbName;
  final String? connectionId;

  /// 初始选中的 tab 索引（U17 表右键「查看 DDL」直达 CREATE Statement）。
  final int initialTabIndex;

  const TablePropertiesDialog({
    super.key,
    required this.tableName,
    required this.dbName,
    this.connectionId,
    this.initialTabIndex = 0,
  });

  @override
  State<TablePropertiesDialog> createState() => _TablePropertiesDialogState();
}

class _TablePropertiesDialogState extends State<TablePropertiesDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _properties;
  String? _createSql;
  List<DbIndex>? _indexes;
  List<ForeignKey>? _foreignKeys;
  bool _supportsForeignKeys = false;
  DatabaseType? _dbType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    final dbType = provider.dbService.getDatabaseType(widget.connectionId);
    _dbType = dbType;
    _supportsForeignKeys = dbType?.supportsForeignKeys ?? false;
    _tabController = TabController(
      length: _supportsForeignKeys ? 4 : 3,
      vsync: this,
    );
    if (widget.initialTabIndex > 0) {
      _tabController.index = widget.initialTabIndex.clamp(
        0,
        _tabController.length - 1,
      );
    }
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<AppProvider>();
    try {
      final props = await provider.getTableProperties(
        widget.tableName,
        connectionId: widget.connectionId,
        dbName: widget.dbName,
      );
      final sql = await provider.getCreateTableSql(
        widget.tableName,
        connectionId: widget.connectionId,
      );
      final idx = await provider.getTableIndexes(
        widget.tableName,
        connectionId: widget.connectionId,
      );
      if (mounted) {
        setState(() {
          _properties = props;
          _createSql = sql;
          _indexes = idx;
          _isLoading = false;
        });
      }

      if (_supportsForeignKeys) {
        final fks = await provider.getForeignKeys(
          widget.tableName,
          connectionId: widget.connectionId,
        );
        if (mounted) {
          setState(() => _foreignKeys = fks);
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e(
        'TablePropertiesDialog',
        'Failed to load data',
        e,
        stackTrace,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.loadFailed(e),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.table2, color: context.themeColors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              widget.tableName,
              style: TextStyle(color: context.themeColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: context.themeColors.accentBlue,
              unselectedLabelColor: context.themeColors.textMuted,
              indicatorColor: context.themeColors.accentBlue,
              tabs: [
                Tab(text: l10n.tableStructureInfo),
                Tab(text: l10n.tableIndexes),
                if (_supportsForeignKeys) const Tab(text: 'Foreign Keys'),
                Tab(text: l10n.createStatement),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.themeColors.accentBlue,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildInfoTab(),
                        _buildIndexesTab(),
                        if (_supportsForeignKeys) _buildForeignKeysTab(),
                        _buildCreateSqlTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildInfoTab() {
    final l10n = AppLocalizations.of(context)!;
    if (_properties == null) {
      return Center(
        child: Text(
          l10n.noInformation,
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: l10n.tableNameLabel,
            value: _properties!['name'] ?? '-',
          ),
          // Engine 是 MySQL 存储引擎概念，Doris 不适用
          if (_dbType != DatabaseType.doris)
            _InfoRow(
              label: l10n.tableEngineLabel,
              value: _properties!['engine'] ?? '-',
            ),
          _InfoRow(
            label: l10n.tableRowCountLabel,
            value: _properties!['rows']?.toString() ?? '0',
          ),
          _InfoRow(
            label: l10n.tableDataSizeLabel,
            value: _formatBytes(_properties!['dataLength']),
          ),
          _InfoRow(
            label: l10n.tableIndexSizeLabel,
            value: _formatBytes(_properties!['indexLength']),
          ),
          // Collation 是 MySQL 专属概念，Doris 中不适用
          if (_dbType != DatabaseType.doris)
            _InfoRow(
              label: l10n.dbPropertyCollation,
              value: _properties!['collation'] ?? '-',
            ),
          _InfoRow(
            label: l10n.createdAt,
            value: _properties!['createTime']?.toString() ?? '-',
          ),
          _InfoRow(
            label: l10n.tableMetadataUpdateTime,
            value: _properties!['updateTime']?.toString() ?? '-',
          ),
          if (_properties!['comment'] != null &&
              _properties!['comment'].toString().isNotEmpty)
            _InfoRow(
              label: l10n.tableMetadataComment,
              value: _properties!['comment'],
            ),
        ],
      ),
    );
  }

  Widget _buildIndexesTab() {
    final l10n = AppLocalizations.of(context)!;
    if (_indexes == null || _indexes!.isEmpty) {
      return Center(
        child: Text(
          l10n.noIndexes,
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      itemCount: _indexes!.length,
      itemBuilder: (context, index) {
        final idx = _indexes![index];
        return Container(
          margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Row(
            children: [
              Icon(
                getIndexIconInfo(
                  idx.name,
                  idx.isUnique,
                  isForeignKey: idx.isForeignKey,
                ).$1,
                size: 16,
                color: getIndexIconInfo(
                  idx.name,
                  idx.isUnique,
                  isForeignKey: idx.isForeignKey,
                ).$2,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idx.name,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      idx.columns.join(', '),
                      style: TextStyle(
                        color: context.themeColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (idx.isUnique)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1_5,
                    vertical: AppDesignSystem.space0_5,
                  ),
                  decoration: BoxDecoration(
                    color: context.themeColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Text(
                    'UNIQUE',
                    style: TextStyle(
                      color: context.themeColors.warning,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildForeignKeysTab() {
    if (_foreignKeys == null) {
      return Center(
        child: CircularProgressIndicator(color: context.themeColors.accentBlue),
      );
    }
    if (_foreignKeys!.isEmpty) {
      return Center(
        child: Text(
          'No foreign keys',
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      itemCount: _foreignKeys!.length,
      itemBuilder: (context, index) {
        final fk = _foreignKeys![index];
        return Container(
          margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.link,
                size: 16,
                color: AppDesignSystem.schemaPurple,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fk.name,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${fk.column} → ${fk.referencedTable}.${fk.referencedColumn}',
                      style: TextStyle(
                        color: context.themeColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if (fk.onUpdate != null || fk.onDelete != null)
                      Text(
                        'ON UPDATE ${fk.onUpdate ?? 'NO ACTION'}  |  ON DELETE ${fk.onDelete ?? 'NO ACTION'}',
                        style: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreateSqlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: SelectableText(
        _createSql ?? 'Cannot get CREATE statement',
        style: TextStyle(
          color: context.themeColors.textPrimary,
          fontSize: 12,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
      ),
    );
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return '-';
    final b = (bytes as num).toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(2)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
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
}
