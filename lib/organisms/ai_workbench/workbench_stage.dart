//! AI 工作台舞台（T24，ui 规格 design-ai-agent-ui.md §5 面五）。
//!
//! A2 净新增结构：tab 体系（增删切 / 关闭 / pin 标记 / dirty 标记 /
//! tab 条 32 / tab 标签上限 200）+ 四类内容槽（网格 / 结构卡 / 编辑器槽 /
//! 图表）+ 空态三元素 + 常驻开合控制语义（[WorkbenchStageController.stageVisible]，
//! 由 T27 shell 消费布局，本组件自身不因可见性消失——是否入树由宿主决定）。
//!
//! 单一事实源（ui 规格 §6.3 判定）：[WorkbenchStageController] 持有 tab 集合 /
//! pinned 标记 / 激活态 / 舞台可见性；舞台 tab 条与产物条（T25）是同一集合的
//! 两个投影，产物条不复制数据。状态宿主为 ChangeNotifier（不新建 Provider，
//! T27 shell 装配时创建并注入）。
//!
//! 数值逐字 ui 规格 §5：tab 条 32（底 bgSecondary + 底部 1px divider）/
//! tab 项 [图标 14 + 6 + 标签 12 ellipsis + 6 + 关闭 12]、内边距 h 10、上限宽
//! 200（不设最小宽）/ 激活底 primaryContainer + 200ms 过渡 / 非激活 textSecondary
//! + hover bgTertiary / 未保存 6px accentBlue 点（标签前）/ 内容区 bgPrimary +
//! padding space3 + 无卡框。四类 tab：网格只读消费 result_renderer_plugin 注册表
//! （零契约改动）；结构卡 describe 四件（列/索引/外键/DDL）；编辑器槽载入
//! ReSqlEditor 不自动执行（AC5.2）+ 未保存点 + 关闭确认（AC5.5）；图表复用
//! ChartView 语义，列型不适配 → 内联错误 + [在经典中打开] 出口不弹窗（AC5.3）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../models/execution_result.dart';
import '../../models/result_data_shape.dart';
import '../../models/result_filter.dart'
    show ColumnDataType, ResultFilterService;
import '../../models/sql_statement.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../plugins/bootstrap.dart' show defaultPluginRegistry;
import '../../plugins/plugin_registry.dart';
import '../../plugins/result_renderer_plugin.dart' show ResultRenderContext;
import '../../services/ai/agent/agent_ui_port.dart' show AgentResultRef;
import '../../theme/app_colors.dart';
import '../editor/re_sql_editor.dart';
import '../editor/re_sql_editor_controller.dart';
import '../results/chart_view.dart';

/// 舞台 tab 类型（§5.2 类型图标映射的唯一权威）。
enum WorkbenchStageTabKind { grid, structure, editor, chart }

/// 结构卡内容（describe_table 四件：列 / 索引 / 外键 / DDL）。
///
/// 值对象由 T27 port 实现（`showTableStructure`）从 adapter 取数后组装；
/// 舞台只读消费，不触发任何数据库访问。
class StageStructureData {
  /// 常量构造；字段不可变。
  const StageStructureData({
    required this.tableName,
    required this.columns,
    required this.indexes,
    required this.foreignKeys,
    this.ddl,
  });

  /// 表名（tab 标签默认值）。
  final String tableName;

  /// 列定义（describe 四件之一）。
  final List<DbColumn> columns;

  /// 索引定义（describe 四件之二）。
  final List<DbIndex> indexes;

  /// 外键定义（describe 四件之三）。
  final List<ForeignKey> foreignKeys;

  /// CREATE TABLE 语句（describe 四件之四；null = 无 DDL 段）。
  final String? ddl;
}

/// 舞台 tab 项（不可变值对象；状态变更经 controller copyWith 替换实例，
/// 保证内容槽 didUpdateWidget 的装载/重建判定可靠）。
///
/// 构造私有：tab 只能由 [WorkbenchStageController] 创建（单一事实源）；
/// T25 产物条只读消费字段。编辑器槽的 [dirty] 由内容组件经
/// `markEditorDirty` 回写（文本 ≠ 载入 SQL 即脏）。
@immutable
class WorkbenchStageTab {
  const WorkbenchStageTab._({
    required this.id,
    required this.kind,
    required this.initialSql,
    this.title,
    this.resultRef,
    this.structure,
    this.chartKind,
    this.pinned = false,
    this.dirty = false,
  });

  /// run 内唯一 tab 标识（`stage_tab_<seq>`，controller 单调生成）。
  final String id;

  /// tab 类型。
  final WorkbenchStageTabKind kind;

  /// 标签；null = 渲染层回退类型标签（agentStageTabGrid/Structure/Editor/Chart）。
  final String? title;

  /// 网格 / 图表 tab 的结果引用（内存引用，不复制）。
  final AgentResultRef? resultRef;

  /// 结构卡 tab 的 describe 数据。
  final StageStructureData? structure;

  /// 图表 tab 的请求类型（line/bar/pie/scatter；null = 推荐模式）。
  final String? chartKind;

  /// 编辑器槽的载入 SQL（非编辑器 tab 为空串）。
  final String initialSql;

  /// 钉入产物条标记（§6.3：产物条 = pinned 子集投影）。
  final bool pinned;

  /// 编辑器槽未保存标记（tab 上 6px 点 + 关闭确认的判据，AC5.5）。
  final bool dirty;

  /// 字段替换（controller 内部状态迁移专用）。
  WorkbenchStageTab copyWith({
    String? title,
    String? chartKind,
    String? initialSql,
    bool? pinned,
    bool? dirty,
  }) => WorkbenchStageTab._(
    id: id,
    kind: kind,
    title: title ?? this.title,
    resultRef: resultRef,
    structure: structure,
    chartKind: chartKind ?? this.chartKind,
    initialSql: initialSql ?? this.initialSql,
    pinned: pinned ?? this.pinned,
    dirty: dirty ?? this.dirty,
  );
}

/// 舞台状态单一事实源（ui 规格 §6.3 判定：tab 集合 / pinned 标记 / 激活态 /
/// 舞台可见性；tab 条与产物条两投影消费，产物条不复制数据）。
///
/// 消费方：舞台本体（本文件）、T25 产物条、T27 `agent_ui_port_impl`
/// （AgentUiPort 前五方法的操作目标）。打开语义（§5.3 工具级规则）：
/// openXxx → 舞台可见 + 激活新 tab；`pinArtifact` → 仅钉入，不改可见性。
class WorkbenchStageController extends ChangeNotifier {
  final List<WorkbenchStageTab> _tabs = <WorkbenchStageTab>[];
  int _activeIndex = -1;
  int _seq = 0;
  bool _stageVisible = false;

  // ── 投影（只读）──────────────────────────────────────────────────────

  /// tab 时间序快照（不可变视图；产物条顺序 = 本序 pinned 子集）。
  List<WorkbenchStageTab> get tabs => List.unmodifiable(_tabs);

  /// 当前激活 tab 下标；空舞台 = -1。
  int get activeTabIndex => _activeIndex;

  /// 当前激活 tab；空舞台 = null。
  WorkbenchStageTab? get activeTab =>
      (_activeIndex >= 0 && _activeIndex < _tabs.length)
      ? _tabs[_activeIndex]
      : null;

  /// pinned 子集（时间序；T25 产物条投影数据源）。
  List<WorkbenchStageTab> get pinnedTabs =>
      List.unmodifiable(_tabs.where((t) => t.pinned));

  /// 舞台可见性（断点布局状态；T27 shell 消费：可见 = 对话列固定 360 +
  /// 舞台 Expanded ≥480，不可见 = 对话列 360–760 居中）。
  bool get stageVisible => _stageVisible;

  /// 舞台开合（产物条左端开关 / T25 点项重开舞台的消费入口）。
  void setStageVisible(bool value) {
    if (_stageVisible == value) return;
    _stageVisible = value;
    notifyListeners();
  }

  // ── 打开（自动开舞台 + 激活；§5.3 打开时机）──────────────────────────

  /// 网格 tab：呈现结果引用全量行（行限内）。同 refId 网格 tab 已存在 →
  /// 复用并激活（tab 标题以新值为准），不重复建 tab。
  WorkbenchStageTab openGrid(AgentResultRef ref, String? title) {
    return _openTab(
      kind: WorkbenchStageTabKind.grid,
      title: title,
      resultRef: ref,
      match: (t) =>
          t.kind == WorkbenchStageTabKind.grid &&
          t.resultRef?.refId == ref.refId,
    );
  }

  /// 结构卡 tab：按表名去重（同表重开 = 复用激活）。
  WorkbenchStageTab openStructure(StageStructureData data) {
    return _openTab(
      kind: WorkbenchStageTabKind.structure,
      // 表名即默认标签（比类型标签「结构」信息量高）。
      title: data.tableName,
      structure: data,
      match: (t) =>
          t.kind == WorkbenchStageTabKind.structure &&
          t.structure?.tableName == data.tableName,
    );
  }

  /// 编辑器槽：载入 SQL 不自动执行（AC5.2；执行语义不在本组件）。
  /// AC5.5 槽策略：目标槽（最近一个编辑器槽）有未保存修改 → 新开槽，
  /// 绝不覆盖用户未保存内容；干净则复用装载。
  WorkbenchStageTab openEditorSlot(String sql) {
    for (final tab in _tabs.reversed) {
      if (tab.kind != WorkbenchStageTabKind.editor) continue;
      if (tab.dirty) break; // 目标槽脏 → 走新开槽（AC5.5）
      final reloaded = tab.copyWith(initialSql: sql, dirty: false);
      _tabs[_tabs.indexOf(tab)] = reloaded;
      _activeIndex = _tabs.indexOf(reloaded);
      _stageVisible = true;
      notifyListeners();
      return reloaded;
    }
    return _openTab(
      kind: WorkbenchStageTabKind.editor,
      title: null,
      initialSql: sql,
    );
  }

  /// 图表 tab：同 refId 图表 tab 已存在 → 复用激活（kind 以新请求为准）。
  WorkbenchStageTab openChart(AgentResultRef ref, String? kind) {
    return _openTab(
      kind: WorkbenchStageTabKind.chart,
      title: null,
      resultRef: ref,
      chartKind: kind,
      match: (t) =>
          t.kind == WorkbenchStageTabKind.chart &&
          t.resultRef?.refId == ref.refId,
    );
  }

  /// 产物条钉住（§6.3）：该 ref 无网格 tab → 建一个 pinned 网格 tab；
  /// 已有 → 置 pinned。**不改舞台可见性**（T27 `pinArtifact` 的操作目标）。
  WorkbenchStageTab pinArtifact(AgentResultRef ref, String? label) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      if (t.kind == WorkbenchStageTabKind.grid &&
          t.resultRef?.refId == ref.refId) {
        if (t.pinned && t.title == (label ?? t.title)) return t; // 已钉住：幂等
        final pinnedTab = t.copyWith(title: label ?? t.title, pinned: true);
        _tabs[i] = pinnedTab;
        notifyListeners();
        return pinnedTab;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      kind: WorkbenchStageTabKind.grid,
      title: label,
      resultRef: ref,
      pinned: true,
      initialSql: '',
    );
    _tabs.add(tab);
    // 无 tab 时激活补位；有 tab 时不动激活（钉入不打断当前工作）。
    if (_activeIndex < 0) _activeIndex = 0;
    notifyListeners();
    return tab;
  }

  // ── tab 操作 ─────────────────────────────────────────────────────────

  /// 激活 tab（越界静默忽略）。
  void activateTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// 钉住 / 取消钉住（产物条 × 与右键菜单共用入口）。
  void setPinned(int tabIndex, bool pinned) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    if (_tabs[tabIndex].pinned == pinned) return;
    _tabs[tabIndex] = _tabs[tabIndex].copyWith(pinned: pinned);
    notifyListeners();
  }

  /// 关闭 tab（原始移除；**不含未保存确认**——确认是 UI 语义，由舞台/
  /// shell 层在调用前执行）。关闭后激活态自动补位。
  void closeTab(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    _tabs.removeAt(tabIndex);
    if (_tabs.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    } else if (tabIndex < _activeIndex) {
      _activeIndex--;
    }
    notifyListeners();
  }

  /// 编辑器槽内容组件回写未保存标记（文本 ≠ 载入 SQL 即脏；仅翻转时通知，
  /// 避免每次击键触发全舞台重建）。
  void markEditorDirty(String tabId, bool dirty) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      if (t.id == tabId && t.dirty != dirty) {
        _tabs[i] = t.copyWith(dirty: dirty);
        notifyListeners();
        return;
      }
    }
  }

  // ── 图表适配判定（AC5.3；与 T27 port renderChart 的 outcome 失败同源）──

  /// 列型是否适配图表渲染：至少一列可检出数值列（图表语义的最小公共
  /// 前提——line/bar/pie/scatter 均需数值度量）。空数据不算不适配
  /// （沿 ChartView 既有空态呈现）。
  static bool isChartable(AgentResultRef ref) {
    if (ref.rows.isEmpty || ref.columns.isEmpty) return true;
    for (final column in ref.columns) {
      if (ResultFilterService.detectColumnType(ref.rows, column) ==
          ColumnDataType.numeric) {
        return true;
      }
    }
    return false;
  }

  // ── 内部 ─────────────────────────────────────────────────────────────

  String _nextId() => 'stage_tab_${_seq++}';

  /// 打开通用路径：命中 [match] → 复用激活；否则新建追加激活。均置舞台可见。
  WorkbenchStageTab _openTab({
    required WorkbenchStageTabKind kind,
    required String? title,
    String? chartKind,
    String? initialSql,
    AgentResultRef? resultRef,
    StageStructureData? structure,
    bool Function(WorkbenchStageTab tab)? match,
  }) {
    if (match != null) {
      for (var i = 0; i < _tabs.length; i++) {
        if (!match(_tabs[i])) continue;
        final reused = _tabs[i].copyWith(
          title: title ?? _tabs[i].title,
          chartKind: chartKind ?? _tabs[i].chartKind,
        );
        _tabs[i] = reused;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return reused;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      kind: kind,
      title: title,
      resultRef: resultRef,
      structure: structure,
      chartKind: chartKind,
      initialSql: initialSql ?? '',
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _stageVisible = true;
    notifyListeners();
    return tab;
  }
}

/// 舞台组件：tab 条 32 + 内容区（bgPrimary / padding space3 / 无卡框）。
///
/// 布局断点（≥480 / 对话列 360 固定）由 T27 shell 消费 controller 可见性
/// 状态实现；本组件只保证自身内容在 1024×768 下无溢出（§5.4-1 的舞台侧）。
/// 内容用 IndexedStack 保活——编辑器槽的未保存内容在 tab 切换间不丢（AC5.5
/// 的前提）；网格按虚拟化表格自身滚动，结构卡单滚动区，DDL 块内部滚动。
class WorkbenchStage extends StatefulWidget {
  const WorkbenchStage({
    super.key,
    required this.controller,
    this.registry,
    this.onOpenInClassic,
  });

  /// 舞台状态宿主（T27 shell 创建注入；测试自建）。
  final WorkbenchStageController controller;

  /// 结果渲染器注册表（网格 tab 只读消费；null = `defaultPluginRegistry`）。
  final PluginRegistry? registry;

  /// [在经典中打开] 出口（图表不适配 / 兜底出口用；参数 = 该结果的原 SQL）。
  /// T27 接线 `WorkbenchOpenInClassic.open`；未注入时按钮照常渲染为 no-op
  /// （沿 sql_tool_card 接口预留先例，不禁用不假实现）。
  final void Function(String sql)? onOpenInClassic;

  /// tab 条容器（§5.4-4 高度探针 / §5.4-5 滚动探针目标）。
  static const Key tabBarKey = ValueKey('workbench_stage_tab_bar');

  /// 内容区容器。
  static const Key contentAreaKey = ValueKey('workbench_stage_content');

  /// 空态（§5.4-7 三元素探针目标）。
  static const Key emptyStateKey = ValueKey('workbench_stage_empty');

  /// 图表不适配内联错误块（§5.4-8）。
  static const Key chartMismatchKey = ValueKey(
    'workbench_stage_chart_mismatch',
  );

  /// 图表不适配 [在经典中打开] 出口。
  static const Key openInClassicButtonKey = ValueKey(
    'workbench_stage_open_in_classic',
  );

  /// 单个 tab 项（几何 / 键盘探针用）。
  static Key tabItemKey(String tabId) => ValueKey('workbench_stage_tab_$tabId');

  /// 单个 tab 的关闭钮。
  static Key tabCloseKey(String tabId) =>
      ValueKey('workbench_stage_tab_close_$tabId');

  /// 编辑器槽未保存 6px 点。
  static Key dirtyDotKey(String tabId) =>
      ValueKey('workbench_stage_tab_dirty_$tabId');

  @override
  State<WorkbenchStage> createState() => _WorkbenchStageState();
}

class _WorkbenchStageState extends State<WorkbenchStage> {
  final ScrollController _tabScroll = ScrollController();

  /// 每 tab 焦点节点（roving tabindex；§0.4 / §5.4-5）。
  final Map<String, FocusNode> _tabFocusNodes = {};

  /// 每 tab 定位键（自动滚入视口 + 测试几何探针）。
  final Map<String, GlobalKey> _tabKeys = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // 挂载即有 tab（T27 重装配 / 测试直开）时把激活项滚入视口。
    final active = widget.controller.activeTab;
    if (active != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureTabVisible(active.id),
      );
    }
  }

  @override
  void didUpdateWidget(covariant WorkbenchStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _tabScroll.dispose();
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    _tabFocusNodes.clear();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _pruneTabResources();
    setState(() {});
    // 激活项 / 新开项自动滚入视口（§5.2 溢出规则）——帧后定位（本帧树未建）。
    final active = widget.controller.activeTab;
    if (active != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureTabVisible(active.id),
      );
    }
  }

  /// 清理已关闭 tab 的焦点节点与键。焦点节点延后一帧 dispose（此刻可能仍
  /// attach 在即将卸载的 Focus 上，立即 dispose 触发调试断言）。
  void _pruneTabResources() {
    final liveIds = widget.controller.tabs.map((t) => t.id).toSet();
    final orphanedNodes = <FocusNode>[];
    _tabFocusNodes.removeWhere((id, node) {
      if (liveIds.contains(id)) return false;
      orphanedNodes.add(node);
      return true;
    });
    _tabKeys.removeWhere((id, _) => !liveIds.contains(id));
    if (orphanedNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in orphanedNodes) {
          node.dispose();
        }
      });
    }
  }

  void _ensureTabVisible(String tabId) {
    if (!mounted) return;
    final ctx = _tabKeys[tabId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppDesignSystem.durationNormal,
      curve: AppDesignSystem.curveDefault,
      alignment: 0.5,
    );
  }

  // ── tab 条 ───────────────────────────────────────────────────────────

  Widget _buildTabBar(BuildContext context) {
    final colors = context.themeColors;
    final tabs = widget.controller.tabs;
    return Container(
      key: WorkbenchStage.tabBarKey,
      height: AppDesignSystem.tabBarHeight,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        border: Border(
          bottom: BorderSide(
            color: colors.dividerColor,
            width: AppDesignSystem.tabBarDividerHeight,
          ),
        ),
      ),
      // 非懒构建（SingleChildScrollView + Row）：roving 键盘要能把焦点移到
      // 视口外的 tab（焦点节点/定位键必须在树上），懒列表会漏建——本面 tab
      // 数上界 = agent 运行步数（§5.4-5 的 20 tab 量级），全量构建代价可接受。
      child: SingleChildScrollView(
        controller: _tabScroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tabs.length; i++)
              _buildTabItem(
                context,
                tabs[i],
                i == widget.controller.activeTabIndex,
                i,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(
    BuildContext context,
    WorkbenchStageTab tab,
    bool isActive,
    int index,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final node = _tabFocusNodes.putIfAbsent(
      tab.id,
      () => FocusNode(debugLabel: 'stage_tab_${tab.id}'),
    );
    final tabKey = _tabKeys.putIfAbsent(
      tab.id,
      () => GlobalKey(debugLabel: tab.id),
    );
    return _StageTabItem(
      key: tabKey,
      itemKey: WorkbenchStage.tabItemKey(tab.id),
      tab: tab,
      isActive: isActive,
      focusNode: node,
      tabIndex: index,
      tabCount: widget.controller.tabs.length,
      displayLabel: tab.title ?? _kindLabel(l10n, tab.kind),
      onActivate: () {
        node.requestFocus();
        widget.controller.activateTab(index);
      },
      onRequestClose: () => _requestCloseTab(tab, index),
      onMoveFocus: _focusTab,
      onContextMenu: (position) => _showTabMenu(context, tab, index, position),
    );
  }

  String _kindLabel(AppLocalizations l10n, WorkbenchStageTabKind kind) {
    switch (kind) {
      case WorkbenchStageTabKind.grid:
        return l10n.agentStageTabGrid;
      case WorkbenchStageTabKind.structure:
        return l10n.agentStageTabStructure;
      case WorkbenchStageTabKind.editor:
        return l10n.agentStageTabEditor;
      case WorkbenchStageTabKind.chart:
        return l10n.agentStageTabChart;
    }
  }

  void _focusTab(int index) {
    final tabs = widget.controller.tabs;
    if (index < 0 || index >= tabs.length) return;
    final node = _tabFocusNodes[tabs[index].id];
    node?.requestFocus();
    _ensureTabVisible(tabs[index].id);
  }

  /// 关闭请求：编辑器槽未保存 → 先确认（AC5.5：确认前 tab 不消失），
  /// 其余类型直接关。
  Future<void> _requestCloseTab(WorkbenchStageTab tab, int index) async {
    if (tab.kind == WorkbenchStageTabKind.editor && tab.dirty) {
      final l10n = AppLocalizations.of(context)!;
      final label = tab.title ?? l10n.agentStageTabEditor;
      final discard = await _confirmDiscardEditorClose(context, label);
      if (!discard) return; // 取消 / 遮罩 / Esc：tab 保留
    }
    widget.controller.closeTab(index);
  }

  /// 未保存关闭确认：沿既有 `TabCloseConfirmDialog` 文案语义（标题/正文/
  /// 取消/放弃），但不提供「保存」——舞台编辑器槽无保存目的地（经典 tab
  /// 才有），内容出口是显式复制 / 在经典中打开。
  Future<bool> _confirmDiscardEditorClose(BuildContext context, String label) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Text(
          l10n.unsavedChangesTitle,
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          l10n.tabCloseConfirmMessage(label),
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.discardChanges,
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  /// tab 右键 / 菜单键菜单（沿经典 tab `onSecondaryTapDown` + showMenu 先例）：
  /// [钉入产物条 / 取消钉住]、[关闭]（§5.2）。
  void _showTabMenu(
    BuildContext context,
    WorkbenchStageTab tab,
    int index,
    Offset globalPosition,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      color: colors.bgTertiary,
      items: [
        CompactPopupMenuItem<String>(
          value: 'pin',
          child: Text(
            tab.pinned ? l10n.agentStageTabUnpin : l10n.agentStageTabPin,
          ),
        ),
        CompactPopupMenuItem<String>(
          value: 'close',
          child: Text(l10n.agentStageTabClose),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      if (value == 'pin') {
        widget.controller.setPinned(index, !tab.pinned);
      } else if (value == 'close') {
        _requestCloseTab(tab, index);
      }
    });
  }

  // ── 内容区 ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final controller = widget.controller;
    return Column(
      children: [
        _buildTabBar(context),
        Expanded(
          child: Container(
            key: WorkbenchStage.contentAreaKey,
            color: colors.bgPrimary,
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            child: controller.tabs.isEmpty
                ? _buildEmpty(context)
                : _buildContent(context),
          ),
        ),
      ],
    );
  }

  /// 空态三元素：panelRight 32 textMuted + 「舞台为空」13 textSecondary +
  /// hint 11 textMuted；无插画无按钮（§5.3）。
  Widget _buildEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      key: WorkbenchStage.emptyStateKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.panelRight, size: 32, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.agentStageEmptyTitle,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            l10n.agentStageEmptyHint,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// 四类内容槽（IndexedStack 保活：编辑器未保存内容跨 tab 切换不丢）。
  Widget _buildContent(BuildContext context) {
    final controller = widget.controller;
    final tabs = controller.tabs;
    final index = controller.activeTabIndex.clamp(0, tabs.length - 1);
    return IndexedStack(
      index: index,
      children: [for (final tab in tabs) _buildSlot(context, tab)],
    );
  }

  Widget _buildSlot(BuildContext context, WorkbenchStageTab tab) {
    switch (tab.kind) {
      case WorkbenchStageTabKind.grid:
        return _StageGridContent(tab: tab, registry: widget.registry);
      case WorkbenchStageTabKind.structure:
        return _StageStructureContent(tab: tab);
      case WorkbenchStageTabKind.editor:
        return _StageEditorContent(
          tab: tab,
          stageController: widget.controller,
        );
      case WorkbenchStageTabKind.chart:
        return _StageChartContent(
          tab: tab,
          onOpenInClassic: widget.onOpenInClassic,
        );
    }
  }
}

/// tab 项（§5.2）：[类型图标 14 textSecondary] + 6 + [未保存 6px accentBlue 点
/// （标签前）] + [标签 12 ellipsis] + 6 + [关闭 12]；内边距 h 10；上限宽 200
/// 不设最小宽；激活 primaryContainer（200ms 过渡）/ 非激活透明 + hover
/// bgTertiary；右键菜单 + roving 键盘（←/→/Home/End 移动、Enter/Space 激活、
/// 菜单键弹菜单）。
class _StageTabItem extends StatefulWidget {
  const _StageTabItem({
    super.key,
    required this.itemKey,
    required this.tab,
    required this.isActive,
    required this.focusNode,
    required this.tabIndex,
    required this.tabCount,
    required this.displayLabel,
    required this.onActivate,
    required this.onRequestClose,
    required this.onMoveFocus,
    required this.onContextMenu,
  });

  final Key itemKey;
  final WorkbenchStageTab tab;
  final bool isActive;
  final FocusNode focusNode;

  /// 本 tab 在集合中的下标与集合总数（roving 键盘的目标计算）。
  final int tabIndex;
  final int tabCount;
  final String displayLabel;
  final VoidCallback onActivate;
  final VoidCallback onRequestClose;
  final void Function(int targetIndex) onMoveFocus;
  final void Function(Offset globalPosition) onContextMenu;

  @override
  State<_StageTabItem> createState() => _StageTabItemState();
}

class _StageTabItemState extends State<_StageTabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final active = widget.isActive;
    final tab = widget.tab;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        onTap: widget.onActivate,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: Tooltip(
          // §0.4：tooltip 同时承载 hover 与键盘聚焦（被截断的全文）。
          message: widget.displayLabel,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedContainer(
              key: widget.itemKey,
              duration: AppDesignSystem.durationNormal,
              curve: AppDesignSystem.curveDefault,
              height: AppDesignSystem.tabBarHeight,
              constraints: const BoxConstraints(
                maxWidth: AppDesignSystem.workbenchStageTabMaxWidth,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2_5,
              ),
              decoration: BoxDecoration(
                color: active
                    ? colors.primaryContainer
                    : (_hovered ? colors.bgTertiary : Colors.transparent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _kindIcon(tab.kind),
                    size: 14,
                    color: colors.textSecondary, // §5.2：恒 textSecondary
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  if (tab.dirty) ...[
                    Tooltip(
                      message: l10n.agentStageTabDirty,
                      child: Container(
                        key: WorkbenchStage.dirtyDotKey(tab.id),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.accentBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space1),
                  ],
                  Flexible(
                    child: Text(
                      widget.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeSm,
                        color: active
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  _buildCloseButton(context, tab.id),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context, String tabId) {
    final colors = context.themeColors;
    return InkWell(
      key: WorkbenchStage.tabCloseKey(tabId),
      onTap: widget.onRequestClose,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space0_5,
          vertical: AppDesignSystem.space1,
        ),
        child: Icon(LucideIcons.x, size: 12, color: colors.textMuted),
      ),
    );
  }

  /// roving 键盘（§0.4 / §5.4-5）：←/→ 相邻移动、Home/End 首末、Enter/Space
  /// 激活（tab 行自身持焦点时）、菜单键弹上下文菜单。越界目标由宿主钳制。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onMoveFocus(widget.tabIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onMoveFocus(widget.tabIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      widget.onMoveFocus(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      widget.onMoveFocus(widget.tabCount - 1);
      return KeyEventResult.handled;
    }
    final isActivate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if ((isActivate || key == LogicalKeyboardKey.space) &&
        node.hasPrimaryFocus) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu) {
      final rect = node.rect;
      widget.onContextMenu(Offset(rect.left, rect.bottom));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

IconData _kindIcon(WorkbenchStageTabKind kind) {
  switch (kind) {
    case WorkbenchStageTabKind.grid:
      return LucideIcons.table;
    case WorkbenchStageTabKind.structure:
      return LucideIcons.listTree;
    case WorkbenchStageTabKind.editor:
      return LucideIcons.code;
    case WorkbenchStageTabKind.chart:
      return LucideIcons.chartColumn;
  }
}

/// 列型检测（网格 / 图表槽共用；沿 results_widget `_detectColumnTypes` 口径，
/// 纯静态计算）。采样上限由 detectColumnType 自身保证（500 行）。
Map<String, ColumnDataType> _detectColumnTypes(AgentResultRef ref) {
  final types = <String, ColumnDataType>{};
  for (final column in ref.columns) {
    types[column] = ResultFilterService.detectColumnType(ref.rows, column);
  }
  return types;
}

/// 网格内容槽：只读消费 result_renderer_plugin 注册表（sqlRows 形态注册序
/// 首个 = 默认视图 table 渲染器），零契约改动；容器不套卡框，0 行沿既有
/// 「No data」空态（results_widget 同款）。
class _StageGridContent extends StatefulWidget {
  const _StageGridContent({required this.tab, this.registry});

  final WorkbenchStageTab tab;
  final PluginRegistry? registry;

  @override
  State<_StageGridContent> createState() => _StageGridContentState();
}

class _StageGridContentState extends State<_StageGridContent> {
  Map<String, ColumnDataType> _columnTypes = const {};

  @override
  void initState() {
    super.initState();
    final ref = widget.tab.resultRef;
    if (ref != null) {
      _columnTypes = _detectColumnTypes(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ref = widget.tab.resultRef;
    if (ref == null || ref.rows.isEmpty) {
      return Center(child: Text(l10n.commonNoData));
    }
    final registry = widget.registry ?? defaultPluginRegistry;
    final renderers = registry.resultRenderersFor(
      shape: ResultDataShape.sqlRows,
    );
    if (renderers.isEmpty) {
      return Center(child: Text(l10n.commonError));
    }
    final result = ExecutionResult(
      statement: SQLStatement(
        index: 0,
        sql: ref.sql,
        type: SQLType.select,
        lineStart: 0,
        lineEnd: 0,
      ),
      success: true,
      data: ref.rows,
      executionTime: Duration.zero,
    );
    return renderers.first.build(
      context,
      ResultRenderContext(
        result: result,
        rows: ref.rows,
        columns: ref.columns,
        columnTypes: _columnTypes,
      ),
    );
  }
}

/// 结构卡内容槽（§5.3）：分组标题 11 w600 textMuted（列/索引/外键/DDL）；
/// 数据行 24（workbenchDenseRowHeight）：列名 mono 12 textPrimary + 类型
/// mono 11 textSecondary + 徽标（PK / NN / 默认值，bgTertiary + 11
/// textSecondary）；DDL 块 codeBlockBg / mono 11 / 上限 360 内滚。
/// 单滚动区（结构分组共享一个 SingleChildScrollView，不嵌套外层滚动）。
class _StageStructureContent extends StatelessWidget {
  const _StageStructureContent({required this.tab});

  final WorkbenchStageTab tab;

  @override
  Widget build(BuildContext context) {
    final data = tab.structure;
    if (data == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            context,
            tableColumnsLabel(context),
            data.columns.map((c) => _StructureColumnRow(column: c)),
          ),
          if (data.indexes.isNotEmpty)
            _buildSection(
              context,
              tableIndexesLabel(context),
              data.indexes.map((i) => _StructureIndexRow(index: i)),
            ),
          if (data.foreignKeys.isNotEmpty)
            _buildSection(
              context,
              foreignKeysLabel(context),
              data.foreignKeys.map((f) => _StructureFkRow(foreignKey: f)),
            ),
          if (data.ddl != null && data.ddl!.isNotEmpty)
            _buildDdlSection(context, data.ddl!),
        ],
      ),
    );
  }

  // 分组标签复用既有 l10n key（本任务禁改 ARB）：
  String tableColumnsLabel(BuildContext context) =>
      AppLocalizations.of(context)!.tableColumns;
  String tableIndexesLabel(BuildContext context) =>
      AppLocalizations.of(context)!.tableIndexes;
  String foreignKeysLabel(BuildContext context) =>
      AppLocalizations.of(context)!.sidebarForeignKeys;

  Widget _buildSection(
    BuildContext context,
    String title,
    Iterable<Widget> rows,
  ) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
            child: Text(
              title,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildDdlSection(BuildContext context, String ddl) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
            child: Text(
              l10n.snippetCategoryDDL,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
          ),
          _StructureDdlBlock(ddl: ddl),
        ],
      ),
    );
  }

  /// 结构行徽标：bgTertiary + 11 textSecondary + radiusSm（沿类型徽标语法）。
  static Widget badge(BuildContext context, String text) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: colors.textSecondary,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
      ),
    );
  }
}

/// DDL 块（_buildDdlSection 的正文部分）。
class _StructureDdlBlock extends StatelessWidget {
  const _StructureDdlBlock({required this.ddl});

  final String ddl;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: AppDesignSystem.toolCardContentMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.codeBlockBg,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            ddl,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              height: 1.4,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 列数据行：列名 mono 12 textPrimary + 类型 mono 11 textSecondary +
/// 徽标（PK / NN / 默认值）。
class _StructureColumnRow extends StatelessWidget {
  const _StructureColumnRow({required this.column});

  final DbColumn column;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    return SizedBox(
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              column.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              column.type,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (column.isPrimaryKey) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, 'PK'),
          ],
          if (!column.isNullable) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, 'NN'),
          ],
          if (column.defaultValue != null &&
              column.defaultValue!.isNotEmpty) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, column.defaultValue!),
          ],
        ],
      ),
    );
  }
}

/// 索引数据行：名称 + 列集合 + UNIQUE 徽标（技术字符串不参与 l10n）。
class _StructureIndexRow extends StatelessWidget {
  const _StructureIndexRow({required this.index});

  final DbIndex index;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    return SizedBox(
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              index.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Flexible(
            child: Text(
              index.columns.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (index.isUnique) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, 'UNIQUE'),
          ],
        ],
      ),
    );
  }
}

/// 外键数据行：`列 → 引用表.引用列`。
class _StructureFkRow extends StatelessWidget {
  const _StructureFkRow({required this.foreignKey});

  final ForeignKey foreignKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    return SizedBox(
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              foreignKey.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Flexible(
            child: Text(
              '${foreignKey.column} → '
              '${foreignKey.referencedTable}.${foreignKey.referencedColumn}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 编辑器内容槽：既有 SQL 编辑器组件（ReSqlEditor）载入不自动执行
/// （AC5.2——本组件不含任何执行入口）；未保存判定 = 当前文本 ≠ 载入 SQL，
/// 经 controller 回写 tab.dirty（tab 上 6px 点 + 关闭确认的判据）。
class _StageEditorContent extends StatefulWidget {
  const _StageEditorContent({required this.tab, required this.stageController});

  final WorkbenchStageTab tab;
  final WorkbenchStageController stageController;

  @override
  State<_StageEditorContent> createState() => _StageEditorContentState();
}

class _StageEditorContentState extends State<_StageEditorContent> {
  late final ReSqlEditorController _editor;

  @override
  void initState() {
    super.initState();
    _editor = ReSqlEditorController(text: widget.tab.initialSql);
    _editor.addTextChangeListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _StageEditorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // AC5.5 复用装载：controller 替换实例（initialSql 变化）→ 不可撤销重载
    // （光标归零清历史，沿经典 tab 切换装载语义）。dirty 已在 open 侧归零。
    if (oldWidget.tab.initialSql != widget.tab.initialSql) {
      _editor.loadText(widget.tab.initialSql);
    }
  }

  @override
  void dispose() {
    _editor.removeTextChangeListener(_onTextChanged);
    _editor.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    widget.stageController.markEditorDirty(
      widget.tab.id,
      text != widget.tab.initialSql,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReSqlEditor(controller: _editor);
  }
}

/// 图表内容槽：复用 ChartView（chart_result_renderer 能力语义）；
/// 列型不适配（无数值列，`WorkbenchStageController.isChartable`）→ 内联错误：
/// circleAlert 12 error + agentStageChartMismatch 11 textPrimary +
/// [在经典中打开] 出口（回调注入，T27 接线 WorkbenchOpenInClassic），
/// **不弹窗**（AC5.3）。
class _StageChartContent extends StatelessWidget {
  const _StageChartContent({required this.tab, this.onOpenInClassic});

  final WorkbenchStageTab tab;
  final void Function(String sql)? onOpenInClassic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ref = tab.resultRef;
    if (ref == null || !WorkbenchStageController.isChartable(ref)) {
      return _buildMismatch(context, l10n, ref?.sql ?? '');
    }
    return ChartView(data: ref.rows, columnTypes: _detectColumnTypes(ref));
  }

  Widget _buildMismatch(
    BuildContext context,
    AppLocalizations l10n,
    String sql,
  ) {
    final colors = context.themeColors;
    return Center(
      key: WorkbenchStage.chartMismatchKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.circleAlert, size: 12, color: colors.error),
              const SizedBox(width: AppDesignSystem.space1),
              Flexible(
                child: Text(
                  l10n.agentStageChartMismatch,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          // 出口：icon 12 accentBlue（图形线）+ 文字 textPrimary（§0.2）。
          InkWell(
            key: WorkbenchStage.openInClassicButtonKey,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            onTap: () => onOpenInClassic?.call(sql),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.externalLink,
                    size: 12,
                    color: colors.accentBlue,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Text(
                    l10n.workbenchActionOpenInClassic,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
