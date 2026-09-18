// Unit tests for ServerConnection service
// =============================================================================
// Tests connect, disconnect, restoreSession, heartbeat transitions,
// and exponential backoff using a custom mock HTTP client.
// =============================================================================

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dbmaster/services/server_connection.dart';

/// Custom test HTTP client that returns canned responses.
///
/// Extends [http.BaseClient] and overrides [send] to intercept all requests.
class _TestClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) _handler;

  _TestClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Read the request body before the stream is consumed
    final bodyBytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;

    final response = await _handler(req);

    // Return a StreamedResponse that wraps the Response's bytes
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

/// Fake FlutterSecureStorage for testing.
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async {
    if (value == null) { _store.remove(key); } else { _store[key] = value; }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WindowsOptions? wOptions,
    MacOsOptions? mOptions, WebOptions? webOptions,
  }) async => _store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WindowsOptions? wOptions,
    MacOsOptions? mOptions, WebOptions? webOptions,
  }) async { _store.remove(key); }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WindowsOptions? wOptions,
    MacOsOptions? mOptions, WebOptions? webOptions,
  }) async { _store.clear(); }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WindowsOptions? wOptions,
    MacOsOptions? mOptions, WebOptions? webOptions,
  }) async => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions, AndroidOptions? aOptions,
    LinuxOptions? lOptions, WindowsOptions? wOptions,
    MacOsOptions? mOptions, WebOptions? webOptions,
  }) async => Map.unmodifiable(_store);
}

const _jsonHeader = {'content-type': 'application/json'};

/// Returns a JSON success response for login.
http.Response _okResponse(Map<String, dynamic> body) =>
  http.Response(jsonEncode(body), 200, headers: _jsonHeader);

/// Returns a JSON error response.
http.Response _errResponse(int statusCode, Map<String, dynamic> body) =>
  http.Response(jsonEncode(body), statusCode, headers: _jsonHeader);

Map<String, dynamic> _loginBody() => {
  'access_token': 'tok-access',
  'refresh_token': 'tok-refresh',
  'user': {'id': 'u1', 'email': 'a@b.com', 'display_name': 'Test'},
};

/// Minimal unsigned JWT-shaped token carrying only an `exp` claim — enough
/// for ServerConnection's expiry decode. The payload must sit in the JWT's
/// middle position ([header, payload, signature]); `_jwtExpiryEpoch` reads
/// `parts[1]`.
String _jwtWithExpiry(int expEpoch) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': expEpoch})));
  return 'e30.$payload.sig';
}

void main() {
  group('ServerConnection', () {
    late ServerConnection service;
    late FakeSecureStorage storage;

    setUp(() {
      storage = FakeSecureStorage();
      service = ServerConnection();
      ServerConnection.resetForTesting();
      // Set test dependencies AFTER reset (reset nulls them)
      service.testSecureStorage = storage;
    });

    tearDown(() {
      ServerConnection.resetForTesting();
    });

    // ── connect() ──

    test('connect succeeds with 200', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));

      await service.connect('https://srv:3000', 'a@b.com', 'pw');

      expect(service.connectionState, ServerConnectionState.connected);
      expect(service.userProfile?.email, 'a@b.com');
      expect(await storage.read(key: 'server_url'), 'https://srv:3000');
    });

    test('connect strips trailing slash', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));

      await service.connect('https://srv:3000/', 'a@b.com', 'pw');
      expect(service.serverUrl, 'https://srv:3000');
    });

    test('connect 401 → ServerConnectionException', () async {
      service.testHttpClient = _TestClient((_) async =>
        _errResponse(401, {'error': {'code': 'AUTH', 'message': 'Bad'}}));

      expect(
        () => service.connect('https://srv:3000', 'x@y.com', 'bad'),
        throwsA(isA<ServerConnectionException>()
          .having((e) => e.message, 'message', contains('Invalid email or password'))),
      );
    });

    test('connect 500 → ServerConnectionException with status', () async {
      service.testHttpClient = _TestClient((_) async =>
        _errResponse(500, {'error': 'ERR'}));

      expect(
        () => service.connect('https://srv:3000', 'a@b.com', 'pw'),
        throwsA(isA<ServerConnectionException>()
          .having((e) => e.message, 'message', contains('500'))),
      );
    });

    test('connect network error → user-friendly message', () async {
      service.testHttpClient = _TestClient((_) async => throw Exception('refused'));

      expect(
        () => service.connect('https://srv:3000', 'a@b.com', 'pw'),
        throwsA(isA<ServerConnectionException>()
          .having((e) => e.message, 'message', contains('Could not reach server'))),
      );
    });

    // ── disconnect() ──

    test('disconnect clears state', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      expect(service.connectionState, ServerConnectionState.connected);

      await service.disconnect();

      expect(service.connectionState, ServerConnectionState.disconnected);
      expect(service.userProfile, isNull);
      expect(service.serverUrl, isNull);
      expect(await storage.read(key: 'server_url'), isNull);
      expect(await storage.read(key: 'server_refresh_token'), isNull);
      expect(await storage.read(key: 'server_email'), isNull);
    });

    test('connect persists email for connect-dialog prefill', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      expect(await storage.read(key: 'server_email'), 'a@b.com');
    });

    test('readStoredSession returns null without stored url', () async {
      expect(await service.readStoredSession(), isNull);
    });

    test('readStoredSession reflects stored session', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');

      final stored = await service.readStoredSession();
      expect(stored, isNotNull);
      expect(stored!.url, 'https://srv:3000');
      expect(stored.email, 'a@b.com');
      expect(stored.hasRefreshToken, isTrue);
    });

    test('reportAuthFailure increments the notifier', () async {
      expect(service.authFailures.value, 0);
      service.reportAuthFailure();
      service.reportAuthFailure();
      expect(service.authFailures.value, 2);
    });

    test('reportAuthFailure in embedded mode does not surface the remote prompt',
        () async {
      service.connectEmbedded(
        port: 1,
        accessToken: 'a',
        refreshToken: 'r',
        installUuid: 'u',
        version: '0.1.0',
      );
      service.reportAuthFailure();
      expect(service.authFailures.value, 0);
    });

    test('reportAuthFailure in embedded mode fires a best-effort refresh',
        () async {
      var refreshCalls = 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('refresh')) {
          refreshCalls++;
          return http.Response(jsonEncode({
            'access_token': _jwtWithExpiry(now + 3600),
            'refresh_token': 'rotated-rt',
          }), 200, headers: _jsonHeader);
        }
        return http.Response('NF', 404);
      });
      service.connectEmbedded(
        port: 1,
        accessToken: 'stale',
        refreshToken: 'r',
        installUuid: 'u',
        version: '0.1.0',
      );

      service.reportAuthFailure();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(refreshCalls, 1);
      expect(service.authFailures.value, 0);
    });

    // ── restoreSession() ──

    test('restoreSession succeeds with valid token', () async {
      await storage.write(key: 'server_url', value: 'https://srv:3000');
      await storage.write(key: 'server_refresh_token', value: 'old-rt');

      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('refresh')) {
          return http.Response(jsonEncode({
            'access_token': 'new-at', 'refresh_token': 'new-rt',
          }), 200, headers: _jsonHeader);
        }
        if (req.url.path.endsWith('me')) {
          return http.Response(jsonEncode({
            'id': 'u1', 'email': 'a@b.com', 'display_name': 'Test',
          }), 200, headers: _jsonHeader);
        }
        return http.Response('NF', 404);
      });

      expect(await service.restoreSession(), isTrue);
      expect(service.connectionState, ServerConnectionState.connected);
      expect(service.userProfile?.email, 'a@b.com');
      expect(await storage.read(key: 'server_refresh_token'), 'new-rt');
      // 恢复成功 = 明确的 remote 意图，必须记住偏好（否则下次启动又被
      // embedded 默认抢占——从未重新登录、一直走恢复的用户会永远循环）。
      expect(await service.readPreferredMode(), 'remote');
    });

    test('restoreSession returns false without stored tokens', () async {
      expect(await service.restoreSession(), isFalse);
      expect(service.connectionState, ServerConnectionState.disconnected);
    });

    test('restoreSession returns false on 401', () async {
      await storage.write(key: 'server_url', value: 'https://srv:3000');
      await storage.write(key: 'server_refresh_token', value: 'expired');

      service.testHttpClient = _TestClient((_) async =>
        _errResponse(401, {'error': {'code': 'EXP', 'message': 'expired'}}));

      expect(await service.restoreSession(), isFalse);
      expect(service.connectionState, ServerConnectionState.disconnected);
    });

    test('restoreSession keeps stored credentials on transient 5xx', () async {
      await storage.write(key: 'server_url', value: 'https://srv:3000');
      await storage.write(key: 'server_refresh_token', value: 'rt');

      service.testHttpClient = _TestClient((_) async =>
        _errResponse(503, {'error': 'restarting'}));

      expect(await service.restoreSession(), isFalse);
      expect(service.connectionState, ServerConnectionState.disconnected);
      // A transient server error must NOT wipe the stored session — the next
      // app start / reconnect attempt should still be able to restore it.
      expect(await storage.read(key: 'server_url'), 'https://srv:3000');
      expect(await storage.read(key: 'server_refresh_token'), 'rt');
    });

    test('restoreSession falls back to disconnected on network error', () async {
      await storage.write(key: 'server_url', value: 'https://srv:3000');
      await storage.write(key: 'server_refresh_token', value: 'rt');

      service.testHttpClient = _TestClient((_) async => throw Exception('refused'));

      expect(await service.restoreSession(), isFalse);
      // Previously this left the state stuck at `connecting` (unclickable pill).
      expect(service.connectionState, ServerConnectionState.disconnected);
      expect(await storage.read(key: 'server_url'), 'https://srv:3000');
    });

    // ── getAccessToken() ──

    test('getAccessToken returns null when disconnected', () async {
      expect(await service.getAccessToken(), isNull);
    });

    test('getAccessToken returns token when connected', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      expect(await service.getAccessToken(), 'tok-access');
    });

    test('getAccessToken proactively refreshes an expiring JWT', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiring = _jwtWithExpiry(now - 10);
      final fresh = _jwtWithExpiry(now + 3600);

      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('refresh')) {
          return http.Response(jsonEncode({
            'access_token': fresh, 'refresh_token': 'rotated-rt',
          }), 200, headers: _jsonHeader);
        }
        return _okResponse({
          'access_token': expiring, 'refresh_token': 'tok-refresh',
          'user': {'id': 'u1', 'email': 'a@b.com', 'display_name': 'Test'},
        });
      });
      await service.connect('https://srv:3000', 'a@b.com', 'pw');

      expect(await service.getAccessToken(), fresh);
      expect(await storage.read(key: 'server_refresh_token'), 'rotated-rt');
    });

    test('getAccessToken refreshes an expiring embedded JWT (transparent '
        're-auth)', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiring = _jwtWithExpiry(now - 10);
      final fresh = _jwtWithExpiry(now + 3600);
      var refreshCalls = 0;

      // Seed a stored REMOTE session — the embedded refresh must not clobber
      // its refresh token (that would poison a later remote restore).
      await storage.write(key: 'server_url', value: 'https://srv:3000');
      await storage.write(key: 'server_refresh_token', value: 'remote-rt');

      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('refresh')) {
          refreshCalls++;
          return http.Response(jsonEncode({
            'access_token': fresh, 'refresh_token': 'embedded-rt-2',
          }), 200, headers: _jsonHeader);
        }
        return http.Response('NF', 404);
      });
      service.connectEmbedded(
        port: 1,
        accessToken: expiring,
        refreshToken: 'embedded-rt',
        installUuid: 'u',
        version: '0.1.0',
      );

      expect(await service.getAccessToken(), fresh);
      expect(refreshCalls, 1);
      // Embedded tokens stay memory-only; the remote session is intact.
      expect(await storage.read(key: 'server_refresh_token'), 'remote-rt');
    });

    test('embedded refresh rejection routes to a child restart, not '
        'disconnect', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiring = _jwtWithExpiry(now - 10);
      var refreshCalls = 0;
      var restarts = 0;

      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('refresh')) {
          refreshCalls++;
          return _errResponse(
              401, {'error': {'code': 'EXP', 'message': 'expired'}});
        }
        return http.Response('NF', 404);
      });
      service.connectEmbedded(
        port: 1,
        accessToken: expiring,
        refreshToken: 'embedded-rt',
        installUuid: 'u',
        version: '0.1.0',
      );
      service.embeddedRestartHandler = () async {
        restarts++;
        return true;
      };

      await service.getAccessToken();
      expect(refreshCalls, 1);
      expect(service.connectionState, ServerConnectionState.reconnecting);

      // _scheduleEmbeddedRestart arms a 1s timer before invoking the handler.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(restarts, 1);
      // The stored state was not torn down by disconnect() — the restart path
      // owns recovery via connectEmbedded.
      expect(service.isEmbeddedMode, isTrue);
    });

    test('concurrent getAccessToken calls share one refresh (single-flight)',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiring = _jwtWithExpiry(now - 10);
      final fresh = _jwtWithExpiry(now + 3600);
      var refreshCalls = 0;

      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('refresh')) {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(jsonEncode({
            'access_token': fresh, 'refresh_token': 'rotated-rt',
          }), 200, headers: _jsonHeader);
        }
        return _okResponse({
          'access_token': expiring, 'refresh_token': 'tok-refresh',
          'user': {'id': 'u1', 'email': 'a@b.com', 'display_name': 'Test'},
        });
      });
      await service.connect('https://srv:3000', 'a@b.com', 'pw');

      final tokens = await Future.wait([
        service.getAccessToken(),
        service.getAccessToken(),
        service.getAccessToken(),
      ]);
      expect(refreshCalls, 1);
      expect(tokens.every((t) => t == fresh), isTrue);
    });

    // ── State ValueListenable ──

    test('state notifier tracks connection lifecycle', () async {
      expect(service.state.value, ServerConnectionState.disconnected);

      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      expect(service.state.value, ServerConnectionState.connected);

      await service.disconnect();
      expect(service.state.value, ServerConnectionState.disconnected);
    });

    // ── Enum values ──

    test('connection states are distinct', () {
      final values = ServerConnectionState.values.toSet();
      expect(values.length, 4);
      expect(values, contains(ServerConnectionState.disconnected));
      expect(values, contains(ServerConnectionState.connecting));
      expect(values, contains(ServerConnectionState.connected));
      expect(values, contains(ServerConnectionState.reconnecting));
    });

    // ── U12: mode persistence + disconnect semantics ──

    test('connect() persists the remote preferred mode', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      expect(await service.readPreferredMode(), 'remote');
    });

    test('connect() clears a stale embedded flag (remote path by definition)',
        () async {
      service.setEmbeddedModeForTesting(true);
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      expect(service.isEmbeddedMode, isFalse);
      expect(await service.readPreferredMode(), 'remote');
    });

    test('remote disconnect clears creds AND preferred mode', () async {
      service.testHttpClient = _TestClient((_) async => _okResponse(_loginBody()));
      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      await service.disconnect();
      expect(await storage.read(key: 'server_url'), isNull);
      expect(await storage.read(key: 'server_refresh_token'), isNull);
      expect(await storage.read(key: 'server_email'), isNull);
      expect(await service.readPreferredMode(), isNull);
    });

    test('embedded disconnect leaves a stored remote session intact',
        () async {
      // Seed a stored remote session as if a remote sign-in happened earlier —
      // leaving local mode must not wipe it.
      await storage.write(key: 'server_url', value: 'https://srv:3000');
      await storage.write(key: 'server_refresh_token', value: 'rt');
      await storage.write(key: 'server_email', value: 'a@b.com');
      await storage.write(key: 'server_preferred_mode', value: 'remote');
      service.connectEmbedded(
        port: 1,
        accessToken: 'a',
        refreshToken: 'r',
        installUuid: 'u',
        version: 'v',
      );
      await service.disconnect();
      expect(service.connectionState, ServerConnectionState.disconnected);
      expect(service.isEmbeddedMode, isFalse);
      expect(await storage.read(key: 'server_url'), 'https://srv:3000');
      expect(await storage.read(key: 'server_refresh_token'), 'rt');
      expect(await storage.read(key: 'server_email'), 'a@b.com');
      expect(await service.readPreferredMode(), 'remote');
    });

    test('readPreferredMode tolerates storage failure as "no preference"',
        () async {
      service.testSecureStorage = _ThrowingReadStorage();
      expect(await service.readPreferredMode(), isNull);
    });

    // ── U15: server version 捕获与最低兼容告警 ──

    test('connectEmbedded 存储握手 version（当前版本 → 不告警）', () async {
      service.connectEmbedded(
        port: 1,
        accessToken: 'a',
        refreshToken: 'r',
        installUuid: 'u',
        version: '0.1.0',
      );
      expect(service.serverVersion, '0.1.0');
      expect(service.serverVersionOutdated, isFalse);
    });

    test('embedded version 低于最低兼容 → serverVersionOutdated', () async {
      service.connectEmbedded(
        port: 1,
        accessToken: 'a',
        refreshToken: 'r',
        installUuid: 'u',
        version: '0.0.9',
      );
      expect(service.serverVersionOutdated, isTrue);
    });

    test('远程连接后 /api/instance 补全 server 版本', () async {
      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('login')) {
          return _okResponse(_loginBody());
        }
        if (req.url.path.endsWith('/api/instance')) {
          return http.Response(jsonEncode({
            'ok': true,
            'data': {'install_uuid': 'u1', 'version': '0.1.0', 'embedded_mode': false},
            'error': null,
          }), 200, headers: _jsonHeader);
        }
        return http.Response('NF', 404);
      });

      await service.connect('https://srv:3000', 'a@b.com', 'pw');
      // connect 对 fetchInstanceVersion 是 fire-and-forget；等待微任务队列排空。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.serverVersion, '0.1.0');
      expect(service.serverVersionOutdated, isFalse);
    });

    test('fetchInstanceVersion 失败（非 200/异常）不抛且版本保持未知', () async {
      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('login')) {
          return _okResponse(_loginBody());
        }
        return http.Response('err', 500);
      });
      await service.connect('https://srv:3000', 'a@b.com', 'pw');

      await service.fetchInstanceVersion(); // 500 → 静默跳过
      expect(service.serverVersion, isNull);

      service.testHttpClient = _TestClient((req) async {
        if (req.url.path.endsWith('/api/instance')) {
          throw Exception('refused');
        }
        return _okResponse(_loginBody());
      });
      await service.fetchInstanceVersion(); // 网络异常 → 静默跳过
      expect(service.serverVersion, isNull);
      expect(service.connectionState, ServerConnectionState.connected);
    });

    test('disconnect 清空 server 版本状态', () async {
      service.connectEmbedded(
        port: 1,
        accessToken: 'a',
        refreshToken: 'r',
        installUuid: 'u',
        version: '0.0.9',
      );
      expect(service.serverVersionOutdated, isTrue);
      await service.disconnect();
      expect(service.serverVersion, isNull);
      expect(service.serverVersionOutdated, isFalse);
    });
  });
}

/// Storage fake whose read() always throws — exercises the failure-as-default
/// contract of readPreferredMode.
class _ThrowingReadStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async => throw Exception('storage unavailable');
}
