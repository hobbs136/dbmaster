import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'package:dbmaster/models/import_models.dart';
import 'package:dbmaster/pro/data_import/smart_import_models.dart';

/// 文件分析服务
/// 负责检测文件格式、编码、分隔符，提取字段和样本数据
class FileAnalyzer {
  /// 最大样本字节数（约 100KB）
  static const int _maxSampleBytes = 100 * 1024;

  /// 分析文件
  static Future<FileAnalysisResult> analyzeFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return _errorResult('文件不存在: $filePath');
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        return _errorResult('文件为空');
      }

      // 读取样本数据用于分析
      final sampleBytes = await _readSample(file);
      final encoding = _detectEncoding(sampleBytes);
      final content = _decodeWithEncoding(sampleBytes, encoding);

      // 检测文件格式
      final format = _detectFormat(content, filePath);

      if (format == ImportFormat.csv) {
        return _analyzeCSV(content, filePath, fileSize, encoding);
      } else if (format == ImportFormat.json) {
        return _analyzeJSON(content, filePath, fileSize, encoding);
      } else if (format == ImportFormat.excel) {
        return _analyzeExcel(filePath, fileSize);
      }

      return _errorResult('不支持的文件格式');
    } catch (e) {
      return _errorResult('文件分析失败: $e');
    }
  }

  /// 读取文件样本
  static Future<Uint8List> _readSample(File file) async {
    final fileSize = await file.length();
    final readSize = fileSize < _maxSampleBytes ? fileSize : _maxSampleBytes;
    final stream = file.openRead(0, readSize);
    final bytes = await stream.expand((chunk) => chunk).toList();
    return Uint8List.fromList(bytes);
  }

  /// 检测编码
  static String _detectEncoding(Uint8List bytes) {
    // 检查 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 'utf-8';
    }

    // 检查 UTF-16 LE BOM
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'utf-16';
    }

    // 检查 UTF-16 BE BOM
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'utf-16';
    }

    // 尝试 UTF-8 解码验证
    try {
      final decoded = utf8.decode(bytes, allowMalformed: false);
      // 如果成功解码，再检查是否有乱码特征（某些 GBK 字符在 UTF-8 下也能解码但会乱码）
      if (!_hasGarbagedChars(decoded)) {
        return 'utf-8';
      }
    } catch (_) {
      // 不是有效的 UTF-8
    }

    // 尝试 GBK（简化为检查常见字节范围）
    if (_isLikelyGBK(bytes)) {
      return 'gbk';
    }

    // 默认 UTF-8
    return 'utf-8';
  }

  /// 检查是否有乱码特征（简单的启发式检测）
  static bool _hasGarbagedChars(String text) {
    // 如果出现大量 � 或常见乱码模式，可能是编码错误
    final garbledPattern = RegExp(r'[�]|ï¿½|Â|Ã|Ã©|Ã¨|Ã ');
    final matches = garbledPattern.allMatches(text);
    // 如果乱码字符比例超过 1%，认为是编码错误
    if (text.isEmpty) return false;
    return matches.length / text.length > 0.01;
  }

  /// 简单判断是否为 GBK 编码
  static bool _isLikelyGBK(Uint8List bytes) {
    int gbkCount = 0;
    for (int i = 0; i < bytes.length - 1; i++) {
      final b1 = bytes[i];
      if (b1 >= 0x81 && b1 <= 0xFE) {
        final b2 = bytes[i + 1];
        if ((b2 >= 0x40 && b2 <= 0xFE) || (b2 >= 0x80 && b2 <= 0xFE)) {
          gbkCount++;
          i++; // 跳过下一个字节
        }
      }
    }
    // 如果 GBK 双字节模式比例超过 5%，认为是 GBK
    return gbkCount > bytes.length * 0.05;
  }

  /// 使用指定编码解码
  static String _decodeWithEncoding(Uint8List bytes, String encoding) {
    try {
      switch (encoding.toLowerCase()) {
        case 'utf-8':
          return utf8.decode(bytes, allowMalformed: true);
        case 'gbk':
        case 'gb2312':
        case 'gb18030':
          // Flutter 原生不支持 GBK，使用 Latin1 解码后再处理
          // 实际上这里应该用 gbk_codec 包，但为简化先用 Latin1
          return latin1.decode(bytes);
        case 'utf-16':
          if (bytes.length >= 2) {
            if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
              return utf8.decode(bytes.sublist(2), allowMalformed: true);
            }
          }
          return utf8.decode(bytes, allowMalformed: true);
        default:
          return utf8.decode(bytes, allowMalformed: true);
      }
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 检测文件格式
  static ImportFormat _detectFormat(String content, String filePath) {
    final ext = filePath.toLowerCase().split('.').last;

    // 根据扩展名判断
    if (ext == 'csv' || ext == 'tsv' || ext == 'txt') {
      return ImportFormat.csv;
    } else if (ext == 'json' || ext == 'jsonl') {
      return ImportFormat.json;
    } else if (ext == 'xlsx' || ext == 'xls') {
      return ImportFormat.excel;
    }

    // 根据内容判断
    final trimmed = content.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      return ImportFormat.json;
    }

    // 默认 CSV
    return ImportFormat.csv;
  }

  /// 分析 CSV 文件
  static FileAnalysisResult _analyzeCSV(
    String content,
    String filePath,
    int fileSize,
    String encoding,
  ) {
    final lines = content.split('\n');
    if (lines.isEmpty) {
      return _errorResult('CSV 文件为空');
    }

    // 检测分隔符
    final delimiter = _detectDelimiter(content);

    // 解析表头
    final firstLine = lines.first.trim();
    if (firstLine.isEmpty) {
      return _errorResult('CSV 文件第一行为空');
    }

    final headerFields = splitCSVLine(firstLine, delimiter);
    final hasHeader = _isLikelyHeader(headerFields);

    List<String> fields;
    int dataStartIndex;

    if (hasHeader) {
      fields = headerFields.map((f) => f.trim()).toList();
      dataStartIndex = 1;
    } else {
      fields = List.generate(headerFields.length, (i) => 'column_${i + 1}');
      dataStartIndex = 0;
    }

    // 提取样本数据
    final sampleData = <Map<String, dynamic>>[];
    for (
      int i = dataStartIndex;
      i < lines.length && sampleData.length < 100;
      i++
    ) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final values = splitCSVLine(line, delimiter);
      final rowData = <String, dynamic>{};
      for (int j = 0; j < values.length && j < fields.length; j++) {
        rowData[fields[j]] = values[j].trim();
      }
      sampleData.add(rowData);
    }

    // 推断字段类型
    final inferredTypes = _inferFieldTypes(fields, sampleData);

    // 估计总行数
    final estimatedTotalRows = _estimateTotalRows(
      fileSize,
      content,
      lines.length,
    );

    return FileAnalysisResult(
      format: ImportFormat.csv,
      encoding: encoding,
      delimiter: delimiter,
      hasHeader: hasHeader,
      fields: fields,
      inferredTypes: inferredTypes,
      sampleData: sampleData,
      estimatedTotalRows: estimatedTotalRows,
      fileName: filePath.split(Platform.pathSeparator).last,
      fileSize: fileSize,
      success: true,
    );
  }

  /// 分析 JSON 文件
  static FileAnalysisResult _analyzeJSON(
    String content,
    String filePath,
    int fileSize,
    String encoding,
  ) {
    try {
      final trimmed = content.trim();
      if (trimmed.isEmpty) {
        return _errorResult('JSON 文件为空');
      }

      List<dynamic> jsonArray;

      if (trimmed.startsWith('[')) {
        // JSON 数组
        final decoded = jsonDecode(trimmed);
        if (decoded is! List) {
          return _errorResult('JSON 文件格式不正确，期望数组');
        }
        jsonArray = decoded;
      } else if (trimmed.startsWith('{')) {
        // JSON Lines 或单个对象
        final lines = trimmed
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        jsonArray = [];
        for (final line in lines) {
          try {
            final decoded = jsonDecode(line.trim());
            if (decoded is Map) {
              jsonArray.add(decoded);
            }
          } catch (_) {
            // 忽略解析失败的行
          }
        }
      } else {
        return _errorResult('无法识别的 JSON 格式');
      }

      if (jsonArray.isEmpty) {
        return _errorResult('JSON 文件中没有有效数据');
      }

      // 收集所有字段
      final fieldSet = <String>{};
      for (final item in jsonArray) {
        if (item is Map) {
          fieldSet.addAll(item.keys.cast<String>());
        }
      }
      final fields = fieldSet.toList();

      // 提取样本数据
      final sampleData = <Map<String, dynamic>>[];
      for (int i = 0; i < jsonArray.length && i < 100; i++) {
        final item = jsonArray[i];
        if (item is Map) {
          sampleData.add(item.cast<String, dynamic>());
        }
      }

      // 推断字段类型
      final inferredTypes = _inferFieldTypes(fields, sampleData);

      // 估计总行数
      final estimatedTotalRows = _estimateTotalRows(
        fileSize,
        content,
        jsonArray.length,
      );

      return FileAnalysisResult(
        format: ImportFormat.json,
        encoding: encoding,
        hasHeader: false,
        fields: fields,
        inferredTypes: inferredTypes,
        sampleData: sampleData,
        estimatedTotalRows: estimatedTotalRows,
        fileName: filePath.split(Platform.pathSeparator).last,
        fileSize: fileSize,
        success: true,
      );
    } catch (e) {
      return _errorResult('JSON 分析失败: $e');
    }
  }

  /// 检测分隔符
  static String _detectDelimiter(String content) {
    final firstLine = content.split('\n').first;
    final candidates = [',', '\t', ';', '|'];
    String bestDelimiter = ',';
    int maxCount = 0;

    for (final delimiter in candidates) {
      final count = firstLine.split(delimiter).length - 1;
      if (count > maxCount) {
        maxCount = count;
        bestDelimiter = delimiter;
      }
    }

    return bestDelimiter;
  }

  /// 判断第一行是否为表头
  static bool _isLikelyHeader(List<String> fields) {
    if (fields.isEmpty) return false;

    // 如果所有字段都是纯数字，不太可能是表头
    final allNumeric = fields.every(
      (f) => int.tryParse(f) != null || double.tryParse(f) != null,
    );
    if (allNumeric) return false;

    // 如果包含常见的列名特征，更可能是表头
    final headerPatterns = RegExp(
      r'(id|name|time|date|code|type|status|value|count|price|amount|email|phone|address|desc|remark|create|update|delete)',
      caseSensitive: false,
    );
    final headerLikeCount = fields
        .where((f) => headerPatterns.hasMatch(f))
        .length;

    return headerLikeCount >= 1 || !allNumeric;
  }

  /// 分割 CSV 行（支持引号）
  static List<String> splitCSVLine(String line, String delimiter) {
    final result = <String>[];
    final current = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && char == delimiter) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(char);
      }
    }

    result.add(current.toString().trim());
    return result;
  }

  /// 推断字段类型
  static Map<String, String> _inferFieldTypes(
    List<String> fields,
    List<Map<String, dynamic>> sampleData,
  ) {
    final result = <String, String>{};

    for (final field in fields) {
      String inferredType = 'TEXT';

      for (final row in sampleData) {
        final value = row[field];
        if (value == null || value.toString().isEmpty) continue;

        final strValue = value.toString();

        // 尝试整数
        if (int.tryParse(strValue) != null) {
          inferredType = inferredType == 'DOUBLE' ? 'DOUBLE' : 'BIGINT';
          continue;
        }

        // 尝试浮点数
        if (double.tryParse(strValue) != null) {
          inferredType = 'DOUBLE';
          continue;
        }

        // 尝试布尔值
        final lower = strValue.toLowerCase();
        if (lower == 'true' || lower == 'false') {
          inferredType = 'BOOLEAN';
          continue;
        }

        // 尝试日期时间
        if (_isDateTime(strValue)) {
          inferredType = 'DATETIME';
          continue;
        }

        // 字符串类型，根据长度判断
        if (strValue.length <= 255) {
          inferredType = 'VARCHAR(255)';
        } else if (strValue.length <= 65535) {
          inferredType = 'TEXT';
        } else {
          inferredType = 'LONGTEXT';
        }
        break; // 一旦确定为字符串，不需要继续检查
      }

      result[field] = inferredType;
    }

    return result;
  }

  /// 简单判断是否为日期时间格式
  static bool _isDateTime(String value) {
    final datePatterns = [
      RegExp(r'^\d{4}-\d{2}-\d{2}$'), // 2024-01-01
      RegExp(r'^\d{4}/\d{2}/\d{2}$'), // 2024/01/01
      RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}'), // 2024-01-01 12:00:00
      RegExp(r'^\d{2}/\d{2}/\d{4}$'), // 01/01/2024
    ];

    return datePatterns.any((p) => p.hasMatch(value));
  }

  /// 估计总行数
  static int? _estimateTotalRows(
    int fileSize,
    String sampleContent,
    int sampleLines,
  ) {
    if (sampleLines <= 1 || sampleContent.isEmpty) return null;

    final avgLineSize = sampleContent.length / sampleLines;
    if (avgLineSize <= 0) return null;

    final estimatedLines = (fileSize / avgLineSize).round();
    return estimatedLines;
  }

  /// 创建错误结果
  static FileAnalysisResult _errorResult(
    String message, {
    String fileName = '',
  }) {
    return FileAnalysisResult(
      format: ImportFormat.csv,
      encoding: 'utf-8',
      hasHeader: false,
      fields: [],
      inferredTypes: {},
      sampleData: [],
      fileName: fileName,
      fileSize: 0,
      success: false,
      errorMessage: message,
    );
  }

  /// 分析 Excel 文件
  static FileAnalysisResult _analyzeExcel(String filePath, int fileSize) {
    try {
      final bytes = File(filePath).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      // 使用第一个工作表
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];

      if (sheet == null || sheet.maxRows == 0) {
        return _errorResult('Excel 文件为空或没有数据');
      }

      // 提取表头（第一行）
      final headerRow = sheet.row(0);
      final fields = headerRow.map((cell) {
        return cell?.value?.toString() ?? 'column_${headerRow.indexOf(cell)}';
      }).toList();

      // 提取样本数据（前 100 行）
      final sampleData = <Map<String, dynamic>>[];
      for (int i = 1; i < sheet.maxRows && sampleData.length < 100; i++) {
        final row = sheet.row(i);
        if (row.every((cell) => cell?.value == null)) continue;

        final rowData = <String, dynamic>{};
        for (int j = 0; j < row.length && j < fields.length; j++) {
          rowData[fields[j]] = row[j]?.value?.toString() ?? '';
        }
        sampleData.add(rowData);
      }

      // 推断字段类型
      final inferredTypes = _inferFieldTypes(fields, sampleData);

      // 估计总行数
      final estimatedTotalRows = sheet.maxRows > 0 ? sheet.maxRows - 1 : 0;

      return FileAnalysisResult(
        format: ImportFormat.excel,
        encoding: 'utf-8',
        hasHeader: true,
        fields: fields,
        inferredTypes: inferredTypes,
        sampleData: sampleData,
        estimatedTotalRows: estimatedTotalRows,
        fileName: filePath.split(Platform.pathSeparator).last,
        fileSize: fileSize,
        success: true,
      );
    } catch (e) {
      return _errorResult('Excel 文件解析失败: $e');
    }
  }
}
