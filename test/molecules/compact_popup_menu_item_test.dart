import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/molecules/compact_popup_menu_item.dart';
import 'package:dbmaster/theme/design_system.dart';

void main() {
  group('CompactPopupMenuItem', () {
    testWidgets('uses compact defaults from design tokens and fires onTap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showMenu<void>(
                      context: context,
                      position: const RelativeRect.fromLTRB(0, 0, 100, 100),
                      items: [
                        CompactPopupMenuItem<void>(
                          onTap: () => tapped = true,
                          child: const Text('Action'),
                        ),
                      ],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final item = tester.widget<CompactPopupMenuItem<void>>(
        find.byType(CompactPopupMenuItem<void>),
      );
      expect(item.height, AppDesignSystem.menuItemHeight);
      expect(
        item.padding,
        const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.menuItemHPadding,
        ),
      );

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    test('allows explicit height override for two-line exception rows', () {
      const item = CompactPopupMenuItem<void>(height: 40, child: Text('x'));
      expect(item.height, 40);
    });
  });
}
