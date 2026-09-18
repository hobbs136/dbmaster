//! Widget smoke test for the data sync task list dialog. Verifies the dialog
//! pumps under a minimal MaterialApp, renders the title + header buttons
//! (including the create-task Add button that closes TASKS #1), and surfaces
//! the not-connected state gracefully — mirroring the drift/health dialog tests.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/server/data_sync/data_sync_task_list_dialog.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// In-memory FlutterSecureStorage fake (same shape as the drift/health dialog
/// tests). ServerConnection persists the refresh token via FlutterSecureStorage,
/// whose MethodChannel is unavailable in unit tests.
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) => Future.value(_store[key]);

  @override
  Future<void> write({
    required String key,
    required String? value,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
    return Future.value();
  }

  @override
  Future<void> delete({
    required String key,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) {
    _store.remove(key);
    return Future.value();
  }
}

void main() {
  setUp(() {
    ServerConnection.resetForTesting();
    ServerConnection().testSecureStorage = _FakeSecureStorage();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  testWidgets(
    'renders title, header add+refresh buttons, and not-connected state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDataSyncTaskListDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      // Open the dialog.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // Title is visible.
      expect(find.text('Data Sync Tasks'), findsOneWidget);
      // Header create-task (Add) button — the entry added to close TASKS #1.
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      // Header refresh button.
      expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);

      // Not connected → graceful message (DataSyncApiService short-circuits when
      // no Server session, so the dialog renders the not-connected centered
      // message instead of the task list).
      expect(find.text('Not connected to a DbMaster server.'), findsOneWidget);
    },
  );
}
