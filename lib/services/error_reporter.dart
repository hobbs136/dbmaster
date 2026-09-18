import '../models/error_event.dart';
import '../providers/execution_center_provider.dart';
import '../utils/app_logger.dart';

/// 错误上报总线——捕获 + 日志 + 推入执行中心。
///
/// 纯 Dart 单例（不 import flutter/material），可从非 UI / 后台路径调用。
/// `ErrorBoundary` 已持有 `FlutterError.onError` / `PlatformDispatcher.onError`
/// 全局 hook；本类**不**重复挂接，由 `ErrorBoundary`（及各 catch 点）委托调用。
class ErrorReporter {
  ErrorReporter._();
  static final ErrorReporter instance = ErrorReporter._();

  ExecutionCenterProvider? _center;

  /// 短窗口内同一异常对象去重，避免重复入中心。
  final Map<int, DateTime> _recent = {};
  static const Duration _dedupeWindow = Duration(seconds: 2);
  static const int _maxRecent = 64;

  int _counter = 0;

  // ── 防级联（导出后灰屏事故 2026-08-17）──
  // 实测 profile：report → center.addError → notifyListeners → 监听器抛错 →
  // FlutterError.onError/PlatformDispatcher.onError → _handleError → report
  // 的自反馈环在 UI 线程无限循环（每圈新异常实例，identityHashCode 去重
  // 拦不住；每圈全量格式化日志行造成巨量分配）。三道闸：
  // 1) notify 期间的重入直接丢弃；2) 每秒洪水上限兜底其它报错风暴；
  // 3) center.addError 的监听器异常就地吞掉，不逃逸到全局钩子。
  bool _notifying = false;
  int _cascadeSuppressed = 0;
  int _floodWindowStartMs = 0;
  int _floodCount = 0;
  bool _floodDropLogged = false;
  static const int _floodMaxPerSecond = 20;

  /// 由 `AppProvider` 在构造时挂接执行中心。
  void attach(ExecutionCenterProvider center) => _center = center;

  /// 由 `AppProvider.dispose` 解除挂接。
  void detach() {
    _center = null;
    _recent.clear();
    _notifying = false;
    _cascadeSuppressed = 0;
    _floodWindowStartMs = 0;
    _floodCount = 0;
    _floodDropLogged = false;
  }

  /// 捕获 + 日志 + 推入执行中心。返回事件供调用方就地渲染（如 `ActionableError`）。
  ErrorEvent report(
    Object error, {
    StackTrace? stackTrace,
    ErrorSeverity severity = ErrorSeverity.error,
    String? tag,
    String? context,
    String? sql,
    String? connectionId,
    String? databaseName,
    bool redactSql = false,
  }) {
    final event = ErrorEvent(
      id: _genId(),
      timestamp: DateTime.now(),
      severity: severity,
      message: error.toString(),
      tag: tag,
      context: context,
      sql: sql,
      connectionId: connectionId,
      databaseName: databaseName,
      redactSql: redactSql,
      stackTrace: stackTrace?.toString(),
    );
    // 闸 1：notify 反馈环内的重入——丢弃（只低频记一行计数日志）。
    if (_notifying) {
      _cascadeSuppressed++;
      if (_cascadeSuppressed == 1 || _cascadeSuppressed % 50 == 0) {
        AppLogger.w('ErrorReporter',
            'error cascade suppressed (×$_cascadeSuppressed)');
      }
      return event;
    }
    // 闸 2：每秒洪水上限——正常路径不可能秒级几十个错误，超过即风暴。
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _floodWindowStartMs >= 1000) {
      _floodWindowStartMs = nowMs;
      _floodCount = 0;
      _floodDropLogged = false;
    }
    if (++_floodCount > _floodMaxPerSecond) {
      if (!_floodDropLogged) {
        AppLogger.w('ErrorReporter',
            'error flood: >$_floodMaxPerSecond/s, dropping the rest this second');
        _floodDropLogged = true;
      }
      return event;
    }
    // 传入脱敏文本作为 error 参数——AppLogger.e 会把 $error 拼进日志行，
    // 若传原始 error 对象，其 toString() 的密钥会绕过 redactSecrets 泄露（FR-011）。
    AppLogger.e(tag ?? 'ErrorReporter', event.messageForLog, event.messageForLog, stackTrace);
    _pushIfNew(event, error);
    return event;
  }

  void _pushIfNew(ErrorEvent event, Object error) {
    final now = DateTime.now();
    // 先清理过期去重项（即便未挂接 center，也避免 _recent 无界增长）
    _recent.removeWhere((_, t) => now.difference(t) > _dedupeWindow);
    if (_recent.length > _maxRecent) _recent.clear();
    final center = _center;
    if (center == null) return;
    final key = identityHashCode(error);
    if (_recent.containsKey(key)) return;
    _recent[key] = now;
    // 闸 3：监听器异常就地吞掉 + 置重入旗标——逃逸到全局钩子就是自反馈环。
    _notifying = true;
    try {
      center.addError(event);
    } catch (e) {
      AppLogger.e('ErrorReporter', 'execution center listener failed: $e');
    } finally {
      _notifying = false;
    }
  }

  String _genId() {
    _counter += 1;
    return 'err_${DateTime.now().millisecondsSinceEpoch}_$_counter';
  }
}
