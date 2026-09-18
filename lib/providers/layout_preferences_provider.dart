import 'package:flutter/foundation.dart';
import '../services/layout_preferences_service.dart';

enum EditorResultsOrientation { vertical, horizontal }

class LayoutPreferencesProvider extends ChangeNotifier {
  final LayoutPreferencesService _service = LayoutPreferencesService();

  /// 内部服务实例（测试用）
  LayoutPreferencesService get service => _service;

  double _sidebarWidth = LayoutPreferencesService.defaultSidebarWidth;
  double _editorResultsRatio =
      LayoutPreferencesService.defaultEditorResultsRatio;
  double _aiPanelWidth = LayoutPreferencesService.defaultAiPanelWidth;
  double _entityPanelWidth = LayoutPreferencesService.defaultEntityPanelWidth;
  bool _sidebarCollapsed = false;
  bool _aiPanelFullscreen = false;
  bool _isLoaded = false;
  final Map<String, Map<String, double>> _columnWidthsCache = {};

  // AI 浮层偏移量
  double _overlayLeftOffset = 0.0;
  double _overlayRightOffset = 0.0;
  double _overlayTopOffset = 0.0;
  double _overlayBottomOffset = 0.0;

  // AI 浮层自定义尺寸（0 表示未设置）
  double _overlayWidth = LayoutPreferencesService.defaultOverlayWidth;
  double _overlayHeight = LayoutPreferencesService.defaultOverlayHeight;

  // AI 浮层位置（null 表示从未持久化过位置，恢复时按存档尺寸居中）
  double? _overlayLeft;
  double? _overlayTop;

  // FAB 偏移量
  double _fabRightOffset = 0.0;
  double _fabBottomOffset = 0.0;

  // 编辑器/结果分栏方向（plan §3.3：默认左右分栏 horizontal）
  EditorResultsOrientation _editorResultsOrientation =
      EditorResultsOrientation.horizontal;

  double get sidebarWidth => _sidebarWidth.clamp(
    LayoutPreferencesService.minSidebarWidth,
    LayoutPreferencesService.maxSidebarWidth,
  );
  double get editorResultsRatio => _editorResultsRatio.clamp(0.2, 0.8);
  double get aiPanelWidth => _aiPanelWidth.clamp(
    LayoutPreferencesService.minAiPanelWidth,
    LayoutPreferencesService.maxAiPanelWidth,
  );
  double get entityPanelWidth => _entityPanelWidth.clamp(
    LayoutPreferencesService.minEntityPanelWidth,
    LayoutPreferencesService.maxEntityPanelWidth,
  );
  bool get sidebarCollapsed => _sidebarCollapsed;
  bool get aiPanelFullscreen => _aiPanelFullscreen;
  bool get isLoaded => _isLoaded;
  @Deprecated('AI 浮层已去除拖拽调整功能，这些偏移量不再使用')
  double get overlayLeftOffset => _overlayLeftOffset;
  @Deprecated('AI 浮层已去除拖拽调整功能，这些偏移量不再使用')
  double get overlayRightOffset => _overlayRightOffset;
  @Deprecated('AI 浮层已去除拖拽调整功能，这些偏移量不再使用')
  double get overlayTopOffset => _overlayTopOffset;
  @Deprecated('AI 浮层已去除拖拽调整功能，这些偏移量不再使用')
  double get overlayBottomOffset => _overlayBottomOffset;
  double get overlayWidth => _overlayWidth;
  double get overlayHeight => _overlayHeight;

  /// 浮层左缘位置（null = 从未持久化过）
  double? get overlayLeft => _overlayLeft;

  /// 浮层上缘位置（null = 从未持久化过）
  double? get overlayTop => _overlayTop;
  @Deprecated('FAB 已改为固定位置，这些偏移量不再使用')
  double get fabRightOffset => _fabRightOffset;
  @Deprecated('FAB 已改为固定位置，这些偏移量不再使用')
  double get fabBottomOffset => _fabBottomOffset;
  EditorResultsOrientation get editorResultsOrientation =>
      _editorResultsOrientation;

  Future<void> load() async {
    _sidebarWidth = await _service.getSidebarWidth();
    _editorResultsRatio = await _service.getEditorResultsRatio();
    _aiPanelWidth = await _service.getAiPanelWidth();
    _entityPanelWidth = await _service.getEntityPanelWidth();
    _sidebarCollapsed = await _service.getSidebarCollapsed();
    _aiPanelFullscreen = await _service.getAiPanelFullscreen();

    // 加载分栏方向（plan §3.3：默认 horizontal；仅当用户显式存过 vertical 才用 vertical）
    final orientation = await _service.getEditorResultsOrientation();
    _editorResultsOrientation = orientation == 'vertical'
        ? EditorResultsOrientation.vertical
        : EditorResultsOrientation.horizontal;

    // 加载浮层偏移量
    final offsets = await _service.getOverlayOffsets();
    _overlayLeftOffset = offsets['left'] ?? 0.0;
    _overlayRightOffset = offsets['right'] ?? 0.0;
    _overlayTopOffset = offsets['top'] ?? 0.0;
    _overlayBottomOffset = offsets['bottom'] ?? 0.0;

    // 加载浮层自定义尺寸
    _overlayWidth = await _service.getOverlayWidth();
    _overlayHeight = await _service.getOverlayHeight();

    // 加载浮层位置（可为 null：旧版本无位置存档）
    _overlayLeft = await _service.getOverlayLeft();
    _overlayTop = await _service.getOverlayTop();

    // 加载 FAB 偏移量
    final fabOffsets = await _service.getFabOffsets();
    _fabRightOffset = fabOffsets['right'] ?? 0.0;
    _fabBottomOffset = fabOffsets['bottom'] ?? 0.0;

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setSidebarWidth(double width) async {
    final clampedWidth = width.clamp(
      LayoutPreferencesService.minSidebarWidth,
      LayoutPreferencesService.maxSidebarWidth,
    );
    if (_sidebarWidth != clampedWidth) {
      _sidebarWidth = clampedWidth;
      notifyListeners();
      await _service.setSidebarWidth(clampedWidth);
    }
  }

  Future<void> setEditorResultsRatio(double ratio) async {
    final clampedRatio = ratio.clamp(0.2, 0.8);
    if (_editorResultsRatio != clampedRatio) {
      _editorResultsRatio = clampedRatio;
      notifyListeners();
      await _service.setEditorResultsRatio(clampedRatio);
    }
  }

  Future<void> setSidebarCollapsed(bool collapsed) async {
    if (_sidebarCollapsed != collapsed) {
      _sidebarCollapsed = collapsed;
      notifyListeners();
      await _service.setSidebarCollapsed(collapsed);
    }
  }

  Future<void> setAiPanelWidth(double width) async {
    final clampedWidth = width.clamp(
      LayoutPreferencesService.minAiPanelWidth,
      LayoutPreferencesService.maxAiPanelWidth,
    );
    if (_aiPanelWidth != clampedWidth) {
      _aiPanelWidth = clampedWidth;
      notifyListeners();
      await _service.setAiPanelWidth(clampedWidth);
    }
  }

  Future<void> setEntityPanelWidth(double width) async {
    final clampedWidth = width.clamp(
      LayoutPreferencesService.minEntityPanelWidth,
      LayoutPreferencesService.maxEntityPanelWidth,
    );
    if (_entityPanelWidth != clampedWidth) {
      _entityPanelWidth = clampedWidth;
      notifyListeners();
      await _service.setEntityPanelWidth(clampedWidth);
    }
  }

  Future<void> setAiPanelFullscreen(bool fullscreen) async {
    if (_aiPanelFullscreen != fullscreen) {
      _aiPanelFullscreen = fullscreen;
      notifyListeners();
      await _service.setAiPanelFullscreen(fullscreen);
    }
  }

  Future<void> setOverlayWidth(double width) async {
    final clampedWidth = width < LayoutPreferencesService.minOverlayWidth
        ? LayoutPreferencesService.minOverlayWidth
        : width;
    if (_overlayWidth != clampedWidth) {
      _overlayWidth = clampedWidth;
      notifyListeners();
      await _service.setOverlayWidth(clampedWidth);
    }
  }

  Future<void> setOverlayHeight(double height) async {
    final clampedHeight = height < LayoutPreferencesService.minOverlayHeight
        ? LayoutPreferencesService.minOverlayHeight
        : height;
    if (_overlayHeight != clampedHeight) {
      _overlayHeight = clampedHeight;
      notifyListeners();
      await _service.setOverlayHeight(clampedHeight);
    }
  }

  /// 批量持久化浮层几何（位置 + 尺寸），手势结束时调用。
  ///
  /// 单次 [notifyListeners]；宽度/高度按最小尺寸约束，位置原样存储
  /// （可视区约束由浮层侧在写入前完成）。
  Future<void> setOverlayRect({
    required double width,
    required double height,
    required double left,
    required double top,
  }) async {
    final clampedWidth = width < LayoutPreferencesService.minOverlayWidth
        ? LayoutPreferencesService.minOverlayWidth
        : width;
    final clampedHeight = height < LayoutPreferencesService.minOverlayHeight
        ? LayoutPreferencesService.minOverlayHeight
        : height;
    if (_overlayWidth != clampedWidth ||
        _overlayHeight != clampedHeight ||
        _overlayLeft != left ||
        _overlayTop != top) {
      _overlayWidth = clampedWidth;
      _overlayHeight = clampedHeight;
      _overlayLeft = left;
      _overlayTop = top;
      notifyListeners();
      await _service.setOverlayRect(
        width: clampedWidth,
        height: clampedHeight,
        left: left,
        top: top,
      );
    }
  }

  @Deprecated('AI 浮层已简化，不再需要偏移量持久化')
  Future<void> setOverlayOffsets({
    required double left,
    required double right,
    required double top,
    required double bottom,
  }) async {
    if (_overlayLeftOffset != left ||
        _overlayRightOffset != right ||
        _overlayTopOffset != top ||
        _overlayBottomOffset != bottom) {
      _overlayLeftOffset = left;
      _overlayRightOffset = right;
      _overlayTopOffset = top;
      _overlayBottomOffset = bottom;
      notifyListeners();
      await _service.setOverlayOffsets({
        'left': left,
        'right': right,
        'top': top,
        'bottom': bottom,
      });
    }
  }

  @Deprecated('FAB 已改为固定位置，不再需要偏移量持久化')
  Future<void> setFabOffsets({
    required double right,
    required double bottom,
  }) async {
    if (_fabRightOffset != right || _fabBottomOffset != bottom) {
      _fabRightOffset = right;
      _fabBottomOffset = bottom;
      notifyListeners();
      await _service.setFabOffsets({'right': right, 'bottom': bottom});
    }
  }

  Future<void> setEditorResultsOrientation(
    EditorResultsOrientation orientation,
  ) async {
    if (_editorResultsOrientation != orientation) {
      _editorResultsOrientation = orientation;
      notifyListeners();
      await _service.setEditorResultsOrientation(orientation.name);
    }
  }

  Future<void> toggleEditorResultsOrientation() async {
    final next = _editorResultsOrientation == EditorResultsOrientation.vertical
        ? EditorResultsOrientation.horizontal
        : EditorResultsOrientation.vertical;
    await setEditorResultsOrientation(next);
  }

  Future<Map<String, double>> getColumnWidths(String tableKey) async {
    if (_columnWidthsCache.containsKey(tableKey)) {
      return _columnWidthsCache[tableKey]!;
    }
    final widths = await service.getColumnWidths(tableKey);
    _columnWidthsCache[tableKey] = widths;
    return widths;
  }

  Future<void> setColumnWidth(
    String tableKey,
    String columnName,
    double width,
  ) async {
    if (!_columnWidthsCache.containsKey(tableKey)) {
      _columnWidthsCache[tableKey] = {};
    }
    final clampedWidth = width.clamp(
      LayoutPreferencesService.minColumnWidth,
      LayoutPreferencesService.maxColumnWidth,
    );
    _columnWidthsCache[tableKey]![columnName] = clampedWidth;
    notifyListeners();
    await _service.setColumnWidth(tableKey, columnName, clampedWidth);
  }
}
