// C14 · 侧边栏能力菜单 —— 分组能力目录的渲染半边（原型
// `sidebar-capability-menu.html`；Q1 快捷面板升级见视角⑦）。
//
// 职责边界（装配见 capability_menu_assembly.dart）：本文件只做渲染与
// 开合态，不判定任何能力——数据来自装配结果（插件合并 + port 门控后的
// 组列表）。无活动连接或装配为空 → 整段隐藏。
//
// Q1（2026-10 工具面板补齐批，feat/db-tooling-completion）：折叠态持久记忆、
// 行级「新建」徽标（[_releaseNewItemIds] 框架侧集合，不改
// SidebarCapabilityItem 契约）、面板局部键盘（Alt+Q 折叠/聚焦全局键 +
// 聚焦后 1~9 直达 / ↑↓ 移动 / Space·Enter 激活）。装配机制零改动。
//
// A42（UIRV-A42，2026-10-25）：能力菜单「入口化 + 向上覆盖抽屉」——树区
// Stack 内 Positioned 底部锚定抽屉（挂载在 sidebar_widget.dart，树布局
// 高度不被扣减），常驻面收缩为 32px 入口行（短标签 + 可见项数 + Alt+Q
// kbd 徽章）；锚定连接名与库型移到入口 tooltip 与抽屉头部（S5 的
// 「连接名主行 + 库型次行」语义保留在抽屉头）。Esc 收起抽屉并归还焦点
// 入口行；折叠记忆沿用 get/setCapabilityMenuCollapsed（collapsed=false
// → 抽屉开），默认展开语义等价保持。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../plugins/bootstrap.dart';
import '../../../providers/app_provider.dart';
import '../../../services/layout_preferences_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/app_logger.dart';
import 'capability_menu_assembly.dart';

/// 展开态抽屉列表体的最大高度（超出滚动）；抽屉为树区上方覆盖层，
/// 不占树布局高度（原型比例）。
const double _kMenuMaxHeight = 264;

/// 入口行高度（32px；A42 规格表「capability entry（space / toolbar）」）。
const double _kEntryRowHeight = 32;

/// Alt+Q 键名提示（技术字符串常量；键名不作 l10n，沿命令面板
/// `_buildShortcutHint('Enter', …)` 先例）。
const String _kAltQHint = 'Alt+Q';

/// 抽屉头部数字直达键段提示（同上，键名技术字符串）。
const String _kDigitHint = '1-9';

/// 2026-10 工具面板补齐批（feat/db-tooling-completion）新增能力项的
/// 「新建」徽标 id 集。批次发布满一个版本周期后可整体清空（清理时机
/// 由架构师确认）。id 与各插件任务书锁定值一致。
const Set<String> _releaseNewItemIds = {
  // W1 已落地（T3 MySQL 4 项 / T4 PG 3 项 / T5 SQLite 3 项）：
  'mysql.variables', 'mysql.maintenance', 'mysql.performance',
  'mysql.backup', 'pg.extension', 'pg.vector', 'pg.maintenance',
  'sqlite.export', 'sqlite.smartImport', 'sqlite.maintain',
  // 后续波次预登记（T8/T10/T11/T12 任务书锁定项 id，queryPlan 已销项）：
  'pg.locks', 'mongo.currentOp', 'mongo.gridfs', 'mongo.explain',
  // 第二程序预登记（T22 集中登记 4 id，消除 R1 的 T18×T20 同文件冲突；
  // 消费任务：T17 分布图 / T18 事件设计器 / T19 外部表 / T20 Redis 备份）：
  'mongo.schemaAnalysis', 'mysql.events', 'pg.foreignTable', 'redis.backup',
};

/// Alt+Q（切换能力面板折叠/展开并聚焦）全局快捷键 → 面板的一次性信号。
/// GlobalShortcutsWrapper 触发（自增计数），[SidebarCapabilityMenu] 监听
/// 消费（开合切换 + 展开时聚焦抽屉面板根）。信号通道收在本文件而不进
/// Provider 层：无连接/装配为空时入口未挂载，信号无人消费自然丢弃
/// （与 SidebarProvider.requestSidebarExpand「重复请求覆盖、消费方只处理
/// 最新」同精神；sidebars Provider 文件不在本批涉及文件清单内）。
final ValueNotifier<int> capabilityPanelToggleSignal = ValueNotifier<int>(0);

/// A42：抽屉开合共享态——入口行与抽屉分体渲染（入口行挂树区下方
/// Column 槽、抽屉挂树区 Stack 覆盖层）的单一事实源。会话级内存 +
/// 折叠记忆持久化（[LayoutPreferencesService.getCapabilityMenuCollapsed]，
/// collapsed=false → 抽屉开）；默认 true = 首帧展开语义等价保持（Q1 现状
/// 默认值不翻转）。
final ValueNotifier<bool> capabilityDrawerOpen = ValueNotifier<bool>(true);

/// Esc 收起抽屉后焦点归还入口行的一次性信号（入口行监听消费，自增计数）。
final ValueNotifier<int> _entryFocusSignal = ValueNotifier<int>(0);

/// Alt+Q 展开后聚焦抽屉面板根的一次性信号（抽屉监听消费，自增计数）。
final ValueNotifier<int> _drawerFocusSignal = ValueNotifier<int>(0);

/// 开合共享写路径（入口行/抽屉头部/Alt+Q 三入口同源）：更新共享态 + 持久
/// 折叠记忆；展开时发抽屉聚焦信号（键盘 1~9/↑↓ 立即可用）。幂等：同值
/// no-op（重复 Alt+Q 信号、头部与入口并发触发不产生二次副作用）。
void _setDrawerOpen(bool open) {
  if (capabilityDrawerOpen.value == open) return;
  capabilityDrawerOpen.value = open;
  unawaited(
    LayoutPreferencesService().setCapabilityMenuCollapsed(!open),
  );
  if (open) _drawerFocusSignal.value++;
}

/// 面板数字直达键位表：主键盘与小键盘 1~9（裸键）。边界：面板项 >9 个时
/// 数字直达仅覆盖前 9 项（跨组连续序号），其余项经 ↑/↓ 可达。
/// （LogicalKeyboardKey 重载 ==，不能作 const 键，故 final。）
final Map<LogicalKeyboardKey, int> _panelDigitKeys =
    <LogicalKeyboardKey, int>{
  LogicalKeyboardKey.digit1: 1,
  LogicalKeyboardKey.digit2: 2,
  LogicalKeyboardKey.digit3: 3,
  LogicalKeyboardKey.digit4: 4,
  LogicalKeyboardKey.digit5: 5,
  LogicalKeyboardKey.digit6: 6,
  LogicalKeyboardKey.digit7: 7,
  LogicalKeyboardKey.digit8: 8,
  LogicalKeyboardKey.digit9: 9,
  LogicalKeyboardKey.numpad1: 1,
  LogicalKeyboardKey.numpad2: 2,
  LogicalKeyboardKey.numpad3: 3,
  LogicalKeyboardKey.numpad4: 4,
  LogicalKeyboardKey.numpad5: 5,
  LogicalKeyboardKey.numpad6: 6,
  LogicalKeyboardKey.numpad7: 7,
  LogicalKeyboardKey.numpad8: 8,
  LogicalKeyboardKey.numpad9: 9,
};

/// 激活当前键盘选中项的按键（Space/Enter；numpadEnter 为桌面小键盘同义键）。
final Set<LogicalKeyboardKey> _panelActivateKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.space,
};

/// 能力菜单 32px 入口行（A42）：短标签「Capabilities」+ 可见项数 +
/// Alt+Q kbd 徽章 + 开合指示箭头；锚定连接名与库型在 tooltip（数据非文案，
/// Tooltip + 省略号沿行级既有溢出模式）。无活动连接/装配空 → 自隐藏。
class SidebarCapabilityMenu extends StatefulWidget {
  const SidebarCapabilityMenu({super.key});

  @override
  State<SidebarCapabilityMenu> createState() => _SidebarCapabilityMenuState();
}

class _SidebarCapabilityMenuState extends State<SidebarCapabilityMenu> {
  /// 入口行焦点（Esc 归还目标；无键盘承接逻辑，仅作焦点锚点）。
  late final FocusNode _entryFocus;

  @override
  void initState() {
    super.initState();
    _entryFocus = FocusNode();
    capabilityPanelToggleSignal.addListener(_onToggleSignal);
    _entryFocusSignal.addListener(_onEntryFocusSignal);
    // 折叠记忆（Q1）：首帧默认展开（共享态默认 true），post-frame 读持久化
    // 值后校正（沿 layout_preferences_service getSidebarCollapsed get/set
    // 对先例）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreExpandedState();
    });
  }

  @override
  void dispose() {
    capabilityPanelToggleSignal.removeListener(_onToggleSignal);
    _entryFocusSignal.removeListener(_onEntryFocusSignal);
    _entryFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreExpandedState() async {
    try {
      final collapsed =
          await LayoutPreferencesService().getCapabilityMenuCollapsed();
      if (!mounted || !collapsed) return;
      capabilityDrawerOpen.value = false;
    } catch (e) {
      // 存储读取失败 = 回退默认展开态（不阻塞渲染）。
      AppLogger.d(
        'SidebarCapabilityMenu',
        'restore capability menu collapsed state failed: $e',
      );
    }
  }

  void _onToggleSignal() {
    if (!mounted) return;
    _setDrawerOpen(!capabilityDrawerOpen.value);
  }

  void _onEntryFocusSignal() {
    // Esc 归还焦点（抽屉发起）；入口未挂载时 context 为空，跳过。
    if (!mounted || _entryFocus.context == null) return;
    _entryFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final server = _resolveServer(provider);
    if (server == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final groups = _assemble(context, provider, server);
    if (groups.isEmpty) return const SizedBox.shrink();

    final visibleCount = [
      for (final group in groups) ...group.items,
    ].length;

    final colors = context.themeColors;
    return Focus(
      focusNode: _entryFocus,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.dividerColor)),
        ),
        child: Tooltip(
          // 锚定连接名 + 库型收进入口 tooltip（数据非文案；A42 条款①）。
          message:
              '${server.name} · ${l10n.sidebarCapabilityTitleWithType(server.type.displayName)}',
          preferBelow: false,
          child: InkWell(
            onTap: () => _setDrawerOpen(!capabilityDrawerOpen.value),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: SizedBox(
              height: _kEntryRowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.layoutGrid,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    // 短标签（沿既有 sidebarCapabilityTitle 键，零新文案）。
                    Expanded(
                      child: Text(
                        l10n.sidebarCapabilityTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppDesignSystem.fontSizeSm,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      '$visibleCount',
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeXs,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    _KbdBadge(label: _kAltQHint),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    AnimatedRotation(
                      turns: capabilityDrawerOpen.value ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        LucideIcons.chevronRight,
                        size: 14,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 能力覆盖抽屉（A42）：挂载在树区 Stack 内 Positioned 底部锚定（入口行
/// 上方），向上覆盖树而不扣减其布局高度。头部 = 连接名主行 + 库型次行
/// （S5 语义保留）+ 数字段提示 + 收起箭头；列表体 max-height 264 内滚，
/// 行级渲染与 Q1 完全同源。面板根 Focus 承接局部键盘（1~9/↑↓/
/// Space·Enter）与 Esc（收起 + 焦点归还入口行）。
class SidebarCapabilityDrawer extends StatefulWidget {
  const SidebarCapabilityDrawer({super.key});

  @override
  State<SidebarCapabilityDrawer> createState() =>
      _SidebarCapabilityDrawerState();
}

class _SidebarCapabilityDrawerState extends State<SidebarCapabilityDrawer> {
  /// 键盘选中项索引（对 [AssembledCapabilityItem] 跨组连续扁平序；-1 = 无选中）。
  /// 仅在抽屉根 Focus 自身持焦时有效（见 [_onPanelFocusChanged]）。
  int _keyboardIndex = -1;

  /// 抽屉面板根焦点（Alt+Q 聚焦 + 局部键盘 onKeyEvent 承接）。initState
  /// 创建（onKeyEvent 需实例方法），dispose 释放——赋值先于一切使用。
  late final FocusNode _panelFocus;

  /// 最近一次 build 的可见项扁平序缓存（跨组连续序号 = 键盘导航的事实源；
  /// 装配在 build 内完成，handler 复用同序，避免二次装配漂移）。
  List<AssembledCapabilityItem> _visibleItems = const [];

  @override
  void initState() {
    super.initState();
    _panelFocus = FocusNode(onKeyEvent: _handlePanelKey);
    _drawerFocusSignal.addListener(_onDrawerFocusSignal);
    _panelFocus.addListener(_onPanelFocusChanged);
  }

  @override
  void dispose() {
    _drawerFocusSignal.removeListener(_onDrawerFocusSignal);
    _panelFocus.removeListener(_onPanelFocusChanged);
    _panelFocus.dispose();
    super.dispose();
  }

  void _onDrawerFocusSignal() {
    // Alt+Q 展开后聚焦面板根。面板根 Focus 常驻挂载（关态仅内容收缩，
    // 见 build 注），可直接聚焦；焦点应用经 FocusManager 微任务，下一帧
    // 生效。抽屉自隐藏（无连接/装配空）时 Focus 无内容但节点仍在树，
    // 聚焦无害。
    if (!mounted || !capabilityDrawerOpen.value) return;
    _panelFocus.requestFocus();
  }

  /// 键盘选中态仅在抽屉根自身持焦时有效；primary 焦点移出本节点（点击行 →
  /// InkWell 行内 Focus 接管，或焦点离开面板）即清除，避免 Space/Enter 与
  /// 行内 InkWell 激活双触发。
  void _onPanelFocusChanged() {
    final primary = FocusManager.instance.primaryFocus;
    if (_keyboardIndex != -1 && primary != _panelFocus) {
      setState(() => _keyboardIndex = -1);
    }
  }

  /// 抽屉局部键盘（scope = panel，登记于 shortcut_bindings.dart）：Esc 收起
  /// 并归还焦点入口行；聚焦后 1~9 直达可见项（跨组连续序号）、↑/↓ 项间
  /// 移动、Space/Enter 激活当前项。
  KeyEventResult _handlePanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _setDrawerOpen(false);
      _entryFocusSignal.value++;
      return KeyEventResult.handled;
    }
    return _consumePanelKey(event);
  }

  KeyEventResult _consumePanelKey(KeyEvent event) {
    final items = _visibleItems;
    if (items.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;

    final digit = _panelDigitKeys[key];
    if (digit != null) {
      // 边界：序号超过可见项数 = 忽略；>9 项经 ↑/↓ 可达（见键位表注）。
      final index = digit - 1;
      if (index >= items.length) return KeyEventResult.ignored;
      _keyboardIndex = index;
      _activateItem(items[index]);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() {
        if (_keyboardIndex < 0 || _keyboardIndex >= items.length) {
          _keyboardIndex = delta > 0 ? 0 : items.length - 1;
        } else {
          _keyboardIndex = (_keyboardIndex + delta).clamp(0, items.length - 1);
        }
      });
      return KeyEventResult.handled;
    }

    if (_panelActivateKeys.contains(key) &&
        _keyboardIndex >= 0 &&
        _keyboardIndex < items.length) {
      _activateItem(items[_keyboardIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _activateItem(AssembledCapabilityItem entry) {
    final action = entry.item.onActivate;
    if (action == null) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    // 面板根 Focus 常驻挂载（关态仅内容收缩为 shrink）：Alt+Q 展开信号
    // 可同帧聚焦，免 post-frame 二段延迟（focus 归还/局部键盘时序更确定）。
    return Focus(
      focusNode: _panelFocus,
      child: ValueListenableBuilder<bool>(
        valueListenable: capabilityDrawerOpen,
        builder: (context, open, _) {
          if (!open) return const SizedBox.shrink();
          final provider = context.watch<AppProvider>();
          final server = _resolveServer(provider);
          if (server == null) return const SizedBox.shrink();

          final groups = _assemble(context, provider, server);
          if (groups.isEmpty) return const SizedBox.shrink();

          // 可见项扁平序缓存（键盘导航事实源，见 _visibleItems 注）。
          _visibleItems = [
            for (final group in groups) ...group.items,
          ];

          final colors = context.themeColors;
          return Container(
            // 抽屉表面（A42 规格表：bgTertiary + borderLight + radiusMd）。
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              border: Border(
                top: BorderSide(color: colors.borderLight),
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppDesignSystem.radiusMd),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDrawerHeader(context, colors, server),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: _kMenuMaxHeight,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      AppDesignSystem.space2,
                      0,
                      AppDesignSystem.space2,
                      AppDesignSystem.space2,
                    ),
                    children: [
                      for (final group in groups) ...[
                        _GroupHeader(label: group.label),
                        for (final entry in group.items)
                          _CapabilityItemRow(
                            entry: entry,
                            keyboardSelected:
                                _visibleItems.indexOf(entry) == _keyboardIndex,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 抽屉头部：连接名主行（server.name，数据非文案；Tooltip + 省略号沿
  /// 行级既有溢出模式）+ 库型名标题次行（既有 l10n 调用降为次级零改动）
  /// —— S5「连接名主行 + 库型次行」语义保留在抽屉头。点击头部收起抽屉。
  Widget _buildDrawerHeader(
    BuildContext context,
    ThemeColors colors,
    DbServer server,
  ) {
    return InkWell(
      onTap: () => _setDrawerOpen(false),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppDesignSystem.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space1_5,
        ),
        child: Row(
          children: [
            Icon(LucideIcons.layoutGrid, size: 14, color: colors.textMuted),
            const SizedBox(width: AppDesignSystem.space1_5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: server.name,
                    preferBelow: false,
                    child: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeSm,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)!.sidebarCapabilityTitleWithType(
                      server.type.displayName,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      letterSpacing: 0.5,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            _KbdBadge(label: _kDigitHint),
            const SizedBox(width: AppDesignSystem.space1_5),
            Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// 锚定解析（Q1 S5 序 + 已连接护栏；与装配同参同源，入口/抽屉共用）。
DbServer? _resolveServer(AppProvider provider) {
  return resolveCapabilityMenuServer(
    currentServer: provider.connection.currentServer,
    activeTabConnectionId: provider.tab.activeTab?.connectionId,
    selectedConnectionId: provider.sidebar.selectedConnectionId,
    isConnected: provider.isConnectionConnected,
    savedConnections: provider.savedConnections,
  );
}

/// 装配（机制零改动：按活动连接 server.type 取插件组 + port 门控）。
List<AssembledCapabilityGroup> _assemble(
  BuildContext context,
  AppProvider provider,
  DbServer server,
) {
  return assembleCapabilityMenu(
    context: context,
    type: server.type,
    port: provider.connection.ports.resolveFor(server.type),
    plugins: defaultPluginRegistry.sidebarPluginsFor(server.type),
    l10n: AppLocalizations.of(context)!,
  );
}

/// kbd 键名徽章（入口 Alt+Q / 抽屉头部 1-9；技术字符串常量，非 l10n）。
class _KbdBadge extends StatelessWidget {
  final String label;

  const _KbdBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        color: colors.bgQuaternary,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: colors.textMuted,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2,
        AppDesignSystem.space1_5,
        AppDesignSystem.space2,
        AppDesignSystem.space0_5,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: colors.textMuted,
        ),
      ),
    );
  }
}

class _CapabilityItemRow extends StatelessWidget {
  final AssembledCapabilityItem entry;

  /// 键盘选中态（面板局部 ↑/↓/数字导航的行级标记；仅视觉，
  /// 不参与命中判定）。
  final bool keyboardSelected;

  const _CapabilityItemRow({
    required this.entry,
    this.keyboardSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final highlighted = entry.item.highlight;
    final foreground =
        highlighted ? colors.accentBlue : colors.textPrimary;
    final iconColor = highlighted ? colors.accentBlue : colors.textSecondary;

    return Tooltip(
      message: '${entry.item.label(AppLocalizations.of(context)!)} · '
          '${entry.badge}',
      preferBelow: false,
      child: InkWell(
        onTap: entry.item.onActivate,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            color: highlighted
                ? colors.accentSubtle
                : keyboardSelected
                    ? colors.bgTertiary
                    : null,
          ),
          child: Row(
            children: [
              Icon(entry.item.icon, size: 14, color: iconColor),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  entry.item.label(AppLocalizations.of(context)!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: highlighted ? FontWeight.w600 : null,
                    color: foreground,
                  ),
                ),
              ),
              // Q1「新建」徽标：框架侧按 item id 命中 [_releaseNewItemIds]
              // 判定（路由任务只按锁定 id 命名，徽标逻辑全部归框架）。
              if (_releaseNewItemIds.contains(entry.item.id)) ...[
                _NewBadge(label: l10n.sidebarCapabilityNewBadge),
                const SizedBox(width: AppDesignSystem.space1),
              ],
              // 来源徽标 Flexible：空间不足（窄侧栏/徽标叠加）时文本省略收缩，
              // 不产生 RenderFlex 溢出；空间足够时渲染原样。
              Flexible(child: _SourceBadge(badge: entry.badge, emphasized: entry.fromAi)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Q1「新建」徽标（行级，沿 [_SourceBadge] 形态；语义色 = success）。
class _NewBadge extends StatelessWidget {
  final String label;

  const _NewBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.success,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String badge;
  final bool emphasized;

  const _SourceBadge({required this.badge, required this.emphasized});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: emphasized ? colors.accentBlue : colors.bgQuaternary,
      ),
      child: Text(
        badge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: emphasized ? Colors.white : colors.textMuted,
        ),
      ),
    );
  }
}
