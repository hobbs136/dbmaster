import 'dart:async';

import 'package:dbmaster/pro/data_sync/data_sync_models.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/pro/data_sync/batch_inserter.dart';
import 'package:dbmaster/pro/data_sync/cursor_paginator.dart';
import 'package:dbmaster/pro/data_sync/segment_calculator.dart';

/// 数据同步服务
/// 协调分段、分页查询、批量插入的全流程
class DataSyncService {
  final DatabaseAdapter sourceAdapter;
  final DatabaseAdapter targetAdapter;
  final AppLocalizations? l10n;

  DataSyncService({
    required this.sourceAdapter,
    required this.targetAdapter,
    this.l10n,
  });

  /// 执行数据同步
  /// 返回进度流，最后会 emit 一个 isCompleted=true 的进度。
  ///
  /// （service 内部循环检查 `cancelToken.isCancelled`）。不传则新建一个内部
  /// token（取消只能靠调用方停止消费流，service 不知情——旧行为）。
  Stream<DataSyncProgress> sync(DataSyncConfig config, {CancellationToken? cancelToken}) async* {
    final stopwatch = Stopwatch()..start();
    final cancelled = cancelToken ?? CancellationToken();

    // 1. 探测主键
    yield DataSyncProgress(
      phase:
          l10n?.dataSyncProgressDetectingSchema ?? 'Detecting table schema...',
    );
    await sourceAdapter.useDatabase(config.sourceDatabase);
    final primaryKey = await _detectPrimaryKey(config.sourceTable);

    // 2. 探测总行数
    yield DataSyncProgress(
      phase: l10n?.dataSyncProgressCountingRows ?? 'Counting total rows...',
    );
    await Future.delayed(const Duration(milliseconds: 100));
    await sourceAdapter.useDatabase(config.sourceDatabase);
    final totalRows = await _getTotalRows(
      config.sourceTable,
      config.sourceDatabase,
    );

    // 3. 生成分段
    yield DataSyncProgress(
      phase:
          l10n?.dataSyncProgressCalculatingSegments ??
          'Calculating segments...',
      totalRows: totalRows,
    );
    await sourceAdapter.useDatabase(config.sourceDatabase);
    final calculator = SegmentCalculatorFactory.create(config.segmentConfig);
    final segments = await calculator.calculateSegments(
      adapter: sourceAdapter,
      tableName: config.sourceTable,
      config: config.segmentConfig,
      l10n: l10n,
    );

    if (segments.isEmpty) {
      stopwatch.stop();
      yield DataSyncProgress(
        phase:
            l10n?.dataSyncProgressEmptyTable ??
            'Source table is empty, sync completed',
        isCompleted: true,
        totalRows: totalRows,
        syncedRows: 0,
      );
      return;
    }

    // 4. 创建批量插入器
    final inserter = BatchInserter(
      targetAdapter: targetAdapter,
      targetTable: config.targetTable,
      strategy: config.targetStrategy,
      primaryKey: primaryKey,
    );

    // 5. truncate 策略：先清空目标表
    if (config.targetStrategy == TargetStrategy.truncate) {
      yield DataSyncProgress(
        phase:
            l10n?.dataSyncProgressTruncatingTarget ??
            'Truncating target table...',
        totalRows: totalRows,
      );
      await targetAdapter.useDatabase(config.targetDatabase);
      try {
        await targetAdapter.executeQuery(
          'TRUNCATE TABLE `${config.targetTable}`',
        );
      } catch (e) {
        // TRUNCATE 可能因外键约束失败，回退到 DELETE
        await targetAdapter.executeQuery(
          'SET FOREIGN_KEY_CHECKS = 0; DELETE FROM `${config.targetTable}`; SET FOREIGN_KEY_CHECKS = 1;',
        );
      }
    }

    // 6. 逐段处理
    int totalSynced = 0;
    int totalFailed = 0;
    int totalSkipped = 0;

    for (int segIndex = 0; segIndex < segments.length; segIndex++) {
      if (cancelled.isCancelled) {
        yield DataSyncProgress(
          phase: l10n?.dataSyncProgressCancelled ?? 'Sync cancelled',
          isCancelled: true,
          currentSegmentIndex: segIndex,
          totalSegments: segments.length,
          totalRows: totalRows,
          syncedRows: totalSynced,
          failedRows: totalFailed,
        );
        return;
      }

      final segment = segments[segIndex];

      yield DataSyncProgress(
        phase:
            l10n?.dataSyncProgressSyncingSegment(
              segIndex + 1,
              segments.length,
            ) ??
            'Syncing segment ${segIndex + 1}/${segments.length}...',
        currentSegmentIndex: segIndex,
        totalSegments: segments.length,
        totalRows: totalRows,
        syncedRows: totalSynced,
        failedRows: totalFailed,
      );

      // 创建游标分页器（确保在源库上下文）
      await sourceAdapter.useDatabase(config.sourceDatabase);
      final paginator = CursorPaginator(
        adapter: sourceAdapter,
        tableName: config.sourceTable,
        segmentField: config.segmentConfig.fieldName,
        primaryKey: primaryKey,
        pageSize: config.pageSize,
        segment: segment,
      );

      int segmentPage = 0;

      // 逐页处理
      while (paginator.hasNext) {
        if (cancelled.isCancelled) break;

        // 查询一页数据（切回源库）
        await sourceAdapter.useDatabase(config.sourceDatabase);
        final rows = await paginator.nextPage();
        if (rows.isEmpty) break;

        // 批量插入（切到目标库）
        await targetAdapter.useDatabase(config.targetDatabase);
        final isFirstBatch = segIndex == 0 && segmentPage == 0;
        final result = await inserter.insertBatch(
          rows,
          isFirstBatch: isFirstBatch,
        );

        totalSynced += result['synced']!;
        totalFailed += result['failed']!;
        totalSkipped += result['skipped']!;

        segmentPage++;

        yield DataSyncProgress(
          phase:
              l10n?.dataSyncProgressPageStatus(
                segIndex + 1,
                segments.length,
                totalSynced,
                totalRows,
              ) ??
              'Segment ${segIndex + 1}/${segments.length}, synced $totalSynced / $totalRows rows',
          currentSegmentIndex: segIndex,
          totalSegments: segments.length,
          currentPageInSegment: segmentPage,
          totalRows: totalRows,
          syncedRows: totalSynced,
          failedRows: totalFailed,
        );

        // 页间 sleep（保护源库）
        if (config.pageIntervalMs > 0) {
          await Future.delayed(Duration(milliseconds: config.pageIntervalMs));
        }
      }

      // 段间 sleep（保护源库）
      if (config.segmentIntervalMs > 0 && segIndex < segments.length - 1) {
        await Future.delayed(Duration(milliseconds: config.segmentIntervalMs));
      }
    }

    stopwatch.stop();

    yield DataSyncProgress(
      phase:
          l10n?.dataSyncProgressCompleted(
            totalSynced,
            totalFailed,
            totalSkipped,
          ) ??
          'Sync completed! Success: $totalSynced rows, Failed: $totalFailed rows, Skipped: $totalSkipped rows',
      isCompleted: true,
      totalSegments: segments.length,
      currentSegmentIndex: segments.length,
      totalRows: totalRows,
      syncedRows: totalSynced,
      failedRows: totalFailed,
    );
  }

  /// 探测表的主键字段
  Future<String?> _detectPrimaryKey(String tableName) async {
    try {
      // 先尝试 getTableColumns
      final columns = await sourceAdapter.getTableColumns(tableName);
      if (columns.isNotEmpty) {
        final pkColumn = columns.where((c) => c.isPrimaryKey).firstOrNull;
        if (pkColumn != null) return pkColumn.name;
      }
      // Fallback：直接查询 INFORMATION_SCHEMA
      final pkResult = await sourceAdapter.executeQuery(
        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '$tableName' "
        "AND CONSTRAINT_NAME = 'PRIMARY' LIMIT 1",
      );
      if (pkResult.rows.isNotEmpty) {
        return pkResult.rows.first['COLUMN_NAME']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 获取表总行数
  Future<int> _getTotalRows(String tableName, String databaseName) async {
    try {
      final sql = 'SELECT COUNT(*) as cnt FROM `$databaseName`.`$tableName`';
      final result = await sourceAdapter.executeQuery(sql);
      if (result.rows.isNotEmpty) {
        final count = result.rows.first['cnt'];
        if (count is int) return count;
        if (count is num) return count.toInt();
        return int.tryParse(count.toString()) ?? 0;
      }
    } catch (_) {
      // 忽略查询错误，返回 0
    }
    return 0;
  }
}

/// 取消令牌（P0-3：公开，供 DataSyncDialog 持有并触发真正中断）。
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}
