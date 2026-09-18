//! Server-backed DDL approval row (#25 client integration). Mirrors the Rust
//! `DdlApproval` struct from `crates/automation/src/lib.rs` — the read shape
//! returned by the Server's `/api/approvals` endpoints.
//!
//! All fields are scalars (no JSON-encoded columns), so `fromJson` is a flat
//! decode. `reviewer_id` and `resolved_at` are nullable on the Server (set only
//! after approve/reject). The exec columns (`exec_status` / `executed_at` /
//! `exec_error`, migration 009) ride along since U10: `exec_error` carries the
//! redacted target-side reason when `status` = 'failed' — previously the UI
//! could only show the bare word "failed".
//!
//! Status lifecycle (see automation/src/handler.rs):
//!   pending → executing (approve, immediate) → approved | failed (async spawn)
//!   pending → rejected (reject; no execution, no rollback)

/// A DDL change submitted for review. `status` drives both the row badge and
/// the available in-row actions (approve/reject are only valid for `pending`).
class DdlApproval {
  final String id;
  final String submitterId;
  final String ddlSql;
  final String targetDbId;
  final String? reviewerId;
  final String status;
  final String createdAt;
  final String? resolvedAt;

  /// Migration 009 execution tracking; see the library doc. Nullable so wire
  /// payloads from Servers older than U10 still decode.
  final String? execStatus;
  final String? executedAt;
  final String? execError;

  const DdlApproval({
    required this.id,
    required this.submitterId,
    required this.ddlSql,
    required this.targetDbId,
    this.reviewerId,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    this.execStatus,
    this.executedAt,
    this.execError,
  });

  factory DdlApproval.fromJson(Map<String, dynamic> j) {
    return DdlApproval(
      id: j['id'] as String,
      submitterId: (j['submitter_id'] as String?) ?? '',
      ddlSql: (j['ddl_sql'] as String?) ?? '',
      targetDbId: (j['target_db_id'] as String?) ?? '',
      reviewerId: j['reviewer_id'] as String?,
      status: (j['status'] as String?) ?? 'pending',
      createdAt: (j['created_at'] as String?) ?? '',
      resolvedAt: j['resolved_at'] as String?,
      execStatus: j['exec_status'] as String?,
      executedAt: j['executed_at'] as String?,
      execError: j['exec_error'] as String?,
    );
  }

  // ── Status predicates (drive UI state + available actions) ──

  /// Submitted, awaiting a reviewer. Approve or reject are valid.
  bool get isPending => status == 'pending';

  /// Approve was claimed; DDL is being executed by the Server's spawned task.
  /// No client action available — poll until it transitions to approved/failed.
  bool get isExecuting => status == 'executing';

  /// Approved + DDL executed successfully.
  bool get isApproved => status == 'approved';

  /// Approve was claimed but DDL execution failed on the target.
  bool get isFailed => status == 'failed';

  /// Rejected by a reviewer. No DDL was executed.
  bool get isRejected => status == 'rejected';

  /// Terminal states (no further action possible).
  bool get isResolved => isApproved || isFailed || isRejected;

  /// The target-side execution error is present (U10 renders it inline + in
  /// the view-DDL dialog). Empty-string/null both count as absent.
  bool get hasExecError => execError != null && execError!.isNotEmpty;
}
