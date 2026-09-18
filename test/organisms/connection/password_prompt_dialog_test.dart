import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/password_prompt_dialog.dart';
import 'package:dbmaster/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(WidgetTester tester, Widget dialog) async {
    final themeProvider = ThemeProvider();
    await themeProvider.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: dialog,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PasswordPromptDialog', () {
    late DbServer server;
    final secureStorage = <String, String>{};

    setUp(() {
      server = DbServer(
        id: 'conn_1',
        name: 'Test MySQL',
        type: DatabaseType.mysql,
        host: 'localhost',
        port: 3306,
      );
      secureStorage.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              final args = call.arguments as Map<dynamic, dynamic>;
              final key = args['key'] as String?;
              switch (call.method) {
                case 'read':
                  return secureStorage[key];
                case 'write':
                  secureStorage[key!] = args['value'] as String;
                  return null;
                case 'delete':
                  secureStorage.remove(key);
                  return null;
                case 'readAll':
                  return secureStorage;
                case 'deleteAll':
                  secureStorage.clear();
                  return null;
                default:
                  return null;
              }
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    });

    testWidgets('save password checkbox is unchecked by default', (
      tester,
    ) async {
      await pumpDialog(tester, PasswordPromptDialog(server: server));

      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    });

    testWidgets('returns password when submitted without saving', (
      tester,
    ) async {
      String? result;
      await pumpDialog(
        tester,
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => PasswordPromptDialog(server: server),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(result, 'secret');
    });

    testWidgets('checkbox can be checked', (tester) async {
      await pumpDialog(tester, PasswordPromptDialog(server: server));

      final checkbox = find.byType(Checkbox);
      await tester.tap(checkbox);
      await tester.pump();

      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    });

    testWidgets('persists password when save checkbox is checked', (
      tester,
    ) async {
      await pumpDialog(tester, PasswordPromptDialog(server: server));

      await tester.enterText(find.byType(TextField), 'my_password');
      await tester.pump();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(
        secureStorage,
        containsPair('dbmaster_credentials_vault', isNotEmpty),
      );
      final vault = secureStorage['dbmaster_credentials_vault'];
      expect(vault, contains('"conn_1":"my_password"'));
      expect(server.password, 'my_password');
    });

    testWidgets('returns empty string when connecting without password', (
      tester,
    ) async {
      String? result;
      await pumpDialog(
        tester,
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => PasswordPromptDialog(server: server),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect Without Password'));
      await tester.pumpAndSettle();

      expect(result, '');
    });

    testWidgets(
      'ensurePassword returns server unchanged when connecting without password',
      (tester) async {
        DbServer? returned;
        await pumpDialog(
          tester,
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  returned = await PasswordPromptDialog.ensurePassword(
                    context,
                    server,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Connect Without Password'));
        await tester.pumpAndSettle();

        expect(returned, same(server));
        expect(returned!.password, isNull);
        expect(secureStorage, isEmpty);
      },
    );

    testWidgets(
      'saving password updates the in-memory server so reconnect does not prompt',
      (tester) async {
        await pumpDialog(
          tester,
          Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await PasswordPromptDialog.ensurePassword(context, server);
                },
                child: const Text('Open'),
              );
            },
          ),
        );

        expect(server.password, isNull);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'my_password');
        await tester.pump();

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        await tester.tap(find.text('Connect'));
        await tester.pumpAndSettle();

        expect(server.password, 'my_password');

        // 再次调用 ensurePassword 不应再弹出对话框
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(PasswordPromptDialog), findsNothing);
      },
    );
  });
}
