import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/table_dialog/create_table_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

// ============================================================================
// CreateTableDialog Doris Widget Tests
// 验证 Doris 连接下创建表对话框不展示 MySQL 专属选项。
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

  Future<AppProvider> _pumpCreateTableDialog(
    WidgetTester tester, {
    required DatabaseType databaseType,
  }) async {
    tester.binding.setSurfaceSize(const Size(1000, 800));

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    await themeProvider.load();
    await localeProvider.load();

    final appProvider = AppProvider();

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
                        builder: (_) => const CreateTableDialog(dbName: 'test_db'),
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

    // 注入目标类型的连接（不真正连接，仅影响对话框的数据库类型判断）
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

    expect(find.byType(CreateTableDialog), findsOneWidget);

    return appProvider;
  }

  group('CreateTableDialog Doris 连接', () {
    testWidgets('不应显示引擎下拉', (WidgetTester tester) async {
      await _pumpCreateTableDialog(tester, databaseType: DatabaseType.doris);

      expect(find.text('InnoDB'), findsNothing);
      expect(find.text('MyISAM'), findsNothing);
    });

    testWidgets('不应显示 AI（AUTO_INCREMENT）列', (WidgetTester tester) async {
      await _pumpCreateTableDialog(tester, databaseType: DatabaseType.doris);

      // 列定义表头中不应有 AI
      expect(find.text('AI'), findsNothing);
    });

    testWidgets('数据类型下拉不应包含 MySQL 专属类型', (
      WidgetTester tester,
    ) async {
      await _pumpCreateTableDialog(tester, databaseType: DatabaseType.doris);

      // 直接读取第一个列数据类型下拉的所有选项
      // Doris 下顺序大致为：charset(0)、model(1)、dataType(2)
      final dropdownFinder = find.descendant(
        of: find.byType(DropdownButtonFormField<String>).at(2),
        matching: find.byType(DropdownButton<String>),
      );
      final dropdown = tester.widget<DropdownButton<String>>(dropdownFinder);
      final itemValues = dropdown.items?.map((i) => i.value).toList() ?? [];

      expect(itemValues, isNot(contains('ENUM')));
      expect(itemValues, isNot(contains('SET')));
      expect(itemValues, isNot(contains('LONGTEXT')));
      expect(itemValues, isNot(contains('MEDIUMTEXT')));
      expect(itemValues, isNot(contains('YEAR')));
      expect(itemValues, isNot(contains('BIT')));
      expect(itemValues, isNot(contains('LONGBLOB')));
      expect(itemValues, isNot(contains('MEDIUMBLOB')));

      expect(itemValues, contains('BOOLEAN'));
      expect(itemValues, contains('LARGEINT'));
      expect(itemValues, contains('STRING'));
    });
  });

  group('CreateTableDialog MySQL 连接', () {
    testWidgets('应继续显示引擎下拉与 AI 列', (WidgetTester tester) async {
      await _pumpCreateTableDialog(tester, databaseType: DatabaseType.mysql);

      expect(find.text('InnoDB'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
    });
  });
}
