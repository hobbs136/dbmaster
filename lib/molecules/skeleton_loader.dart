import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class SkeletonLoader extends StatefulWidget {
  final Widget child;
  final bool isLoading;

  const SkeletonLoader({super.key, required this.child, this.isLoading = true});

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(
      begin: 0.3,
      end: 0.6,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.themeColors.bgTertiary,
                context.themeColors.bgTertiary.withValues(
                  alpha: _animation.value + 0.3,
                ),
                context.themeColors.bgTertiary,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlideGradientTransform(_controller.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlideGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * slidePercent * 2 - bounds.width,
      0,
      0,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: borderRadius ?? BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
    );
  }
}

class SkeletonText extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonText({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width ?? double.infinity,
      height: height,
      borderRadius: borderRadius ?? BorderRadius.circular(AppDesignSystem.radiusSm),
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        shape: BoxShape.circle,
      ),
    );
  }
}

class TableSkeleton extends StatelessWidget {
  final int columns;
  final int rows;
  final double columnWidth;
  final double rowHeight;

  const TableSkeleton({
    super.key,
    this.columns = 5,
    this.rows = 10,
    this.columnWidth = 120,
    this.rowHeight = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: rowHeight,
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            border: Border(
              bottom: BorderSide(color: context.themeColors.borderLight),
            ),
          ),
          child: Row(
            children: List.generate(columns, (index) {
              return Container(
                width: columnWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                ),
                alignment: Alignment.centerLeft,
                child: SkeletonText(width: 60 + (index % 3) * 20),
              );
            }),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows,
            itemBuilder: (context, index) {
              return Container(
                height: rowHeight,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.themeColors.borderLight),
                  ),
                ),
                child: Row(
                  children: List.generate(columns, (colIndex) {
                    return Container(
                      width: columnWidth,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space2,
                      ),
                      alignment: Alignment.centerLeft,
                      child: SkeletonText(width: 40 + (colIndex % 4) * 25.0),
                    );
                  }),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CardSkeleton extends StatelessWidget {
  final double width;
  final double height;

  const CardSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonCircle(size: 32),
              const SizedBox(width: AppDesignSystem.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 120, height: 14),
                    const SizedBox(height: AppDesignSystem.space1),
                    SkeletonText(width: 80, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          SkeletonText(width: double.infinity, height: 12),
          const SizedBox(height: AppDesignSystem.space1),
          SkeletonText(width: 200, height: 12),
        ],
      ),
    );
  }
}

class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const ListSkeleton({super.key, this.itemCount = 5, this.itemHeight = 60});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return Container(
          height: itemHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          child: Row(
            children: [
              const SkeletonCircle(size: 40),
              const SizedBox(width: AppDesignSystem.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SkeletonText(width: 150, height: 14),
                    const SizedBox(height: AppDesignSystem.space1_5),
                    SkeletonText(width: 100, height: 12),
                  ],
                ),
              ),
              SkeletonBox(width: 60, height: 24),
            ],
          ),
        );
      },
    );
  }
}
