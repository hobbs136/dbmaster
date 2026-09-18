import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/layout_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LayoutPreferencesService', () {
    late LayoutPreferencesService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = LayoutPreferencesService();
    });

    group('侧边栏宽度', () {
      test('getSidebarWidth 默认值应为 280', () async {
        final width = await service.getSidebarWidth();
        expect(width, 280.0);
      });

      test('setSidebarWidth 后 getSidebarWidth 应返回新值', () async {
        await service.setSidebarWidth(350);
        final width = await service.getSidebarWidth();
        expect(width, 350.0);
      });
    });

    group('编辑器结果比例', () {
      test('getEditorResultsRatio 默认值应为 0.5', () async {
        final ratio = await service.getEditorResultsRatio();
        expect(ratio, 0.5);
      });

      test('setEditorResultsRatio 后应返回新值', () async {
        await service.setEditorResultsRatio(0.7);
        final ratio = await service.getEditorResultsRatio();
        expect(ratio, 0.7);
      });
    });

    group('侧边栏折叠', () {
      test('getSidebarCollapsed 默认值应为 false', () async {
        final collapsed = await service.getSidebarCollapsed();
        expect(collapsed, isFalse);
      });

      test('setSidebarCollapsed(true) 后应返回 true', () async {
        await service.setSidebarCollapsed(true);
        final collapsed = await service.getSidebarCollapsed();
        expect(collapsed, isTrue);
      });
    });

    group('AI 面板宽度', () {
      test('getAiPanelWidth 默认值应为 400', () async {
        final width = await service.getAiPanelWidth();
        expect(width, 400.0);
      });

      test('setAiPanelWidth 后应返回新值', () async {
        await service.setAiPanelWidth(500);
        final width = await service.getAiPanelWidth();
        expect(width, 500.0);
      });
    });

    group('实体面板宽度', () {
      test('getEntityPanelWidth 默认值应为 280', () async {
        final width = await service.getEntityPanelWidth();
        expect(width, 280.0);
      });

      test('setEntityPanelWidth 后应返回新值', () async {
        await service.setEntityPanelWidth(350);
        final width = await service.getEntityPanelWidth();
        expect(width, 350.0);
      });
    });

    group('AI 面板全屏', () {
      test('getAiPanelFullscreen 默认值应为 false', () async {
        final fullscreen = await service.getAiPanelFullscreen();
        expect(fullscreen, isFalse);
      });

      test('setAiPanelFullscreen(true) 后应返回 true', () async {
        await service.setAiPanelFullscreen(true);
        final fullscreen = await service.getAiPanelFullscreen();
        expect(fullscreen, isTrue);
      });
    });

    group('列宽度', () {
      test('getColumnWidths 默认值应返回空 Map', () async {
        final widths = await service.getColumnWidths('table_a');
        expect(widths, isEmpty);
      });

      test('setColumnWidth 后 getColumnWidths 应返回该宽度', () async {
        await service.setColumnWidth('table_a', 'col_1', 200);
        final widths = await service.getColumnWidths('table_a');
        expect(widths['col_1'], 200.0);
      });

      test('不同表的列宽度应独立', () async {
        await service.setColumnWidth('table_a', 'col_1', 200);
        await service.setColumnWidth('table_b', 'col_1', 300);

        final widthsA = await service.getColumnWidths('table_a');
        final widthsB = await service.getColumnWidths('table_b');

        expect(widthsA['col_1'], 200.0);
        expect(widthsB['col_1'], 300.0);
      });
    });

    group('浮层偏移量', () {
      test('getOverlayOffsets 默认值应返回全 0', () async {
        final offsets = await service.getOverlayOffsets();
        expect(offsets['left'], 0.0);
        expect(offsets['right'], 0.0);
        expect(offsets['top'], 0.0);
        expect(offsets['bottom'], 0.0);
      });

      test('setOverlayOffsets 后应返回新值', () async {
        // 先触发版本初始化
        await service.getOverlayOffsets();
        await service.setOverlayOffsets({
          'left': 10,
          'right': 20,
          'top': 30,
          'bottom': 40,
        });
        final offsets = await service.getOverlayOffsets();
        expect(offsets['left'], 10.0);
        expect(offsets['right'], 20.0);
        expect(offsets['top'], 30.0);
        expect(offsets['bottom'], 40.0);
      });
    });

    group('FAB 偏移量', () {
      test('getFabOffsets 默认值应返回全 0', () async {
        final offsets = await service.getFabOffsets();
        expect(offsets['right'], 0.0);
        expect(offsets['bottom'], 0.0);
      });

      test('setFabOffsets 后应返回新值', () async {
        await service.setFabOffsets({'right': 16, 'bottom': 16});
        final offsets = await service.getFabOffsets();
        expect(offsets['right'], 16.0);
        expect(offsets['bottom'], 16.0);
      });
    });
  });
}
