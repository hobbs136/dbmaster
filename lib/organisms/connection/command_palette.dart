import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

class _MoveSelectionDownIntent extends Intent {
  const _MoveSelectionDownIntent();
}

class _MoveSelectionUpIntent extends Intent {
  const _MoveSelectionUpIntent();
}

class _ExecuteSelectedIntent extends Intent {
  const _ExecuteSelectedIntent();
}

class CommandPaletteDialog extends StatefulWidget {
  // commands 必填——杜绝无命令时落入 no-op fallback（spec 040 T008）
  final List<Command> commands;
  final String initialQuery;

  const CommandPaletteDialog({
    super.key,
    required this.commands,
    this.initialQuery = '',
  });

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();

  // commands 必填（spec 040 T008）
  static Future<void> show(
    BuildContext context, {
    required List<Command> commands,
    String initialQuery = '',
  }) {
    return showDialog(
      context: context,
      builder: (context) =>
          CommandPaletteDialog(commands: commands, initialQuery: initialQuery),
    );
  }
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  late TextEditingController _searchController;
  late FocusNode _focusNode;
  late List<Command> _allCommands;
  late List<Command> _filteredCommands;
  int _selectedIndex = 0;
  final ScrollController _listScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();
    _allCommands = widget.commands;
    _filteredCommands = List.from(_allCommands);

    if (widget.initialQuery.isNotEmpty) {
      _filterCommands(widget.initialQuery);
    }

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterCommands(_searchController.text);
  }

  void _filterCommands(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCommands = List.from(_allCommands);
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredCommands = _allCommands.where((cmd) {
          return cmd.label.toLowerCase().contains(lowerQuery) ||
              cmd.category.toLowerCase().contains(lowerQuery) ||
              cmd.keywords.any((k) => k.toLowerCase().contains(lowerQuery));
        }).toList();
      }
      _selectedIndex = 0;
    });
  }

  void _executeCommand(Command command) {
    Navigator.pop(context);
    command.execute(context);
  }

  void _moveSelectionDown() {
    if (_filteredCommands.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + 1).clamp(
        0,
        _filteredCommands.length - 1,
      );
    });
    _scrollToSelected();
  }

  void _moveSelectionUp() {
    if (_filteredCommands.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex - 1).clamp(
        0,
        _filteredCommands.length - 1,
      );
    });
    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (!_listScrollController.hasClients) return;
    const itemHeight = 40.0; // Approximate height of each item
    final offset = _selectedIndex * itemHeight;
    final viewportHeight = _listScrollController.position.viewportDimension;
    final currentOffset = _listScrollController.offset;

    if (offset < currentOffset) {
      _listScrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (offset + itemHeight > currentOffset + viewportHeight) {
      _listScrollController.animateTo(
        offset + itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.arrowDown):
            const _MoveSelectionDownIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            const _MoveSelectionUpIntent(),
        SingleActivator(LogicalKeyboardKey.enter):
            const _ExecuteSelectedIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter):
            const _ExecuteSelectedIntent(),
      },
      child: Actions(
        actions: {
          _MoveSelectionDownIntent: CallbackAction<_MoveSelectionDownIntent>(
            onInvoke: (_) {
              _moveSelectionDown();
              return null;
            },
          ),
          _MoveSelectionUpIntent: CallbackAction<_MoveSelectionUpIntent>(
            onInvoke: (_) {
              _moveSelectionUp();
              return null;
            },
          ),
          _ExecuteSelectedIntent: CallbackAction<_ExecuteSelectedIntent>(
            onInvoke: (_) {
              if (_filteredCommands.isNotEmpty) {
                _executeCommand(_filteredCommands[_selectedIndex]);
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(color: Colors.black54),
                ),
                Center(
                  child: Container(
                    width: 500,
                    height: 400,
                    decoration: BoxDecoration(
                      color: colors.bgSecondary,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusMd,
                      ),
                      border: Border.all(color: colors.borderLight),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          offset: Offset(0, 16),
                          blurRadius: 40,
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Expanded(child: _buildSearchField(l10n)),
                        Divider(height: 1, color: colors.dividerColor),
                        Expanded(flex: 3, child: _buildCommandList(l10n)),
                        Divider(height: 1, color: colors.dividerColor),
                        _buildFooter(l10n),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 18, color: colors.textMuted),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onSubmitted: (_) {
                if (_filteredCommands.isNotEmpty) {
                  _executeCommand(_filteredCommands[_selectedIndex]);
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 16, color: colors.textMuted),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: l10n.searchClose,
          ),
        ],
      ),
    );
  }

  Widget _buildCommandList(AppLocalizations l10n) {
    if (_filteredCommands.isEmpty) {
      return _buildEmptyState(l10n);
    }

    return ListView.separated(
      controller: _listScrollController,
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      itemCount: _filteredCommands.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: AppDesignSystem.space0_5),
      itemBuilder: (context, index) {
        final command = _filteredCommands[index];
        final isSelected = index == _selectedIndex;

        return _CommandItem(
          command: command,
          isSelected: isSelected,
          onTap: () => _executeCommand(command),
        );
      },
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    final colors = context.themeColors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.searchX, size: 48, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            l10n.searchNoResults,
            style: TextStyle(fontSize: 14, color: colors.textMuted),
          ),
          if (_searchController.text.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              l10n.searchTryDifferentKeywords,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        border: Border(top: BorderSide(color: colors.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.keyboard, size: 14, color: colors.textMuted),
          const SizedBox(width: AppDesignSystem.space1),
          // Flexible + 水平滚动：窄对话框(500px)或长 locale 下提示行不再溢出，
          // 右侧计数始终可见。
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildShortcutHint(
                    l10n.searchNavigateKeys,
                    l10n.searchNavigate,
                  ),
                  _buildShortcutHint('Enter', l10n.searchSelect),
                  _buildShortcutHint('Esc', l10n.searchClose),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            '${_filteredCommands.length}/${_allCommands.length}',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutHint(String key, String label) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            key,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(label, style: TextStyle(fontSize: 11, color: colors.textMuted)),
        ],
      ),
    );
  }
}

class _CommandItem extends StatelessWidget {
  final Command command;
  final bool isSelected;
  final VoidCallback onTap;

  const _CommandItem({
    required this.command,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          color: isSelected ? colors.accentBlue.withValues(alpha: 0.15) : null,
          border: isSelected
              ? Border(left: BorderSide(color: colors.accentBlue, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Icon(
                command.icon,
                size: 16,
                color: isSelected ? colors.accentBlue : colors.textMuted,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    command.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                  if (command.description.isNotEmpty) ...[
                    const SizedBox(height: AppDesignSystem.space0_5),
                    Text(
                      command.description,
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              decoration: BoxDecoration(
                color: colors.bgPrimary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                command.category,
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            if (command.shortcut.isNotEmpty)
              _ShortcutBadge(
                text: Platform.isMacOS
                    ? command.shortcut.replaceAll('Ctrl', '⌘')
                    : command.shortcut,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  final String text;

  const _ShortcutBadge({required this.text});

  String _formatShortcutForPlatform(String shortcut, BuildContext context) {
    if (shortcut.isEmpty) return shortcut;
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    if (isMacOS) {
      return shortcut.replaceAll('Ctrl+', '⌘+');
    } else {
      return shortcut.replaceAll('⌘+', 'Ctrl+').replaceAll('⌘', 'Ctrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _formatShortcutForPlatform(text, context);
    final colors = context.themeColors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.borderLight, width: 1),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 11,
          color: colors.textMuted,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          height: 1.2,
        ),
      ),
    );
  }
}

class Command {
  final String id;
  final String label;
  final String description;
  final String shortcut;
  final IconData icon;
  final String category;
  final List<String> keywords;
  final void Function(BuildContext context) execute;

  const Command({
    required this.id,
    required this.label,
    this.description = '',
    this.shortcut = '',
    required this.icon,
    required this.category,
    this.keywords = const [],
    required this.execute,
  });
}
