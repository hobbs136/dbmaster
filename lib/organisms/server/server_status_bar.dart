//! Compact status bar widget showing server connection state.
//!
//! Displays in the top-right chrome area. Shows:
//! - Disconnected: grey icon + "Not connected", click to open connect dialog
//! - Connecting: yellow spinner
//! - Connected: green dot + server hostname + user email
//! - Reconnecting: yellow dot + countdown

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/server_connection_provider.dart';
import '../../services/server_connection.dart';
import '../../theme/app_colors.dart';
import 'server_connect_dialog.dart';
import 'drift/drift_task_list_dialog.dart';
import 'data_sync/data_sync_task_list_dialog.dart';
import 'health_check/health_check_task_list_dialog.dart';
import 'slow_query/slow_query_dialog.dart';
import 'reports/reports_dialog.dart';
import 'team_query/team_query_library_dialog.dart';
import 'approval/approval_list_dialog.dart';
import 'workspace/workspace_list_dialog.dart';
import 'mcp/mcp_token_dialog.dart';
import 'connections/server_connections_dialog.dart';
import '../../providers/health_check_provider.dart';
import '../../providers/approval_provider.dart';
import '../../molecules/compact_popup_menu_item.dart';

/// Server connection status indicator for the top bar.
///
/// Always visible — displays different states based on connection.
class ServerStatusBar extends StatefulWidget {
  const ServerStatusBar({super.key});

  @override
  State<ServerStatusBar> createState() => _ServerStatusBarState();
}

class _ServerStatusBarState extends State<ServerStatusBar> {
  Timer? _countdownTimer;
  final int _reconnectSeconds = 0;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerConnectionProvider>(
      builder: (context, provider, _) {
        final state = provider.connectionState;
        final colors = context.themeColors;

        switch (state) {
          case ServerConnectionState.disconnected:
            return _buildDisconnected(context, colors, provider);
          case ServerConnectionState.connecting:
            return _buildConnecting(colors);
          case ServerConnectionState.connected:
            return _buildConnected(colors, provider);
          case ServerConnectionState.reconnecting:
            return _buildReconnecting(colors, provider);
        }
      },
    );
  }

  Widget _buildDisconnected(
    BuildContext context,
    ThemeColors colors,
    ServerConnectionProvider provider,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => showServerConnectDialog(context, provider),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1,
        ),
        decoration: BoxDecoration(
          color: colors.textMuted.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cloudOff, size: 12, color: colors.textMuted),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n.serverBarNotConnected,
              style: AppTextStyles.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnecting(ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(context.themeColors.warning),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            l10n.serverBarConnecting,
            style: AppTextStyles.caption.copyWith(
              color: context.themeColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnected(
    ThemeColors colors,
    ServerConnectionProvider provider,
  ) {
    final l10n = AppLocalizations.of(context)!;
    // in embedded mode show "Local" instead of the
    // loopback host (127.0.0.1 conveys nothing useful to the user).
    final isEmbedded = provider.isEmbeddedMode;
    final host = Uri.tryParse(provider.serverUrl ?? '')?.host ?? '';
    final label = isEmbedded
        ? l10n.serverBarLocal
        : (host.isNotEmpty ? host : l10n.serverBarConnected);
    final icon = isEmbedded ? LucideIcons.server : LucideIcons.cloudCheck;

    return InkWell(
      onTap: () => _showConnectedMenu(context, provider),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1,
        ),
        decoration: BoxDecoration(
          color: context.themeColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(
            color: context.themeColors.success.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.themeColors.success,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Icon(icon, size: 12, color: context.themeColors.success),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: context.themeColors.success,
                fontWeight: AppDesignSystem.fontWeightMedium,
              ),
            ),
            // Health alert badge (ADR-0004 client integration): renders only
            // when monitored source connections have active alerts. Tapping
            // opens the health check dialog. Hidden in embedded mode — the
            // Provider never refreshes there, so alertedConnectionIds is empty.
            ..._healthBadge(context),
            ..._approvalBadge(context),
          ],
        ),
      ),
    );
  }

  /// Active-alert badge appended to the connected status pill. Returns an
  /// empty list (renders nothing) when there are no alerts or in embedded mode.
  List<Widget> _healthBadge(BuildContext context) {
    final count = context
        .watch<HealthCheckProvider>()
        .alertedConnectionIds
        .length;
    if (count == 0) return const [];
    final l10n = AppLocalizations.of(context)!;
    return [
      const SizedBox(width: AppDesignSystem.space1),
      Tooltip(
        message: l10n.healthBadgeAlerts(count),
        child: InkWell(
          onTap: () => showHealthCheckTaskListDialog(context),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: context.themeColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.error.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.triangleAlert,
                  size: 11,
                  color: context.themeColors.error,
                ),
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: AppTextStyles.caption.copyWith(
                    color: context.themeColors.error,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  /// Pending-approval badge appended to the connected status pill. Returns an
  /// empty list (renders nothing) when there are no pending approvals or in
  /// embedded mode. Tapping opens the DDL approval queue dialog.
  List<Widget> _approvalBadge(BuildContext context) {
    final count = context.watch<ApprovalProvider>().pendingCount;
    if (count == 0) return const [];
    final l10n = AppLocalizations.of(context)!;
    return [
      const SizedBox(width: AppDesignSystem.space1),
      Tooltip(
        message: l10n.approvalBadgeCount(count),
        child: InkWell(
          onTap: () => showApprovalListDialog(context),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: context.themeColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.clipboardCheck,
                  size: 11,
                  color: context.themeColors.warning,
                ),
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: AppTextStyles.caption.copyWith(
                    color: context.themeColors.warning,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildReconnecting(
    ThemeColors colors,
    ServerConnectionProvider provider,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(context.themeColors.warning),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            _reconnectSeconds > 0
                ? l10n.serverBarReconnectingIn(_reconnectSeconds)
                : l10n.serverBarReconnecting,
            style: AppTextStyles.caption.copyWith(
              color: context.themeColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectedMenu(
    BuildContext context,
    ServerConnectionProvider provider,
  ) {
    final l10n = AppLocalizations.of(context)!;
    // Drift / health check / MCP tokens require a remote server deployment:
    // the embedded engine runs drift & health on Noop runners and binds a
    // random loopback port that dies with the app — disable the entries with
    // a hint instead of letting users create tasks that never run.
    final isEmbedded = provider.isEmbeddedMode;
    // Fixed spacing (not Spacer): the popup menu sizes itself via
    // IntrinsicWidth, where an Expanded collapses to zero and the hint would
    // then overflow the row instead of widening the menu.
    List<Widget> remoteOnlySuffix() => isEmbedded
        ? [
            const SizedBox(width: 12),
            Text(
              l10n.embeddedRequiresRemoteServer,
              style: AppTextStyles.caption.copyWith(fontSize: 10),
            ),
          ]
        : const <Widget>[];
    // Anchor the menu below-right of the status pill. The old hardcoded
    // fromLTRB(1000, 40, 1000, 0) placed the menu off-screen on windows
    // narrower than ~2000px.
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final overlaySize = MediaQuery.of(context).size;
    final menuPosition = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height + 4,
      overlaySize.width - origin.dx - box.size.width,
      0,
    );
    showMenu(
      context: context,
      position: menuPosition,
      items: <PopupMenuEntry<void>>[
        CompactPopupMenuItem<void>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.userProfile?.displayName ?? l10n.serverBarUnknownUser,
                style: AppTextStyles.body.copyWith(
                  fontWeight: AppDesignSystem.fontWeightSemibold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                provider.userProfile?.email ?? '',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.serverBarServerUrl(provider.serverUrl ?? ''),
                style: AppTextStyles.caption.copyWith(fontSize: 11),
              ),
              // U15：server 版本（embedded 握手 / 远程 /api/instance 同源）；
              // 低于客户端最低兼容版本时给告警色提示。
              if (ServerConnection().serverVersion != null) ...[
                const SizedBox(height: 2),
                Text(
                  ServerConnection().serverVersionOutdated
                      ? l10n.serverVersionOutdated(
                          ServerConnection().serverVersion!,
                          ServerConnection.minCompatibleServerVersion,
                        )
                      : l10n.serverVersionLine(
                          ServerConnection().serverVersion!,
                        ),
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10,
                    color: ServerConnection().serverVersionOutdated
                        ? context.themeColors.warning
                        : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem<void>(
          enabled: !isEmbedded,
          onTap: () => showDriftTaskListDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.bellRing, size: 16),
              const SizedBox(width: 8),
              Flexible(child: Text(l10n.driftMenuLabel)),
              ...remoteOnlySuffix(),
            ],
          ),
        ),
        CompactPopupMenuItem<void>(
          onTap: () => showDataSyncTaskListDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.arrowRightLeft, size: 16),
              const SizedBox(width: 8),
              Text(l10n.dataSyncMenuLabel),
            ],
          ),
        ),
        CompactPopupMenuItem<void>(
          enabled: !isEmbedded,
          onTap: () => showHealthCheckTaskListDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.heartPulse, size: 16),
              const SizedBox(width: 8),
              Flexible(child: Text(l10n.healthMenuLabel)),
              ...remoteOnlySuffix(),
            ],
          ),
        ),
        CompactPopupMenuItem<void>(
          onTap: () => showTeamQueryLibraryDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.folderSymlink, size: 16),
              const SizedBox(width: 8),
              Text(l10n.teamQueryMenuLabel),
            ],
          ),
        ),
        // U05 — the server-side connection registry writer (list/create/
        // edit/delete). Works in both modes: remote had no writer at all;
        // embedded mirrors exist but stay inspectable/repairable here.
        CompactPopupMenuItem<void>(
          onTap: () => showServerConnectionsDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.database, size: 16),
              const SizedBox(width: 8),
              Text(l10n.serverConnectionsMenuLabel),
            ],
          ),
        ),
        CompactPopupMenuItem<void>(
          onTap: () => showApprovalListDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.clipboardCheck, size: 16),
              const SizedBox(width: 8),
              Text(l10n.approvalMenuLabel),
            ],
          ),
        ),
        CompactPopupMenuItem<void>(
          onTap: () => showWorkspaceListDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.users, size: 16),
              const SizedBox(width: 8),
              Text(l10n.workspacesMenuLabel),
            ],
          ),
        ),
        CompactPopupMenuItem<void>(
          enabled: !isEmbedded,
          onTap: () => showMcpTokenDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.keyRound, size: 16),
              const SizedBox(width: 8),
              Flexible(child: Text(l10n.mcpTokensMenuLabel)),
              ...remoteOnlySuffix(),
            ],
          ),
        ),
        // reports-M1（#29）— 慢查询统计：embedded **不禁用**（与 drift/health
        // 的 remote-only 不同——embedded 是本功能主场景：桌面全部查询经嵌
        // 入式 server，采样本地即得）。
        CompactPopupMenuItem<void>(
          onTap: () => showSlowQueryDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.gauge, size: 16),
              const SizedBox(width: 8),
              Text(l10n.slowQueryMenuLabel),
            ],
          ),
        ),
        // reports-M2（#29）— 报告中心（通用 hub）：embedded 可用（生成按钮
        // 是 mutation，远程 Gated 态 403 由 service 转 Entitlement 异常提示）。
        CompactPopupMenuItem<void>(
          onTap: () => showReportsDialog(context),
          child: Row(
            children: [
              const Icon(LucideIcons.sparkles, size: 16),
              const SizedBox(width: 8),
              Text(l10n.reportsMenuLabel),
            ],
          ),
        ),
        CompactPopupMenuItem<void>(
          onTap: () => provider.disconnect(),
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 16),
              const SizedBox(width: 8),
              Text(l10n.serverBarDisconnect),
            ],
          ),
        ),
      ],
    );
  }
}
