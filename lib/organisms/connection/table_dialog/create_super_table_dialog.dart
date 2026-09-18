import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../atoms/app_loading.dart';
import '../../../models/tdengine_models.dart';
import '../../../utils/app_logger.dart';
import '../../../services/adapters/tdengine_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../error_boundary.dart';
import '../../../theme/app_colors.dart';

/// TDengine 创建超级表对话框
class CreateSuperTableDialog extends StatefulWidget {
  final String dbName;

  const CreateSuperTableDialog({super.key, required this.dbName});

  @override
  State<CreateSuperTableDialog> createState() => _CreateSuperTableDialogState();
}

class _CreateSuperTableDialogState extends State<CreateSuperTableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _tableNameController = TextEditingController();
  final _commentController = TextEditingController();
  final List<_ColumnDefinition> _columns = [
    _ColumnDefinition(name: 'ts', type: 'TIMESTAMP', isPrimaryKey: true),
  ];
  final List<_TagDefinition> _tags = [_TagDefinition()];
  bool _isLoading = false;

  final List<String> _dataTypes = [
    'TIMESTAMP',
    'INT',
    'BIGINT',
    'FLOAT',
    'DOUBLE',
    'BINARY(64)',
    'BINARY(128)',
    'BINARY(256)',
    'NCHAR(64)',
    'NCHAR(128)',
    'NCHAR(256)',
    'BOOL',
    'JSON',
  ];

  @override
  void dispose() {
    _tableNameController.dispose();
    _commentController.dispose();
    for (final col in _columns) {
      col.dispose();
    }
    for (final tag in _tags) {
      tag.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 700,
        height: 550,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Icon(
                    LucideIcons.folderBookmark,
                    color: context.themeColors.accentPurple,
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Text(
                    l10n.createSuperTableTitle,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSize2xl,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      color: context.themeColors.textMuted,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space4),

              // 表名和注释
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _tableNameController,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.sidebarSuperTableName,
                        labelStyle: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 12,
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space3,
                          vertical: AppDesignSystem.space2_5,
                        ),
                        isDense: true,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.dlgNameRequired;
                        }
                        if (!_isValidIdentifier(value)) {
                          return l10n.commonInvalidIdentifier;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _commentController,
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.sidebarCommentOptional,
                        labelStyle: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 12,
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space3,
                          vertical: AppDesignSystem.space2_5,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space4),

              // 列定义
              _buildSectionHeader(
                l10n.superTableColumns,
                LucideIcons.columns2,
                _addColumn,
              ),
              const SizedBox(height: AppDesignSystem.space1),
              _buildColumnHeader(),
              Expanded(
                flex: 2,
                child: ListView.builder(
                  itemCount: _columns.length,
                  itemBuilder: (context, index) => _buildColumnRow(index),
                ),
              ),
              const SizedBox(height: AppDesignSystem.space3),

              // 标签定义
              _buildSectionHeader(
                l10n.superTableTags,
                LucideIcons.tag,
                _addTag,
              ),
              const SizedBox(height: AppDesignSystem.space1),
              _buildTagHeader(),
              Expanded(
                flex: 2,
                child: ListView.builder(
                  itemCount: _tags.length,
                  itemBuilder: (context, index) => _buildTagRow(index),
                ),
              ),
              const SizedBox(height: AppDesignSystem.space4),

              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  LoadingButton(
                    label: l10n.createSuperTableTitle,
                    onPressed: _createSuperTable,
                    isLoading: _isLoading,
                    backgroundColor: context.themeColors.accentPurple,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, VoidCallback onAdd) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: context.themeColors.accentPurple),
            const SizedBox(width: AppDesignSystem.space1_5),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textPrimary,
              ),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: Icon(
            LucideIcons.plus,
            size: 14,
            color: context.themeColors.accentPurple,
          ),
          label: Text(
            'Add',
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.accentPurple,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
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
              'Name',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              'Type',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              'PK',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              'Length (for BINARY/NCHAR)',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
                fontWeight: FontWeight.w500,
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
    final selectedType = _dataTypes.contains(col.type) ? col.type : null;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
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
              controller: col.nameController,
              enabled: index > 0, // 第一列 ts 不可编辑
              style: TextStyle(
                color: index > 0
                    ? context.themeColors.textPrimary
                    : context.themeColors.textMuted,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.sidebarColumnNameHint,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              validator: (value) {
                if (index == 0) return null; // ts 已预设
                if (value == null || value.isEmpty) {
                  return l10n.commonRequired;
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<String>(
              initialValue: selectedType,
              isExpanded: true,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
                isDense: true,
                border: InputBorder.none,
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
              onChanged: index > 0
                  ? (value) => setState(() => col.type = value!)
                  : null,
            ),
          ),
          SizedBox(
            width: 50,
            height: 24,
            child: Checkbox(
              value: col.isPrimaryKey,
              activeColor: context.themeColors.accentPurple,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: index == 0
                  ? null // 第一列默认是主键
                  : (value) => setState(() => col.isPrimaryKey = value!),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: col.lengthController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText:
                    col.type.contains('BINARY') || col.type.contains('NCHAR')
                    ? 'e.g. 64'
                    : 'N/A',
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: index > 0
                ? IconButton(
                    icon: Icon(
                      LucideIcons.trash2,
                      size: 14,
                      color: context.themeColors.error,
                    ),
                    onPressed: () => _removeColumn(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTagHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 150,
            child: Text(
              'Tag Name',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              'Type',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Length',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space6),
        ],
      ),
    );
  }

  Widget _buildTagRow(int index) {
    final l10n = AppLocalizations.of(context)!;
    final tag = _tags[index];
    final selectedType = _dataTypes.contains(tag.type) ? tag.type : null;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: AppDesignSystem.space1),
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: tag.nameController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.sidebarTagNameHint,
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.commonRequired;
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: selectedType,
              isExpanded: true,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
              items: _dataTypes
                  .where((t) => t != 'TIMESTAMP' && t != 'JSON') // 标签不支持这些类型
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
              onChanged: (value) => setState(() => tag.type = value!),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: tag.lengthController,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText:
                    tag.type.contains('BINARY') || tag.type.contains('NCHAR')
                    ? 'e.g. 64'
                    : 'N/A',
                hintStyle: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              icon: Icon(
                LucideIcons.trash2,
                size: 14,
                color: context.themeColors.error,
              ),
              onPressed: _tags.length > 1 ? () => _removeTag(index) : null,
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
    if (_columns.length > 1 && index > 0) {
      setState(() => _columns.removeAt(index));
    }
  }

  void _addTag() {
    setState(() => _tags.add(_TagDefinition()));
  }

  void _removeTag(int index) {
    if (_tags.length > 1) {
      setState(() => _tags.removeAt(index));
    }
  }

  Future<void> _createSuperTable() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    // 验证列
    final validColumns = _columns
        .where((c) => c.nameController.text.isNotEmpty)
        .toList();

    if (validColumns.isEmpty || validColumns.first.type != 'TIMESTAMP') {
      AppErrorHandler.showErrorSnackBar(
        context,
        'First column must be TIMESTAMP',
      );
      return;
    }

    // 验证标签
    final validTags = _tags
        .where((t) => t.nameController.text.isNotEmpty)
        .toList();

    if (validTags.isEmpty) {
      AppErrorHandler.showErrorSnackBar(
        context,
        'At least one tag is required',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = context.read<AppProvider>();
      final adapter = provider.connection.dbService.currentAdapter;

      if (adapter is! TDengineAdapter) {
        throw Exception('Not connected to TDengine');
      }

      final columns = validColumns.map((c) {
        final type = c.type;
        int? length;
        if (type.contains('BINARY') || type.contains('NCHAR')) {
          final match = RegExp(r'\((\d+)\)').firstMatch(type);
          if (match != null) {
            length = int.tryParse(match.group(1)!);
          }
        }
        return TdColumn(
          name: c.nameController.text,
          type: type.replaceAll(RegExp(r'\(\d+\)'), '').trim(),
          length: length,
          isPrimaryKey: c.isPrimaryKey,
        );
      }).toList();

      final tags = validTags.map((t) {
        final type = t.type;
        int? length;
        if (type.contains('BINARY') || type.contains('NCHAR')) {
          final match = RegExp(r'\((\d+)\)').firstMatch(type);
          if (match != null) {
            length = int.tryParse(match.group(1)!);
          }
        }
        return TdTag(
          name: t.nameController.text,
          type: type.replaceAll(RegExp(r'\(\d+\)'), '').trim(),
          length: length,
        );
      }).toList();

      final success = await adapter.createSuperTable(
        name: _tableNameController.text,
        columns: columns,
        tags: tags,
        comment: _commentController.text.isEmpty
            ? null
            : _commentController.text,
      );

      if (success && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.superTableCreated),
            backgroundColor: context.themeColors.success,
          ),
        );
      } else if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, l10n.superTableCreateFailed);
      }
    } catch (e) {
      AppLogger.e('CreateSuperTableDialog', '创建超级表失败', e);
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.dbCreateError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isValidIdentifier(String name) {
    if (name.isEmpty) return false;
    if (RegExp(
      r'''[;\-\-\*/\\'"`\s!@#\$%\^\u0026\*\(\)\+={}\[\]|:\u003c\u003e,\?]''',
    ).hasMatch(name)) {
      return false;
    }
    return true;
  }
}

class _ColumnDefinition {
  late final TextEditingController nameController;
  String type;
  bool isPrimaryKey;
  final TextEditingController lengthController;

  _ColumnDefinition({
    String? name,
    this.type = 'INT',
    this.isPrimaryKey = false,
  }) : nameController = TextEditingController(text: name),
       lengthController = TextEditingController();

  void dispose() {
    nameController.dispose();
    lengthController.dispose();
  }
}

class _TagDefinition {
  final TextEditingController nameController;
  String type;
  final TextEditingController lengthController;

  _TagDefinition()
    : type = 'BINARY(64)',
      nameController = TextEditingController(),
      lengthController = TextEditingController();

  void dispose() {
    nameController.dispose();
    lengthController.dispose();
  }
}
