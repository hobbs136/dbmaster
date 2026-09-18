import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'secret_redactor.dart';

/// 统一日志工具，替代所有散落的 print()
///
/// 使用方式：
///   AppLogger.d('MyService', 'Detailed debug message');   // DEBUG
///   AppLogger.i('MyService', 'Info message');            // INFO
///   AppLogger.w('MyService', 'Warning message');         // WARNING
///   AppLogger.e('MyService', 'Error message');           // ERROR
///   AppLogger.e('MyService', 'Error with exception', e); // ERROR with stack
///
/// 双通道输出：`developer.log`（调试器可见，与历史行为一致）+ **文件落盘**
/// （release 排障，U14）。文件通道需先 [init]；未 init / init 失败 / 写盘
/// 出错时自动停用文件通道——日志工具自身绝不能成为新的错误源，所有落盘
/// 异常就地吞掉。
///
/// 文件策略：每次会话一个 `dbmaster_<yyyyMMdd_HHmmss>.log`；单文件超过
/// 上限滚动到 `_N` 后缀（每会话最多滚动 3 次后停写，单会话硬上限 ~20MB）；
/// 启动时按修改时间只保留最新 10 个文件。落盘行统一先过 [redactSecrets]——
/// 调用点按「调试日志」语义写成明文，落盘文件是持久数据，必须防御性脱敏
/// （spec FR-011）。
class AppLogger {
  static const String _name = 'Dbmaster';

  // ── 文件通道状态（static = 主 isolate 单例；后台 isolate 各自独立，退化
  // 为仅 developer.log，安全）──
  static Directory? _logsDir;
  static File? _logFile;
  static IOSink? _sink;
  static String? _sessionBaseName;
  static int _bytesWritten = 0;
  static int _rollCount = 0;
  static bool _fileDisabled = false;

  static const int _defaultMaxFileBytes = 5 * 1024 * 1024;
  static const int _defaultMaxKeepFiles = 10;
  static const int _defaultMaxRolls = 3;
  static int _maxFileBytes = _defaultMaxFileBytes;
  static int _maxKeepFiles = _defaultMaxKeepFiles;
  static int _maxRolls = _defaultMaxRolls;

  /// 日志目录（[init] 成功后非空；设置页「打开日志目录」入口用）。
  static Directory? get logsDirectory => _logsDir;

  /// 当前正在写的日志文件（未 init 或已停写时为 null；「导出日志」入口用）。
  static File? get currentLogFile =>
      (_sink != null && !_fileDisabled) ? _logFile : null;

  /// 初始化文件通道。目录不存在则创建；任何失败只停用文件通道，不抛出。
  /// [maxFileBytes] / [maxKeepFiles] / [maxRollsPerSession] 供测试缩小规模。
  static Future<void> init(
    Directory logsDir, {
    int? maxFileBytes,
    int? maxKeepFiles,
    int? maxRollsPerSession,
  }) async {
    try {
      await logsDir.create(recursive: true);
      _maxFileBytes = maxFileBytes ?? _defaultMaxFileBytes;
      _maxKeepFiles = maxKeepFiles ?? _defaultMaxKeepFiles;
      _maxRolls = maxRollsPerSession ?? _defaultMaxRolls;
      _logsDir = logsDir;
      _sessionBaseName = 'dbmaster_${_fileNameStamp(DateTime.now())}';
      final logFile = File(_join(logsDir.path, '$_sessionBaseName.log'));
      // 注意：openWrite 在 Windows 上惰性建文件，此处不能读 length()（会
      // PathNotFound 竞态）。字节计数归零——同秒重复 init（仅测试场景）时
      // 首次滚动会略晚，无实际影响。
      _sink = _openSink(logFile);
      _bytesWritten = 0;
      _logFile = logFile;
      _rollCount = 0;
      _fileDisabled = false;
      await _pruneOldFiles();
      _writeFile('[App] session start · ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}');
    } catch (_) {
      _fileDisabled = true;
    }
  }

  /// 把缓冲写进磁盘（导出日志前调用，保证拷到最新行）。
  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// 冲刷并关闭文件通道（窗口关闭时调用；之后退化回仅 developer.log）。
  static Future<void> dispose() async {
    final sink = _sink;
    _sink = null;
    _logFile = null;
    try {
      await sink?.flush();
      await sink?.close();
    } catch (_) {}
  }

  /// 测试隔离：关掉文件通道并清空全部状态。
  static Future<void> resetForTesting() async {
    await dispose();
    _logsDir = null;
    _sessionBaseName = null;
    _bytesWritten = 0;
    _rollCount = 0;
    _fileDisabled = false;
    _maxFileBytes = _defaultMaxFileBytes;
    _maxKeepFiles = _defaultMaxKeepFiles;
    _maxRolls = _defaultMaxRolls;
  }

  static void d(String tag, String message) => _emit('DEBUG', tag, message);
  static void i(String tag, String message) => _emit('INFO', tag, message);
  static void w(String tag, String message) => _emit('WARN', tag, message);
  static void e(String tag, String message, [Object? error, StackTrace? st]) =>
      _emit('ERROR', tag, message, error, st);

  /// 外部进程输出透传（如 embedded server 的 tracing stderr 行）——行自带
  /// 级别/时间戳，只加 [tag] 标记来源，不再套级别前缀。
  static void external(String tag, String line) {
    developer.log('[$tag] $line', name: _name);
    _writeFile('[$tag] $line');
  }

  /// 日志用 SQL 预览：超长 SQL（如整库导出脚本，可达 MB 级）截断——
  /// 拼完整 SQL 进日志既拖慢执行（字符串插值在调用点已付出代价）也污染输出。
  static String sqlPreview(String sql, [int max = 200]) {
    if (sql.length <= max) return sql;
    return '${sql.substring(0, max)}...<${sql.length} chars>';
  }

  static void _emit(String level, String tag, String message,
      [Object? error, StackTrace? st]) {
    final buf = StringBuffer('[$level] [$tag] $message');
    if (error != null) buf.write('\n$error');
    if (st != null) buf.write('\n$st');
    final text = buf.toString();
    developer.log(text, name: _name, error: error, stackTrace: st);
    _writeFile(text);
  }

  static void _writeFile(String content) {
    if (_sink == null || _fileDisabled) return;
    // 时间戳 + 脱敏在文件通道统一做（developer.log 保持调用方原文）。
    final line = '${_stamp(DateTime.now())} ${redactSecrets(content)}';
    // 滚动会替换 _sink——sink 引用必须在滚动之后再取，否则握着已 close
    // 的旧 sink writeln 抛 StateError，被误判为磁盘故障停用整个通道。
    if (_bytesWritten + line.length + 1 > _maxFileBytes && !_roll()) return;
    final sink = _sink;
    if (sink == null) return;
    try {
      sink.writeln(line);
      _bytesWritten += line.length + 1;
    } catch (_) {
      _fileDisabled = true;
    }
  }

  /// 打开追加模式 sink，并挂一次性 `done` 错误处理——writeln 是同步入队
  /// （StringSink，返回 void），缓冲写失败（磁盘满等）在 `done` future 上
  /// 结算。必须就地吞掉并停用通道，不能让它变成未处理异步错误（会经全局
  /// 钩子回到 ErrorReporter → AppLogger 形成反馈环）。
  static IOSink _openSink(File file) {
    final sink = file.openWrite(mode: FileMode.append);
    unawaited(sink.done.then((_) {}, onError: (_) {
      _fileDisabled = true;
    }));
    return sink;
  }

  /// 滚动到 `_N` 后缀新文件；超过每会话滚动次数上限则停写（硬上限）。
  static bool _roll() {
    if (_rollCount >= _maxRolls) {
      _fileDisabled = true;
      return false;
    }
    _rollCount++;
    final old = _sink;
    // 旧 sink 的 close 自带 flush；不 await——滚动不能阻塞调用方日志路径。
    if (old != null) unawaited(old.close().then((_) {}, onError: (_) {}));
    try {
      final dir = _logsDir!;
      final rolled = File(_join(dir.path, '${_sessionBaseName}_$_rollCount.log'));
      _sink = _openSink(rolled);
      _logFile = rolled;
      _bytesWritten = 0;
      return true;
    } catch (_) {
      _sink = null;
      _fileDisabled = true;
      return false;
    }
  }

  /// 启动清理：只保留最新 [_maxKeepFiles] 个 .log（按 mtime）。
  static Future<void> _pruneOldFiles() async {
    final dir = _logsDir;
    if (dir == null) return;
    final files = <File>[];
    try {
      await for (final entry in dir.list()) {
        if (entry is File && entry.path.endsWith('.log')) files.add(entry);
      }
    } catch (_) {
      return;
    }
    if (files.length <= _maxKeepFiles) return;
    final statted = <(File, DateTime)>[];
    for (final f in files) {
      try {
        statted.add((f, f.lastModifiedSync()));
      } catch (_) {}
    }
    statted.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (f, _) in statted.skip(_maxKeepFiles)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// `2026-08-17 14:30:22.123`（DateTime.toString 截到毫秒）。
  static String _stamp(DateTime t) => t.toString().substring(0, 23);

  static String _fileNameStamp(DateTime t) =>
      '${t.year}${_pad2(t.month)}${_pad2(t.day)}'
      '_${_pad2(t.hour)}${_pad2(t.minute)}${_pad2(t.second)}';

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}
