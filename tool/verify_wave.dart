// verify_wave.dart — 波次收口校验工具（纯 Dart CLI，零新依赖）。
//
// 用法：
//   dart run tool/verify_wave.dart --analyze-baseline 149 [--base HEAD]
//       [--spec-section 6.23] [--allow <路径前缀或清单文件>]...
//       [--max-line 1000] [--skip-tests] [--tests <目录/文件列表>] [--self-test]
//
// 检查项（逐项 PASS/FAIL/SKIPPED，末尾汇总，任一 FAIL → exit 1）：
//   a. `dart analyze lib/` 的 issues found 数 == --analyze-baseline（自动运行并解析）；
//   b. ARB：六语 JSON 合法；与 --base 比对「缺失键 / 值变化 / 顺序位移」（未给 --base 则只验 JSON）；
//      新增键要求六语齐备；
//   c. spec 结构：`## <section>` 唯一、`###` 子节标题唯一、尾注 `*文档结束*` 合法居末
//      （其后仅允许空行与 `*最后更新` 元数据行）、无连续重复非空行；
//      单行长度上限（--max-line，默认 1000）覆盖 PROJECT_STATUS.md / AGENTS.md /
//      dbmaster-flutter/AGENTS.md / docs/test/unified_test_spec.md（存在才查）；
//   d. git diff 中新增行命中变更标记（CHANGE 冒号字面量运行时拼接，避免本工具源码
//      被自身扫描规则与 pre-commit 钩子误伤；--base 为空则查未提交 diff）；
//   e. git status --porcelain 路径必须全部匹配 --allow 列表（未给 --allow 则 SKIPPED 不算 FAIL）；
//      --allow 的值若为存在的文件，则按清单文件读取（每行一个前缀）；
//   f. 可选：--tests 指定目标时运行 `flutter test <targets>`（--skip-tests 强制不跑；默认不跑）。
//
// --self-test：在系统临时目录建最小 fixture，对纯函数（ARB 比对 / spec 结构 /
// 行长 / 重复行）跑正反例，全部通过打印 PASS；不触碰仓库文件。

import 'dart:convert';
import 'dart:io';

const Set<String> _kLocales = <String>{'en', 'zh', 'zh_TW', 'de', 'fr', 'ru'};
const String _kTailNote = '*文档结束*';
const String _kAllowedTailPrefix = '*最后更新';
// 变更标记字面量运行时拼接（预提交钩子与本工具自身都按此字面量扫描源码）。
const String _kChangeMarker = 'CHANGE' ':';

// CLI 工具允许 stdout/stderr 输出（print 禁令针对生产代码，CLI 例外）。
void _log(String line) => stdout.writeln(line);
void _err(String line) => stderr.writeln(line);

class CheckResult {
  final String id;
  final String status; // PASS / FAIL / SKIPPED
  final List<String> evidence;
  const CheckResult(this.id, this.status, this.evidence);
}

void main(List<String> args) async {
  final parsed = _parseArgs(args);
  if (parsed == null) {
    exitCode = 2;
    return;
  }
  if (parsed.selfTest) {
    final ok = _runSelfTest();
    exitCode = ok ? 0 : 1;
    return;
  }
  final baseline = parsed.analyzeBaseline;
  if (baseline == null) {
    _err('缺少 --analyze-baseline <n>');
    exitCode = 2;
    return;
  }

  final root = _repoRoot();
  final results = <CheckResult>[];

  // ---------- a. dart analyze ----------
  results.add(await _checkAnalyze(root, baseline));

  // ---------- b. ARB ----------
  results.add(await _checkArb(root, parsed.base));

  // ---------- c. spec 结构 ----------
  results.addAll(await _checkSpecStructure(root, parsed.specSection, parsed.maxLine));

  // ---------- d. 变更标记（见 _kChangeMarker） ----------
  results.add(await _checkChangeMarker(root, parsed.base));

  // ---------- e. allow 范围 ----------
  results.add(await _checkAllowList(root, parsed.allow));

  // ---------- f. 定向测试 ----------
  results.add(await _checkTests(root, parsed));

  // ---------- 汇总 ----------
  _log('');
  _log('===== 汇总 =====');
  var failCount = 0;
  for (final r in results) {
    _log('${r.status.padRight(7)} ${r.id}');
    for (final e in r.evidence) {
      _log('         $e');
    }
    if (r.status == 'FAIL') {
      failCount++;
    }
  }
  _log('');
  if (failCount == 0) {
    _log('PASS: ${results.length} 项检查全部通过（SKIPPED 不计失败）');
  } else {
    _log('FAIL: $failCount 项检查失败');
    exitCode = 1;
  }
}

class _Args {
  int? analyzeBaseline;
  String? base;
  String? specSection;
  List<String> allow = <String>[];
  int maxLine = 1000;
  bool skipTests = false;
  List<String> tests = <String>[];
  bool selfTest = false;
}

_Args? _parseArgs(List<String> args) {
  final result = _Args();
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--self-test') {
      result.selfTest = true;
      continue;
    }
    String name;
    String? value;
    if (arg.startsWith('--')) {
      final eq = arg.indexOf('=');
      if (eq > 0) {
        name = arg.substring(0, eq);
        value = arg.substring(eq + 1);
      } else {
        name = arg;
        if (name != '--skip-tests') {
          if (i + 1 >= args.length) {
            _err('$name 缺少值');
            return null;
          }
          i++;
          value = args[i];
        }
      }
    } else {
      _err('未知参数: $arg');
      return null;
    }
    switch (name) {
      case '--analyze-baseline':
        final n = int.tryParse(value ?? '');
        if (n == null) {
          _err('--analyze-baseline 必须是整数');
          return null;
        }
        result.analyzeBaseline = n;
      case '--base':
        result.base = value;
      case '--spec-section':
        result.specSection = value;
      case '--allow':
        if (value != null && value.isNotEmpty) {
          result.allow.add(value);
        }
      case '--max-line':
        final n = int.tryParse(value ?? '');
        if (n == null || n <= 0) {
          _err('--max-line 必须是正整数');
          return null;
        }
        result.maxLine = n;
      case '--skip-tests':
        result.skipTests = true;
      case '--tests':
        if (value != null && value.isNotEmpty) {
          result.tests.addAll(value.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty));
        }
      default:
        _err('未知参数: $name');
        return null;
    }
  }
  return result;
}

String _repoRoot() {
  final scriptFile = File(Platform.script.toFilePath());
  return scriptFile.parent.parent.path; // tool/ 的上一级
}

String _workspaceRoot() {
  final sep = Platform.pathSeparator;
  final root = _repoRoot();
  final idx = root.lastIndexOf(sep);
  return idx > 0 ? root.substring(0, idx) : root;
}

// ============================================================
// 检查实现
// ============================================================

Future<CheckResult> _checkAnalyze(String root, int baseline) async {
  final proc = await Process.run('dart', <String>['analyze', 'lib'],
      workingDirectory: root, runInShell: true);
  final output = '${proc.stdout}\n${proc.stderr}';
  final matches = RegExp(r'(\d+)\s+issues?\s+found').allMatches(output);
  int? found;
  if (matches.isNotEmpty) {
    found = int.tryParse(matches.last.group(1) ?? '');
  } else if (output.contains('No issues found')) {
    found = 0;
  }
  if (found == null) {
    return CheckResult('a. dart analyze', 'FAIL', <String>[
      '无法解析 issues 数（dart analyze exit ${proc.exitCode}）',
      ...output.trim().split('\n').take(10),
    ]);
  }
  final ok = found == baseline;
  return CheckResult('a. dart analyze lib/ 基线', ok ? 'PASS' : 'FAIL', <String>[
    'issues found = $found（基线 $baseline，exit ${proc.exitCode}）',
  ]);
}

Future<CheckResult> _checkArb(String root, String? base) async {
  final sep = Platform.pathSeparator;
  final l10nDir = '$root${sep}lib${sep}l10n';
  final problems = <String>[];
  final current = <String, Map<String, dynamic>>{};
  for (final locale in _kLocales) {
    final file = File('$l10nDir${sep}app_$locale.arb');
    if (!file.existsSync()) {
      problems.add('ARB 缺失: ${file.path}');
      continue;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        current[locale] = decoded;
      } else {
        problems.add('$locale: 顶层不是对象');
      }
    } on FormatException catch (e) {
      problems.add('$locale: JSON 非法: $e');
    }
  }
  if (problems.isNotEmpty) {
    return CheckResult('b. ARB 六语 JSON', 'FAIL', problems);
  }
  if (base == null || base.isEmpty) {
    return CheckResult('b. ARB 六语 JSON', 'PASS', <String>[
      '六语 JSON 全部合法（未给 --base，跳过 HEAD 比对）',
    ]);
  }

  // 取 HEAD 版本（stdoutEncoding: utf8 —— Windows 默认系统码页会把 UTF-8 内容解码成乱码）
  final old = <String, Map<String, dynamic>>{};
  for (final locale in _kLocales) {
    final rel = 'lib/l10n/app_$locale.arb';
    final proc = await Process.run('git', <String>['show', '$base:$rel'],
        workingDirectory: root,
        runInShell: true,
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    if (proc.exitCode != 0) {
      problems.add('$locale: git show $base:$rel 失败（exit ${proc.exitCode}）');
      continue;
    }
    try {
      final decoded = jsonDecode(proc.stdout.toString());
      if (decoded is Map<String, dynamic>) {
        old[locale] = decoded;
      } else {
        problems.add('$locale: HEAD 版本顶层不是对象');
      }
    } on FormatException catch (e) {
      problems.add('$locale: HEAD 版本 JSON 非法: $e');
    }
  }
  if (problems.isNotEmpty) {
    return CheckResult('b. ARB vs $base', 'FAIL', problems);
  }

  for (final locale in _kLocales) {
    final diff = compareArb(old[locale] ?? <String, dynamic>{}, current[locale] ?? <String, dynamic>{});
    for (final k in diff.missingKeys) {
      problems.add('$locale: 缺失键 $k（HEAD 有、当前无）');
    }
    for (final k in diff.valueChanges) {
      problems.add('$locale: 既有键 $k 值变化');
    }
    if (diff.orderShifted) {
      problems.add('$locale: 既有键顺序位移（HEAD 相对顺序被破坏）');
    }
  }
  // 新增键六语齐备
  final newKeysByLocale = <String, Set<String>>{};
  for (final locale in _kLocales) {
    final diff = compareArb(old[locale] ?? <String, dynamic>{}, current[locale] ?? <String, dynamic>{});
    newKeysByLocale[locale] = diff.newKeys.where((k) => !k.startsWith('@')).toSet();
  }
  final union = <String>{};
  for (final s in newKeysByLocale.values) {
    union.addAll(s);
  }
  for (final key in union) {
    final missing = _kLocales.where((l) => !newKeysByLocale[l]!.contains(key)).toList();
    if (missing.isNotEmpty) {
      problems.add('新增键 $key 缺少语言: ${missing.join(', ')}');
    }
  }
  if (problems.isNotEmpty) {
    return CheckResult('b. ARB vs $base', 'FAIL', problems);
  }
  final addedTotal = union.length;
  return CheckResult('b. ARB vs $base', 'PASS', <String>[
    '既有键值逐字一致、顺序无位移；新增键 $addedTotal 个，六语齐备',
  ]);
}

class ArbDiff {
  final List<String> missingKeys;
  final List<String> valueChanges;
  final List<String> newKeys;
  final bool orderShifted;
  const ArbDiff(this.missingKeys, this.valueChanges, this.newKeys, this.orderShifted);
}

/// 纯函数：比对旧/新 ARB 解析结果（LinkedHashMap 保序）。
ArbDiff compareArb(Map<String, dynamic> oldMap, Map<String, dynamic> newMap) {
  final missing = <String>[];
  final changed = <String>[];
  final fresh = <String>[];
  final newKeysOrder = newMap.keys.toList();
  var lastIndex = -1;
  var shifted = false;
  for (final key in oldMap.keys) {
    if (!newMap.containsKey(key)) {
      missing.add(key);
      continue;
    }
    if (jsonEncode(oldMap[key]) != jsonEncode(newMap[key])) {
      changed.add(key);
    }
    final idx = newKeysOrder.indexOf(key);
    if (idx < lastIndex) {
      shifted = true;
    }
    lastIndex = idx;
  }
  for (final key in newMap.keys) {
    if (!oldMap.containsKey(key)) {
      fresh.add(key);
    }
  }
  return ArbDiff(missing, changed, fresh, shifted);
}

Future<List<CheckResult>> _checkSpecStructure(String root, String? section, int maxLine) async {
  final results = <CheckResult>[];
  final sep = Platform.pathSeparator;
  final specPath = '$root${sep}docs${sep}test${sep}unified_test_spec.md';
  final specFile = File(specPath);
  if (!specFile.existsSync()) {
    results.add(CheckResult('c. spec 结构', 'FAIL', <String>['规格文件不存在: $specPath']));
    return results;
  }
  final lines = specFile.readAsStringSync().split('\n');

  // 节头唯一
  if (section != null && section.isNotEmpty) {
    final prefix = '## $section';
    final matches = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] == prefix || lines[i].startsWith('$prefix ')) {
        matches.add(i + 1);
      }
    }
    if (matches.length != 1) {
      results.add(CheckResult('c. spec 节头 ## $section', 'FAIL', <String>[
        matches.isEmpty ? '未找到节头' : '出现 ${matches.length} 次: ${matches.join(', ')}',
      ]));
    } else {
      results.add(CheckResult('c. spec 节头 ## $section', 'PASS', <String>['唯一（行 ${matches.first}）']));
    }
  } else {
    results.add(const CheckResult('c. spec 节头', 'SKIPPED', <String>['未给 --spec-section']));
  }

  // ### 子节标题唯一（按所属 `## ` 节内判定——全仓既有大量跨节通用小标题如「说明」，
  // 事故形态是同一节内重复子节头，故按节作用域收窄；跨节同名不算重复）
  final dupHeadings = duplicateHeadingsWithinSection(lines);
  final headingTotal = duplicateHeadingCount(lines);
  results.add(CheckResult('c. spec 子节标题唯一', dupHeadings.isEmpty ? 'PASS' : 'FAIL', <String>[
    dupHeadings.isEmpty
        ? '全部 $headingTotal 个 ### 标题在各自节内唯一'
        : '节内重复: ${dupHeadings.take(5).join(' ; ')}',
  ]));

  // 尾注
  final tailProblem = specTailProblem(lines);
  results.add(CheckResult('c. spec 尾注结构', tailProblem == null ? 'PASS' : 'FAIL', <String>[
    tailProblem ?? '$_kTailNote 合法居末',
  ]));

  // 连续重复非空行
  final dups = consecutiveDuplicateNonEmptyLines(lines);
  results.add(CheckResult('c. spec 连续重复行', dups.isEmpty ? 'PASS' : 'FAIL', <String>[
    dups.isEmpty ? '无连续重复非空行' : '行号: ${dups.join(', ')}',
  ]));

  // 行长检查（存在才查）。存量超限行只记数不判失败；仅「本次 diff 新增行」超限才 FAIL
  //（波次收口语义：不因历史遗留挡门，但禁止新增超限行）。
  final lengthTargets = <String, String>{
    'PROJECT_STATUS.md': '${_workspaceRoot()}${sep}PROJECT_STATUS.md',
    'AGENTS.md': '${_workspaceRoot()}${sep}AGENTS.md',
    'dbmaster-flutter/AGENTS.md': '$root${sep}AGENTS.md',
    'docs/test/unified_test_spec.md': specPath,
  };
  final newViolations = <String>[];
  var legacyCount = 0;
  for (final entry in lengthTargets.entries) {
    final f = File(entry.value);
    if (!f.existsSync()) {
      continue;
    }
    final fileLines = f.readAsLinesSync();
    final over = linesOverLimit(fileLines, maxLine);
    if (over.isEmpty) {
      continue;
    }
    final added = await addedLineNumbers(entry.value);
    for (final item in over) {
      final colon = item.indexOf(':');
      final lineNo = int.tryParse(item.substring(0, colon)) ?? 0;
      if (added.contains(lineNo)) {
        newViolations.add('${entry.key}:$item（新增行）');
      } else {
        legacyCount++;
      }
    }
  }
  final lenFail = newViolations.isNotEmpty;
  final lenEvidence = <String>[
    '新增行超限 ${newViolations.length} 处；存量超限 $legacyCount 处（不判失败）',
  ];
  if (lenFail) {
    lenEvidence.add('新增超限（前 10）: ${newViolations.take(10).join(' ; ')}');
  }
  results.add(CheckResult('c. 行长上限($maxLine)', lenFail ? 'FAIL' : 'PASS', lenEvidence));
  return results;
}

/// 纯函数：按所属 `## ` 节判定 ### 子节标题是否节内重复。
/// 返回重复描述列表（"标题 → 行 a, b"）。
List<String> duplicateHeadingsWithinSection(List<String> lines) {
  final counts = <String, List<int>>{};
  var currentSection = '(文件头)';
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trimLeft();
    if (raw.startsWith('## ') && !raw.startsWith('### ')) {
      currentSection = raw.trimRight();
      continue;
    }
    if (raw.startsWith('### ') && !raw.startsWith('#### ')) {
      final key = '$currentSection :: ${raw.trimRight()}';
      counts.putIfAbsent(key, () => <int>[]).add(i + 1);
    }
  }
  final result = <String>[];
  for (final entry in counts.entries) {
    if (entry.value.length > 1) {
      final parts = entry.key.split(' :: ');
      final section = parts.first.length > 20 ? '${parts.first.substring(0, 20)}…' : parts.first;
      result.add('${parts.last}（$section）→ 行 ${entry.value.join(', ')}');
    }
  }
  return result;
}

/// 纯函数：统计 ### 子节标题总数（供证据展示）。
int duplicateHeadingCount(List<String> lines) {
  var n = 0;
  for (final line in lines) {
    final raw = line.trimLeft();
    if (raw.startsWith('### ') && !raw.startsWith('#### ')) {
      n++;
    }
  }
  return n;
}

/// 纯函数：解析 `git diff -U0` 输出，返回新文件侧「+」新增行号集合。
Set<int> addedLinesFromDiff(String diffOutput) {
  final result = <int>{};
  final hunk = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@');
  int? cursor;
  for (final line in diffOutput.split('\n')) {
    final m = hunk.firstMatch(line);
    if (m != null) {
      cursor = int.tryParse(m.group(1) ?? '') ?? 0;
      continue;
    }
    if (cursor == null || line.startsWith('\\')) {
      continue;
    }
    if (line.startsWith('-')) {
      continue; // 旧文件侧行不推进新文件游标
    }
    if (line.startsWith('+')) {
      result.add(cursor);
    }
    cursor++;
  }
  return result;
}

/// 返回指定文件（绝对路径）在其所属 git 仓库中「本次 diff 新增行」的行号集合。
/// base 为空则查未提交 diff（HEAD）；文件不在 git 仓库或未被跟踪 → 全部行视为新增。
Future<Set<int>> addedLineNumbers(String absolutePath) async {
  final repoRoot = _gitRootFor(absolutePath);
  if (repoRoot == null) {
    return _allLineNumbers(absolutePath);
  }
  final normalized = absolutePath.replaceAll('\\', '/');
  final rootNorm = repoRoot.replaceAll('\\', '/');
  final rel = normalized.startsWith('$rootNorm/') ? normalized.substring(rootNorm.length + 1) : normalized;
  final diff = await Process.run('git', <String>['diff', '-U0', '--', rel],
      workingDirectory: repoRoot,
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  if (diff.exitCode == 0 && diff.stdout.toString().isNotEmpty) {
    return addedLinesFromDiff(diff.stdout.toString());
  }
  // 无 diff：未跟踪新文件（??）时全部行算新增；否则按 HEAD diff 再查一次
  final st = await Process.run('git', <String>['status', '--porcelain', '--', rel],
      workingDirectory: repoRoot,
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  if (st.stdout.toString().startsWith('??')) {
    return _allLineNumbers(absolutePath);
  }
  final diffHead = await Process.run('git', <String>['diff', 'HEAD', '-U0', '--', rel],
      workingDirectory: repoRoot,
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  if (diffHead.exitCode == 0 && diffHead.stdout.toString().isNotEmpty) {
    return addedLinesFromDiff(diffHead.stdout.toString());
  }
  return <int>{};
}

Set<int> _allLineNumbers(String absolutePath) {
  final f = File(absolutePath);
  if (!f.existsSync()) {
    return <int>{};
  }
  final n = f.readAsLinesSync().length;
  return <int>{for (var i = 1; i <= n; i++) i};
}

String? _gitRootFor(String filePath) {
  var dir = File(filePath).parent;
  while (true) {
    if (Directory('${dir.path}${Platform.pathSeparator}.git').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
}

/// 纯函数：尾注结构检查（尾注唯一，其后仅空行与 `*最后更新` 元数据行）。
String? specTailProblem(List<String> lines) {
  var tailLine = -1;
  var count = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith(_kTailNote)) {
      count++;
      if (tailLine < 0) {
        tailLine = i;
      }
    }
  }
  if (count == 0) {
    return '未找到尾注 "$_kTailNote"';
  }
  if (count > 1) {
    return '尾注出现 $count 次（应为 1）';
  }
  for (var i = tailLine + 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith(_kAllowedTailPrefix)) {
      continue;
    }
    return '尾注之后（行 ${i + 1}）存在非预期内容: "${line.substring(0, line.length > 60 ? 60 : line.length)}"';
  }
  return null;
}

/// 纯函数：连续重复非空行检测（返回 1-based 行号）。
List<int> consecutiveDuplicateNonEmptyLines(List<String> lines) {
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

/// 纯函数：行长超限检测（返回 "行号:长度" 列表）。
List<String> linesOverLimit(List<String> lines, int maxLine) {
  final result = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].length > maxLine) {
      result.add('${i + 1}:${lines[i].length}');
    }
  }
  return result;
}

Future<CheckResult> _checkChangeMarker(String root, String? base) async {
  final diffArgs = <String>['diff'];
  if (base != null && base.isNotEmpty) {
    diffArgs.add(base);
  } else {
    diffArgs.add('HEAD'); // 未提交 diff（含 staged + unstaged）
  }
  final proc = await Process.run('git', diffArgs,
      workingDirectory: root,
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  if (proc.exitCode != 0) {
    return CheckResult('d. CHANGE 标记', 'FAIL', <String>[
      'git ${diffArgs.join(' ')} 失败（exit ${proc.exitCode}）',
    ]);
  }
  final hits = addedChangeMarkerHits(proc.stdout.toString());
  return CheckResult('d. 变更标记新增行', hits.isEmpty ? 'PASS' : 'FAIL', <String>[
    hits.isEmpty ? 'diff 新增行零命中' : '命中 ${hits.length} 处（前 10）: ${hits.take(10).join(' ; ')}',
  ]);
}

/// 纯函数：扫描 unified diff 新增行（`+` 行）中的变更标记（_kChangeMarker），
/// 返回 "文件: 内容摘录" 命中列表。
List<String> addedChangeMarkerHits(String diffOutput) {
  final hits = <String>[];
  var currentFile = '';
  for (final line in diffOutput.split('\n')) {
    if (line.startsWith('+++ b/')) {
      currentFile = line.substring(6).trim();
      continue;
    }
    if (line.startsWith('+') && !line.startsWith('+++')) {
      if (line.contains(_kChangeMarker)) {
        final text = line.substring(1).trim();
        hits.add('$currentFile: ${text.substring(0, text.length > 60 ? 60 : text.length)}');
      }
    }
  }
  return hits;
}

Future<CheckResult> _checkAllowList(String root, List<String> allowArgs) async {
  if (allowArgs.isEmpty) {
    return const CheckResult('e. 变更范围', 'SKIPPED', <String>['未给 --allow，跳过范围核对']);
  }
  final prefixes = <String>[];
  for (final arg in allowArgs) {
    final f = File(arg);
    if (f.existsSync()) {
      for (final line in f.readAsLinesSync()) {
        final t = line.trim();
        if (t.isNotEmpty) {
          prefixes.add(t.replaceAll('\\', '/'));
        }
      }
    } else {
      prefixes.add(arg.replaceAll('\\', '/'));
    }
  }
  final proc = await Process.run('git', <String>['status', '--porcelain'],
      workingDirectory: root,
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  if (proc.exitCode != 0) {
    return CheckResult('e. 变更范围', 'FAIL', <String>['git status 失败（exit ${proc.exitCode}）']);
  }
  final violations = <String>[];
  for (final raw in proc.stdout.toString().split('\n')) {
    if (raw.trim().isEmpty) {
      continue;
    }
    var path = raw.length > 3 ? raw.substring(3).trim() : '';
    if (path.contains(' -> ')) {
      path = path.split(' -> ').last;
    }
    if (path.startsWith('"') && path.endsWith('"') && path.length > 1) {
      path = path.substring(1, path.length - 1);
    }
    if (path.isEmpty) {
      continue;
    }
    var ok = false;
    for (final p in prefixes) {
      if (p == '.') {
        ok = true;
        break;
      }
      final withSlash = p.endsWith('/') ? p : '$p/';
      if (path == p || path.startsWith(withSlash)) {
        ok = true;
        break;
      }
    }
    if (!ok) {
      violations.add(path);
    }
  }
  return CheckResult('e. 变更范围', violations.isEmpty ? 'PASS' : 'FAIL', <String>[
    violations.isEmpty
        ? '全部变更路径匹配 --allow（${prefixes.length} 个前缀）'
        : '越界变更 ${violations.length} 处（前 10）: ${violations.take(10).join(' ; ')}',
  ]);
}

Future<CheckResult> _checkTests(String root, _Args parsed) async {
  if (parsed.skipTests || parsed.tests.isEmpty) {
    return const CheckResult('f. 定向测试', 'SKIPPED', <String>['未指定 --tests（或 --skip-tests），不运行测试']);
  }
  _log('运行定向测试: flutter test ${parsed.tests.join(' ')} ...');
  final proc = await Process.run('flutter', <String>['test', ...parsed.tests],
      workingDirectory: root, runInShell: true);
  final output = proc.stdout.toString().trim();
  final tail = output.split('\n').skip(output.split('\n').length > 5 ? output.split('\n').length - 5 : 0).join('\n');
  return CheckResult('f. 定向测试', proc.exitCode == 0 ? 'PASS' : 'FAIL', <String>[
    'flutter test exit ${proc.exitCode}',
    ...tail.split('\n'),
  ]);
}

// ============================================================
// --self-test：临时目录 fixture，只测纯函数，不触碰仓库文件
// ============================================================

bool _runSelfTest() {
  var pass = 0;
  var fail = 0;
  void expect(String name, bool cond) {
    if (cond) {
      pass++;
      _log('  PASS $name');
    } else {
      fail++;
      _log('  FAIL $name');
    }
  }

  _log('[self-test] ARB 比对（compareArb）');
  final oldArb = <String, dynamic>{'a': '1', 'b': '2', '@a': <String, String>{'description': 'x'}};
  final goodNew = <String, dynamic>{'a': '1', 'b': '2', '@a': <String, String>{'description': 'x'}, 'c': '3'};
  expect('无变化+新增 → 干净', _diffClean(compareArb(oldArb, goodNew), shifted: false, changed: 0, missing: 0, fresh: 1));
  expect('值变化 → 检出', compareArb(oldArb, <String, dynamic>{'a': '1', 'b': '2!'}).valueChanges.length == 1);
  expect('缺键 → 检出', compareArb(oldArb, <String, dynamic>{'a': '1'}).missingKeys.length == 2);
  expect('顺序位移 → 检出', compareArb(oldArb, <String, dynamic>{'b': '2', 'a': '1'}).orderShifted);

  _log('[self-test] spec 尾注结构（specTailProblem）');
  expect('仅尾注 → 合法', specTailProblem(<String>['内容', _kTailNote]) == null);
  expect('尾注+最后更新 → 合法', specTailProblem(<String>['$_kTailNote  ', '', '$_kAllowedTailPrefix 2026']) == null);
  expect('尾注后夹内容 → 非法', specTailProblem(<String>[_kTailNote, '夹层内容']) != null);
  expect('双尾注 → 非法', specTailProblem(<String>[_kTailNote, '', _kTailNote]) != null);
  expect('无尾注 → 非法', specTailProblem(<String>['正文']) != null);

  _log('[self-test] 连续重复非空行');
  expect('无重复 → 空', consecutiveDuplicateNonEmptyLines(<String>['a', '', 'a', 'b']).isEmpty);
  expect('连续重复 → 检出行 2', consecutiveDuplicateNonEmptyLines(<String>['a', 'a']).join(',') == '2');
  expect('空行不算重复', consecutiveDuplicateNonEmptyLines(<String>['', '']).isEmpty);

  _log('[self-test] 行长上限');
  expect('超限检出', linesOverLimit(<String>['ok', 'x' * 11], 10).join(',') == '2:11');
  expect('未超限 → 空', linesOverLimit(<String>['ok'], 10).isEmpty);

  _log('[self-test] 节内子节标题唯一');
  expect('跨节同名 → 不算重复',
      duplicateHeadingsWithinSection(<String>['## A', '### 说明', '## B', '### 说明']).isEmpty);
  expect('同节重复 → 检出',
      duplicateHeadingsWithinSection(<String>['## A', '### 说明', '### 说明']).length == 1);

  _log('[self-test] diff 新增行号解析');
  const diffOut = '--- a/f.md\n+++ b/f.md\n@@ -1,3 +1,4 @@\n a\n+new1\n+new2\n b\n@@ -10,2 +12,2 @@\n+new3\n c\n';
  final added = addedLinesFromDiff(diffOut);
  expect('hunk1 新增行 2,3', added.contains(2) && added.contains(3));
  expect('hunk2 新增行 12', added.contains(12));
  expect('上下文行不计', !added.contains(1) && !added.contains(13) && !added.contains(14));

  _log('[self-test] 变更标记新增行扫描');
  // fixture 用运行时常量拼出真实标记，源码中不出现字面量
  final markerDiff = '--- a/f.dart\n+++ b/f.dart\n@@ -1,2 +1,3 @@\n'
      ' ok\n+$_kChangeMarker fixture 命中\n+无关行\n clean\n';
  final markerHits = addedChangeMarkerHits(markerDiff);
  expect('新增行命中检出', markerHits.length == 1 && markerHits.first.startsWith('f.dart:'));
  expect('旧文件侧行不命中',
      addedChangeMarkerHits('+++ b/f.dart\n-removed $_kChangeMarker\n context\n').isEmpty);
  expect('上下文行不命中', addedChangeMarkerHits('+++ b/f.dart\n kept $_kChangeMarker\n').isEmpty);

  _log('[self-test] 尾注检测 fixture 写入临时目录');
  // 临时目录 fixture（readAsLinesSync 真文件路径），验证后清理
  Directory? tmpDir;
  try {
    tmpDir = Directory.systemTemp.createTempSync('verify_wave_self_test_');
    final f = File('${tmpDir.path}${Platform.pathSeparator}spec.md');
    f.writeAsStringSync('正文\n$_kTailNote  \n\n$_kAllowedTailPrefix 尾注元数据\n');
    final fileLines = f.readAsLinesSync();
    expect('真文件尾注结构合法', specTailProblem(fileLines) == null);
  } finally {
    if (tmpDir != null && tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  }

  _log('');
  _log('[self-test] 结果: $pass PASS / $fail FAIL');
  return fail == 0;
}

bool _diffClean(ArbDiff d, {required bool shifted, required int changed, required int missing, required int fresh}) {
  return d.orderShifted == shifted &&
      d.valueChanges.length == changed &&
      d.missingKeys.length == missing &&
      d.newKeys.length == fresh;
}
