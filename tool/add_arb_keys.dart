// add_arb_keys.dart — 六语 ARB 原子追加工具（纯 Dart CLI，零新依赖）。
//
// 用法：
//   dart run tool/add_arb_keys.dart --input <keys.json> [--dry-run] [--no-gen-l10n] [--force]
//
// keys.json 形态：
//   {
//     "新键名": {"en": "...", "zh": "...", "zh_TW": "...", "de": "...",
//               "fr": "...", "ru": "...", "@description": "可选"}
//   }
//
// 行为：
//   1. 校验每个键六语（en/zh/zh_TW/de/fr/ru）齐全；
//   2. 默认拒绝已存在键（--force 允许重复插入，按 JSON last-wins 语义覆盖，见下）；
//   3. 对每个 lib/l10n/app_*.arb 做【文本级追加】：保留原文件格式与既有内容逐字不变，
//      只在末尾 `}` 前插入键块；写入前用 JSON 解析验证新内容合法；
//      临时文件 + rename 原子替换；任一语文件校验失败则一个文件都不写。
//   4. 默认最后运行 `flutter gen-l10n`（--no-gen-l10n 关闭；--dry-run 不运行）。
//   5. 输出每个文件新增键数。
//
// 注意：--force 对已存在键采用「重复插入 last-wins」实现（JSON 解析与 gen-l10n 均取后值），
// 不做整体重序列化（本工具存在的原因正是禁绝整体重序列化破坏格式）。推荐仍以新键为主。

import 'dart:convert';
import 'dart:io';

const Set<String> _kLocales = <String>{'en', 'zh', 'zh_TW', 'de', 'fr', 'ru'};

// CLI 工具允许 stdout/stderr 输出（AGENTS.md §0 print 禁令针对生产代码，CLI 例外）。
void _log(String line) => stdout.writeln(line);
void _err(String line) => stderr.writeln(line);

void main(List<String> args) async {
  String? inputPath;
  var dryRun = false;
  var genL10n = true;
  var force = false;
  for (final arg in args) {
    if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--no-gen-l10n') {
      genL10n = false;
    } else if (arg == '--force') {
      force = true;
    } else if (arg.startsWith('--input=')) {
      inputPath = arg.substring('--input='.length);
    } else if (arg == '--input') {
      inputPath = null; // 值在下一个参数
      _pendingInput = true;
    } else if (_pendingInput) {
      inputPath = arg;
      _pendingInput = false;
    } else {
      _err('未知参数: $arg');
      _usage();
      exitCode = 2;
      return;
    }
  }
  if (inputPath == null) {
    _err('缺少 --input <keys.json>');
    _usage();
    exitCode = 2;
    return;
  }

  final root = _repoRoot();
  final keysFile = File(inputPath);
  if (!keysFile.existsSync()) {
    _err('keys 文件不存在: $inputPath');
    exitCode = 2;
    return;
  }

  // ---------- 1. 解析 keys.json ----------
  final Map<String, dynamic> raw;
  try {
    final decoded = jsonDecode(keysFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      _err('keys.json 顶层必须是 JSON 对象');
      exitCode = 2;
      return;
    }
    raw = decoded;
  } on FormatException catch (e) {
    _err('keys.json 不是合法 JSON: $e');
    exitCode = 2;
    return;
  }
  if (raw.isEmpty) {
    _err('keys.json 为空，无事可做');
    exitCode = 2;
    return;
  }

  // 校验六语齐全 + 值类型
  final errors = <String>[];
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is! Map<String, dynamic>) {
      errors.add('键 ${entry.key}: 值必须是对象（各语言文案）');
      continue;
    }
    for (final locale in _kLocales) {
      if (!value.containsKey(locale)) {
        errors.add('键 ${entry.key}: 缺少 $locale 文案');
      } else if (value[locale] is! String) {
        errors.add('键 ${entry.key}: $locale 值必须是字符串');
      }
    }
    final desc = value['@description'];
    if (desc != null && desc is! String) {
      errors.add('键 ${entry.key}: @description 必须是字符串');
    }
  }
  if (errors.isNotEmpty) {
    _err('六语校验失败（未写任何文件）:');
    for (final e in errors) {
      _err('  - $e');
    }
    exitCode = 1;
    return;
  }

  // ---------- 2. 全量校验既有 ARB ----------
  final newKeys = raw.keys.toList();
  final perLocaleNewText = <String, String>{};
  final perLocaleAdded = <String, int>{};
  final loadErrors = <String>[];
  for (final locale in _kLocales.toList()..sort()) {
    final arbFile = File(_arbPath(root, locale));
    if (!arbFile.existsSync()) {
      loadErrors.add('ARB 文件不存在: ${arbFile.path}');
      continue;
    }
    final original = arbFile.readAsStringSync();
    final Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(original);
      if (decoded is! Map<String, dynamic>) {
        loadErrors.add('$locale: ARB 顶层不是对象');
        continue;
      }
      parsed = decoded;
    } on FormatException catch (e) {
      loadErrors.add('$locale: 既有 ARB 不是合法 JSON: $e');
      continue;
    }

    // 重复键检查（默认拒绝）
    final conflicts = <String>[];
    for (final key in newKeys) {
      if (parsed.containsKey(key)) {
        conflicts.add(key);
      }
    }
    if (conflicts.isNotEmpty && !force) {
      loadErrors.add('$locale: 以下键已存在（--force 可覆盖）: ${conflicts.join(', ')}');
      continue;
    }
    if (conflicts.isNotEmpty && force) {
      _log('警告 [$locale]: --force 覆盖已存在键（重复插入 last-wins）: ${conflicts.join(', ')}');
    }

    // 组装键块：键行 + 紧随的 @meta 行（行间逗号统一补齐，末行逗号由 _insertBeforeFinalBrace 控制）
    final lines = <String>[];
    for (final key in newKeys) {
      final value = raw[key] as Map<String, dynamic>;
      lines.add('  ${jsonEncode(key)}: ${jsonEncode(value[locale] as String)}');
      final desc = value['@description'];
      if (desc is String) {
        lines.add('  ${jsonEncode('@$key')}: ${jsonEncode(<String, String>{'description': desc})}');
      }
    }
    for (var i = 0; i < lines.length - 1; i++) {
      if (!lines[i].endsWith(',')) {
        lines[i] = '${lines[i]},';
      }
    }
    String newText;
    try {
      newText = _insertBeforeFinalBrace(original, lines);
      // 写前验证新内容合法
      final verify = jsonDecode(newText);
      if (verify is! Map<String, dynamic>) {
        loadErrors.add('$locale: 新内容顶层不是对象（内部错误）');
        continue;
      }
    } on FormatException catch (e) {
      loadErrors.add('$locale: 追加后内容不是合法 JSON（未写盘）: $e');
      continue;
    }
    perLocaleNewText[locale] = newText;
    perLocaleAdded[locale] = newKeys.length;
  }
  if (loadErrors.isNotEmpty) {
    _err('校验失败（未写任何文件）:');
    for (final e in loadErrors) {
      _err('  - $e');
    }
    exitCode = 1;
    return;
  }

  // ---------- 3. dry-run ----------
  if (dryRun) {
    _log('[dry-run] 未写任何文件。计划：');
    for (final locale in perLocaleNewText.keys) {
      final added = perLocaleAdded[locale] ?? 0;
      _log('  $locale: 将新增 $added 键（含 @meta 行）');
    }
    _log('[dry-run] gen-l10n: ${genL10n ? '将运行' : '跳过（--no-gen-l10n）'}');
    return;
  }

  // ---------- 4. 原子写盘（临时文件 + rename） ----------
  var written = 0;
  for (final locale in perLocaleNewText.keys) {
    final arbFile = File(_arbPath(root, locale));
    final tmp = File('${arbFile.path}.tmp_add_arb_keys');
    try {
      tmp.writeAsStringSync(perLocaleNewText[locale] ?? '', flush: true);
      tmp.renameSync(arbFile.path);
      written++;
      _log('${arbFile.path.split(Platform.pathSeparator).last}: +${perLocaleAdded[locale]} 键');
    } on FileSystemException catch (e) {
      _err('写入 $locale 失败: $e（已写入 $written 个文件，其余未动）');
      if (tmp.existsSync()) {
        tmp.deleteSync();
      }
      exitCode = 1;
      return;
    }
  }
  _log('完成: $written 个 ARB 文件已原子更新。');

  // ---------- 5. gen-l10n ----------
  if (genL10n) {
    _log('运行 flutter gen-l10n ...');
    final result = await Process.run('flutter', <String>['gen-l10n'],
        workingDirectory: root, runInShell: true);
    if (result.exitCode != 0) {
      _err('flutter gen-l10n 失败（exit ${result.exitCode}）:');
      final out = result.stdout.toString().trim();
      final errOut = result.stderr.toString().trim();
      if (out.isNotEmpty) {
        _err(out);
      }
      if (errOut.isNotEmpty) {
        _err(errOut);
      }
      exitCode = 1;
      return;
    }
    _log('flutter gen-l10n 完成。');
  } else {
    _log('跳过 flutter gen-l10n（--no-gen-l10n）。');
  }
}

bool _pendingInput = false;

void _usage() {
  _err('用法: dart run tool/add_arb_keys.dart --input <keys.json> [--dry-run] [--no-gen-l10n] [--force]');
}

String _repoRoot() {
  final scriptFile = File(Platform.script.toFilePath());
  return scriptFile.parent.parent.path; // tool/ 的上一级
}

String _arbPath(String root, String locale) {
  final sep = Platform.pathSeparator;
  return '$root${sep}lib${sep}l10n${sep}app_$locale.arb';
}

/// 在 content 末尾的 `}` 前插入键行（保留原文本与其尾部空白逐字不变）。
/// 行数 > 0；调用方负责已组装好含逗号的行列表。
String _insertBeforeFinalBrace(String content, List<String> lines) {
  final trimmed = content.trimRight();
  if (!trimmed.endsWith('}')) {
    throw const FormatException('ARB 文本不以 } 结尾');
  }
  final head = trimmed.substring(0, trimmed.length - 1);
  final trailing = content.substring(trimmed.length);
  final headTrim = head.trimRight();
  final separator = headTrim.endsWith('{') ? '' : ',';
  final block = lines.join('\n');
  return '$head$separator\n$block\n}$trailing';
}
