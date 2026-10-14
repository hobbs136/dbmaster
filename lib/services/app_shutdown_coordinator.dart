import 'dart:async';

import 'package:dbmaster/utils/app_logger.dart';

/// 关窗清理序列的结果（供调用方日志与测试断言）。
enum ShutdownOutcome {
  /// 三步清理全部正常完成。
  normal,

  /// 至少一个清理步骤抛出异常（已就地隔离，不影响窗口放行）。
  stepFailed,

  /// 清理整体超出 deadline，超时放弃等待剩余步骤后强制放行。
  timedOut,
}

/// 关窗链路总超时协调器（sleep-resume 修复批 D1）。
///
/// 背景：关窗清理步骤（embedded stop / clean-exit 标记 / logger dispose）
/// 任何一个永挂（如 Windows 上子进程陷入不可中断内核 I/O、`stop()` 永不
/// 返回），都会让 `setPreventClose(false)` 永不执行 → 窗口永久关不掉，且
/// 调用方的 `_closing` 旗标会吞掉用户的一切重试。本协调器把清理整体套上
/// 总 deadline，并保证放行步骤在**任何**路径（步骤异常 / 步骤永挂 / 超时）
/// 下都执行——死锁形态从结构上消除。
///
/// 默认 12s 取值依据：`stop()` 正常最坏预算 ≈ 8s（stdin.close 2s + 优雅
/// 退出 grace 3s + kill 后等待 3s）+ `prepareForCleanExit` 既有 3s 原子写
/// 上限 + logger dispose ≈ 11s，留余量。覆盖正常慢路径，只切异常挂死；
/// 正常典型路径 <1s，用户无感。超时后的失败语义是良性的：clean-exit 标记
/// 被切 → 下次启动走崩溃恢复会话（U16 设计内）；logger 未 dispose → 进程
/// 退出由 OS 回收句柄。
///
/// 纯逻辑服务：禁 import material/widgets——这是「单元测试禁 import
/// main.dart」（组件指南 §0 MUST NOT #7）得以成立的结构性前提。
class AppShutdownCoordinator {
  const AppShutdownCoordinator();

  /// 日志键，保持与 main.dart 关窗链路既有口径一致。
  static const String _logTag = 'WindowCloseGuard';

  /// 执行关窗清理序列并无条件放行窗口。
  ///
  /// [stopEmbeddedServer] → [prepareCleanExit] → [disposeLogger] 三步依次
  /// 执行，各自 try/catch 隔离（一步失败不影响后续步骤），整体套 [deadline]；
  /// 超时即放弃等待剩余步骤（被放弃的步骤在后台继续跑，无法被 Dart 取消，
  /// 由进程退出兜底）。最后**无条件**执行 [releaseWindowClose]——它自身
  /// try/catch 隔离且**不进 deadline**（D1 不变量④：放行本身永不被罩）。
  ///
  /// 调用方须保证 [releaseWindowClose] 内部先释放窗口关闭门控（如
  /// `setPreventClose(false)`）、后真正 `close()`，两者顺序是放行不变量的
  /// 前半段，由调用侧闭包固化。
  ///
  /// 结果优先级：[ShutdownOutcome.timedOut] > [ShutdownOutcome.stepFailed] >
  /// [ShutdownOutcome.normal]（超时是最严重的结构信号，覆盖早先的步骤失败）。
  Future<ShutdownOutcome> run({
    required Future<void> Function() stopEmbeddedServer,
    required Future<void> Function() prepareCleanExit,
    required Future<void> Function() disposeLogger,
    required Future<void> Function() releaseWindowClose,
    Duration deadline = const Duration(seconds: 12),
  }) async {
    var outcome = ShutdownOutcome.normal;
    try {
      await _runTeardown(
        stopEmbeddedServer: stopEmbeddedServer,
        prepareCleanExit: prepareCleanExit,
        disposeLogger: disposeLogger,
        onStepFailed: () {
          if (outcome == ShutdownOutcome.normal) {
            outcome = ShutdownOutcome.stepFailed;
          }
        },
      ).timeout(deadline);
    } on TimeoutException {
      outcome = ShutdownOutcome.timedOut;
      // 尽力而为打点：若挂在 dispose 步骤，logger 可能已半关。
      try {
        AppLogger.e(
          _logTag,
          'close teardown timed out after ${deadline.inSeconds}s, '
          'forcing window release',
        );
      } catch (_) {}
    }
    // D1 不变量：release 任何路径必达，且不被 deadline 罩。
    try {
      await releaseWindowClose();
    } catch (e, st) {
      try {
        AppLogger.e(_logTag, 'window release failed', e, st);
      } catch (_) {}
    }
    return outcome;
  }

  Future<void> _runTeardown({
    required Future<void> Function() stopEmbeddedServer,
    required Future<void> Function() prepareCleanExit,
    required Future<void> Function() disposeLogger,
    required void Function() onStepFailed,
  }) async {
    await _runStep('embedded server stop failed', stopEmbeddedServer,
        onStepFailed);
    await _runStep('clean-exit mark failed', prepareCleanExit, onStepFailed);
    await _runStep('logger dispose failed', disposeLogger, onStepFailed);
  }

  /// 单步隔离执行：异常就地吞掉并打点（保持 `'WindowCloseGuard'` 日志键），
  /// 不让任何一步的失败中断序列。
  Future<void> _runStep(
    String failureMessage,
    Future<void> Function() step,
    void Function() onStepFailed,
  ) async {
    try {
      await step();
    } catch (e, st) {
      onStepFailed();
      try {
        AppLogger.e(_logTag, failureMessage, e, st);
      } catch (_) {}
    }
  }
}
