import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/app_localizations.dart';
import '../connection/error_boundary.dart';

/// 图表 PNG 导出工具（R2: 导出 PNG）。
///
/// 用 RepaintBoundary 包裹图表，调用 toImage 转 PNG，通过 FilePicker
/// 让用户选保存路径。pixelRatio=3.0 保证高清。
class ChartExporter {
  /// 将 [boundary] 渲染的 widget 导出为 PNG。
  ///
  /// 典型用法：用 GlobalKey 拿到 RepaintBoundary 的 RenderObject，
  /// 传给本方法。
  static Future<void> exportToPng({
    required GlobalKey boundaryKey,
    required BuildContext context,
    String baseName = 'chart',
  }) async {
    final l10n = AppLocalizations.of(context);
    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n?.chartExportFailed('no boundary') ?? 'Export failed',
      );
      return;
    }

    try {
      // pixelRatio=3.0 高清截图
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!context.mounted) return;
      if (byteData == null) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n?.chartExportFailed('encode') ?? 'Export failed',
        );
        return;
      }
      final bytes = byteData.buffer.asUint8List();

      // 用户选保存路径
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出图表',
        fileName: '$baseName.png',
        type: FileType.image,
      );
      if (!context.mounted) return;

      if (result != null && result.isNotEmpty) {
        final path = result.endsWith('.png') ? result : '$result.png';
        final file = File(path);
        await file.writeAsBytes(bytes);
        if (!context.mounted) return;
        AppErrorHandler.showSuccessSnackBar(
          context,
          l10n?.chartExportSuccess(path) ?? 'Saved: $path',
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n?.chartExportFailed(e.toString()) ?? 'Export failed: $e',
      );
    }
  }
}

/// 便捷 mixin：在 State 里持有 RepaintBoundary 的 GlobalKey。
/// 用法：
/// ```
/// class _MyChartState extends State<MyChart> with ChartExportBoundary {
///   Widget build(...) => RepaintBoundary(
///     key: boundaryKey,
///     child: chart,
///   );
/// }
/// ```
/// 导出时调 `ChartExporter.exportToPng(boundaryKey: boundaryKey, ...)`。
mixin ChartExportBoundary<T extends StatefulWidget> on State<T> {
  final GlobalKey boundaryKey = GlobalKey();
}

/// 占位：Uint8List 便捷转换（未来若需内存预览 PNG 可用）。
Uint8List pngBytesFromByteData(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
