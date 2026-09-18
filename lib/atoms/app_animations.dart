import 'package:flutter/material.dart';
import '../../theme/design_system.dart';

/// ============================================================================
/// AppAnimations - 动画配置
/// ============================================================================
class AppAnimations {
  /// 快速动画（150ms）- 用于小组件和微交互
  static const Duration fast = Duration(milliseconds: 150);

  /// 正常动画（300ms）- 用于中等组件和标准交互
  static const Duration normal = Duration(milliseconds: 300);

  /// 慢速动画（500ms）- 用于大组件和页面切换
  static const Duration slow = Duration(milliseconds: 500);

  /// 非常慢速动画（800ms）- 用于模态框和复杂动画
  static const Duration extraSlow = Duration(milliseconds: 800);

  /// 标准曲线（缓入缓出）
  static const Curve defaultCurve = Curves.easeInOut;

  /// 进入曲线（快入慢出）
  static const Curve enterCurve = Curves.easeOut;

  /// 离开曲线（快出慢入）
  static const Curve exitCurve = Curves.easeIn;

  /// 弹性曲线
  static const Curve elasticCurve = Curves.elasticOut;
}

/// ============================================================================
/// AnimatedContainer - 带淡入动画的容器
/// ============================================================================
class AnimatedContainer extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onComplete;
  final bool isVisible;

  const AnimatedContainer({
    super.key,
    required this.child,
    this.duration = AppAnimations.normal,
    this.curve = AppAnimations.defaultCurve,
    this.onComplete,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: duration,
      curve: curve,
      onEnd: onComplete,
      child: child,
    );
  }
}

/// ============================================================================
/// SlideInContainer - 带滑入动画的容器
/// ============================================================================
class SlideInContainer extends StatelessWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;
  final Curve curve;
  final bool isVisible;
  final double slideOffset;

  const SlideInContainer({
    super.key,
    required this.child,
    this.direction = SlideDirection.fromBottom,
    this.duration = AppAnimations.normal,
    this.curve = AppAnimations.defaultCurve,
    this.isVisible = true,
    this.slideOffset = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: Offset(
        direction == SlideDirection.fromLeft
            ? -slideOffset
            : direction == SlideDirection.fromRight
            ? slideOffset
            : 0.0,
        direction == SlideDirection.fromTop
            ? -slideOffset
            : direction == SlideDirection.fromBottom
            ? slideOffset
            : 0.0,
      ),
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}

enum SlideDirection { fromTop, fromBottom, fromLeft, fromRight }

/// ============================================================================
/// ScaleContainer - 带缩放动画的容器
/// ============================================================================
class ScaleContainer extends StatefulWidget {
  final Widget child;
  final double beginScale;
  final double endScale;
  final Duration duration;
  final Curve curve;
  final bool isScaled;

  const ScaleContainer({
    super.key,
    required this.child,
    this.beginScale = 0.9,
    this.endScale = 1.0,
    this.duration = AppAnimations.normal,
    this.curve = AppAnimations.defaultCurve,
    this.isScaled = true,
  });

  @override
  State<ScaleContainer> createState() => _ScaleContainerState();
}

class _ScaleContainerState extends State<ScaleContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = Tween<double>(
      begin: widget.beginScale,
      end: widget.endScale,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    if (widget.isScaled) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(ScaleContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScaled && !oldWidget.isScaled) {
      _controller.forward();
    } else if (!widget.isScaled && oldWidget.isScaled) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}

/// ============================================================================
/// LoadingShimmer - 加载时的微光动画
/// ============================================================================
class LoadingShimmer extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  const LoadingShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBaseColor = widget.baseColor ?? AppDesignSystem.bgTertiary;

    return Container(
      decoration: BoxDecoration(
        color: effectiveBaseColor.withValues(alpha: _animation.value),
      ),
      child: widget.child,
    );
  }
}

/// ============================================================================
/// PulseWidget - 脉冲效果组件
/// ============================================================================
class PulseWidget extends StatefulWidget {
  final Widget child;
  final double scaleBegin;
  final double scaleEnd;
  final Duration duration;

  const PulseWidget({
    super.key,
    required this.child,
    this.scaleBegin = 1.0,
    this.scaleEnd = 1.05,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<PulseWidget> createState() => _PulseWidgetState();
}

class _PulseWidgetState extends State<PulseWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation =
        Tween<double>(begin: widget.scaleBegin, end: widget.scaleEnd).animate(
          CurvedAnimation(
            parent: _controller,
            curve: AppAnimations.elasticCurve,
          ),
        );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(scale: _scaleAnimation.value, child: widget.child);
  }
}

/// ============================================================================
/// StaggeredFadeIn - 交错淡入动画
/// ============================================================================
class StaggeredFadeIn extends StatelessWidget {
  final List<Widget> children;
  final Duration duration;
  final Duration staggerDelay;
  final Curve curve;

  const StaggeredFadeIn({
    super.key,
    required this.children,
    this.duration = AppAnimations.normal,
    this.staggerDelay = const Duration(milliseconds: 100),
    this.curve = AppAnimations.enterCurve,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children.asMap().entries.map((entry) {
        final child = entry.value;

        return AnimatedOpacity(
          opacity: 1.0,
          duration: duration,
          curve: curve,
          child: child,
        );
      }).toList(),
    );
  }
}
