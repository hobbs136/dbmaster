import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/task_models.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// 导出任务创建对话框
/// 用于从 AI 助手界面快速创建导出任务
class ExportTaskCreateDialog extends StatefulWidget {
  final String connectionId;
  final String? databaseName;
  final String tableName;
  final String? whereClause;
  final int? rowCount;

  const ExportTaskCreateDialog({
    super.key,
    required this.connectionId,
    this.databaseName,
    required this.tableName,
    this.whereClause,
    this.rowCount,
  });

  @override
  State<ExportTaskCreateDialog> createState() => _ExportTaskCreateDialogState();
}

class _ExportTaskCreateDialogState extends State<ExportTaskCreateDialog> {
  ExportFormat _selectedFormat = ExportFormat.csv;
  String? _outputPath;
  bool _isValidating = false;
  String? _errorMessage;

  final List<Map<String, dynamic>> _formats = [
    {'value': ExportFormat.csv, 'label': 'CSV', 'ext': 'csv'},
    {'value': ExportFormat.json, 'label': 'JSON', 'ext': 'json'},
    {'value': ExportFormat.sql, 'label': 'SQL', 'ext': 'sql'},
  ];

  @override
  Widget build(BuildContext context) {
    final themeColors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      backgroundColor: themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.fileDown, size: 20, color: themeColors.accentPurple),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.taskCreateExportTitle,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.w600,
              color: themeColors.textPrimary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 表信息
            _buildInfoRow(l10n.tableTableName, widget.tableName, themeColors),
            if (widget.whereClause != null)
              _buildInfoRow(
                l10n.taskCreateExportFilter,
                widget.whereClause!,
                themeColors,
              ),
            if (widget.rowCount != null)
              _buildInfoRow(
                l10n.taskCreateExportEstRows,
                '${widget.rowCount}',
                themeColors,
              ),
            const SizedBox(height: AppDesignSystem.space4),

            // 格式选择
            Text(
              l10n.taskCreateExportFormat,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: themeColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Wrap(
              spacing: 8,
              children: _formats.map((format) {
                final isSelected = _selectedFormat == format['value'];
                return ChoiceChip(
                  label: Text(format['label'] as String),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedFormat = format['value'] as ExportFormat;
                    });
                  },
                  backgroundColor: themeColors.bgTertiary,
                  selectedColor: themeColors.accentPurple.withValues(
                    alpha: 0.2,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isSelected
                        ? themeColors.accentPurple
                        : themeColors.textSecondary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppDesignSystem.space4),

            // 输出路径
            Text(
              l10n.taskCreateExportPath,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: themeColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space3,
                      vertical: AppDesignSystem.space2,
                    ),
                    decoration: BoxDecoration(
                      color: themeColors.bgTertiary,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      border: Border.all(
                        color: _errorMessage != null
                            ? themeColors.error
                            : themeColors.borderLight,
                      ),
                    ),
                    child: Text(
                      _outputPath ?? l10n.taskCreateExportPathPlaceholder,
                      style: TextStyle(
                        fontSize: 12,
                        color: _outputPath != null
                            ? themeColors.textPrimary
                            : themeColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                IconButton(
                  icon: Icon(
                    LucideIcons.folderOpen,
                    size: 18,
                    color: themeColors.accentPurple,
                  ),
                  onPressed: _selectOutputPath,
                  tooltip: l10n.taskCreateExportPathSelect,
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppDesignSystem.space1),
              Text(
                _errorMessage!,
                style: TextStyle(fontSize: 11, color: themeColors.error),
              ),
            ],
            if (_isValidating) ...[
              const SizedBox(height: AppDesignSystem.space2),
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        themeColors.accentPurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Text(
                    l10n.taskCreateExportValidating,
                    style: TextStyle(
                      fontSize: 11,
                      color: themeColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.commonCancel,
            style: TextStyle(color: themeColors.textMuted),
          ),
        ),
        FilledButton.icon(
          onPressed: _outputPath != null && !_isValidating ? _createTask : null,
          icon: Icon(LucideIcons.play, size: 16),
          label: Text(l10n.taskCreateExportStart),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeColors themeColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space0_5),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: themeColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: themeColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectOutputPath() async {
    final l10n = AppLocalizations.of(context)!;
    final format = _formats.firstWhere((f) => f['value'] == _selectedFormat);
    final ext = format['ext'] as String;

    final result = await FilePicker.platform.saveFile(
      dialogTitle: l10n.taskCreateExportSaveDialogTitle,
      fileName: '${widget.tableName}_export.$ext',
      type: FileType.custom,
      allowedExtensions: [ext],
    );

    if (result != null) {
      setState(() {
        _outputPath = result;
        _errorMessage = null;
      });
      _validatePath(result);
    }
  }

  Future<void> _validatePath(String path) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isValidating = true;
      _errorMessage = null;
    });

    try {
      final file = File(path);
      final dir = file.parent;

      // 检查目录是否存在
      if (!await dir.exists()) {
        setState(() {
          _errorMessage = l10n.taskValidationPathNotExists(dir.path);
        });
        return;
      }

      // 检查是否可写（尝试创建临时文件）
      final testFile = File(
        '${dir.path}/.write_test_${DateTime.now().millisecondsSinceEpoch}',
      );
      try {
        await testFile.writeAsString('test');
        await testFile.delete();
      } catch (e) {
        setState(() {
          _errorMessage = l10n.taskValidationPathNotWritable;
        });
        return;
      }

      // 检查文件是否已存在
      if (await file.exists()) {
        setState(() {
          _errorMessage = l10n.taskValidationPathExists;
        });
      }
    } finally {
      setState(() {
        _isValidating = false;
      });
    }
  }

  void _createTask() {
    if (_outputPath == null) return;

    final l10n = AppLocalizations.of(context)!;
    final config = ExportTaskConfig(
      connectionId: widget.connectionId,
      databaseName: widget.databaseName,
      description: widget.whereClause != null
          ? l10n.taskCreateExportDescFiltered(widget.tableName)
          : l10n.taskCreateExportDesc(widget.tableName),
      tableName: widget.tableName,
      outputPath: _outputPath!,
      format: _selectedFormat,
      whereClause: widget.whereClause,
    );

    Navigator.of(context).pop(config);
  }
}
