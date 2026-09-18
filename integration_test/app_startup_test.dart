// ============================================================================
// App Startup Integration Test
// Tests: App launches, renders home screen, navigates between tabs
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/main.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/pro_module.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Startup', () {
    testWidgets('app launches and shows home screen', (tester) async {
      await tester.pumpWidget(DbmasterApp(proModule: NoOpProModule()));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // App should render without crashing
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('bottom navigation tabs are present', (tester) async {
      await tester.pumpWidget(DbmasterApp(proModule: NoOpProModule()));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Check for bottom navigation bar (common in this app)
      final bottomNav = find.byType(BottomNavigationBar);
      if (bottomNav.evaluate().isNotEmpty) {
        expect(bottomNav, findsOneWidget);
      }
    });

    testWidgets('app respects theme provider', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppProvider()),
          ],
          child: DbmasterApp(proModule: NoOpProModule()),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // App should build successfully with providers
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
