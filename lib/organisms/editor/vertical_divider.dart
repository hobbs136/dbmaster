import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// EditorVerticalDivider - 编辑器工具栏垂直分隔线
class EditorVerticalDivider extends StatelessWidget {
  const EditorVerticalDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      color: context.themeColors.borderLight,
    );
  }
}
