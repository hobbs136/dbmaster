import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/ai_panel/ai_table_mention_menu.dart';

Widget _buildMenu({
  String prefix = '',
  List<String> candidates = const [],
  int highlightIndex = 0,
  ValueChanged<String>? onTableSelected,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AiTableMentionMenu(
        prefix: prefix,
        candidates: candidates,
        highlightIndex: highlightIndex,
        onTableSelected: onTableSelected ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('AiTableMentionMenu', () {
    testWidgets('renders all candidates when prefix is empty', (tester) async {
      await tester.pumpWidget(
        _buildMenu(candidates: <String>['users', 'orders']),
      );
      await tester.pumpAndSettle();

      expect(find.text('users'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);
    });

    testWidgets('filters candidates by case-insensitive prefix', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildMenu(
          prefix: 'US',
          candidates: <String>['users', 'user_roles', 'orders'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('users'), findsOneWidget);
      expect(find.text('user_roles'), findsOneWidget);
      expect(find.text('orders'), findsNothing);
    });

    testWidgets('prefix filter is startsWith, not contains', (tester) async {
      await tester.pumpWidget(
        _buildMenu(
          prefix: 'ser',
          candidates: <String>['users', 'serpent_logs'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('users'), findsNothing);
      expect(find.text('serpent_logs'), findsOneWidget);
    });

    testWidgets('renders empty box when no candidate matches', (tester) async {
      await tester.pumpWidget(
        _buildMenu(prefix: 'zz', candidates: <String>['users']),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsNothing);
      expect(find.text('users'), findsNothing);
    });

    testWidgets('tapping a candidate reports the table name', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(
        _buildMenu(
          candidates: <String>['users', 'orders'],
          onTableSelected: selected.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('orders'));
      await tester.pumpAndSettle();

      expect(selected, <String>['orders']);
    });

    testWidgets('highlight index marks exactly one row', (tester) async {
      await tester.pumpWidget(
        _buildMenu(candidates: <String>['users', 'orders'], highlightIndex: 1),
      );
      await tester.pumpAndSettle();

      final highlight = find.byKey(const ValueKey('aiTableMentionHighlight'));
      expect(highlight, findsOneWidget);
      final Text rowText = tester.widget(
        find.descendant(of: highlight, matching: find.byType(Text)).first,
      );
      expect(rowText.data, 'orders');
    });

    testWidgets('out-of-range highlight index clamps to the last row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildMenu(candidates: <String>['users', 'orders'], highlightIndex: 99),
      );
      await tester.pumpAndSettle();

      final highlight = find.byKey(const ValueKey('aiTableMentionHighlight'));
      expect(highlight, findsOneWidget);
      final Text rowText = tester.widget(
        find.descendant(of: highlight, matching: find.byType(Text)).first,
      );
      expect(rowText.data, 'orders');
    });
  });
}
