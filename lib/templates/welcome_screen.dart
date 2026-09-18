// ============================================================================
// DbMaster Welcome Screen - Shown when no server is connected
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../atoms/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../../organisms/connection/error_boundary.dart';
import '../../organisms/connection/password_prompt_dialog.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';

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
          width: 480,
          padding: const EdgeInsets.all(AppDesignSystem.space10),
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
                const SizedBox(height: AppDesignSystem.space6),
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
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeMd,
                    color: context.themeColors.textMuted,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space8),
                // Primary button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onNewConnection,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(l10n.connectionNewConnection),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.themeColors.accentBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDesignSystem.space3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                // Secondary button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOpenConnectionManager,
                    icon: const Icon(LucideIcons.share2, size: 18),
                    label: Text(l10n.connectionManageConnection),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.themeColors.textSecondary,
                      side: BorderSide.none,
                      backgroundColor: context.themeColors.bgTertiary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDesignSystem.space3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                // Open SQLite File — 零摩擦文件打开入口
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onOpenSqliteFile,
                    icon: const Icon(LucideIcons.folderOpen, size: 18),
                    label: Text(l10n.openSqliteFile),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.themeColors.textSecondary,
                      side: BorderSide.none,
                      backgroundColor: context.themeColors.bgTertiary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDesignSystem.space3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space8),
                // Recent Files —— 最近打开的 SQLite 文件（按时间倒序）
                Consumer<AppProvider>(
                  builder: (context, provider, _) {
                    final recentFiles = provider.connection.recentSqliteFiles;
                    if (recentFiles.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.recentFiles,
                            style: TextStyle(
                              fontSize: AppDesignSystem.fontSizeSm,
                              fontWeight: AppDesignSystem.fontWeightMedium,
                              color: context.themeColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.space3),
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
                                    l10n.sqliteOpenError,
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
                const SizedBox(height: AppDesignSystem.space8),
                // Saved connections
                Consumer<AppProvider>(
                  builder: (context, provider, _) {
                    if (provider.connection.savedConnections.isEmpty) {
                      return const AppEmptyState(
                        icon: LucideIcons.history,
                        title: 'No recent connections',
                      );
                    }
                    return Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Recent',
                            style: TextStyle(
                              fontSize: AppDesignSystem.fontSizeSm,
                              fontWeight: AppDesignSystem.fontWeightMedium,
                              color: context.themeColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.space3),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: provider.connection.savedConnections.map((
                            conn,
                          ) {
                            return ActionChip(
                              // emoji→矢量图标+品牌色（F-37）
                              avatar: Icon(
                                conn.type.typeIcon,
                                size: 14,
                                color: context.themeColors.brandColor(
                                  conn.type,
                                ),
                              ),
                              label: Text(
                                conn.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final connWithPassword =
                                    await PasswordPromptDialog.ensurePassword(
                                      context,
                                      conn,
                                    );
                                if (connWithPassword == null) return;
                                final success = await provider.connectToServer(
                                  connWithPassword,
                                );
                                if (success && context.mounted) {
                                  provider.sidebar.selectConnection(conn.id);
                                } else if (!success && context.mounted) {
                                  AppErrorHandler.showErrorSnackBar(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    )!.connectionFailedWith(
                                      provider.errorMessage ?? 'unknown',
                                    ),
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
