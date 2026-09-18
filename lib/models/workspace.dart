//! Server-backed workspace + membership models. Mirror the Rust shapes from
//! `crates/core/src/workspace/model.rs` (workspace CRUD/join/leave/members,
//! #26).
//!
//! These are the wire shapes returned by the Server's `/api/workspaces*`
//! endpoints. Unlike the automation routes, workspace endpoints return the
//! payload **directly** (no `{ok,data,error}` envelope); errors come back as
//! `{error:{code,message}}`. See `WorkspaceApiService`.
//!
//! NOTE: this `Workspace` (a Server team/membership concept) is unrelated to
//! the local `MainWorkspace` layout widget in `lib/templates/` — different
//! directory, different concept, no clash.

/// A workspace as returned by `GET /api/workspaces` (list item). Carries the
/// caller's `role` in this workspace (`"admin"` or `"member"`) + the member
/// count, so the list view can show role badges without a detail round-trip.
class Workspace {
  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final int memberCount;
  final String role;
  final String createdAt;

  const Workspace({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    required this.memberCount,
    required this.role,
    required this.createdAt,
  });

  /// `true` when the caller is an admin of this workspace (can delete it and
  /// remove members). The Server writes only `"admin"` / `"member"`.
  bool get isAdmin => role == 'admin';

  factory Workspace.fromJson(Map<String, dynamic> j) {
    return Workspace(
      id: j['id'] as String,
      name: j['name'] as String,
      ownerId: (j['owner_id'] as String?) ?? '',
      inviteCode: (j['invite_code'] as String?) ?? '',
      memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
      role: (j['role'] as String?) ?? 'member',
      createdAt: (j['created_at'] as String?) ?? '',
    );
  }
}

/// A member row from `GET /api/workspaces/:id` (joined with the `users` table
/// for display_name/email).
class WorkspaceMember {
  final String userId;
  final String displayName;
  final String email;
  final String role;
  final String joinedAt;

  const WorkspaceMember({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
    required this.joinedAt,
  });

  bool get isAdmin => role == 'admin';

  factory WorkspaceMember.fromJson(Map<String, dynamic> j) {
    return WorkspaceMember(
      userId: (j['user_id'] as String?) ?? '',
      displayName: (j['display_name'] as String?) ?? '',
      email: (j['email'] as String?) ?? '',
      role: (j['role'] as String?) ?? 'member',
      joinedAt: (j['joined_at'] as String?) ?? '',
    );
  }
}

/// Full workspace detail as returned by `GET /api/workspaces/:id` — the
/// workspace fields plus its full member list.
class WorkspaceDetail {
  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final String createdAt;
  final List<WorkspaceMember> members;

  const WorkspaceDetail({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    required this.createdAt,
    required this.members,
  });

  factory WorkspaceDetail.fromJson(Map<String, dynamic> j) {
    final rawMembers = j['members'];
    final members = (rawMembers is List)
        ? rawMembers
            .whereType<Map<String, dynamic>>()
            .map(WorkspaceMember.fromJson)
            .toList(growable: false)
        : const <WorkspaceMember>[];
    return WorkspaceDetail(
      id: j['id'] as String,
      name: j['name'] as String,
      ownerId: (j['owner_id'] as String?) ?? '',
      inviteCode: (j['invite_code'] as String?) ?? '',
      createdAt: (j['created_at'] as String?) ?? '',
      members: members,
    );
  }
}
