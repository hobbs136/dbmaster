// C14 · 侧边栏能力菜单 —— 分组能力目录的渲染半边（原型
// `sidebar-capability-menu.html`；Q1 快捷面板升级见视角⑦）。
//
// 职责边界（装配见 capability_menu_assembly.dart）：本 widget 只做渲染与
// 折叠态，不判定任何能力——数据来自装配结果（插件合并 + port 门控后的
// 组列表）。无活动连接或装配为空 → 整段隐藏。
//
// 徽章形态对齐原型：core / <type>-plugin / ai-plugin；AI 来源徽章用
// 品牌色底白字，highlight 项（AI 助手）brand-subtle 底 + 主色文字。
//
// Q1（2026-10 工具面板补齐批，feat/db-tooling-completion）：标题带库型名、
// 折叠态持久记忆、行级「新建」徽标（[_releaseNewItemIds] 框架侧集合，
// 不改 SidebarCapabilityItem 契约）、面板局部键盘（Alt+Q 折叠/聚焦全局键 +
// 聚焦后 1~9 直达 / ↑↓ 移动 / Space·Enter 激活）。装配机制零改动。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../plugins/bootstrap.dart';
import '../../../providers/app_provider.dart';
import '../../../services/layout_preferences_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/app_logger.dart';
import 'capability_menu_assembly.dart';

/// 展开态菜单体的最大高度（超出滚动）；树仍是侧边栏主体（原型比例）。
const double _kMenuMaxHeight = 264;

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
};

/// Alt+Q（切换能力面板折叠/展开并聚焦）全局快捷键 → 面板的一次性信号。
/// GlobalShortcutsWrapper 触发（自增计数），[SidebarCapabilityMenu] 监听
/// 消费（折叠切换 + 展开时聚焦面板根焦点）。信号通道收在本文件而不进
/// Provider 层：无连接/装配为空时面板未挂载，信号无人消费自然丢弃
/// （与 SidebarProvider.requestSidebarExpand「重复请求覆盖、消费方只处理
/// 最新」同精神；sidebars Provider 文件不在本批涉及文件清单内）。
final ValueNotifier<int> capabilityPanelToggleSignal = ValueNotifier<int>(0);

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

class SidebarCapabilityMenu extends StatefulWidget {
  const SidebarCapabilityMenu({super.key});

  @override
  State<SidebarCapabilityMenu> createState() => _SidebarCapabilityMenuState();
}

class _SidebarCapabilityMenuState extends State<SidebarCapabilityMenu> {
  bool _expanded = true;

  /// 键盘选中项索引（对 [AssembledCapabilityItem] 跨组连续扁平序；-1 = 无选中）。
  /// 仅在面板根 Focus 自身持焦时有效（见 [_onPanelFocusChanged]）。
  int _keyboardIndex = -1;

  /// 面板根焦点（Alt+Q 聚焦入口 + 局部键盘 onKeyEvent 承接）。initState
  /// 创建（onKeyEvent 需实例方法），dispose 释放——赋值先于一切使用。
  late final FocusNode _panelFocus;

  /// 最近一次 build 的可见项扁平序缓存（跨组连续序号 = 键盘导航的事实源；
  /// 装配在 build 内完成，handler 复用同序，避免二次装配漂移）。
  List<AssembledCapabilityItem> _visibleItems = const [];

  @override
  void initState() {
    super.initState();
    _panelFocus = FocusNode(onKeyEvent: _handlePanelKey);
    capabilityPanelToggleSignal.addListener(_onToggleSignal);
    _panelFocus.addListener(_onPanelFocusChanged);
    // 折叠记忆（Q1）：首帧默认展开，post-frame 读持久化值后校正
    //（沿 layout_preferences_service getSidebarCollapsed get/set 对先例）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreExpandedState();
    });
  }

  @override
  void dispose() {
    capabilityPanelToggleSignal.removeListener(_onToggleSignal);
    _panelFocus.removeListener(_onPanelFocusChanged);
    _panelFocus.dispose();
    super.dispose();
  }

  Future<void> _restoreExpandedState() async {
    try {
      final collapsed =
          await LayoutPreferencesService().getCapabilityMenuCollapsed();
      if (!mounted || !collapsed || !_expanded) return;
      setState(() => _expanded = false);
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
    _toggleExpanded(focusAfterExpand: true);
  }

  void _toggleExpanded({bool focusAfterExpand = false}) {
    setState(() => _expanded = !_expanded);
    unawaited(
      LayoutPreferencesService().setCapabilityMenuCollapsed(!_expanded),
    );
    if (focusAfterExpand && _expanded) {
      // Alt+Q 从折叠态展开后聚焦面板根，数字/方向键立即可用；面板未挂载
      //（无连接自隐藏）时 context 为空，跳过聚焦。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _panelFocus.context != null) {
          _panelFocus.requestFocus();
        }
      });
    }
  }

  /// 键盘选中态仅在面板根自身持焦时有效；primary 焦点移出本节点（点击行 →
  /// InkWell 行内 Focus 接管，或焦点离开面板）即清除，避免 Space/Enter 与
  /// 行内 InkWell 激活双触发。
  void _onPanelFocusChanged() {
    final primary = FocusManager.instance.primaryFocus;
    if (_keyboardIndex != -1 && primary != _panelFocus) {
      setState(() => _keyboardIndex = -1);
    }
  }

  /// 面板局部键盘（scope = panel，登记于 shortcut_bindings.dart）：聚焦后
  /// 1~9 直达可见项（跨组连续序号）、↑/↓ 项间移动、Space/Enter 激活当前项。
  KeyEventResult _handlePanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
    final provider = context.watch<AppProvider>();
    final server = resolveCapabilityMenuServer(
      currentServer: provider.connection.currentServer,
      activeTabConnectionId: provider.tab.activeTab?.connectionId,
      selectedConnectionId: provider.sidebar.selectedConnectionId,
      isConnected: provider.isConnectionConnected,
      savedConnections: provider.savedConnections,
    );
    if (server == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final groups = assembleCapabilityMenu(
      context: context,
      type: server.type,
      port: provider.connection.ports.resolveFor(server.type),
      plugins: defaultPluginRegistry.sidebarPluginsFor(server.type),
      l10n: l10n,
    );
    if (groups.isEmpty) return const SizedBox.shrink();

    // 可见项扁平序缓存（键盘导航事实源，见 _visibleItems 注）。
    _visibleItems = [
      for (final group in groups) ...group.items,
    ];

    final colors = context.themeColors;
    return Focus(
      focusNode: _panelFocus,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, colors, server.type.displayName),
            if (_expanded)
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
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeColors colors,
    String typeDisplayName,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => _toggleExpanded(),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space1_5,
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            Icon(LucideIcons.layoutGrid, size: 14, color: colors.textMuted),
            const SizedBox(width: AppDesignSystem.space1_5),
            Expanded(
              child: Text(
                l10n.sidebarCapabilityTitleWithType(typeDisplayName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
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
