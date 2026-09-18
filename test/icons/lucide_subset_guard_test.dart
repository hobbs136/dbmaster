// lucide_subset_guard_test.dart — Lucide 子集字体守卫（#31 T15）
//
// 拦截两类回归：
//   1. 新增 `LucideIcons.xxx` 引用但未重跑 tool/subset_lucide_font.dart
//      （图标会渲染为空框）；
//   2. 子集字体与 manifest 清单漂移（字体/清单之一被单独改动）。
//
// 验证方式：直接解析 third_party/lucide_icons_flutter/assets/lucide.ttf 的
// cmap 表（格式 4/12 最小解析器，无第三方依赖），对每个引用码点断言字形
// 存在——测试不过时运行：dart run tool/subset_lucide_font.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'lucide_subset_manifest.g.dart';

void main() {
  test('app 引用的 Lucide 图标均存在于子集字体（缺失时重跑子集脚本）', () {
    final usedNames = <String>{}
      ..addAll(_scanIconReferences(Directory('lib')))
      // integration_test 以真实构建产物运行（字体是真的），必须覆盖；
      // test/ 下 flutter_test 不加载真实图标字体，生成脚本已含、此处不查。
      ..addAll(_scanIconReferences(Directory('integration_test')));
    expect(usedNames, isNotEmpty, reason: '扫描结果为空异常——检查扫描逻辑');

    final missingFromManifest =
        usedNames.difference(kLucideSubsetCodepoints.keys.toSet()).toList()..sort();
    expect(
      missingFromManifest,
      isEmpty,
      reason: '以下图标不在子集清单中，运行 dart run tool/subset_lucide_font.dart '
          '再生成字体与清单后提交：$missingFromManifest',
    );

    // 字体级校验：manifest 码点必须真的在 lucide.ttf 的 cmap 里。
    final fontBytes =
        File('third_party/lucide_icons_flutter/assets/lucide.ttf').readAsBytesSync();
    final mappedCodepoints = _parseCmapCodepoints(fontBytes);
    final missingGlyphs = <String>[];
    for (final name in usedNames) {
      final cp = kLucideSubsetCodepoints[name]!;
      if (!mappedCodepoints.contains(cp)) missingGlyphs.add(name);
    }
    expect(
      missingGlyphs,
      isEmpty,
      reason: '以下码点在 lucide.ttf 的 cmap 中无字形（字体与清单漂移，'
          '重跑 dart run tool/subset_lucide_font.dart）：$missingGlyphs',
    );
  });
}

Set<String> _scanIconReferences(Directory dir) {
  if (!dir.existsSync()) return <String>{};
  final names = <String>{};
  final pattern = RegExp(r'\bLucideIcons\.([a-zA-Z0-9_]+)');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final match in pattern.allMatches(entity.readAsStringSync())) {
      names.add(match.group(1)!);
    }
  }
  return names;
}

/// 最小 sfnt cmap 解析：返回字体中有字形映射的全部码点。
///
/// 只实现格式 4（segment mapping，BMP）与格式 12（segmented coverage），
/// 图标字体子集只会有这两种。解析失败直接抛异常让测试红掉（字体损坏
/// 本身就是需要拦截的回归）。
Set<int> _parseCmapCodepoints(Uint8List b) {
  final bd = ByteData.sublistView(b);
  final numTables = bd.getUint16(4); // sfnt 表数（偏移 4）
  var cmapOffset = -1;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(b.sublist(rec, rec + 4));
    if (tag == 'cmap') {
      cmapOffset = bd.getUint32(rec + 8);
      break;
    }
  }
  if (cmapOffset < 0) throw const FormatException('lucide.ttf 无 cmap 表');

  final encodingCount = bd.getUint16(cmapOffset + 2);
  var subtableOffset = -1;
  for (var i = 0; i < encodingCount; i++) {
    final rec = cmapOffset + 4 + i * 8;
    final platformId = bd.getUint16(rec);
    final encodingId = bd.getUint16(rec + 2);
    final offset = bd.getUint32(rec + 4);
    final format = bd.getUint16(cmapOffset + offset);
    final preferred = (platformId == 3 && (encodingId == 1 || encodingId == 10)) ||
        platformId == 0;
    if (preferred && (format == 4 || format == 12)) {
      subtableOffset = cmapOffset + offset;
      break;
    }
  }
  if (subtableOffset < 0) throw const FormatException('lucide.ttf cmap 无可用子表');

  final format = bd.getUint16(subtableOffset);
  final codepoints = <int>{};
  if (format == 4) {
    final segCountX2 = bd.getUint16(subtableOffset + 6);
    final segCount = segCountX2 ~/ 2;
    final endCodesBase = subtableOffset + 14;
    final startCodesBase = endCodesBase + segCountX2 + 2;
    final idDeltaBase = startCodesBase + segCountX2;
    final idRangeOffsetBase = idDeltaBase + segCountX2;
    for (var seg = 0; seg < segCount; seg++) {
      final end = bd.getUint16(endCodesBase + seg * 2);
      final start = bd.getUint16(startCodesBase + seg * 2);
      if (start == 0xFFFF) continue; // 结尾哨兵段
      final idDelta = bd.getInt16(idDeltaBase + seg * 2);
      final idRangeOffset = bd.getUint16(idRangeOffsetBase + seg * 2);
      for (var cp = start; cp <= end; cp++) {
        if (idRangeOffset == 0) {
          // idDelta 回绕加法按 uint16 语义取模；glyphId 为 0 即 .notdef（无字形）。
          if (((cp + idDelta) & 0xFFFF) != 0) codepoints.add(cp);
        } else {
          final glyphIndexAddress = idRangeOffsetBase +
              seg * 2 +
              idRangeOffset +
              (cp - start) * 2;
          if (bd.getUint16(glyphIndexAddress) != 0) codepoints.add(cp);
        }
      }
    }
  } else if (format == 12) {
    final nGroups = bd.getUint32(subtableOffset + 12);
    for (var g = 0; g < nGroups; g++) {
      final rec = subtableOffset + 16 + g * 12;
      final start = bd.getUint32(rec);
      final end = bd.getUint32(rec + 4);
      for (var cp = start; cp <= end; cp++) {
        codepoints.add(cp);
      }
    }
  } else {
    throw FormatException('不支持的 cmap 子表格式 $format');
  }
  return codepoints;
}
