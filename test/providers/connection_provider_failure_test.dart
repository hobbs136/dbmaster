// ConnectionProvider 连接失败结构化状态测试（连接失败 UX 重构 T3 + T10）。
//
// T3 覆盖：connectToServer 失败 → lastConnectFailure 非 null 且 errorMessage
// 兼容面不破；失败后成功 → lastConnectFailure 清空；openSqliteFile 非法
// 扩展名 → unknown 兜底。走真实 DatabaseService + 真实 SQLite adapter
// （「不 mock 数据库服务」纪律；失败用垃圾文件构造，无需平台通道 mock）。
//
// T10 覆盖：每连接未处置失败 map（lastFailureFor / hasUnacknowledgedFailures
// / acknowledgeFailure / acknowledgeAllFailures）+ 意外断连（事件流注入）
// 记录、主动断开不产生失败条目。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/database_service.dart';

DbServer _sqliteServer(String id, String host) => DbServer(
  id: id,
  name: id,
  type: DatabaseType.sqlite,
  host: host,
  port: 0,
  username: null,
  password: null,
  database: null,
  useSSL: false,
  timeoutSeconds: 30,
  autoReconnect: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 防御：避免任何意外的持久化路径触碰真实插件通道。
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ConnectionProvider 连接失败结构化状态（T3）', () {
    test(
      'connectToServer 失败（SQLite 垃圾文件）→ lastConnectFailure 非 null + errorMessage 非空',
      () async {
        final provider = ConnectionProvider(dbService: DatabaseService());
        final garbage = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_prov_garbage_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        await garbage.writeAsString('not a database at all');
        addTearDown(() async {
          if (await garbage.exists()) await garbage.delete();
        });

        final result = await provider.connectToServer(
          _sqliteServer('t3_prov_1', garbage.path),
        );

        expect(result, isFalse);
        final failure = provider.lastConnectFailure;
        expect(failure, isNotNull);
        expect(failure!.kind, ConnectionFailureKind.notADatabase);
        expect(failure.errorCode, '26');
        expect(failure.target, garbage.path);
        // 兼容面不破：errorMessage getter 仍非空（app_provider 镜像 / AI 面板消费）。
        expect(provider.errorMessage, isNotNull);
        expect(provider.errorMessage, isNotEmpty);
        expect(provider.isConnecting, isFalse);
      },
    );

    test(
      'connectToServer 失败后成功 → lastConnectFailure 清空 + errorMessage 清空',
      () async {
        final provider = ConnectionProvider(dbService: DatabaseService());

        // 先失败：父路径被普通文件占据 → fileNotFound。
        final blocker = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_prov_blocker_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        await blocker.writeAsString('i block the parent path');
        addTearDown(() async {
          if (await blocker.exists()) await blocker.delete();
        });
        expect(
          await provider.connectToServer(
            _sqliteServer(
              't3_prov_2a',
              '${blocker.path}${Platform.pathSeparator}x.db',
            ),
          ),
          isFalse,
        );
        expect(
          provider.lastConnectFailure?.kind,
          ConnectionFailureKind.fileNotFound,
        );
        expect(provider.errorMessage, isNotEmpty);

        // 再成功：真实临时 SQLite 文件。
        final good = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_prov_ok_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        expect(
          await provider.connectToServer(
            _sqliteServer('t3_prov_2b', good.path),
          ),
          isTrue,
        );
        expect(provider.lastConnectFailure, isNull);
        expect(provider.errorMessage, isNull);
        // 连接建立后断开清理。
        await provider.disconnectConnection();
      },
    );

    test(
      'openSqliteFile 非法扩展名 → lastConnectFailure(unknown) + 返回 false',
      () async {
        final provider = ConnectionProvider(dbService: DatabaseService());

        final result = await provider.openSqliteFile('not_a_sqlite_file.txt');

        expect(result, isFalse);
        final failure = provider.lastConnectFailure;
        expect(failure, isNotNull);
        expect(failure!.kind, ConnectionFailureKind.unknown);
        expect(failure.rawMessage, contains('Not a supported SQLite file'));
        expect(provider.errorMessage, contains('Not a supported SQLite file'));
      },
    );
  });

  group('ConnectionProvider 未处置失败 map（T10）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('connect 失败 → lastFailureFor(id) 非 null + hasUnacknowledgedFailures', () async {
      final provider = ConnectionProvider(dbService: DatabaseService());
      final garbage = _tempDbFile('map_fail');
      addTearDown(() => _deleteQuietly(garbage));

      expect(
        await provider.connectToServer(_sqliteServer('t10_map_1', garbage.path)),
        isFalse,
      );
      expect(provider.lastFailureFor('t10_map_1'), isNotNull);
      expect(provider.hasUnacknowledgedFailures, isTrue);
      // 与 T3 单值 getter 同生共死。
      expect(provider.latestUnacknowledgedFailure, isNotNull);
    });

    test('acknowledgeFailure 处置清除（幂等）；acknowledgeAllFailures 清全部', () async {
      final provider = ConnectionProvider(dbService: DatabaseService());
      final garbage = _tempDbFile('ack');
      addTearDown(() => _deleteQuietly(garbage));

      await provider.connectToServer(_sqliteServer('t10_ack_1', garbage.path));
      await provider.connectToServer(_sqliteServer('t10_ack_2', garbage.path));

      provider.acknowledgeFailure('t10_ack_1');
      expect(provider.lastFailureFor('t10_ack_1'), isNull);
      expect(provider.lastFailureFor('t10_ack_2'), isNotNull);
      // 幂等：重复处置不抛、状态不变。
      provider.acknowledgeFailure('t10_ack_1');
      expect(provider.lastFailureFor('t10_ack_1'), isNull);
      expect(provider.hasUnacknowledgedFailures, isTrue);

      provider.acknowledgeAllFailures();
      expect(provider.lastFailureFor('t10_ack_2'), isNull);
      expect(provider.hasUnacknowledgedFailures, isFalse);
      expect(provider.latestUnacknowledgedFailure, isNull);
    });

    test('重试成功（同 id 换有效文件）→ 失败条目自动清除', () async {
      final provider = ConnectionProvider(dbService: DatabaseService());
      final garbage = _tempDbFile('retry');
      addTearDown(() => _deleteQuietly(garbage));

      await provider.connectToServer(_sqliteServer('t10_retry_1', garbage.path));
      expect(provider.lastFailureFor('t10_retry_1'), isNotNull);

      final good = _tempDbFile('retry_ok', content: '');
      expect(
        await provider.connectToServer(_sqliteServer('t10_retry_1', good.path)),
        isTrue,
      );
      expect(provider.lastFailureFor('t10_retry_1'), isNull);
      expect(provider.hasUnacknowledgedFailures, isFalse);
      await provider.disconnectConnection();
    });

    test('意外断连（事件流注入 ConnectionDisconnected）→ 记录失败条目', () async {
      final provider = ConnectionProvider(dbService: DatabaseService());
      final good = _tempDbFile('lost', content: '');
      final server = _sqliteServer('t10_lost_1', good.path);

      expect(await provider.connectToServer(server), isTrue);
      expect(provider.hasUnacknowledgedFailures, isFalse);

      // 模拟意外断连：无主动断开标记的 ConnectionDisconnected 事件。
      provider.dbService.addEventForTest(
        ConnectionDisconnected(server.id, server),
      );
      // 广播流异步派发，让出事件循环后断言。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final failure = provider.lastFailureFor('t10_lost_1');
      expect(failure, isNotNull);
      expect(failure!.kind, ConnectionFailureKind.unknown);
      expect(failure.rawMessage, contains('Connection lost'));
      expect(provider.hasUnacknowledgedFailures, isTrue);

      // 处置后恢复无失败态。
      provider.acknowledgeFailure('t10_lost_1');
      expect(provider.hasUnacknowledgedFailures, isFalse);
      await provider.disconnectConnection();
    });

    test('主动断开（disconnectConnection）→ 不产生失败条目', () async {
      final provider = ConnectionProvider(dbService: DatabaseService());
      final good = _tempDbFile('manual', content: '');
      final server = _sqliteServer('t10_manual_1', good.path);

      expect(await provider.connectToServer(server), isTrue);
      await provider.disconnectConnection(connectionId: server.id);
      // 事件派发后断言：主动断开不应被误判为意外断连。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(provider.lastFailureFor('t10_manual_1'), isNull);
      expect(provider.hasUnacknowledgedFailures, isFalse);
    });
  });
}

// 在系统临时目录写一个唯一命名的文件（同步 IO）。
// content 为垃圾字节 → NOTADB；空串 → 合法空 SQLite 库。
File _tempDbFile(String tag, {String content = 'not a database at all'}) {
  final file = File(
    '${Directory.systemTemp.absolute.path}'
    '${Platform.pathSeparator}dbmaster_t10_${tag}_'
    '${DateTime.now().millisecondsSinceEpoch}.db',
  );
  file.writeAsStringSync(content);
  return file;
}

// 临时文件清理尽力而为（连接未关时句柄占用删除失败不影响测试结论）。
void _deleteQuietly(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // ignore
  }
}
