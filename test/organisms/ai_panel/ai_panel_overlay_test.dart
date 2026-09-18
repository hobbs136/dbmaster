import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/services/ai/ai_session_manager.dart';
import 'package:dbmaster/organisms/ai_panel/ai_mini_fab.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_overlay.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Regression + feature tests for AiPanelOverlay.
///
/// Covers:
///   - rendering without gray-screen exception
///   - S / M / L preset removal
///   - drag-to-resize on edges / corners (dragged edge follows pointer,
///     opposite edge stays pinned — rendered geometry asserted via getRect)
///   - custom size persistence

/// Rendered rect of the overlay panel (viewport-absolute coordinates).
Rect panelRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('ai_overlay_panel')));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<_TestHarness> pumpHarness(WidgetTester tester) async {
    final app = AppProvider();
    final aiPanel = AiPanelProvider(sessionManager: AiSessionManager());
    final layout = LayoutPreferencesProvider();
    await layout.load();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<AiPanelProvider>.value(value: aiPanel),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layout,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: _Harness(aiPanel: aiPanel),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _TestHarness(app: app, aiPanel: aiPanel, layout: layout);
  }

  testWidgets('AiPanelOverlay renders without gray-screen exception', (
    tester,
  ) async {
    await pumpHarness(tester);

    // FAB visible at start (AI panel is closed).
    expect(find.byType(AiMiniFab), findsOneWidget);

    // Tap the FAB to open the fullscreen overlay.
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    // Overlay should now be on screen.
    expect(find.byType(AiPanelOverlay), findsOneWidget);
  });

  testWidgets('first open uses medium-equivalent default geometry', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    // 1400x900 surface with empty archive: max(400, 1400*0.65)=910 wide,
    // max(300, (900-72)*0.65)=538.2 high, centered with a 9.6px upward nudge.
    final rect = panelRect(tester);
    expect(rect.width, closeTo(910, 0.5));
    expect(rect.height, closeTo(538.2, 0.5));
    expect(rect.left, closeTo(245, 0.5));
    expect(rect.top, closeTo(171.3, 0.5));
  });

  testWidgets('S/M/L preset UI is gone', (tester) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    expect(find.byType(AiPanelOverlay), findsOneWidget);
    expect(find.text('S'), findsNothing);
    expect(find.text('M'), findsNothing);
    expect(find.text('L'), findsNothing);

    // The shortcuts dialog must not contain the preset-size entry either.
    await tester.tap(find.byIcon(LucideIcons.keyboard));
    await tester.pumpAndSettle();
    expect(find.text('S / M / L buttons'), findsNothing);
    expect(find.text('Switch overlay size'), findsNothing);
  });

  testWidgets('drag right edge moves only right edge', (tester) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);
    final handle = find.byKey(const ValueKey('ai_overlay_resize_right'));
    expect(handle, findsOneWidget);

    await tester.drag(handle, const Offset(50, 0));
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.width, closeTo(before.width + 50, 1.0));
    expect(after.left, closeTo(before.left, 0.5));
    expect(after.top, closeTo(before.top, 0.5));
    expect(after.height, closeTo(before.height, 0.5));
  });

  testWidgets('drag top edge moves only top edge, bottom stays pinned', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_top')),
      const Offset(0, -40),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.top, closeTo(before.top - 40, 1.0));
    expect(after.height, closeTo(before.height + 40, 1.0));
    expect(after.bottom, closeTo(before.bottom, 0.5));
    expect(after.left, closeTo(before.left, 0.5));
  });

  testWidgets('drag bottom edge moves only bottom edge, top stays pinned', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_bottom')),
      const Offset(0, 40),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.height, closeTo(before.height + 40, 1.0));
    expect(after.top, closeTo(before.top, 0.5));
    expect(after.left, closeTo(before.left, 0.5));
  });

  testWidgets('drag left edge moves only left edge, right stays pinned', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_left')),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.left, closeTo(before.left - 40, 1.0));
    expect(after.width, closeTo(before.width + 40, 1.0));
    expect(after.right, closeTo(before.right, 0.5));
    expect(after.top, closeTo(before.top, 0.5));
  });

  testWidgets('drag top-left corner keeps bottom-right corner pinned', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_topLeft')),
      const Offset(-30, -20),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.left, closeTo(before.left - 30, 1.0));
    expect(after.top, closeTo(before.top - 20, 1.0));
    expect(after.width, closeTo(before.width + 30, 1.0));
    expect(after.height, closeTo(before.height + 20, 1.0));
    expect(after.right, closeTo(before.right, 0.5));
    expect(after.bottom, closeTo(before.bottom, 0.5));
  });

  testWidgets('drag bottom-right corner moves only bottom and right edges', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_bottomRight')),
      const Offset(60, 40),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.width, closeTo(before.width + 60, 1.0));
    expect(after.height, closeTo(before.height + 40, 1.0));
    expect(after.left, closeTo(before.left, 0.5));
    expect(after.top, closeTo(before.top, 0.5));
  });

  testWidgets('drag top edge beyond min size keeps bottom edge pinned', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    // 500px downward would shrink height below the 300px minimum.
    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_top')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.height, closeTo(300, 0.5));
    expect(after.bottom, closeTo(before.bottom, 0.5));
    expect(after.top, closeTo(before.bottom - 300, 1.0));
  });

  testWidgets('drag left edge beyond min size keeps right edge pinned', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    // 1000px rightward would shrink width below the 400px minimum.
    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_left')),
      const Offset(1000, 0),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.width, closeTo(400, 0.5));
    expect(after.right, closeTo(before.right, 0.5));
    expect(after.left, closeTo(before.right - 400, 1.0));
  });

  testWidgets('toolbar drag moves panel without resizing', (tester) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    await tester.drag(
      find.byIcon(LucideIcons.wandSparkles),
      const Offset(30, 20),
    );
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.left, closeTo(before.left + 30, 1.0));
    expect(after.top, closeTo(before.top + 20, 1.0));
    expect(after.width, closeTo(before.width, 0.5));
    expect(after.height, closeTo(before.height, 0.5));
  });

  testWidgets('window shrink clamps panel into viewport without re-centering', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(const Size(1400, 900)));

    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final before = panelRect(tester);

    // Shrink the surface: default panel (910x538.2 at 245,171.3) overflows
    // on both axes and must be clamped in place — NOT re-centered
    // (re-centering would yield left=45, top=71.3).
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    await tester.pumpAndSettle();

    final after = panelRect(tester);
    expect(after.width, closeTo(before.width, 0.5));
    expect(after.height, closeTo(before.height, 0.5));
    expect(after.left, greaterThanOrEqualTo(0));
    expect(after.top, greaterThanOrEqualTo(0));
    expect(after.right, lessThanOrEqualTo(1000));
    expect(after.bottom, lessThanOrEqualTo(700));
    // Clamped flush to the bottom-right, not re-centered.
    expect(after.left, closeTo(1000 - before.width, 1.0));
    expect(after.top, closeTo(700 - before.height, 1.0));
  });

  testWidgets('overlay geometry is persisted after move and resize', (
    tester,
  ) async {
    final harness = await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_right')),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byIcon(LucideIcons.wandSparkles),
      const Offset(30, 20),
    );
    await tester.pumpAndSettle();

    // Pump another frame to allow async persistence to complete.
    await tester.pump(const Duration(milliseconds: 100));

    final rect = panelRect(tester);
    final savedW = await harness.layout.service.getOverlayWidth();
    final savedH = await harness.layout.service.getOverlayHeight();
    final savedLeft = await harness.layout.service.getOverlayLeft();
    final savedTop = await harness.layout.service.getOverlayTop();
    expect(savedW, closeTo(rect.width, 0.5));
    expect(savedH, closeTo(rect.height, 0.5));
    expect(savedLeft, closeTo(rect.left, 0.5));
    expect(savedTop, closeTo(rect.top, 0.5));
  });

  testWidgets('persisted position and size are restored on reopen', (
    tester,
  ) async {
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('ai_overlay_resize_right')),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byIcon(LucideIcons.wandSparkles),
      const Offset(30, 20),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    final expected = panelRect(tester);

    // Re-pump a fresh harness over the SAME SharedPreferences mock store —
    // simulates closing and reopening the app.
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final restored = panelRect(tester);
    expect(restored.left, closeTo(expected.left, 1.0));
    expect(restored.top, closeTo(expected.top, 1.0));
    expect(restored.width, closeTo(expected.width, 1.0));
    expect(restored.height, closeTo(expected.height, 1.0));
  });

  testWidgets(
    'legacy archive with size only restores centered with saved size',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'overlay_width': 800.0,
        'overlay_height': 500.0,
      });
      await pumpHarness(tester);
      await tester.tap(find.byType(AiMiniFab));
      await tester.pumpAndSettle();

      final rect = panelRect(tester);
      expect(rect.width, closeTo(800, 0.5));
      expect(rect.height, closeTo(500, 0.5));
      expect(rect.left, closeTo((1400 - 800) / 2, 1.0));
      expect(rect.top, closeTo((900 - 500) / 2 - 9.6, 1.0));
    },
  );

  testWidgets('oversized archive is clamped into viewport', (tester) async {
    SharedPreferences.setMockInitialValues({
      'overlay_width': 3000.0,
      'overlay_height': 2000.0,
      'overlay_left': 5000.0,
      'overlay_top': 4000.0,
    });
    await pumpHarness(tester);
    await tester.tap(find.byType(AiMiniFab));
    await tester.pumpAndSettle();

    final rect = panelRect(tester);
    expect(rect.width, lessThanOrEqualTo(1400));
    expect(rect.height, lessThanOrEqualTo(900));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1400));
    expect(rect.bottom, lessThanOrEqualTo(900));
  });
}

class _TestHarness {
  final AppProvider app;
  final AiPanelProvider aiPanel;
  final LayoutPreferencesProvider layout;

  const _TestHarness({
    required this.app,
    required this.aiPanel,
    required this.layout,
  });
}

class _Harness extends StatelessWidget {
  final AiPanelProvider aiPanel;

  const _Harness({required this.aiPanel});

  @override
  Widget build(BuildContext context) {
    // AiMiniFab uses Positioned internally, so it must be a child of a
    // Stack. AiPanelOverlay also must be a child of a Stack.
    return Scaffold(
      body: Stack(
        children: [
          const SizedBox.expand(),
          Consumer<AiPanelProvider>(
            builder: (context, ai, _) {
              if (ai.aiPanelOpen && ai.aiPanelFullscreen) {
                return AiPanelOverlay(
                  onClose: () => ai.closeAiPanel(),
                  onToggleDock: () => ai.toggleAiPanelFullscreen(),
                );
              }
              if (!ai.aiPanelOpen) {
                return AiMiniFab(
                  onTap: () {
                    ai.openAiPanel();
                    ai.setAiPanelFullscreen(true);
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
