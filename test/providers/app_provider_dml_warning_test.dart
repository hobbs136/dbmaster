import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/services/database_service.dart';

/// Regression guard for the DML/DDL safety confirmation "Error label" bug
/// (see .workflows/dml-warning-confirm-noop/01-diagnose.md RC-1).
///
/// `AppProvider.executeCurrentQueryAndRecord` used to catch every exception —
/// including the control-flow signals [DmlWarningRequiredException],
/// [DmlConfirmationRequiredException] and [DdlConfirmationRequiredException]
/// — in one generic `catch (e)` and call `addErrorMessageToTab`, so a high-risk
/// DELETE-with-WHERE-no-LIMIT surfaced a red "Query failed, DmlWarningRequiredException"
/// sub-tab alongside the warning banner. These signals are control flow, not query
/// errors, and must propagate unrecorded for the editor to render the banner/dialog.
///
/// Subclasses the real [DatabaseService] (so its `transactionEvents`/`events`
/// Streams stay real and AppProvider construction is unaffected) and overrides
/// [executeQuery] to throw the control-flow exception — sidestepping the
/// null-return problem a Mockito `Mock` has on non-nullable getters.
class _ControlFlowThrowingDatabaseService extends DatabaseService {
  final Exception Function() _thrower;
  _ControlFlowThrowingDatabaseService(this._thrower);

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    throw _thrower();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deleteSql = 'DELETE FROM "users" WHERE "id" > 1';
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  DmlWarningRequiredException warningException() =>
      const DmlWarningRequiredException(
        sql: deleteSql,
        analysis: RiskAnalysisResult(
          riskLevel: DmlRiskLevel.high,
          triggers: [RiskTrigger.dmlWithoutLimit],
        ),
      );

  group('executeCurrentQueryAndRecord control-flow exceptions', () {
    late AppProvider appProvider;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      messenger.setMockMethodCallHandler(secureChannel, (call) async => null);

      appProvider = AppProvider(
        connectionProvider: ConnectionProvider(
          dbService: _ControlFlowThrowingDatabaseService(warningException),
        ),
      );
      appProvider.tab.addTab(QueryTab(id: 'tab-1', title: 'T', sql: deleteSql));
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(secureChannel, null);
    });

    /// Without the fix this fails: the generic catch recorded the exception as an
    /// error sub-tab (`hasError == true`). With the fix it propagates untouched.
    test(
        'DmlWarningRequiredException is rethrown and NOT recorded as an error sub-tab',
        () async {
      await expectLater(
        appProvider.executeCurrentQueryAndRecord(overrideSql: deleteSql),
        throwsA(isA<DmlWarningRequiredException>()),
      );

      final hasErrorSubTab =
          appProvider.tab.activeResults.any((r) => r.hasError);
      expect(
        hasErrorSubTab,
        isFalse,
        reason:
            'Control-flow DmlWarningRequiredException must surface as the warning '
            'banner, not a "Query failed" error sub-tab.',
      );
      expect(appProvider.tab.activeResults, isEmpty);
    });
  });
}
