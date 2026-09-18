import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dbmaster/pro/data_import/smart_import_models.dart';
import 'package:dbmaster/services/ai/ai_client.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/pro/data_import/smart_import_service.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';

/// 数据导入向导步骤
enum WizardStep {
  selectFile,
  analyzeFile,
  columnMapping,
  previewAndPII,
  confirmImport,
}

/// 增强版数据导入向导对话框
///
/// 提供清晰的步骤式导入流程：
/// 1. 文件选择
/// 2. AI 分析
/// 3. 列映射
/// 4. 数据预览 & PII 检测
/// 5. 确认导入
class ImportWizardDialog extends StatefulWidget {
  final String? initialConnectionId;
  final String? initialDatabase;
  final DatabaseAdapter adapter;
  final AiClient aiClient;

  const ImportWizardDialog({
    super.key,
    this.initialConnectionId,
    this.initialDatabase,
    required this.adapter,
    required this.aiClient,
  });

  @override
  State<ImportWizardDialog> createState() => _ImportWizardDialogState();
}

class _ImportWizardDialogState extends State<ImportWizardDialog> {
  late final SmartImportService _importService;
  late final AiClient _aiClient;

  // 当前步骤
  WizardStep _currentStep = WizardStep.selectFile;
  final List<WizardStep> _completedSteps = [];

  // 目标选择
  String? _selectedDatabase;
  String? _selectedTable;
  List<String> _availableTables = [];
  List<String> _availableDatabases = [];

  // 文件相关
  String? _selectedFilePath;
  FileAnalysisResult? _analysisResult;
  String? _fileName;

  // AI 分析
  String? _aiSuggestedTableName;
  String? _createTableSQL;
  bool _isAnalyzing = false;

  // 列映射
  List<ColumnMapping> _columnMappings = [];
  bool _isMappingComplete = false;

  // PII 检测
  PIIDetectionResult? _piiResult;
  bool _piiWarningAcknowledged = false;

  // 数据预览
  DataPreviewResult? _previewResult;
  List<ValidationError> _validationErrors = [];

  // 冲突处理
  ConflictResolution _conflictResolution = ConflictResolution.skip;

  // 导入状态
  bool _isImporting = false;
  SmartImportProgress? _importProgress;
  SmartImportResult? _importResult;

  // 错误信息
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _aiClient = widget.aiClient;
    _importService = SmartImportService(
      adapter: widget.adapter,
      aiClient: _aiClient,
    );
    _selectedDatabase = widget.initialDatabase;
    _loadDatabases();
  }

  @override
  void dispose() {
    _importService.cancel();
    super.dispose();
  }

  // ==================== 数据加载 ====================

  Future<void> _loadDatabases() async {
    try {
      final dbs = await widget.adapter.getDatabases();
      setState(() {
        _availableDatabases = dbs;
      });
      if (_selectedDatabase != null) {
        await _loadTables(_selectedDatabase!);
      }
    } catch (e) {
      _setError(
        AppLocalizations.of(
          context,
        )!.importWizLoadDatabasesFailed(e.toString()),
      );
    }
  }

  Future<void> _loadTables(String database) async {
    try {
      final tables = await widget.adapter.getTables();
      setState(() {
        _availableTables = tables;
      });
    } catch (e) {
      _setError(
        AppLocalizations.of(context)!.importWizLoadTablesFailed(e.toString()),
      );
    }
  }

  // ==================== 文件选择 ====================

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'csv',
          'json',
          'txt',
          'tsv',
          'jsonl',
          'xlsx',
          'xls',
        ],
        allowMultiple: false,
      );

      if (result != null &&
          result.files.isNotEmpty &&
          result.files.first.path != null) {
        setState(() {
          _selectedFilePath = result.files.first.path;
          _fileName = result.files.first.name;
          _analysisResult = null;
          _errorMessage = null;
          _columnMappings = [];
          _previewResult = null;
          _piiResult = null;
          _piiWarningAcknowledged = false;
        });
      }
    } catch (e) {
      _setError(
        AppLocalizations.of(context)!.importWizPickFileFailed(e.toString()),
      );
    }
  }

  // ==================== AI 分析 ====================

  Future<void> _analyzeFile() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      // 本地分析文件
      final analysis = await _importService.analyzeFile(_selectedFilePath!);
      if (!analysis.success) {
        _setError(
          analysis.errorMessage ??
              AppLocalizations.of(context)!.importWizFileAnalysisFailed,
        );
        return;
      }

      setState(() {
        _analysisResult = analysis;
      });

      // 如果用户已选择表，直接使用；否则 AI 推断表名
      if (_selectedTable != null && _selectedTable!.isNotEmpty) {
        setState(() {
          _aiSuggestedTableName = _selectedTable;
        });
      } else {
        // 从文件名推断表名
        final suggestedName = _fileName!
            .split('.')
            .first
            .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
            .toLowerCase();
        setState(() {
          _aiSuggestedTableName = suggestedName;
        });
      }

      // 进入下一步
      _goToStep(WizardStep.analyzeFile);
    } catch (e) {
      _setError(
        AppLocalizations.of(context)!.importWizAnalysisFailed(e.toString()),
      );
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  // ==================== 列映射 ====================

  Future<void> _generateColumnMappings() async {
    if (_analysisResult == null || _aiSuggestedTableName == null) return;

    try {
      // 获取表结构
      final tableColumns = await _importService.getTableColumns(
        _aiSuggestedTableName!,
      );
      final tableColumnNames = tableColumns
          .map((c) => c['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      // 生成列映射
      final mappings = _importService.generateColumnMappings(
        fileColumns: _analysisResult!.fields,
        tableColumns: tableColumnNames,
      );

      setState(() {
        _columnMappings = mappings;
        _isMappingComplete = mappings.every((m) => m.isMapped);
      });

      // 生成预览
      _generatePreview();
    } catch (e) {
      _setError(
        AppLocalizations.of(context)!.importWizMappingFailed(e.toString()),
      );
    }
  }

  void _updateColumnMapping(int index, String? tableColumn) {
    setState(() {
      _columnMappings[index] = _columnMappings[index].copyWith(
        tableColumn: tableColumn,
      );
      _isMappingComplete = _columnMappings.every((m) => m.isMapped);
    });
    _generatePreview();
  }

  // ==================== 数据预览 ====================

  void _generatePreview() {
    if (_analysisResult == null || _columnMappings.isEmpty) return;

    try {
      final result = _importService.generatePreview(
        analysis: _analysisResult!,
        columnMappings: _columnMappings,
      );

      setState(() {
        _previewResult = result;
      });

      // 验证数据
      _validateData();
    } catch (e) {
      // 预览生成失败不阻塞流程
    }
  }

  void _validateData() {
    if (_previewResult == null) return;

    final errors = <ValidationError>[];
    final mappedColumns = _columnMappings.where((m) => m.isMapped).toList();

    for (
      int rowIndex = 0;
      rowIndex < _previewResult!.previewData.length;
      rowIndex++
    ) {
      final row = _previewResult!.previewData[rowIndex];
      for (final mapping in mappedColumns) {
        final value = row[mapping.fileColumn];
        if (value == null || value.toString().isEmpty) {
          errors.add(
            ValidationError(
              rowIndex: rowIndex,
              columnName: mapping.fileColumn,
              message: '空值',
              severity: ValidationSeverity.warning,
            ),
          );
        }
      }
    }

    setState(() {
      _validationErrors = errors;
    });
  }

  // ==================== PII 检测 ====================

  Future<void> _detectPII() async {
    if (_analysisResult == null) return;

    try {
      final result = _importService.detectPII(
        columns: _analysisResult!.fields,
        sampleData: _analysisResult!.sampleData,
      );

      setState(() {
        _piiResult = result;
      });
    } catch (e) {
      // PII 检测失败不阻塞流程
    }
  }

  // ==================== 导入执行 ====================

  Future<void> _startImport() async {
    if (_selectedFilePath == null ||
        _analysisResult == null ||
        _aiSuggestedTableName == null)
      return;

    setState(() {
      _isImporting = true;
      _errorMessage = null;
      _importProgress = null;
      _importResult = null;
    });

    try {
      final config = SmartImportConfig(
        filePath: _selectedFilePath!,
        targetTable: _aiSuggestedTableName,
        batchSize: 1000,
      );

      final result = await _importService.importData(
        config: config,
        analysis: _analysisResult!,
        tableName: _aiSuggestedTableName!,
        columnMappings: _columnMappings.where((m) => m.isMapped).toList(),
        conflictResolution: _conflictResolution,
        onProgress: (progress) {
          setState(() {
            _importProgress = progress;
          });
        },
      );

      setState(() {
        _importResult = result;
        _isImporting = false;
      });

      if (result.success) {
        _goToStep(WizardStep.confirmImport);
      } else {
        _setError(
          result.errorMessage ??
              AppLocalizations.of(context)!.importWizImportFailedGeneric,
        );
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
      });
      _setError(
        AppLocalizations.of(context)!.importWizImportFailed(e.toString()),
      );
    }
  }

  // ==================== 步骤导航 ====================

  void _goToStep(WizardStep step) {
    setState(() {
      if (!_completedSteps.contains(_currentStep)) {
        _completedSteps.add(_currentStep);
      }
      _currentStep = step;
      _errorMessage = null;
    });

    // 步骤进入时的初始化
    switch (step) {
      case WizardStep.columnMapping:
        _generateColumnMappings();
        break;
      case WizardStep.previewAndPII:
        _detectPII();
        break;
      default:
        break;
    }
  }

  bool _canGoNext() {
    switch (_currentStep) {
      case WizardStep.selectFile:
        return _selectedFilePath != null && _selectedDatabase != null;
      case WizardStep.analyzeFile:
        return _analysisResult != null;
      case WizardStep.columnMapping:
        return _isMappingComplete;
      case WizardStep.previewAndPII:
        return _piiResult == null ||
            _piiResult!.hasSensitiveData == false ||
            _piiWarningAcknowledged;
      case WizardStep.confirmImport:
        return true;
    }
  }

  void _nextStep() {
    switch (_currentStep) {
      case WizardStep.selectFile:
        _analyzeFile();
        break;
      case WizardStep.analyzeFile:
        _goToStep(WizardStep.columnMapping);
        break;
      case WizardStep.columnMapping:
        _goToStep(WizardStep.previewAndPII);
        break;
      case WizardStep.previewAndPII:
        _goToStep(WizardStep.confirmImport);
        break;
      case WizardStep.confirmImport:
        _startImport();
        break;
    }
  }

  void _previousStep() {
    switch (_currentStep) {
      case WizardStep.analyzeFile:
        _goToStep(WizardStep.selectFile);
        break;
      case WizardStep.columnMapping:
        _goToStep(WizardStep.analyzeFile);
        break;
      case WizardStep.previewAndPII:
        _goToStep(WizardStep.columnMapping);
        break;
      case WizardStep.confirmImport:
        _goToStep(WizardStep.previewAndPII);
        break;
      default:
        break;
    }
  }

  // ==================== 工具方法 ====================

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
    });
  }

  String _getStepTitle(WizardStep step) {
    final l10n = AppLocalizations.of(context)!;
    switch (step) {
      case WizardStep.selectFile:
        return l10n.importWizStepSelectFile;
      case WizardStep.analyzeFile:
        return l10n.importWizStepAnalyzeFile;
      case WizardStep.columnMapping:
        return l10n.importWizStepColumnMapping;
      case WizardStep.previewAndPII:
        return l10n.importWizStepPreviewPII;
      case WizardStep.confirmImport:
        return l10n.importWizStepConfirmImport;
    }
  }

  // ==================== UI 构建 ====================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 800,
        height: 700,
        constraints: const BoxConstraints(
          maxWidth: 900,
          minHeight: 500,
          maxHeight: 800,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            _buildHeader(l10n),
            const SizedBox(height: AppDesignSystem.space5),

            // 步骤指示器
            _buildStepper(),
            const SizedBox(height: AppDesignSystem.space5),

            // 分隔线
            Divider(
              color: context.themeColors.borderSubtle,
              height: 1,
            ),
            const SizedBox(height: AppDesignSystem.space5),

            // 错误提示
            if (_errorMessage != null) ...[
              _buildErrorBanner(),
              const SizedBox(height: AppDesignSystem.space4),
            ],

            // 主内容区
            Expanded(child: SingleChildScrollView(child: _buildStepContent())),

            const SizedBox(height: AppDesignSystem.space5),

            // 底部操作按钮
            _buildActions(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.themeColors.accentBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: Icon(
            LucideIcons.wandSparkles,
            color: context.themeColors.accentBlue,
            size: 24,
          ),
        ),
        const SizedBox(width: AppDesignSystem.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.importWizardTitle,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSize2xl,
                  fontWeight: FontWeight.w700,
                  color: context.themeColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space0_5),
              Text(
                l10n.importWizStepOf(
                  (_currentStep.index + 1).toString(),
                  WizardStep.values.length.toString(),
                  _getStepTitle(_currentStep),
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            LucideIcons.x,
            size: 20,
            color: context.themeColors.textMuted,
          ),
          tooltip: AppLocalizations.of(context)!.commonClose,
        ),
      ],
    );
  }

  /// 原型 import-wizard 步骤指示器：20px 圆点三态
  /// （done=success+check / active=accent+序号 / pending=bgTertiary+描边），
  /// 标签随行、1px 连接线。
  Widget _buildStepper() {
    final steps = WizardStep.values;

    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isActive = step == _currentStep;
        final isCompleted = _completedSteps.contains(step);
        final isLast = index == steps.length - 1;

        return Expanded(
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? context.themeColors.accentBlue
                      : isCompleted
                      ? context.themeColors.success
                      : context.themeColors.bgTertiary,
                  border: Border.all(
                    color: isActive || isCompleted
                        ? Colors.transparent
                        : context.themeColors.borderLight,
                  ),
                ),
                child: isCompleted && !isActive
                    ? const Icon(
                        LucideIcons.check,
                        size: 12,
                        color: AppDesignSystem.textInverted,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: AppDesignSystem.fontSizeXs,
                          fontWeight: AppDesignSystem.fontWeightSemibold,
                          color: isActive
                              ? AppDesignSystem.textInverted
                              : context.themeColors.textSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  _getStepTitle(step),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: isActive
                        ? AppDesignSystem.fontWeightSemibold
                        : AppDesignSystem.fontWeightMedium,
                    color: isActive
                        ? context.themeColors.accentBlue
                        : context.themeColors.textSecondary,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 1,
                    color: isCompleted
                        ? context.themeColors.borderLight
                        : context.themeColors.borderColor,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 18,
            color: context.themeColors.error,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: 12, color: context.themeColors.error),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _errorMessage = null),
            icon: Icon(
              LucideIcons.x,
              size: 16,
              color: context.themeColors.error,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case WizardStep.selectFile:
        return _buildSelectFileStep();
      case WizardStep.analyzeFile:
        return _buildAnalyzeFileStep();
      case WizardStep.columnMapping:
        return _buildColumnMappingStep();
      case WizardStep.previewAndPII:
        return _buildPreviewAndPIIStep();
      case WizardStep.confirmImport:
        return _buildConfirmImportStep();
    }
  }

  // ==================== Step 1: 选择文件 ====================

  Widget _buildSelectFileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 数据库选择
        _buildDatabaseSelector(),
        const SizedBox(height: AppDesignSystem.space5),

        // 表选择（可选）
        if (_selectedDatabase != null) ...[
          _buildTableSelector(),
          const SizedBox(height: AppDesignSystem.space5),
        ],

        // 文件选择区域
        _buildFileDropZone(),
        const SizedBox(height: AppDesignSystem.space5),

        // 已选择文件信息
        if (_selectedFilePath != null) ...[_buildSelectedFileInfo()],
      ],
    );
  }

  Widget _buildDatabaseSelector() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importWizTargetDatabase,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: context.themeColors.borderSubtle,
            ),
          ),
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedDatabase,
            isDense: true,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.dlgChooseDatabase,
              hintStyle: TextStyle(
                fontSize: 13,
                color: context.themeColors.textMuted,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space3,
              ),
            ),
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textPrimary,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  l10n.importWizSelectDatabase,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              ..._availableDatabases.map(
                (db) => DropdownMenuItem<String?>(
                  value: db,
                  child: Text(db, style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedDatabase = value;
                _selectedTable = null;
                _availableTables = [];
              });
              if (value != null) {
                _loadTables(value);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableSelector() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importWizTargetTableOptional,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: context.themeColors.borderSubtle,
            ),
          ),
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedTable,
            isDense: true,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.dlgChooseTableOrAI,
              hintStyle: TextStyle(
                fontSize: 13,
                color: context.themeColors.textMuted,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space3,
              ),
            ),
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textPrimary,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  l10n.importWizLetAiInfer,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              ..._availableTables.map(
                (table) => DropdownMenuItem<String?>(
                  value: table,
                  child: Text(table, style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedTable = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFileDropZone() {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: AppDesignSystem.space10,
          horizontal: AppDesignSystem.space6,
        ),
        decoration: BoxDecoration(
          color: context.themeColors.bgTertiary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
          border: Border.all(
            color: _selectedFilePath != null
                ? context.themeColors.accentBlue.withValues(alpha: 0.5)
                : context.themeColors.borderSubtle,
            width: _selectedFilePath != null ? 2 : 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(
              LucideIcons.cloudUpload,
              size: 48,
              color: _selectedFilePath != null
                  ? context.themeColors.accentBlue
                  : context.themeColors.textMuted,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              _selectedFilePath != null
                  ? l10n.importWizChangeFile
                  : l10n.importWizChooseFile,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.themeColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              l10n.importWizSupportedFormats,
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFileInfo() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeColors.accentBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.accentBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.file,
            size: 20,
            color: context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fileName ?? l10n.importWizFileUnknown,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                if (_selectedFilePath != null)
                  Text(
                    _selectedFilePath!,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedFilePath = null;
                _fileName = null;
              });
            },
            icon: Icon(
              LucideIcons.x,
              size: 18,
              color: context.themeColors.textMuted,
            ),
            tooltip: AppLocalizations.of(context)!.dlgRemoveFile,
          ),
        ],
      ),
    );
  }

  // ==================== Step 2: 分析文件 ====================

  Widget _buildAnalyzeFileStep() {
    if (_isAnalyzing) {
      return _buildAnalyzingState();
    }

    if (_analysisResult == null) {
      final l10n = AppLocalizations.of(context)!;
      return _buildEmptyState(
        l10n.importWizNoAnalysisResult,
        l10n.importWizSelectFileFirst,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 文件概览
        _buildAnalysisOverview(),
        const SizedBox(height: AppDesignSystem.space5),

        // 字段列表
        _buildFieldsSection(),
        const SizedBox(height: AppDesignSystem.space5),

        // AI 推断信息
        if (_aiSuggestedTableName != null) ...[_buildAISuggestionSection()],
      ],
    );
  }

  Widget _buildAnalyzingState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppDesignSystem.space10),
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: context.themeColors.accentBlue,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space5),
          Text(
            l10n.importWizAiAnalyzing,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.importWizDetectingFormat,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space10),
        ],
      ),
    );
  }

  Widget _buildAnalysisOverview() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.importWizFileAnalysisResult,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _buildInfoChip(
                l10n.importWizFormat,
                _analysisResult!.format.name.toUpperCase(),
              ),
              _buildInfoChip(l10n.importWizEncoding, _analysisResult!.encoding),
              _buildInfoChip(
                l10n.importWizFieldCount,
                '${_analysisResult!.fields.length}',
              ),
              if (_analysisResult!.estimatedTotalRows != null)
                _buildInfoChip(
                  l10n.importWizEstimatedRows,
                  '~${_analysisResult!.estimatedTotalRows}',
                ),
              _buildInfoChip(
                l10n.importWizFileSize,
                _formatFileSize(_analysisResult!.fileSize),
              ),
              if (_analysisResult!.delimiter != null)
                _buildInfoChip(
                  l10n.importWizDelimiter,
                  '"${_analysisResult!.delimiter}"',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2_5,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldsSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importWizDetectedFields,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: context.themeColors.borderSubtle,
            ),
          ),
          child: Column(
            children: _analysisResult!.fields.asMap().entries.map((entry) {
              final index = entry.key;
              final field = entry.value;
              final inferredType =
                  _analysisResult!.inferredTypes[field] ?? 'TEXT';

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                  vertical: AppDesignSystem.space2,
                ),
                decoration: BoxDecoration(
                  border: index < _analysisResult!.fields.length - 1
                      ? Border(
                          bottom: BorderSide(
                            color: context.themeColors.borderSubtle,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: context.themeColors.accentBlue.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.themeColors.accentBlue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space3),
                    Expanded(
                      child: Text(
                        field,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.themeColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space2,
                        vertical: AppDesignSystem.space0_5,
                      ),
                      decoration: BoxDecoration(
                        color: context.themeColors.bgSecondary,
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: Text(
                        inferredType,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAISuggestionSection() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.themeColors.accentBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.accentBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.wandSparkles,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.importWizAiSuggestion,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.importWizTargetTableName(_aiSuggestedTableName!),
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.textPrimary,
            ),
          ),
          if (_createTableSQL != null) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: SelectableText(
                _createTableSQL!,
                style: TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 11,
                  color: context.themeColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== Step 3: 列映射 ====================

  Widget _buildColumnMappingStep() {
    if (_columnMappings.isEmpty) {
      final l10n2 = AppLocalizations.of(context)!;
      return _buildEmptyState(
        l10n2.importWizNoColumnMapping,
        l10n2.importWizGeneratingMapping,
      );
    }

    final l10n = AppLocalizations.of(context)!;
    final mappedCount = _columnMappings.where((m) => m.isMapped).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.importWizColumnMappingConfig,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              l10n.importWizColumnsMapped(
                mappedCount.toString(),
                _columnMappings.length.toString(),
              ),
              style: TextStyle(
                fontSize: 12,
                color: _isMappingComplete
                    ? context.themeColors.success
                    : context.themeColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space3),
        Text(
          l10n.importWizMappingDescription,
          style: TextStyle(
            fontSize: 12,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space4),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: context.themeColors.borderSubtle,
            ),
          ),
          child: Column(
            children: [
              // 表头
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space4,
                  vertical: AppDesignSystem.space2_5,
                ),
                decoration: BoxDecoration(
                  color: context.themeColors.bgSecondary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppDesignSystem.radiusMd),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        l10n.importWizFileColumn,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: context.themeColors.textMuted,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        l10n.importWizDatabaseColumn,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        l10n.importWizType,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 映射行
              ...List.generate(_columnMappings.length, (index) {
                final mapping = _columnMappings[index];
                final fileColumn = mapping.fileColumn;
                final inferredType =
                    _analysisResult?.inferredTypes[fileColumn] ?? 'TEXT';

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space4,
                    vertical: AppDesignSystem.space2,
                  ),
                  decoration: BoxDecoration(
                    border: index < _columnMappings.length - 1
                        ? Border(
                            bottom: BorderSide(
                              color: context.themeColors.borderSubtle,
                            ),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Icon(
                              mapping.isMapped
                                  ? LucideIcons.circleCheckBig
                                  : LucideIcons.circle,
                              size: 14,
                              color: mapping.isMapped
                                  ? context.themeColors.success
                                  : context.themeColors.textMuted,
                            ),
                            const SizedBox(width: AppDesignSystem.space2),
                            Text(
                              fileColumn,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.themeColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Icon(
                          LucideIcons.arrowRight,
                          size: 14,
                          color: mapping.isMapped
                              ? context.themeColors.success
                              : context.themeColors.textMuted,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String?>(
                          initialValue: mapping.tableColumn,
                          isDense: true,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(
                              context,
                            )!.dlgSkipImport,
                            hintStyle: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.textMuted,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.themeColors.textPrimary,
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                l10n.dlgSkipImport,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            ..._availableTables.map(
                              (col) => DropdownMenuItem<String?>(
                                value: col,
                                child: Text(
                                  col,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              _updateColumnMapping(index, value),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          inferredType,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.themeColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== Step 4: 预览 & PII ====================

  Widget _buildPreviewAndPIIStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PII 警告
        if (_piiResult != null &&
            _piiResult!.hasSensitiveData &&
            !_piiWarningAcknowledged) ...[
          _buildPIIWarning(),
          const SizedBox(height: AppDesignSystem.space5),
        ],

        // 数据预览
        if (_previewResult != null) ...[
          _buildDataPreview(),
          const SizedBox(height: AppDesignSystem.space5),
        ],

        // 验证错误
        if (_validationErrors.isNotEmpty) ...[
          _buildValidationErrors(),
          const SizedBox(height: AppDesignSystem.space5),
        ],
      ],
    );
  }

  Widget _buildPIIWarning() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.themeColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.triangleAlert,
                color: context.themeColors.warning,
                size: 20,
              ),
              const SizedBox(width: AppDesignSystem.space2_5),
              Text(
                l10n.importWizPiiDetection,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.importWizPiiDetectionMessage,
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2_5),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _piiResult!.sensitiveColumns.map((col) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2_5,
                  vertical: AppDesignSystem.space1,
                ),
                decoration: BoxDecoration(
                  color: context.themeColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(
                    color: context.themeColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.triangleAlert,
                      size: 12,
                      color: context.themeColors.warning,
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Text(
                      '${col.columnName} (${col.piiTypeDisplay})',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.themeColors.warning,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _piiWarningAcknowledged = true;
                  });
                },
                child: Text(
                  l10n.importWizPiiAcknowledge,
                  style: TextStyle(color: context.themeColors.warning),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataPreview() {
    final l10n = AppLocalizations.of(context)!;
    final hasErrors = _validationErrors.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.importWizDataPreview,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (hasErrors)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space0_5,
                ),
                decoration: BoxDecoration(
                  color: context.themeColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  l10n.importWizWarnings(_validationErrors.length.toString()),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.warning,
                  ),
                ),
              ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              l10n.importWizFirstRows(
                _previewResult!.previewData.length.toString(),
              ),
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space3),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: hasErrors
                  ? context.themeColors.warning.withValues(alpha: 0.3)
                  : context.themeColors.borderSubtle,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 36,
                horizontalMargin: 16,
                columnSpacing: 20,
                headingTextStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textSecondary,
                ),
                dataTextStyle: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textPrimary,
                ),
                columns: _previewResult!.previewData.isNotEmpty
                    ? _previewResult!.previewData.first.keys.map((col) {
                        final isSensitive =
                            _piiResult?.sensitiveColumns.any(
                              (s) => s.columnName == col,
                            ) ??
                            false;
                        return DataColumn(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(col),
                              if (isSensitive) ...[
                                const SizedBox(width: AppDesignSystem.space1),
                                Tooltip(
                                  message: l10n.importWizSensitiveField,
                                  child: Icon(
                                    LucideIcons.triangleAlert,
                                    size: 14,
                                    color: context.themeColors.warning,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList()
                    : [],
                rows: _previewResult!.previewData.asMap().entries.map((entry) {
                  final rowIndex = entry.key;
                  final row = entry.value;
                  final hasRowError = _validationErrors.any(
                    (e) => e.rowIndex == rowIndex,
                  );

                  return DataRow(
                    color: hasRowError
                        ? WidgetStateProperty.all(
                            context.themeColors.warning.withValues(alpha: 0.05),
                          )
                        : null,
                    cells: row.values.map((value) {
                      return DataCell(
                        Text(
                          value?.toString() ?? 'NULL',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidationErrors() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.triangleAlert,
              size: 14,
              color: context.themeColors.warning,
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            Text(
              l10n.importWizDataValidationWarnings,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.themeColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.themeColors.warning.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: context.themeColors.warning.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _validationErrors.take(5).map((error) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.circle,
                      size: 6,
                      color: context.themeColors.warning,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Expanded(
                      child: Text(
                        l10n.importWizValidationRowFormat(
                          (error.rowIndex + 1).toString(),
                          error.columnName,
                          error.message,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ==================== Step 5: 确认导入 ====================

  Widget _buildConfirmImportStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 导入配置摘要
        _buildImportSummary(),
        const SizedBox(height: AppDesignSystem.space5),

        // 冲突处理
        _buildConflictResolution(),
        const SizedBox(height: AppDesignSystem.space5),

        // 导入进度
        if (_isImporting || _importResult != null) ...[_buildImportProgress()],
      ],
    );
  }

  Widget _buildImportSummary() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.importWizImportSummary,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          _buildSummaryRow(
            l10n.importWizSummaryTargetDatabase,
            _selectedDatabase ?? l10n.importWizNotSelected,
          ),
          _buildSummaryRow(
            l10n.importWizSummaryTargetTable,
            _aiSuggestedTableName ?? l10n.importWizNotSet,
          ),
          _buildSummaryRow(
            l10n.importWizSummaryFile,
            _fileName ?? l10n.importWizNotSelected,
          ),
          _buildSummaryRow(
            l10n.importWizSummaryMappedColumns,
            '${_columnMappings.where((m) => m.isMapped).length}/${_columnMappings.length}',
          ),
          _buildSummaryRow(
            l10n.importWizSummaryDataRows,
            _analysisResult?.estimatedTotalRows != null
                ? '~${_analysisResult!.estimatedTotalRows}'
                : l10n.importWizUnknown,
          ),
          if (_piiResult != null && _piiResult!.hasSensitiveData)
            _buildSummaryRow(
              l10n.importWizPiiDetectionSummary,
              l10n.importWizSensitiveFieldCount(
                _piiResult!.sensitiveColumns.length.toString(),
              ),
              isWarning: true,
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isWarning = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isWarning
                  ? context.themeColors.warning
                  : context.themeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictResolution() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importWizConflictStrategy,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space3),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: context.themeColors.borderSubtle,
            ),
          ),
          child: Column(
            children: [
              _buildConflictOption(
                ConflictResolution.skip,
                l10n.importWizConflictSkip,
                l10n.importWizConflictSkipDesc,
                LucideIcons.skipForward,
              ),
              const SizedBox(height: AppDesignSystem.space2),
              _buildConflictOption(
                ConflictResolution.update,
                l10n.importWizConflictUpdate,
                l10n.importWizConflictUpdateDesc,
                LucideIcons.rotateCw,
              ),
              const SizedBox(height: AppDesignSystem.space2),
              _buildConflictOption(
                ConflictResolution.abort,
                l10n.importWizConflictAbort,
                l10n.importWizConflictAbortDesc,
                LucideIcons.circleStop,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConflictOption(
    ConflictResolution resolution,
    String title,
    String description,
    IconData icon,
  ) {
    final isSelected = _conflictResolution == resolution;
    return InkWell(
      onTap: () {
        setState(() {
          _conflictResolution = resolution;
        });
      },
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? context.themeColors.accentBlue.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          border: Border.all(
            color: isSelected
                ? context.themeColors.accentBlue.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Radio<ConflictResolution>(
              value: resolution,
              groupValue: _conflictResolution,
              onChanged: (value) {
                setState(() {
                  _conflictResolution = value!;
                });
              },
              activeColor: context.themeColors.accentBlue,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Icon(icon, size: 18, color: context.themeColors.textSecondary),
            const SizedBox(width: AppDesignSystem.space2_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textSecondary,
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

  Widget _buildImportProgress() {
    final l10n = AppLocalizations.of(context)!;
    if (_importResult != null) {
      return _buildImportResult();
    }

    if (_importProgress == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.themeColors.accentBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.accentBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.importWizImporting,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.themeColors.accentBlue,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          LinearProgressIndicator(
            value: _importProgress!.percentage / 100,
            backgroundColor: context.themeColors.bgSecondary,
            valueColor: AlwaysStoppedAnimation<Color>(
              context.themeColors.accentBlue,
            ),
            minHeight: 6,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          const SizedBox(height: AppDesignSystem.space2_5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.importWizRowsProgress(
                  _importProgress!.importedRecords.toString(),
                  _importProgress!.totalRecords.toString(),
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              ),
              Text(
                '${_importProgress!.percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.accentBlue,
                ),
              ),
            ],
          ),
          if (_importProgress!.failedRecords > 0) ...[
            const SizedBox(height: AppDesignSystem.space1_5),
            Text(
              l10n.importWizFailedRows(
                _importProgress!.failedRecords.toString(),
              ),
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImportResult() {
    final l10n = AppLocalizations.of(context)!;
    final success = _importResult!.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: success
            ? context.themeColors.success.withValues(alpha: 0.1)
            : context.themeColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: success
              ? context.themeColors.success.withValues(alpha: 0.3)
              : context.themeColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            success ? LucideIcons.circleCheckBig : LucideIcons.circleAlert,
            size: 48,
            color: success
                ? context.themeColors.success
                : context.themeColors.error,
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            success
                ? l10n.importWizImportComplete
                : l10n.importWizImportFailedGeneric,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: success
                  ? context.themeColors.success
                  : context.themeColors.error,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            success
                ? l10n.importWizImportSuccessMsg(
                    _importResult!.importedRows.toString(),
                  )
                : _importResult!.errorMessage ?? l10n.importWizImportErrorMsg,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (_importResult!.failedRows > 0) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              l10n.importWizFailedRows(_importResult!.failedRows.toString()),
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 底部操作按钮 ====================

  Widget _buildActions(AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 上一步
        if (_currentStep != WizardStep.selectFile && !_isImporting)
          OutlinedButton.icon(
            onPressed: _previousStep,
            icon: const Icon(LucideIcons.arrowLeft, size: 16),
            label: Text(l10n.importWizPreviousStep),
          ),
        const SizedBox(width: AppDesignSystem.space2),

        // 取消/关闭
        if (_currentStep == WizardStep.selectFile || _importResult != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              _importResult != null ? l10n.importWizClose : l10n.commonCancel,
            ),
          ),

        const Spacer(),

        // 下一步/开始导入
        if (_importResult == null) ...[
          FilledButton.icon(
            onPressed: _canGoNext() && !_isImporting ? _nextStep : null,
            icon: _isImporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _currentStep == WizardStep.confirmImport
                        ? LucideIcons.play
                        : LucideIcons.arrowRight,
                    size: 16,
                  ),
            label: Text(
              _isImporting
                  ? l10n.importWizImporting
                  : _currentStep == WizardStep.confirmImport
                  ? l10n.importWizStartImport
                  : l10n.importWizNextStep,
            ),
          ),
        ] else ...[
          // 导入完成后的重新导入按钮
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _importResult = null;
                _importProgress = null;
                _currentStep = WizardStep.selectFile;
                _completedSteps.clear();
              });
            },
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text(l10n.importWizReimport),
          ),
        ],
      ],
    );
  }

  // ==================== 通用组件 ====================

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppDesignSystem.space10),
          Icon(
            LucideIcons.inbox,
            size: 48,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space10),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

/// 验证错误
class ValidationError {
  final int rowIndex;
  final String columnName;
  final String message;
  final ValidationSeverity severity;

  const ValidationError({
    required this.rowIndex,
    required this.columnName,
    required this.message,
    this.severity = ValidationSeverity.warning,
  });
}

enum ValidationSeverity { warning, error }
