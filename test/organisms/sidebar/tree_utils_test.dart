import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/sidebar/builders/tree_utils.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('tree_utils formatters', () {
    test('formatNumber returns raw value for numbers < 1000', () {
      expect(formatNumber(0), '0');
      expect(formatNumber(999), '999');
    });

    test('formatNumber uses K suffix for thousands', () {
      expect(formatNumber(1500), '1.5K');
      expect(formatNumber(1000), '1.0K');
    });

    test('formatNumber uses M suffix for millions', () {
      expect(formatNumber(1500000), '1.5M');
      expect(formatNumber(1000000), '1.0M');
    });

    test('formatTTL returns seconds for values < 60', () {
      expect(formatTTL(45), '45s');
    });

    test('formatTTL returns minutes and seconds for values < 3600', () {
      expect(formatTTL(125), '2m 5s');
    });

    test('formatTTL returns hours and minutes for values < 86400', () {
      expect(formatTTL(3665), '1h 1m');
    });

    test('formatTTL returns days and hours for large values', () {
      expect(formatTTL(90061), '1d 1h');
    });

    test('formatUptime handles null input', () {
      expect(formatUptime(null), 'N/A');
    });

    test('formatUptime parses string input', () {
      expect(formatUptime('3665'), '1h 1m');
    });

    test('formatUptime returns days hours minutes for long uptimes', () {
      expect(formatUptime(90061), '1d 1h 1m');
    });
  });

  group('tree_utils column icon helpers', () {
    test('getColumnIconInfo returns integer icon for INT types', () {
      final (icon, color) = getColumnIconInfo('INT');
      expect(icon, LucideIcons.pin);
      expect(color, isNotNull);
    });

    test('getColumnIconInfo returns text icon for VARCHAR', () {
      final (icon, color) = getColumnIconInfo('VARCHAR(255)');
      expect(icon, LucideIcons.type);
      expect(color, isNotNull);
    });

    test('getColumnIconInfo returns default icon for unknown type', () {
      final (icon, color) = getColumnIconInfo('UNKNOWN');
      expect(icon, LucideIcons.list);
      expect(color, isNotNull);
    });

    test('getTagTypeColor returns color for integer types', () {
      expect(getTagTypeColor('BIGINT'), isNotNull);
    });

    test('getIndexIconInfo returns primary key icon', () {
      final (icon, color) = getIndexIconInfo('PRIMARY', false);
      expect(icon, LucideIcons.keyRound);
      expect(color, isNotNull);
    });

    test('getIndexIconInfo returns foreign key icon', () {
      final (icon, color) = getIndexIconInfo(
        'FK_user_id',
        false,
        isForeignKey: true,
      );
      expect(icon, LucideIcons.link);
      expect(color, isNotNull);
    });

    test('getIndexIconInfo returns unique icon', () {
      final (icon, color) = getIndexIconInfo('UNIQUE_idx', true);
      expect(icon, LucideIcons.lock);
      expect(color, isNotNull);
    });
  });

  group('tree_utils widgets', () {
    testWidgets('buildInfoLeaf renders label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  buildInfoLeaf(context, LucideIcons.info, 'Info Leaf'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Info Leaf'), findsOneWidget);
      expect(find.byIcon(LucideIcons.info), findsOneWidget);
    });

    testWidgets('buildLoadingLeaf renders Loading label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => buildLoadingLeaf(context)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('buildSkeletonLeaf renders placeholder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => buildSkeletonLeaf(context)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('buildDivider renders horizontal line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => buildDivider(context)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final divider = tester.widget<Container>(find.byType(Container));
      expect(divider.constraints?.maxHeight, 1.0);
      expect(divider.color, isNotNull);
    });

    testWidgets('buildSkeletonPlaceholders renders N placeholders', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: buildSkeletonPlaceholders(context, count: 3),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final containers = find.byType(Container).evaluate().toList();
      expect(containers.length, greaterThanOrEqualTo(3));
    });

    // 共享 buildSimpleObjectCategory（PG + SQL Server 复用）
    testWidgets(
      'buildSimpleObjectCategory renders header with count, hides items when collapsed',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: buildSimpleObjectCategory(
                    context: context,
                    expandedItems: const {},
                    onToggleExpand: (_) {},
                    isSelected: (_) => false,
                    categoryKey: 'views',
                    icon: LucideIcons.eye,
                    label: 'Views',
                    items: const ['v1', 'v2'],
                    totalCount: 2,
                    sq: '',
                    level: 4,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Views (2)'), findsOneWidget);
        // Collapsed → individual items hidden.
        expect(find.text('v1'), findsNothing);
      },
    );

    testWidgets('buildSimpleObjectCategory renders items when expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ListView(
                children: buildSimpleObjectCategory(
                  context: context,
                  expandedItems: const {'views'},
                  onToggleExpand: (_) {},
                  isSelected: (_) => false,
                  categoryKey: 'views',
                  icon: LucideIcons.eye,
                  label: 'Views',
                  items: const ['v1', 'v2'],
                  totalCount: 2,
                  sq: '',
                  level: 4,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('v1'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
    });

    testWidgets(
      'buildSimpleObjectCategory search forces expansion and shows filtered count',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: buildSimpleObjectCategory(
                    context: context,
                    expandedItems: const {},
                    onToggleExpand: (_) {},
                    isSelected: (_) => false,
                    categoryKey: 'views',
                    icon: LucideIcons.eye,
                    label: 'Views',
                    items: const ['active'],
                    totalCount: 3,
                    sq: 'act',
                    level: 4,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // sq non-empty forces expansion → item visible; count shows "1/3".
        expect(find.text('active'), findsOneWidget);
        expect(find.text('Views (1/3)'), findsOneWidget);
      },
    );
  });
}
