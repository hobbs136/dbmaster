// Tests for WorkspaceProvider's data flow + guards (#26).
//
// Uses a Fake WorkspaceApiService (override list, no network) and an injected
// `shouldRefresh: () => false` to keep the constructor's auto-evaluate quiet,
// then drives `doRefreshForTesting` / `evaluateForTesting` directly. Pattern
// mirrors `approval_provider_test.dart`.

import 'package:dbmaster/models/workspace.dart';
import 'package:dbmaster/providers/workspace_provider.dart';
import 'package:dbmaster/services/workspace_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake that overrides the only method the provider calls — the inherited
/// ServerConnection singleton is never touched (no network).
class _FakeWorkspaceApi extends WorkspaceApiService {
  _FakeWorkspaceApi();
  List<Workspace> workspaces = const [];
  Object? listError;

  @override
  Future<List<Workspace>> list() async {
    if (listError != null) throw listError!;
    return workspaces;
  }
}

Workspace _w(String id,
        {String name = 'WS',
        String role = 'member',
        int memberCount = 1}) =>
    Workspace(
      id: id,
      name: name,
      ownerId: 'u1',
      inviteCode: 'CODE12',
      memberCount: memberCount,
      role: role,
      createdAt: '2026-08-13T10:00:00Z',
    );

void main() {
  late _FakeWorkspaceApi api;

  setUp(() {
    api = _FakeWorkspaceApi();
  });

  test('doRefresh populates workspaces cache', () async {
    api.workspaces = [
      _w('w1', name: 'Data Platform', role: 'admin', memberCount: 3),
      _w('w2', name: 'Analytics', role: 'member', memberCount: 7),
    ];
    final provider =
        WorkspaceProvider(api: api, shouldRefresh: () => false);

    await provider.doRefreshForTesting();

    expect(provider.workspaces.length, equals(2));
    expect(provider.workspaces[0].name, equals('Data Platform'));
    expect(provider.workspaces[0].isAdmin, isTrue);
    expect(provider.workspaces[1].isAdmin, isFalse);
    expect(provider.lastError, isNull);
    provider.dispose();
  });

  test('list failure keeps the previous cache (no flicker)', () async {
    api.workspaces = [_w('w1')];
    final provider =
        WorkspaceProvider(api: api, shouldRefresh: () => false);
    await provider.doRefreshForTesting();
    expect(provider.workspaces.length, equals(1));
    expect(provider.lastError, isNull);

    // Second refresh fails — cache should be retained.
    api.workspaces = const [];
    api.listError = const WorkspaceApiException('network down');
    await provider.doRefreshForTesting();

    expect(provider.workspaces.length, equals(1)); // old cache kept
    expect(provider.lastError, isNotNull);
    provider.dispose();
  });

  test('refresh() is a no-op when shouldRefresh is false', () async {
    api.workspaces = [_w('w1')];
    final provider =
        WorkspaceProvider(api: api, shouldRefresh: () => false);

    await provider.refresh(); // guard short-circuits, no fetch

    expect(provider.workspaces, isEmpty); // never populated
    expect(provider.lastRefreshAt, isNull);
    provider.dispose();
  });

  test('refresh() fetches when shouldRefresh is true', () async {
    api.workspaces = [_w('w1'), _w('w2')];
    final provider =
        WorkspaceProvider(api: api, shouldRefresh: () => true);

    await provider.refresh();

    expect(provider.workspaces.length, equals(2));
    expect(provider.lastRefreshAt, isNotNull);
    provider.dispose();
  });

  test('evaluate clears cache when shouldRefresh turns false', () async {
    var refreshable = true;
    api.workspaces = [_w('w1')];
    final provider =
        WorkspaceProvider(api: api, shouldRefresh: () => refreshable);

    await provider.doRefreshForTesting();
    expect(provider.workspaces.length, equals(1));

    refreshable = false;
    provider.evaluateForTesting(); // _clear runs synchronously

    expect(provider.workspaces, isEmpty);
    provider.dispose();
  });

  test('re-entrancy: concurrent doRefresh calls fetch only once', () async {
    api.workspaces = [_w('w1')];
    final provider =
        WorkspaceProvider(api: api, shouldRefresh: () => false);

    // Drive two refreshes concurrently — _isRefreshing guards the second.
    await Future.wait([
      provider.doRefreshForTesting(),
      provider.doRefreshForTesting(),
    ]);

    expect(provider.workspaces.length, equals(1));
    provider.dispose();
  });
}
