import 'dart:io';

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
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app_logger_test');
    });

    tearDown(() async {
      await AppLogger.resetForTesting();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('init 后日志落到会话文件，行含时间戳/级别/tag', () async {
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
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ', multiLine: true)
            .hasMatch(content),
        isTrue,
      );
      // 会话头
      expect(content, contains('session start'));
    });

    test('e 的 error 与 stackTrace 追加进文件', () async {
      await AppLogger.init(tempDir);
      final file = AppLogger.currentLogFile!;
      AppLogger.e('Boom', 'failed', StateError('bad state'), StackTrace.current);
      await AppLogger.flush();
      final content = await file.readAsString();
      expect(content, contains('Bad state: bad state'));
    });

    test('落盘行脱敏：password= 明文不进文件', () async {
      await AppLogger.init(tempDir);
      final file = AppLogger.currentLogFile!;
      AppLogger.e('Conn', 'connect failed: password=hunter2 host=127.0.0.1');
      await AppLogger.flush();
      final content = await file.readAsString();
      expect(content, contains('***'));
      expect(content, isNot(contains('hunter2')));
    });

    test('external 透传外部进程行：tag 标记来源、不套级别前缀', () async {
      await AppLogger.init(tempDir);
      final file = AppLogger.currentLogFile!;
      const tracing = '2026-08-17T06:00:00.123Z INFO dbmaster_server: ready';
      AppLogger.external('Server', tracing);
      await AppLogger.flush();
      final content = await file.readAsString();
      expect(content, contains('[Server] $tracing'));
      expect(content, isNot(contains('[INFO] [Server]')));
    });

    test('单文件超限滚动到 _N 后缀新文件', () async {
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
            AppLogger.currentLogFile!.path.split(Platform.pathSeparator).last),
        isTrue,
        reason: '滚动后应在 _N 后缀文件上',
      );
      // 旧文件保留（滚动不删除）
      expect(await first.exists(), isTrue);
      // 新文件继续接收写入
      final rolled = await AppLogger.currentLogFile!.readAsString();
      expect(rolled, isNotEmpty);
    });

    test('滚动次数达上限后停写（currentLogFile → null），调用仍不抛', () async {
      await AppLogger.init(tempDir, maxFileBytes: 100, maxRollsPerSession: 1);
      for (var i = 0; i < 60; i++) {
        AppLogger.i('T', 'flood $i ${'y' * 30}');
      }
      expect(AppLogger.currentLogFile, isNull);
      AppLogger.i('T', 'after disabled');
      AppLogger.external('Server', 'after disabled');
    });

    test('启动清理只保留最新 N 个 .log', () async {
      // 造 12 个 mtime 错开的旧文件（old_0 最旧，old_11 最新）。
      for (var i = 0; i < 12; i++) {
        final f = File(
            '${tempDir.path}${Platform.pathSeparator}dbmaster_old_$i.log');
        await f.writeAsString('old $i');
        await f.setLastModified(DateTime.now().subtract(Duration(hours: 20 - i)));
      }
      await AppLogger.init(tempDir, maxKeepFiles: 5);
      final remaining = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
      expect(remaining.length, 5);
      String name(File f) =>
          f.path.split(Platform.pathSeparator).last;
      final names = remaining.map(name).toList();
      // 最旧的被清，最新的旧文件保留
      expect(names, isNot(contains('dbmaster_old_0.log')));
      expect(names, contains('dbmaster_old_11.log'));
      // 新会话文件占一个名额
      expect(names.where((n) => !n.startsWith('dbmaster_old_')).length, 1);
    });

    test('dispose 冲刷并关闭：之后退化，调用不抛，已写内容可读', () async {
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

    test('未 init：getters 为 null，所有入口调用不抛', () {
      expect(AppLogger.logsDirectory, isNull);
      expect(AppLogger.currentLogFile, isNull);
      AppLogger.d('T', 'x');
      AppLogger.i('T', 'x');
      AppLogger.w('T', 'x');
      AppLogger.e('T', 'x');
      AppLogger.external('Server', 'x');
    });
  });
}
