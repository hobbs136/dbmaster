import 'package:flutter/material.dart';
import '../../theme/design_system.dart';

/// ============================================================================
/// AppScrollbar - 优化的滚动条
/// ============================================================================
///
/// 特点：
/// - 自定义滚动条颜色
/// - 统一的圆角
/// - 可配置宽度
/// - 支持悬停效果
///
/// 用法：
/// ```dart
/// SingleChildScrollView(
///   scrollDirection: Axis.horizontal,
///   child: AppScrollbar(
///     child: // 你的内容
///   ),
/// )
/// ```
/// ============================================================================
class AppScrollbar extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  final Axis? scrollDirection;
  final double? thickness;
  final Color? backgroundColor;
  final Color? thumbColor;
  final double? radius;
  final bool isAlwaysShown;
  final EdgeInsets? padding;

  const AppScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.scrollDirection,
    this.thickness,
    this.backgroundColor,
    this.thumbColor,
    this.radius,
    this.isAlwaysShown = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveThickness = thickness ?? AppDesignSystem.scrollbarWidth;
    final effectiveRadius = radius ?? AppDesignSystem.radiusSm;

    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(effectiveThickness),
        radius: Radius.circular(effectiveRadius),
        thumbColor: WidgetStateProperty.all(
          thumbColor ?? Theme.of(context).colorScheme.surface,
        ),
        trackColor: WidgetStateProperty.all(
          backgroundColor ?? AppDesignSystem.bgTertiary,
        ),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        trackVisibility: WidgetStateProperty.all(true),
        thumbVisibility: WidgetStateProperty.all(isAlwaysShown ? true : false),
        minThumbLength: 48,
      ),
      child: child,
    );
  }
}

/// ============================================================================
/// ScrollableContainer - 带滚动条的容器
/// ============================================================================
///
/// 便捷组件，在容器上自动添加滚动条
/// ============================================================================
class ScrollableContainer extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  final Axis scrollDirection;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? thumbColor;

  const ScrollableContainer({
    super.key,
    required this.child,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.padding,
    this.backgroundColor,
    this.thumbColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: backgroundColor),
      child: AppScrollbar(
        controller: controller,
        scrollDirection: scrollDirection,
        thumbColor: thumbColor,
        child: child,
      ),
    );
  }
}

/// ============================================================================
/// HorizontalScrollableContainer - 水平滚动容器
/// ============================================================================
///
/// 专门用于水平滚动的容器
/// ============================================================================
class HorizontalScrollableContainer extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? thumbColor;
  final double? spacing;

  const HorizontalScrollableContainer({
    super.key,
    required this.children,
    this.controller,
    this.padding,
    this.backgroundColor,
    this.thumbColor,
    this.spacing = AppDesignSystem.space3,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSpacing = spacing ?? AppDesignSystem.space3;

    return ScrollableContainer(
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: padding,
      backgroundColor: backgroundColor,
      thumbColor: thumbColor,
      child: Row(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) SizedBox(width: effectiveSpacing),
          ],
        ],
      ),
    );
  }
}

/// ============================================================================
/// VerticalScrollableContainer - 垂直滚动容器
/// ============================================================================
///
/// 专门用于垂直滚动的容器
/// ============================================================================
class VerticalScrollableContainer extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? thumbColor;
  final double? spacing;

  const VerticalScrollableContainer({
    super.key,
    required this.children,
    this.controller,
    this.padding,
    this.backgroundColor,
    this.thumbColor,
    this.spacing = AppDesignSystem.space2,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSpacing = spacing ?? AppDesignSystem.space2;

    return ScrollableContainer(
      controller: controller,
      scrollDirection: Axis.vertical,
      padding: padding,
      backgroundColor: backgroundColor,
      thumbColor: thumbColor,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) SizedBox(height: effectiveSpacing),
          ],
        ],
      ),
    );
  }
}

/// ============================================================================
/// ScrollableListView - 带滚动条的列表视图
/// ============================================================================
///
/// 便捷组件，在列表视图上自动添加滚动条
/// ============================================================================
class ScrollableListView extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? thumbColor;
  final double? itemSpacing;

  const ScrollableListView({
    super.key,
    required this.children,
    this.controller,
    this.padding,
    this.backgroundColor,
    this.thumbColor,
    this.itemSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: backgroundColor),
      child: ListView(
        controller: controller,
        padding: EdgeInsets.zero,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (itemSpacing != null && i < children.length - 1)
              SizedBox(height: itemSpacing),
          ],
        ],
      ),
    );
  }
}
