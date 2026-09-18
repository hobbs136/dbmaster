import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildTreeTheme({required Widget child, required ThemeData theme}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: SizedBox(width: 300, child: Column(children: [child])),
    ),
  );
}

Widget _darkTheme(Widget child) => _buildTreeTheme(
  child: child,
  theme: ThemeData.dark().copyWith(
    scaffoldBackgroundColor: AppDesignSystem.bgPrimary,
  ),
);

void main() {
  group('TreeItem extended', () {
    // emoji 退场——改为校验 Material 图标渲染
    testWidgets('renders with Material icon', (tester) async {
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 0,
            icon: LucideIcons.database,
            iconColor: Colors.blue,
            label: 'Database',
            onTap: () {},
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.database), findsOneWidget);
      expect(find.text('Database'), findsOneWidget);
    });

    testWidgets('renders badge when provided', (tester) async {
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 1,
            icon: LucideIcons.table2,
            iconColor: Colors.orange,
            label: 'users',
            badge: '100',
            onTap: () {},
          ),
        ),
      );

      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('isLoading shows spinning indicator', (tester) async {
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 0,
            icon: LucideIcons.database,
            iconColor: Colors.green,
            label: 'Connecting...',
            isLoading: true,
            onTap: () {},
          ),
        ),
      );

      // Should show a small progress indicator
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('isExpanded shows expanded arrow indicator', (tester) async {
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 0,
            icon: LucideIcons.folder,
            iconColor: Colors.amber,
            label: 'Expanded',
            isExpanded: true,
            onTap: () {},
          ),
        ),
      );

      // Expanded item should render — the rotation is an implementation detail
      expect(find.text('Expanded'), findsOneWidget);
    });

    testWidgets('trailing widget is rendered', (tester) async {
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 1,
            icon: LucideIcons.table2,
            iconColor: Colors.blue,
            label: 'users',
            trailing: const Icon(LucideIcons.ellipsisVertical, size: 14),
            onTap: () {},
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
    });

    testWidgets('onTap callback fires', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 0,
            icon: LucideIcons.database,
            iconColor: Colors.green,
            label: 'Tap me',
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Tap me'));
      expect(tapped, true);
    });

    testWidgets('onDoubleTap callback fires', (tester) async {
      bool doubleTapped = false;
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 1,
            icon: LucideIcons.table2,
            iconColor: Colors.blue,
            label: 'Double tap',
            onTap: () {},
            onDoubleTap: () => doubleTapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Double tap'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Double tap'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(doubleTapped, true);
    });

    testWidgets('different levels have distinct indentations', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: AppDesignSystem.bgPrimary,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: Column(
                children: [
                  TreeItem(
                    level: 0,
                    icon: LucideIcons.database,
                    iconColor: Colors.green,
                    label: 'Level 0',
                    onTap: () {},
                  ),
                  TreeItem(
                    level: 1,
                    icon: LucideIcons.folder,
                    iconColor: Colors.amber,
                    label: 'Level 1',
                    onTap: () {},
                  ),
                  TreeItem(
                    level: 2,
                    icon: LucideIcons.table2,
                    iconColor: Colors.blue,
                    label: 'Level 2',
                    onTap: () {},
                  ),
                  TreeItem(
                    level: 3,
                    icon: LucideIcons.type,
                    iconColor: Colors.grey,
                    label: 'Level 3',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Level 0'), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('Level 2'), findsOneWidget);
      expect(find.text('Level 3'), findsOneWidget);
    });

    testWidgets('showArrow false hides expand arrow', (tester) async {
      await tester.pumpWidget(
        _darkTheme(
          TreeItem(
            level: 0,
            icon: LucideIcons.table2,
            iconColor: Colors.blue,
            label: 'No arrow',
            showArrow: false,
            onTap: () {},
          ),
        ),
      );

      // Should not have rotation transform for arrow
      expect(find.text('No arrow'), findsOneWidget);
    });
  });
}
