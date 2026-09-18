//! Workspaces manager dialog (#26) — the main entry from the ServerStatusBar
//! menu. Lists the caller's workspaces, with create / join-by-invite / leave /
//! delete (admin) + a drill-down to per-workspace member management.
//!
//! Read path uses the shared [WorkspaceProvider] cache (kept warm by a 60s
//! timer); mutating actions use a short-lived [WorkspaceApiService] and then
//! refresh the provider. Mirrors the team-query + approval dialog conventions.
//!
//! Scope note: this is workspace lifecycle + membership ONLY. The Server has
//! no per-workspace data scoping (tasks/connections/queries/approvals are not
//! filtered by workspace), so there is deliberately NO "active workspace
//! switcher" here — a switcher would imply filtering that does not exist.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/workspace.dart';
import '../../../providers/workspace_provider.dart';
import '../../../services/workspace_api_service.dart';
import '../../../theme/app_colors.dart';
import 'create_workspace_dialog.dart';
import 'join_workspace_dialog.dart';
import 'workspace_members_dialog.dart';

/// Opens the Workspaces manager dialog.
Future<void> showWorkspaceListDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const Dialog(
      child: SizedBox(width: 640, height: 520, child: _WorkspaceListDialog()),
    ),
  );
}

class _WorkspaceListDialog extends StatefulWidget {
  const _WorkspaceListDialog();
  @override
  State<_WorkspaceListDialog> createState() => _WorkspaceListDialogState();
}

class _WorkspaceListDialogState extends State<_WorkspaceListDialog> {
  late final WorkspaceApiService _api;
  final Set<String> _actionInFlight = {};

  @override
  void initState() {
    super.initState();
    _api = WorkspaceApiService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WorkspaceProvider>().refresh();
    });
  }

  WorkspaceProvider get _provider => context.read<WorkspaceProvider>();

  Future<void> _create() async {
    final ws = await showCreateWorkspaceDialog(context, api: _api);
    if (ws != null && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.workspacesCreated(ws.name))));
      _provider.refresh();
    }
  }

  Future<void> _join() async {
    final ok = await showJoinWorkspaceDialog(context, api: _api);
    if (ok == true && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.workspacesJoined)));
      _provider.refresh();
    }
  }

  Future<void> _leave(Workspace ws) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workspacesLeave),
        content: Text(l10n.workspacesLeaveConfirm(ws.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.workspacesCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.workspacesLeave),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInFlight.add(ws.id));
    try {
      await _api.leave(ws.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.workspacesLeft(ws.name))));
        _provider.refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(ws.id));
    }
  }

  Future<void> _delete(Workspace ws) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workspacesDelete),
        content: Text(l10n.workspacesDeleteConfirm(ws.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.workspacesCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.workspacesDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInFlight.add(ws.id));
    try {
      await _api.delete(ws.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.workspacesDeleted(ws.name))),
        );
        _provider.refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(ws.id));
    }
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = _l10n;
    final provider = context.watch<WorkspaceProvider>();
    final workspaces = provider.workspaces;
    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Row(
            children: [
              Icon(LucideIcons.users, color: colors.accentBlue, size: 18),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  l10n.workspacesTitle,
                  style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.userPlus),
                tooltip: l10n.workspacesJoin,
                onPressed: _join,
              ),
              IconButton(
                icon: const Icon(LucideIcons.circlePlus),
                tooltip: l10n.workspacesCreate,
                onPressed: _create,
              ),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw),
                tooltip: l10n.workspacesRefresh,
                onPressed: () => provider.refresh(),
              ),
            ],
          ),
          const Divider(),
          // D2-B 改口：明示工作空间的实际作用域（成员分组），防止用户误以为
          // 任务/连接/团队查询按工作空间隔离（server 端无此过滤）。
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDesignSystem.space1,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 14, color: colors.textSecondary),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    l10n.workspacesScopeNotice,
                    style: AppTextStyles.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          // List.
          Expanded(
            child: !_api.isConnected
                ? _centeredMessage(l10n.workspacesNotConnected, colors)
                : _body(provider, workspaces, colors),
          ),
        ],
      ),
    );
  }

  Widget _body(
    WorkspaceProvider provider,
    List<Workspace> workspaces,
    ThemeColors colors,
  ) {
    if (provider.isRefreshing && workspaces.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.lastError != null && workspaces.isEmpty) {
      final msg = provider.lastError is WorkspaceApiException
          ? (provider.lastError as WorkspaceApiException).message
          : provider.lastError.toString();
      return _centeredMessage(msg, colors);
    }
    if (workspaces.isEmpty) {
      return _centeredMessage(_l10n.workspacesEmpty, colors);
    }
    return RefreshIndicator(
      onRefresh: () async => provider.refresh(),
      child: ListView.separated(
        itemCount: workspaces.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: colors.borderSubtle,
        ),
        itemBuilder: (context, i) => _workspaceRow(workspaces[i], colors),
      ),
    );
  }

  Widget _workspaceRow(Workspace ws, ThemeColors colors) {
    final l10n = _l10n;
    final inFlight = _actionInFlight.contains(ws.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(LucideIcons.group, size: 18, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ws.name,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: AppDesignSystem.fontWeightSemibold,
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _roleBadge(ws.isAdmin, colors),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.workspacesMemberCount(ws.memberCount),
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (inFlight)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: Icon(LucideIcons.users, size: 18, color: colors.accentBlue),
              tooltip: l10n.workspacesMembers,
              onPressed: () => showWorkspaceMembersDialog(context, ws),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(
                LucideIcons.logOut,
                size: 18,
                color: colors.textSecondary,
              ),
              tooltip: l10n.workspacesLeave,
              onPressed: () => _leave(ws),
              visualDensity: VisualDensity.compact,
            ),
            if (ws.isAdmin)
              IconButton(
                icon: Icon(
                  LucideIcons.trash2,
                  size: 18,
                  color: colors.textSecondary,
                ),
                tooltip: l10n.workspacesDelete,
                onPressed: () => _delete(ws),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ],
      ),
    );
  }

  Widget _roleBadge(bool isAdmin, ThemeColors colors) {
    final l10n = _l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: (isAdmin ? colors.warning : colors.accentBlue).withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: (isAdmin ? colors.warning : colors.accentBlue).withValues(
            alpha: 0.3,
          ),
        ),
      ),
      child: Text(
        isAdmin ? l10n.workspacesRoleAdmin : l10n.workspacesRoleMember,
        style: TextStyle(
          fontSize: 10,
          color: isAdmin ? colors.warning : colors.accentBlue,
          fontWeight: AppDesignSystem.fontWeightSemibold,
        ),
      ),
    );
  }

  /// Centered message in a ListView (RefreshIndicator requires scrollable).
  Widget _centeredMessage(String message, ThemeColors colors) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            child: Text(
              message,
              style: AppTextStyles.body.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
