/// 导入数据模型
/// 支持的数据格式：CSV, JSON
library;

/// 导入格式枚举
enum ImportFormat { csv, json, excel }

/// 导入状态枚举
enum ImportStatus {
  /// 准备导入
  ready,

  /// 正在导入
  importing,

  /// 导入成功
  success,

  /// 导入失败
  failed,
}

/// 导入配置
class ImportConfig {
  /// 目标表名
  final String tableName;

  /// 数据格式
  final ImportFormat format;

  /// 是否包含表头（CSV）
  final bool hasHeader;

  /// 字段分隔符（CSV）
  final String delimiter;

  /// 是否覆盖已存在的表
  final bool overwriteTable;

  /// 批量插入大小
  final int batchSize;

  const ImportConfig({
    required this.tableName,
    required this.format,
    this.hasHeader = true,
    this.delimiter = ',',
    this.overwriteTable = false,
    this.batchSize = 100,
  });

  /// 复制并更新配置
  ImportConfig copyWith({
    String? tableName,
    ImportFormat? format,
    bool? hasHeader,
    String? delimiter,
    bool? overwriteTable,
    int? batchSize,
  }) {
    return ImportConfig(
      tableName: tableName ?? this.tableName,
      format: format ?? this.format,
      hasHeader: hasHeader ?? this.hasHeader,
      delimiter: delimiter ?? this.delimiter,
      overwriteTable: overwriteTable ?? this.overwriteTable,
      batchSize: batchSize ?? this.batchSize,
    );
  }
}

/// 导入进度信息
class ImportProgress {
  /// 总记录数
  final int totalRecords;

  /// 已导入记录数
  final int importedRecords;

  /// 失败记录数
  final int failedRecords;

  /// 当前状态
  final ImportStatus status;

  /// 错误消息（失败时）
  final String? errorMessage;

  const ImportProgress({
    required this.totalRecords,
    required this.importedRecords,
    this.failedRecords = 0,
    required this.status,
    this.errorMessage,
  });

  /// 计算进度百分比（0-100）
  double get progress {
    if (totalRecords == 0) return 0;
    return (importedRecords / totalRecords * 100).clamp(0, 100);
  }

  /// 是否完成
  bool get isCompleted =>
      status == ImportStatus.success || status == ImportStatus.failed;

  /// 复制并更新进度
  ImportProgress copyWith({
    int? totalRecords,
    int? importedRecords,
    int? failedRecords,
    ImportStatus? status,
    String? errorMessage,
  }) {
    return ImportProgress(
      totalRecords: totalRecords ?? this.totalRecords,
      importedRecords: importedRecords ?? this.importedRecords,
      failedRecords: failedRecords ?? this.failedRecords,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 导入数据行
class ImportDataRow {
  /// 行数据（字段名 -> 值）
  final Map<String, dynamic> data;

  /// 行号（1-based）
  final int rowNumber;

  /// 是否有效
  final bool isValid;

  /// 错误消息
  final String? errorMessage;

  const ImportDataRow({
    required this.data,
    required this.rowNumber,
    this.isValid = true,
    this.errorMessage,
  });

  /// 复制并更新
  ImportDataRow copyWith({
    Map<String, dynamic>? data,
    int? rowNumber,
    bool? isValid,
    String? errorMessage,
  }) {
    return ImportDataRow(
      data: data ?? this.data,
      rowNumber: rowNumber ?? this.rowNumber,
      isValid: isValid ?? this.isValid,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 导入预览结果
class ImportPreview {
  /// 数据格式
  final ImportFormat format;

  /// 文件名
  final String fileName;

  /// 解析的数据
  final List<ImportDataRow> data;

  /// 字段列表
  final List<String> fields;

  /// 总行数
  final int totalRows;

  /// 是否成功
  final bool success;

  /// 错误消息
  final String? errorMessage;

  const ImportPreview({
    required this.format,
    required this.fileName,
    required this.data,
    required this.fields,
    required this.totalRows,
    required this.success,
    this.errorMessage,
  });

  /// 复制并更新
  ImportPreview copyWith({
    ImportFormat? format,
    String? fileName,
    List<ImportDataRow>? data,
    List<String>? fields,
    int? totalRows,
    bool? success,
    String? errorMessage,
  }) {
    return ImportPreview(
      format: format ?? this.format,
      fileName: fileName ?? this.fileName,
      data: data ?? this.data,
      fields: fields ?? this.fields,
      totalRows: totalRows ?? this.totalRows,
      success: success ?? this.success,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
