//! AI 工作台会话栏（design-ai-workbench §2.2 / §7.4 会话同源 / §8【二】布局；
//! 批3 T7 UI35-310 收窄态路由改版，.specs/tasks-v3.5-ui.md §3-B01）。
//!
//! 会话列表本体已抽取为共享 [SessionListView]（v2 A2，任务书 §6.2）：rail
//! 内容页 196 窄列形态渲染（sessionList/history/savedQueries 退出舞台枚举
//! 后，三抽屉**只**在此承载，v2 §8-5 同源）。
//!
//! 宽度（design §8【二】 + v2 结果面板第一批 A1）：展开 =
//! `Row[活动条 44 | 内容页 196]`（总宽 `workbenchSessionListWidth` 240 不变，
//! 内容页宽 = 总宽 − `workbenchRailActivityBarWidth` 派生，不设独立 token）；
//! shell 可用宽 < [WorkbenchSessionRail.collapseBreakpoint] 时收纯活动条
//! [AppDesignSystem.workbenchRailActivityBarWidth] 44（断点由
//! `AiWorkbenchShell` 的 LayoutBuilder 判定后经 [collapsed] 传入）。
//!
//! 页选择与收窄态路由（批3 UI35-310，行为变更）：当前抽屉页状态**上提**
//! shell（[currentPage] / [onPageSelected]）——活动条点击两态统一上报
//! shell：收窄态点击 = **展开 rail 至 196 并切对应抽屉**（不再开舞台单例
//! tab——openSessionList 类 API 随枚举退役删除）；rail 已展开时点击 = 切
//! 换抽屉页。展开/收窄决策在 shell 侧（`_railForceExpanded` 手势展开覆写）。
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

/// AI 工作台会话栏（会话页承载；页面切换上报）。
class WorkbenchSessionRail extends StatefulWidget {
  const WorkbenchSessionRail({
    super.key,
    required this.collapsed,
    required this.currentPage,
    required this.onPageSelected,
    required this.stageController,
    this.zoneRegistry,
  });

  /// 收窄断点（design §8【二】"workbenchSessionListWidth 240（<900 断点收
  /// 成 44）"）。判定对象是 shell 的可用宽（LayoutBuilder），非窗口宽。
  static const double collapseBreakpoint = 900;

  /// true = 收成纯活动条 [AppDesignSystem.workbenchRailActivityBarWidth] 44
  /// （窄工作区）；false = 展开 `Row[活动条 44 | 内容页 196]` 总宽 240。
  /// 批3 UI35-310：收窄态点击的展开由 shell 覆写本值后重传（rail 自身
  /// 不持展开覆写态）。
  final bool collapsed;

  /// 当前抽屉页（批3 上提 shell：三抽屉只在此承载，页态归 shell）。
  final WorkbenchRailPage currentPage;

  /// 抽屉页选择回调（收窄/展开两态统一上报；收窄态点击的展开决策在
  /// shell 侧）。
  final ValueChanged<WorkbenchRailPage> onPageSelected;

  /// 舞台状态宿主（抽屉载入回调绑 `openEditorSlot` 用——AC5.5 脏槽保护
  /// 既有；收窄态单例 open* 路由已随枚举退役删除）。
  final WorkbenchStageController stageController;

  /// F6 六区注册表（A5；null = 不注册，既有组件面测试零改动）。本栏登记
  /// rail 内容页区（仅展开态）并透传给活动条（活动条区由其自行登记）。
  final WorkbenchFocusZoneRegistry? zoneRegistry;

  @override
  State<WorkbenchSessionRail> createState() => _WorkbenchSessionRailState();
}

class _WorkbenchSessionRailState extends State<WorkbenchSessionRail> {
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
            currentPage: widget.currentPage,
            onPageSelected: widget.onPageSelected,
            zoneRegistry: widget.zoneRegistry,
          ),
          SizedBox(
            key: _contentPageKey,
            // 内容页宽 = 总宽 − 活动条宽（派生算式，不设独立 token；196）。
            width: AppDesignSystem.workbenchSessionListWidth -
                AppDesignSystem.workbenchRailActivityBarWidth,
            // 内容页（三抽屉：批3 起唯一承载面）：会话列表 = 共享
            // SessionListView（A2 抽取，头栏含新建钮）；保存的查询 = 共享
            // SavedQueryListView 196 窄列形态（A4，本地段）；查询历史 = 共享
            // QueryHistoryListView 196 窄列形态（A3）。两类抽屉载入回调绑
            // 舞台 openEditorSlot（AC5.5 脏槽保护既有）。
            child: switch (widget.currentPage) {
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

  // ──────────────────────────────────────────────────────────────────────────
  // 收窄态（纯活动条 44；批3 UI35-310：点击 = 上报 shell 展开 rail 切抽屉）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildCollapsedRail(BuildContext context) {
    // 批3 UI35-310（行为变更）：收窄态活动条点击 → 上报 shell（shell 覆写
    // 展开态 + 切抽屉页），**不再**开舞台单例 tab（openSessions 等 API 随
    // 枚举退役删除）。收窄态新建会话入口 = rail 展开后的会话页头栏
    // （SessionListView showHeader: true）。
    return Container(
      width: AppDesignSystem.workbenchRailActivityBarWidth,
      color: context.themeColors.bgSecondary,
      child: WorkbenchActivityBar(
        pages: _pages,
        currentPage: widget.currentPage,
        onPageSelected: widget.onPageSelected,
        zoneRegistry: widget.zoneRegistry,
      ),
    );
  }
}

/// 活动条页序（v2 §7-7 终态 = 会话/保存的查询/历史）。
const List<WorkbenchRailPage> _pages = [
  WorkbenchRailPage.sessions,
  WorkbenchRailPage.savedQueries,
  WorkbenchRailPage.history,
];
