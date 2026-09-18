import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/utils/app_logger.dart';
import 'package:dbmaster/utils/secret_redactor.dart';
import 'package:flutter/services.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/error_event.dart';
import 'package:dbmaster/services/error_reporter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace stackTrace)? errorBuilder;

  const ErrorBoundary({super.key, required this.child, this.errorBuilder});

  /// 判断错误是否为瞬态、可恢复的连接错误（keepAlive/重连会自动恢复）。
  /// 这类错误不应触发全屏错误屏——只匹配明确的 mid-session 网络瞬断关键词，
  /// 避免误吞真实业务错误（permission denied / already exists / connect 失败等）。
  /// public static 便于单测。
  static bool isTransientConnectionError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('connection is closing down') ||
        msg.contains('closing down') ||
        msg.contains('broken pipe') ||
        msg.contains('connection reset');
  }

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _registerErrorHandler();
  }

  void _registerErrorHandler() {
    FlutterError.onError = (details) {
      // 让 Flutter 默认错误处理显示黄色错误框，同时记录日志
      FlutterError.presentError(details);
      // 只有非布局异常、且非瞬态可恢复连接错误才替换整个应用
      if (!_isLayoutError(details.exception) &&
          !ErrorBoundary.isTransientConnectionError(details.exception)) {
        _handleError(details.exception, details.stack ?? StackTrace.current);
      }
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      // 瞬态可恢复连接错误（如 postgres "Connection is closing down"，
      // 并发竞态导致连接瞬态关闭、keepAlive 会自动重连）不应把整个 app 替换成
      // 错误屏——只记日志并标记已处理，避免误崩。其它错误保持原行为（不吞）。
      if (ErrorBoundary.isTransientConnectionError(error)) {
        AppLogger.w('ErrorBoundary', '忽略瞬态可恢复连接错误（已由重连机制恢复）: $error');
        return true;
      }
      if (!_isLayoutError(error)) {
        _handleError(error, stackTrace);
      }
      return false;
    };
  }

  bool _isLayoutError(Object error) {
    // 布局/渲染错误不应该替换整个应用，让 Flutter 的黄色错误框处理
    return error is AssertionError ||
        error is ArgumentError ||
        error is StateError ||
        (error is FlutterError && error.toString().contains('RenderBox'));
  }

  void _handleError(Object error, StackTrace stackTrace) {
    // 先上报到执行中心（FR-004：未捕获异常也进历史），再决定是否替换全屏。
    ErrorReporter.instance.report(
      error,
      stackTrace: stackTrace,
      tag: 'ErrorBoundary',
    );
    if (_hasError) return;

    setState(() {
      _error = error;
      _stackTrace = stackTrace;
      _hasError = true;
    });
  }

  void _resetError() {
    setState(() {
      _hasError = false;
      _error = null;
      _stackTrace = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!, _stackTrace ?? StackTrace.current);
      }
      return _DefaultErrorWidget(
        error: _error!,
        stackTrace: _stackTrace ?? StackTrace.current,
        onReset: _resetError,
      );
    }

    return widget.child;
  }
}

class _DefaultErrorWidget extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;
  final VoidCallback onReset;

  const _DefaultErrorWidget({
    required this.error,
    required this.stackTrace,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    // 本组件接管的是 MaterialApp 之外的树（ErrorBoundary 包在 MaterialApp
    // 外层，见 main.dart），Localizations/Material 祖先不存在——Theme.of 有
    // fallback 不崩，但 AppLocalizations.of 返回 null。错误屏是全应用最后
    // 一道兜底，自身绝不能再抛（2026-08-22 灰屏卡死事故：l10n 空断言崩溃
    // → release 灰屏无响应）——一切依赖可空回退。
    final colors = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final titleText = l10n?.errorTitle ?? 'Something went wrong';
    final descLabelText = l10n?.errorDescriptionLabel ?? 'Description';
    final stackLabelText = l10n?.errorStackLabel ?? 'Stack Trace';
    final retryText = l10n?.errorRetry ?? 'Retry';
    final reportText = l10n?.errorReport ?? 'Report';

    // 崩溃页游离色全部收编主题令牌（F-04）
    final themeColors = context.themeColors;
    final bgColor = themeColors.bgPrimary;
    final textPrimary = colors.colorScheme.onSurface;
    final textSecondary = themeColors.textSecondary;
    final accentRed = themeColors.error;
    final accentBlue = themeColors.accentBlue;
    final borderColor = colors.colorScheme.outline;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: bgColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.circleAlert, size: 64, color: accentRed),
                const SizedBox(height: AppDesignSystem.space6),
                Text(
                  titleText,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space4),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeColors.bgSecondary,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusMd,
                    ),
                    border: Border.all(color: borderColor),
                  ),
                  constraints: const BoxConstraints(
                    maxWidth: 600,
                    maxHeight: 400,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          descLabelText,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.space2),
                        Text(
                          redactSecrets(error.toString()),
                          style: TextStyle(
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                            fontSize: 12,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.space4),
                        Text(
                          stackLabelText,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.space2),
                        Text(
                          stackTrace.toString(),
                          style: TextStyle(
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                            fontSize: 11,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onReset,
                      icon: const Icon(LucideIcons.refreshCw),
                      label: Text(retryText),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space4),
                    OutlinedButton.icon(
                      onPressed: () {
                        FlutterError.presentError(
                          FlutterErrorDetails(
                            exception: error,
                            stack: stackTrace,
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.bug),
                      label: Text(reportText),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppErrorHandler {
  /// 错误 SnackBar：上报到执行中心 + Copy（或 onRetry）action。
  /// Flutter SnackBar 仅支持单个 action——传了 [onRetry] 则显示 Retry，
  /// 否则显示 Copy；复制始终也可在执行中心 / 内联 ActionableError 完成。
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    String? tag,
    String? opContext,
    String? sql,
    String? connectionId,
    String? databaseName,
    VoidCallback? onRetry,
    ErrorSeverity severity = ErrorSeverity.error,
    Duration duration = const Duration(seconds: 5),
  }) {
    final event = ErrorReporter.instance.report(
      message,
      tag: tag,
      context: opContext,
      sql: sql,
      connectionId: connectionId,
      databaseName: databaseName,
      severity: severity,
    );
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.themeColors.error,
        duration: duration,
        // Flutter 3.41：带 action 的 SnackBar 默认 persist=true（不自动消失，需用户操作）。
        // 错误通知应到期自动消失，故显式 persist=false；Copy 仍可点击立即关闭。
        persist: false,
        action: onRetry != null
            ? SnackBarAction(label: l10n.retry, onPressed: onRetry)
            : SnackBarAction(
                label: l10n.errorCopy,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: event.messageForAi)),
              ),
      ),
    );
  }

  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.themeColors.success,
        duration: duration,
        persist: false, // 带 action 默认 persist=true 不自动消失（Flutter 3.41）
        action: action,
      ),
    );
  }

  static void showWarningSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.themeColors.warning,
        duration: duration,
        persist: false, // 带 action 默认 persist=true 不自动消失（Flutter 3.41）
        action: action,
      ),
    );
  }

  static void showInfoSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.themeColors.accentBlue,
        duration: duration,
        persist: false, // 带 action 默认 persist=true 不自动消失（Flutter 3.41）
        action: action,
      ),
    );
  }
}
