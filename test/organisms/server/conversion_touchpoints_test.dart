// Widget tests for conversion touchpoints
// =============================================================================
// Tests ConversionGuideRow rendering, dismissal, session persistence, and
// the telemetry wrapper that emits `touchpoint_exposed` / `touchpoint_clicked`
// (telemetry-funnel-plan §4.2).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/organisms/server/conversion_guide_row.dart';
import 'package:dbmaster/services/telemetry_service.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Pump a [ConversionGuideRow] inside a MaterialApp.
Future<void> _pumpGuide(
  WidgetTester tester, {
  required String guideId,
  String title = 'Test Guide',
  String description = 'Description text',
  String actionLabel = 'Learn More',
  IconData icon = LucideIcons.info,
  VoidCallback? onAction,
  bool serverConnected = true,
  ConversionGuideVariant variant = ConversionGuideVariant.full,
  String? actionUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(Colors.blue),
      home: Scaffold(
        body: ConversionGuideRow(
          guideId: guideId,
          icon: icon,
          title: title,
          description: description,
          actionLabel: actionLabel,
          onAction: onAction,
          serverConnected: serverConnected,
          variant: variant,
          actionUrl: actionUrl,
        ),
      ),
    ),
  );
}

/// Builds an initialised, isolated [TelemetryService] for in-process capture.
Future<List<Map<String, Object?>>> _captureTelemetryEvents(
  WidgetTester tester,
  Future<void> Function(TelemetryService) body,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  TelemetryService.instance.dispose();
  TelemetryService.instance.testInstallUuid =
      '44444444-4444-4444-8444-444444444444';
  TelemetryService.instance.testPrefs = prefs;
  TelemetryService.instance.testSkipPersistence = true;
  // Inject a client that always throws on send → service treats each failure
  // as transient (no event removal), so the queue retains every emitted event
  // for assertions.
  TelemetryService.instance.testHttpClient = _AlwaysFailClient();
  await TelemetryService.instance.init();

  await body(TelemetryService.instance);

  // Let the post-frame exposure callback land.
  await tester.pumpAndSettle();
  // Yield extra microtasks so the unawaited _enqueue → _flush chain settles
  // into the "keep in queue (transient failure)" state.
  for (var i = 0; i < 4; i++) {
    await Future.microtask(() {});
  }

  final snapshot = TelemetryService.instance.debugQueueSnapshot;
  TelemetryService.instance.dispose();
  return snapshot;
}

/// HTTP client whose `send` always throws — used to force flush to treat
/// every event as transient so it stays in the queue for assertions.
class _AlwaysFailClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('always fail (test client)');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ConversionGuideRow.resetDismissedGuides();
    TelemetryService.instance.dispose();
    TelemetryService.instance.testInstallUuid = null;
    TelemetryService.instance.testPrefs = null;
  });

  group('ConversionGuideRow — Rendering', () {
    testWidgets('renders icon, title, description, action', (tester) async {
      await _pumpGuide(
        tester,
        guideId: 'g1',
        title: 'Slow Query Reports',
        description: 'Weekly slow query analysis',
        actionLabel: 'Learn More',
      );

      expect(find.text('Slow Query Reports'), findsOneWidget);
      expect(find.text('Weekly slow query analysis'), findsOneWidget);
      expect(find.text('Learn More'), findsOneWidget);
      expect(find.byIcon(LucideIcons.info), findsOneWidget);
    });

    testWidgets('shows close button', (tester) async {
      await _pumpGuide(tester, guideId: 'g2');
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('action button fires callback', (tester) async {
      bool called = false;
      await _pumpGuide(tester, guideId: 'g3', onAction: () => called = true);

      await tester.tap(find.text('Learn More'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('custom icon renders', (tester) async {
      await _pumpGuide(tester, guideId: 'g4', icon: LucideIcons.clock);
      expect(find.byIcon(LucideIcons.clock), findsOneWidget);
    });
  });

  group('ConversionGuideRow — Dismissal', () {
    testWidgets('dismiss removes guide from view', (tester) async {
      await _pumpGuide(tester, guideId: 'dismiss-me', title: 'Dismiss Me');

      expect(find.text('Dismiss Me'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      expect(find.text('Dismiss Me'), findsNothing);
    });

    testWidgets('different guide IDs are independent', (tester) async {
      // Render two guides with DIFFERENT guideIds → dismissing one
      // should leave the other visible.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(Colors.blue),
          home: Scaffold(
            body: Column(
              children: [
                ConversionGuideRow(
                  guideId: 'a',
                  icon: LucideIcons.info,
                  title: 'Guide A',
                  description: 'dA',
                  actionLabel: 'Act',
                ),
                ConversionGuideRow(
                  guideId: 'b',
                  icon: LucideIcons.star,
                  title: 'Guide B',
                  description: 'dB',
                  actionLabel: 'Act',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Guide A'), findsOneWidget);
      expect(find.text('Guide B'), findsOneWidget);

      // Dismiss first guide
      await tester.tap(find.byIcon(LucideIcons.x).first);
      await tester.pump();

      // Guide A gone, Guide B still visible
      expect(find.text('Guide A'), findsNothing);
      expect(find.text('Guide B'), findsOneWidget);
    });
  });

  // Telemetry wrapper coverage (telemetry-funnel-plan §4.2).
  group('ConversionGuideRow — Telemetry wrapper', () {
    testWidgets(
      'fires touchpoint_exposed once on first render (when not dismissed)',
      (tester) async {
        final events = await _captureTelemetryEvents(tester, (_) async {
          await _pumpGuide(tester, guideId: 'tp-exposed');
          await tester.pumpAndSettle();
        });

        final exposedEvents = events
            .where((e) => e['event_type'] == 'touchpoint_exposed')
            .toList();
        expect(exposedEvents, hasLength(1));
        final payload = exposedEvents.single['payload'] as Map<String, Object?>;
        expect(payload['touchpoint_id'], 'tp-exposed');
        expect(payload['server_connected'], true);
      },
    );

    testWidgets('does NOT fire exposure when already dismissed this session', (
      tester,
    ) async {
      ConversionGuideRow.resetDismissedGuides();
      // Pre-dismiss
      await _pumpGuide(tester, guideId: 'tp-skip');
      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink()); // unmount

      final events = await _captureTelemetryEvents(tester, (_) async {
        // Re-pump — the static dismissed set still contains 'tp-skip'.
        await _pumpGuide(tester, guideId: 'tp-skip');
        await tester.pumpAndSettle();
      });

      final exposed = events
          .where((e) => e['event_type'] == 'touchpoint_exposed')
          .toList();
      expect(
        exposed,
        isEmpty,
        reason: 'session-dismissed guides must not emit exposure',
      );
    });

    testWidgets('action tap fires touchpoint_clicked then onAction', (
      tester,
    ) async {
      bool callerCalled = false;
      final events = await _captureTelemetryEvents(tester, (_) async {
        await _pumpGuide(
          tester,
          guideId: 'tp-click',
          onAction: () => callerCalled = true,
          actionUrl: 'https://example.test/x',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Learn More'));
        await tester.pumpAndSettle();
      });

      expect(callerCalled, isTrue, reason: 'onAction must still fire');
      final clicks = events
          .where((e) => e['event_type'] == 'touchpoint_clicked')
          .toList();
      expect(clicks, hasLength(1));
      final payload = clicks.single['payload'] as Map<String, Object?>;
      expect(payload['touchpoint_id'], 'tp-click');
      expect(payload['target_url'], 'https://example.test/x');
    });

    testWidgets('server_connected=false is recorded in the exposure payload', (
      tester,
    ) async {
      final events = await _captureTelemetryEvents(tester, (_) async {
        await _pumpGuide(tester, guideId: 'tp-disc', serverConnected: false);
        await tester.pumpAndSettle();
      });

      final payload =
          events.singleWhere(
                (e) => e['event_type'] == 'touchpoint_exposed',
              )['payload']
              as Map<String, Object?>;
      expect(payload['server_connected'], false);
    });
  });
}
