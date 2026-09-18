import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';

// T009 — ContextMenuItem gains `disabledReason` for accessible disabled-state explanations (FR-002, read-only tooltips)
class ContextMenuItem {
  final String id;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isDivider;
  final bool isDestructive;
  final List<ContextMenuItem>? children;
  final bool enabled;

  /// Tooltip text shown when the item is disabled (e.g. "Read-only connection").
  /// When null and the item is disabled, no tooltip is rendered.
  final String? disabledReason;

  const ContextMenuItem({
    required this.id,
    required this.label,
    this.icon,
    this.onTap,
    this.isDivider = false,
    this.isDestructive = false,
    this.children,
    this.enabled = true,
    this.disabledReason,
  });

  const ContextMenuItem.divider()
    : id = 'divider',
      label = '',
      icon = null,
      onTap = null,
      isDivider = true,
      isDestructive = false,
      children = null,
      enabled = false,
      disabledReason = null;
}

class ContextMenu extends StatefulWidget {
  final List<ContextMenuItem> items;
  final double maxWidth;
  final double itemHeight;

  const ContextMenu({
    super.key,
    required this.items,
    this.maxWidth = 200,
    this.itemHeight = AppDesignSystem.menuItemHeight,
  });

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<ContextMenu> {
  String? _activeSubmenuId;
  Timer? _closeTimer;
  // T010 — keyboard navigation state (FR-025..FR-027)
  final FocusNode _focusNode = FocusNode(debugLabel: 'contextMenu');
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    // Pre-highlight the first navigable (non-divider) item for keyboard users.
    final valid = _validItems;
    for (int i = 0; i < valid.length; i++) {
      if (!valid[i].isDivider) {
        _focusedIndex = i;
        break;
      }
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// Indices into [_validItems] that can receive keyboard focus (every
  /// non-divider item — disabled items are focusable but not activatable,
  /// per FR-027).
  List<int> get _navigableIndices {
    final result = <int>[];
    final valid = _validItems;
    for (int i = 0; i < valid.length; i++) {
      if (!valid[i].isDivider) result.add(i);
    }
    return result;
  }

  // T010 — move keyboard focus by [delta] steps among navigable items
  void _moveFocus(int delta) {
    final navigable = _navigableIndices;
    if (navigable.isEmpty) return;
    final currentPos = navigable.indexOf(_focusedIndex);
    int newPos;
    if (currentPos < 0) {
      newPos = delta > 0 ? 0 : navigable.length - 1;
    } else {
      newPos = (currentPos + delta) % navigable.length;
      if (newPos < 0) newPos += navigable.length;
    }
    setState(() => _focusedIndex = navigable[newPos]);
  }

  // T010 — activate the currently focused item if it is actionable
  void _activateFocused() {
    final valid = _validItems;
    if (_focusedIndex < 0 || _focusedIndex >= valid.length) return;
    final item = valid[_focusedIndex];
    // Disabled items are focusable but not activatable (FR-027).
    if (!item.enabled || item.onTap == null) return;
    Navigator.of(context).pop();
    item.onTap!();
  }

  // T010 — keyboard event handler (ArrowUp/Down, Enter, Escape)
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activateFocused();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Filter leading/trailing dividers and collapse consecutive ones.
  List<ContextMenuItem> get _validItems {
    final result = <ContextMenuItem>[];
    for (final item in widget.items) {
      if (item.isDivider) {
        if (result.isNotEmpty && !result.last.isDivider) {
          result.add(item);
        }
      } else {
        result.add(item);
      }
    }
    if (result.isNotEmpty && result.last.isDivider) {
      result.removeLast();
    }
    return result;
  }

  /// Calculate the top offset of the item at [index] (for submenu positioning).
  double _itemTopOffset(int index) {
    double offset = 0;
    final validItems = _validItems;
    for (int i = 0; i < index && i < validItems.length; i++) {
      if (validItems[i].isDivider) {
        offset +=
            1 +
            AppDesignSystem.menuDividerVPadding *
                2; // divider height + vertical margins
      } else {
        offset += widget.itemHeight;
      }
    }
    return offset;
  }

  void _toggleSubmenu(String id) {
    _closeTimer?.cancel();
    setState(() => _activeSubmenuId = _activeSubmenuId == id ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final validItems = _validItems;

    ContextMenuItem? activeItem;
    int activeIndex = -1;
    if (_activeSubmenuId != null) {
      activeIndex = validItems.indexWhere((i) => i.id == _activeSubmenuId);
      if (activeIndex >= 0) activeItem = validItems[activeIndex];
    }

    // T010 — capture keyboard focus for menu navigation (FR-025..FR-027)
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Main menu ──
          Container(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: colors.borderSubtle,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: validItems.asMap().entries.map((entry) {
                  return _buildItem(context, entry.value, entry.key);
                }).toList(),
              ),
            ),
          ),

          // ── Submenu overlay ──
          if (activeItem != null && activeIndex >= 0)
            Positioned(
              left: widget.maxWidth + 2,
              top: _itemTopOffset(activeIndex),
              child: Material(
                elevation: 0,
                color: Colors.transparent,
                child: ContextMenu(
                  items: activeItem.children!,
                  maxWidth: widget.maxWidth,
                  itemHeight: widget.itemHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, ContextMenuItem item, int index) {
    final colors = context.themeColors;

    if (item.isDivider) {
      return Container(
        height: 1,
        margin: const EdgeInsets.symmetric(
          vertical: AppDesignSystem.menuDividerVPadding,
          horizontal: AppDesignSystem.space2,
        ),
        color: colors.borderSubtle,
      );
    }

    final hasChildren = item.children != null && item.children!.isNotEmpty;
    final isSubmenuOpen = _activeSubmenuId == item.id;
    // T010 — keyboard focus highlight (FR-025)
    final isKeyboardFocused = _focusedIndex == index;

    final color = item.isDestructive
        ? context.themeColors.accentRed
        : item.enabled
        ? colors.textPrimary
        : colors.textMuted;

    final tile = Material(
      color: (isSubmenuOpen || isKeyboardFocused)
          ? context.themeColors.accentBlue.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: hasChildren
            ? () => _toggleSubmenu(item.id)
            : (item.enabled && item.onTap != null
                  ? () {
                      Navigator.of(context).pop();
                      item.onTap!();
                    }
                  : null),
        hoverColor: context.themeColors.accentBlue.withValues(alpha: 0.1),
        splashColor: context.themeColors.accentBlue.withValues(alpha: 0.05),
        child: Container(
          height: widget.itemHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.menuItemHPadding,
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: AppDesignSystem.menuIconSize,
                  color: color,
                ),
                const SizedBox(width: AppDesignSystem.space2),
              ] else
                const SizedBox(
                  width: AppDesignSystem.menuIconSize + AppDesignSystem.space2,
                ),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: AppDesignSystem.menuFontSize,
                    color: color,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasChildren)
                Icon(
                  LucideIcons.chevronRight,
                  size: 14,
                  color: colors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );

    // T009 — surface disabled reason as a tooltip for accessibility (FR-002)
    if (!item.enabled && item.disabledReason != null) {
      return Tooltip(
        message: item.disabledReason!,
        preferBelow: false,
        child: tile,
      );
    }
    return tile;
  }
}

class ContextMenuUtils {
  static Future<void> show({
    required BuildContext context,
    required Offset position,
    required List<ContextMenuItem> items,
    double maxWidth = 200,
  }) async {
    final overlay = Overlay.of(context);
    final renderBox = overlay.context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(position);

    await showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        localPosition.dx + maxWidth,
        localPosition.dy + 100,
      ),
      color: Colors.transparent,
      elevation: 0,
      items: [
        PopupMenuItem<void>(
          padding: EdgeInsets.zero,
          child: ContextMenu(items: items, maxWidth: maxWidth),
        ),
      ],
    );
  }

  static Widget gestureDetector({
    required Widget child,
    required List<ContextMenuItem> Function() itemsBuilder,
  }) {
    return Builder(
      builder: (context) {
        return GestureDetector(
          onSecondaryTapUp: (details) {
            show(
              context: context,
              position: details.globalPosition,
              items: itemsBuilder(),
            );
          },
          child: child,
        );
      },
    );
  }
}
