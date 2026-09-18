import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';

import 'package:dbmaster/models/import_models.dart';
import 'package:dbmaster/pro/data_import/file_analyzer.dart';

/// 文件读取回调
typedef OnBatchRead = void Function(List<Map<String, dynamic>> batch);

/// 流式文件读取器
/// 支持大文件分块读取，避免内存溢出
class StreamingFileReader {
  final String filePath;
  final ImportFormat format;
  final String encoding;
  final String? delimiter;
  final List<String> fields;
  final bool hasHeader;
  final int batchSize;

  StreamingFileReader({
    required this.filePath,
    required this.format,
    required this.encoding,
    this.delimiter,
    required this.fields,
    required this.hasHeader,
    this.batchSize = 1000,
  });

  /// 流式读取文件并分批处理
  ///
  /// [onBatch] 每读取一批数据时回调
  /// [onProgress] 进度回调（已读取字节数，总字节数）
  ///
  /// 返回 [StreamReaderResult]
  Future<StreamReaderResult> readBatches({
    required OnBatchRead onBatch,
    void Function(int readBytes, int totalBytes)? onProgress,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return StreamReaderResult.error('文件不存在: $filePath');
      }

      final totalBytes = await file.length();
      int readBytes = 0;
      int totalRows = 0;
      int failedRows = 0;

      if (format == ImportFormat.csv) {
        final result = await _readCSVBatch(file, totalBytes, onBatch, (r, t) {
          readBytes = r;
          onProgress?.call(r, t);
        });
        totalRows = result.totalRows;
        failedRows = result.failedRows;
      } else if (format == ImportFormat.json) {
        final result = await _readJSONBatch(file, totalBytes, onBatch, (r, t) {
          readBytes = r;
          onProgress?.call(r, t);
        });
        totalRows = result.totalRows;
        failedRows = result.failedRows;
      } else if (format == ImportFormat.excel) {
        final result = await _readExcelBatch(file, totalBytes, onBatch, (r, t) {
          readBytes = r;
          onProgress?.call(r, t);
        });
        totalRows = result.totalRows;
        failedRows = result.failedRows;
      }

      return StreamReaderResult.success(
        totalRows: totalRows,
        failedRows: failedRows,
        readBytes: readBytes,
        totalBytes: totalBytes,
      );
    } catch (e) {
      return StreamReaderResult.error('读取文件失败: $e');
    }
  }

  /// 读取 CSV 文件批次
  Future<_InternalReadResult> _readCSVBatch(
    File file,
    int totalBytes,
    OnBatchRead onBatch,
    void Function(int readBytes, int totalBytes) onProgress,
  ) async {
    final stream = file.openRead();
    final batch = <Map<String, dynamic>>[];
    int totalRows = 0;
    int failedRows = 0;
    int readBytes = 0;
    bool isFirstLine = true;
    String buffer = '';

    await for (final chunk in stream) {
      readBytes += chunk.length;
      final decoded = _decodeChunk(chunk, encoding);
      buffer += decoded;

      // 按行分割
      int lineEnd;
      while ((lineEnd = buffer.indexOf('\n')) != -1) {
        String line = buffer.substring(0, lineEnd);
        buffer = buffer.substring(lineEnd + 1);

        // 移除 \r
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }

        if (line.isEmpty) continue;

        // 跳过表头
        if (isFirstLine && hasHeader) {
          isFirstLine = false;
          continue;
        }
        isFirstLine = false;

        try {
          final values = FileAnalyzer.splitCSVLine(line, delimiter ?? ',');
          final rowData = <String, dynamic>{};
          for (int j = 0; j < values.length && j < fields.length; j++) {
            rowData[fields[j]] = values[j].trim();
          }
          batch.add(rowData);

          if (batch.length >= batchSize) {
            onBatch(List.from(batch));
            totalRows += batch.length;
            batch.clear();
          }
        } catch (e) {
          failedRows++;
        }
      }

      onProgress(readBytes, totalBytes);
    }

    // 处理剩余缓冲区
    if (buffer.isNotEmpty) {
      String line = buffer;
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isNotEmpty) {
        try {
          final values = FileAnalyzer.splitCSVLine(line, delimiter ?? ',');
          final rowData = <String, dynamic>{};
          for (int j = 0; j < values.length && j < fields.length; j++) {
            rowData[fields[j]] = values[j].trim();
          }
          batch.add(rowData);
        } catch (e) {
          failedRows++;
        }
      }
    }

    // 发送最后一批
    if (batch.isNotEmpty) {
      onBatch(List.from(batch));
      totalRows += batch.length;
    }

    return _InternalReadResult(totalRows: totalRows, failedRows: failedRows);
  }

  /// 读取 JSON 文件批次
  Future<_InternalReadResult> _readJSONBatch(
    File file,
    int totalBytes,
    OnBatchRead onBatch,
    void Function(int readBytes, int totalBytes) onProgress,
  ) async {
    final content = await file.readAsString();
    final readBytes = content.length;
    onProgress(readBytes, totalBytes);

    int totalRows = 0;
    int failedRows = 0;

    try {
      final trimmed = content.trim();
      List<dynamic> jsonArray;

      if (trimmed.startsWith('[')) {
        // JSON 数组
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          jsonArray = decoded;
        } else {
          return _InternalReadResult(totalRows: 0, failedRows: 1);
        }
      } else {
        // JSON Lines
        jsonArray = [];
        final lines = trimmed.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final decoded = jsonDecode(line.trim());
            if (decoded is Map) {
              jsonArray.add(decoded);
            }
          } catch (e) {
            failedRows++;
          }
        }
      }

      // 分批处理
      final batch = <Map<String, dynamic>>[];
      for (final item in jsonArray) {
        if (item is Map) {
          batch.add(item.cast<String, dynamic>());

          if (batch.length >= batchSize) {
            onBatch(List.from(batch));
            totalRows += batch.length;
            batch.clear();
          }
        }
      }

      // 发送最后一批
      if (batch.isNotEmpty) {
        onBatch(List.from(batch));
        totalRows += batch.length;
      }

      return _InternalReadResult(totalRows: totalRows, failedRows: failedRows);
    } catch (e) {
      return _InternalReadResult(
        totalRows: totalRows,
        failedRows: failedRows + 1,
      );
    }
  }

  /// 解码数据块
  static String _decodeChunk(List<int> bytes, String encoding) {
    try {
      switch (encoding.toLowerCase()) {
        case 'utf-8':
          return utf8.decode(bytes, allowMalformed: true);
        case 'gbk':
        case 'gb2312':
        case 'gb18030':
          return latin1.decode(bytes);
        default:
          return utf8.decode(bytes, allowMalformed: true);
      }
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

/// 流式读取结果
class StreamReaderResult {
  final bool success;
  final int totalRows;
  final int failedRows;
  final int readBytes;
  final int totalBytes;
  final String? errorMessage;

  StreamReaderResult({
    required this.success,
    this.totalRows = 0,
    this.failedRows = 0,
    this.readBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  factory StreamReaderResult.success({
    required int totalRows,
    required int failedRows,
    required int readBytes,
    required int totalBytes,
  }) {
    return StreamReaderResult(
      success: true,
      totalRows: totalRows,
      failedRows: failedRows,
      readBytes: readBytes,
      totalBytes: totalBytes,
    );
  }

  factory StreamReaderResult.error(String message) {
    return StreamReaderResult(success: false, errorMessage: message);
  }
}

class _InternalReadResult {
  final int totalRows;
  final int failedRows;

  _InternalReadResult({required this.totalRows, required this.failedRows});
}

/// Excel 读取扩展
extension ExcelReader on StreamingFileReader {
  Future<_InternalReadResult> _readExcelBatch(
    File file,
    int totalBytes,
    OnBatchRead onBatch,
    void Function(int readBytes, int totalBytes) onProgress,
  ) async {
    try {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];

      if (sheet == null) {
        return _InternalReadResult(totalRows: 0, failedRows: 0);
      }

      int totalRows = 0;
      int failedRows = 0;
      int currentRow = 1; // 跳过表头

      while (currentRow < sheet.maxRows) {
        final batch = <Map<String, dynamic>>[];

        for (
          int i = 0;
          i < batchSize && currentRow < sheet.maxRows;
          i++, currentRow++
        ) {
          final row = sheet.row(currentRow);
          if (row.every((cell) => cell?.value == null)) continue;

          final rowData = <String, dynamic>{};
          for (int j = 0; j < row.length && j < fields.length; j++) {
            rowData[fields[j]] = row[j]?.value?.toString() ?? '';
          }
          batch.add(rowData);
          totalRows++;
        }

        if (batch.isNotEmpty) {
          onBatch(batch);
        }

        onProgress(
          (currentRow / sheet.maxRows * totalBytes).round(),
          totalBytes,
        );
      }

      return _InternalReadResult(totalRows: totalRows, failedRows: failedRows);
    } catch (e) {
      return _InternalReadResult(totalRows: 0, failedRows: 0);
    }
  }
}
