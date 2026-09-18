//! Widget smoke test for [ApprovalListDialog] (#25). Mirrors the team-query /
//! data_sync / drift task-list dialog tests: renders the title + surfaces the
//! not-connected state gracefully (ApprovalApiService short-circuits when no
//! Server session is active). A real [ApprovalProvider] is injected with
// `shouldRefresh: false` so the constructor's auto-evaluate stays quiet.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ddl_approval.dart';
import 'package:dbmaster/models/drift_models.dart';
import 'package:dbmaster/organisms/server/approval/approval_list_dialog.dart';
import 'package:dbmaster/providers/approval_provider.dart';
import 'package:dbmaster/services/approval_api_service.dart';
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

/// Fake service feeding the provider + dialog a fixed approval list (U10 —
/// render coverage for failed rows carrying exec_error). `isConnected` is
/// forced true so the dialog renders the list instead of the not-connected
/// message; `listConnections` stays empty (name resolution falls back to id).
class _FakeApi extends ApprovalApiService {
  final List<DdlApproval> approvals;
  _FakeApi(this.approvals);

  @override
  bool get isConnected => true;

  @override
  Future<List<DdlApproval>> list() async => approvals;

  @override
  Future<List<DriftSourceConnection>> listConnections() async => [];
}

DdlApproval _approval({
  required String id,
  required String status,
  String? execError,
}) {
  return DdlApproval(
    id: id,
    submitterId: 'u1',
    ddlSql: 'ALTER TABLE t ADD c INT',
    targetDbId: 'conn-1',
    reviewerId: status == 'pending' ? null : 'u2',
    status: status,
    createdAt: '2026-08-17T10:00:00Z',
    resolvedAt: status == 'pending' ? null : '2026-08-17T11:00:00Z',
    execStatus: status == 'pending' ? null : status,
    execError: execError,
  );
}

void main() {
  setUp(() {
    ServerConnection.resetForTesting();
    ServerConnection().testSecureStorage = _FakeSecureStorage();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  Future<void> _pumpApp(WidgetTester tester, {ApprovalApiService? api}) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ApprovalProvider>(
        create: (_) => ApprovalProvider(
            api: api, shouldRefresh: () => api != null),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showApprovalListDialog(context, api: api),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders title + not-connected state gracefully', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Title is visible.
    expect(find.text('DDL Approvals'), findsOneWidget);
    // Not connected → ApprovalApiService short-circuits, dialog renders the
    // not-connected centered message instead of the approval list.
    expect(find.text('Connect to a DbMaster server to view approvals.'),
        findsOneWidget);
  });

  testWidgets('failed row shows the exec error inline (U10)', (tester) async {
    final api = _FakeApi([
      _approval(id: 'f1', status: 'failed', execError: 'mysql: syntax error near c'),
      _approval(id: 'p1', status: 'pending'),
    ]);
    await _pumpApp(tester, api: api);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('DDL Approvals'), findsOneWidget);
    // Failed row: one inline single-line error preview; the pending row has
    // no execution outcome and must not render an error line.
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Error: mysql: syntax error near c'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('view-DDL dialog for a failed row shows the full error (U10)',
      (tester) async {
    final api = _FakeApi([
      _approval(
          id: 'f1',
          status: 'failed',
          execError: 'mysql: connect failed: connection refused (timed out after 30s)'),
    ]);
    await _pumpApp(tester, api: api);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Resolved rows expose the eye-icon action (tooltip = approvalViewDdl).
    await tester.tap(find.byTooltip('View DDL'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('View DDL'), findsOneWidget);
    // Full text appears in the detail dialog on top of the inline preview.
    expect(
      find.textContaining(
          'Error: mysql: connect failed: connection refused (timed out after 30s)'),
      findsNWidgets(2),
    );
  });
}
