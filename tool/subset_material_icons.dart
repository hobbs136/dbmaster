// subset_material_icons.dart — MaterialIcons 字体子集（#31 T15，构建后处理）
//
// 用法：dart run tool/subset_material_icons.dart [--dist dist/Release]
//
// 背景（T01 实证）：Flutter 3.41 Windows 桌面构建的 --tree-shake-icons 实际
// 不生效，MaterialIcons-Regular.otf（1.57MB）按 SDK 原版直拷进产物。本工具
// 在构建产物上做后处理：静态扫描会被编进程序的全部源码（app lib/test/
// integration_test + .dart_tool/package_config.json 依赖闭包 + Flutter SDK
// 框架库），收集 `Icons.*` 引用并解析为码点，用 pyftsubset 原地子集化
// dist 产物里的 MaterialIcons-Regular.otf。
//
// 码点来源：SDK material/icons.dart 常量表 + PlatformAdaptiveIcons 的
// adaptive getter（`Icons.adaptive.more` 这类平台自适应引用，展开为两个
// 候选图标并全部保留）。
//
// fail-open 纪律：本工具失败（无 Python/fontTools、package_config 缺失、
// 解析异常等）一律打警告后退出 0——保留原版字体，构建不因此挂掉，只是
// 产物大 ~1.5MB。
import 'dart:convert';
import 'dart:io';

import 'font_subset_common.dart';

void main(List<String> args) async {
  var distDir = 'dist/Release';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--dist') distDir = args[i + 1];
  }
  banner('MaterialIcons 字体子集（构建后处理）');
  final fontFile = '$distDir/data/flutter_assets/fonts/MaterialIcons-Regular.otf';
  if (!File(fontFile).existsSync()) {
    stdout.writeln('  跳过：未找到 $fontFile');
    return;
  }

  try {
    await _subset(fontFile);
  } catch (e) {
    stdout.writeln('  [警告] MaterialIcons 子集化失败（保留原版字体，产物'
        '大 ~1.5MB）：$e');
  }
}

Future<void> _subset(String fontFile) async {
  // ── 1. 解析依赖闭包：app 自身 + 全部包 + Flutter SDK 路径 ──
  final packageConfig = File('.dart_tool/package_config.json');
  if (!packageConfig.existsSync()) {
    throw StateError('缺少 .dart_tool/package_config.json（先 flutter pub get）');
  }
  final config =
      (jsonDecode(packageConfig.readAsStringSync()) as Map<String, dynamic>);
  final packages = (config['packages'] as List).cast<Map<String, dynamic>>();

  final scanDirs = <Directory>[
    Directory('lib'),
    Directory('test'),
    Directory('integration_test'),
  ];
  String? sdkFlutterLib;
  for (final pkg in packages) {
    final name = pkg['name'] as String?;
    final rootUri = pkg['rootUri'] as String?;
    if (name == null || rootUri == null) continue;
    final rootPath = _fileUriToPath(rootUri);
    if (name == 'flutter') {
      // rootUri 形如 <sdk>/packages/flutter —— lib/src/material 是框架内部
      // Icons 引用（BackButton/选择工具栏/PaginatedDataTable 等）的来源。
      sdkFlutterLib = '$rootPath/lib';
    }
    // 依赖包只扫 lib/（编译进产物的部分）；路径依赖（含 third_party）同样覆盖。
    scanDirs.add(Directory('$rootPath/lib'));
  }
  if (sdkFlutterLib == null) {
    throw StateError('package_config 中未找到 flutter 包（无法定位 SDK）');
  }

  // ── 2. 扫描全部源码的 Icons 引用（含 adaptive getter 成员）──
  const plainPattern = r'\bIcons\.([a-zA-Z0-9_]+)';
  const adaptivePattern = r'\bIcons\.adaptive\.([a-zA-Z0-9_]+)';
  final constNames = <String>{};
  final adaptiveNames = <String>{};
  for (final dir in scanDirs) {
    constNames.addAll(scanDartSourcesFor(dir, RegExp(plainPattern)));
    adaptiveNames.addAll(scanDartSourcesFor(dir, RegExp(adaptivePattern)));
  }
  constNames.remove('adaptive'); // getter 分组本身不是图标，单独展开
  if (constNames.isEmpty && adaptiveNames.isEmpty) {
    stdout.writeln('  跳过：未扫描到任何 Icons 引用（异常，保守起见不动字体）');
    return;
  }

  // ── 3. 解析 SDK icons.dart：常量表 + adaptive getter 展开 ──
  // sdkFlutterLib 已是 <sdk>/packages/flutter/lib。
  final iconsSource = File('$sdkFlutterLib/src/material/icons.dart')
      .readAsStringSync();

  final codepointByName = <String, int>{};
  for (final match in RegExp(
          r'static const IconData ([a-zA-Z0-9_]+) = IconData\(\s*0x([0-9a-fA-F]+)')
          .allMatches(iconsSource)) {
    codepointByName[match.group(1)!] = int.parse(match.group(2)!, radix: 16);
  }

  final unresolved = <String>[];
  final codepoints = <int>{};
  void resolve(String name) {
    final cp = codepointByName[name];
    if (cp == null) {
      unresolved.add(name);
    } else {
      codepoints.add(cp);
    }
  }

  for (final name in constNames) {
    resolve(name);
  }
  // adaptive getter：`IconData get more => !_isCupertino() ? Icons.more_vert
  // : Icons.more_horiz;` —— 展开为候选集（Windows 上恒走前者，两者都保留）。
  final adaptiveGetterRe =
      RegExp(r'IconData get ([a-zA-Z0-9_]+) =>(.+?);', dotAll: true);
  final adaptiveBodies = <String, String>{};
  for (final match in adaptiveGetterRe.allMatches(iconsSource)) {
    adaptiveBodies[match.group(1)!] = match.group(2)!;
  }
  for (final member in adaptiveNames) {
    final body = adaptiveBodies[member];
    if (body == null) {
      unresolved.add('adaptive.$member');
      continue;
    }
    for (final ref in RegExp(r'\bIcons\.([a-zA-Z0-9_]+)').allMatches(body)) {
      resolve(ref.group(1)!);
    }
  }

  if (unresolved.isNotEmpty) {
    // 未解析名通常是注释命中或非图标符号（如 Icons.adaptive 分组）——
    // 打印出来供人工核对，但不阻塞（保守方向是多打几个字形）。
    stdout.writeln('  未解析引用（注释/非图标命中，忽略）：'
        '${unresolved.take(10).join(', ')}${unresolved.length > 10 ? ' …' : ''}');
  }
  if (codepoints.isEmpty) {
    stdout.writeln('  跳过：码点解析结果为空（保守起见不动字体）');
    return;
  }
  stdout.writeln('  引用图标：${constNames.length} 常量 + ${adaptiveNames.length} '
      'adaptive → 去重码点 ${codepoints.length} 个');

  // ── 4. pyftsubset 原地子集化产物字体 ──
  final python = await findPythonWithFontTools();
  if (python == null) {
    stdout.writeln('  [警告] 未找到 Python 3 + fontTools，保留原版字体'
        '（安装后下次构建自动生效，或用 DBMASTER_PYTHON 指定）');
    return;
  }
  final before = File(fontFile).lengthSync();
  final tmpOut = '$fontFile.subset';
  if (!await runPyftsubset(python, fontFile, codepoints, tmpOut)) {
    try {
      File(tmpOut).deleteSync();
    } catch (_) {}
    throw StateError('pyftsubset 执行失败');
  }
  File(tmpOut).renameSync(fontFile);
  final after = File(fontFile).lengthSync();
  stdout.writeln('  MaterialIcons-Regular.otf：${(before / 1024).toStringAsFixed(0)} KB '
      '-> ${(after / 1024).toStringAsFixed(0)} KB');
}

String _fileUriToPath(String uri) {
  var path = uri;
  if (path.startsWith('file:///')) {
    path = path.substring('file:///'.length);
  } else if (path.startsWith('file://')) {
    path = path.substring('file://'.length);
  }
  // package_config 中根相对 URI（如 "../"）已由 pub 展开为绝对 file URI，
  // 这里只需处理 percent-encoding 与盘符。
  path = Uri(path: path).toFilePath();
  return path;
}
