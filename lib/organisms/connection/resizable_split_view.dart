import 'package:flutter/material.dart';
import '../../theme/design_system.dart';
import '../../theme/app_colors.dart';

class ResizableSplitView extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double initialSplitRatio;
  final double minLeftWidth;
  final double minRightWidth;
  final Axis direction;
  final ValueChanged<double>? onSplitRatioChanged;

  const ResizableSplitView({
    super.key,
    required this.left,
    required this.right,
    this.initialSplitRatio = 0.6,
    this.minLeftWidth = 200,
    this.minRightWidth = 200,
    this.direction = Axis.horizontal,
    this.onSplitRatioChanged,
  });

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  late double _splitRatio;
  bool _isResizing = false;

  @override
  void initState() {
    super.initState();
    _splitRatio = widget.initialSplitRatio.clamp(0.1, 0.9);
  }

  void _updateSplitRatio(double delta, double totalSize) {
    setState(() {
      final newRatio = (_splitRatio + delta / totalSize);
      final minRatio = widget.minLeftWidth / totalSize;
      final maxRatio = 1 - (widget.minRightWidth / totalSize);
      _splitRatio = newRatio.clamp(minRatio, maxRatio);
    });
  }

  void _onResizeEnd() {
    setState(() => _isResizing = false);
    widget.onSplitRatioChanged?.call(_splitRatio);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize = widget.direction == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;

        final splitPosition = totalSize * _splitRatio;

        if (widget.direction == Axis.horizontal) {
          return Row(
            children: [
              SizedBox(width: splitPosition, child: widget.left),
              _Resizer(
                direction: widget.direction,
                isResizing: _isResizing,
                onResizeStart: () => setState(() => _isResizing = true),
                onResizeUpdate: (delta) => _updateSplitRatio(delta, totalSize),
                onResizeEnd: _onResizeEnd,
              ),
              Expanded(child: widget.right),
            ],
          );
        } else {
          return Column(
            children: [
              SizedBox(height: splitPosition, child: widget.left),
              _Resizer(
                direction: widget.direction,
                isResizing: _isResizing,
                onResizeStart: () => setState(() => _isResizing = true),
                onResizeUpdate: (delta) => _updateSplitRatio(delta, totalSize),
                onResizeEnd: _onResizeEnd,
              ),
              Expanded(child: widget.right),
            ],
          );
        }
      },
    );
  }
}

class _Resizer extends StatefulWidget {
  final Axis direction;
  final bool isResizing;
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResizeUpdate;
  final VoidCallback onResizeEnd;

  const _Resizer({
    required this.direction,
    required this.isResizing,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  @override
  State<_Resizer> createState() => _ResizerState();
}

class _ResizerState extends State<_Resizer> {
  bool _isHovered = false;
  double _accumulatedDelta = 0.0;
  static const double _sensitivityFactor = 0.8;
  static const double _threshold = 1.0;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.direction == Axis.horizontal;

    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _accumulatedDelta = 0.0;
          widget.onResizeStart();
        },
        onPanUpdate: (details) {
          final delta = isHorizontal ? details.delta.dx : details.delta.dy;
          _accumulatedDelta += delta * _sensitivityFactor;
          if (_accumulatedDelta.abs() >= _threshold) {
            widget.onResizeUpdate(_accumulatedDelta);
            _accumulatedDelta = 0.0;
          }
        },
        onPanEnd: (_) {
          if (_accumulatedDelta.abs() > 0) {
            widget.onResizeUpdate(_accumulatedDelta);
          }
          widget.onResizeEnd();
        },
        child: SizedBox(
          width: isHorizontal ? 12 : null,
          height: isHorizontal ? null : 12,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: widget.isResizing
                ? context.themeColors.accentBlue.withValues(alpha: 0.3)
                : _isHovered
                ? context.themeColors.accentBlue.withValues(alpha: 0.1)
                : Colors.transparent,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: isHorizontal ? 1 : 24,
                height: isHorizontal ? 24 : 1,
                decoration: BoxDecoration(
                  color: widget.isResizing
                      ? context.themeColors.accentBlue
                      : _isHovered
                      ? context.themeColors.accentBlue.withValues(alpha: 0.5)
                      : AppDesignSystem.borderDefault,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThreePaneResizableLayout extends StatefulWidget {
  final Widget left;
  final Widget center;
  final Widget? right;
  final double initialLeftWidth;
  final double initialCenterRatio;
  final double minLeftWidth;
  final double minCenterWidth;
  final double? minRightWidth;
  final ValueChanged<double>? onLeftWidthChanged;
  final ValueChanged<double>? onCenterRatioChanged;

  const ThreePaneResizableLayout({
    super.key,
    required this.left,
    required this.center,
    this.right,
    this.initialLeftWidth = 280.0,
    this.initialCenterRatio = 0.65,
    this.minLeftWidth = 200.0,
    this.minCenterWidth = 400.0,
    this.minRightWidth,
    this.onLeftWidthChanged,
    this.onCenterRatioChanged,
  });

  @override
  State<ThreePaneResizableLayout> createState() =>
      _ThreePaneResizableLayoutState();
}

class _ThreePaneResizableLayoutState extends State<ThreePaneResizableLayout> {
  late double _leftWidth;
  late double _centerRatio;
  bool _isLeftResizing = false;
  bool _isRightResizing = false;

  @override
  void initState() {
    super.initState();
    _leftWidth = widget.initialLeftWidth;
    _centerRatio = widget.initialCenterRatio.clamp(0.3, 0.7);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final remainingWidth = availableWidth - _leftWidth;

        if (widget.right == null) {
          return Row(
            children: [
              SizedBox(width: _leftWidth, child: widget.left),
              _Resizer(
                direction: Axis.horizontal,
                isResizing: _isLeftResizing,
                onResizeStart: () => setState(() => _isLeftResizing = true),
                onResizeUpdate: (delta) {
                  setState(() {
                    _leftWidth = (_leftWidth + delta).clamp(
                      widget.minLeftWidth,
                      availableWidth - widget.minCenterWidth,
                    );
                  });
                },
                onResizeEnd: () {
                  setState(() => _isLeftResizing = false);
                  widget.onLeftWidthChanged?.call(_leftWidth);
                },
              ),
              Expanded(child: widget.center),
            ],
          );
        }

        final centerWidth = remainingWidth * _centerRatio;

        return Row(
          children: [
            SizedBox(width: _leftWidth, child: widget.left),
            _Resizer(
              direction: Axis.horizontal,
              isResizing: _isLeftResizing,
              onResizeStart: () => setState(() => _isLeftResizing = true),
              onResizeUpdate: (delta) {
                setState(() {
                  final newLeftWidth = _leftWidth + delta;
                  final minRemaining =
                      widget.minCenterWidth + (widget.minRightWidth ?? 200);

                  _leftWidth = newLeftWidth.clamp(
                    widget.minLeftWidth,
                    availableWidth - minRemaining,
                  );
                });
              },
              onResizeEnd: () {
                setState(() => _isLeftResizing = false);
                widget.onLeftWidthChanged?.call(_leftWidth);
              },
            ),
            SizedBox(width: centerWidth, child: widget.center),
            _Resizer(
              direction: Axis.horizontal,
              isResizing: _isRightResizing,
              onResizeStart: () => setState(() => _isRightResizing = true),
              onResizeUpdate: (delta) {
                setState(() {
                  final newCenterRatio = _centerRatio + delta / remainingWidth;
                  final minRightRatio =
                      (widget.minRightWidth ?? 200) / remainingWidth;
                  final maxCenterRatio = 1 - minRightRatio;

                  _centerRatio = newCenterRatio.clamp(
                    widget.minCenterWidth / remainingWidth,
                    maxCenterRatio,
                  );
                });
              },
              onResizeEnd: () {
                setState(() => _isRightResizing = false);
                widget.onCenterRatioChanged?.call(_centerRatio);
              },
            ),
            Expanded(child: widget.right!),
          ],
        );
      },
    );
  }
}
