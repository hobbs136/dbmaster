//! Gate for the lite conversion touchpoint variant (D1=B per
//! `telemetry-funnel-plan.md` §1.B).
//!
//! Decides whether to render a lite [ConversionGuideRow] for an unconnected
//! user based on three conditions:
//!   1. The global kill switch is on
//!      ([TelemetryService.liteTouchpointEnabled]).
//!   2. The user has completed the corresponding feature at least
//!      [TelemetryService.liteEligibilityThreshold] times
//!      (rewards repeat users — the target persona).
//!   3. The user has not already seen this specific guide more than
//!      [TelemetryService.liteMaxExposuresPerGuide] times (anti-fatigue).
//!
//! Exposure counts are persisted per (install_uuid × guideId) so that the
//! cap survives app restarts. The install_uuid dimensioning is implicit —
//! the underlying SharedPreferences store is per-install.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'telemetry_service.dart';

class LiteTouchpointGate {
  LiteTouchpointGate._();
  static final LiteTouchpointGate _instance = LiteTouchpointGate._();
  factory LiteTouchpointGate() => _instance;
  static LiteTouchpointGate get instance => _instance;

  static const String _exposureCountPrefKey =
      'telemetry_lite_exposure_counts_v1';

  /// SharedPreferences instance injectable for tests. When null, the gate
  /// lazily resolves the real singleton.
  @visibleForTesting
  SharedPreferences? testPrefs;

  /// When true, persistence is skipped entirely (unit tests that don't touch
  /// SharedPreferences).
  @visibleForTesting
  bool testSkipPersistence = false;

  /// In-memory cache: guideId → lifetime render count.
  final Map<String, int> _exposureCounts = {};
  bool _loaded = false;

  /// True iff the lite touchpoint for [guideId] should render in the current
  /// unconnected state, given the gating feature [featureId].
  ///
  /// Callers must also ensure (caller-side) that the user is NOT currently
  /// connected to a server — the lite variant is exclusively for unconnected
  /// users per `telemetry-funnel-plan.md` §1.B.
  Future<bool> shouldShowLite({
    required String guideId,
    required String featureId,
  }) async {
    await _ensureLoaded();

    final telemetry = TelemetryService.instance;
    if (!telemetry.liteTouchpointEnabled) return false;
    if (!telemetry.isFeatureEligibleForLite(featureId)) return false;
    if ((_exposureCounts[guideId] ?? 0) >=
        TelemetryService.liteMaxExposuresPerGuide) {
      return false;
    }
    return true;
  }

  /// Record that the lite variant for [guideId] was actually rendered.
  /// Call from the touchpoint widget's `initState` (after `shouldShowLite`
  /// returned true), so future renders respect the anti-fatigue cap.
  Future<void> recordExposure(String guideId) async {
    await _ensureLoaded();
    final next = ((_exposureCounts[guideId] ?? 0) + 1).clamp(0, 1 << 30);
    _exposureCounts[guideId] = next;
    if (!testSkipPersistence) await _persist();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || testSkipPersistence) {
      _loaded = true;
      return;
    }
    _loaded = true;
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      final raw = prefs.getString(_exposureCountPrefKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = const JsonCodec().decode(raw);
      if (decoded is Map) {
        _exposureCounts.clear();
        decoded.forEach((k, v) {
          if (k is String && v is int) _exposureCounts[k] = v;
        });
      }
    } catch (e) {
      AppLogger.w('LiteTouchpointGate', 'Failed to load exposure counts: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      await prefs.setString(
        _exposureCountPrefKey,
        const JsonCodec().encode(_exposureCounts),
      );
    } catch (e) {
      AppLogger.w('LiteTouchpointGate', 'Failed to persist exposure counts: $e');
    }
  }

  /// Test helper: reset all state.
  @visibleForTesting
  Future<void> resetForTesting() async {
    _exposureCounts.clear();
    _loaded = false;
  }

  /// Read-only diagnostic accessor.
  @visibleForTesting
  int exposureCount(String guideId) => _exposureCounts[guideId] ?? 0;
}
