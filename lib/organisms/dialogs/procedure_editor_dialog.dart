import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/stored_procedure.dart';
import '../../services/stored_procedure_service.dart';
import '../../theme/app_theme.dart';
import '../connection/error_boundary.dart';
import '../connection/parameter_editor.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

class ProcedureEditorDialog extends StatefulWidget {
  final StoredProcedure? procedure; // null 表示创建新过程/函数
  final StoredProcedureService service;

  const ProcedureEditorDialog({
    super.key,
    this.procedure,
    required this.service,
  });

  @override
  State<ProcedureEditorDialog> createState() => _ProcedureEditorDialogState();
}

class _ProcedureEditorDialogState extends State<ProcedureEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _bodyController;
  late ProcedureType _selectedType;
  String? _selectedReturnType;
  List<ProcedureParameter> _parameters = [];
  bool _isLoading = false;

  static const List<String> _returnTypes = [
    'INT',
    'VARCHAR(255)',
    'TEXT',
    'DECIMAL(10,2)',
    'DATE',
    'DATETIME',
    'TIMESTAMP',
    'BOOLEAN',
    'FLOAT',
    'DOUBLE',
    'BIGINT',
    'SMALLINT',
    'TINYINT',
  ];

  @override
  void initState() {
    super.initState();
    final procedure = widget.procedure;
    _nameController = TextEditingController(text: procedure?.name ?? '');
    _bodyController = TextEditingController(text: procedure?.body ?? '');
    _selectedType = procedure?.type ?? ProcedureType.procedure;
    _selectedReturnType = procedure?.returnType;
    _parameters = procedure?.parameters ?? [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final procedure = StoredProcedure(
        name: _nameController.text.trim(),
        type: _selectedType,
        parameters: _parameters,
        returnType: _selectedReturnType,
        body: _bodyController.text.trim(),
      );

      if (widget.procedure != null) {
        // 更新
        await widget.service.update(procedure);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.dlgProcedureUpdated),
              backgroundColor: context.themeColors.success,
            ),
          );
        }
      } else {
        // 创建
        await widget.service.create(procedure);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.dlgProcedureCreated),
              backgroundColor: context.themeColors.success,
            ),
          );
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.dlgOperationFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _formatSql() {
    // 简单的 SQL 格式化
    final sql = _bodyController.text;
    final formatted = sql
        .replaceAllMapped(
          RegExp(
            r'\b(DECLARE|SET|IF|THEN|ELSE|WHILE|DO|END|LOOP|CASE|WHEN|SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|JOIN|ORDER BY|GROUP BY|HAVING)\b',
            caseSensitive: false,
          ),
          (match) => '\n${match.group(0)!.toUpperCase()}',
        )
        .trim();
    _bodyController.text = formatted;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEdit = widget.procedure != null;
    final title = isEdit
        ? l10n.dlgEditRoutine(_getTypeName(l10n))
        : l10n.dlgCreateRoutine(_getTypeName(l10n));

    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 800,
        height: 700,
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: Column(
          children: [
            // 标题栏
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
                    title,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSize2xl,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x),
                    color: context.themeColors.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // 内容
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDesignSystem.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 名称和类型
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<ProcedureType>(
                              initialValue: _selectedType,
                              decoration: InputDecoration(
                                labelText: l10n.dlgType,
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: ProcedureType.procedure,
                                  child: Text(l10n.dlgProcedureType),
                                ),
                                DropdownMenuItem(
                                  value: ProcedureType.function,
                                  child: Text(l10n.dlgFunctionType),
                                ),
                              ],
                              onChanged: isEdit
                                  ? null // 编辑时不允许修改类型
                                  : (value) {
                                      if (value != null) {
                                        setState(() => _selectedType = value);
                                      }
                                    },
                              style: TextStyle(
                                color: context.themeColors.textPrimary,
                              ),
                              dropdownColor: context.themeColors.bgSecondary,
                            ),
                          ),
                          const SizedBox(width: AppDesignSystem.space4),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _nameController,
                              enabled: !isEdit, // 编辑时不允许修改名称
                              decoration: InputDecoration(
                                labelText: l10n.connName,
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.dlgNameRequired;
                                }
                                if (!RegExp(
                                  r'^[a-zA-Z_][a-zA-Z0-9_]*$',
                                ).hasMatch(value.trim())) {
                                  return l10n.dlgRoutineNameInvalid;
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppDesignSystem.space4),

                      // 返回类型 (仅函数)
                      if (_selectedType == ProcedureType.function) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedReturnType,
                          decoration: InputDecoration(
                            labelText: l10n.dlgReturnType,
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _returnTypes
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _selectedReturnType = value);
                          },
                          validator: (value) {
                            if (_selectedType == ProcedureType.function &&
                                (value == null || value.isEmpty)) {
                              return l10n.dlgReturnTypeRequired;
                            }
                            return null;
                          },
                          style: TextStyle(
                            color: context.themeColors.textPrimary,
                          ),
                          dropdownColor: context.themeColors.bgSecondary,
                        ),
                        const SizedBox(height: AppDesignSystem.space4),
                      ],

                      // 参数编辑器
                      ParameterEditor(
                        parameters: _parameters,
                        isFunction: _selectedType == ProcedureType.function,
                        onChanged: (params) => _parameters = params,
                      ),

                      const SizedBox(height: AppDesignSystem.space4),

                      // SQL 代码编辑器
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.dlgSqlCode,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.themeColors.textPrimary,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _formatSql,
                            icon: const Icon(LucideIcons.alignLeft, size: 14),
                            label: Text(l10n.queryFormat),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDesignSystem.space2,
                                vertical: AppDesignSystem.space1,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDesignSystem.space2),
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          color: context.themeColors.bgPrimary,
                          borderRadius: BorderRadius.circular(
                            AppDesignSystem.radiusSm,
                          ),
                          border: Border.all(
                            color: context.themeColors.borderLight,
                          ),
                        ),
                        child: TextField(
                          controller: _bodyController,
                          maxLines: null,
                          expands: true,
                          style: TextStyle(
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                            fontSize: 13,
                            color: context.themeColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.dlgEnterSqlHint,
                            hintStyle: TextStyle(
                              color: context.themeColors.textMuted,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(
                              AppDesignSystem.space3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 底部按钮
            Container(
              padding: const EdgeInsets.all(AppDesignSystem.space4),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                border: Border(
                  top: BorderSide(color: context.themeColors.borderLight),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _save,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.save, size: 16),
                    label: Text(isEdit ? l10n.commonUpdate : l10n.commonCreate),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space5,
                        vertical: AppDesignSystem.space2_5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeName(AppLocalizations l10n) {
    return _selectedType == ProcedureType.procedure
        ? l10n.dlgRoutineProcedure
        : l10n.dlgRoutineFunction;
  }
}
