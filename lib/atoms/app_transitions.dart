// ============================================================================
// App Transitions - 统一页面过渡动画
// ============================================================================

import 'package:flutter/material.dart';
import '../theme/design_system.dart';

/// 页面过渡类型
enum AppTransitionType { fade, slideRight, slideUp, scale, fadeScale }

/// 自定义页面路由 - 带过渡动画
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final AppTransitionType transitionType;
  final Duration duration;
  @override
  final bool maintainState;

  AppPageRoute({
    required this.child,
    this.transitionType = AppTransitionType.fadeScale,
    this.duration = AppDesignSystem.durationNormal,
    this.maintainState = true,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) => child,
         transitionDuration: duration,
         reverseTransitionDuration: duration,
         maintainState: maintainState,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           return _buildTransition(
             animation,
             secondaryAnimation,
             child,
             transitionType,
           );
         },
       );

  static Widget _buildTransition(
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
    AppTransitionType type,
  ) {
    switch (type) {
      case AppTransitionType.fade:
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppDesignSystem.curveEnter,
          ),
          child: child,
        );
      case AppTransitionType.slideRight:
        return SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: AppDesignSystem.curveEnter,
                ),
              ),
          child: child,
        );
      case AppTransitionType.slideUp:
        return SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0.0, 1.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: AppDesignSystem.curveEnter,
                ),
              ),
          child: child,
        );
      case AppTransitionType.scale:
        return ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: AppDesignSystem.curveEnter,
            ),
          ),
          child: child,
        );
      case AppTransitionType.fadeScale:
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppDesignSystem.curveEnter,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: AppDesignSystem.curveEnter,
              ),
            ),
            child: child,
          ),
        );
    }
  }
}

/// 弹窗/对话框过渡动画
class AppDialogTransitions {
  /// 缩放+淡入弹窗
  static Widget scaleFade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.9,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  /// 从底部滑入（适合底部弹窗）
  static Widget slideUp(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

/// 统一的路由跳转扩展
extension AppNavigationExtension on BuildContext {
  /// 带动画推入新页面
  Future<T?> pushWithTransition<T>(
    Widget page, {
    AppTransitionType type = AppTransitionType.fadeScale,
    Duration? duration,
  }) {
    return Navigator.push<T>(
      this,
      AppPageRoute<T>(
        child: page,
        transitionType: type,
        duration: duration ?? AppDesignSystem.durationNormal,
      ),
    );
  }

  /// 带动画替换当前页面
  Future<T?> pushReplacementWithTransition<T>(
    Widget page, {
    AppTransitionType type = AppTransitionType.fadeScale,
    Duration? duration,
  }) {
    return Navigator.pushReplacement<T, dynamic>(
      this,
      AppPageRoute<T>(
        child: page,
        transitionType: type,
        duration: duration ?? AppDesignSystem.durationNormal,
      ),
    );
  }
}

/// 统一弹窗显示扩展
extension AppDialogExtension on BuildContext {
  /// 显示带动画的对话框
  Future<T?> showAnimatedDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
    Duration transitionDuration = AppDesignSystem.durationNormal,
  }) {
    return showGeneralDialog<T>(
      context: this,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(this).modalBarrierDismissLabel,
      barrierColor: barrierColor ?? Colors.black54,
      transitionDuration: transitionDuration,
      transitionBuilder: AppDialogTransitions.scaleFade,
    );
  }
}
