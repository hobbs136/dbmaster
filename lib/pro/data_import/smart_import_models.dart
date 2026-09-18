import 'package:dbmaster/models/import_models.dart';

/// 智能导入阶段
enum SmartImportPhase {
  /// 空闲
  idle,

  /// 分析文件中
  analyzing,

  /// AI 分析中
  aiAnalyzing,

  /// 检查目标表
  checkingTable,

  /// 等待用户确认（表已存在）
  waitingConfirmation,

  /// 创建表中
  creatingTable,

  /// 导入数据中
  importing,

  /// 完成
  completed,

  /// 失败
  failed,

  /// 已取消
  cancelled,
}

/// 智能导入配置
class SmartImportConfig {
  /// 文件路径
  final String filePath;

  /// 目标表名（可选，AI 可推断）
  final String? targetTable;

  /// 分批大小
  final int batchSize;

  /// 文件大小上限（字节）
  final int maxFileSize;

  /// 样本行数（用于 AI 分析）
  final int sampleRows;

  const SmartImportConfig({
    required this.filePath,
    this.targetTable,
    this.batchSize = 1000,
    this.maxFileSize = 500 * 1024 * 1024, // 500MB
    this.sampleRows = 100,
  });

  SmartImportConfig copyWith({
    String? filePath,
    String? targetTable,
    int? batchSize,
    int? maxFileSize,
    int? sampleRows,
  }) {
    return SmartImportConfig(
      filePath: filePath ?? this.filePath,
      targetTable: targetTable ?? this.targetTable,
      batchSize: batchSize ?? this.batchSize,
      maxFileSize: maxFileSize ?? this.maxFileSize,
      sampleRows: sampleRows ?? this.sampleRows,
    );
  }
}

/// 文件分析结果
class FileAnalysisResult {
  /// 文件格式
  final ImportFormat format;

  /// 检测到的编码
  final String encoding;

  /// 分隔符（CSV）
  final String? delimiter;

  /// 是否有表头
  final bool hasHeader;

  /// 字段列表
  final List<String> fields;

  /// 字段类型推断
  final Map<String, String> inferredTypes;

  /// 样本数据（前 N 行）
  final List<Map<String, dynamic>> sampleData;

  /// 文件总行数（估计）
  final int? estimatedTotalRows;

  /// 文件名
  final String fileName;

  /// 文件大小（字节）
  final int fileSize;

  /// 是否成功
  final bool success;

  /// 错误消息
  final String? errorMessage;

  const FileAnalysisResult({
    required this.format,
    required this.encoding,
    this.delimiter,
    required this.hasHeader,
    required this.fields,
    required this.inferredTypes,
    required this.sampleData,
    this.estimatedTotalRows,
    required this.fileName,
    required this.fileSize,
    required this.success,
    this.errorMessage,
  });

  FileAnalysisResult copyWith({
    ImportFormat? format,
    String? encoding,
    String? delimiter,
    bool? hasHeader,
    List<String>? fields,
    Map<String, String>? inferredTypes,
    List<Map<String, dynamic>>? sampleData,
    int? estimatedTotalRows,
    String? fileName,
    int? fileSize,
    bool? success,
    String? errorMessage,
  }) {
    return FileAnalysisResult(
      format: format ?? this.format,
      encoding: encoding ?? this.encoding,
      delimiter: delimiter ?? this.delimiter,
      hasHeader: hasHeader ?? this.hasHeader,
      fields: fields ?? this.fields,
      inferredTypes: inferredTypes ?? this.inferredTypes,
      sampleData: sampleData ?? this.sampleData,
      estimatedTotalRows: estimatedTotalRows ?? this.estimatedTotalRows,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      success: success ?? this.success,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 导入日志条目
class ImportLogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;

  const ImportLogEntry({
    required this.timestamp,
    required this.message,
    this.level = LogLevel.info,
  });
}

enum LogLevel { info, warning, error, success }

/// 智能导入进度
class SmartImportProgress {
  /// 当前阶段
  final SmartImportPhase phase;

  /// 阶段描述
  final String? phaseDescription;

  /// 总记录数
  final int totalRecords;

  /// 已导入记录数
  final int importedRecords;

  /// 失败记录数
  final int failedRecords;

  /// 当前批次
  final int currentBatch;

  /// 总批次数
  final int totalBatches;

  /// 错误消息
  final String? errorMessage;

  /// 目标表名
  final String? tableName;

  /// 导入日志
  final List<ImportLogEntry> logs;

  /// 查询到的总行数（导入完成后）
  final int? finalRowCount;

  const SmartImportProgress({
    required this.phase,
    this.phaseDescription,
    this.totalRecords = 0,
    this.importedRecords = 0,
    this.failedRecords = 0,
    this.currentBatch = 0,
    this.totalBatches = 0,
    this.errorMessage,
    this.tableName,
    this.logs = const [],
    this.finalRowCount,
  });

  double get percentage {
    if (totalRecords == 0) return 0;
    return (importedRecords / totalRecords * 100).clamp(0, 100);
  }

  bool get isCompleted =>
      phase == SmartImportPhase.completed ||
      phase == SmartImportPhase.failed ||
      phase == SmartImportPhase.cancelled;

  SmartImportProgress copyWith({
    SmartImportPhase? phase,
    String? phaseDescription,
    int? totalRecords,
    int? importedRecords,
    int? failedRecords,
    int? currentBatch,
    int? totalBatches,
    String? errorMessage,
    String? tableName,
    List<ImportLogEntry>? logs,
    int? finalRowCount,
  }) {
    return SmartImportProgress(
      phase: phase ?? this.phase,
      phaseDescription: phaseDescription ?? this.phaseDescription,
      totalRecords: totalRecords ?? this.totalRecords,
      importedRecords: importedRecords ?? this.importedRecords,
      failedRecords: failedRecords ?? this.failedRecords,
      currentBatch: currentBatch ?? this.currentBatch,
      totalBatches: totalBatches ?? this.totalBatches,
      errorMessage: errorMessage ?? this.errorMessage,
      tableName: tableName ?? this.tableName,
      logs: logs ?? this.logs,
      finalRowCount: finalRowCount ?? this.finalRowCount,
    );
  }
}

/// 智能导入结果
class SmartImportResult {
  /// 是否成功
  final bool success;

  /// 导入的行数
  final int importedRows;

  /// 失败的行数
  final int failedRows;

  /// 目标表名
  final String tableName;

  /// 文件分析结果
  final FileAnalysisResult? analysisResult;

  /// 错误消息
  final String? errorMessage;

  const SmartImportResult({
    required this.success,
    this.importedRows = 0,
    this.failedRows = 0,
    required this.tableName,
    this.analysisResult,
    this.errorMessage,
  });

  SmartImportResult copyWith({
    bool? success,
    int? importedRows,
    int? failedRows,
    String? tableName,
    FileAnalysisResult? analysisResult,
    String? errorMessage,
  }) {
    return SmartImportResult(
      success: success ?? this.success,
      importedRows: importedRows ?? this.importedRows,
      failedRows: failedRows ?? this.failedRows,
      tableName: tableName ?? this.tableName,
      analysisResult: analysisResult ?? this.analysisResult,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 表存在确认结果
enum TableExistAction {
  /// 覆盖（删除并重建）
  overwrite,

  /// 追加数据
  append,

  /// 取消
  cancel,
}

/// 列映射关系
class ColumnMapping {
  /// 文件中的列名
  final String fileColumn;

  /// 映射到的表列名（null 表示不导入该列）
  final String? tableColumn;

  /// 是否导入此列
  bool get isMapped => tableColumn != null && tableColumn!.isNotEmpty;

  const ColumnMapping({required this.fileColumn, this.tableColumn});

  ColumnMapping copyWith({String? fileColumn, String? tableColumn}) {
    return ColumnMapping(
      fileColumn: fileColumn ?? this.fileColumn,
      tableColumn: tableColumn ?? this.tableColumn,
    );
  }
}

/// 冲突处理策略
enum ConflictResolution {
  /// 跳过冲突行
  skip,

  /// 更新现有行
  update,

  /// 中止导入
  abort,
}

/// PII 检测结果
class PIIDetectionResult {
  /// 检测到的敏感列
  final List<PIIColumnInfo> sensitiveColumns;

  /// 是否包含敏感数据
  bool get hasSensitiveData => sensitiveColumns.isNotEmpty;

  const PIIDetectionResult({this.sensitiveColumns = const []});
}

/// PII 列信息
class PIIColumnInfo {
  /// 列名
  final String columnName;

  /// 检测到的 PII 类型
  final String piiType;

  /// PII 类型显示名称
  final String piiTypeDisplay;

  /// 样本值（脱敏后）
  final String? sampleValue;

  /// 匹配的行数
  final int matchCount;

  const PIIColumnInfo({
    required this.columnName,
    required this.piiType,
    required this.piiTypeDisplay,
    this.sampleValue,
    this.matchCount = 0,
  });
}

/// 数据预览配置
class DataPreviewConfig {
  /// 最多预览行数
  final int maxPreviewRows;

  /// 是否应用列映射
  final bool applyMapping;

  /// 是否显示 PII 警告
  final bool showPiiWarning;

  const DataPreviewConfig({
    this.maxPreviewRows = 10,
    this.applyMapping = true,
    this.showPiiWarning = true,
  });
}

/// 数据预览结果
class DataPreviewResult {
  /// 预览数据（已应用列映射）
  final List<Map<String, dynamic>> previewData;

  /// 使用的列映射
  final List<ColumnMapping> columnMappings;

  /// PII 检测结果
  final PIIDetectionResult? piiResult;

  /// 总行数
  final int totalRows;

  const DataPreviewResult({
    required this.previewData,
    required this.columnMappings,
    this.piiResult,
    required this.totalRows,
  });
}
