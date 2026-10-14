//! Shared per-request timeout for the server API service family.
//!
//! Decision D5 (.specs/tasks-sleep-resume-fix.md): ONE shared constant, not
//! per-file literals. 30s follows the repo's existing convention
//! (`ports/gateway_backing.dart` requestTimeout = 30s, `DbGatewayService`
//! 30s/15s), and a single knob keeps future retuning one-point. The eleven
//! `_send` call sites (10 `*_api_service.dart` + `connection_sync_service`)
//! wrap their request await with `.timeout(ApiHttpTimeouts.request)` and map
//! `TimeoutException` onto each service's existing transport error type —
//! no unified envelope/base-class refactor (D5 explicitly rejected it; the
//! services being "structurally mirrored" is the settled architecture, see
//! `dbmaster-flutter/AGENTS.md` §3.1.6).

/// Wall-clock budget for one server API request (send → response headers +
/// body). Error messages carry method + path only — host/DNS details are
/// deliberately excluded (same discipline as `gateway_backing.dart`).
class ApiHttpTimeouts {
  ApiHttpTimeouts._();

  /// Per-request timeout applied by every server API `_send` (D5): 30s.
  ///
  /// Mutable static (not const) so tests can inject a shortened budget.
  /// Production code must only read it, never write. Note: intentionally
  /// NOT annotated `@visibleForTesting` — all 11 consumers are production
  /// cross-file reads, and the annotation would raise an
  /// invalid_use_of_visible_for_testing_member warning at every call site
  /// (same finding as `SseTimeouts` in T3, see `sse_timeout.dart`).
  static Duration request = const Duration(seconds: 30);
}
