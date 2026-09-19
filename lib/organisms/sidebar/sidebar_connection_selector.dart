// C22-0 · 侧边栏顶部连接选择器（原型 sidebar-*.html chrome 的
//「Connection selector」）。
//
// 显示当前活动连接（活动 tab → currentServer → 侧栏选中，与
// resolveCapabilityMenuServer 同源的回退序但不要求已连接——选择器展示
// 选中目标即可）；点击弹出全部已保存连接的快速切换菜单：
// - 已连接项 → switchToConnection（直接切换，不折叠树——与树节点 tap
//   的「切换 + toggleExpand」不同，选择器语义是纯切换）；
// - 未连接项 → 经 [onConnectionTap] 走与树/折叠 rail 同款连接流程
//   （密码弹窗等副作用留在宿主 controller）；
// - 底部固定「管理连接…」入口。
// 无已保存连接时退化为占位按钮，点击直接打开连接管理器。
import 'dart:async'; // unawaited

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/connection_failure.dart';
import '../../models/database_models.dart' show DbServer, DatabaseType;
import '../../molecules/compact_popup_menu_item.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';
import '../connection/connect_failure_dialog.dart';
import 'sidebar_current_connection.dart';

class SidebarConnectionSelector extends StatelessWidget {
  /// 未连接项的连接流程（宿主 SidebarController.handleConnectionTap）。
  final Future<void> Function(DbServer server)? onConnectionTap;

  /// 打开连接管理器（底部固定项 + 空态按钮共用）。
  final VoidCallback onManageConnections;

  const SidebarConnectionSelector({
    super.key,
    this.onConnectionTap,
    required this.onManageConnections,
  });

  /// 地址段：SQLite host 承载文件路径（无端口）；其余 host:port。
  static String addressLabel(DbServer server) {
    if (server.type == DatabaseType.sqlite || server.port <= 0) {
      return server.host;
    }
    return '${server.host}:${server.port}';
  }

  /// T10 · 失败分型 → 人话消息（与 ConnectFailureDialog 同口径的展示边界
  /// 映射；rawMessage 未脱敏不进 tooltip）。选择器条目与树根状态点共用
  /// （任务书允许文件清单内无共享 helper 落点，取选择器公开静态挂载）。
  static String failurePlainMessage(
    AppLocalizations l10n,
    ConnectionFailureKind kind,
  ) => switch (kind) {
    ConnectionFailureKind.fileLocked => l10n.connectFailureFileLocked,
    ConnectionFailureKind.fileNotFound => l10n.connectFailureFileNotFound,
    ConnectionFailureKind.permissionDenied =>
      l10n.connectFailurePermissionDenied,
    ConnectionFailureKind.notADatabase => l10n.connectFailureNotADatabase,
    ConnectionFailureKind.corrupt => l10n.connectFailureCorrupt,
    ConnectionFailureKind.authFailed => l10n.connectFailureAuthFailed,
    ConnectionFailureKind.unreachable => l10n.connectFailureUnreachable,
    ConnectionFailureKind.unknown => l10n.connectFailureUnknown,
  };

  DbServer? _resolveCurrent(AppProvider provider) =>
      resolveSidebarCurrentConnection(provider);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final current = _resolveCurrent(provider);
    final l10n = AppLocalizations.of(context)!;

    if (provider.savedConnections.isEmpty) {
      return _SelectorButton(
        onTap: onManageConnections,
        tooltip: l10n.sidebarConnectionNone,
        child: Row(
          children: [
            Icon(LucideIcons.plus, size: 12, color: context.themeColors.textMuted),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                l10n.sidebarConnectionNone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: context.themeColors.textMuted,
                ),
              ),
            ),
            _ChevronsIcon(color: context.themeColors.textMuted),
          ],
        ),
      );
    }

    final isConnected = current != null && provider.isConnectionConnected(
      current.id,
    );

    return PopupMenuButton<String>(
      tooltip: l10n.sidebarConnectionSwitch,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 220, maxHeight: 360),
      onSelected: (value) {
        if (value == '__manage__') {
          onManageConnections();
          return;
        }
        final server = provider.savedConnections
            .where((s) => s.id == value)
            .firstOrNull;
        if (server == null) return;
        if (provider.isConnectionConnected(server.id)) {
          provider.switchToConnection(server.id);
        } else if (provider.connection.lastFailureFor(server.id) != null) {
          // T10 · 未处置失败条目点击 = 重试连接；失败弹结构化对话框
          // （回调注入，T5 契约），成功由 provider 清除失败态。
          unawaited(_retryFailedConnection(context, provider, server));
        } else {
          onConnectionTap?.call(server);
        }
      },
      // C22-1：树不再列连接，分组呈现迁到下拉——未分组连接在前，
      // 各分组以不可点的小节头分隔（组色圆点 + 组名）。
      itemBuilder: (context) => [
        ..._buildGroupedItems(context, provider, current?.id),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: '__manage__',
          child: Row(
            children: [
              Icon(
                LucideIcons.settings2,
                size: 14,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                AppLocalizations.of(context)!.sidebarManageConnections,
                style: TextStyle(color: context.themeColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
      child: _SelectorButton(
        onTap: null, // PopupMenuButton 自管点击
        tooltip: current == null
            ? l10n.sidebarConnectionSwitch
            : '${current.name} - ${addressLabel(current)}',
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected
                    ? context.themeColors.success
                    : context.themeColors.textMuted,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                current == null
                    ? l10n.sidebarConnectionSwitch
                    : '${current.name} - ${addressLabel(current)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  fontWeight: FontWeight.w500,
                  color: current == null
                      ? context.themeColors.textMuted
                      : context.themeColors.textPrimary,
                ),
              ),
            ),
            _ChevronsIcon(color: context.themeColors.textMuted),
          ],
        ),
      ),
    );
  }

  /// T10 · 重试未处置失败的连接：直接走 provider 连接（不经宿主
  /// onConnectionTap 的表单/密码流程——失败条目自带完整凭据）；失败 →
  /// ConnectFailureDialog（重试/最新失败回调注入，T5 契约）。
  Future<void> _retryFailedConnection(
    BuildContext context,
    AppProvider provider,
    DbServer server,
  ) async {
    final ok = await provider.connectToServer(server);
    if (ok || !context.mounted) return;
    final failure = provider.connection.lastConnectFailure;
    if (failure == null) return;
    await ConnectFailureDialog.show(
      context,
      failure: failure,
      onRetry: () => provider.connectToServer(server),
      latestFailure: () => provider.connection.lastConnectFailure,
    );
  }

  /// 分区下拉项：未分组连接 + 各分组（组头不可点）。分组孤儿
  ///（groupId 指向已删组）按未分组处理，与原树装配语义一致。
  List<PopupMenuEntry<String>> _buildGroupedItems(
    BuildContext context,
    AppProvider provider,
    String? currentId,
  ) {
    final groups = provider.connectionGroups;
    final grouped = <String, List<DbServer>>{};
    final ungrouped = <DbServer>[];
    for (final conn in provider.savedConnections) {
      final gid = conn.groupId;
      if (gid != null && groups.any((g) => g.id == gid)) {
        grouped.putIfAbsent(gid, () => []).add(conn);
      } else {
        ungrouped.add(conn);
      }
    }

    final items = <PopupMenuEntry<String>>[
      for (final server in ungrouped)
        _connectionItem(context, provider, server, currentId),
    ];
    for (final group in groups) {
      final members = grouped[group.id];
      if (members == null || members.isEmpty) continue;
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          height: 26,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _parseGroupColor(context, group.color),
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      items.addAll(
        members.map(
          (s) => _connectionItem(context, provider, s, currentId),
        ),
      );
    }
    return items;
  }

  Color _parseGroupColor(BuildContext context, String? colorStr) {
    if (colorStr == null) return context.themeColors.accentBlue;
    try {
      return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
    } catch (_) {
      return context.themeColors.accentBlue;
    }
  }

  PopupMenuItem<String> _connectionItem(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    String? currentId,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final isConnected = provider.isConnectionConnected(server.id);
    final isCurrent = currentId == server.id;
    final isConnecting = provider.isConnectionConnecting(server.id);

    return PopupMenuItem<String>(
      value: server.id,
      height: 36,
      child: Row(
        children: [
          Icon(
            server.type.typeIcon,
            size: 14,
            color: context.themeColors.brandColor(server.type),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: isCurrent ? FontWeight.w600 : null,
                color: isCurrent
                    ? context.themeColors.textPrimary
                    : context.themeColors.textSecondary,
              ),
            ),
          ),
          if (isConnecting)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: context.themeColors.accentBlue,
              ),
            )
          else if (isConnected)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? context.themeColors.accentBlue
                    : context.themeColors.success,
              ),
            )
          else if (provider.connection.lastFailureFor(server.id)
              case final ConnectionFailure failure?) ...[
            // T10 · 未处置失败条目：error 状态点 + 人话 tooltip。
            Tooltip(
              key: ValueKey('selector_failure_dot_${server.id}'),
              message: l10n.connectFailureLatestTooltip(
                failurePlainMessage(l10n, failure.kind),
              ),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.themeColors.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 选择器按钮壳：全宽、边框、hover 反馈（原型 button 版式）。
class _SelectorButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String tooltip;
  final Widget child;

  const _SelectorButton({this.onTap, required this.tooltip, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space3,
        AppDesignSystem.space1,
        AppDesignSystem.space3,
        0,
      ),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          hoverColor: colors.bgTertiary,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              border: Border.all(color: colors.borderLight),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ChevronsIcon extends StatelessWidget {
  final Color color;

  const _ChevronsIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Icon(LucideIcons.chevronsUpDown, size: 12, color: color);
  }
}
