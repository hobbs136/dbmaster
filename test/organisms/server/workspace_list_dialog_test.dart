//! Widget smoke test for the Workspaces manager dialog (#26). Mirrors the
//! team-query / task-list dialog tests: renders the title + Add/Join header
//! actions + surfaces the not-connected state gracefully. The dialog reads the
//! [WorkspaceProvider], so the test supplies one (its default shouldRefresh
//! guard is false because ServerConnection is not connected → no fetch).

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/server/workspace/workspace_list_dialog.dart';
import 'package:dbmaster/providers/workspace_provider.dart';
import 'package:dbmaster/services/server_connection.dart';

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
  }) =>
      Future.value(_store[key]);

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

  testWidgets('renders title + Add/Join actions + not-connected state gracefully',
      (tester) async {
    await tester.pumpWidget(
      // Provider wraps MaterialApp so the dialog (rendered in the Navigator
      // overlay) can resolve WorkspaceProvider — mirrors main.dart structure.
      ChangeNotifierProvider<WorkspaceProvider>(
        create: (_) => WorkspaceProvider(shouldRefresh: () => false),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showWorkspaceListDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Title is visible.
    expect(find.text('Workspaces'), findsOneWidget);
    // Header actions present (tooltips).
    expect(find.byTooltip('New workspace'), findsOneWidget);
    expect(find.byTooltip('Join workspace'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    // Not connected → dialog renders the not-connected centered message.
    expect(
        find.text('Connect to a DbMaster server to manage workspaces.'),
        findsOneWidget);
  });
}
