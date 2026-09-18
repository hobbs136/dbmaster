//! Workspace members dialog (#26). Shows a workspace's detail (`GET
//! /api/workspaces/:id`): its invite code (with a Copy button that produces an
//! id+code block an admin can forward), the member list, and admin-only member
//! removal.
//!
//! Server constraints the client adapts to (no contract change):
//! - There is NO role-promotion endpoint, so a solo admin cannot hand off and
//!   leave — the Server refuses with 422 BUSINESS_RULE_VIOLATION ("last
//!   admin"). That message is surfaced verbatim.
//! - Only admins can remove members; the Remove button is hidden for
//!   non-admins and for the caller's own row (use Leave from the list dialog).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/workspace.dart';
import '../../../services/server_connection.dart';
import '../../../services/workspace_api_service.dart';
import '../../../theme/app_colors.dart';

/// Shows the members dialog for [workspace]. `workspace` carries the cached
/// role/inviteCode so the header renders before the detail round-trip resolves.
Future<void> showWorkspaceMembersDialog(
  BuildContext context,
  Workspace workspace,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 560,
        height: 560,
        child: _WorkspaceMembersDialog(workspace: workspace),
      ),
    ),
  );
}

class _WorkspaceMembersDialog extends StatefulWidget {
  final Workspace workspace;
  const _WorkspaceMembersDialog({required this.workspace});
  @override
  State<_WorkspaceMembersDialog> createState() =>
      _WorkspaceMembersDialogState();
}

class _WorkspaceMembersDialogState extends State<_WorkspaceMembersDialog> {
  late final WorkspaceApiService _api;
  Future<WorkspaceDetail>? _future;
  final Set<String> _removing = {};
  // Caller's user id, to mark "(you)" and disable self-remove.
  final String? _selfUserId = ServerConnection().userProfile?.id;

  @override
  void initState() {
    super.initState();
    _api = WorkspaceApiService();
    _refresh();
  }

  void _refresh() {
    if (!_api.isConnected) return;
    final future = _api.get(widget.workspace.id);
    // 关闭对话框时在途请求的拒绝无 FutureBuilder 监听者 → unhandled zone
    // error 打到 ErrorBoundary（2026-08-22 灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  /// Copy a forward-friendly block carrying BOTH the workspace id (needed by
  /// join) and the invite code, so an admin can paste it to a teammate.
  Future<void> _copyInvite(String id, String inviteCode) async {
    final block =
        '${widget.workspace.name}\n'
        'ID: $id\n'
        'Invite code: $inviteCode';
    await Clipboard.setData(ClipboardData(text: block));
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.workspacesInviteCopied)));
    }
  }

  Future<void> _removeMember(WorkspaceMember m) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workspacesRemoveMember),
        content: Text(
          l10n.workspacesRemoveMemberConfirm(
            m.displayName.isEmpty
                ? m.email.isEmpty
                      ? m.userId
                      : m.email
                : m.displayName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.workspacesCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.workspacesRemoveMember),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _removing.add(m.userId));
    try {
      await _api.removeMember(widget.workspace.id, m.userId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _removing.remove(m.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final isAdmin = widget.workspace.isAdmin;
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
                  l10n.workspacesMembersTitle(widget.workspace.name),
                  style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                tooltip: l10n.workspacesRefresh,
                onPressed: _refresh,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: AppDesignSystem.space2),
          // Invite code + copy.
          FutureBuilder<WorkspaceDetail>(
            future: _future,
            builder: (context, snapshot) {
              final code =
                  snapshot.data?.inviteCode ?? widget.workspace.inviteCode;
              final id = snapshot.data?.id ?? widget.workspace.id;
              return _inviteCard(id, code, colors);
            },
          ),
          const SizedBox(height: AppDesignSystem.space3),
          // Member list.
          Expanded(
            child: !_api.isConnected
                ? _centeredMessage(l10n.workspacesNotConnected, colors)
                : FutureBuilder<WorkspaceDetail>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        final msg = snapshot.error is WorkspaceApiException
                            ? (snapshot.error as WorkspaceApiException).message
                            : snapshot.error.toString();
                        return _centeredMessage(msg, colors);
                      }
                      final members = snapshot.data?.members ?? const [];
                      if (members.isEmpty) {
                        return _centeredMessage(
                          l10n.workspacesMembersEmpty,
                          colors,
                        );
                      }
                      return ListView.separated(
                        itemCount: members.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: colors.borderSubtle,
                        ),
                        itemBuilder: (context, i) =>
                            _memberRow(members[i], isAdmin, colors),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _inviteCard(String id, String code, ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.accentBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.accentBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.keyRound, size: 18, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.workspacesInviteCode,
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                SelectableText(
                  code,
                  style: AppTextStyles.code.copyWith(
                    fontSize: AppDesignSystem.fontSize3xl,
                    fontWeight: AppDesignSystem.fontWeightBold,
                    letterSpacing: 2,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy, size: 18),
            tooltip: l10n.workspacesCopyInvite,
            onPressed: () => _copyInvite(id, code),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(WorkspaceMember m, bool isAdmin, ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    final isSelf = _selfUserId != null && _selfUserId == m.userId;
    final canRemove = isAdmin && !isSelf;
    final removing = _removing.contains(m.userId);
    final name = m.displayName.isEmpty
        ? (m.email.isEmpty ? m.userId : m.email)
        : m.displayName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: m.isAdmin
                ? colors.warning.withValues(alpha: 0.15)
                : colors.bgTertiary,
            child: Icon(
              m.isAdmin ? LucideIcons.shield : LucideIcons.user,
              size: 16,
              color: m.isAdmin ? colors.warning : colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: AppDesignSystem.fontWeightSemibold,
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 4),
                      Text(
                        l10n.workspacesYou,
                        style: AppTextStyles.caption.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
                if (m.email.isNotEmpty && m.email != name)
                  Text(
                    m.email,
                    style: AppTextStyles.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          // Role badge.
          _roleBadge(m.isAdmin, colors),
          if (removing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (canRemove)
            IconButton(
              icon: Icon(
                LucideIcons.userMinus,
                size: 18,
                color: colors.textSecondary,
              ),
              tooltip: l10n.workspacesRemoveMember,
              onPressed: () => _removeMember(m),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _roleBadge(bool isAdmin, ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
