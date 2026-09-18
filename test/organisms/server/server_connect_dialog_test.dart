// Widget tests for ServerConnectDialog
// =============================================================================
// Tests dialog rendering, field validation, connect button state.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'package:dbmaster/organisms/server/server_connect_dialog.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// In-memory stand-in for the secure-storage method channel.
final secureStorage = <String, String>{};

/// Canned HTTP client for the one-click reconnect path.
class _FakeClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) _handler;
  _FakeClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    final response = await _handler(req);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      contentLength: response.bodyBytes.length,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

/// Helper: pump the connect dialog triggered from a button.
Future<void> _openDialog(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(Colors.blue),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          return ElevatedButton(
            key: const Key('trigger'),
            onPressed: () {
              final provider = ServerConnectionProvider();
              showServerConnectDialog(context, provider);
            },
            child: const Text('Open'),
          );
        },
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('trigger')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
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
    ServerConnection.resetForTesting();
  });

  group('ServerConnectDialog', () {
    testWidgets('renders with empty fields', (tester) async {
      await _openDialog(tester);

      expect(find.text('Connect to Server'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog', (tester) async {
      await _openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to Server'), findsNothing);
    });

    testWidgets('URL field exists', (tester) async {
      await _openDialog(tester);
      // Find URL field by its label
      expect(find.text('Server URL'), findsOneWidget);
    });

    testWidgets('Email field exists', (tester) async {
      await _openDialog(tester);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('Password field exists with obscured text', (tester) async {
      await _openDialog(tester);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byIcon(LucideIcons.lock), findsOneWidget);
    });

    testWidgets('text fields accept input', (tester) async {
      await _openDialog(tester);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'https://example.com:3000',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'password123');

      // Dialog still open — fields accept input without crash
      await tester.pump();
      expect(find.text('Connect to Server'), findsOneWidget);
    });

    testWidgets('Connect button exists', (tester) async {
      await _openDialog(tester);

      // Connect button is in the actions area
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    });

    testWidgets('form has three TextFormFields', (tester) async {
      await _openDialog(tester);

      expect(find.byType(TextFormField), findsNWidgets(3));
    });

    // ── Stored-session prefill & one-click reconnect（#32 U02）──

    testWidgets('prefills url and email from the stored session', (
      tester,
    ) async {
      secureStorage['server_url'] = 'https://srv:3000';
      secureStorage['server_email'] = 'a@b.com';
      secureStorage['server_refresh_token'] = 'rt';
      await _openDialog(tester);
      await tester.pump(); // let the async prefill future land

      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'https://srv:3000',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'a@b.com',
      );
      expect(find.text('Reconnect to last server'), findsOneWidget);
    });

    testWidgets('no reconnect button without a stored refresh token', (
      tester,
    ) async {
      secureStorage['server_url'] = 'https://srv:3000';
      await _openDialog(tester);
      await tester.pump();

      expect(find.text('Reconnect to last server'), findsNothing);
    });

    testWidgets('one-click reconnect restores the session without a password', (
      tester,
    ) async {
      secureStorage['server_url'] = 'https://srv:3000';
      secureStorage['server_email'] = 'a@b.com';
      secureStorage['server_refresh_token'] = 'rt';
      ServerConnection().testHttpClient = _FakeClient((req) async {
        if (req.url.path.endsWith('refresh')) {
          return http.Response(
            jsonEncode({'access_token': 'at', 'refresh_token': 'rt2'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('me')) {
          return http.Response(
            jsonEncode({
              'id': 'u1',
              'email': 'a@b.com',
              'display_name': 'Test',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('NF', 404);
      });

      await _openDialog(tester);
      await tester.pump();

      await tester.tap(find.text('Reconnect to last server'));
      await tester.pumpAndSettle();

      // Dialog closed on success; the session is live again.
      expect(find.text('Connect to Server'), findsNothing);
      expect(
        ServerConnection().connectionState,
        ServerConnectionState.connected,
      );
      // Cancel the 30s heartbeat timer the restore started — widget tests
      // fail on pending timers once the tree is disposed.
      ServerConnection.resetForTesting();
    });

    testWidgets('failed one-click reconnect shows a fallback error', (
      tester,
    ) async {
      secureStorage['server_url'] = 'https://srv:3000';
      secureStorage['server_refresh_token'] = 'revoked';
      ServerConnection().testHttpClient = _FakeClient(
        (req) async => http.Response(
          jsonEncode({'error': 'revoked'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      );

      await _openDialog(tester);
      await tester.pump();

      await tester.tap(find.text('Reconnect to last server'));
      await tester.pumpAndSettle();

      expect(find.text('Connect to Server'), findsOneWidget);
      expect(
        find.text(
          'The stored session is no longer valid. Please sign in again.',
        ),
        findsOneWidget,
      );
    });
  });
}
