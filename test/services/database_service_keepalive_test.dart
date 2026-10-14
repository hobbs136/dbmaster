// keepalive in-flight 单飞守卫测试(sleep-resume-fix T5;编号 SVC-KA-001..003)。
//
// 「不 mock 数据库服务」纪律下,守卫与失败计数/重连调度是纯客户端逻辑,
// 按任务书允许以注入 stub adapter 方式覆盖(守卫/超时类测试用注入桩 +
// fake_async,不依赖真库慢查询)。
import 'dart:async';

import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// keepalive ping 的单次行为。
enum _PingAction { hang, throwError, ok }

/// 跨 adapter 实例(重连会经工厂新建)共享的调用计数器。
class _Probe {
  int queryCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  final List<Completer<void>> hungQueries = [];

  /// 结算最早一个挂起的 executeQuery(守卫 finally 随之释放)。
  void completeOneHungQuery() => hungQueries.removeAt(0).complete();
}

/// executeQuery 行为按脚本编程的 stub adapter;connect 可配置成败。
/// 未显式实现的成员经 noSuchMethod 抛错作 tripwire(与 connect_failure
/// 测试同模式)。
class _ScriptedPingAdapter implements DatabaseAdapter {
  _ScriptedPingAdapter(
    this.probe, {
    this.connectSucceeds = true,
    List<_PingAction>? pingActions,
  }) : pingActions = pingActions ?? const [_PingAction.ok];

  final _Probe probe;
  final bool connectSucceeds;

  /// 按序消费;耗尽后重复最后一个动作。
  final List<_PingAction> pingActions;
  int _cursor = 0;

  void Function()? _onDisconnect;

  @override
  void Function()? get onDisconnect => _onDisconnect;
  @override
  set onDisconnect(void Function()? callback) => _onDisconnect = callback;

  @override
  bool get isConnected => true;

  // _keepAlivePing 失败路径会读取该标志(切库早退判定),必须显式提供 false。
  @override
  bool get isSwitchingDatabase => false;

  @override
  Future<bool> connect(DatabaseConnection connection) {
    probe.connectCalls++;
    return Future.value(connectSucceeds);
  }

  @override
  Future<void> disconnect() async {
    probe.disconnectCalls++;
  }

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) {
    probe.queryCalls++;
    final action = pingActions[
        _cursor < pingActions.length - 1 ? _cursor++ : pingActions.length - 1];
    switch (action) {
      case _PingAction.hang:
        final completer = Completer<void>();
        probe.hungQueries.add(completer);
        return completer.future.then((_) => QueryResult.empty());
      case _PingAction.throwError:
        throw StateError('keepalive ping boom');
      case _PingAction.ok:
        return Future.value(QueryResult.empty());
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DbServer _server(String id) => DbServer(
  id: id,
  name: id,
  type: DatabaseType.sqlite,
  host: '127.0.0.1',
  port: 0,
  username: null,
  password: null,
  database: null,
  useSSL: false,
  timeoutSeconds: 30,
  autoReconnect: true,
);

void main() {
  group('keepalive in-flight 单飞守卫(T5)', () {
    test('SVC-KA-001 守卫:挂起的 ping 期间连续 tick 只触发一次,结算后恢复', () {
      fakeAsync((async) {
        const id = 'ka1';
        final probe = _Probe();
        final service = DatabaseService();
        service.registerConnectedServerForTest(_server(id));
        service.registerConnectedAdapterForTest(
          id,
          _ScriptedPingAdapter(probe, pingActions: const [_PingAction.hang]),
        );
        service.startKeepAliveForTest(id, interval: const Duration(milliseconds: 10));

        // 100ms = 10 个 tick,但首 ping 挂起 → 守卫持有 → 只触发一次。
        async.elapse(const Duration(milliseconds: 100));
        expect(probe.queryCalls, 1,
            reason: 'ping 挂起期间,后续 tick 应被单飞守卫跳过');

        // 结算挂起的 ping → finally 释放守卫 → 下一 tick 恢复触发。
        probe.completeOneHungQuery();
        async.elapse(const Duration(milliseconds: 1));
        expect(probe.queryCalls, 1);

        async.elapse(const Duration(milliseconds: 20));
        expect(probe.queryCalls, 2, reason: 'ping 结算(守卫释放)后应恢复触发');
        probe.completeOneHungQuery();
        async.elapse(const Duration(milliseconds: 1));
      });
    });

    test('SVC-KA-002 finally 释放:ping 抛异常后守卫清除,后续 tick 不被永久吞', () {
      fakeAsync((async) {
        const id = 'ka2';
        final probe = _Probe();
        final service = DatabaseService();
        service.registerConnectedServerForTest(_server(id));
        service.registerConnectedAdapterForTest(
          id,
          _ScriptedPingAdapter(
            probe,
            pingActions: const [_PingAction.throwError, _PingAction.ok],
          ),
        );
        service.startKeepAliveForTest(id, interval: const Duration(milliseconds: 10));

        async.elapse(const Duration(milliseconds: 10));
        expect(probe.queryCalls, 1, reason: '第一次 ping 抛异常');

        async.elapse(const Duration(milliseconds: 10));
        expect(probe.queryCalls, 2,
            reason: '异常路径 finally 释放守卫,下一 tick 照常触发');

        async.elapse(const Duration(milliseconds: 10));
        expect(probe.queryCalls, 3);
        // 单次失败(<2)不触发重连/disconnect,连接仍在。
        expect(service.hasConnection(id), isTrue);
      });
    });

    group('SVC-KA-003 失败计数/重连/disconnect 语义回归', () {
      test('连续 2 次失败触发重连,成功后计数归零(不误耗尽)', () {
        fakeAsync((async) {
          const id = 'ka3';
          final probe = _Probe();
          final service = DatabaseService();
          service.registerConnectedServerForTest(_server(id));
          service.registerConnectedAdapterForTest(
            id,
            _ScriptedPingAdapter(probe,
                pingActions: const [_PingAction.throwError]),
          );
          service.setAdapterFactoryForTest(
            DatabaseType.sqlite,
            () => _ScriptedPingAdapter(
              probe,
              pingActions: const [_PingAction.throwError],
            ),
          );
          final events = <ConnectionEvent>[];
          final sub = service.events.listen(events.add);

          service.startKeepAliveForTest(id, interval: const Duration(milliseconds: 10));

          // 首轮 2 个失败 tick(10/20ms)→ 退避 1s → 第 1 次重连成功。
          async.elapse(const Duration(milliseconds: 25));
          // 重连成功后 connect() 以默认 10s 间隔重启 keepalive;每轮
          // 「2 失败 + 1s 退避」≈21s。累计 50s 覆盖 3 轮、不足第 4 轮。
          async.elapse(const Duration(seconds: 50));

          expect(probe.connectCalls, 3,
              reason: '连续 2 次失败 → 重连;成功后计数归零,重复失败循环不误耗尽');
          expect(events.whereType<ConnectionEstablished>().length, 3);
          expect(service.hasConnection(id), isTrue);
          sub.cancel();
        });
      });

      test('重连 5 次耗尽后 disconnect(连接移除、不再重连)', () {
        fakeAsync((async) {
          const id = 'ka4';
          final probe = _Probe();
          final service = DatabaseService();
          service.setAdapterFactoryForTest(
            DatabaseType.sqlite,
            () => _ScriptedPingAdapter(
              probe,
              connectSucceeds: false,
              pingActions: const [_PingAction.throwError],
            ),
          );
          final events = <ConnectionEvent>[];
          final sub = service.events.listen(events.add);

          // connect 恒失败时,失败的那次 connect 会移除 server 条目并停掉
          // timer;每次重挂 server+adapter 模拟用户侧重建,attempts 计数
          // 跨周期保留(_stopKeepAlive 不清 reconnectAttempts)→ 累积到 5。
          for (var cycle = 1; cycle <= 5; cycle++) {
            service.registerConnectedServerForTest(_server(id));
            service.registerConnectedAdapterForTest(
              id,
              _ScriptedPingAdapter(probe,
                  pingActions: const [_PingAction.throwError]),
            );
            service.startKeepAliveForTest(
              id,
              interval: const Duration(milliseconds: 10),
            );
            // 2 个失败 tick + 本轮退避(1/2/4/8/16s)内的 disconnect+connect。
            async.elapse(const Duration(milliseconds: 25));
            async.elapse(const Duration(seconds: 17));
          }
          // 第 6 轮:attempts 已达上限 → 耗尽分支(计数归零 + disconnect)。
          service.registerConnectedServerForTest(_server(id));
          service.registerConnectedAdapterForTest(
            id,
            _ScriptedPingAdapter(
              probe,
              pingActions: const [_PingAction.throwError],
            ),
          );
          service.startKeepAliveForTest(id, interval: const Duration(milliseconds: 10));
          async.elapse(const Duration(milliseconds: 25));
          async.elapse(const Duration(seconds: 17));

          expect(probe.connectCalls, 5, reason: '5 次重连尝试后进入耗尽分支,不再 connect');
          expect(events.whereType<ConnectionDisconnected>().length, 6,
              reason: '前 5 轮各 1 次 disconnect 事件 + 耗尽分支 1 次');
          expect(service.hasConnection(id), isFalse,
              reason: '耗尽分支断开并移除连接');
          expect(probe.disconnectCalls, 6);
          sub.cancel();
        });
      });
    });
  });
}
