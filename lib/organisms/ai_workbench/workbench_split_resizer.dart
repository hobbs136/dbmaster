//! 工作台对话列-舞台分隔条（任务书 B3）：`EditorResultsResizer(isHorizontal:
//! true)` 的键盘可达包装（R1 零布局占位——本组件自身不含布局尺寸语义，
//! 宽度/叠层定位由 shell 的 `_buildStageLayout` 承担）。
//!
//! 指针拖拽：delta 直通 `onResizeUpdate`（向右拖对话列变宽，AppResizer 内含
//! 0.8 灵敏度）。键盘（v1 §5-4）：聚焦后 ←/→ = 16px、Shift+←/→ = 64px、
//! Home = 复位 360——经 [onKeyboardResize] / [onReset] 回调交宿主处理并即时
//! 落盘。tooltip 消费预登记 key `workbenchSplitResizerTooltip`（标注快捷键）。
//!
//! `molecules/resizer_widgets.dart` 零改动：本组件只组合，不继承不改视觉参数
//! （gripHandle/restLine 沿缺省）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../molecules/resizer_widgets.dart';

/// 工作台对话列-舞台分隔条（拖拽 + 键盘双通道，见文件头 dartdoc）。
class WorkbenchSplitResizer extends StatefulWidget {
  const WorkbenchSplitResizer({
    super.key,
    required this.isResizing,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onKeyboardResize,
    required this.onReset,
    this.focusNode,
  });

  /// 是否拖拽中（宿主 State 持有，透传给底层 [AppResizer]）。
  final bool isResizing;

  final VoidCallback onResizeStart;
  final ValueChanged<double> onResizeUpdate;
  final VoidCallback onResizeEnd;

  /// 键盘步进：[delta] 为带符号像素（← 负 / → 正；普通 16、Shift 64）。
  /// 宿主立即生效并落盘（与拖拽的「update 改内存、end 落盘」不同）。
  final ValueChanged<double> onKeyboardResize;

  /// Home 复位到 360（宿主写盘，见任务书允许自决项）。
  final VoidCallback onReset;

  /// 可选外部焦点节点（A5 焦点区注册可复用；缺省由 [Focus] 自建）。
  final FocusNode? focusNode;

  @override
  State<WorkbenchSplitResizer> createState() => _WorkbenchSplitResizerState();
}

class _WorkbenchSplitResizerState extends State<WorkbenchSplitResizer> {
  /// 键盘步进像素（tooltip 文案 `workbenchSplitResizerTooltip` 标注 16/64，
  /// 两处必须同步改）。
  static const double _stepNormal = 16.0;
  static const double _stepShift = 64.0;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // KeyRepeat 按住连发与单击同语义（stage tab roving 仅 KeyDown 的先例
    // 针对离散移动；宽度步进按住连续调整是预期手感）。
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final step = HardwareKeyboard.instance.isShiftPressed
        ? _stepShift
        : _stepNormal;
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onKeyboardResize(-step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onKeyboardResize(step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      widget.onReset();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Tooltip(
        message: l10n.workbenchSplitResizerTooltip,
        child: EditorResultsResizer(
          isResizing: widget.isResizing,
          isHorizontal: true,
          onResizeStart: widget.onResizeStart,
          onResizeUpdate: widget.onResizeUpdate,
          onResizeEnd: widget.onResizeEnd,
        ),
      ),
    );
  }
}
