import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
// 快捷键展示单一真相源（spec 040 Phase 2.3）
import '../../core/shortcuts/shortcut_bindings.dart';

class ShortcutsDialog extends StatefulWidget {
  static void show(BuildContext context) {
    showDialog(context: context, builder: (context) => const ShortcutsDialog());
  }

  const ShortcutsDialog({super.key});

  @override
  State<ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _MoveSelectionDownIntent extends Intent {
  const _MoveSelectionDownIntent();
}

class _MoveSelectionUpIntent extends Intent {
  const _MoveSelectionUpIntent();
}

class _CloseDialogIntent extends Intent {
  const _CloseDialogIntent();
}

class _ShortcutsDialogState extends State<ShortcutsDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  int _selectedIndex = -1;

  bool get _isMacOS => Platform.isMacOS;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ShortcutItem> _getAllFlatShortcuts() {
    final filtered = _getFilteredShortcuts();
    final List<ShortcutItem> flat = [];
    for (final category in filtered) {
      flat.addAll(category['items'] as List<ShortcutItem>);
    }
    return flat;
  }

  void _moveSelection(int delta) {
    final flatShortcuts = _getAllFlatShortcuts();
    if (flatShortcuts.isEmpty) return;

    setState(() {
      if (_selectedIndex == -1) {
        _selectedIndex = delta > 0 ? 0 : flatShortcuts.length - 1;
      } else {
        _selectedIndex = (_selectedIndex + delta).clamp(
          0,
          flatShortcuts.length - 1,
        );
      }
    });

    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (_selectedIndex < 0 || !_scrollController.hasClients) return;

    final itemHeight = 40.0;
    final viewportHeight = _scrollController.position.viewportDimension;
    final offset = _selectedIndex * itemHeight;

    if (offset < _scrollController.offset) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    } else if (offset + itemHeight >
        _scrollController.offset + viewportHeight) {
      _scrollController.animateTo(
        offset + itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  // 从 shortcutBindings 单一真相源派生并按 category 分组（spec 040 Phase 2.3）。
  List<Map<String, dynamic>> _getFilteredShortcuts() {
    final l10n = AppLocalizations.of(context)!;
    final isMacOS = _isMacOS;
    final query = _searchQuery.toLowerCase();

    final Map<String, List<ShortcutItem>> byCategory = {};
    for (final b in shortcutBindings) {
      final cat = b.category(l10n);
      byCategory
          .putIfAbsent(cat, () => [])
          .add(
            ShortcutItem(
              description: b.label(l10n),
              keys: b.displayKeys(isMacOS),
            ),
          );
    }

    final allShortcuts = byCategory.entries
        .map((e) => {'category': e.key, 'items': e.value})
        .toList();
    if (query.isEmpty) return allShortcuts;

    return allShortcuts
        .map((category) {
          final filteredItems = (category['items'] as List<ShortcutItem>)
              .where(
                (item) =>
                    item.description.toLowerCase().contains(query) ||
                    item.keys.any((key) => key.toLowerCase().contains(query)),
              )
              .toList();
          return {'category': category['category'], 'items': filteredItems};
        })
        .where((category) => (category['items'] as List).isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Dialog(
      backgroundColor: colors.bgSecondary,
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 600, minHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(l10n),
            _buildSearchBar(),
            Expanded(child: _buildContent()),
            _buildFooter(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.keyboard, color: colors.accentBlue),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            l10n.shortcutShortcutHelp,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(LucideIcons.x, color: colors.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: l10n.commonClose,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: TextStyle(color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: l10n.commonSearch,
          hintStyle: TextStyle(color: colors.textMuted),
          prefixIcon: Icon(LucideIcons.search, color: colors.textMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(LucideIcons.x, color: colors.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colors.bgTertiary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final filteredShortcuts = _getFilteredShortcuts();

    if (filteredShortcuts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.searchX, size: 48, color: colors.textMuted),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              l10n.shortcutNoMatching,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    int globalIndex = 0;
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const _MoveSelectionDownIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const _MoveSelectionUpIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _CloseDialogIntent(),
      },
      child: Actions(
        actions: {
          _MoveSelectionDownIntent: CallbackAction<_MoveSelectionDownIntent>(
            onInvoke: (_) {
              _moveSelection(1);
              return null;
            },
          ),
          _MoveSelectionUpIntent: CallbackAction<_MoveSelectionUpIntent>(
            onInvoke: (_) {
              _moveSelection(-1);
              return null;
            },
          ),
          _CloseDialogIntent: CallbackAction<_CloseDialogIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: filteredShortcuts
                .map(
                  (category) => _buildShortcutCategory(
                    category['category'] as String,
                    category['items'] as List<ShortcutItem>,
                    (items) {
                      final startIndex = globalIndex;
                      globalIndex += items.length;
                      return startIndex;
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutCategory(
    String title,
    List<ShortcutItem> shortcuts,
    int Function(List<ShortcutItem>) getStartIndex,
  ) {
    final colors = context.themeColors;
    final startIndex = getStartIndex(shortcuts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 16, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.accentBlue,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Column(
            children: shortcuts.asMap().entries.map((entry) {
              final globalIndex = startIndex + entry.key;
              return _buildShortcutItem(
                entry.value,
                entry.key == shortcuts.length - 1,
                globalIndex,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutItem(ShortcutItem item, bool isLast, int index) {
    final colors = context.themeColors;
    final isSelected = index == _selectedIndex;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: isSelected ? colors.accentBlue.withValues(alpha: 0.1) : null,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              item.description,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? colors.accentBlue : colors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(height: 1, color: colors.borderLight),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          _ShortcutKeys(keys: item.keys, isSelected: isSelected),
        ],
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        border: Border(top: BorderSide(color: colors.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.shortcutPressEscToClose,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ShortcutKeys extends StatelessWidget {
  final List<String> keys;
  final bool isSelected;

  const _ShortcutKeys({required this.keys, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: keys
          .map((key) => _ShortcutKey(text: key, isSelected: isSelected))
          .toList(),
    );
  }
}

class _ShortcutKey extends StatelessWidget {
  final String text;
  final bool isSelected;

  const _ShortcutKey({required this.text, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? colors.accentBlue.withValues(alpha: 0.15)
            : colors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: isSelected
              ? colors.accentBlue.withValues(alpha: 0.3)
              : colors.borderLight,
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? colors.accentBlue : colors.textSecondary,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          height: 1.2,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

class ShortcutItem {
  final String description;
  final List<String> keys;

  const ShortcutItem({required this.description, required this.keys});
}
