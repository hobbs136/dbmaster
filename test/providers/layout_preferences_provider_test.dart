import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/services/layout_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LayoutPreferencesProvider', () {
    late LayoutPreferencesProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = LayoutPreferencesProvider();
    });

    group('初始状态', () {
      test('sidebarWidth 应在 min-max 范围内', () {
        expect(
          provider.sidebarWidth,
          greaterThanOrEqualTo(LayoutPreferencesService.minSidebarWidth),
        );
        expect(
          provider.sidebarWidth,
          lessThanOrEqualTo(LayoutPreferencesService.maxSidebarWidth),
        );
      });

      test('editorResultsRatio 应在 0.2-0.8 范围内', () {
        expect(provider.editorResultsRatio, greaterThanOrEqualTo(0.2));
        expect(provider.editorResultsRatio, lessThanOrEqualTo(0.8));
      });

      test('aiPanelWidth 应在 min-max 范围内', () {
        expect(
          provider.aiPanelWidth,
          greaterThanOrEqualTo(LayoutPreferencesService.minAiPanelWidth),
        );
        expect(
          provider.aiPanelWidth,
          lessThanOrEqualTo(LayoutPreferencesService.maxAiPanelWidth),
        );
      });

      test('entityPanelWidth 应在 min-max 范围内', () {
        expect(
          provider.entityPanelWidth,
          greaterThanOrEqualTo(LayoutPreferencesService.minEntityPanelWidth),
        );
        expect(
          provider.entityPanelWidth,
          lessThanOrEqualTo(LayoutPreferencesService.maxEntityPanelWidth),
        );
      });

      test('sidebarCollapsed 应为 false', () {
        expect(provider.sidebarCollapsed, isFalse);
      });

      test('aiPanelFullscreen 应为 false', () {
        expect(provider.aiPanelFullscreen, isFalse);
      });

      test('isLoaded 应为 false', () {
        expect(provider.isLoaded, isFalse);
      });

      test('overlay offsets 应默认为 0', () {
        expect(provider.overlayLeftOffset, 0.0);
        expect(provider.overlayRightOffset, 0.0);
        expect(provider.overlayTopOffset, 0.0);
        expect(provider.overlayBottomOffset, 0.0);
      });

      test('fab offsets 应默认为 0', () {
        expect(provider.fabRightOffset, 0.0);
        expect(provider.fabBottomOffset, 0.0);
      });
    });

    group('setSidebarWidth', () {
      test('应更新 sidebarWidth', () async {
        await provider.setSidebarWidth(350);
        expect(provider.sidebarWidth, 350.0);
      });

      test('超出范围的值应被 clamp', () async {
        await provider.setSidebarWidth(1000);
        expect(provider.sidebarWidth, LayoutPreferencesService.maxSidebarWidth);

        await provider.setSidebarWidth(0);
        expect(provider.sidebarWidth, LayoutPreferencesService.minSidebarWidth);
      });

      test('应触发 notifyListeners', () async {
        var notified = false;
        provider.addListener(() => notified = true);
        await provider.setSidebarWidth(350);
        expect(notified, isTrue);
      });

      test('相同值不应触发 notifyListeners', () async {
        await provider.setSidebarWidth(350);
        var notified = false;
        provider.addListener(() => notified = true);
        await provider.setSidebarWidth(350);
        expect(notified, isFalse);
      });
    });

    group('setEditorResultsRatio', () {
      test('应更新 editorResultsRatio', () async {
        await provider.setEditorResultsRatio(0.7);
        expect(provider.editorResultsRatio, 0.7);
      });

      test('超出范围的值应被 clamp', () async {
        await provider.setEditorResultsRatio(1.5);
        expect(provider.editorResultsRatio, 0.8);

        await provider.setEditorResultsRatio(0.0);
        expect(provider.editorResultsRatio, 0.2);
      });
    });

    group('setSidebarCollapsed', () {
      test('应更新 sidebarCollapsed', () async {
        await provider.setSidebarCollapsed(true);
        expect(provider.sidebarCollapsed, isTrue);
      });

      test('相同值不应触发 notifyListeners', () async {
        var notified = false;
        provider.addListener(() => notified = true);
        await provider.setSidebarCollapsed(false);
        expect(notified, isFalse);
      });
    });

    group('setAiPanelWidth', () {
      test('应更新 aiPanelWidth', () async {
        await provider.setAiPanelWidth(500);
        expect(provider.aiPanelWidth, 500.0);
      });
    });

    group('setEntityPanelWidth', () {
      test('应更新 entityPanelWidth', () async {
        await provider.setEntityPanelWidth(350);
        expect(provider.entityPanelWidth, 350.0);
      });
    });

    group('setAiPanelFullscreen', () {
      test('应更新 aiPanelFullscreen', () async {
        await provider.setAiPanelFullscreen(true);
        expect(provider.aiPanelFullscreen, isTrue);
      });
    });

    group('setOverlayOffsets', () {
      test('应更新所有偏移量', () async {
        await provider.setOverlayOffsets(
          left: 10,
          right: 20,
          top: 30,
          bottom: 40,
        );
        expect(provider.overlayLeftOffset, 10.0);
        expect(provider.overlayRightOffset, 20.0);
        expect(provider.overlayTopOffset, 30.0);
        expect(provider.overlayBottomOffset, 40.0);
      });

      test('相同值不应触发 notifyListeners', () async {
        var notified = false;
        provider.addListener(() => notified = true);
        await provider.setOverlayOffsets(left: 0, right: 0, top: 0, bottom: 0);
        expect(notified, isFalse);
      });
    });

    group('setFabOffsets', () {
      test('应更新 FAB 偏移量', () async {
        await provider.setFabOffsets(right: 16, bottom: 16);
        expect(provider.fabRightOffset, 16.0);
        expect(provider.fabBottomOffset, 16.0);
      });
    });

    group('load', () {
      test('load 后 isLoaded 应为 true', () async {
        await provider.load();
        expect(provider.isLoaded, isTrue);
      });

      test('load 应加载持久化的值', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('sidebar_width', 350.0);
        await prefs.setBool('sidebar_collapsed', true);

        await provider.load();

        expect(provider.sidebarWidth, 350.0);
        expect(provider.sidebarCollapsed, isTrue);
      });
    });
  });
}
