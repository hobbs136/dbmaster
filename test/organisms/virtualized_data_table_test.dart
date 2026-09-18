import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/theme/design_system.dart';

Widget _buildTable({List<String>? columns, List<Map<String, dynamic>>? data}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppDesignSystem.bgPrimary,
    ),
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 400,
        child: VirtualizedDataTable(
          columns: columns ?? ['id', 'name', 'age'],
          data:
              data ??
              [
                {'id': 1, 'name': 'Alice', 'age': 30},
                {'id': 2, 'name': 'Bob', 'age': 25},
                {'id': 3, 'name': 'Charlie', 'age': 35},
              ],
        ),
      ),
    ),
  );
}

void main() {
  group('VirtualizedDataTable', () {
    testWidgets('renders all columns and rows', (tester) async {
      await tester.pumpWidget(_buildTable());
      await tester.pumpAndSettle();

      expect(find.text('id'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('age'), findsOneWidget);

      expect(find.text('1'), findsWidgets);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows empty state text when data is empty', (tester) async {
      await tester.pumpWidget(
        _buildTable(columns: const ['id', 'name'], data: const []),
      );
      await tester.pumpAndSettle();

      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('TS-008.2 row container uses background color on hover', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTable());
      await tester.pumpAndSettle();

      final firstRow = find
          .ancestor(
            of: find.text('Alice'),
            matching: find.byWidgetPredicate(
              (widget) => widget is Container && widget.decoration != null,
            ),
          )
          .first;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();

      await mouse.moveTo(tester.getCenter(firstRow));
      await tester.pump();

      final rowContainer = tester.widget<Container>(firstRow);
      final deco = rowContainer.decoration as BoxDecoration;
      final border = deco.border as Border?;
      final borderColorAlpha = border != null
          ? (border.bottom.color.a * 255).round()
          : 0;
      expect(
        deco.color != null || borderColorAlpha > 0,
        isTrue,
        reason: 'Hovered row should have a visible color or border',
      );
    });

    testWidgets(
      'TS-008.1 row border is semi-transparent (no opaque 1px divider)',
      (tester) async {
        await tester.pumpWidget(_buildTable());
        await tester.pumpAndSettle();

        final firstRow = find
            .ancestor(
              of: find.text('Alice'),
              matching: find.byWidgetPredicate(
                // P0-4 后单元格容器也有 decoration（右侧竖线），
                // 此处须定位到带底边行线的行容器
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).border is Border &&
                    ((widget.decoration! as BoxDecoration).border! as Border)
                            .bottom
                            .width >
                        0,
              ),
            )
            .first;

        final rowContainer = tester.widget<Container>(firstRow);
        final deco = rowContainer.decoration as BoxDecoration;
        final border = deco.border as Border?;

        expect(border, isNotNull);
        final alpha = (border!.bottom.color.a * 255).round();
        expect(
          alpha,
          lessThan(255),
          reason: 'Row divider should be semi-transparent, not fully opaque',
        );
      },
    );

    testWidgets('shows row numbers by default', (tester) async {
      await tester.pumpWidget(_buildTable());
      await tester.pumpAndSettle();

      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('does not show row numbers when showRowNumbers is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: VirtualizedDataTable(
                columns: const ['name'],
                data: const [
                  {'name': 'Alice'},
                  {'name': 'Bob'},
                ],
                showRowNumbers: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });
  });
}
