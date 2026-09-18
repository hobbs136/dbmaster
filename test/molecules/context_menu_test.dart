import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('ContextMenu', () {
    testWidgets('renders all provided items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(
                  id: 'copy',
                  label: 'Copy',
                  icon: LucideIcons.copy,
                ),
                ContextMenuItem(
                  id: 'paste',
                  label: 'Paste',
                  icon: LucideIcons.clipboardPaste,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.byIcon(LucideIcons.copy), findsOneWidget);
      expect(find.byIcon(LucideIcons.clipboardPaste), findsOneWidget);
    });

    testWidgets('tapping an item invokes onTap and closes menu', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(
                  id: 'delete',
                  label: 'Delete',
                  icon: LucideIcons.trash2,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('disabled item is not tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(
                  id: 'disabled',
                  label: 'Disabled',
                  enabled: false,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();

      expect(tapped, isFalse);
    });

    testWidgets('destructive item uses accent red color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(
                  id: 'delete',
                  label: 'Delete',
                  isDestructive: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('Delete'));
      expect(text.style?.color, isNotNull);
    });

    testWidgets('strips leading and trailing dividers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem.divider(),
                ContextMenuItem(id: 'a', label: 'A'),
                ContextMenuItem.divider(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      final dividerContainers = find
          .byWidgetPredicate(
            (w) =>
                w is Container &&
                w.constraints?.maxHeight == null &&
                w.child == null,
          )
          .evaluate()
          .length;
      expect(dividerContainers, 0);
    });

    testWidgets('collapses consecutive dividers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(id: 'a', label: 'A'),
                ContextMenuItem.divider(),
                ContextMenuItem.divider(),
                ContextMenuItem(id: 'b', label: 'B'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('ContextMenuUtils.gestureDetector', () {
    testWidgets('right-click shows context menu', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMenuUtils.gestureDetector(
              child: const SizedBox.expand(
                child: Center(child: Text('Right click me')),
              ),
              itemsBuilder: () => [
                ContextMenuItem(
                  id: 'action',
                  label: 'Action',
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Right click me'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Action'), findsOneWidget);

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
      expect(find.text('Action'), findsNothing);
    });
  });
}
