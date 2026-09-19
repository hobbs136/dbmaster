import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../theme/app_colors.dart';

enum ToastType { success, error, warning, info }

class ToastService {
  static final List<OverlayEntry> _overlays = [];
  static const Duration _defaultDuration = Duration(seconds: 3);

  /// 连接失败 UX 重构 T10：error 类 toast 需持久可见，默认时长 3s → 8s
  /// （仅 error；success/warning/info 保持 3s）。显式传 duration 仍可覆盖。
  static const Duration _defaultErrorDuration = Duration(seconds: 8);

  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration? duration,
    Widget? action,
  }) {
    final effectiveDuration = duration ??
        (type == ToastType.error ? _defaultErrorDuration : _defaultDuration);
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: type,
        duration: effectiveDuration,
        action: action,
        onDismiss: () => _removeOverlay(entry),
      ),
    );

    _overlays.add(entry);
    overlay.insert(entry);
  }

  static void _removeOverlay(OverlayEntry entry) {
    entry.remove();
    _overlays.remove(entry);
  }

  static void dismissAll() {
    for (var overlay in _overlays) {
      overlay.remove();
    }
    _overlays.clear();
  }

  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    show(
      context,
      message: message,
      type: ToastType.success,
      duration: duration,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    show(
      context,
      message: message,
      type: ToastType.error,
      duration: duration,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    show(
      context,
      message: message,
      type: ToastType.warning,
      duration: duration,
    );
  }

  static void info(BuildContext context, String message, {Duration? duration}) {
    show(
      context,
      message: message,
      type: ToastType.info,
      duration: duration,
    );
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final Widget? action;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    this.action,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (mounted) {
      _controller.reverse().then((_) {
        widget.onDismiss();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.type) {
      case ToastType.success:
        return context.themeColors.success;
      case ToastType.error:
        return context.themeColors.error;
      case ToastType.warning:
        return context.themeColors.warning;
      case ToastType.info:
        return context.themeColors.accentBlue;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case ToastType.success:
        return LucideIcons.circleCheckBig;
      case ToastType.error:
        return LucideIcons.circleAlert;
      case ToastType.warning:
        return LucideIcons.triangleAlert;
      case ToastType.info:
        return LucideIcons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: AppDesignSystem.space10,
      right: AppDesignSystem.space4,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
                border: Border.all(color: _color.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IntrinsicWidth(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 4,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppDesignSystem.radiusMd),
                          bottomLeft: Radius.circular(AppDesignSystem.radiusMd),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space3,
                        vertical: AppDesignSystem.space3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icon, color: _color, size: 20),
                          SizedBox(width: AppDesignSystem.space3),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.themeColors.textPrimary,
                              ),
                            ),
                          ),
                          if (widget.action != null) ...[
                            SizedBox(width: AppDesignSystem.space3),
                            widget.action!,
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        LucideIcons.x,
                        size: 16,
                        color: context.themeColors.textMuted,
                      ),
                      onPressed: _dismiss,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
