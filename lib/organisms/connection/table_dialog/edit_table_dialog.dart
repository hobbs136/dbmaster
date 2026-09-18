import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../atoms/app_loading.dart';
import '../../../models/database_models.dart';
import '../../../l10n/app_localizations.dart';
import '../error_boundary.dart';
import '../../../theme/app_colors.dart';

class EditTableDialog extends StatefulWidget {
  final String dbName;
  final DbTable table;

  const EditTableDialog({super.key, required this.dbName, required this.table});

  @override
  State<EditTableDialog> createState() => _EditTableDialogState();
}

class _EditTableDialogState extends State<EditTableDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _tableNameController = TextEditingController();
  final _commentController = TextEditingController();
  List<_EditColumn> _columns = [];
  List<_EditIndex> _indexes = [];
  bool _isLoading = false;
  late TabController _tabController;

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
    _tableNameController.text = widget.table.name;
    // 初始化表注释
    _commentController.text = widget.table.comment ?? '';
    _columns = widget.table.columns
        .map((c) => _EditColumn.fromColumn(c))
        .toList();
    if (_columns.isEmpty) {
      _columns = [_EditColumn()];
    }
    _indexes = widget.table.indexes
        .map((i) => _EditIndex.fromIndex(i))
        .toList();
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
        l10n.tableEditTable,
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: SizedBox(
        width: 750,
        height: 480,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
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
                    _buildIndexesTab(isDoris: isDoris),
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
          label: l10n.commonSave,
          onPressed: _saveChanges,
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

  // isDoris 参数控制索引类型下拉选项（Doris 仅 BITMAP/INVERTED，无 UNIQUE）
  Widget _buildIndexesTab({required bool isDoris}) {
    final l10n = AppLocalizations.of(context)!;
    final visibleIndexes = _indexes.where((i) => !i.isDeleted).toList();
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
          child: visibleIndexes.isEmpty
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
                  itemCount: visibleIndexes.length,
                  itemBuilder: (context, index) =>
                      _buildIndexRow(visibleIndexes[index], isDoris: isDoris),
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

  // isDoris 参数 — Doris 仅支持 BITMAP/INVERTED 索引，隐藏 UNIQUE 选项
  Widget _buildIndexRow(_EditIndex idx, {required bool isDoris}) {
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
              initialValue: isDoris ? 'INDEX' : idx.indexType,
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
                // Doris 不显示 UNIQUE（仅支持 BITMAP/INVERTED 索引）
                if (!isDoris)
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
              onPressed: () => _removeIndex(idx),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  void _addColumn() {
    setState(() => _columns.add(_EditColumn(isNew: true)));
  }

  void _removeColumn(int index) {
    setState(() {
      _columns[index].isDeleted = true;
      if (_columns.where((c) => !c.isDeleted).isEmpty) {
        _columns.add(_EditColumn());
      }
    });
  }

  void _addIndex() {
    setState(() => _indexes.add(_EditIndex(isNew: true)));
  }

  void _removeIndex(_EditIndex idx) {
    setState(() {
      idx.isDeleted = true;
    });
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final provider = context.read<AppProvider>();
      // 提前读取 isDoris，避免 async gap 后使用 context
      final isDoris =
          provider.connection.currentServer?.type == DatabaseType.doris;

      // 重命名表
      if (_tableNameController.text != widget.table.name) {
        await provider.renameTable(
          widget.dbName,
          widget.table.name,
          _tableNameController.text,
        );
      }

      // 处理列的变更
      for (final col in _columns) {
        if (col.isDeleted && !col.isNew) {
          await provider.dropColumn(
            widget.dbName,
            _tableNameController.text,
            col.originalName,
          );
        } else if (col.isNew &&
            !col.isDeleted &&
            col.nameController.text.isNotEmpty) {
          // 增加 isPrimaryKey 持久化
          await provider.addColumn(
            widget.dbName,
            _tableNameController.text,
            DbColumn(
              name: col.nameController.text,
              type: col.dataType,
              isNullable: !col.isNotNull,
              isPrimaryKey: col.isPrimaryKey,
              defaultValue: col.defaultValueController.text.isEmpty
                  ? null
                  : col.defaultValueController.text,
            ),
          );
        } else if (!col.isNew && !col.isDeleted) {
          final originalCol = widget.table.columns.firstWhere(
            (c) => c.name == col.originalName,
            orElse: () => DbColumn(name: '', type: ''),
          );

          final nameChanged = col.nameController.text != col.originalName;
          final newIsNullable = !col.isNotNull;
          final typeChanged = col.dataType != originalCol.type;
          final nullableChanged = newIsNullable != originalCol.isNullable;
          final defaultChanged =
              col.defaultValueController.text !=
              (originalCol.defaultValue ?? '');

          // 列重命名 — 先 RENAME COLUMN 再 MODIFY COLUMN
          // （Doris 不支持 MySQL CHANGE COLUMN 改名+改类型一体）
          if (nameChanged && col.nameController.text.isNotEmpty) {
            await provider.renameColumn(
              widget.dbName,
              _tableNameController.text,
              col.originalName,
              col.nameController.text,
            );
          }

          // 增加 isPrimaryKey 持久化 + 列名变更检测
          if (typeChanged || nullableChanged || defaultChanged) {
            await provider.modifyColumn(
              widget.dbName,
              _tableNameController.text,
              col.originalName,
              DbColumn(
                name: col.nameController.text,
                type: col.dataType,
                isNullable: newIsNullable,
                isPrimaryKey: col.isPrimaryKey,
                defaultValue: col.defaultValueController.text.isEmpty
                    ? null
                    : col.defaultValueController.text,
              ),
            );
          }
        }
      }

      // 处理索引的变更
      // 收集索引操作错误，保存完成后统一提示用户
      final indexErrors = <String>[];
      for (final idx in _indexes) {
        if (idx.isDeleted && !idx.isNew) {
          try {
            await provider.dropIndex(
              widget.dbName,
              _tableNameController.text,
              idx.originalName,
            );
          } catch (e) {
            indexErrors.add('Drop index "${idx.originalName}": $e');
          }
        } else if (idx.isNew &&
            !idx.isDeleted &&
            idx.nameController.text.isNotEmpty &&
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
              indexErrors.add('Create index "${idx.nameController.text}": $e');
            }
          }
        }
      }

      // 保存表注释（isDoris 已在方法顶部预读，避免 async gap）
      if (_commentController.text.trim() != (widget.table.comment ?? '')) {
        final newComment = _commentController.text.trim();
        if (isDoris) {
          // Doris: ALTER TABLE ... MODIFY COMMENT
          final escapedComment = newComment.replaceAll("'", "\\'");
          await provider.dbService.executeQuery(
            "ALTER TABLE `${_tableNameController.text}` MODIFY COMMENT '$escapedComment'",
          );
        } else {
          await provider.dbService.executeQuery(
            "ALTER TABLE `${_tableNameController.text}` COMMENT = '${newComment.replaceAll("'", "\\'")}'",
          );
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        if (indexErrors.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.modifyFailed(
                  '${AppLocalizations.of(context)!.tableModified}; ${indexErrors.length} index operation(s) failed',
                ),
              ),
              backgroundColor: context.themeColors.warning,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.tableModified),
              backgroundColor: context.themeColors.success,
            ),
          );
        }
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

class _EditColumn {
  final String originalName;
  final nameController = TextEditingController();
  String dataType;
  bool isPrimaryKey;
  bool isNotNull;
  bool autoIncrement = false;
  final defaultValueController = TextEditingController();
  bool isNew;
  bool isDeleted = false;

  _EditColumn({
    this.originalName = '',
    this.dataType = 'VARCHAR(255)',
    this.isPrimaryKey = false,
    this.isNotNull = false,
    this.isNew = false,
  });

  void dispose() {
    nameController.dispose();
    defaultValueController.dispose();
  }

  factory _EditColumn.fromColumn(DbColumn col) {
    final edit = _EditColumn(
      originalName: col.name,
      dataType: col.type,
      isPrimaryKey: col.isPrimaryKey,
      isNotNull: !col.isNullable,
      isNew: false,
    );
    edit.nameController.text = col.name;
    edit.defaultValueController.text = col.defaultValue ?? '';
    return edit;
  }
}

class _EditIndex {
  final String originalName;
  final nameController = TextEditingController();
  String indexType;
  final columnsController = TextEditingController();
  bool isNew;
  bool isDeleted = false;

  _EditIndex({
    this.originalName = '',
    this.indexType = 'INDEX',
    this.isNew = false,
  });

  void dispose() {
    nameController.dispose();
    columnsController.dispose();
  }

  factory _EditIndex.fromIndex(DbIndex idx) {
    final edit = _EditIndex(
      originalName: idx.name,
      indexType: idx.isUnique ? 'UNIQUE' : 'INDEX',
      isNew: false,
    );
    edit.nameController.text = idx.name;
    edit.columnsController.text = idx.columns.join(', ');
    return edit;
  }
}
