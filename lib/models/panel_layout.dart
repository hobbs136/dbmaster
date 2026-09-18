// spec 041: per-tab 面板可见性布局描述 —— 统一三面板状态机。

/// Per-tab 面板可见性布局描述（会话内、不持久化、不进 `QueryTab.toJson`）。
///
/// 描述某 tab 当前渲染哪些区域：SQL 编辑器 / FilterBar / 结果面板。
/// 几何（左右/上下朝向 + 比例）与此正交，仍走全局 `LayoutPreferencesProvider`。
/// 隐藏 = 不渲染（非压成 0 高），由 `EditorResultsSplit` 据本对象决定是否 build 子树。
///
/// 不可变值类：重写 `operator==`/`hashCode` 以支持 `context.select` 精确比较，
/// 仅在值真正变化时触发重建。
class PanelLayout {
  final bool editorVisible;
  final bool filterBarVisible;
  final bool resultsVisible;

  const PanelLayout({
    required this.editorVisible,
    required this.filterBarVisible,
    required this.resultsVisible,
  });

  /// 新建查询 tab 默认：editor 显、FilterBar 隐、results 隐到首次执行。
  static const PanelLayout query = PanelLayout(
    editorVisible: true,
    filterBarVisible: false,
    resultsVisible: false,
  );

  /// 浏览表数据 tab 默认：editor 隐、FilterBar 显、results 隐到自动执行返回。
  static const PanelLayout browse = PanelLayout(
    editorVisible: false,
    filterBarVisible: true,
    resultsVisible: false,
  );

  /// 翻转单个可见位（未传参保留原值）。
  PanelLayout copyWith({
    bool? editorVisible,
    bool? filterBarVisible,
    bool? resultsVisible,
  }) {
    return PanelLayout(
      editorVisible: editorVisible ?? this.editorVisible,
      filterBarVisible: filterBarVisible ?? this.filterBarVisible,
      resultsVisible: resultsVisible ?? this.resultsVisible,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PanelLayout &&
            other.editorVisible == editorVisible &&
            other.filterBarVisible == filterBarVisible &&
            other.resultsVisible == resultsVisible);
  }

  @override
  int get hashCode =>
      Object.hash(editorVisible, filterBarVisible, resultsVisible);
}

/// Tab 创建期布局预设（仅决定 `PanelLayout` 初值，无运行期迁移）。
enum QueryLayoutPreset { query, browse }
