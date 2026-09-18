import 'dart:async';

import 'package:dbmaster/pro/data_import/smart_import_models.dart';
import 'package:dbmaster/models/task_models.dart';
import 'package:dbmaster/services/ai/ai_client.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/pro/data_import/file_analyzer.dart';
import 'package:dbmaster/pro/data_import/smart_import_service.dart';
import 'package:dbmaster/services/task/task_executor.dart';
import 'package:dbmaster/l10n/app_localizations.dart';

/// 导入任务执行器
class ImportTaskExecutor implements TaskExecutor {
  final ImportTaskConfig config;
  final DatabaseAdapter adapter;
  final AiClient aiClient;

  ImportTaskExecutor({
    required this.config,
    required this.adapter,
    required this.aiClient,
  });

  @override
  Future<void> execute({
    required Function(TaskProgressUpdate) onProgress,
    required Function(TaskLog) onLog,
    required Function() isCancelled,
    // l10n 对象（可选）：传入后 executor 内所有用户可见文案走本地化
    AppLocalizations? l10n,
  }) async {
    onLog(TaskLog.info(l10n?.taskExecutorAnalyzeFile(config.filePath) ?? '开始分析文件: ${config.filePath}'));

    // 1. 分析文件
    final analysis = await FileAnalyzer.analyzeFile(config.filePath);
    onLog(
      TaskLog.info(
        l10n?.taskExecutorFileFormat(
              analysis.format.name.toUpperCase(),
              analysis.encoding,
              analysis.estimatedTotalRows?.toString() ?? (l10n?.importWizUnknown ?? '未知'),
            ) ??
            '文件格式: ${analysis.format.name.toUpperCase()}, 编码: ${analysis.encoding}, 预估行数: ${analysis.estimatedTotalRows ?? "未知"}',
      ),
    );

    if (isCancelled()) return;

    // 2. 检查目标表是否存在
    final service = SmartImportService(adapter: adapter, aiClient: aiClient);
    final tableExists = await service.tableExists(config.targetTable);

    if (!tableExists) {
      if (config.createTableIfNotExists && config.createTableSQL != null) {
        onLog(TaskLog.info(l10n?.taskExecutorTableNotExists ?? '表不存在，正在创建表...'));
        final created = await service.createTable(config.createTableSQL!);
        if (!created) {
          throw Exception(l10n?.taskExecutorTableCreateFailed ?? '创建表失败');
        }
        onLog(TaskLog.success(l10n?.taskExecutorTableCreated ?? '表创建成功'));
      } else {
        throw Exception(l10n?.taskExecutorTableNotExistsError(config.targetTable) ?? '目标表 "${config.targetTable}" 不存在，请先创建表');
      }
    }

    if (isCancelled()) return;

    // 3. 获取表结构并生成列映射
    final tableColumns = await service.getTableColumns(config.targetTable);
    final tableColumnNames = tableColumns
        .map((c) => c['name'] as String)
        .toList();
    final columnMappings = service.generateColumnMappings(
      fileColumns: analysis.fields,
      tableColumns: tableColumnNames,
    );

    final mappedCount = columnMappings.where((m) => m.isMapped).length;
    onLog(TaskLog.info(l10n?.taskExecutorColumnMapping(mappedCount.toString(), columnMappings.length.toString()) ?? '列映射: $mappedCount/${columnMappings.length} 列已映射'));

    if (mappedCount == 0) {
      throw Exception(l10n?.taskExecutorNoColumnMapping ?? '没有可用的列映射，请检查文件字段与表字段是否匹配');
    }

    if (isCancelled()) return;

    // 4. 执行导入
    onLog(TaskLog.info(l10n?.taskExecutorStartImport ?? '开始导入数据...'));

    final importConfig = SmartImportConfig(
      filePath: config.filePath,
      batchSize: 1000,
    );

    final result = await service.importData(
      config: importConfig,
      analysis: analysis,
      tableName: config.targetTable,
      columnMappings: columnMappings,
      l10n: l10n,
      onProgress: (progress) {
        if (isCancelled()) return;

        final percent = progress.totalRecords > 0
            ? (progress.importedRecords / progress.totalRecords * 100).toInt()
            : 0;

        onProgress(
          TaskProgressUpdate(
            progress: percent.clamp(0, 100),
            phase: progress.phaseDescription,
            processedRows: progress.importedRecords,
            totalRows: progress.totalRecords,
          ),
        );
      },
      onLog: (message, {isError = false}) {
        if (isError) {
          onLog(TaskLog.error(message));
        } else {
          onLog(TaskLog.info(message));
        }
      },
    );

    if (isCancelled()) return;

    if (result.success) {
      onLog(
        TaskLog.success(
          l10n?.taskExecutorImportComplete(result.importedRows.toString(), result.failedRows.toString()) ??
              '导入完成! 成功: ${result.importedRows} 行, 失败: ${result.failedRows} 行',
        ),
      );
      onProgress(
        TaskProgressUpdate(
          progress: 100,
          phase: l10n?.taskExecutorImportFinished ?? '导入完成',
          processedRows: result.importedRows,
          totalRows: result.importedRows + result.failedRows,
        ),
      );
    } else {
      throw Exception(result.errorMessage ?? (l10n?.importWizImportFailedGeneric ?? '导入失败'));
    }
  }
}
