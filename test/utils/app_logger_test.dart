import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/app_logger.dart';

void main() {
  setUp(() async {
    await AppLogger.resetForTesting();
  });

  tearDown(() async {
    await AppLogger.resetForTesting();
  });

  group('AppLogger', () {
    test('d 不应抛出异常', () {
      expect(() => AppLogger.d('TestTag', 'debug message'), returnsNormally);
    });

    test('i 不应抛出异常', () {
      expect(() => AppLogger.i('TestTag', 'info message'), returnsNormally);
    });

    test('w 不应抛出异常', () {
      expect(() => AppLogger.w('TestTag', 'warning message'), returnsNormally);
    });

    test('e 不应抛出异常', () {
      expect(() => AppLogger.e('TestTag', 'error message'), returnsNormally);
    });

    test('e 带异常不应抛出', () {
      expect(
        () => AppLogger.e('TestTag', 'error', Exception('test')),
        returnsNormally,
      );
    });

    test('e 带异常和堆栈不应抛出', () {
      expect(
        () => AppLogger.e(
          'TestTag',
          'error',
          Exception('test'),
          StackTrace.current,
        ),
        returnsNormally,
      );
    });

    test('连续调用不应抛出', () {
      expect(() {
        AppLogger.d('Tag', '1');
        AppLogger.i('Tag', '2');
        AppLogger.w('Tag', '3');
        AppLogger.e('Tag', '4');
      }, returnsNormally);
    });
  });

  group('AppLogger 文件落盘（U14）', () {
    // 2026-10-27 IOOverrides 化收口（flake 第 5 次复现后，计划 §10.6 第 4 条）；语义断言未变。
    late Directory tempDir;
    late _U14MemFs fs;

    setUp(() async {
      fs = _U14MemFs();
      tempDir = await fs.run(
        () => Directory.systemTemp.createTemp('app_logger_test'),
      );
    });

    tearDown(() async {
      await AppLogger.resetForTesting();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('init 后日志落到会话文件，行含时间戳/级别/tag', () {
      return fs.run(() async {
        await AppLogger.init(tempDir);
        final file = AppLogger.currentLogFile;
        expect(file, isNotNull);
        expect(file!.path, contains('dbmaster_'));
        AppLogger.i('MyTag', 'hello file');
        AppLogger.w('OtherTag', 'warning text');
        await AppLogger.flush();
        final content = await file.readAsString();
        expect(content, contains('[INFO] [MyTag] hello file'));
        expect(content, contains('[WARN] [OtherTag] warning text'));
        // 行首毫秒精度时间戳
        expect(
          RegExp(
            r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ',
            multiLine: true,
          ).hasMatch(content),
          isTrue,
        );
        // 会话头
        expect(content, contains('session start'));
      });
    });

    test('e 的 error 与 stackTrace 追加进文件', () {
      return fs.run(() async {
        await AppLogger.init(tempDir);
        final file = AppLogger.currentLogFile!;
        AppLogger.e(
          'Boom',
          'failed',
          StateError('bad state'),
          StackTrace.current,
        );
        await AppLogger.flush();
        final content = await file.readAsString();
        expect(content, contains('Bad state: bad state'));
      });
    });

    test('落盘行脱敏：password= 明文不进文件', () {
      return fs.run(() async {
        await AppLogger.init(tempDir);
        final file = AppLogger.currentLogFile!;
        AppLogger.e('Conn', 'connect failed: password=hunter2 host=127.0.0.1');
        await AppLogger.flush();
        final content = await file.readAsString();
        expect(content, contains('***'));
        expect(content, isNot(contains('hunter2')));
      });
    });

    test('external 透传外部进程行：tag 标记来源、不套级别前缀', () {
      return fs.run(() async {
        await AppLogger.init(tempDir);
        final file = AppLogger.currentLogFile!;
        const tracing = '2026-08-17T06:00:00.123Z INFO dbmaster_server: ready';
        AppLogger.external('Server', tracing);
        await AppLogger.flush();
        final content = await file.readAsString();
        expect(content, contains('[Server] $tracing'));
        expect(content, isNot(contains('[INFO] [Server]')));
      });
    });

    test('单文件超限滚动到 _N 后缀新文件', () {
      return fs.run(() async {
        await AppLogger.init(tempDir, maxFileBytes: 250, maxRollsPerSession: 3);
        final first = AppLogger.currentLogFile!;
        // 5 行 × ~70 字符 + 会话头 ≈ 490 字符。滚动有分布浪费（每文件尾部
        // ≤70 字符），4×250 的有效容量 ≥ 780 仍富余——必然滚动一次以上、但
        // 不会耗尽 3 次滚动（会话头长度随平台版本串浮动，已留余量）。
        for (var i = 0; i < 5; i++) {
          AppLogger.i('T', 'filler line $i ${'x' * 20}');
        }
        await AppLogger.flush();
        expect(AppLogger.currentLogFile, isNotNull);
        expect(AppLogger.currentLogFile!.path, isNot(first.path));
        expect(
          RegExp(r'_\d\.log$').hasMatch(
            AppLogger.currentLogFile!.path
                .split(Platform.pathSeparator)
                .last,
          ),
          isTrue,
          reason: '滚动后应在 _N 后缀文件上',
        );
        // 旧文件保留（滚动不删除）
        expect(await first.exists(), isTrue);
        // 新文件继续接收写入
        final rolled = await AppLogger.currentLogFile!.readAsString();
        expect(rolled, isNotEmpty);
      });
    });

    test('滚动次数达上限后停写（currentLogFile → null），调用仍不抛', () {
      return fs.run(() async {
        await AppLogger.init(tempDir, maxFileBytes: 100, maxRollsPerSession: 1);
        for (var i = 0; i < 60; i++) {
          AppLogger.i('T', 'flood $i ${'y' * 30}');
        }
        expect(AppLogger.currentLogFile, isNull);
        AppLogger.i('T', 'after disabled');
        AppLogger.external('Server', 'after disabled');
      });
    });

    test('启动清理只保留最新 N 个 .log', () {
      return fs.run(() async {
        // 造 12 个 mtime 错开的旧文件（old_0 最旧，old_11 最新）。
        // 虚拟 FS 下 mtime 由单调计数器按调用顺序分配（writeAsString 与
        // setLastModified 各自严格递增），写入顺序即新旧序，不再依赖真实磁盘。
        for (var i = 0; i < 12; i++) {
          final f = File(
            '${tempDir.path}${Platform.pathSeparator}dbmaster_old_$i.log',
          );
          await f.writeAsString('old $i');
          await f.setLastModified(
            DateTime.now().subtract(Duration(hours: 20 - i)),
          );
        }
        await AppLogger.init(tempDir, maxKeepFiles: 5);
        final remaining = tempDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.log'))
            .toList();
        expect(remaining.length, 5);
        String name(File f) => f.path.split(Platform.pathSeparator).last;
        final names = remaining.map(name).toList();
        // 最旧的被清，最新的旧文件保留
        expect(names, isNot(contains('dbmaster_old_0.log')));
        expect(names, contains('dbmaster_old_11.log'));
        // 新会话文件占一个名额
        expect(names.where((n) => !n.startsWith('dbmaster_old_')).length, 1);
      });
    });

    test('dispose 冲刷并关闭：之后退化，调用不抛，已写内容可读', () {
      return fs.run(() async {
        await AppLogger.init(tempDir);
        AppLogger.i('T', 'before dispose');
        final file = AppLogger.currentLogFile!;
        await AppLogger.dispose();
        expect(AppLogger.currentLogFile, isNull);
        AppLogger.i('T', 'after dispose');
        final content = await file.readAsString();
        expect(content, contains('before dispose'));
        expect(content, isNot(contains('after dispose')));
      });
    });

    test('未 init：getters 为 null，所有入口调用不抛', () {
      return fs.run(() async {
        expect(AppLogger.logsDirectory, isNull);
        expect(AppLogger.currentLogFile, isNull);
        AppLogger.d('T', 'x');
        AppLogger.i('T', 'x');
        AppLogger.w('T', 'x');
        AppLogger.e('T', 'x');
        AppLogger.external('Server', 'x');
      });
    });
  });
}

/// ─────────────────────────────────────────────────────────────────────────
/// U14 专用内存文件系统（2026-10-27 IOOverrides 化收口，test-only）。
///
/// 本 SDK（Dart 3.x）的 [IOOverrides] 是构造器注入缝：overrides zone 内
/// `File()` / `Directory()` / `Directory.systemTemp` 改走
/// [IOOverrides.createFile] / [IOOverrides.createDirectory] /
/// [IOOverrides.getSystemTempDirectory]，之后实例方法全部落在注入的实现上——
/// 因此 `lastModifiedSync` / `deleteSync` / `exists` / `createTemp` /
/// `openWrite` 等旧式 IOOverrides hook 覆盖不到的调用也被一并虚拟化。
///
/// mtime 由 [_U14MemFs._tick] 单调计数器分配：每次写入 / setLastModified /
/// openWrite 严格递增，调用顺序即时间序，消除真实磁盘 mtime 粒度与并行 IO
/// 争用导致的清理排序偶发。整个 U14 组不触真实磁盘。
/// ─────────────────────────────────────────────────────────────────────────
final class _U14MemFs extends IOOverrides {
  /// 真实系统临时目录路径，仅作为内存路径命名空间前缀（构造发生在
  /// overrides zone 之外，拿到的是真实 systemTemp）。
  final String systemTempPath = Directory.systemTemp.path;

  final Map<String, _U14DirNode> _dirs = {};
  final Map<String, _U14FileNode> _files = {};
  int _tick = 0;
  int _unique = 0;

  static final String _sep = Platform.pathSeparator;

  _U14MemFs() {
    // 根节点：systemTemp 本身在内存树中先就位（createTemp 的父目录检查用）。
    _ensureDir(systemTempPath);
  }

  /// 在本文件系统的 IOOverrides zone 内执行 [body]（异步体全程留在 zone 内）。
  Future<R> run<R>(Future<R> Function() body) =>
      IOOverrides.runWithIOOverrides<Future<R>>(body, this);

  // ── IOOverrides 注入缝 ──

  @override
  File createFile(String path) => _U14MemFile._(path, this);

  @override
  Directory createDirectory(String path) => _U14MemDirectory._(path, this);

  @override
  Directory getSystemTempDirectory() => _U14MemDirectory._(systemTempPath, this);

  // ── mtime：单调计数器（每次写入 / setLastModified 严格递增）──

  DateTime _nextMtime() => DateTime.fromMillisecondsSinceEpoch(0)
      .add(Duration(milliseconds: ++_tick));

  // ── 节点操作（_U14MemFile / _U14MemDirectory 委托至此）──

  _U14FileNode _fileNode(String path) =>
      _files.putIfAbsent(path, () => _U14FileNode(_nextMtime()));

  void _ensureDir(String path, {bool recursive = true}) {
    if (_dirs.containsKey(path)) return;
    if (recursive) {
      final parent = _parentOf(path);
      if (parent != path) _ensureDir(parent);
    }
    _dirs[path] = const _U14DirNode();
  }

  Directory _createTempSync(String parentPath, String? prefix) {
    if (!_dirs.containsKey(parentPath)) {
      throw FileSystemException('目录不存在', parentPath);
    }
    final base = prefix ?? 'temp';
    var candidate = '$parentPath$_sep$base${_unique++}';
    while (_dirs.containsKey(candidate) || _files.containsKey(candidate)) {
      candidate = '$parentPath$_sep${base}_${_unique++}';
    }
    _ensureDir(candidate);
    return _U14MemDirectory._(candidate, this);
  }

  void _truncate(String path) {
    final node = _fileNode(path);
    node.modified = _nextMtime();
    node.bytes = Uint8List(0);
  }

  void _appendBytes(String path, List<int> bytes) {
    final node = _fileNode(path);
    node.modified = _nextMtime();
    node.bytes = _concat(node.bytes, bytes);
  }

  void _writeBytes(String path, List<int> bytes, FileMode mode) {
    final append = identical(mode, FileMode.append) ||
        identical(mode, FileMode.writeOnlyAppend);
    final node = _fileNode(path);
    node.modified = _nextMtime();
    node.bytes = append ? _concat(node.bytes, bytes) : Uint8List.fromList(bytes);
  }

  static Uint8List _concat(List<int> head, List<int> tail) {
    final merged = Uint8List(head.length + tail.length)
      ..setRange(0, head.length, head)
      ..setRange(head.length, head.length + tail.length, tail);
    return merged;
  }

  List<FileSystemEntity> _listDir(String dirPath, {required bool recursive}) {
    if (!_dirs.containsKey(dirPath)) {
      throw FileSystemException('目录不存在', dirPath);
    }
    final prefix = '$dirPath$_sep';
    bool isDirectChild(String p) {
      if (!p.startsWith(prefix)) return false;
      final rest = p.substring(prefix.length);
      return rest.isNotEmpty && !rest.contains(_sep);
    }

    final entries = <FileSystemEntity>[
      ..._files.keys
          .where(isDirectChild)
          .map((p) => _U14MemFile._(p, this)),
      ..._dirs.keys
          .where(isDirectChild)
          .map((p) => _U14MemDirectory._(p, this)),
    ]..sort((a, b) => a.path.compareTo(b.path));
    if (recursive) {
      final subDirs =
          _dirs.keys.where(isDirectChild).toList()..sort();
      for (final dir in subDirs) {
        entries.addAll(_listDir(dir, recursive: true));
      }
    }
    return entries;
  }

  void _deleteDir(String path, {required bool recursive}) {
    if (!_dirs.containsKey(path)) {
      throw FileSystemException('目录不存在', path);
    }
    final prefix = '$path$_sep';
    final hasChildren = _files.keys.any((p) => p.startsWith(prefix)) ||
        _dirs.keys.any((p) => p != path && p.startsWith(prefix));
    if (!recursive && hasChildren) {
      throw FileSystemException('目录非空', path);
    }
    if (recursive) {
      _files.removeWhere((p, _) => p.startsWith(prefix));
      _dirs.removeWhere((p, _) => p != path && p.startsWith(prefix));
    }
    _dirs.remove(path);
  }

  Directory _renameDir(String path, String newPath) {
    final node = _dirs.remove(path);
    if (node == null) throw FileSystemException('目录不存在', path);
    final prefix = '$path$_sep';
    for (final key in _files.keys
        .where((p) => p.startsWith(prefix))
        .toList()) {
      _files[newPath + key.substring(path.length)] = _files.remove(key)!;
    }
    for (final key in _dirs.keys
        .where((p) => p != path && p.startsWith(prefix))
        .toList()) {
      _dirs[newPath + key.substring(path.length)] = _dirs.remove(key)!;
    }
    _dirs[newPath] = node;
    return _U14MemDirectory._(newPath, this);
  }

  static String _parentOf(String path) {
    final i = path.lastIndexOf(_sep);
    return i <= 0 ? path : path.substring(0, i);
  }

  static bool _isAbsolutePath(String path) =>
      path.startsWith('/') ||
      path.startsWith('\\') ||
      (path.length >= 2 && path.codeUnitAt(1) == 0x3A); // ':' 驱动器号
}

final class _U14FileNode {
  _U14FileNode(this.modified);

  Uint8List bytes = Uint8List(0);
  DateTime modified;
}

final class _U14DirNode {
  const _U14DirNode();
}

/// 内存文件实体：节点数据存在 [_U14MemFs] 的 map 里，实体只是路径句柄。
final class _U14MemFile implements File {
  _U14MemFile._(this.path, this._fs);

  @override
  final String path;

  final _U14MemFs _fs;

  _U14FileNode get _node {
    final node = _fs._files[path];
    if (node == null) throw FileSystemException('文件不存在', path);
    return node;
  }

  // ── 存在 / 元数据 ──

  @override
  bool existsSync() => _fs._files.containsKey(path);

  @override
  Future<bool> exists() async => existsSync();

  @override
  int lengthSync() => _node.bytes.length;

  @override
  Future<int> length() async => lengthSync();

  @override
  DateTime lastModifiedSync() => _node.modified;

  @override
  Future<DateTime> lastModified() async => lastModifiedSync();

  @override
  DateTime lastAccessedSync() => _node.modified;

  @override
  Future<DateTime> lastAccessed() async => lastAccessedSync();

  /// 虚拟 mtime：忽略请求的时间值，由单调计数器分配（调用顺序即时间序）。
  @override
  Future setLastModified(DateTime time) async {
    _node.modified = _fs._nextMtime();
  }

  @override
  void setLastModifiedSync(DateTime time) {
    _node.modified = _fs._nextMtime();
  }

  @override
  Future setLastAccessed(DateTime time) async {}

  @override
  void setLastAccessedSync(DateTime time) {}

  // ── 读 ──

  @override
  Uint8List readAsBytesSync() => Uint8List.fromList(_node.bytes);

  @override
  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(_node.bytes);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) {
    final lines = readAsStringSync(encoding: encoding).split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      readAsLinesSync(encoding: encoding);

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    final bytes = _node.bytes;
    return Stream.value(bytes.sublist(start ?? 0, end ?? bytes.length));
  }

  // ── 写 ──

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) =>
      _fs._writeBytes(path, bytes, mode);

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    writeAsBytesSync(bytes, mode: mode);
    return this;
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      writeAsBytesSync(encoding.encode(contents), mode: mode);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writeAsStringSync(contents, mode: mode, encoding: encoding);
    return this;
  }

  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) {
    // 与真实 openWrite 语义一致：write 模式打开即截断，append 保留内容；
    // 两种模式都保证文件节点立即存在（列表立即可见，消除实体化竞态）。
    if (identical(mode, FileMode.write) ||
        identical(mode, FileMode.writeOnly)) {
      _fs._truncate(path);
    } else {
      _fs._fileNode(path);
    }
    return _U14MemIOSink._(_fs, path);
  }

  // ── 结构操作 ──

  @override
  void createSync({bool recursive = false, bool exclusive = false}) {
    if (exclusive && _fs._files.containsKey(path)) {
      throw FileSystemException('文件已存在', path);
    }
    _fs._fileNode(path);
  }

  @override
  Future<File> create({
    bool recursive = false,
    bool exclusive = false,
  }) async {
    createSync(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  void deleteSync({bool recursive = false}) {
    if (_fs._files.remove(path) == null) {
      throw FileSystemException('文件不存在', path);
    }
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  @override
  File renameSync(String newPath) {
    final node = _fs._files.remove(path);
    if (node == null) throw FileSystemException('文件不存在', path);
    _fs._files[newPath] = node;
    return _U14MemFile._(newPath, _fs);
  }

  @override
  Future<File> rename(String newPath) async => renameSync(newPath);

  @override
  File copySync(String newPath) {
    final node = _node;
    _fs._files[newPath] = _U14FileNode(node.modified)
      ..bytes = Uint8List.fromList(node.bytes);
    return _U14MemFile._(newPath, _fs);
  }

  @override
  Future<File> copy(String newPath) async => copySync(newPath);

  // ── FileSystemEntity 成员 ──

  @override
  bool get isAbsolute => _U14MemFs._isAbsolutePath(path);

  @override
  File get absolute => this;

  @override
  Uri get uri => Uri.file(path);

  @override
  Directory get parent => _U14MemDirectory._(_U14MemFs._parentOf(path), _fs);

  @override
  Future<String> resolveSymbolicLinks() async => path;

  @override
  String resolveSymbolicLinksSync() => path;

  @override
  Future<FileStat> stat() => FileStat.stat(path);

  @override
  FileStat statSync() => FileStat.statSync(path);

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) =>
      throw UnsupportedError('U14 内存文件系统不支持 watch()');

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      throw UnsupportedError('U14 内存文件系统不支持 open()');

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      throw UnsupportedError('U14 内存文件系统不支持 openSync()');
}

/// 内存目录实体。
final class _U14MemDirectory implements Directory {
  _U14MemDirectory._(this.path, this._fs);

  @override
  final String path;

  final _U14MemFs _fs;

  // ── 目录操作 ──

  @override
  void createSync({bool recursive = false}) =>
      _fs._ensureDir(path, recursive: recursive);

  @override
  Future<Directory> create({bool recursive = false}) async {
    createSync(recursive: recursive);
    return this;
  }

  @override
  Directory createTempSync([String? prefix]) =>
      _fs._createTempSync(path, prefix);

  @override
  Future<Directory> createTemp([String? prefix]) async => createTempSync(prefix);

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      _fs._listDir(path, recursive: recursive);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      Stream.fromIterable(_fs._listDir(path, recursive: recursive));

  @override
  void deleteSync({bool recursive = false}) =>
      _fs._deleteDir(path, recursive: recursive);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  @override
  Directory renameSync(String newPath) => _fs._renameDir(path, newPath);

  @override
  Future<Directory> rename(String newPath) async => renameSync(newPath);

  // ── 存在 / 元数据 ──

  @override
  bool existsSync() => _fs._dirs.containsKey(path);

  @override
  Future<bool> exists() async => existsSync();

  // ── FileSystemEntity 成员 ──

  @override
  bool get isAbsolute => _U14MemFs._isAbsolutePath(path);

  @override
  Directory get absolute => this;

  @override
  Uri get uri => Uri.file(path);

  @override
  Directory get parent => _U14MemDirectory._(_U14MemFs._parentOf(path), _fs);

  @override
  Future<String> resolveSymbolicLinks() async => path;

  @override
  String resolveSymbolicLinksSync() => path;

  @override
  Future<FileStat> stat() => FileStat.stat(path);

  @override
  FileStat statSync() => FileStat.statSync(path);

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) =>
      throw UnsupportedError('U14 内存文件系统不支持 watch()');
}

/// 内存 IOSink：writeln 即写入内存节点（无缓冲延迟），flush 为空操作，
/// close 后写入静默忽略（比真实 StateError 更保守，避免任何时序把通道
/// 误判为磁盘故障停写）。
final class _U14MemIOSink implements IOSink {
  _U14MemIOSink._(this._fs, this._path);

  final _U14MemFs _fs;
  final String _path;
  Encoding _encoding = utf8;
  bool _closed = false;
  final Completer<void> _done = Completer<void>();

  @override
  Encoding get encoding => _encoding;

  @override
  set encoding(Encoding value) => _encoding = value;

  void _append(List<int> bytes) {
    if (_closed) return;
    _fs._appendBytes(_path, bytes);
  }

  @override
  void write(Object? object) => _append(_encoding.encode('$object'));

  @override
  void writeln([Object? object = ""]) {
    _append(_encoding.encode('$object'));
    _append(_encoding.encode('\n'));
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    var first = true;
    for (final object in objects) {
      if (!first && separator.isNotEmpty) write(separator);
      write(object);
      first = false;
    }
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void add(List<int> data) => _append(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future flush() async {}

  @override
  Future close() {
    if (!_closed) {
      _closed = true;
      _done.complete();
    }
    return _done.future;
  }

  @override
  Future get done => _done.future;
}
