// subset_lucide_font.dart — Lucide 图标字体子集生成器（#31 T15）
//
// 用法（仓库根目录）：dart run tool/subset_lucide_font.dart
//
// 做四件事：
//   1. 扫描 lib/、test/、integration_test/ 中所有 `LucideIcons.xxx` 引用；
//   2. 从 third_party/lucide_icons_flutter/lib/lucide_icons.dart 解析
//      引用名 → 码点（仅 fontFamily 'Lucide' 主字体常量，忽略 w100-w600
//      字重变体——本 app 零引用且字体已不随包分发）；
//   3. 用 pyftsubset 从 assets/lucide-full.ttf 抽取子集 → assets/lucide.ttf
//      （vendored pubspec 只声明后者，故打进产物的只有子集）；
//   4. 再生成守卫清单 test/icons/lucide_subset_manifest.g.dart（供
//      lucide_subset_guard_test.dart 拦截「新增图标未进子集」的回归）。
//
// 依赖：本机 Python 3 + fontTools（自动探测，可用 DBMASTER_PYTHON 指定）。
// 探测不到时以退出码 2 失败——本工具的产物要提交仓库，不应静默跳过
// （与构建脚本的 MaterialIcons 子集 fail-open 策略不同）。
import 'dart:io';

import 'font_subset_common.dart';

Future<void> main(List<String> args) async {
  final quiet = args.contains('--quiet');
  banner('Lucide 字体子集生成');
  const pkgDir = 'third_party/lucide_icons_flutter';
  const sourceFont = '$pkgDir/assets/lucide-full.ttf';
  const outputFont = '$pkgDir/assets/lucide.ttf';
  const iconsDart = '$pkgDir/lib/lucide_icons.dart';
  const manifestOut = 'test/icons/lucide_subset_manifest.g.dart';

  // ── 1. 扫描 app 源码中的 LucideIcons 引用 ──
  // 排除守卫测试自身——其文档注释含 `LucideIcons.xxx` 字面量会污染扫描结果。
  const selfReferential = [
    'lucide_subset_guard_test.dart',
    'lucide_subset_manifest.g.dart',
  ];
  final usedNames = <String>{}
    ..addAll(scanDartSourcesFor(
        Directory('lib'), RegExp(r'\bLucideIcons\.([a-zA-Z0-9_]+)')))
    ..addAll(scanDartSourcesFor(Directory('test'),
        RegExp(r'\bLucideIcons\.([a-zA-Z0-9_]+)'),
        excludePathContains: selfReferential))
    ..addAll(scanDartSourcesFor(
        Directory('integration_test'), RegExp(r'\bLucideIcons\.([a-zA-Z0-9_]+)')));
  if (usedNames.isEmpty) {
    stderr.writeln('未扫描到任何 LucideIcons 引用，可疑——中止以免误清空字体。');
    exit(1);
  }
  stdout.writeln('源码引用图标：${usedNames.length} 个');

  // ── 2. 解析 vendored 常量表：名称 → 码点（仅主 Lucide family）──
  final codepointByName = _parseLucideConstants(File(iconsDart).readAsStringSync());
  final missing = usedNames.difference(codepointByName.keys.toSet()).toList()..sort();
  if (missing.isNotEmpty) {
    stderr.writeln('以下引用在 lucide_icons.dart 中不存在（拼写错误或上游改名）：$missing');
    exit(1);
  }
  final codepoints = usedNames.map((n) => codepointByName[n]!).toSet();
  stdout.writeln('去重后码点：${codepoints.length} 个');

  // ── 3. pyftsubset 生成子集字体 ──
  final python = await findPythonWithFontTools();
  if (python == null) {
    stderr.writeln(
        '未找到可用的 Python 3 + fontTools。请安装后重试，或用 DBMASTER_PYTHON 指定路径。\n'
        '本工具产物需提交仓库，不做 fail-open 跳过。');
    exit(2);
  }
  final tmpOutput = '$outputFont.tmp';
  if (!await runPyftsubset(python, sourceFont, codepoints, tmpOutput)) {
    stderr.writeln('pyftsubset 生成失败，保留现有字体。');
    exit(1);
  }
  final oldSize = File(sourceFont).lengthSync();
  File(tmpOutput).renameSync(outputFont);
  final newSize = File(outputFont).lengthSync();
  stdout.writeln('字体：${_kb(oldSize)} -> ${_kb(newSize)}'
      '（assets/lucide-full.ttf -> assets/lucide.ttf）');

  // ── 4. 再生成守卫清单 ──
  final names = usedNames.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('// 本文件由 tool/subset_lucide_font.dart 自动生成——勿手改。')
    ..writeln('// 当前子集字体（third_party/lucide_icons_flutter/assets/lucide.ttf）')
    ..writeln('// 包含的 Lucide 图标名 → 码点。守卫测试 test/icons/lucide_subset_guard_test.dart')
    ..writeln('// 用它拦截「新增 LucideIcons 引用但未重跑子集脚本」的回归。')
    ..writeln('// 新增图标后请运行：dart run tool/subset_lucide_font.dart')
    ..writeln('const Map<String, int> kLucideSubsetCodepoints = <String, int>{');
  for (final name in names) {
    buffer.writeln("  '$name': ${codepointByName[name]},");
  }
  buffer
    ..writeln('};')
    ..writeln();
  File(manifestOut).parent.createSync(recursive: true);
  File(manifestOut).writeAsStringSync(buffer.toString());
  stdout.writeln('守卫清单已再生成：$manifestOut（${names.length} 项）');
  if (!quiet) {
    stdout.writeln('完成。请将 assets/lucide.ttf 与 manifest 一并提交。');
  }
}

/// 解析 lucide_icons.dart 中主 family（'Lucide'）常量的名称 → 十进制码点。
///
/// 形如（跨行、含 matchTextDirection 变体，字重变体 family 为 'Lucide100'
/// 等被 `family != 'Lucide'` 分组过滤）：
///   static const IconData aArrowDown = const IconData(58757,
///       fontFamily: 'Lucide', fontPackage: 'lucide_icons_flutter');
Map<String, int> _parseLucideConstants(String source) {
  final re = RegExp(
      r"static const IconData ([a-zA-Z0-9_]+) = const IconData\((\d+),\s*fontFamily: '(Lucide\d*)'");
  final result = <String, int>{};
  for (final match in re.allMatches(source)) {
    final family = match.group(3)!;
    if (family != 'Lucide') continue;
    result[match.group(1)!] = int.parse(match.group(2)!);
  }
  return result;
}

String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';
