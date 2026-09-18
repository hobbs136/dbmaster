//! Server-backed saved query (team query library). Mirrors the Rust
//! `SavedQuery` row from `saved_queries` (migrations/002_automation.sql) — the
//! read shape returned by the Server's `/api/queries` endpoints (#4).
//!
//! Distinct from the local `QueryTab` (which models an editor tab with
//! execution state + connection binding): this is the wire shape for team
//! queries, which are workspace-scoped (`workspace_id = "default"`) and
//! cross-connection. `tags` is stored on the Server as a JSON-encoded string
//! column; this model exposes it as a parsed `List<String>`.

import 'dart:convert';

class SavedQuery {
  final String id;
  final String title;
  final String sqlText;
  final List<String> tags;
  final String workspaceId;
  final String createdBy;
  final String createdAt;

  const SavedQuery({
    required this.id,
    required this.title,
    required this.sqlText,
    this.tags = const [],
    this.workspaceId = 'default',
    required this.createdBy,
    required this.createdAt,
  });

  factory SavedQuery.fromJson(Map<String, dynamic> j) {
    // The Server persists `tags` as a JSON-encoded string (e.g.
    // '["foo","bar"]'). Tolerate already-decoded List forms too, for
    // forward-compat + test fixtures.
    Object? tagsRaw = j['tags'];
    if (tagsRaw is String) {
      try {
        tagsRaw = jsonDecode(tagsRaw);
      } catch (_) {
        tagsRaw = null;
      }
    }
    final tags = (tagsRaw is List)
        ? tagsRaw.whereType<String>().toList(growable: false)
        : const <String>[];

    return SavedQuery(
      id: j['id'] as String,
      title: j['title'] as String,
      sqlText: j['sql_text'] as String,
      tags: tags,
      workspaceId: (j['workspace_id'] as String?) ?? 'default',
      createdBy: (j['created_by'] as String?) ?? '',
      createdAt: (j['created_at'] as String?) ?? '',
    );
  }
}
