import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

Widget _buildQueryEditorTest(AppProvider provider, {int tabIndex = 0}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('zh')],
    locale: const Locale('en'),
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<LayoutPreferencesProvider>(
          create: (_) => LayoutPreferencesProvider(),
        ),
      ],
      child: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: QueryEditorWidget(tabIndex: tabIndex),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock in_app_purchase Pigeon channels so [AppProvider] can be constructed
  // in widget tests without platform errors.
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

  group('QueryEditorShortcuts (US3)', () {
    Future<AppProvider> _createProvider() async {
      SharedPreferences.setMockInitialValues({});
      final provider = AppProvider();
      provider.connection.saveConnection(
        DbServer(
          id: 'test-conn',
          name: 'Test Connection',
          host: 'localhost',
          port: 8123,
          type: DatabaseType.sqlite, // T29 第三批：CH 已 gateway-backed，占位切 sqlite
        ),
      );
      await provider.tab.openQueryTab(
        connectionId: 'test-conn',
        databaseName: 'test-db',
      );
      return provider;
    }

    testWidgets('Ctrl+S saves non-empty query as a saved query', (
      tester,
    ) async {
      final provider = await _createProvider();
      provider.updateTabSql(0, 'SELECT * FROM users');

      await tester.pumpWidget(_buildQueryEditorTest(provider));
      await tester.pumpAndSettle();

      expect(provider.tab.savedQueries.length, 0);

      // Focus the editor and trigger Ctrl+S.
      await tester.tap(find.byType(ReSqlEditor));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // New query should show the naming dialog.
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(provider.tab.savedQueries.length, 1);
      expect(provider.tab.savedQueries.first.sql, 'SELECT * FROM users');
      expect(provider.tab.savedQueries.first.connectionId, 'test-conn');
      expect(provider.tab.savedQueries.first.databaseName, 'test-db');
    });

    testWidgets('Ctrl+S on empty editor is a no-op', (tester) async {
      final provider = await _createProvider();
      provider.updateTabSql(0, '');

      await tester.pumpWidget(_buildQueryEditorTest(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ReSqlEditor));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(provider.tab.savedQueries.length, 0);
      expect(provider.queryHistory.historyCount, 0);
    });

    testWidgets('Ctrl+S on existing saved query saves without dialog', (
      tester,
    ) async {
      final provider = await _createProvider();
      provider.updateTabSql(0, 'SELECT 1');

      await tester.pumpWidget(_buildQueryEditorTest(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ReSqlEditor));
      await tester.pump();

      // First save creates the saved query via naming dialog.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(provider.tab.savedQueries.length, 1);
      final firstId = provider.tab.savedQueries.first.id;

      // Modify SQL and save again（re_editor 无 EditableText，经门面设值）。
      tester
          .state<QueryEditorWidgetState>(find.byType(QueryEditorWidget))
          .controller
          .text = 'SELECT 2';
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // The tab now has a savedQueryId, so the second save is direct.
      expect(find.byType(AlertDialog), findsNothing);
      expect(provider.tab.savedQueries.length, 1);
      expect(provider.tab.savedQueries.first.id, firstId);
      expect(provider.tab.savedQueries.first.sql, 'SELECT 2');
    });

    testWidgets('Ctrl+S cancel on new query does not save', (tester) async {
      final provider = await _createProvider();
      provider.updateTabSql(0, 'SELECT cancel');

      await tester.pumpWidget(_buildQueryEditorTest(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ReSqlEditor));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(provider.tab.savedQueries.length, 0);
    });

    // TRB-C21 回归（2026-08-24）：连接/库选择器的旧守卫（activeTab != null
    // → SizedBox.shrink，面包屑时代为消双显而设）在 BreadcrumbBar 退役后
    // 仍生效，致工具栏 isWorkspaceMode 推断（connectionSelector is SizedBox）
    // 恒真、右端四芯片（连接/库/LIMIT/超时）整组被吞。此处用真实
    // QueryEditorWidget + 活跃 tab 断言五入口常显。
    group('TRB-C21 回归：活跃 tab 下上下文芯片常显', () {
      testWidgets('连接/库/LIMIT/超时/⌘K 五入口全部渲染', (tester) async {
        final provider = await _createProvider();

        await tester.pumpWidget(_buildQueryEditorTest(provider));
        await tester.pumpAndSettle();

        expect(find.text('Test Connection'), findsOneWidget);
        expect(find.text('test-db'), findsOneWidget);
        expect(find.textContaining('LIMIT'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && RegExp(r'^(\d+s|∞)$').hasMatch(w.data ?? ''),
          ),
          findsOneWidget,
        );
        expect(find.text('Ctrl+K'), findsOneWidget);
      });
    });
  });
}
