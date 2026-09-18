import 'package:flutter/material.dart';

import '../theme/design_system.dart';

/// 紧凑弹出菜单项 —— 体系 B（showMenu / PopupMenuButton）的统一菜单行。
///
/// 与 [PopupMenuItem] 构造签名对齐，仍是 `PopupMenuEntry<T>`，
/// onSelected / onTap 语义完全不变；仅收紧默认行高与水平内边距：
/// - [height] 默认 [AppDesignSystem.menuItemHeight]（26）
/// - [padding] 默认水平 [AppDesignSystem.menuItemHPadding]（10）
///
/// 例外场景（双行内容等）可显式传 `height` 覆盖并在调用处注释原因。
class CompactPopupMenuItem<T> extends PopupMenuItem<T> {
  const CompactPopupMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled = true,
    super.height = AppDesignSystem.menuItemHeight,
    super.padding = const EdgeInsets.symmetric(
      horizontal: AppDesignSystem.menuItemHPadding,
    ),
    super.textStyle,
    super.labelTextStyle,
    super.mouseCursor,
    required super.child,
  });
}
