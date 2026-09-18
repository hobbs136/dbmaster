import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildTreeItem({required TreeItem item, ThemeData? theme}) {
  return MaterialApp(
    // 默认主题用生产主题——TreeItem 选中色现读
    // colorScheme.primary，ThemeData.dark() 的 M3 紫与 accentPrimary 不一致
    theme: theme ?? AppTheme.darkTheme,
    home: Scaffold(
      body: SizedBox(width: 300, child: Column(children: [item])),
    ),
  );
}

void main() {
  group('TreeItem (TS-007)', () {
    testWidgets('renders label, icon, and arrow by default', (tester) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'test_database',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('test_database'), findsOneWidget);
      expect(find.byIcon(LucideIcons.database), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    });

    // emoji 退场——改为校验 Material 图标着色（iconColor 现在真正生效）
    testWidgets('applies iconColor to the Material icon', (tester) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.server,
            iconColor: Colors.green,
            label: 'Mobile DB',
            showArrow: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.server));
      expect(icon.color, Colors.green);
    });

    testWidgets('TS-007.3 hover applies bgTertiary-based background', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'hovered_node',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.text('hovered_node')));
      await tester.pump();

      final containers = find.descendant(
        of: find.byType(TreeItem),
        matching: find.byType(Container),
      );
      final containerWidgets = tester
          .widgetList<Container>(containers)
          .toList();

      final hoveredContainer = containerWidgets.firstWhere(
        (c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.color != null &&
              d.color != Colors.transparent &&
              d.borderRadius != null;
        },
        orElse: () =>
            throw StateError('No decorated container with borderRadius found'),
      );
      final deco = hoveredContainer.decoration as BoxDecoration;
      expect(
        (deco.borderRadius as BorderRadius).topLeft.x,
        AppDesignSystem.radiusSm,
        reason: 'Hovered tree item should use radiusSm (6px)',
      );
      expect(
        (deco.color!.a * 255).round(),
        greaterThan(0),
        reason: 'Hovered background should have non-zero alpha',
      );
    });

    testWidgets('TS-007.3 selected state uses accent color overlay', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'selected_node',
            isSelected: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final containers = find.descendant(
        of: find.byType(TreeItem),
        matching: find.byType(Container),
      );
      final containerWidgets = tester
          .widgetList<Container>(containers)
          .toList();

      final selectedContainer = containerWidgets.firstWhere((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.color != null &&
            d.color != Colors.transparent &&
            d.borderRadius != null;
      }, orElse: () => throw StateError('No selected container found'));
      final deco = selectedContainer.decoration as BoxDecoration;
      // darkTheme 的 selected overlay 取 colorScheme.primary，现为暗色变体（plan §2.3）
      final accentArgb = AppDesignSystem.accentPrimaryDark;
      expect(
        (deco.color!.r * 255).round(),
        (accentArgb.r * 255).round(),
        reason: 'Selected bg should carry accentPrimary red channel',
      );
      expect(
        (deco.color!.g * 255).round(),
        (accentArgb.g * 255).round(),
        reason: 'Selected bg should carry accentPrimary green channel',
      );
      expect(
        (deco.color!.b * 255).round(),
        (accentArgb.b * 255).round(),
        reason: 'Selected bg should carry accentPrimary blue channel',
      );
      expect(
        (deco.color!.a * 255).round(),
        lessThan(255),
        reason: 'Selected bg should be semi-transparent overlay',
      );
    });

    testWidgets('chevron rotates when isExpanded is true', (tester) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'expanded_node',
            isExpanded: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final animatedRotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(
        animatedRotation.turns,
        0.25,
        reason: 'Expanded chevron should be rotated 90 degrees (0.25 turn)',
      );
    });

    testWidgets('loading state shows CircularProgressIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'loading_node',
            isLoading: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byIcon(LucideIcons.chevronRight),
        findsNothing,
        reason: 'Chevron should be hidden while loading',
      );
    });

    testWidgets('no arrow when showArrow is false', (tester) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 3,
            icon: LucideIcons.table2,
            iconColor: Colors.grey,
            label: 'leaf_node',
            showArrow: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    });

    testWidgets('badge renders when provided', (tester) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'db_with_badge',
            badge: '3',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
    });

    // 契约 C6：ellipsis 截断处必须有完整值入口（Tooltip）
    testWidgets('label is wrapped in a Tooltip carrying the full name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 3,
            icon: LucideIcons.table2,
            iconColor: Colors.grey,
            label: 'a_very_long_table_name_that_will_be_truncated',
            showArrow: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(
        tooltip.message,
        'a_very_long_table_name_that_will_be_truncated',
        reason: 'Tooltip should expose the full (untruncated) label',
      );
    });

    testWidgets('labelWidget mode does not add a Tooltip', (tester) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 3,
            icon: LucideIcons.columns2,
            iconColor: Colors.grey,
            labelWidget: const Text('column_leaf'),
            showArrow: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('column_leaf'), findsOneWidget);
      expect(
        find.byType(Tooltip),
        findsNothing,
        reason: 'labelWidget branch should not be wrapped in a Tooltip',
      );
    });

    testWidgets('onTap is called when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'tappable_node',
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('tappable_node'));
      expect(tapped, isTrue);
    });

    testWidgets('onDoubleTap is called when double-tapped', (tester) async {
      var doubleTapCount = 0;
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'dbl_tap_node',
            onTap: () {},
            onDoubleTap: () => doubleTapCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('dbl_tap_node'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('dbl_tap_node'));
      await tester.pumpAndSettle();

      expect(doubleTapCount, 1);
    });

    testWidgets('onContextMenu is called on right-click with position', (
      tester,
    ) async {
      Offset? capturedPosition;
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'ctx_node',
            onTap: () {},
            onContextMenu: (position) => capturedPosition = position,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ctx_node'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(capturedPosition, isNotNull);
      expect(capturedPosition!.dx, greaterThan(0));
      expect(capturedPosition!.dy, greaterThan(0));
    });

    testWidgets('right-click without onContextMenu does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'no_ctx_node',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('no_ctx_node'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('no_ctx_node'), findsOneWidget);
    });

    testWidgets('trailing widget is rendered and tappable independently', (
      tester,
    ) async {
      var trailingTapped = false;
      var itemTapped = false;
      await tester.pumpWidget(
        _buildTreeItem(
          item: TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.amber,
            label: 'trailing_node',
            onTap: () => itemTapped = true,
            trailing: IconButton(
              icon: const Icon(LucideIcons.ellipsisVertical, size: 16),
              onPressed: () => trailingTapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await tester.pumpAndSettle();

      expect(trailingTapped, isTrue);
      expect(itemTapped, isFalse);
    });

    testWidgets('level 2 item has smaller font and height than level 1', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Column(
              children: [
                TreeItem(
                  level: 1,
                  icon: LucideIcons.database,
                  iconColor: Colors.amber,
                  label: 'L1_node',
                  onTap: () {},
                ),
                TreeItem(
                  level: 2,
                  icon: LucideIcons.folder,
                  iconColor: Colors.blue,
                  label: 'L2_node',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l1Text = tester.widget<Text>(find.text('L1_node'));
      final l2Text = tester.widget<Text>(find.text('L2_node'));

      expect(
        l1Text.style!.fontSize,
        greaterThan(l2Text.style!.fontSize!),
        reason: 'Level 1 font size should be larger than level 2',
      );
      expect(
        l1Text.style!.fontWeight!.value,
        greaterThan(l2Text.style!.fontWeight!.value),
        reason: 'Level 1 font weight should be heavier than level 2',
      );
    });
  });
}
