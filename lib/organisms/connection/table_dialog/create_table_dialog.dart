import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../atoms/app_loading.dart';
import '../../../models/database_models.dart';
import '../../../utils/app_logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../../molecules/destructive_confirm_dialog.dart'
    show DestructiveConfirmDialog, DestructiveTone;
import '../../../services/audit_log_service.dart';
import '../../../services/adapters/postgresql_gateway_adapter.dart';
import '../error_boundary.dart';
import '../../../theme/app_colors.dart';

/// DBT-T19（W-16）：分区建表 DDL 审计载荷（recordQuery 口径子集；测试断言面）。
typedef PgPartitionAuditRecord = ({
  String connectionId,
  String databaseName,
  String sql,
  Duration executionTime,
  bool success,
  String? errorMessage,
});

/// 分区 DDL 默认审计器：先 initialize；SQL 脱敏与截断由 recordQuery 内部处理。
Future<void> auditPgPartitionDdl(PgPartitionAuditRecord record) async {
  final audit = AuditLogService();
  await audit.initialize();
  audit.recordQuery(
    connectionId: record.connectionId,
    databaseName: record.databaseName,
    sql: record.sql,
    executionTime: record.executionTime,
    success: record.success,
    errorMessage: record.errorMessage,
    isWriteQuery: true,
  );
}

/// DBT-T19：建表执行注入缝（默认 = provider.createTable；widget 测试计数与
/// options 逐字断言面，沿 T18 executor 注入先例）。
typedef PgTableCreator =
    Future<bool> Function(
      String dbName,
      String tableName,
      List<DbColumn> columns, {
      String? comment,
      String? engine,
      Map<String, dynamic>? options,
    });

class CreateTableDialog extends StatefulWidget {
  final String dbName;

  const CreateTableDialog({super.key, required this.dbName});

  @override
  State<CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<CreateTableDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _tableNameController = TextEditingController();
  final _commentController = TextEditingController();
  // Doris 表模型 + 分桶（仅 Doris 连接渲染；非 Doris 连接不显示）
  String _dorisModel = 'DUPLICATE';
  String? _dorisHashColumn;
  int _dorisBuckets = 1;
  // RANGE 分区
  String? _dorisPartitionColumn;
  final List<_PartitionDefinition> _partitions = [];
  String _engine = 'InnoDB';
  String _charset = 'utf8mb4';
  final List<_ColumnDefinition> _columns = [_ColumnDefinition()];
  final List<_IndexDefinition> _indexes = [];
  bool _isLoading = false;
  late TabController _tabController;

  final List<String> _engines = [
    'InnoDB',
    'MyISAM',
    'MEMORY',
    'ARCHIVE',
    'CSV',
  ];
  final List<String> _charsets = ['utf8mb4', 'utf8', 'latin1', 'gbk', 'big5'];
  final List<String> _dataTypes = [
    'INT',
    'BIGINT',
    'SMALLINT',
    'TINYINT',
    'DECIMAL',
    'FLOAT',
    'DOUBLE',
    'VARCHAR(255)',
    'CHAR(50)',
    'TEXT',
    'LONGTEXT',
    'MEDIUMTEXT',
    'DATE',
    'DATETIME',
    'TIMESTAMP',
    'TIME',
    'YEAR',
    'BOOLEAN',
    'BIT',
    'BLOB',
    'LONGBLOB',
    'MEDIUMBLOB',
    'JSON',
    'ENUM',
    'SET',
  ];

  // Doris 支持的数据类型（去除了 MySQL 专属类型）
  final List<String> _dorisDataTypes = [
    'BOOLEAN',
    'TINYINT',
    'SMALLINT',
    'INT',
    'BIGINT',
    'LARGEINT',
    'FLOAT',
    'DOUBLE',
    'DECIMAL',
    'DATE',
    'DATETIME',
    'VARCHAR(255)',
    'CHAR(50)',
    'STRING',
    'TEXT',
    'JSON',
    'HLL',
    'BITMAP',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tableNameController.dispose();
    _commentController.dispose();
    _tabController.dispose();
    for (final col in _columns) {
      col.dispose();
    }
    for (final idx in _indexes) {
      idx.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDoris =
        context.read<AppProvider>().connection.currentServer?.type ==
        DatabaseType.doris;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        l10n.tableCreateNewTable,
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: SizedBox(
        width: 750,
        height: 520,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _tableNameController,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.tableName,
                        labelStyle: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 12,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space3,
                          vertical: AppDesignSystem.space2,
                        ),
                        isDense: true,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.enterTableName;
                        }
                        return null;
                      },
                    ),
                  ),
                  if (!isDoris) ...[
                    const SizedBox(width: AppDesignSystem.space3),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _engine,
                        style: TextStyle(
                          color: context.themeColors.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.tableEngineLabel,
                          labelStyle: TextStyle(
                            color: context.themeColors.textMuted,
                            fontSize: 12,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppDesignSystem.space3,
                            vertical: AppDesignSystem.space2,
                          ),
                          isDense: true,
                        ),
                        items: _engines
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _engine = value!),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _charset,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.connCharset,
                        labelStyle: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 12,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space3,
                          vertical: AppDesignSystem.space2,
                        ),
                        isDense: true,
                      ),
                      items: _charsets
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _charset = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space2),
              TextFormField(
                controller: _commentController,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  labelText: l10n.connComment,
                  labelStyle: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 12,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space3,
                    vertical: AppDesignSystem.space2,
                  ),
                  isDense: true,
                ),
              ),
              // Doris 表模型 + 分桶（仅 Doris 连接渲染）
              if (context.read<AppProvider>().connection.currentServer?.type ==
                  DatabaseType.doris) ...[
                const SizedBox(height: AppDesignSystem.space2),
                _buildDorisOptionsRow(l10n),
                const SizedBox(height: AppDesignSystem.space2),
                _buildDorisPartitionSection(l10n),
              ],
              const SizedBox(height: AppDesignSystem.space3),
              TabBar(
                controller: _tabController,
                labelColor: context.themeColors.accentBlue,
                unselectedLabelColor: context.themeColors.textMuted,
                indicatorColor: context.themeColors.accentBlue,
                tabs: [
                  Tab(text: l10n.tableColumns),
                  Tab(text: l10n.tableIndexes),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildColumnsTab(isDoris: isDoris),
                    _buildIndexesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        LoadingButton(
          label: l10n.commonAdd,
          onPressed: _createTable,
          isLoading: _isLoading,
          backgroundColor: context.themeColors.accentBlue,
        ),
      ],
    );
  }

  Widget _buildColumnsTab({required bool isDoris}) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Column Definitions',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textMuted,
              ),
            ),
            TextButton.icon(
              onPressed: _addColumn,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(l10n.addColumn, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1),
        _buildColumnHeader(l10n, isDoris: isDoris),
        Expanded(
          child: ListView.builder(
            itemCount: _columns.length,
            itemBuilder: (context, index) =>
                _buildColumnRow(index, isDoris: isDoris),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnHeader(AppLocalizations l10n, {required bool isDoris}) {
    return Container(
      height: 26,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Row(
        children: [
          SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 100,
            child: Text(
              l10n.connName,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              'Type',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              'PK',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              'NN',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // AI（AUTO_INCREMENT）仅 MySQL 路径展示；Doris 使用键模型保证唯一性
          if (!isDoris)
            SizedBox(
              width: 32,
              child: Text(
                'AI',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          // AGGREGATE 聚合函数表头（仅 Doris + AGGREGATE）
          if (context.read<AppProvider>().connection.currentServer?.type ==
                  DatabaseType.doris &&
              _dorisModel == 'AGGREGATE')
            SizedBox(
              width: 70,
              child: Text(
                l10n.dorisAggregateFunctionLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: Text(
              l10n.connDefault,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(width: AppDesignSystem.space6),
        ],
      ),
    );
  }

  Widget _buildColumnRow(int index, {required bool isDoris}) {
    final l10n = AppLocalizations.of(context)!;
    final col = _columns[index];
    final effectiveDataTypes = isDoris ? _dorisDataTypes : _dataTypes;
    final selectedType = effectiveDataTypes.contains(col.dataType)
        ? col.dataType
        : null;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 100,
            child: TextFormField(
              controller: col.nameController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.connName,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 90,
            child: DropdownButtonFormField<String>(
              initialValue: selectedType,
              isExpanded: true,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              hint: Text(
                col.dataType,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              items: effectiveDataTypes
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => col.dataType = value!),
            ),
          ),
          SizedBox(
            width: 32,
            height: 22,
            child: Checkbox(
              value: col.isPrimaryKey,
              activeColor: context.themeColors.warning,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => setState(() => col.isPrimaryKey = value!),
            ),
          ),
          SizedBox(
            width: 32,
            height: 22,
            child: Checkbox(
              value: col.isNotNull,
              activeColor: context.themeColors.error,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => setState(() => col.isNotNull = value!),
            ),
          ),
          // AI（AUTO_INCREMENT）仅 MySQL 路径展示
          if (!isDoris)
            SizedBox(
              width: 32,
              height: 22,
              child: Checkbox(
                value: col.autoIncrement,
                activeColor: context.themeColors.accentBlue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) =>
                    setState(() => col.autoIncrement = value!),
              ),
            ),
          // AGGREGATE 值列聚合函数下拉（维度列/PK 留空对齐）
          if (context.read<AppProvider>().connection.currentServer?.type ==
                  DatabaseType.doris &&
              _dorisModel == 'AGGREGATE')
            col.isPrimaryKey
                ? const SizedBox(width: 70)
                : SizedBox(
                    width: 70,
                    child: DropdownButtonFormField<String>(
                      initialValue: col.aggregateFunction ?? 'SUM',
                      isExpanded: true,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 11,
                      ),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space1,
                          vertical: AppDesignSystem.space1,
                        ),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      items:
                          [
                                'SUM',
                                'MAX',
                                'MIN',
                                'REPLACE',
                                'BITMAP_UNION',
                                'HLL_UNION',
                                'REPLACE_IF_NOT_NULL',
                              ]
                              .map(
                                (fn) => DropdownMenuItem(
                                  value: fn,
                                  child: Text(
                                    fn,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (v) =>
                          setState(() => col.aggregateFunction = v),
                    ),
                  ),
          Expanded(
            child: TextFormField(
              controller: col.defaultValueController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.connDefault,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 22,
            child: IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 14,
                color: context.themeColors.error,
              ),
              onPressed: _columns.length > 1
                  ? () => _removeColumn(index)
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexesTab() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Index Definitions',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textMuted,
              ),
            ),
            TextButton.icon(
              onPressed: _addIndex,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(l10n.addIndex, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1),
        _buildIndexHeader(),
        Expanded(
          child: _indexes.isEmpty
              ? Center(
                  child: Text(
                    l10n.noIndexesClickToAdd,
                    style: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _indexes.length,
                  itemBuilder: (context, index) =>
                      _buildIndexRow(_indexes[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildIndexHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Row(
        children: [
          SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 120,
            child: Text(
              l10n.connIndexName,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              'Type',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Columns (comma separated)',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(width: AppDesignSystem.space6),
        ],
      ),
    );
  }

  Widget _buildIndexRow(_IndexDefinition idx, int index) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: idx.nameController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.connIndexName,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 80,
            child: DropdownButtonFormField<String>(
              initialValue: idx.indexType,
              isExpanded: true,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              items: [
                DropdownMenuItem(
                  value: 'INDEX',
                  child: Text(
                    l10n.indexTypeNormal,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                DropdownMenuItem(
                  value: 'UNIQUE',
                  child: Text(
                    l10n.indexTypeUnique,
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => idx.indexType = value!),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: idx.columnsController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.hintIndexColumns,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 22,
            child: IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 14,
                color: context.themeColors.error,
              ),
              onPressed: () => _removeIndex(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  void _addColumn() {
    setState(() => _columns.add(_ColumnDefinition()));
  }

  void _removeColumn(int index) {
    setState(() => _columns.removeAt(index));
  }

  void _addIndex() {
    setState(() => _indexes.add(_IndexDefinition()));
  }

  void _removeIndex(int index) {
    setState(() => _indexes.removeAt(index));
  }

  // Doris 表模型 + 分桶配置行（仅 Doris 连接渲染）
  Widget _buildDorisOptionsRow(AppLocalizations l10n) {
    final colNames = _columns
        .map((c) => c.nameController.text)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    final effectiveHash = colNames.contains(_dorisHashColumn)
        ? _dorisHashColumn
        : null;
    final tMuted = context.themeColors.textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: _dorisModel,
            decoration: InputDecoration(
              labelText: l10n.dorisTableModelLabel,
              labelStyle: TextStyle(color: tMuted, fontSize: 12),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: 'DUPLICATE',
                child: Text(l10n.dorisModelDuplicate),
              ),
              DropdownMenuItem(
                value: 'UNIQUE',
                child: Text(l10n.dorisModelUnique),
              ),
              DropdownMenuItem(
                value: 'PRIMARY KEY',
                child: Text(l10n.dorisModelPrimaryKey),
              ),
              // AGGREGATE 模型
              DropdownMenuItem(
                value: 'AGGREGATE',
                child: Text(l10n.dorisModelAggregate),
              ),
            ],
            onChanged: (v) => setState(() => _dorisModel = v ?? 'DUPLICATE'),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String?>(
            initialValue: effectiveHash,
            decoration: InputDecoration(
              labelText: l10n.dorisHashColumnLabel,
              labelStyle: TextStyle(color: tMuted, fontSize: 12),
              isDense: true,
            ),
            items: colNames
                .map((n) => DropdownMenuItem<String?>(value: n, child: Text(n)))
                .toList(),
            onChanged: (v) => setState(() => _dorisHashColumn = v),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          flex: 1,
          child: DropdownButtonFormField<int>(
            initialValue: _dorisBuckets,
            decoration: InputDecoration(
              labelText: l10n.dorisBucketsLabel,
              labelStyle: TextStyle(color: tMuted, fontSize: 12),
              isDense: true,
            ),
            items: [1, 3, 5, 8, 10, 16]
                .map((b) => DropdownMenuItem<int>(value: b, child: Text('$b')))
                .toList(),
            onChanged: (v) => setState(() => _dorisBuckets = v ?? 1),
          ),
        ),
      ],
    );
  }

  // RANGE 分区配置区（仅 Doris 连接渲染）
  Widget _buildDorisPartitionSection(AppLocalizations l10n) {
    final colNames = _columns
        .map((c) => c.nameController.text)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    final effectivePartCol = colNames.contains(_dorisPartitionColumn)
        ? _dorisPartitionColumn
        : null;
    final tMuted = context.themeColors.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.dorisPartitionColumn,
          style: TextStyle(fontSize: 11, color: tMuted),
        ),
        DropdownButtonFormField<String?>(
          initialValue: effectivePartCol,
          decoration: const InputDecoration(isDense: true),
          items: colNames
              .map((n) => DropdownMenuItem<String?>(value: n, child: Text(n)))
              .toList(),
          onChanged: (v) => setState(() => _dorisPartitionColumn = v),
        ),
        for (final entry in _partitions.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.value.nameController,
                    decoration: InputDecoration(
                      hintText: l10n.dorisPartitionName,
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextFormField(
                    controller: entry.value.lessThanController,
                    decoration: InputDecoration(
                      hintText: l10n.dorisPartitionLessThan,
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.circleMinus, size: 16),
                  onPressed: () => setState(() {
                    _partitions[entry.key].dispose();
                    _partitions.removeAt(entry.key);
                  }),
                ),
              ],
            ),
          ),
        TextButton.icon(
          icon: const Icon(LucideIcons.plus, size: 16),
          label: Text(l10n.dorisAddPartition),
          onPressed: () =>
              setState(() => _partitions.add(_PartitionDefinition())),
        ),
      ],
    );
  }

  Future<void> _createTable() async {
    if (!_formKey.currentState!.validate()) return;

    final validColumns = _columns
        .where((c) => c.nameController.text.isNotEmpty)
        .toList();
    if (validColumns.isEmpty) {
      AppErrorHandler.showErrorSnackBar(
        context,
        AppLocalizations.of(context)!.pleaseDefineAtLeastOneColumn,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = context.read<AppProvider>();
      if (!mounted) return;

      final columns = validColumns
          .map(
            (c) => DbColumn(
              name: c.nameController.text,
              type: c.dataType,
              isPrimaryKey: c.isPrimaryKey,
              isNullable: !c.isNotNull,
              defaultValue: c.defaultValueController.text.isEmpty
                  ? null
                  : c.defaultValueController.text,
            ),
          )
          .toList();

      // Doris 表模型 + 分桶 → options；UNIQUE/PK/AGGREGATE 须有键列（维度列）
      final isDoris =
          provider.connection.currentServer?.type == DatabaseType.doris;
      Map<String, dynamic>? dorisOptions;
      if (isDoris) {
        if ((_dorisModel == 'UNIQUE' ||
                _dorisModel == 'PRIMARY KEY' ||
                _dorisModel == 'AGGREGATE') &&
            !columns.any((c) => c.isPrimaryKey)) {
          if (mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              AppLocalizations.of(context)!.dorisModelNeedsKeyColumn,
            );
          }
          setState(() => _isLoading = false);
          return;
        }
        dorisOptions = {
          'model': _dorisModel,
          if (_dorisHashColumn != null) 'hashColumn': _dorisHashColumn,
          if (_dorisBuckets > 1) 'buckets': _dorisBuckets,
          // AGGREGATE 值列聚合函数（默认 SUM）内联构造
          if (_dorisModel == 'AGGREGATE')
            'aggregateColumns': {
              for (final c in validColumns)
                if (!c.isPrimaryKey)
                  c.nameController.text: c.aggregateFunction ?? 'SUM',
            },
          // RANGE 分区
          if (_dorisPartitionColumn != null)
            'partitionColumn': _dorisPartitionColumn,
          if (_partitions
              .where((p) => p.nameController.text.isNotEmpty)
              .isNotEmpty)
            'partitions': [
              for (final p in _partitions)
                if (p.nameController.text.isNotEmpty)
                  {
                    'name': p.nameController.text,
                    'lessThan': p.lessThanController.text,
                  },
            ],
        };
      }

      await provider.createTable(
        widget.dbName,
        _tableNameController.text,
        columns,
        comment: _commentController.text.isEmpty
            ? null
            : _commentController.text,
        engine: isDoris ? null : _engine,
        options: dorisOptions,
      );

      // 创建索引
      for (final idx in _indexes) {
        if (idx.nameController.text.isNotEmpty &&
            idx.columnsController.text.isNotEmpty) {
          final cols = idx.columnsController.text
              .split(',')
              .map((c) => c.trim())
              .where((c) => c.isNotEmpty)
              .toList();
          if (cols.isNotEmpty) {
            try {
              await provider.createIndex(
                widget.dbName,
                _tableNameController.text,
                idx.nameController.text,
                cols,
                unique: idx.indexType == 'UNIQUE',
              );
            } catch (e) {
              AppLogger.d('TableDialog', 'Index creation failed: $e');
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.commonSuccess),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.modifyFailed(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _ColumnDefinition {
  final nameController = TextEditingController();
  String dataType = 'INT';
  bool isPrimaryKey = false;
  bool isNotNull = false;
  bool autoIncrement = false;
  final defaultValueController = TextEditingController();
  // Doris AGGREGATE 模型值列聚合函数（仅 AGGREGATE 用）
  String? aggregateFunction;

  void dispose() {
    nameController.dispose();
    defaultValueController.dispose();
  }
}

// RANGE 分区定义
class _PartitionDefinition {
  final nameController = TextEditingController();
  final lessThanController = TextEditingController();
  void dispose() {
    nameController.dispose();
    lessThanController.dispose();
  }
}

class _IndexDefinition {
  final nameController = TextEditingController();
  String indexType = 'INDEX';
  final columnsController = TextEditingController();

  void dispose() {
    nameController.dispose();
    columnsController.dispose();
  }
}

class CreatePostgresTableDialog extends StatefulWidget {
  final String dbName;

  /// DBT-T19：建表执行注入缝（默认 = provider.createTable；widget 测试断言面）。
  @visibleForTesting
  final PgTableCreator? tableCreator;

  /// DBT-T19：分区 DDL 审计注入缝（默认 = [auditPgPartitionDdl]；测试断言面）。
  @visibleForTesting
  final Future<void> Function(PgPartitionAuditRecord record)? partitionAuditor;

  const CreatePostgresTableDialog({
    super.key,
    required this.dbName,
    this.tableCreator,
    this.partitionAuditor,
  });

  /// DBT-T19（W-16）：分区表单值 → options['pgPartition'] 序列化（纯函数，
  /// widget 测试逐字断言面；与 adapter `pgPartition` 协议一致）。
  ///
  /// [column] 为空或无有效分区行 → null（不分区，走既有裸建表路径零变化）。
  static Map<String, dynamic>? pgPartitionOptions(
    String strategy,
    String? column,
    List<(String, String)> partitions,
  ) {
    if (column == null || column.isEmpty) return null;
    final valid = <Map<String, dynamic>>[
      for (final p in partitions)
        if (p.$1.isNotEmpty && p.$2.isNotEmpty)
          {'name': p.$1, 'values': p.$2},
    ];
    return {
      'pgPartition': {
        'strategy': strategy,
        'column': column,
        if (valid.isNotEmpty) 'partitions': valid,
      },
    };
  }

  @override
  State<CreatePostgresTableDialog> createState() =>
      _CreatePostgresTableDialogState();
}

class _CreatePostgresTableDialogState extends State<CreatePostgresTableDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _tableNameController = TextEditingController();
  final _commentController = TextEditingController();
  // DBT-T19（W-16）：PG 声明式分区——死线三断点接线（此前分区 UI 是 Doris
  // 死代码副本：渲染被 type==doris 门死、提交从不读 _partitions、adapter
  // 忽略 options）。分区键列 null = 不分区（缺省，走既有裸建表路径）。
  String _pgPartitionStrategy = 'RANGE';
  String? _pgPartitionColumn;
  final List<_PartitionDefinition> _partitions = [];
  String _schema = 'public';
  String _tablespace = 'pg_default';
  final List<_PgColumnDefinition> _columns = [_PgColumnDefinition()];
  final List<_PgIndexDefinition> _indexes = [];
  bool _isLoading = false;
  late TabController _tabController;

  // 技术字符串（SQL 字面量示例，非文案——同本文件 'BTREE'/'GIN' 下拉项先例）：
  // RANGE 边界 = 上界表达式（10 / '2026-11-01' / MAXVALUE，链式下界自动推导）；
  // LIST 边界 = 值列表内容。
  static const String _pgListBoundHint = "e.g. 'a', 'b'";

  final List<String> _schemas = ['public', 'information_schema'];
  final List<String> _tablespaces = ['pg_default', 'pg_global', 'pg_local'];
  final List<String> _dataTypes = [
    'INTEGER',
    'BIGINT',
    'SMALLINT',
    'SERIAL',
    'BIGSERIAL',
    'SMALLSERIAL',
    'DECIMAL',
    'NUMERIC',
    'REAL',
    'DOUBLE PRECISION',
    'VARCHAR(255)',
    'CHAR(50)',
    'TEXT',
    'BOOLEAN',
    'DATE',
    'TIME',
    'TIMESTAMP',
    'TIMESTAMPTZ',
    'INTERVAL',
    'UUID',
    'JSON',
    'JSONB',
    'BYTEA',
    'INET',
    'CIDR',
    'MACADDR',
    'ARRAY',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tableNameController.dispose();
    _commentController.dispose();
    _tabController.dispose();
    for (final col in _columns) {
      col.dispose();
    }
    for (final idx in _indexes) {
      idx.dispose();
    }
    // DBT-T19：分区行控制器释放（此前分区 UI 为死代码、从不 dispose）。
    for (final part in _partitions) {
      part.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        l10n.tableCreateNewTable,
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: SizedBox(
        width: 750,
        height: 520,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _schema,
                      isExpanded: true,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.dbDialogSchema,
                        labelStyle: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 12,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space3,
                          vertical: AppDesignSystem.space2,
                        ),
                        isDense: true,
                      ),
                      items: _schemas
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _schema = value!),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _tableNameController,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.tableName,
                        labelStyle: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 12,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space3,
                          vertical: AppDesignSystem.space2,
                        ),
                        isDense: true,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.enterTableName;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _tablespace,
                      isExpanded: true,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.dbDialogTablespace,
                        labelStyle: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 12,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space3,
                          vertical: AppDesignSystem.space2,
                        ),
                        isDense: true,
                      ),
                      items: _tablespaces
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _tablespace = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space2),
              TextFormField(
                controller: _commentController,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  labelText: l10n.connComment,
                  labelStyle: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 12,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space3,
                    vertical: AppDesignSystem.space2,
                  ),
                  isDense: true,
                ),
              ),
              // DBT-T19（W-16）：PG 分区节——此前为 Doris 死代码副本（type==doris
              // 条件对 PG 连接永不真），接线为 PG 声明式分区配置（始终渲染）。
              const SizedBox(height: AppDesignSystem.space2),
              _buildPgPartitionSection(l10n),
              const SizedBox(height: AppDesignSystem.space3),
              TabBar(
                controller: _tabController,
                labelColor: context.themeColors.accentBlue,
                unselectedLabelColor: context.themeColors.textMuted,
                indicatorColor: context.themeColors.accentBlue,
                tabs: [
                  Tab(text: l10n.tableColumns),
                  Tab(text: l10n.tableIndexes),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildColumnsTab(), _buildIndexesTab()],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        LoadingButton(
          label: l10n.commonAdd,
          onPressed: _createTable,
          isLoading: _isLoading,
          backgroundColor: context.themeColors.accentBlue,
        ),
      ],
    );
  }

  Widget _buildColumnsTab() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Column Definitions',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textMuted,
              ),
            ),
            TextButton.icon(
              onPressed: _addColumn,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(l10n.addColumn, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1),
        _buildColumnHeader(l10n),
        Expanded(
          child: ListView.builder(
            itemCount: _columns.length,
            itemBuilder: (context, index) => _buildColumnRow(index),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnHeader(AppLocalizations l10n) {
    return Container(
      height: 26,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 100,
            child: Text(
              l10n.connName,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              'Type',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              'PK',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              'NN',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              l10n.connDefault,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space6),
        ],
      ),
    );
  }

  Widget _buildColumnRow(int index) {
    final l10n = AppLocalizations.of(context)!;
    final col = _columns[index];
    final selectedType = _dataTypes.contains(col.dataType)
        ? col.dataType
        : null;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 100,
            child: TextFormField(
              controller: col.nameController,
              // DBT-T19：列名变更即时刷新分区键下拉的候选列（分区节读取
              // 已定义列；此前无 onChanged，下拉候选为陈旧快照）。
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.connName,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<String>(
              initialValue: selectedType,
              isExpanded: true,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              hint: Text(
                col.dataType,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              items: _dataTypes
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => col.dataType = value!),
            ),
          ),
          SizedBox(
            width: 28,
            height: 22,
            child: Checkbox(
              value: col.isPrimaryKey,
              activeColor: context.themeColors.warning,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => setState(() => col.isPrimaryKey = value!),
            ),
          ),
          SizedBox(
            width: 28,
            height: 22,
            child: Checkbox(
              value: col.isNotNull,
              activeColor: context.themeColors.error,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => setState(() => col.isNotNull = value!),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: col.defaultValueController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.connDefault,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 22,
            child: IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 14,
                color: context.themeColors.error,
              ),
              onPressed: _columns.length > 1
                  ? () => _removeColumn(index)
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexesTab() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Index Definitions',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textMuted,
              ),
            ),
            TextButton.icon(
              onPressed: _addIndex,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: Text(l10n.addIndex, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space1),
        _buildIndexHeader(),
        Expanded(
          child: _indexes.isEmpty
              ? Center(
                  child: Text(
                    l10n.noIndexesClickToAdd,
                    style: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _indexes.length,
                  itemBuilder: (context, index) =>
                      _buildIndexRow(_indexes[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildIndexHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 120,
            child: Text(
              l10n.connIndexName,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              'Type',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Columns (comma separated)',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space6),
        ],
      ),
    );
  }

  Widget _buildIndexRow(_PgIndexDefinition idx, int index) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(
        left: AppDesignSystem.space1,
        right: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: idx.nameController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.connIndexName,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 100,
            child: DropdownButtonFormField<String>(
              initialValue: idx.indexType,
              isExpanded: true,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'INDEX',
                  child: Text('BTREE', style: TextStyle(fontSize: 11)),
                ),
                DropdownMenuItem(
                  value: 'UNIQUE',
                  child: Text('UNIQUE', style: TextStyle(fontSize: 11)),
                ),
                DropdownMenuItem(
                  value: 'GIN',
                  child: Text('GIN', style: TextStyle(fontSize: 11)),
                ),
                DropdownMenuItem(
                  value: 'GIST',
                  child: Text('GIST', style: TextStyle(fontSize: 11)),
                ),
              ],
              onChanged: (value) => setState(() => idx.indexType = value!),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: idx.columnsController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              decoration: InputDecoration(
                hintText: l10n.hintIndexColumns,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: AppDesignSystem.space1,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 22,
            child: IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 14,
                color: context.themeColors.error,
              ),
              onPressed: () => _removeIndex(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  void _addColumn() {
    setState(() => _columns.add(_PgColumnDefinition()));
  }

  void _removeColumn(int index) {
    setState(() => _columns.removeAt(index));
  }

  void _addIndex() {
    setState(() => _indexes.add(_PgIndexDefinition()));
  }

  void _removeIndex(int index) {
    setState(() => _indexes.removeAt(index));
  }

  // ── DBT-T19（W-16）：PG 分区配置区（替换自 Doris 死代码副本）──────────
  // 策略 RANGE/LIST（PG 声明式分区关键字，技术字符串）；分区键列下拉 =
  // 已定义列；未选分区键 = 不分区。分区行复用 _PartitionDefinition
  //（name + 边界），RANGE 边界 = 上界表达式、LIST 边界 = 值列表内容。
  Widget _buildPgPartitionSection(AppLocalizations l10n) {
    final colNames = _columns
        .map((c) => c.nameController.text)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    final effectivePartCol = colNames.contains(_pgPartitionColumn)
        ? _pgPartitionColumn
        : null;
    final tMuted = context.themeColors.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.pgPartitionSectionTitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tMuted,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _pgPartitionStrategy,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.pgPartitionStrategy,
                  labelStyle: TextStyle(color: tMuted, fontSize: 12),
                  isDense: true,
                ),
                items: ['RANGE', 'LIST']
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => _pgPartitionStrategy = v ?? 'RANGE'),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: effectivePartCol,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.pgPartitionColumn,
                  labelStyle: TextStyle(color: tMuted, fontSize: 12),
                  isDense: true,
                ),
                items: colNames
                    .map(
                      (n) => DropdownMenuItem<String?>(value: n, child: Text(n)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _pgPartitionColumn = v),
              ),
            ),
          ],
        ),
        for (final entry in _partitions.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.value.nameController,
                    key: Key('pg_partition_name_${entry.key}'),
                    decoration: InputDecoration(
                      hintText: l10n.dorisPartitionName,
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextFormField(
                    controller: entry.value.lessThanController,
                    key: Key('pg_partition_bound_${entry.key}'),
                    decoration: InputDecoration(
                      // RANGE 边界语义 = 上界（与 Doris lessThan 同语义复用）；
                      // LIST 为值列表（SQL 字面量示例，技术字符串）。
                      hintText: _pgPartitionStrategy == 'RANGE'
                          ? l10n.dorisPartitionLessThan
                          : _pgListBoundHint,
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.circleMinus, size: 16),
                  onPressed: () => setState(() {
                    _partitions[entry.key].dispose();
                    _partitions.removeAt(entry.key);
                  }),
                ),
              ],
            ),
          ),
        TextButton.icon(
          key: const Key('pg_partition_add'),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: Text(l10n.dorisAddPartition),
          onPressed: () =>
              setState(() => _partitions.add(_PartitionDefinition())),
        ),
      ],
    );
  }

  /// 分区 DDL mono 预览（预览 = 执行同一构造函数：SQL 与 adapter 执行
  /// 同源 PostgreSQLAdapter.buildPgPartitionDdl，「无假保存」铁律①）。
  Widget _pgDdlPreview(BuildContext context, String sql) {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              sql,
              key: const Key('pg_partition_ddl_preview'),
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// DBT-T19：分区 DDL 审计（成功/失败均落；写失败不阻塞 UI，AppLogger 记录）。
  Future<void> _auditPartition(
    AppProvider provider,
    String? sql,
    Duration elapsed, {
    required bool success,
    String? errorMessage,
  }) async {
    if (sql == null) return;
    final audit = widget.partitionAuditor ?? auditPgPartitionDdl;
    try {
      await audit((
        connectionId: provider.connection.currentServer?.id ?? '',
        databaseName: widget.dbName,
        sql: sql,
        executionTime: elapsed,
        success: success,
        errorMessage: errorMessage,
      ));
    } catch (e) {
      AppLogger.e('PgTableDialog', 'audit write failed', e);
    }
  }

  Future<void> _createTable() async {
    if (!_formKey.currentState!.validate()) return;

    final validColumns = _columns
        .where((c) => c.nameController.text.isNotEmpty)
        .toList();
    if (validColumns.isEmpty) {
      AppErrorHandler.showErrorSnackBar(
        context,
        AppLocalizations.of(context)!.pleaseDefineAtLeastOneColumn,
      );
      return;
    }

    setState(() => _isLoading = true);

    // DBT-T19：分区 DDL（预览 = 执行同一 SQL；非分区路径恒 null）。
    String? partitionDdl;
    final stopwatch = Stopwatch()..start();
    try {
      final provider = context.read<AppProvider>();
      if (!mounted) return;

      final columns = validColumns
          .map(
            (c) => DbColumn(
              name: c.nameController.text,
              type: c.dataType,
              isPrimaryKey: c.isPrimaryKey,
              isNullable: !c.isNotNull,
              defaultValue: c.defaultValueController.text.isEmpty
                  ? null
                  : c.defaultValueController.text,
            ),
          )
          .toList();

      final fullTableName = '$_schema.${_tableNameController.text}';

      // ── DBT-T19 分区分支（死线断点②：提交此前从不读 _partitions）─────
      final colNames = columns.map((c) => c.name).toSet();
      final partColumn =
          colNames.contains(_pgPartitionColumn) ? _pgPartitionColumn : null;
      Map<String, dynamic>? pgOptions;
      if (partColumn != null) {
        final l10n = AppLocalizations.of(context)!;
        // readonly 入口前置拦截（UX 收口）；服务层 _isWriteQuery CREATE
        // 关键字 + adapter guardReadOnly 为硬保证（fail-closed 既有）。
        if (provider.connection.currentServer?.readOnly == true) {
          setState(() => _isLoading = false);
          AppErrorHandler.showErrorSnackBar(context, l10n.readOnlyModeBlocked);
          return;
        }
        // 硬校验：有 PK 列时必须包含分区键（引擎会拒绝——前置拦截不出
        // 半成品 SQL；无 PK 的分区表合法，不强制）。
        final pkNames = columns
            .where((c) => c.isPrimaryKey)
            .map((c) => c.name)
            .toSet();
        if (pkNames.isNotEmpty && !pkNames.contains(partColumn)) {
          setState(() => _isLoading = false);
          AppErrorHandler.showErrorSnackBar(
            context,
            l10n.pgPartitionNeedsPk(partColumn),
          );
          return;
        }
        // 分区行收集 + 边界轻校验（空名/空界拒绝；语句分隔符与注释串 =
        // 注入面防御——边界本为 DDL 字面量片段，引擎错误原文兜底）。
        for (final p in _partitions) {
          final name = p.nameController.text.trim();
          final values = p.lessThanController.text.trim();
          if (name.isEmpty && values.isEmpty) continue;
          if (name.isEmpty || values.isEmpty) {
            setState(() => _isLoading = false);
            AppErrorHandler.showErrorSnackBar(context, l10n.commonRequired);
            return;
          }
          if (values.contains(';') ||
              values.contains('--') ||
              values.contains('/*')) {
            setState(() => _isLoading = false);
            AppErrorHandler.showErrorSnackBar(context, l10n.commonFailed);
            return;
          }
        }
        final partitionRows = [
          for (final p in _partitions)
            (p.nameController.text.trim(), p.lessThanController.text.trim()),
        ];
        pgOptions = CreatePostgresTableDialog.pgPartitionOptions(
          _pgPartitionStrategy,
          partColumn,
          partitionRows,
        );
        if (pgOptions != null) {
          // DDL 预览门（R4-d 先例：barrierDismissible:false；SQL 与 adapter
          // 执行同源 buildPgPartitionDdl）。
          final ddlSql = PostgreSQLAdapter.buildPgPartitionDdl(
            fullTableName,
            columns,
            strategy: _pgPartitionStrategy,
            column: partColumn,
            partitions: [
              for (final r in partitionRows) (name: r.$1, values: r.$2),
            ],
          ).join(';\n');
          partitionDdl = ddlSql;
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => DestructiveConfirmDialog(
              icon: LucideIcons.table2,
              title: l10n.tableCreateNewTable,
              impactDescription:
                  '${l10n.pgPartitionSectionTitle} · $_pgPartitionStrategy'
                  '($partColumn)',
              impactTone: DestructiveTone.warning,
              confirmLabel: l10n.commonConfirm,
              contentWidth: 620,
              extraContent: _pgDdlPreview(context, ddlSql),
              onConfirm: () => Navigator.of(context).pop(true),
            ),
          );
          if (confirmed != true) {
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      final create = widget.tableCreator ?? provider.createTable;
      final ok = await create(
        widget.dbName,
        fullTableName,
        columns,
        comment: _commentController.text.isEmpty
            ? null
            : _commentController.text,
        options: pgOptions,
      );
      stopwatch.stop();
      // 引擎失败不再假成功：分区路径失败经 adapter 重抛走 catch（引擎错误
      // 原文）；普通路径 false 亦不再弹「成功」+关窗（此前 false 仍报成功
      // 为既有缺陷，DBT-T19 接线时修复——详见任务回报）。
      if (!ok) {
        await _auditPartition(
          provider,
          partitionDdl,
          stopwatch.elapsed,
          success: false,
          errorMessage: 'createTable returned false',
        );
        if (mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            AppLocalizations.of(context)!.commonFailed,
          );
        }
        return;
      }
      await _auditPartition(
        provider,
        partitionDdl,
        stopwatch.elapsed,
        success: true,
      );

      for (final idx in _indexes) {
        if (idx.nameController.text.isNotEmpty &&
            idx.columnsController.text.isNotEmpty) {
          final cols = idx.columnsController.text
              .split(',')
              .map((c) => c.trim())
              .where((c) => c.isNotEmpty)
              .toList();
          if (cols.isNotEmpty) {
            try {
              await provider.createIndex(
                widget.dbName,
                fullTableName,
                idx.nameController.text,
                cols,
                unique: idx.indexType == 'UNIQUE',
              );
            } catch (e) {
              AppLogger.d('PgTableDialog', 'Index creation failed: $e');
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.commonSuccess),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    } catch (e) {
      stopwatch.stop();
      if (partitionDdl != null && mounted) {
        await _auditPartition(
          context.read<AppProvider>(),
          partitionDdl,
          stopwatch.elapsed,
          success: false,
          errorMessage: e.toString(),
        );
      }
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.modifyFailed(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _PgColumnDefinition {
  final nameController = TextEditingController();
  String dataType = 'INTEGER';
  bool isPrimaryKey = false;
  bool isNotNull = false;
  final defaultValueController = TextEditingController();

  void dispose() {
    nameController.dispose();
    defaultValueController.dispose();
  }
}

class _PgIndexDefinition {
  final nameController = TextEditingController();
  String indexType = 'INDEX';
  final columnsController = TextEditingController();

  void dispose() {
    nameController.dispose();
    columnsController.dispose();
  }
}
