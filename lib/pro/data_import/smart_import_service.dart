import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dbmaster/pro/data_import/smart_import_models.dart';
import 'package:dbmaster/services/ai/ai_client.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/pro/data_import/file_analyzer.dart';
import 'package:dbmaster/services/pii_masker.dart';
import 'package:dbmaster/pro/data_import/streaming_file_reader.dart';
import 'package:dbmaster/l10n/app_localizations.dart';

/// 智能导入服务
/// 协调文件分析、AI 建表、分批导入的完整流程
class SmartImportService {
  final DatabaseAdapter adapter;
  final AiClient aiClient;

  SmartImportService({required this.adapter, required this.aiClient});

  /// 取消标记
  bool _isCancelled = false;

  /// 取消导入
  void cancel() {
    _isCancelled = true;
  }

  /// 重置取消状态
  void reset() {
    _isCancelled = false;
  }

  /// 分析文件
  Future<FileAnalysisResult> analyzeFile(String filePath) async {
    return await FileAnalyzer.analyzeFile(filePath);
  }

  /// 使用 AI 生成/优化建表语句
  Future<Map<String, dynamic>> generateCreateTableSQL({
    required FileAnalysisResult analysis,
    required String provider,
    required String model,
    required String apiKey,
    String? targetTable,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final sampleDataJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(analysis.sampleData.take(5).toList());

    final fieldsDescription = analysis.fields
        .map((field) {
          final type = analysis.inferredTypes[field] ?? 'TEXT';
          return '- $field: $type';
        })
        .join('\n');

    final prompt =
        '''你是一个数据库专家。请根据以下文件分析结果，生成一个优化的 CREATE TABLE 语句。

【文件信息】
- 格式: ${analysis.format.name.toUpperCase()}
- 编码: ${analysis.encoding}
- 分隔符: ${analysis.delimiter ?? 'N/A'}
- 字段数: ${analysis.fields.length}
- 样本行数: ${analysis.sampleData.length}

【字段列表（初步推断类型）】
$fieldsDescription

【样本数据（前5行）】
$sampleDataJson

【要求】
1. 表名建议使用: ${targetTable ?? _suggestTableName(analysis)}
2. 根据数据特点选择最合适的数据库类型
3. 如果有 ID 列，设为 PRIMARY KEY AUTO_INCREMENT
4. 如果有时间戳列，使用 DATETIME 或 TIMESTAMP
5. 返回格式必须是纯 SQL，不要加 markdown 代码块
6. 只需要返回 CREATE TABLE 语句

请生成优化的 CREATE TABLE 语句：''';

    final response = await aiClient.chat(
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      message: prompt,
      systemPrompt:
          '你是数据库专家，擅长根据数据结构生成优化的 CREATE TABLE 语句。只返回纯 SQL，不要 markdown 格式。',
      timeout: timeout,
    );

    final sql = _extractSQL(response.content ?? '');
    final suggestedTable =
        _extractTableName(sql) ?? targetTable ?? _suggestTableName(analysis);

    return {
      'sql': sql,
      'tableName': suggestedTable,
      'fields': analysis.fields,
      'types': analysis.inferredTypes,
    };
  }

  /// 检查表是否存在
  Future<bool> tableExists(String tableName) async {
    try {
      final tables = await adapter.getTables();
      return tables.any((t) => t.toLowerCase() == tableName.toLowerCase());
    } catch (e) {
      developer.log('检查表存在性失败: $e', name: 'SmartImportService');
      return false;
    }
  }

  /// 获取表行数
  Future<int> getTableRowCount(String tableName) async {
    try {
      return await adapter.getTableRowCount(tableName);
    } catch (e) {
      developer.log('获取表行数失败: $e', name: 'SmartImportService');
      return 0;
    }
  }

  /// 获取表结构（列信息）
  Future<List<Map<String, dynamic>>> getTableColumns(String tableName) async {
    try {
      final columns = await adapter.getTableColumns(tableName);
      return columns
          .map(
            (col) => {
              'name': col.name,
              'type': col.type,
              'isNullable': col.isNullable,
              'defaultValue': col.defaultValue,
              'isPrimaryKey': col.isPrimaryKey,
            },
          )
          .toList();
    } catch (e) {
      developer.log('获取表结构失败: $e', name: 'SmartImportService');
      return [];
    }
  }

  /// 自动生成列映射（基于名称相似度）
  List<ColumnMapping> generateColumnMappings({
    required List<String> fileColumns,
    required List<String> tableColumns,
  }) {
    final mappings = <ColumnMapping>[];

    for (final fileCol in fileColumns) {
      String? bestMatch;
      double bestScore = 0;

      for (final tableCol in tableColumns) {
        final score = _calculateSimilarity(fileCol, tableCol);
        if (score > bestScore && score > 0.6) {
          bestScore = score;
          bestMatch = tableCol;
        }
      }

      mappings.add(ColumnMapping(fileColumn: fileCol, tableColumn: bestMatch));
    }

    return mappings;
  }

  /// 计算两个字符串的相似度（0-1）
  double _calculateSimilarity(String a, String b) {
    final a1 = a.toLowerCase().trim();
    final b1 = b.toLowerCase().trim();

    // 完全匹配
    if (a1 == b1) return 1.0;

    // 包含关系
    if (a1.contains(b1) || b1.contains(a1)) return 0.9;

    // 编辑距离
    final distance = _levenshteinDistance(a1, b1);
    final maxLen = a1.length > b1.length ? a1.length : b1.length;
    if (maxLen == 0) return 1.0;

    return 1.0 - (distance / maxLen);
  }

  /// 计算编辑距离
  int _levenshteinDistance(String a, String b) {
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= n; j++) {
      dp[0][j] = j;
    }

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] =
              1 +
              [
                dp[i - 1][j],
                dp[i][j - 1],
                dp[i - 1][j - 1],
              ].reduce((a, b) => a < b ? a : b);
        }
      }
    }

    return dp[m][n];
  }

  /// 检测 PII 敏感数据
  PIIDetectionResult detectPII({
    required List<String> columns,
    required List<Map<String, dynamic>> sampleData,
  }) {
    final masker = PIIMasker();
    final sensitiveColumns = <PIIColumnInfo>[];

    for (final column in columns) {
      // 检查列名是否匹配 PII 模式
      String? detectedType;
      String? typeDisplay;

      for (final entry in masker.patterns.entries) {
        final pattern = entry.value;
        if (pattern.regex.hasMatch(column)) {
          detectedType = entry.key;
          typeDisplay = pattern.description;
          break;
        }
      }

      // 如果列名未匹配，检查内容
      if (detectedType == null && sampleData.isNotEmpty) {
        for (final entry in masker.patterns.entries) {
          final pattern = entry.value;
          int matchCount = 0;

          for (final row in sampleData.take(5)) {
            final value = row[column]?.toString() ?? '';
            if (pattern.regex.hasMatch(value)) {
              matchCount++;
            }
          }

          if (matchCount >= 2) {
            detectedType = entry.key;
            typeDisplay = pattern.description;
            break;
          }
        }
      }

      if (detectedType != null) {
        final sampleValue = sampleData.isNotEmpty
            ? sampleData.first[column]?.toString()
            : null;

        sensitiveColumns.add(
          PIIColumnInfo(
            columnName: column,
            piiType: detectedType,
            piiTypeDisplay: typeDisplay ?? detectedType,
            sampleValue: sampleValue != null
                ? masker.maskValue(sampleValue)
                : null,
          ),
        );
      }
    }

    return PIIDetectionResult(sensitiveColumns: sensitiveColumns);
  }

  /// 生成数据预览（应用列映射）
  DataPreviewResult generatePreview({
    required FileAnalysisResult analysis,
    required List<ColumnMapping> columnMappings,
    DataPreviewConfig config = const DataPreviewConfig(),
  }) {
    final previewData = <Map<String, dynamic>>[];
    final mappedColumns = columnMappings.where((m) => m.isMapped).toList();

    for (final row in analysis.sampleData.take(config.maxPreviewRows)) {
      final mappedRow = <String, dynamic>{};
      for (final mapping in mappedColumns) {
        if (mapping.tableColumn != null) {
          mappedRow[mapping.tableColumn!] = row[mapping.fileColumn];
        }
      }
      previewData.add(mappedRow);
    }

    // 检测 PII
    PIIDetectionResult? piiResult;
    if (config.showPiiWarning) {
      final tableColumns = mappedColumns.map((m) => m.tableColumn!).toList();
      piiResult = detectPII(columns: tableColumns, sampleData: previewData);
    }

    return DataPreviewResult(
      previewData: previewData,
      columnMappings: columnMappings,
      piiResult: piiResult,
      totalRows: analysis.estimatedTotalRows ?? analysis.sampleData.length,
    );
  }

  /// 执行建表语句
  Future<bool> createTable(String createSQL) async {
    try {
      await adapter.executeQuery(createSQL);
      return true;
    } catch (e) {
      developer.log('建表失败: $e', name: 'SmartImportService');
      return false;
    }
  }

  /// 删除表
  Future<bool> dropTable(String tableName) async {
    try {
      await adapter.dropTable(tableName);
      return true;
    } catch (e) {
      developer.log('删除表失败: $e', name: 'SmartImportService');
      return false;
    }
  }

  /// 流式导入数据
  Future<SmartImportResult> importData({
    required SmartImportConfig config,
    required FileAnalysisResult analysis,
    required String tableName,
    List<ColumnMapping>? columnMappings,
    ConflictResolution conflictResolution = ConflictResolution.skip,
    void Function(SmartImportProgress)? onProgress,
    void Function(String message, {bool isError})? onLog,
    AppLocalizations? l10n,
  }) async {
    reset();

    final totalEstimatedRows = analysis.estimatedTotalRows ?? 0;
    int importedRows = 0;
    int failedRows = 0;
    int skippedRows = 0;
    int updatedRows = 0;
    int currentBatch = 0;
    final logs = <ImportLogEntry>[];

    final mappedFields = columnMappings != null
        ? columnMappings
              .where((m) => m.isMapped)
              .map((m) => m.tableColumn!)
              .toList()
        : analysis.fields;

    void addLog(String message, {bool isError = false}) {
      logs.add(
        ImportLogEntry(
          timestamp: DateTime.now(),
          message: message,
          level: isError ? LogLevel.error : LogLevel.info,
        ),
      );
      onLog?.call(message, isError: isError);
    }

    addLog(l10n?.importServiceStartImport(tableName) ?? '开始导入数据到表 "$tableName"...');
    if (columnMappings != null) {
      final mappedCount = columnMappings.where((m) => m.isMapped).length;
      addLog(l10n?.importServiceColumnMapping(mappedCount.toString(), columnMappings.length.toString()) ?? '列映射: $mappedCount/${columnMappings.length} 列已映射');
    }
    addLog(l10n?.importServiceConflictStrategy(_getConflictResolutionName(conflictResolution, l10n)) ?? '冲突处理策略: ${_getConflictResolutionName(conflictResolution, null)}');

    _notifyProgress(
      onProgress,
      SmartImportProgress(
        phase: SmartImportPhase.importing,
        phaseDescription: l10n?.importServiceImporting ?? '开始导入数据...',
        totalRecords: totalEstimatedRows,
        importedRecords: 0,
        tableName: tableName,
        logs: List.from(logs),
      ),
    );

    final reader = StreamingFileReader(
      filePath: config.filePath,
      format: analysis.format,
      encoding: analysis.encoding,
      delimiter: analysis.delimiter,
      fields: analysis.fields,
      hasHeader: analysis.hasHeader,
      batchSize: config.batchSize,
    );

    final result = await reader.readBatches(
      onBatch: (batch) async {
        if (_isCancelled) return;

        currentBatch++;
        bool batchSuccess = false;

        // 应用列映射转换数据
        final mappedBatch = columnMappings != null
            ? batch
                  .map((row) => _applyColumnMapping(row, columnMappings))
                  .toList()
            : batch;

        try {
          // 生成批量插入语句（使用映射后的字段名）
          final sql = _generateBatchInsertSQL(
            tableName,
            mappedFields,
            mappedBatch,
          );
          await adapter.executeQuery(sql);
          importedRows += mappedBatch.length;
          batchSuccess = true;
        } catch (e) {
          // 批量失败，尝试逐条插入
          addLog(l10n?.importServiceBatchInsertFailed(mappedBatch.length.toString()) ?? '批量插入失败（${mappedBatch.length}行），尝试逐条插入...', isError: true);

          int batchImported = 0;
          int batchFailed = 0;
          int batchSkipped = 0;
          int batchUpdated = 0;

          for (int i = 0; i < mappedBatch.length; i++) {
            if (_isCancelled) return;
            final row = mappedBatch[i];
            try {
              final sql = _generateInsertSQL(tableName, row);
              await adapter.executeQuery(sql);
              importedRows++;
              batchImported++;
            } catch (e) {
              final errorMsg = e.toString();

              // 根据冲突处理策略处理错误
              if (_isDuplicateError(errorMsg)) {
                switch (conflictResolution) {
                  case ConflictResolution.skip:
                    skippedRows++;
                    batchSkipped++;
                    break;
                  case ConflictResolution.update:
                    try {
                      await _updateExistingRow(tableName, row, mappedFields);
                      updatedRows++;
                      batchUpdated++;
                    } catch (updateError) {
                      failedRows++;
                      batchFailed++;
                      addLog(
                        l10n?.importServiceUpdateFailed(_truncateError(updateError.toString())) ?? '更新失败: ${_truncateError(updateError.toString())}',
                        isError: true,
                      );
                    }
                    break;
                  case ConflictResolution.abort:
                    throw Exception(l10n?.importWizConflictAbortDesc ?? '导入中止: 检测到重复键冲突');
                }
              } else if (_isDataTooLong(errorMsg)) {
                failedRows++;
                batchFailed++;
                final rowNum = importedRows + failedRows + skippedRows + updatedRows;
                addLog(
                  l10n?.importServiceDataTooLong(rowNum.toString()) ?? '第 $rowNum 行数据过长，已跳过',
                  isError: true,
                );
              } else {
                failedRows++;
                batchFailed++;
                final rowNum2 = importedRows + failedRows + skippedRows + updatedRows;
                addLog(
                  l10n?.importServiceRowInsertFailed(rowNum2.toString(), _truncateError(errorMsg)) ?? '第 $rowNum2 行插入失败: ${_truncateError(errorMsg)}',
                  isError: true,
                );
              }
            }
          }

          if (batchSkipped > 0) addLog(l10n?.importServiceBatchSkipped(batchSkipped.toString()) ?? '本批次跳过: $batchSkipped 行（重复）');
          if (batchUpdated > 0) addLog(l10n?.importServiceBatchUpdated(batchUpdated.toString()) ?? '本批次更新: $batchUpdated 行');
          if (batchFailed > 0) addLog(l10n?.importServiceBatchFailed(batchFailed.toString()) ?? '本批次失败: $batchFailed 行');
          if (batchImported > 0) addLog(l10n?.importServiceBatchSuccess(currentBatch.toString(), batchImported.toString()) ?? '本批次成功: $batchImported 行');
        }

        if (batchSuccess) {
          addLog(l10n?.importServiceBatchSuccess(currentBatch.toString(), mappedBatch.length.toString()) ?? '批次 $currentBatch: 成功导入 ${mappedBatch.length} 行');
        }

        _notifyProgress(
          onProgress,
          SmartImportProgress(
            phase: SmartImportPhase.importing,
            phaseDescription:
                l10n?.importServicePhaseProgress(importedRows.toString(), skippedRows.toString(), updatedRows.toString()) ?? '已导入 $importedRows 行，跳过 $skippedRows 行，更新 $updatedRows 行...',
            totalRecords: totalEstimatedRows,
            importedRecords: importedRows,
            failedRecords: failedRows,
            currentBatch: currentBatch,
            tableName: tableName,
            logs: List.from(logs),
          ),
        );
      },
      onProgress: (readBytes, totalBytes) {
        // 字节级进度
      },
    );

    if (_isCancelled) {
      final cancelMsg = l10n?.importServiceImportCancelled ?? '导入已取消';
      addLog(cancelMsg, isError: true);
      return SmartImportResult(
        success: false,
        importedRows: importedRows,
        failedRows: failedRows,
        tableName: tableName,
        analysisResult: analysis,
        errorMessage: cancelMsg,
      );
    }

    if (!result.success) {
      final fileErrMsg = l10n?.importServiceFileReadFailed(result.errorMessage ?? '') ?? '文件读取失败: ${result.errorMessage}';
      addLog(fileErrMsg, isError: true);
      return SmartImportResult(
        success: false,
        importedRows: importedRows,
        failedRows: failedRows,
        tableName: tableName,
        analysisResult: analysis,
        errorMessage: result.errorMessage ?? (l10n?.importWizImportFailedGeneric ?? '导入失败'),
      );
    }

    addLog(l10n?.importServiceImportComplete(importedRows.toString(), failedRows.toString()) ?? '数据导入完成！成功: $importedRows 行, 失败: $failedRows 行');

    return SmartImportResult(
      success: true,
      importedRows: importedRows,
      failedRows: failedRows,
      tableName: tableName,
      analysisResult: analysis,
    );
  }

  /// 判断是否为重复键错误
  bool _isDuplicateError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('duplicate') ||
        lower.contains('unique constraint') ||
        lower.contains('1062') || // MySQL error code
        lower.contains('重复');
  }

  /// 判断是否为数据过长错误
  bool _isDataTooLong(String error) {
    final lower = error.toLowerCase();
    return lower.contains('data too long') ||
        lower.contains('1406') || // MySQL error code
        lower.contains('value too long');
  }

  /// 截断错误信息
  String _truncateError(String error) {
    if (error.length > 100) {
      return '${error.substring(0, 100)}...';
    }
    return error;
  }

  /// 生成批量插入语句
  String _generateBatchInsertSQL(
    String tableName,
    List<String> fields,
    List<Map<String, dynamic>> batch,
  ) {
    if (batch.isEmpty) return '';

    final values = batch
        .map((row) {
          final valueList = fields
              .map((field) {
                final value = row[field];
                return _formatValue(value);
              })
              .join(', ');
          return '($valueList)';
        })
        .join(',\n  ');

    final fieldList = fields.map((f) => '`$f`').join(', ');
    return 'INSERT INTO `$tableName` ($fieldList) VALUES\n  $values';
  }

  /// 生成单条插入语句
  String _generateInsertSQL(String tableName, Map<String, dynamic> row) {
    final fields = row.keys.toList();
    final values = fields.map((field) => _formatValue(row[field])).join(', ');
    final fieldList = fields.map((f) => '`$f`').join(', ');
    return 'INSERT INTO `$tableName` ($fieldList) VALUES ($values)';
  }

  /// 格式化值
  String _formatValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is String) {
      final escaped = value.replaceAll("'", "''");
      return "'$escaped'";
    }
    if (value is bool) return value ? '1' : '0';
    return value.toString();
  }

  /// 建议表名
  String _suggestTableName(FileAnalysisResult analysis) {
    final fileName = analysis.fileName.split('.').first;
    // 清理文件名，只保留字母数字下划线
    final cleanName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return cleanName.isEmpty ? 'imported_data' : cleanName;
  }

  /// 从 AI 响应中提取 SQL
  String _extractSQL(String response) {
    // 尝试从 markdown 代码块提取
    final codeBlockPattern = RegExp(
      r'```(?:sql)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final match = codeBlockPattern.firstMatch(response);
    if (match != null) {
      return match.group(1)?.trim() ?? response.trim();
    }
    return response.trim();
  }

  /// 从 CREATE TABLE 语句中提取表名
  String? _extractTableName(String sql) {
    final pattern = RegExp(
      r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[`\x22\x27]?(\w+)[`\x22\x27]?',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(sql);
    return match?.group(1);
  }

  /// 应用列映射转换数据行
  Map<String, dynamic> _applyColumnMapping(
    Map<String, dynamic> row,
    List<ColumnMapping> mappings,
  ) {
    final result = <String, dynamic>{};
    for (final mapping in mappings) {
      if (mapping.isMapped && row.containsKey(mapping.fileColumn)) {
        result[mapping.tableColumn!] = row[mapping.fileColumn];
      }
    }
    return result;
  }

  /// 更新已存在的行（基于主键或所有字段）
  Future<void> _updateExistingRow(
    String tableName,
    Map<String, dynamic> row,
    List<String> fields,
  ) async {
    // 尝试找到主键
    final pkFields = fields
        .where(
          (f) => f.toLowerCase().endsWith('_id') || f.toLowerCase() == 'id',
        )
        .toList();

    if (pkFields.isNotEmpty) {
      // 使用主键更新
      final pkField = pkFields.first;
      final pkValue = row[pkField];
      if (pkValue != null) {
        final setClauses = row.entries
            .where((e) => e.key != pkField)
            .map((e) {
              return '`${e.key}` = ${_formatValue(e.value)}';
            })
            .join(', ');

        final sql =
            'UPDATE `$tableName` SET $setClauses WHERE `$pkField` = ${_formatValue(pkValue)}';
        await adapter.executeQuery(sql);
        return;
      }
    }

    // 没有主键，使用所有字段作为条件（可能不准确，但作为后备）
    final whereClauses = row.entries
        .map((e) {
          return '`${e.key}` = ${_formatValue(e.value)}';
        })
        .join(' AND ');

    final sql =
        'UPDATE `$tableName` SET ${row.entries.map((e) => '`${e.key}` = ${_formatValue(e.value)}').join(', ')} WHERE $whereClauses';
    await adapter.executeQuery(sql);
  }

  /// 获取冲突处理策略名称
  String _getConflictResolutionName(ConflictResolution resolution, AppLocalizations? l10n) {
    switch (resolution) {
      case ConflictResolution.skip:
        return l10n?.importWizConflictSkipName ?? '跳过重复行';
      case ConflictResolution.update:
        return l10n?.importWizConflictUpdateName ?? '更新现有行';
      case ConflictResolution.abort:
        return l10n?.importWizConflictAbortName ?? '中止导入';
    }
  }

  /// 通知进度
  void _notifyProgress(
    void Function(SmartImportProgress)? callback,
    SmartImportProgress progress,
  ) {
    if (callback != null && !_isCancelled) {
      callback(progress);
    }
  }
}
