// font_subset_common.dart — 字体子集化共用工具（#31 T15）
//
// 供 tool/subset_lucide_font.dart（Lucide 子集，产物提交进仓库）与
// tool/subset_material_icons.dart（MaterialIcons 子集，构建产物后处理）复用：
//   - Python 3 + fontTools 探测（fail-open：探测不到返回 null，调用方保留原字体）
//   - pyftsubset 进程调用（fontTools.subset 模块）
//   - Dart 源码图标引用扫描（递归收集 .dart 文件中的正则命中）
import 'dart:io';

/// 探测可用的 Python 3 + fontTools 解释器路径。
///
/// 优先级：`DBMASTER_PYTHON` 环境变量 > PATH 上的 python/python3/py >
/// 常见安装位置（%LOCALAPPDATA%\Python\bin、%LOCALAPPDATA%\Programs\Python\*）。
/// 每个候选用 `import fontTools` 试运行验证（Windows 商店 stub 会立即失败或
/// 超时，自动跳过）。返回 null = 本机不可用，调用方应 fail-open 并打印提示。
Future<String?> findPythonWithFontTools() async {
  final env = Platform.environment['DBMASTER_PYTHON'];
  final candidates = <String>[
    if (env != null && env.isNotEmpty) env,
    'python',
    'python3',
    'py',
  ];
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData != null) {
    candidates.add('$localAppData\\Python\\bin\\python.exe');
    final programsDir = Directory('$localAppData\\Programs\\Python');
    if (programsDir.existsSync()) {
      final versions = programsDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final dir in versions) {
        final exe = File('${dir.path}\\python.exe');
        if (exe.existsSync()) candidates.add(exe.path);
      }
    }
  }

  for (final cmd in candidates) {
    try {
      final result = await Process.run(cmd, <String>[
        '-c',
        'import sys, fontTools; '
            'sys.stdout.write(fontTools.version); '
            'sys.exit(0 if sys.version_info >= (3, 8) else 1)',
      ]).timeout(const Duration(seconds: 15));
      if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
        return cmd;
      }
    } catch (_) {
      // 启动失败 / 超时（Windows 商店 stub）：尝试下一个候选。
    }
  }
  return null;
}

/// 用 pyftsubset 生成子集字体。
///
/// [codepoints] 为需要的码点集合（十进制）；输出写到 [outputFile]。
/// 成功返回 true；失败（进程异常 / 产物缺失）返回 false，调用方 fail-open。
Future<bool> runPyftsubset(
  String python,
  String fontFile,
  Set<int> codepoints,
  String outputFile,
) async {
  final tmpDir = Directory.systemTemp;
  final unicodesFile =
      File('${tmpDir.path}/dbmaster_subset_${DateTime.now().millisecondsSinceEpoch}.txt');
  await unicodesFile.writeAsString(
    codepoints.map((cp) => cp.toRadixString(16)).join('\n'),
    flush: true,
  );
  try {
    final result = await Process.run(python, <String>[
      '-m', 'fontTools.subset', fontFile,
      '--unicodes-file=${unicodesFile.path}',
      '--output-file=$outputFile',
      // 图标字体不需要 GSUB/GPOS 布局闭包与 hinting，全部裁掉更小。
      '--no-layout-closure',
      '--no-hinting',
      // 保留 .notdef 轮廓：缺失字形时渲染为可见方框而非空白，便于发现问题。
      '--notdef-outline',
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('pyftsubset 失败 (exit ${result.exitCode}):\n${result.stderr}');
      return false;
    }
    final out = File(outputFile);
    if (!out.existsSync() || out.lengthSync() == 0) return false;
    return true;
  } finally {
    try {
      await unicodesFile.delete();
    } catch (_) {
      // 临时文件清理失败无碍。
    }
  }
}

/// 递归扫描目录下所有 .dart 文件，返回 [pattern] 的第一个捕获组合集。
///
/// 忽略 .dart_tool / build / .git 等目录；[excludePathContains] 用于排除
/// 会自引用污染扫描结果的文件（如守卫测试自身的文档注释）。
/// 目录不存在时返回空集。
Set<String> scanDartSourcesFor(
  Directory dir,
  RegExp pattern, {
  List<String> excludePathContains = const [],
}) {
  if (!dir.existsSync()) return <String>{};
  final matches = <String>{};
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (entity.path.contains(RegExp(r'[/\\]\.dart_tool[/\\]'))) continue;
    if (excludePathContains.any(entity.path.contains)) continue;
    // 一次性读取整文件（含注释/文档命中，宁多勿缺——多出的图标只多几十字节）。
    final source = entity.readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      final name = match.group(1);
      if (name != null) matches.add(name);
    }
  }
  return matches;
}

/// 读取 UTF-8 文件并打印小工具横幅。
void banner(String title) {
  stdout.writeln('== $title ==');
}
