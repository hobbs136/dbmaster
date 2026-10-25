// append_test_spec.dart — 统一测试规格安全追加工具（纯 Dart CLI，零新依赖）。
//
// 用法：
//   dart run tool/append_test_spec.dart --section "6.23" --heading "UIRV-XX · 标题"
//       --file <block.md> [--dry-run] [--spec <path>]
//
// 行为（目标文件默认 docs/test/unified_test_spec.md）：
//   1. 找到唯一的 `## <section>` 节头（0 个或 >1 个直接失败；>1 时列出候选行号）；
//   2. 拒绝重复子节标题：`### <heading>` 已存在则失败；
//   3. 把 block.md 内容插到文档尾注（`*文档结束*` 行）之前；
//      尾注后只允许空行与 `*最后更新` 开头的元数据行（本仓既有结构），否则失败并提示先修结构；
//   4. 拒绝插入后出现连续重复非空行；
//   5. 临时文件 + rename 原子写；--dry-run 只校验并打印插入位置，不写文件。

import 'dart:io';

// CLI 工具允许 stdout/stderr 输出（print 禁令针对生产代码，CLI 例外）。
void _log(String line) => stdout.writeln(line);
void _err(String line) => stderr.writeln(line);

const String _kTailNote = '*文档结束*';
const String _kAllowedTailPrefix = '*最后更新';

void main(List<String> args) async {
  String? section;
  String? heading;
  String? blockPath;
  String? specPath;
  var dryRun = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg.startsWith('--')) {
      String? value;
      final eq = arg.indexOf('=');
      if (eq > 0) {
        value = arg.substring(eq + 1);
      }
      final name = eq > 0 ? arg.substring(0, eq) : arg;
      if (value == null) {
        if (i + 1 >= args.length) {
          _err('$name 缺少值');
          exitCode = 2;
          return;
        }
        i++;
        value = args[i];
      }
      if (name == '--section') {
        section = value;
      } else if (name == '--heading') {
        heading = value;
      } else if (name == '--file') {
        blockPath = value;
      } else if (name == '--spec') {
        specPath = value;
      } else {
        _err('未知参数: $name');
        exitCode = 2;
        return;
      }
    } else {
      _err('未知参数: $arg');
      exitCode = 2;
      return;
    }
  }
  if (section == null || heading == null || blockPath == null) {
    _err('用法: dart run tool/append_test_spec.dart --section "6.23" '
        '--heading "UIRV-XX · 标题" --file <block.md> [--dry-run] [--spec <path>]');
    exitCode = 2;
    return;
  }

  final root = _repoRoot();
  final specFile = File(specPath ?? '$root/docs/test/unified_test_spec.md');
  if (!specFile.existsSync()) {
    _err('规格文件不存在: ${specFile.path}');
    exitCode = 2;
    return;
  }
  final blockFile = File(blockPath);
  if (!blockFile.existsSync()) {
    _err('block 文件不存在: $blockPath');
    exitCode = 2;
    return;
  }

  final content = specFile.readAsStringSync();
  final lines = content.split('\n');

  // ---------- 1. 节头唯一性 ----------
  final sectionLine = '## $section';
  final sectionMatches = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line == sectionLine || line.startsWith('$sectionLine ')) {
      sectionMatches.add(i + 1);
    }
  }
  if (sectionMatches.isEmpty) {
    _err('FAIL: 未找到节头 "$sectionLine"');
    exitCode = 1;
    return;
  }
  if (sectionMatches.length > 1) {
    _err('FAIL: 节头 "$sectionLine" 出现 ${sectionMatches.length} 次（须唯一），候选行号: '
        '${sectionMatches.join(', ')}');
    exitCode = 1;
    return;
  }

  // ---------- 2. 子节标题重复 ----------
  final headingLine = '### $heading';
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] == headingLine) {
      _err('FAIL: 子节标题 "$headingLine" 已存在（行 ${i + 1}）');
      exitCode = 1;
      return;
    }
  }

  // ---------- 3. 尾注位置 ----------
  final tailLine = _findTailNote(lines);
  if (tailLine == null) {
    _err('FAIL: 未找到尾注 "$_kTailNote"');
    exitCode = 1;
    return;
  }
  final tailProblem = _tailNoteStructureProblem(lines);
  if (tailProblem != null) {
    _err('FAIL: $tailProblem');
    _err('请先修复文档结构（尾注 $_kTailNote 之后只允许空行与 $_kAllowedTailPrefix 元数据行）');
    exitCode = 1;
    return;
  }

  // ---------- 4. 组装新内容 ----------
  final blockRaw = blockFile.readAsStringSync().trimRight();
  if (blockRaw.isEmpty) {
    _err('FAIL: block 文件为空');
    exitCode = 1;
    return;
  }
  final blockLines = blockRaw.split('\n');
  // 插入点：尾注行之前，先回退尾注前的空行，保证 block 与前文之间一个空行
  var insertAt = tailLine - 1; // 0-based 尾注行索引
  while (insertAt > 0 && lines[insertAt - 1].trim().isEmpty) {
    insertAt--;
  }
  final newLines = <String>[
    ...lines.sublist(0, insertAt),
    '', // 与前文空行分隔
    ...blockLines,
    '', // 与尾注空行分隔
    ...lines.sublist(insertAt),
  ];

  // ---------- 5. 插入后结构校验：连续重复非空行 ----------
  final dupLines = _consecutiveDuplicateNonEmptyLines(newLines);
  if (dupLines.isNotEmpty) {
    _err('FAIL: 插入后出现连续重复非空行（未写盘），行号: ${dupLines.join(', ')}');
    for (final ln in dupLines.take(5)) {
      final text = newLines[ln - 1].trim();
      _err('  行 $ln: ${text.substring(0, text.length > 80 ? 80 : text.length)}');
    }
    exitCode = 1;
    return;
  }

  // 插入位置的人类可读描述（以原行号）
  final anchorBefore = insertAt > 0 ? lines[insertAt - 1].trim() : '(文件头)';
  final anchorShow = anchorBefore.substring(0, anchorBefore.length > 60 ? 60 : anchorBefore.length);
  final preview =
      '插入位置: 原第 ${insertAt + 1} 行（尾注 "$_kTailNote" 位于原第 $tailLine 行）之前；'
      '前一非空行: ${anchorBefore.isEmpty ? '(空行)' : anchorShow}';

  if (dryRun) {
    _log('[dry-run] 结构校验通过，未写盘。');
    _log(preview);
    _log('block 共 ${blockLines.length} 行，标题 "$headingLine"。');
    return;
  }

  // ---------- 6. 原子写盘 ----------
  final newContent = newLines.join('\n');
  // 最终合法性：JSON 结构工具不适用，这里只做基本不变式（尾注仍存在且唯一）
  final verifyLines = newContent.split('\n');
  var tailCount = 0;
  for (final line in verifyLines) {
    if (line.trimLeft().startsWith(_kTailNote)) {
      tailCount++;
    }
  }
  if (tailCount != 1) {
    _err('FAIL: 写盘前自检失败——尾注出现 $tailCount 次（应为 1），未写盘');
    exitCode = 1;
    return;
  }
  final tmp = File('${specFile.path}.tmp_append_spec');
  try {
    tmp.writeAsStringSync(newContent, flush: true);
    tmp.renameSync(specFile.path);
  } on FileSystemException catch (e) {
    _err('写入失败: $e');
    if (tmp.existsSync()) {
      tmp.deleteSync();
    }
    exitCode = 1;
    return;
  }
  _log('OK: 已追加到 ${specFile.path}');
  _log(preview);
  _log('新文件共 ${verifyLines.length} 行（原 ${lines.length} 行，+${verifyLines.length - lines.length}）。');
}

String _repoRoot() {
  final scriptFile = File(Platform.script.toFilePath());
  return scriptFile.parent.parent.path; // tool/ 的上一级
}

/// 返回尾注行号（1-based），按 trimLeft 前缀匹配（容忍行尾空格）。
int? _findTailNote(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith(_kTailNote)) {
      return i + 1;
    }
  }
  return null;
}

/// 尾注结构检查：尾注之后只允许空行与 `*最后更新` 开头的元数据行。
/// 返回 null 表示结构合法，否则返回失败原因。
String? _tailNoteStructureProblem(List<String> lines) {
  final tailLine = _findTailNote(lines);
  if (tailLine == null) {
    return '未找到尾注 "$_kTailNote"';
  }
  for (var i = tailLine; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith(_kAllowedTailPrefix)) {
      continue;
    }
    return '尾注之后（行 ${i + 1}）存在非预期内容: "${line.substring(0, line.length.clamp(0, 60))}"';
  }
  // 尾注本身必须唯一
  var count = 0;
  for (final line in lines) {
    if (line.trimLeft().startsWith(_kTailNote)) {
      count++;
    }
  }
  if (count > 1) {
    return '尾注 "$_kTailNote" 出现 $count 次（应为 1）';
  }
  return null;
}

/// 返回连续重复非空行的行号（1-based，报重复对的第二行）。
List<int> _consecutiveDuplicateNonEmptyLines(List<String> lines) {
  final result = <int>[];
  for (var i = 1; i < lines.length; i++) {
    final prev = lines[i - 1].trim();
    final cur = lines[i].trim();
    if (prev.isNotEmpty && prev == cur) {
      result.add(i + 1);
    }
  }
  return result;
}
