import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/stored_procedure.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

class ParameterEditor extends StatefulWidget {
  final List<ProcedureParameter> parameters;
  final ValueChanged<List<ProcedureParameter>> onChanged;
  final bool isFunction; // 函数不支持 IN/OUT/INOUT 模式

  const ParameterEditor({
    super.key,
    required this.parameters,
    required this.onChanged,
    this.isFunction = false,
  });

  @override
  State<ParameterEditor> createState() => _ParameterEditorState();
}

class _ParameterEditorState extends State<ParameterEditor> {
  late List<ProcedureParameter> _parameters;

  static const List<String> _dataTypes = [
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
    'CHAR(1)',
    'ENUM',
    'SET',
  ];

  static const List<String> _modes = ['IN', 'OUT', 'INOUT'];

  @override
  void initState() {
    super.initState();
    _parameters = List.from(widget.parameters);
  }

  @override
  void didUpdateWidget(ParameterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parameters != widget.parameters) {
      _parameters = List.from(widget.parameters);
    }
  }

  void _addParameter() {
    setState(() {
      _parameters.add(
        ProcedureParameter(
          name: 'param${_parameters.length + 1}',
          dataType: 'INT',
          mode: 'IN',
        ),
      );
      widget.onChanged(_parameters);
    });
  }

  void _removeParameter(int index) {
    setState(() {
      _parameters.removeAt(index);
      widget.onChanged(_parameters);
    });
  }

  void _updateParameter(int index, ProcedureParameter param) {
    setState(() {
      _parameters[index] = param;
      widget.onChanged(_parameters);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '参数列表',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: _addParameter,
              icon: Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.success,
              ),
              label: Text(
                '添加参数',
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.success,
                ),
              ),
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
        if (_parameters.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(color: context.themeColors.borderLight),
            ),
            child: Center(
              child: Text(
                '暂无参数',
                style: TextStyle(color: context.themeColors.textSecondary),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(color: context.themeColors.borderLight),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _parameters.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.themeColors.borderLight),
              itemBuilder: (context, index) {
                return _ParameterRow(
                  parameter: _parameters[index],
                  isFunction: widget.isFunction,
                  dataTypes: _dataTypes,
                  modes: _modes,
                  onChanged: (param) => _updateParameter(index, param),
                  onRemove: () => _removeParameter(index),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ParameterRow extends StatefulWidget {
  final ProcedureParameter parameter;
  final bool isFunction;
  final List<String> dataTypes;
  final List<String> modes;
  final ValueChanged<ProcedureParameter> onChanged;
  final VoidCallback onRemove;

  const _ParameterRow({
    required this.parameter,
    required this.isFunction,
    required this.dataTypes,
    required this.modes,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_ParameterRow> createState() => _ParameterRowState();
}

class _ParameterRowState extends State<_ParameterRow> {
  late TextEditingController _nameController;
  late String _selectedDataType;
  late String _selectedMode;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.parameter.name);
    _selectedDataType = widget.parameter.dataType;
    _selectedMode = widget.parameter.mode;
  }

  @override
  void didUpdateWidget(_ParameterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parameter != widget.parameter) {
      _nameController.text = widget.parameter.name;
      _selectedDataType = widget.parameter.dataType;
      _selectedMode = widget.parameter.mode;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _notifyChange() {
    widget.onChanged(
      ProcedureParameter(
        name: _nameController.text,
        dataType: _selectedDataType,
        mode: _selectedMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      child: Row(
        children: [
          // 删除按钮
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(LucideIcons.trash2, size: 18),
            color: context.themeColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: AppLocalizations.of(context)!.dlgDeleteParam,
          ),
          const SizedBox(width: AppDesignSystem.space2),

          // 模式选择 (仅存储过程)
          if (!widget.isFunction) ...[
            Container(
              width: 80,
              height: 32,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(color: context.themeColors.borderLight),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMode,
                  items: widget.modes
                      .map(
                        (mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(
                            mode,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedMode = value;
                      });
                      _notifyChange();
                    }
                  },
                  style: TextStyle(color: context.themeColors.textPrimary),
                  dropdownColor: context.themeColors.bgSecondary,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
          ],

          // 参数名
          Expanded(
            flex: 2,
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: l10n.connParameterName,
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space2,
                ),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => _notifyChange(),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),

          // 数据类型
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(color: context.themeColors.borderLight),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedDataType,
                  isExpanded: true,
                  items: widget.dataTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedDataType = value;
                      });
                      _notifyChange();
                    }
                  },
                  style: TextStyle(color: context.themeColors.textPrimary),
                  dropdownColor: context.themeColors.bgSecondary,
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
