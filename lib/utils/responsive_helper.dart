import 'package:flutter/material.dart';

import '../theme/design_system.dart';

enum ScreenSize { compact, medium, expanded, large }

class ResponsiveHelper {
  // 断点值的 single source of truth 在 AppDesignSystem（plan §3.3）；
  // 这里保留语义别名，使调用方 `ResponsiveHelper.compactBreakpoint` 等不需改动。
  static const double compactBreakpoint = AppDesignSystem.breakpointCompact;
  static const double mediumBreakpoint = AppDesignSystem.breakpointMedium;
  static const double expandedBreakpoint = AppDesignSystem.breakpointExpanded;
  static const double largeBreakpoint = AppDesignSystem.breakpointLarge;

  static ScreenSize getScreenSize(double width) {
    if (width < compactBreakpoint) return ScreenSize.compact;
    if (width < mediumBreakpoint) return ScreenSize.medium;
    if (width < expandedBreakpoint) return ScreenSize.expanded;
    return ScreenSize.large;
  }

  static bool isCompact(BuildContext context) =>
      MediaQuery.of(context).size.width < compactBreakpoint;

  static bool isMedium(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= compactBreakpoint && width < mediumBreakpoint;
  }

  static bool isExpanded(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mediumBreakpoint && width < expandedBreakpoint;
  }

  static bool isLarge(BuildContext context) =>
      MediaQuery.of(context).size.width >= expandedBreakpoint;

  static double getSidebarWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < compactBreakpoint) return 0;
    if (width < mediumBreakpoint) return 180;
    if (width < expandedBreakpoint) return 220;
    return 280;
  }

  static double getAiPanelWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < expandedBreakpoint) return 280;
    if (width < largeBreakpoint) return 320;
    return 380;
  }

  static bool shouldShowLabels(BuildContext context) =>
      MediaQuery.of(context).size.width >= mediumBreakpoint;

  static int getGridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < compactBreakpoint) return 1;
    if (width < mediumBreakpoint) return 2;
    if (width < expandedBreakpoint) return 3;
    if (width < largeBreakpoint) return 4;
    return 5;
  }

  static double getDialogWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < compactBreakpoint) return width * 0.95;
    if (width < mediumBreakpoint) return width * 0.85;
    if (width < expandedBreakpoint) return width * 0.7;
    return 600;
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenSize screenSize) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = ResponsiveHelper.getScreenSize(constraints.maxWidth);
        return builder(context, screenSize);
      },
    );
  }
}

class ResponsiveValue<T> {
  final T compact;
  final T? medium;
  final T? expanded;
  final T? large;

  const ResponsiveValue({
    required this.compact,
    this.medium,
    this.expanded,
    this.large,
  });

  T getValue(ScreenSize size) {
    switch (size) {
      case ScreenSize.compact:
        return compact;
      case ScreenSize.medium:
        return medium ?? compact;
      case ScreenSize.expanded:
        return expanded ?? medium ?? compact;
      case ScreenSize.large:
        return large ?? expanded ?? medium ?? compact;
    }
  }
}
