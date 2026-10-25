// ============================================================================
// DbMaster Welcome Screen - Shown when no server is connected
// ============================================================================
//
// UIRV-B6（2026-10-25）紧凑化：欢迎列 400px / 内距 24px；New Connection 为唯一
// 主行动（32px 高），Manage Connections / Open SQLite File 同级紧凑双钮；中央
// 不再渲染 savedConnections / Recent 连接 chips（连接浏览由左侧长驻树承接，
// 数据零改动）；Recent Files 仅 recentSqliteFiles 非空时渲染（无空态卡）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../organisms/connection/error_boundary.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';

/// 主/次行动按钮高度（设计稿 B6 规格表「主动作高 32px」；设计系统暂无对应
/// token，落为文件内常量，后续若 design_system 增补按钮高度 token 再对齐）。
const double _kWelcomeActionHeight = 32.0;

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onNewConnection;
  final VoidCallback onOpenConnectionManager;
  // SQLite 文件打开入口回调（零摩擦打开 .db）
  final VoidCallback onOpenSqliteFile;

  const WelcomeScreen({
    super.key,
    required this.onNewConnection,
    required this.onOpenConnectionManager,
    required this.onOpenSqliteFile,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      key: const ValueKey('welcome_screen'),
      color: context.themeColors.bgPrimary,
      child: Center(
        child: Container(
          width: AppDesignSystem.inputMaxWidth,
          padding: const EdgeInsets.all(AppDesignSystem.space6),
          decoration: BoxDecoration(
            color: context.themeColors.bgSecondary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: context.themeColors.accentBlue.withOpacityValue(0.1),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusMd,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.database,
                    size: 32,
                    color: context.themeColors.accentBlue,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space4),
                Text(
                  l10n.appTitle,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeDisplay,
                    fontWeight: AppDesignSystem.fontWeightBold,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                Text(
                  l10n.welcomeSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeMd,
                    color: context.themeColors.textMuted,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space6),
                // 唯一主行动：New Connection
                SizedBox(
                  width: double.infinity,
                  height: _kWelcomeActionHeight,
                  child: ElevatedButton.icon(
                    onPressed: onNewConnection,
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: Text(l10n.connectionNewConnection),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.themeColors.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                // 次级紧凑双钮：Manage Connections / Open SQLite File
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: _kWelcomeActionHeight,
                        child: OutlinedButton.icon(
                          onPressed: onOpenConnectionManager,
                          icon: const Icon(LucideIcons.share2, size: 16),
                          label: Text(
                            l10n.connectionManageConnection,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                context.themeColors.textSecondary,
                            side: BorderSide.none,
                            backgroundColor: context.themeColors.bgTertiary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDesignSystem.space2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDesignSystem.radiusSm,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Expanded(
                      child: SizedBox(
                        height: _kWelcomeActionHeight,
                        child: OutlinedButton.icon(
                          onPressed: onOpenSqliteFile,
                          icon: const Icon(LucideIcons.folderOpen, size: 16),
                          label: Text(
                            l10n.openSqliteFile,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                context.themeColors.textSecondary,
                            side: BorderSide.none,
                            backgroundColor: context.themeColors.bgTertiary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDesignSystem.space2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDesignSystem.radiusSm,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Recent Files —— 仅在最近 SQLite 文件非空时渲染（无空态卡）
                Consumer<AppProvider>(
                  builder: (context, provider, _) {
                    final recentFiles = provider.connection.recentSqliteFiles;
                    if (recentFiles.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppDesignSystem.space6),
                        Text(
                          AppLocalizations.of(context)!.recentFiles,
                          style: TextStyle(
                            fontSize: AppDesignSystem.fontSizeSm,
                            fontWeight: AppDesignSystem.fontWeightMedium,
                            color: context.themeColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.space2),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: recentFiles.map((conn) {
                            return ActionChip(
                              avatar: const Icon(
                                LucideIcons.fileText,
                                size: 14,
                              ),
                              label: Text(
                                conn.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                // 复用 openSqliteFile：连接 + 刷新 lastConnected
                                final success = await provider.connection
                                    .openSqliteFile(conn.host);
                                if (success && context.mounted) {
                                  provider.sidebar.selectConnection(conn.id);
                                } else if (!success && context.mounted) {
                                  AppErrorHandler.showErrorSnackBar(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.sqliteOpenError,
                                  );
                                }
                              },
                              backgroundColor: context.themeColors.bgTertiary,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDesignSystem.radiusSm,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
