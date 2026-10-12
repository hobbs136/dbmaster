// ============================================================================
// ShortcutBindings - 快捷键单一真相源（spec 040 Phase 2.3）
// ----------------------------------------------------------------------------
// ShortcutsDialog 从此表派生展示（替代原 4 个手写清单，消除漂移）。增删全局快捷键
// 时同步更新此表 + global_shortcuts_wrapper._handleKeyEvent / query_editor_widget
// .onKeyEvent；shortcut_bindings_parity_test 守护「展示 ⊆ 真实处理器」（防幽灵条目）。
//
// 不重构 load-bearing 的 if-chain（非 Strategy B）；此表仅为展示与 parity 的数据源。
//
// 键位裁定（plan §6-4，2026-10 工具面板补齐批）：**Alt+1~9 全局保留给 S1
// （结果子标签直达提案），任何面板不得绑定 Alt+数字**；能力面板项直达使用
// 面板局部作用域的裸数字键 1~9（scope = panel）。
// ============================================================================

import '../../l10n/app_localizations.dart';

/// 快捷键作用域：global = GlobalShortcutsWrapper 处理；editor = 编辑器焦点链处理；
/// workbench = 工作台壳内焦点树处理（AiWorkbenchShell 壳根 Focus 冒泡承接）；
/// panel = 能力面板根 Focus onKeyEvent 处理（Q1 快捷面板局部作用域，面板
/// 聚焦后才生效）。parity 守卫只锁 global 集合（同 editor/workbench 先例）。
enum ShortcutScope { global, editor, workbench, panel }

class ShortcutBinding {
  /// 本地化标签（延迟取，避免无 context 时求值）。
  final String Function(AppLocalizations) label;

  /// 本地化分类。
  final String Function(AppLocalizations) category;

  /// 是否含 Ctrl/⌘ 修饰键。
  final bool control;

  /// 是否含 Shift 修饰键。
  final bool shift;

  /// 是否含 Alt 修饰键（Q1：Alt+Q 切换能力面板——首个 Alt 组合键条目）。
  final bool alt;

  /// 非修饰键的显示名，如 'T'、'F5'、'/'、'Enter'、'Space'。
  final String key;

  final ShortcutScope scope;

  /// 附加展示按键段（A5：一键与其修饰变体同行展示，如 F6 行附 'Shift+F6'）。
  final List<String> extraKeys;

  const ShortcutBinding({
    required this.label,
    required this.category,
    this.control = false,
    this.shift = false,
    this.alt = false,
    required this.key,
    this.scope = ShortcutScope.global,
    this.extraKeys = const <String>[],
  });

  /// 平台感知的显示按键段（'Ctrl'/'⌘' + 'Shift' + 'Alt' + key + [extraKeys]）。
  List<String> displayKeys(bool isMacOS) {
    final mod = isMacOS ? '⌘' : 'Ctrl';
    return [
      if (control) mod,
      if (shift) 'Shift',
      if (alt) 'Alt',
      key,
      ...extraKeys,
    ];
  }
}

/// 快捷键展示单一真相源。顺序即分类展示顺序（File → Edit → View → Tabs）。
/// 新增 spec 040 前缺失的 Ctrl+K(搜索)/Ctrl+Shift+G(AI 全屏)/Ctrl+Shift+L(审计)/
/// Ctrl+,(设置)/Ctrl±(浮层透明度)；移除原幽灵 Ctrl+Enter（全局）（实际仅编辑器有，已标 scope）。
final shortcutBindings = <ShortcutBinding>[
  // --- File ---
  ShortcutBinding(
      label: (l) => l.shortcutNewTab,
      category: (l) => l.shortcutCategoryFile,
      control: true,
      key: 'T'),
  ShortcutBinding(
      label: (l) => l.shortcutCloseTab,
      category: (l) => l.shortcutCategoryFile,
      control: true,
      key: 'W'),
  ShortcutBinding(
      label: (l) => l.shortcutSaveQuery,
      category: (l) => l.shortcutCategoryFile,
      control: true,
      key: 'S'),

  // --- Edit ---
  ShortcutBinding(
      label: (l) => l.shortcutExecuteQuery,
      category: (l) => l.shortcutCategoryEdit,
      key: 'F5'),
  ShortcutBinding(
      label: (l) => l.shortcutExecuteQuery,
      category: (l) => l.shortcutCategoryEdit,
      control: true,
      key: 'Enter',
      scope: ShortcutScope.editor),
  ShortcutBinding(
      label: (l) => l.shortcutFormatSql,
      category: (l) => l.shortcutCategoryEdit,
      control: true,
      shift: true,
      key: 'F'),
  ShortcutBinding(
      label: (l) => l.shortcutAutocomplete,
      category: (l) => l.shortcutCategoryEdit,
      control: true,
      key: 'Space',
      scope: ShortcutScope.editor),
  ShortcutBinding(
      label: (l) => l.shortcutUndo,
      category: (l) => l.shortcutCategoryEdit,
      control: true,
      key: 'Z',
      scope: ShortcutScope.editor),
  ShortcutBinding(
      label: (l) => l.shortcutRedo,
      category: (l) => l.shortcutCategoryEdit,
      control: true,
      shift: true,
      key: 'Z',
      scope: ShortcutScope.editor),

  // --- View ---
  ShortcutBinding(
      label: (l) => l.shortcutToggleAiPanel,
      category: (l) => l.shortcutCategoryView,
      control: true,
      shift: true,
      key: 'A'),
  ShortcutBinding(
      // D2 迁移（design §3.1）：键与处理器不变（Ctrl+Shift+G 走
      // toggleAiPanelFullscreen），展示名换工作台文案。
      label: (l) => l.workbenchCommandEnterWorkbench,
      category: (l) => l.shortcutCategoryView,
      control: true,
      shift: true,
      key: 'G'),
  ShortcutBinding(
      label: (l) => l.shortcutCommandPalette,
      category: (l) => l.shortcutCategoryView,
      control: true,
      shift: true,
      key: 'P'),
  ShortcutBinding(
      label: (l) => l.searchDialogTitle,
      category: (l) => l.shortcutCategoryView,
      control: true,
      key: 'K'),
  ShortcutBinding(
      label: (l) => l.shortcutShortcutHelp,
      category: (l) => l.shortcutCategoryView,
      control: true,
      key: '/'),
  ShortcutBinding(
      label: (l) => l.commandSettings,
      category: (l) => l.shortcutCategoryView,
      control: true,
      key: ','),
  ShortcutBinding(
      label: (l) => l.shortcutAuditLog,
      category: (l) => l.shortcutCategoryView,
      control: true,
      shift: true,
      key: 'L'),
  ShortcutBinding(
      label: (l) => l.shortcutIncreaseOpacity,
      category: (l) => l.shortcutCategoryView,
      control: true,
      key: '='),
  ShortcutBinding(
      label: (l) => l.shortcutDecreaseOpacity,
      category: (l) => l.shortcutCategoryView,
      control: true,
      key: '-'),
  // A5：F6/Shift+F6 工作台六区轮转——处理器在 AiWorkbenchShell 壳根焦点树
  //（R10：不碰 GlobalShortcutsWrapper），scope = workbench（parity 守卫只
  // 锁 global 集合，不受影响）。
  ShortcutBinding(
      label: (l) => l.shortcutZoneCycle,
      category: (l) => l.shortcutCategoryView,
      key: 'F6',
      extraKeys: <String>['Shift+F6'],
      scope: ShortcutScope.workbench),
  // Q1（2026-10 工具面板补齐批）：Alt+Q 折叠/展开切换 + 聚焦能力面板。
  // 处理器在 GlobalShortcutsWrapper._handleKeyEvent（经
  // capabilityPanelToggleSignal 一次性通知面板，见 sidebar_capability_menu.dart）。
  ShortcutBinding(
      label: (l) => l.shortcutToggleCapabilityPanel,
      category: (l) => l.shortcutCategoryView,
      key: 'Q',
      alt: true),
  // Q1 面板内键（局部作用域）：面板聚焦后 ↑/↓ 项间移动、裸数字 1~9 直达
  //（跨组连续序号，仅前 9 项；**Alt+1~9 全局保留给 S1，面板不得绑定**，
  // 见头注裁定）。标签复用快速搜索/命令面板既有动词（searchNavigate /
  // searchSelect），数字直达并入导航行键段。parity 只锁 global，不入锁。
  ShortcutBinding(
      label: (l) => l.searchNavigate,
      category: (l) => l.shortcutCategoryView,
      key: '↑/↓',
      extraKeys: <String>['1~9'],
      scope: ShortcutScope.panel),
  ShortcutBinding(
      label: (l) => l.searchSelect,
      category: (l) => l.shortcutCategoryView,
      key: 'Enter',
      extraKeys: <String>['Space'],
      scope: ShortcutScope.panel),

  // --- Tabs ---
  ShortcutBinding(
      label: (l) => l.shortcutNextTab,
      category: (l) => l.shortcutCategoryTab,
      control: true,
      key: 'Tab'),
  ShortcutBinding(
      label: (l) => l.shortcutPreviousTab,
      category: (l) => l.shortcutCategoryTab,
      control: true,
      shift: true,
      key: 'Tab'),
];
