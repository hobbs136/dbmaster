// ============================================================================
// ShortcutBindings - 快捷键单一真相源（spec 040 Phase 2.3）
// ----------------------------------------------------------------------------
// ShortcutsDialog 从此表派生展示（替代原 4 个手写清单，消除漂移）。增删全局快捷键
// 时同步更新此表 + global_shortcuts_wrapper._handleKeyEvent / query_editor_widget
// .onKeyEvent；shortcut_bindings_parity_test 守护「展示 ⊆ 真实处理器」（防幽灵条目）。
//
// 不重构 load-bearing 的 if-chain（非 Strategy B）；此表仅为展示与 parity 的数据源。
// ============================================================================

import '../../l10n/app_localizations.dart';

/// 快捷键作用域：global = GlobalShortcutsWrapper 处理；editor = 编辑器焦点链处理。
enum ShortcutScope { global, editor }

class ShortcutBinding {
  /// 本地化标签（延迟取，避免无 context 时求值）。
  final String Function(AppLocalizations) label;

  /// 本地化分类。
  final String Function(AppLocalizations) category;

  /// 是否含 Ctrl/⌘ 修饰键。
  final bool control;

  /// 是否含 Shift 修饰键。
  final bool shift;

  /// 非修饰键的显示名，如 'T'、'F5'、'/'、'Enter'、'Space'。
  final String key;

  final ShortcutScope scope;

  const ShortcutBinding({
    required this.label,
    required this.category,
    this.control = false,
    this.shift = false,
    required this.key,
    this.scope = ShortcutScope.global,
  });

  /// 平台感知的显示按键段（'Ctrl'/'⌘' + 'Shift' + key）。
  List<String> displayKeys(bool isMacOS) {
    final mod = isMacOS ? '⌘' : 'Ctrl';
    return [
      if (control) mod,
      if (shift) 'Shift',
      key,
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
      label: (l) => l.shortcutToggleAiFullscreen,
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
