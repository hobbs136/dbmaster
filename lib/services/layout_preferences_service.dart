import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LayoutPreferencesService {
  static const String _sidebarWidthKey = 'sidebar_width';
  static const String _editorResultsRatioKey = 'editor_results_ratio';
  static const String _sidebarCollapsedKey = 'sidebar_collapsed';
  static const String _columnWidthsPrefixKey = 'column_widths_';
  static const String _aiPanelWidthKey = 'ai_panel_width';
  static const String _aiPanelFullscreenKey = 'ai_panel_fullscreen';
  static const String _entityPanelWidthKey = 'entity_panel_width';
  static const String _overlayLeftOffsetKey = 'overlay_left_offset';
  static const String _overlayRightOffsetKey = 'overlay_right_offset';
  static const String _overlayTopOffsetKey = 'overlay_top_offset';
  static const String _overlayBottomOffsetKey = 'overlay_bottom_offset';
  static const String _overlayWidthKey = 'overlay_width';
  static const String _overlayHeightKey = 'overlay_height';
  static const String _overlayLeftKey = 'overlay_left';
  static const String _overlayTopKey = 'overlay_top';
  static const String _fabRightOffsetKey = 'fab_right_offset';
  static const String _fabBottomOffsetKey = 'fab_bottom_offset';
  static const String _editorResultsOrientationKey =
      'editor_results_orientation';
  static const String _overlayOffsetsVersionKey = 'overlay_offsets_version';
  static const int _currentOverlayOffsetsVersion = 2;

  static const double defaultSidebarWidth = 280.0;
  static const double defaultEditorResultsRatio = 0.5;
  static const double defaultAiPanelWidth = 400.0;
  static const double defaultEntityPanelWidth = 280.0;
  static const double defaultOverlayWidth = 0.0;
  static const double defaultOverlayHeight = 0.0;
  static const double minSidebarWidth = 200.0;
  static const double maxSidebarWidth = 500.0;
  static const double minAiPanelWidth = 300.0;
  static const double maxAiPanelWidth = 600.0;
  static const double minEntityPanelWidth = 200.0;
  static const double maxEntityPanelWidth = 500.0;
  static const double minOverlayWidth = 400.0;
  static const double minOverlayHeight = 300.0;
  static const double defaultColumnWidth = 150.0;
  static const double minColumnWidth = 50.0;
  static const double maxColumnWidth = 600.0;

  Future<double> getSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_sidebarWidthKey) ?? defaultSidebarWidth;
  }

  Future<void> setSidebarWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sidebarWidthKey, width);
  }

  Future<double> getEditorResultsRatio() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_editorResultsRatioKey) ?? defaultEditorResultsRatio;
  }

  Future<void> setEditorResultsRatio(double ratio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_editorResultsRatioKey, ratio);
  }

  Future<bool> getSidebarCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sidebarCollapsedKey) ?? false;
  }

  Future<void> setSidebarCollapsed(bool collapsed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidebarCollapsedKey, collapsed);
  }

  Future<double> getAiPanelWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_aiPanelWidthKey) ?? defaultAiPanelWidth;
  }

  Future<void> setAiPanelWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_aiPanelWidthKey, width);
  }

  Future<double> getEntityPanelWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_entityPanelWidthKey) ?? defaultEntityPanelWidth;
  }

  Future<void> setEntityPanelWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_entityPanelWidthKey, width);
  }

  Future<bool> getAiPanelFullscreen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_aiPanelFullscreenKey) ?? false;
  }

  Future<void> setAiPanelFullscreen(bool fullscreen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiPanelFullscreenKey, fullscreen);
  }

  Future<double> getOverlayWidth() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_overlayWidthKey) ?? defaultOverlayWidth;
  }

  Future<void> setOverlayWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_overlayWidthKey, width);
  }

  Future<double> getOverlayHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_overlayHeightKey) ?? defaultOverlayHeight;
  }

  Future<void> setOverlayHeight(double height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_overlayHeightKey, height);
  }

  /// 浮层左缘位置。返回 null 表示从未持久化过位置（旧版本/全新用户）。
  Future<double?> getOverlayLeft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_overlayLeftKey);
  }

  /// 浮层上缘位置。返回 null 表示从未持久化过位置（旧版本/全新用户）。
  Future<double?> getOverlayTop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_overlayTopKey);
  }

  /// 批量持久化浮层几何（位置 + 尺寸），手势结束时一次性写入。
  Future<void> setOverlayRect({
    required double width,
    required double height,
    required double left,
    required double top,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_overlayWidthKey, width);
    await prefs.setDouble(_overlayHeightKey, height);
    await prefs.setDouble(_overlayLeftKey, left);
    await prefs.setDouble(_overlayTopKey, top);
  }

  Future<Map<String, double>> getOverlayOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getInt(_overlayOffsetsVersionKey) ?? 0;
    if (savedVersion < _currentOverlayOffsetsVersion) {
      await prefs.setInt(
        _overlayOffsetsVersionKey,
        _currentOverlayOffsetsVersion,
      );
      return {'left': 0.0, 'right': 0.0, 'top': 0.0, 'bottom': 0.0};
    }
    return {
      'left': prefs.getDouble(_overlayLeftOffsetKey) ?? 0.0,
      'right': prefs.getDouble(_overlayRightOffsetKey) ?? 0.0,
      'top': prefs.getDouble(_overlayTopOffsetKey) ?? 0.0,
      'bottom': prefs.getDouble(_overlayBottomOffsetKey) ?? 0.0,
    };
  }

  Future<void> setOverlayOffsets(Map<String, double> offsets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_overlayLeftOffsetKey, offsets['left'] ?? 0.0);
    await prefs.setDouble(_overlayRightOffsetKey, offsets['right'] ?? 0.0);
    await prefs.setDouble(_overlayTopOffsetKey, offsets['top'] ?? 0.0);
    await prefs.setDouble(_overlayBottomOffsetKey, offsets['bottom'] ?? 0.0);
  }

  Future<Map<String, double>> getFabOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'right': prefs.getDouble(_fabRightOffsetKey) ?? 0.0,
      'bottom': prefs.getDouble(_fabBottomOffsetKey) ?? 0.0,
    };
  }

  Future<void> setFabOffsets(Map<String, double> offsets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fabRightOffsetKey, offsets['right'] ?? 0.0);
    await prefs.setDouble(_fabBottomOffsetKey, offsets['bottom'] ?? 0.0);
  }

  Future<Map<String, double>> getColumnWidths(String tableKey) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('$_columnWidthsPrefixKey$tableKey');
    if (jsonString == null) return {};
    try {
      final Map<String, dynamic> json = jsonDecode(jsonString);
      return json.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (e) {
      return {};
    }
  }

  Future<void> setColumnWidths(
    String tableKey,
    Map<String, double> widths,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(widths);
    await prefs.setString('$_columnWidthsPrefixKey$tableKey', jsonString);
  }

  Future<String> getEditorResultsOrientation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_editorResultsOrientationKey) ?? 'vertical';
  }

  Future<void> setEditorResultsOrientation(String orientation) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_editorResultsOrientationKey, orientation);
  }

  Future<void> setColumnWidth(
    String tableKey,
    String columnName,
    double width,
  ) async {
    final widths = await getColumnWidths(tableKey);
    widths[columnName] = width.clamp(minColumnWidth, maxColumnWidth);
    await setColumnWidths(tableKey, widths);
  }
}
