// Tests for ApprovalProvider's data flow + guards (#25).
//
// Uses a Fake ApprovalApiService (override list, no network) and an injected
// `shouldRefresh: () => false` to keep the constructor's auto-evaluate quiet,
// then drives `doRefreshForTesting` / `evaluateForTesting` directly. Pattern
// mirrors `health_check_provider_test.dart`.

import 'package:dbmaster/models/ddl_approval.dart';
import 'package:dbmaster/providers/approval_provider.dart';
import 'package:dbmaster/services/approval_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake that overrides the only method the provider calls — the inherited
/// ServerConnection singleton is never touched (no network).
class _FakeApprovalApi extends ApprovalApiService {
  _FakeApprovalApi();
  List<DdlApproval> approvals = const [];
  Object? listError;

  @override
  Future<List<DdlApproval>> list() async {
    if (listError != null) throw listError!;
    return approvals;
  }
}

DdlApproval _a(String id, {String status = 'pending'}) => DdlApproval(
      id: id,
      submitterId: 'u1',
      ddlSql: 'CREATE TABLE t(id INT)',
      targetDbId: 'c1',
      status: status,
      createdAt: '2026-08-13T10:00:00Z',
    );

void main() {
  late _FakeApprovalApi api;

  setUp(() {
    api = _FakeApprovalApi();
  });

  test('doRefresh populates approvals + pendingCount', () async {
    api.approvals = [_a('a1'), _a('a2', status: 'executing'), _a('a3')];
    final provider =
        ApprovalProvider(api: api, shouldRefresh: () => false);

    await provider.doRefreshForTesting();

    expect(provider.approvals.length, equals(3));
    expect(provider.pendingCount, equals(2)); // a1 + a3 pending
    expect(provider.executingCount, equals(1)); // a2 executing
    provider.dispose();
  });

  test('pendingCount counts only pending; executingCount only executing',
      () async {
    api.approvals = [
      _a('a1', status: 'pending'),
      _a('a2', status: 'executing'),
      _a('a3', status: 'approved'),
      _a('a4', status: 'failed'),
      _a('a5', status: 'rejected'),
      _a('a6', status: 'pending'),
    ];
    final provider =
        ApprovalProvider(api: api, shouldRefresh: () => false);

    await provider.doRefreshForTesting();

    expect(provider.pendingCount, equals(2)); // a1 + a6
    expect(provider.executingCount, equals(1)); // a2
    provider.dispose();
  });

  test('list failure keeps the previous cache (no flicker)', () async {
    api.approvals = [_a('a1')];
    final provider =
        ApprovalProvider(api: api, shouldRefresh: () => false);
    await provider.doRefreshForTesting();
    expect(provider.pendingCount, equals(1));
    expect(provider.lastError, isNull);

    // Second refresh fails — cache should be retained.
    api.approvals = const [];
    api.listError = const ApprovalApiException('network down');
    await provider.doRefreshForTesting();

    expect(provider.approvals.length, equals(1)); // old cache kept
    expect(provider.pendingCount, equals(1));
    expect(provider.lastError, isNotNull);
    provider.dispose();
  });

  test('refresh() is a no-op when shouldRefresh is false', () async {
    api.approvals = [_a('a1')];
    final provider =
        ApprovalProvider(api: api, shouldRefresh: () => false);

    await provider.refresh(); // guard short-circuits, no fetch

    expect(provider.approvals, isEmpty); // never populated
    expect(provider.lastRefreshAt, isNull);
    provider.dispose();
  });

  test('refresh() fetches when shouldRefresh is true', () async {
    api.approvals = [_a('a1'), _a('a2')];
    final provider =
        ApprovalProvider(api: api, shouldRefresh: () => true);

    await provider.refresh();

    expect(provider.approvals.length, equals(2));
    expect(provider.pendingCount, equals(2));
    expect(provider.lastRefreshAt, isNotNull);
    provider.dispose();
  });

  test('evaluate clears cache when shouldRefresh turns false', () async {
    var refreshable = true;
    api.approvals = [_a('a1')];
    final provider =
        ApprovalProvider(api: api, shouldRefresh: () => refreshable);

    await provider.doRefreshForTesting();
    expect(provider.pendingCount, equals(1));

    refreshable = false;
    provider.evaluateForTesting(); // _clear runs synchronously

    expect(provider.approvals, isEmpty);
    expect(provider.pendingCount, equals(0));
    provider.dispose();
  });
}
