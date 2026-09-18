// Unit tests for LiteTouchpointGate.
// =============================================================================
// Covers all three gating conditions (kill switch, ≥3 feature-completion
// threshold, per-guide exposure cap), plus persistence of the exposure
// counter.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/services/lite_touchpoint_gate.dart';
import 'package:dbmaster/services/telemetry_service.dart';

void main() {
  late SharedPreferences prefs;
  late SharedPreferences prefsForService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    prefsForService = await SharedPreferences.getInstance();
    // Reset both singletons to a clean state.
    TelemetryService.instance.dispose();
    TelemetryService.instance.testSecureStorage = null;
    TelemetryService.instance.testPrefs = prefsForService;
    TelemetryService.instance.testInstallUuid =
        '33333333-3333-4333-8333-333333333333';
    await TelemetryService.instance.init();

    LiteTouchpointGate.instance.testSkipPersistence = false;
    LiteTouchpointGate.instance.testPrefs = prefs;
    await LiteTouchpointGate.instance.resetForTesting();
  });

  tearDown(() async {
    await LiteTouchpointGate.instance.resetForTesting();
    LiteTouchpointGate.instance.testPrefs = null;
    LiteTouchpointGate.instance.testSkipPersistence = false;
    TelemetryService.instance.dispose();
    await TelemetryService.instance.resetForTesting();
    TelemetryService.instance.testPrefs = null;
    TelemetryService.instance.testInstallUuid = null;
  });

  group('shouldShowLite', () {
    test('false when feature count below threshold', () async {
      final ok = await LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'g1',
        featureId: 'schema_diff_compare',
      );
      expect(ok, isFalse);
    });

    test('true once threshold met, kill switch on, cap not reached', () async {
      TelemetryService.instance.logFeatureUsed('schema_diff_compare');
      TelemetryService.instance.logFeatureUsed('schema_diff_compare');
      TelemetryService.instance.logFeatureUsed('schema_diff_compare');

      final ok = await LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'g1',
        featureId: 'schema_diff_compare',
      );
      expect(ok, isTrue);
    });

    test('false when kill switch off (regardless of feature count)', () async {
      await TelemetryService.instance.setLiteTouchpointEnabled(false);
      for (var i = 0; i < 5; i++) {
        TelemetryService.instance.logFeatureUsed('f');
      }

      final ok = await LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'g2',
        featureId: 'f',
      );
      expect(ok, isFalse);
    });

    test(
        'false after exposure count reaches per-guide lifetime cap (3)',
        () async {
      for (var i = 0; i < 3; i++) {
        TelemetryService.instance.logFeatureUsed('f');
      }
      // Expose 3 times — each call should succeed, then the 4th is gated off.
      for (var i = 0; i < TelemetryService.liteMaxExposuresPerGuide; i++) {
        final ok = await LiteTouchpointGate.instance.shouldShowLite(
          guideId: 'cap-test',
          featureId: 'f',
        );
        expect(ok, isTrue);
        await LiteTouchpointGate.instance.recordExposure('cap-test');
      }

      final fourth = await LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'cap-test',
        featureId: 'f',
      );
      expect(fourth, isFalse,
          reason: 'per-guide lifetime exposure cap (3) must block further renders');
    });

    test('cap is per guideId, not global', () async {
      for (var i = 0; i < 3; i++) {
        TelemetryService.instance.logFeatureUsed('f');
      }
      // Saturate guideId A.
      for (var i = 0; i < TelemetryService.liteMaxExposuresPerGuide; i++) {
        await LiteTouchpointGate.instance.recordExposure('A');
      }
      // guideId B still shows.
      final ok = await LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'B',
        featureId: 'f',
      );
      expect(ok, isTrue);
    });
  });

  group('persistence', () {
    test('exposure counts survive a fresh instance reload', () async {
      for (var i = 0; i < 3; i++) {
        TelemetryService.instance.logFeatureUsed('f');
      }
      await LiteTouchpointGate.instance.recordExposure('persist-test');
      await LiteTouchpointGate.instance.recordExposure('persist-test');

      // Drop the in-memory cache and force a reload from prefs.
      await LiteTouchpointGate.instance.resetForTesting();
      final ok = await LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'persist-test',
        featureId: 'f',
      );
      expect(ok, isTrue, reason: 'cap=3, exposed=2, still allowed');

      // One more exposure hits the cap.
      await LiteTouchpointGate.instance.recordExposure('persist-test');
      await LiteTouchpointGate.instance.resetForTesting();
      final after = await LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'persist-test',
        featureId: 'f',
      );
      expect(after, isFalse);
    });
  });
}
