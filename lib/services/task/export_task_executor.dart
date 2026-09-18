import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/task_models.dart';
import '../database_abstract.dart';
import 'task_executor.dart';

/// 导出任务执行器
class ExportTaskExecutor implements TaskExecutor {
  final ExportTaskConfig config;
  final DatabaseAdapter adapter;

  ExportTaskExecutor({required this.config, required this.adapter});

  @override
  Future<void> execute({
    required Function(TaskProgressUpdate) onProgress,
    required Function(TaskLog) onLog,
    required Function() isCancelled,
  }) async {
    onLog(TaskLog.info('开始导出表: ${config.tableName}'));
    onLog(TaskLog.info('输出路径: ${config.outputPath}'));
    onLog(TaskLog.info('格式: ${config.format.name.toUpperCase()}'));

    // 1. 获取表总行数（用于进度计算）
    onLog(TaskLog.info('正在统计行数...'));
    final totalRows = await _getTotalRows();
    onLog(TaskLog.info('共 $totalRows 行数据待导出'));

    if (isCancelled()) return;

    if (totalRows == 0) {
      throw Exception('表中没有数据可导出');
    }

    // 2. 分批查询并导出
    onProgress(
      TaskProgressUpdate(
        progress: 0,
        phase: '正在查询数据...',
        processedRows: 0,
        totalRows: totalRows,
      ),
    );

    final batchSize = 5000; // 每批查询行数
    int offset = 0;
    int processedRows = 0;
    bool isFirstBatch = true;

    // 打开文件（覆盖模式）
    final file = File(config.outputPath);
    final sink = file.openWrite();

    try {
      // 写入文件头
      await _writeFileHeader(sink);

      while (offset < totalRows) {
        if (isCancelled()) {
          sink.close();
          throw Exception('导出已取消');
        }

        // 查询一批数据
        final batch = await _queryBatch(offset, batchSize);
        if (batch.isEmpty) break;

        // 写入数据
        await _writeBatch(sink, batch, isFirstBatch);
        isFirstBatch = false;

        processedRows += batch.length;
        offset += batch.length;

        final progress = (processedRows / totalRows * 100).toInt();
        onProgress(
          TaskProgressUpdate(
            progress: progress.clamp(0, 100),
            phase: '已导出 $processedRows / $totalRows 行',
            processedRows: processedRows,
            totalRows: totalRows,
          ),
        );

        onLog(TaskLog.info('已导出 $processedRows / $totalRows 行'));

        // 给 UI 刷新机会
        await Future.delayed(Duration.zero);
      }

      // 写入文件尾
      await _writeFileFooter(sink);

      await sink.close();

      onLog(
        TaskLog.success('导出完成! 共 $processedRows 行数据已写入 ${config.outputPath}'),
      );
      onProgress(
        TaskProgressUpdate(
          progress: 100,
          phase: '导出完成',
          processedRows: processedRows,
          totalRows: totalRows,
        ),
      );
    } catch (e) {
      await sink.close();
      // 删除不完整的文件
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  /// 获取总行数
  Future<int> _getTotalRows() async {
    final whereClause = config.whereClause;
    final countSql = whereClause != null && whereClause.isNotEmpty
        ? 'SELECT COUNT(*) as count FROM `${config.tableName}` WHERE $whereClause'
        : 'SELECT COUNT(*) as count FROM `${config.tableName}`';

    final result = await adapter.executeQuery(countSql);
    if (result.rows.isNotEmpty && result.rows.first.containsKey('count')) {
      final countValue = result.rows.first['count'];
      if (countValue is int) return countValue;
      if (countValue is num) return countValue.toInt();
      return int.tryParse(countValue.toString()) ?? 0;
    }
    return 0;
  }

  /// 查询一批数据
  Future<List<Map<String, dynamic>>> _queryBatch(int offset, int limit) async {
    var sql = 'SELECT * FROM `${config.tableName}`';

    if (config.whereClause != null && config.whereClause!.isNotEmpty) {
      sql += ' WHERE ${config.whereClause}';
    }

    if (config.orderBy != null && config.orderBy!.isNotEmpty) {
      sql += ' ORDER BY ${config.orderBy}';
    }

    sql += ' LIMIT $limit OFFSET $offset';

    final result = await adapter.executeQuery(sql);
    return result.rows;
  }

  /// 写入文件头
  Future<void> _writeFileHeader(IOSink sink) async {
    switch (config.format) {
      case ExportFormat.csv:
        // CSV BOM for Excel compatibility
        if (config.encoding.toLowerCase() == 'utf-8') {
          sink.write('\ufeff');
        }
        break;
      case ExportFormat.json:
        sink.writeln('[');
        break;
      case ExportFormat.sql:
        sink.writeln('-- Export from table: ${config.tableName}');
        sink.writeln('-- Generated at: ${DateTime.now().toIso8601String()}');
        sink.writeln();
        break;
      case ExportFormat.excel:
        // Excel 实际上用 CSV 格式
        if (config.encoding.toLowerCase() == 'utf-8') {
          sink.write('\ufeff');
        }
        break;
    }
  }

  /// 写入一批数据
  Future<void> _writeBatch(
    IOSink sink,
    List<Map<String, dynamic>> batch,
    bool isFirstBatch,
  ) async {
    switch (config.format) {
      case ExportFormat.csv:
        await _writeCsvBatch(sink, batch, isFirstBatch);
        break;
      case ExportFormat.json:
        await _writeJsonBatch(sink, batch, isFirstBatch);
        break;
      case ExportFormat.sql:
        await _writeSqlBatch(sink, batch);
        break;
      case ExportFormat.excel:
        await _writeCsvBatch(sink, batch, isFirstBatch);
        break;
    }
  }

  /// 写入 CSV 批次
  Future<void> _writeCsvBatch(
    IOSink sink,
    List<Map<String, dynamic>> batch,
    bool isFirstBatch,
  ) async {
    if (batch.isEmpty) return;

    final headers = batch.first.keys.toList();

    // 写入表头（仅第一批）
    if (isFirstBatch && config.includeHeader) {
      final headerLine = headers.map((h) => _escapeCsv(h)).join(',');
      sink.writeln(headerLine);
    }

    // 写入数据行
    for (final row in batch) {
      final values = headers.map((header) {
        final value = row[header];
        if (value == null) return '';
        return _escapeCsv(value.toString());
      }).toList();
      sink.writeln(values.join(','));
    }
  }

  /// 写入 JSON 批次
  Future<void> _writeJsonBatch(
    IOSink sink,
    List<Map<String, dynamic>> batch,
    bool isFirstBatch,
  ) async {
    for (int i = 0; i < batch.length; i++) {
      if (!isFirstBatch || i > 0) {
        sink.writeln(',');
      }
      sink.write(const JsonEncoder.withIndent('  ').convert(batch[i]));
    }
  }

  /// 写入 SQL 批次
  Future<void> _writeSqlBatch(
    IOSink sink,
    List<Map<String, dynamic>> batch,
  ) async {
    if (batch.isEmpty) return;

    final fields = batch.first.keys.toList();
    final fieldList = fields.map((f) => '`$f`').join(', ');

    for (final row in batch) {
      final values = fields
          .map((field) => _formatSqlValue(row[field]))
          .join(', ');
      sink.writeln(
        'INSERT INTO `${config.tableName}` ($fieldList) VALUES ($values);',
      );
    }
  }

  /// 写入文件尾
  Future<void> _writeFileFooter(IOSink sink) async {
    switch (config.format) {
      case ExportFormat.json:
        sink.writeln();
        sink.writeln(']');
        break;
      case ExportFormat.csv:
      case ExportFormat.sql:
      case ExportFormat.excel:
        // 无需尾部
        break;
    }
  }

  /// 转义 CSV 值
  String _escapeCsv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }
    return value;
  }

  /// 格式化 SQL 值
  String _formatSqlValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is String) {
      final escaped = value.replaceAll("'", "''");
      return "'$escaped'";
    }
    if (value is bool) return value ? '1' : '0';
    return value.toString();
  }
}
