import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/app_localizations.dart';
import '../organisms/connection/error_boundary.dart';
import '../services/audit_log_service.dart';
import '../services/pii_masker.dart';

/// R4: 单列 PII 脱敏动作。
enum PiiMaskAction {
  /// 保留原值（用户显式选择）
  keep,
  /// 掩码（PIIMasker.maskValue，按 pattern 类型局部遮挡）
  mask,
  /// 哈希（SHA-256，单向不可逆）
  hash,
  /// 删除此列（整列不导出）
  drop,
}

class ExportService {
  static const String _csvBom = '﻿';

  /// 生成的默认文件名（不含后缀），基于当前时间戳，格式 `query_result_yyyyMMdd_HHmmss`。
  ///
  /// 暴露为 public static 以便单元测试格式。
  static String defaultBaseName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'query_result_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static Future<void> exportToCsv(
    List<Map<String, dynamic>> data,
    BuildContext context,
  ) async {
    if (data.isEmpty) {
      _showError(context, '没有数据可导出');
      return;
    }

    final headers = data[0].keys.toList();
    final csvContent = StringBuffer();

    csvContent.writeln(
      headers.map((h) => '"${h.replaceAll('"', '""')}"').join(','),
    );

    for (final row in data) {
      final values = headers.map((header) {
        final value = row[header];
        if (value == null) return '';
        final str = value.toString();
        return '"${str.replaceAll('"', '""')}"';
      }).toList();
      csvContent.writeln(values.join(','));
    }

    await _saveFile(
      _csvBom + csvContent.toString(),
      defaultBaseName(),
      'csv',
      'text/csv',
      context,
    );
  }

  static Future<void> exportToJson(
    List<Map<String, dynamic>> data,
    BuildContext context,
  ) async {
    if (data.isEmpty) {
      _showError(context, '没有数据可导出');
      return;
    }

    try {
      final jsonContent = jsonEncode(
        data,
        toEncodable: (dynamic obj) => obj.toString(),
      );
      await _saveFile(
        jsonContent,
        defaultBaseName(),
        'json',
        'application/json',
        context,
      );
    } catch (e) {
      AppErrorHandler.showErrorSnackBar(context, '导出JSON失败: $e');
    }
  }

  /// D3-A（#32）：真 .xlsx 导出。此前按钮产出 CSV 内容 + `.csv` 后缀（假
  /// xlsx）；现在用 excel 包生成带类型的单元格——int/double/bool 走数值/布尔
  /// 单元格，其余（含 DateTime/Decimal/嵌套）走文本，null 为空单元格。
  ///
  /// 修复（D3-A hotfix）：excel 包按单元格构建簿记 + ZIP 编码是 CPU 密集
  /// 操作，大结果集在 UI isolate 执行会冻结整个窗口（灰屏、消息循环停摆、
  /// 无法关闭）。生成移入后台 isolate（行数据先转纯值保证可跨 isolate
  /// 传输），期间弹阻塞进度框防重复触发。
  static Future<void> exportToExcel(
    List<Map<String, dynamic>> data,
    BuildContext context,
  ) async {
    if (data.isEmpty) {
      _showError(context, '没有数据可导出');
      return;
    }

    final headers = data[0].keys.toList();
    final rows = sanitizeRowsForIsolate(headers, data);

    final l10n = AppLocalizations.of(context)!;
    final generatingText = l10n.exportExcelGenerating;
    final navigator = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(generatingText),
                ],
              ),
            ),
          ),
        ),
      ),
    ));

    final List<int> bytes;
    try {
      bytes = await Isolate.run(() => buildXlsxBytes(rows));
    } catch (e) {
      navigator.pop();
      if (context.mounted) _showError(context, '导出Excel失败: $e');
      return;
    }
    navigator.pop();
    if (!context.mounted) return;

    await _saveFileBytes(
      bytes,
      defaultBaseName(),
      'xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      context,
    );
  }

  /// 行数据 → 可跨 isolate 传输的纯值表（首行表头）。int/double/bool/String
  /// 原样保留（类型保真），null 保留，其余一切类型（DateTime/Decimal/驱动
  /// 包装）toString——与 excelCellForValue 的文本兜底语义一致。
  @visibleForTesting
  static List<List<Object?>> sanitizeRowsForIsolate(
    List<String> headers,
    List<Map<String, dynamic>> data,
  ) {
    Object? sanitize(Object? v) => switch (v) {
          null || int() || double() || bool() || String() => v,
          _ => v.toString(),
        };
    return [
      headers.toList(),
      for (final row in data) headers.map((h) => sanitize(row[h])).toList(),
    ];
  }

  /// 纯值表 → xlsx 字节（在后台 isolate 执行，见 exportToExcel）。
  @visibleForTesting
  static List<int> buildXlsxBytes(List<List<Object?>> rows) {
    final workbook = xlsx.Excel.createExcel();
    // excel 4.x 的 [] 操作符保证返回 Sheet（不存在时创建），无需判空。
    final sheet = workbook[workbook.getDefaultSheet() ?? 'Sheet1'];
    for (final row in rows) {
      sheet.appendRow(row.map((v) => excelCellForValue(v)).toList());
    }
    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('xlsx encode failed');
    }
    return bytes;
  }

  /// 值 → xlsx 单元格的类型映射（导出保真：数字/布尔不失真，其余走文本）。
  @visibleForTesting
  static xlsx.CellValue? excelCellForValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return xlsx.IntCellValue(value);
    if (value is double) return xlsx.DoubleCellValue(value);
    if (value is bool) return xlsx.BoolCellValue(value);
    return xlsx.TextCellValue(value.toString());
  }

  /// R4: 带脱敏的导出（PII 保护 + 审计）。
  ///
  /// 按 [columnActions] 处理每列后再委托现有导出方法，最后记录审计日志。
  /// - drop → 该列从结果中移除
  /// - mask → PIIMasker.maskValue 局部遮挡
  /// - hash → SHA-256 单向哈希
  /// - keep → 原值（用户显式选择）
  ///
  /// [format] 'csv'/'json'/'excel'，[sourceSql] 审计用源查询。
  static Future<void> exportWithMasking({
    required List<Map<String, dynamic>> data,
    required BuildContext context,
    required String format,
    required Map<String, PiiMaskAction> columnActions,
    String? sourceSql,
  }) async {
    if (data.isEmpty) {
      _showError(context, '没有数据可导出');
      return;
    }

    final masked = _applyMasking(data, columnActions);

    // 委托现有导出方法（它们内部处理 _saveFile）
    switch (format) {
      case 'json':
        await exportToJson(masked, context);
        break;
      case 'excel':
        await exportToExcel(masked, context);
        break;
      case 'csv':
      default:
        await exportToCsv(masked, context);
        break;
    }

    // 审计日志（NF5: 只记处理方式 + 列名，不记值）
    await AuditLogService().logExportEvent(
      sourceSql: sourceSql,
      format: format,
      rowCount: masked.length,
      columnActions: columnActions.map((k, v) => MapEntry(k, v.name)),
    );
  }

  /// 对数据按列应用脱敏动作，返回处理后的副本（不改原数据）。
  /// drop 列直接从每行移除；mask/hash 改值；keep 不动。
  @visibleForTesting
  static List<Map<String, dynamic>> applyMaskingForTest(
    List<Map<String, dynamic>> data,
    Map<String, PiiMaskAction> columnActions,
  ) => _applyMasking(data, columnActions);

  static List<Map<String, dynamic>> _applyMasking(
    List<Map<String, dynamic>> data,
    Map<String, PiiMaskAction> columnActions,
  ) {
    final piiMasker = PIIMasker();
    final dropCols = columnActions.entries
        .where((e) => e.value == PiiMaskAction.drop)
        .map((e) => e.key)
        .toSet();
    final maskCols = columnActions.entries
        .where((e) => e.value == PiiMaskAction.mask)
        .map((e) => e.key)
        .toSet();
    final hashCols = columnActions.entries
        .where((e) => e.value == PiiMaskAction.hash)
        .map((e) => e.key)
        .toSet();

    return data.map((row) {
      final newRow = <String, dynamic>{};
      for (final entry in row.entries) {
        final col = entry.key;
        final value = entry.value;
        if (dropCols.contains(col)) continue; // drop → 跳过
        if (maskCols.contains(col) && value != null) {
          newRow[col] = piiMasker.maskValue(value, columnName: col);
        } else if (hashCols.contains(col) && value != null) {
          newRow[col] = sha256.convert(utf8.encode(value.toString())).toString();
        } else {
          newRow[col] = value; // keep 或无动作
        }
      }
      return newRow;
    }).toList();
  }

  /// 若 [path] 不以 `.<extension>` 结尾则补全，确保导出文件始终带正确后缀。
  /// 大小写不敏感比较（`FOO.CSV` 视为已有 .csv）。
  /// 独立为纯函数以便单元测试（避免依赖 FilePicker / 文件系统）。
  static String ensureExtension(String path, String extension) {
    final extWithDot = '.$extension';
    if (path.toLowerCase().endsWith(extWithDot)) return path;
    return '$path$extWithDot';
  }

  /// [baseName] 不含后缀的文件名主体；[extension] 不含点（如 'csv'/'json'）。
  /// 落盘前强制补全后缀，避免用户在保存对话框改名后丢失后缀。
  static Future<void> _saveFile(
    String content,
    String baseName,
    String extension,
    String mimeType,
    BuildContext context,
  ) async {
    await _saveFileBytes(
      utf8.encode(content),
      baseName,
      extension,
      mimeType,
      context,
    );
  }

  /// 二进制版 [_saveFile]（xlsx 等）。文本版委托到这里，统一保存对话框 +
  /// 后缀补全 + 成功/失败反馈路径。
  static Future<void> _saveFileBytes(
    List<int> bytes,
    String baseName,
    String extension,
    String mimeType,
    BuildContext context,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final fileName = '$baseName.$extension';
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出文件',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );

      if (result != null && result.isNotEmpty) {
        final path = ensureExtension(result, extension);
        final file = File(path);
        await file.writeAsBytes(bytes);
        // 裸色 SnackBar → helper（F-15）
        AppErrorHandler.showSuccessSnackBar(
          context,
          l10n.svcExportSuccess(path),
        );
      }
    } catch (e) {
      AppErrorHandler.showErrorSnackBar(context, l10n.svcExportFailed(e.toString()));
    }
  }

  static void _showError(BuildContext context, String message) {
    AppErrorHandler.showErrorSnackBar(context, message);
  }
}
