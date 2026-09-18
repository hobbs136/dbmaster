// SidebarWidget 拆分（plan §3.4）：侧边栏搜索框。
//
// 从 `_SidebarWidgetState._buildExpandedSidebar` 的内联 TextField 迁出。
// 受控组件：controller / focusNode 由 SidebarController 持有并传入，
// 查询归一化（trim + lowercase）与 server-side search 触发由调用方
// 经 [onQueryChanged] 委托给 SidebarController.updateSearchQuery。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

/// 侧边栏过滤搜索框（稳定样式：dense / 无边框 / 搜索前缀图标）。
class SidebarSearchField extends StatelessWidget {
  const SidebarSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onQueryChanged,
    required this.hasActiveQuery,
    this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// 搜索词变化回调（传原始输入；归一化由调用方负责）。
  final ValueChanged<String> onQueryChanged;

  /// 是否存在生效中的查询（控制清空按钮显隐）。
  final bool hasActiveQuery;

  /// 清空按钮回调（需同时清 [controller] 文本与查询状态）。
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    // C22-0 换装：与顶部连接选择器同宽容器（space3）+ 描边圆角版式。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space3,
        AppDesignSystem.space1_5,
        AppDesignSystem.space3,
        AppDesignSystem.space1,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: TextStyle(fontSize: 12, color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.sidebarFilterHint,
          hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
          prefixIcon: const Icon(LucideIcons.search, size: 14),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 30,
          ),
          suffixIcon: hasActiveQuery
              ? InkWell(
                  onTap: onClear,
                  child: const Icon(LucideIcons.x, size: 14),
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: colors.bgTertiary,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
            vertical: AppDesignSystem.space1_5,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: colors.borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: colors.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: colors.accentBlue),
          ),
        ),
        onChanged: onQueryChanged,
      ),
    );
  }
}
