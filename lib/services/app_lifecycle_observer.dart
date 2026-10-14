import 'dart:async';

import 'package:dbmaster/utils/app_logger.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

/// 应用生命周期打点与唤醒探活协调器(sleep-resume 修复批 D6/T8)。
///
/// 背景:全仓此前零 `WidgetsBindingObserver`(诊断报告 §2.6),睡眠唤醒后
/// 没有任何运行时证据可判定 isolate/UI 管线死活(黑屏根因候选 1 的取证
/// 缺口),且 embedded 子进程死掉后要等最多 30s 心跳 tick 才被发现。本类补
/// 两件仪器:
/// ① 每个 lifecycle 转换打一条 AppLogger(取证时间线:睡眠起点/唤醒起点
///    可见;判据——唤醒后日志静默 = isolate 死,持续滚动 = isolate 活);
/// ② `resumed` 时对 server 触发一次探活([_probe],生产接
///    `ServerConnection().probeNow`,复用 T4 既有失败处理链——embedded
///    子进程死 → 立即转重启调度),把死活判定从「等 30s 心跳 tick」提前到
///    唤醒瞬间。
///
/// D7 裁决(不纳入本批,勿在此扩展):唤醒后主动清理挂死请求 / 强制重连
/// ——超时 + 单飞守卫(批内 T3-T6)已提供有界自愈,主动取消有误杀慢查询
/// 风险且会与 keepalive 既有重连机制竞争,等本类打点数据再凭证据立项
/// (任务书 §5.2)。
///
/// 结构说明:本类自身实现 [WidgetsBindingObserver] 并暴露 [attach] /
/// [detach],main.dart 的私有挂载 widget 只在 initState/dispose 调这两个
/// 方法——注册/注销逻辑因此可以在不 import main.dart 的单测中断言
/// (§0 MUST NOT #7;「dispose 正确移除 observer」防泄漏断言由
/// `test/services/app_lifecycle_observer_test.dart` 覆盖)。
///
/// 仅 import `package:flutter/widgets.dart`(show 限定的 binding 层符号,
/// 均非 material),保持纯逻辑可单测。probe 回调构造注入便于测试;[onLog]
/// 是可选测试日志缝——AppLogger 的 developer.log/文件通道在单测中不可
/// 断言,测试经该缝逐条镜像打点内容。
class AppLifecycleObserver with WidgetsBindingObserver {
  AppLifecycleObserver({
    required Future<bool> Function() probe,
    void Function(String message)? onLog,
  })  : _probe = probe,
        _onLog = onLog;

  static const String _logTag = 'AppLifecycle';

  /// 唤醒探活回调(生产 = `ServerConnection().probeNow`)。probeNow 自带
  /// T4 单飞守卫,inactive↔resumed 快速抖动导致的重复触发天然无害。
  final Future<bool> Function() _probe;

  /// 测试日志缝:每条 AppLogger 打点同时镜像一份给测试断言;生产为 null。
  final void Function(String message)? _onLog;

  /// 把本观察者注册进 WidgetsBinding(挂载 widget 的 initState 调用)。
  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// 注销观察者(挂载 widget 的 dispose 调用)。不注销会让本类永久驻留
  /// WidgetsBinding——防泄漏不变量。
  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  /// 生命周期转换统一入口:逐条打点;仅 [AppLifecycleState.resumed] 追加
  /// 一次探活。探活 fire-and-forget:挂起不阻塞本回调(方法同步返回),
  /// 异常就地吞掉不外溢。
  void handle(AppLifecycleState state) {
    _log('state → ${state.name}');
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // Future.sync:probe 同步抛错也进 failed future,统一走 onError。
    unawaited(Future<bool>.sync(_probe).then((bool ok) {
      _log('post-resume server probe: ${ok ? 'ok' : 'failed'}');
    }, onError: (Object error, StackTrace stackTrace) {
      // 探活异常吞掉(fire-and-forget 的错误必须就地处理,不外溢);
      // 失败处置链(重连/重启调度)由 probeNow 内部既有逻辑负责,此处
      // 只补取证。挂死 probe 永不结算也安全——没有这里等待任何东西。
      AppLogger.e(_logTag, 'post-resume server probe threw', error, stackTrace);
      _onLog?.call('post-resume server probe threw: $error');
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handle(state);
  }

  void _log(String message) {
    AppLogger.i(_logTag, message);
    _onLog?.call(message);
  }
}
