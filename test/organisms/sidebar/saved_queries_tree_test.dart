import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbServer;
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/organisms/sidebar/saved_queries/saved_queries_section.dart';

/// Test subclass of [AppProvider] that bypasses real connection checks when
/// opening a saved query, allowing widget tests to focus on UI behavior.
class TestAppProvider extends AppProvider {
  @override
  Future<void> openSavedQuery(QueryTab savedQuery) async {
    await tab.openQueryTab(
      connectionId: savedQuery.connectionId!,
      databaseName: savedQuery.databaseName!,
      sql: savedQuery.sql,
      title: savedQuery.title,
      savedQueryId: savedQuery.savedQueryId ?? savedQuery.id,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const _androidChannelName =
      'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi';
  const _storekitChannelName =
      'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchaseApi';

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_androidChannelName, (message) async {
          return const StandardMessageCodec().encodeMessage(
            <String, dynamic>{},
          );
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_storekitChannelName, (message) async {
          return const StandardMessageCodec().encodeMessage(
            <String, dynamic>{},
          );
        });
  });

  Future<TestAppProvider> _createProviderWithSavedQueries(
    List<QueryTab> savedQueries,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final provider = TestAppProvider();
    provider.connection.saveConnection(
      DbServer(
        id: 'test-conn',
        name: 'Test Connection',
        host: 'localhost',
        port: 8123,
        type: DatabaseType.sqlite, // T29 第三批：CH 已 gateway-backed，占位切 sqlite
      ),
    );
    for (final q in savedQueries) {
      await provider.tab.saveQuery(q);
    }
    return provider;
  }

  Widget _buildSection(
    TestAppProvider provider, {
    Set<String> expandedItems = const {},
    void Function(String)? onToggleExpand,
    void Function(String)? onSelectNode,
  }) {
    return ChangeNotifierProvider<AppProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 400,
            child: SavedQueriesSection(
              connectionId: 'test-conn',
              searchQuery: '',
              expandedItems: expandedItems,
              onToggleExpand: onToggleExpand ?? (_) {},
              onSelectNode: onSelectNode ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  group('SavedQueriesSection', () {
    testWidgets('shows Saved Queries node under every connection', (
      tester,
    ) async {
      final provider = await _createProviderWithSavedQueries([]);

      await tester.pumpWidget(_buildSection(provider));
      await tester.pumpAndSettle();

      expect(find.text('Saved Queries (0)'), findsOneWidget);
    });

    testWidgets('lists saved queries when expanded', (tester) async {
      final provider = await _createProviderWithSavedQueries([
        QueryTab(
          id: 'q1',
          title: 'User Query',
          sql: 'SELECT * FROM users',
          isSaved: true,
          connectionId: 'test-conn',
          databaseName: 'test-db',
        ),
      ]);

      await tester.pumpWidget(
        _buildSection(provider, expandedItems: {'test-conn:saved_queries'}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved Queries (1)'), findsOneWidget);
      expect(find.text('User Query'), findsOneWidget);
    });

    testWidgets('shows empty state when no saved queries', (tester) async {
      final provider = await _createProviderWithSavedQueries([]);

      await tester.pumpWidget(
        _buildSection(provider, expandedItems: {'test-conn:saved_queries'}),
      );
      await tester.pumpAndSettle();

      expect(find.text('No saved queries'), findsOneWidget);
    });

    testWidgets('single-clicking a saved query selects it', (tester) async {
      final provider = await _createProviderWithSavedQueries([
        QueryTab(
          id: 'q1',
          savedQueryId: 'saved-1',
          title: 'User Query',
          sql: 'SELECT * FROM users',
          isSaved: true,
          connectionId: 'test-conn',
          databaseName: 'test-db',
        ),
      ]);

      String? selectedKey;
      await tester.pumpWidget(
        _buildSection(
          provider,
          expandedItems: {'test-conn:saved_queries'},
          onSelectNode: (key) => selectedKey = key,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('User Query'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(selectedKey, 'savedquery:test-conn:saved-1');
      expect(provider.tab.tabs.length, 0);
    });

    testWidgets('double-clicking a saved query opens a new tab', (
      tester,
    ) async {
      final provider = await _createProviderWithSavedQueries([
        QueryTab(
          id: 'q1',
          savedQueryId: 'saved-1',
          title: 'User Query',
          sql: 'SELECT * FROM users',
          isSaved: true,
          connectionId: 'test-conn',
          databaseName: 'test-db',
        ),
      ]);

      await tester.pumpWidget(
        _buildSection(provider, expandedItems: {'test-conn:saved_queries'}),
      );
      await tester.pumpAndSettle();

      expect(provider.tab.tabs.length, 0);

      await tester.tap(find.text('User Query'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('User Query'));
      await tester.pumpAndSettle();

      expect(provider.tab.tabs.length, 1);
      expect(provider.tab.tabs.first.sql, 'SELECT * FROM users');
      expect(provider.tab.tabs.first.title, 'User Query');
      expect(provider.tab.tabs.first.savedQueryId, 'saved-1');
      expect(provider.tab.tabs.first.isSaved, isTrue);
      expect(provider.tab.tabs.first.isModified, isFalse);
    });

    testWidgets(
      'double-clicking an already open saved query activates the existing tab',
      (tester) async {
        final provider = await _createProviderWithSavedQueries([
          QueryTab(
            id: 'q1',
            savedQueryId: 'saved-1',
            title: 'User Query',
            sql: 'SELECT * FROM users',
            isSaved: true,
            connectionId: 'test-conn',
            databaseName: 'test-db',
          ),
        ]);

        // Pre-open the saved query
        await provider.openSavedQuery(provider.tab.savedQueries.first);
        expect(provider.tab.tabs.length, 1);
        provider.tab.addNewTab();
        provider.tab.setActiveTab(1);
        expect(provider.tab.activeTabIndex, 1);

        await tester.pumpWidget(
          _buildSection(provider, expandedItems: {'test-conn:saved_queries'}),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('User Query'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('User Query'));
        await tester.pumpAndSettle();

        expect(provider.tab.tabs.length, 2);
        expect(provider.tab.activeTabIndex, 0);
      },
    );

    testWidgets('rename updates the saved query title', (tester) async {
      final provider = await _createProviderWithSavedQueries([
        QueryTab(
          id: 'q1',
          title: 'Old Title',
          sql: 'SELECT 1',
          isSaved: true,
          connectionId: 'test-conn',
          databaseName: 'test-db',
        ),
      ]);

      await tester.pumpWidget(
        _buildSection(provider, expandedItems: {'test-conn:saved_queries'}),
      );
      await tester.pumpAndSettle();

      final target = find.text('Old Title');
      expect(target, findsOneWidget);
      final center = tester.getCenter(target);
      await tester.tapAt(center, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New Title');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(provider.tab.savedQueries.first.title, 'New Title');
    });

    testWidgets('delete removes the saved query node', (tester) async {
      final provider = await _createProviderWithSavedQueries([
        QueryTab(
          id: 'q1',
          title: 'To Delete',
          sql: 'SELECT 1',
          isSaved: true,
          connectionId: 'test-conn',
          databaseName: 'test-db',
        ),
      ]);

      await tester.pumpWidget(
        _buildSection(provider, expandedItems: {'test-conn:saved_queries'}),
      );
      await tester.pumpAndSettle();

      final target = find.text('To Delete');
      final center = tester.getCenter(target);
      await tester.tapAt(center, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Query'));
      await tester.pumpAndSettle();

      expect(find.text('To Delete'), findsNothing);
      expect(provider.tab.savedQueries.length, 0);
    });
  });
}
