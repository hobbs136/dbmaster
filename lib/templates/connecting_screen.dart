// ============================================================================
// DbMaster Connecting Screen - Shown while connecting to a server
// ============================================================================

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../atoms/app_loading.dart';

class ConnectingScreen extends StatelessWidget {
  const ConnectingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('connecting_screen'),
      color: context.themeColors.bgPrimary,
      child: const AppPageLoading(message: '连接中...', showLogo: true),
    );
  }
}
