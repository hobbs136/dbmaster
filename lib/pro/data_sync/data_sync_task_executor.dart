import 'dart:async';

import 'package:dbmaster/pro/data_sync/data_sync_models.dart';
import 'package:dbmaster/models/task_models.dart';
import 'package:dbmaster/pro/data_sync/data_sync_service.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/task/task_executor.dart';

/// 数据同步任务执行器
class DataSyncTaskExecutor implements TaskExecutor {
  final DataSyncTaskConfig config;
  final DatabaseService databaseService;

  DataSyncTaskExecutor({required this.config, required this.databaseService});

  @override
  Future<void> execute({
    required Function(TaskProgressUpdate) onProgress,
    required Function(TaskLog) onLog,
    required Function() isCancelled,
  }) async {
    onLog(
      TaskLog.info('开始数据同步: ${config.sourceTable} → ${config.targetTable}'),
    );
    onLog(
      TaskLog.info('源: ${config.sourceConnectionId}/${config.sourceDatabase}'),
    );
    onLog(
      TaskLog.info('目标: ${config.targetConnectionId}/${config.targetDatabase}'),
    );

    // 获取源和目标 adapter
    final sourceAdapter = databaseService.getAdapter(config.sourceConnectionId);
    final targetAdapter = databaseService.getAdapter(config.targetConnectionId);

    if (sourceAdapter == null) {
      throw Exception('源连接未找到: ${config.sourceConnectionId}');
    }
    if (targetAdapter == null) {
      throw Exception('目标连接未找到: ${config.targetConnectionId}');
    }

    // 构建 DataSyncConfig
    final syncConfig = _buildDataSyncConfig();

    // 创建服务并执行
    final service = DataSyncService(
      sourceAdapter: sourceAdapter,
      targetAdapter: targetAdapter,
    );

    int? totalRows;

    await for (final progress in service.sync(syncConfig)) {
      if (isCancelled()) {
        onLog(TaskLog.warning('同步已取消'));
        onProgress(
          TaskProgressUpdate(
            progress: progress.overallPercent?.toInt() ?? 0,
            phase: '已取消',
            processedRows: progress.syncedRows,
            totalRows: totalRows,
          ),
        );
        throw Exception('同步已取消');
      }

      if (progress.totalRows != null) {
        totalRows = progress.totalRows;
      }

      final percent = progress.overallPercent != null
          ? (progress.overallPercent! * 100).toInt()
          : 0;

      onProgress(
        TaskProgressUpdate(
          progress: percent.clamp(0, 100),
          phase: progress.phase,
          processedRows: progress.syncedRows,
          totalRows: totalRows,
        ),
      );

      // 记录日志
      if (progress.phase.contains('失败')) {
        onLog(TaskLog.warning(progress.phase));
      } else if (progress.isCompleted) {
        onLog(TaskLog.success(progress.phase));
      } else if (!progress.isCancelled) {
        onLog(TaskLog.info(progress.phase));
      }

      // 给 UI 刷新机会
      await Future.delayed(Duration.zero);
    }
  }

  DataSyncConfig _buildDataSyncConfig() {
    final segmentConfig = _buildSegmentConfig();
    final targetStrategy = _parseTargetStrategy(config.targetStrategy);

    return DataSyncConfig(
      sourceConnectionId: config.sourceConnectionId,
      sourceDatabase: config.sourceDatabase,
      sourceTable: config.sourceTable,
      targetConnectionId: config.targetConnectionId,
      targetDatabase: config.targetDatabase,
      targetTable: config.targetTable,
      segmentConfig: segmentConfig,
      pageSize: config.pageSize,
      targetStrategy: targetStrategy,
      segmentIntervalMs: config.segmentIntervalMs,
      pageIntervalMs: config.pageIntervalMs,
    );
  }

  SegmentConfig _buildSegmentConfig() {
    if (config.segmentType == 'time') {
      final unit = _parseTimeUnit(config.timeUnit ?? 'minute');
      return TimeSegmentConfig(
        fieldName: config.segmentField,
        unit: unit,
        interval: config.timeInterval ?? 60,
      );
    } else {
      return NumericSegmentConfig(
        fieldName: config.segmentField,
        segmentSize: config.numericSegmentSize ?? 100000,
      );
    }
  }

  TimeUnit _parseTimeUnit(String unit) {
    switch (unit.toLowerCase()) {
      case 'minute':
      case 'minutes':
        return TimeUnit.minute;
      case 'hour':
      case 'hours':
        return TimeUnit.hour;
      case 'day':
      case 'days':
        return TimeUnit.day;
      default:
        return TimeUnit.minute;
    }
  }

  TargetStrategy _parseTargetStrategy(String strategy) {
    switch (strategy.toLowerCase()) {
      case 'truncate':
        return TargetStrategy.truncate;
      case 'append':
        return TargetStrategy.append;
      case 'replace':
        return TargetStrategy.replace;
      case 'upsert':
        return TargetStrategy.upsert;
      default:
        return TargetStrategy.append;
    }
  }
}
