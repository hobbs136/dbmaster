// DatabaseService.connect 失败管道测试（连接失败 UX 重构 T3）。
//
// 覆盖：真实 SQLite adapter + 坏路径 → typed failure 透传；
// 防御分支（stub adapter return false）→ unknown 兜底；
// 非 typed 异常 → 包装 unknown 且 cause 保留异常链。
// 「不 mock 数据库服务」纪律下：真实 SQLite 走真实文件路径；纯错误路径
// （防御分支）按任务书允许注入 stub adapter。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/database_abstract.dart';

/// connect 恒 return false 的 stub（模拟未迁移到 typed 异常契约的网关族
/// adapter，T9 范围；其余成员经 noSuchMethod 委托）。
class _FalseConnectAdapter implements DatabaseAdapter {
  @override
  Future<bool> connect(DatabaseConnection connection) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// connect 抛裸异常（非 AdapterConnectException）的 stub。
class _ThrowingConnectAdapter implements DatabaseAdapter {
  @override
  Future<bool> connect(DatabaseConnection connection) async =>
      throw StateError('gw engine boom');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  group('DatabaseService.connect 失败管道（T3）', () {
    test(
      '真实 SQLite adapter + 父路径被文件占据 → AdapterConnectException(fileNotFound) 透传',
      () async {
        final service = DatabaseService();
        final blocker = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_svc_blocker_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        await blocker.writeAsString('a plain file blocking the parent path');
        addTearDown(() async {
          if (await blocker.exists()) await blocker.delete();
        });
        final server = _sqliteServer(
          't3_svc_1',
          '${blocker.path}${Platform.pathSeparator}x.db',
        );

        await expectLater(
          service.connect(server),
          throwsA(
            isA<AdapterConnectException>()
                .having(
                  (e) => e.failure.kind,
                  'kind',
                  ConnectionFailureKind.fileNotFound,
                )
                .having((e) => e.failure.errorCode, 'errorCode', '14'),
          ),
        );
        // 失败后状态清理干净：无残留连接、无在途标记。
        expect(service.hasConnection(server.id), isFalse);
        expect(service.isConnecting(server.id), isFalse);
      },
    );

    test(
      '真实 SQLite adapter + 非法库文件 → AdapterConnectException(notADatabase) 透传',
      () async {
        final service = DatabaseService();
        final garbage = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_svc_garbage_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        await garbage.writeAsString('definitely not a database');
        addTearDown(() async {
          if (await garbage.exists()) await garbage.delete();
        });
        final server = _sqliteServer('t3_svc_2', garbage.path);

        await expectLater(
          service.connect(server),
          throwsA(
            isA<AdapterConnectException>().having(
              (e) => e.failure.kind,
              'kind',
              ConnectionFailureKind.notADatabase,
            ),
          ),
        );
      },
    );

    test(
      '防御分支：stub adapter return false → 兜底 AdapterConnectException(unknown)',
      () async {
        final service = DatabaseService()
          ..setAdapterFactoryForTest(
            DatabaseType.sqlite,
            _FalseConnectAdapter.new,
          );
        final server = _sqliteServer('t3_svc_3', 'stub_host_x');

        await expectLater(
          service.connect(server),
          throwsA(
            isA<AdapterConnectException>()
                .having(
                  (e) => e.failure.kind,
                  'kind',
                  ConnectionFailureKind.unknown,
                )
                .having((e) => e.failure.errorCode, 'errorCode', isEmpty)
                .having((e) => e.failure.target, 'target', 'stub_host_x:0')
                .having(
                  (e) => e.failure.rawMessage,
                  'rawMessage',
                  contains('数据库适配器连接失败'),
                ),
          ),
        );
      },
    );

    test('非 typed 异常（stub 抛 StateError）→ 包装 unknown 且 cause 保留链', () async {
      final service = DatabaseService()
        ..setAdapterFactoryForTest(
          DatabaseType.sqlite,
          _ThrowingConnectAdapter.new,
        );
      final server = _sqliteServer('t3_svc_4', 'stub_host_y');

      await expectLater(
        service.connect(server),
        throwsA(
          isA<AdapterConnectException>()
              .having(
                (e) => e.failure.kind,
                'kind',
                ConnectionFailureKind.unknown,
              )
              .having(
                (e) => e.failure.rawMessage,
                'rawMessage',
                contains('gw engine boom'),
              )
              .having((e) => e.failure.target, 'target', 'stub_host_y:0')
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
    });
  });
}
