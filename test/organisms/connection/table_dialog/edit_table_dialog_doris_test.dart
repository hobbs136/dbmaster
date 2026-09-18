import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/table_dialog/edit_table_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

// ============================================================================
// EditTableDialog Doris Widget Tests
// 验证 Doris 连接下编辑表对话框不展示 MySQL 专属选项。
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      await prefs.remove(key);
    }
  });

  Future<AppProvider> _pumpEditTableDialog(
    WidgetTester tester, {
    required DatabaseType databaseType,
  }) async {
    tester.binding.setSurfaceSize(const Size(1000, 800));

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    await themeProvider.load();
    await localeProvider.load();

    final appProvider = AppProvider();

    final table = DbTable(
      name: 'users',
      columns: [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(255)', isNullable: true),
      ],
      indexes: [],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
        ],
        child: Consumer2<LocaleProvider, ThemeProvider>(
          builder: (context, locale, theme, _) {
            return MaterialApp(
              locale: locale.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(theme.accentColorValue),
              home: Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditTableDialog(
                          dbName: 'test_db',
                          table: table,
                        ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    final server = DbServer(
      id: 'test_conn',
      name: 'Test Connection',
      type: databaseType,
      host: 'localhost',
      port: databaseType == DatabaseType.doris ? 9030 : 3306,
      username: 'root',
      password: '',
      database: 'test_db',
    );
    appProvider.connection.setCurrentServer(server);

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.byType(EditTableDialog), findsOneWidget);

    return appProvider;
  }

  group('EditTableDialog Doris 连接', () {
    testWidgets('不应显示 AI（AUTO_INCREMENT）列', (WidgetTester tester) async {
      await _pumpEditTableDialog(tester, databaseType: DatabaseType.doris);

      expect(find.text('AI'), findsNothing);
    });

    testWidgets('数据类型下拉不应包含 MySQL 专属类型', (
      WidgetTester tester,
    ) async {
      await _pumpEditTableDialog(tester, databaseType: DatabaseType.doris);

      // 编辑对话框只有 charset(0) 与 dataType(1) 两个 String 下拉
      final dropdownFinder = find.descendant(
        of: find.byType(DropdownButtonFormField<String>).at(1),
        matching: find.byType(DropdownButton<String>),
      );
      final dropdown = tester.widget<DropdownButton<String>>(dropdownFinder);
      final itemValues = dropdown.items?.map((i) => i.value).toList() ?? [];

      expect(itemValues, isNot(contains('ENUM')));
      expect(itemValues, isNot(contains('LONGTEXT')));
      expect(itemValues, contains('BOOLEAN'));
      expect(itemValues, contains('STRING'));
    });
  });

  group('EditTableDialog MySQL 连接', () {
    testWidgets('应继续显示 AI 列', (WidgetTester tester) async {
      await _pumpEditTableDialog(tester, databaseType: DatabaseType.mysql);

      expect(find.text('AI'), findsOneWidget);
    });
  });
}
