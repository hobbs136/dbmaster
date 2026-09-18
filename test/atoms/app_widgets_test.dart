import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/atoms/app_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('StatusType', () {
    test('has 5 values', () {
      expect(StatusType.values.length, 5);
      expect(
        StatusType.values,
        containsAll([
          StatusType.success,
          StatusType.warning,
          StatusType.error,
          StatusType.info,
          StatusType.primary,
        ]),
      );
    });
  });

  group('AppStatusBadge', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders success badge with green tint', (tester) async {
      await tester.pumpWidget(
        wrap(const AppStatusBadge(text: 'Active', type: StatusType.success)),
      );
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('renders error badge with red tint', (tester) async {
      await tester.pumpWidget(
        wrap(const AppStatusBadge(text: 'Failed', type: StatusType.error)),
      );
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('renders warning badge', (tester) async {
      await tester.pumpWidget(
        wrap(const AppStatusBadge(text: 'Pending', type: StatusType.warning)),
      );
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('renders info badge', (tester) async {
      await tester.pumpWidget(
        wrap(const AppStatusBadge(text: 'Neutral', type: StatusType.info)),
      );
      expect(find.text('Neutral'), findsOneWidget);
    });

    testWidgets('renders primary badge with accent color', (tester) async {
      await tester.pumpWidget(
        wrap(const AppStatusBadge(text: 'New', type: StatusType.primary)),
      );
      expect(find.text('New'), findsOneWidget);
    });
  });

  group('AppEmptyState', () {
    Widget buildEmptyState({String? description, Widget? action}) {
      return MaterialApp(
        home: Scaffold(
          body: AppEmptyState(
            icon: LucideIcons.inbox,
            title: 'No Data',
            description: description,
            action: action,
          ),
        ),
      );
    }

    testWidgets('renders icon, title, and optional description', (
      tester,
    ) async {
      await tester.pumpWidget(buildEmptyState(description: 'No items found'));
      expect(find.text('No Data'), findsOneWidget);
      expect(find.text('No items found'), findsOneWidget);
      expect(find.byIcon(LucideIcons.inbox), findsOneWidget);
    });

    testWidgets('renders without description', (tester) async {
      await tester.pumpWidget(buildEmptyState());
      expect(find.text('No Data'), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      await tester.pumpWidget(
        buildEmptyState(
          action: ElevatedButton(
            onPressed: () {},
            child: const Text('Add Item'),
          ),
        ),
      );
      expect(find.text('Add Item'), findsOneWidget);
    });
  });

  group('AppLoadingOverlay', () {
    Widget buildOverlay({required bool isLoading, String? message}) {
      return MaterialApp(
        home: Scaffold(
          body: AppLoadingOverlay(
            isLoading: isLoading,
            message: message,
            child: const Text('Content'),
          ),
        ),
      );
    }

    testWidgets('shows content when not loading', (tester) async {
      await tester.pumpWidget(buildOverlay(isLoading: false));
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('shows progress indicator when loading', (tester) async {
      await tester.pumpWidget(
        buildOverlay(isLoading: true, message: 'Loading...'),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('shows loading without message', (tester) async {
      await tester.pumpWidget(buildOverlay(isLoading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
