//! AI 工作台会话栏（design-ai-workbench §2.2 / §7.4 会话同源 / §8【二】布局）。
//!
//! 会话列表本体已抽取为共享 [SessionListView]（v2 A2，任务书 §6.2）：rail
//! 内容页 196 窄列与舞台 sessionList 单例 tab 全宽同一组件双形态渲染（v2
//! §8-5 同源）；会话管理语义（新建/切换/删除/改名/撤销）在共享组件内保留。
//!
//! 宽度（design §8【二】 + v2 结果面板第一批 A1）：展开 =
//! `Row[活动条 44 | 内容页 196]`（总宽 `workbenchSessionListWidth` 240 不变，
//! 内容页宽 = 总宽 − `workbenchRailActivityBarWidth` 派生，不设独立 token）；
//! shell 可用宽 < [WorkbenchSessionRail.collapseBreakpoint] 时收纯活动条
//! [AppDesignSystem.workbenchRailActivityBarWidth] 44（断点由
//! `AiWorkbenchShell` 的 LayoutBuilder 判定后经 [collapsed] 传入）。
//!
//! 收窄态路由（R6 接缝，v2 A2）：shell 把舞台控制器经 [stageController]
//! 传入，收窄态活动条点击 → 对应舞台单例 tab 直开（重复点击激活不重复建）：
//! 会话图标 → `openSessions()`（A2）/ 保存的查询图标 → `openSavedQueries()`
//! （A4）/ 历史图标 → `openHistory()`（A3）。展开态活动条点击 = 内容页切换
//! （终态三页：会话 / 保存的查询 / 历史，v2 §7-7）。
//!
//! A5（v2 先行批）：rail 内容页注册为 F6 第二区
//! [WorkbenchFocusZone.railContentPage]——入口 = 页内首个可聚焦元素（经
//! [_firstFocusableDescendant] 元素树遍历：会话页 = 头栏新建钮、历史/保存的
//! 查询页 = 顶行搜索框）；仅展开态注册，收窄态（无内容页）注销。活动条
//! 子组件经 [zoneRegistry] 透传自行注册第一区。

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'workbench_activity_bar.dart';
import 'workbench_focus_zones.dart';
import 'workbench_query_history_view.dart';
import 'workbench_saved_query_list_view.dart';
import 'workbench_session_list_view.dart';
import 'workbench_stage.dart' show WorkbenchStageController;

/// AI 工作台会话栏（会话页承载；页面切换 + 收窄态路由）。
class WorkbenchSessionRail extends StatefulWidget {
  const WorkbenchSessionRail({
    super.key,
    required this.collapsed,
    required this.stageController,
    this.zoneRegistry,
  });

  /// 收窄断点（design §8【二】"workbenchSessionListWidth 240（<900 断点收
  /// 成 44）"）。判定对象是 shell 的可用宽（LayoutBuilder），非窗口宽。
  static const double collapseBreakpoint = 900;

  /// true = 收成纯活动条 [AppDesignSystem.workbenchRailActivityBarWidth] 44
  /// （窄工作区）；false = 展开 `Row[活动条 44 | 内容页 196]` 总宽 240。
  final bool collapsed;

  /// 舞台状态宿主（R6 接缝，v2 A2：shell 注入既有 `_stageController`）——
  /// 收窄态活动条点击经 [WorkbenchStageController.openSessions]（A2）/
  /// [WorkbenchStageController.openSavedQueries]（A4）/
  /// [WorkbenchStageController.openHistory]（A3）开舞台对应单例 tab。
  final WorkbenchStageController stageController;

  /// F6 六区注册表（A5；null = 不注册，既有组件面测试零改动）。本栏登记
  /// rail 内容页区（仅展开态）并透传给活动条（活动条区由其自行登记）。
  final WorkbenchFocusZoneRegistry? zoneRegistry;

  @override
  State<WorkbenchSessionRail> createState() => _WorkbenchSessionRailState();
}

class _WorkbenchSessionRailState extends State<WorkbenchSessionRail> {
  /// 当前活动条页（v2 A1：仅 sessions 一页；A3/A4 追加页后此处承载切换）。
  WorkbenchRailPage _currentPage = WorkbenchRailPage.sessions;

  /// 活动条页序（v2 §7-7 终态 = 会话/保存的查询/历史；A4 落地后即终态）。
  static const List<WorkbenchRailPage> _pages = [
    WorkbenchRailPage.sessions,
    WorkbenchRailPage.savedQueries,
    WorkbenchRailPage.history,
  ];

  /// 内容页定位锚（A5 内容页区入口的遍历根；GlobalKey 跨页切换稳定寻址）。
  final GlobalKey _contentPageKey = GlobalKey(
    debugLabel: 'workbench_rail_content_page',
  );

  /// rail 内容页区聚焦入口（身份稳定闭包：注册/注销成对使用同一实例）。
  late final WorkbenchZoneFocusEntry _contentPageEntry = _focusContentPage;

  @override
  void initState() {
    super.initState();
    _syncZoneRegistration(null);
  }

  @override
  void didUpdateWidget(covariant WorkbenchSessionRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 注册表实例变更（防御）或折叠态翻转：旧表注销、按当前态重登记。
    if (!identical(oldWidget.zoneRegistry, widget.zoneRegistry) ||
        widget.collapsed != oldWidget.collapsed) {
      _syncZoneRegistration(oldWidget.zoneRegistry);
    }
  }

  @override
  void dispose() {
    widget.zoneRegistry?.unregister(
      WorkbenchFocusZone.railContentPage,
      _contentPageEntry,
    );
    super.dispose();
  }

  /// 内容页区注册同步：注册表实例变更时先从旧表注销；展开态注册、收窄态
  /// 注销（无内容页可聚焦——轮转按未注册跳过）。
  void _syncZoneRegistration(WorkbenchFocusZoneRegistry? oldRegistry) {
    if (oldRegistry != null && !identical(oldRegistry, widget.zoneRegistry)) {
      oldRegistry.unregister(
        WorkbenchFocusZone.railContentPage,
        _contentPageEntry,
      );
    }
    final registry = widget.zoneRegistry;
    if (registry == null) return;
    if (widget.collapsed) {
      registry.unregister(
        WorkbenchFocusZone.railContentPage,
        _contentPageEntry,
      );
      return;
    }
    registry.register(WorkbenchFocusZone.railContentPage, _contentPageEntry);
  }

  /// rail 内容页区入口：聚焦内容页首个可聚焦元素。
  bool _focusContentPage() {
    final context = _contentPageKey.currentContext;
    if (context == null) return false;
    final FocusNode? first = _firstFocusableDescendant(context);
    if (first == null) return false;
    first.requestFocus();
    return true;
  }

  /// 在 [anchor] 子树内找首个可聚焦 [FocusNode]（ReadingOrderTraversalPolicy
  /// 的简化投影：按焦点节点矩形 (top, left) 升序——工作台各区内部均为简单
  /// 纵列/横行，该投影与真实遍历序一致）。
  ///
  /// 与 `ai_workbench_shell.dart` 的 `_findEditableState` 同属「壳内私有
  /// 向下遍历辅助」先例：rail 与 stage 各持一份同构实现（两文件均不 import
  /// 对方私有成员；注册表文件保持纯 Dart 不引 widgets）。
  FocusNode? _firstFocusableDescendant(BuildContext anchor) {
    final FocusScopeNode scope = FocusScope.of(anchor);
    final Element anchorElement = anchor as Element;
    FocusNode? best;
    Rect? bestRect;
    for (final FocusNode node in scope.traversalDescendants) {
      final BuildContext? nodeContext = node.context;
      if (nodeContext == null) continue;
      if (!_isWithinSubtree(nodeContext, anchorElement)) continue;
      final rect = node.rect;
      if (bestRect == null ||
          rect.top < bestRect.top ||
          (rect.top == bestRect.top && rect.left < bestRect.left)) {
        best = node;
        bestRect = rect;
      }
    }
    return best;
  }

  /// [context] 是否位于 [ancestor] 子树内。
  static bool _isWithinSubtree(BuildContext context, Element ancestor) {
    if (identical(context, ancestor)) return true;
    var found = false;
    (context as Element).visitAncestorElements((element) {
      if (identical(element, ancestor)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) return _buildCollapsedRail(context);
    return _buildExpandedRail(context);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 展开态（Row[活动条 44 | 内容页 196]，总宽 240 不变）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildExpandedRail(BuildContext context) {
    return Container(
      width: AppDesignSystem.workbenchSessionListWidth,
      color: context.themeColors.bgSecondary,
      child: Row(
        children: [
          WorkbenchActivityBar(
            pages: _pages,
            currentPage: _currentPage,
            onPageSelected: _selectPage,
            zoneRegistry: widget.zoneRegistry,
          ),
          SizedBox(
            key: _contentPageKey,
            // 内容页宽 = 总宽 − 活动条宽（派生算式，不设独立 token；196）。
            width: AppDesignSystem.workbenchSessionListWidth -
                AppDesignSystem.workbenchRailActivityBarWidth,
            // 内容页（v2 A3/A4 起多页切换，终态三页）：会话列表 = 共享
            // SessionListView（A2 抽取，头栏含新建钮）；保存的查询 = 共享
            // SavedQueryListView 196 窄列形态（A4，本地段）；查询历史 = 共享
            // QueryHistoryListView 196 窄列形态（A3）。两类抽屉载入回调绑
            // 舞台 openEditorSlot（R6 接缝）。
            child: switch (_currentPage) {
              WorkbenchRailPage.sessions => SessionListView(showHeader: true),
              WorkbenchRailPage.savedQueries => SavedQueryListView(
                narrow: true,
                onLoadIntoEditor: widget.stageController.openEditorSlot,
              ),
              WorkbenchRailPage.history => QueryHistoryListView(
                narrow: true,
                onLoadIntoEditor: widget.stageController.openEditorSlot,
              ),
            },
          ),
        ],
      ),
    );
  }

  /// 展开态页切换（v2 A1 单页选中态；A3 起承载多页）。
  void _selectPage(WorkbenchRailPage page) {
    if (page == _currentPage) return;
    setState(() => _currentPage = page);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 收窄态（纯活动条 44；旧逐会话图标列随 v2 A1 整体下线）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildCollapsedRail(BuildContext context) {
    // v2 A2（R6 接缝）：收窄态活动条点击 → 舞台对应单例 tab 直开（重复
    // 点击激活不重复建，§8-2）。已知中间态消除：旧收窄图标列的「新建会话」
    // 按钮随列下线后，收窄态新建入口 = 舞台会话列表 tab 头栏
    // （SessionListView showHeader: true）。
    return Container(
      width: AppDesignSystem.workbenchRailActivityBarWidth,
      color: context.themeColors.bgSecondary,
      child: WorkbenchActivityBar(
        pages: _pages,
        currentPage: _currentPage,
        onPageSelected: _openStagePage,
        zoneRegistry: widget.zoneRegistry,
      ),
    );
  }

  /// 收窄态路由（R6 接缝）：活动条图标点击 → 舞台对应单例 tab（A2 会话 /
  /// A3 历史 / A4 保存的查询，同一既有模式）。
  void _openStagePage(WorkbenchRailPage page) {
    switch (page) {
      case WorkbenchRailPage.sessions:
        widget.stageController.openSessions();
      case WorkbenchRailPage.savedQueries:
        widget.stageController.openSavedQueries();
      case WorkbenchRailPage.history:
        widget.stageController.openHistory();
    }
  }
}
