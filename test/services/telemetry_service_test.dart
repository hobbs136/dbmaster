// Unit tests for TelemetryService.
// =============================================================================
// Covers install_uuid persistence, payload assembly, PII masking, queue LRU,
// flush success / transient / permanent failures, feature counters, and
// the lite kill switch.
//
// No real network or platform channels are exercised — `http.Client` is
// intercepted via `http.BaseClient` and `FlutterSecureStorage` via a fake.
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/services/telemetry_service.dart';

// ── Test doubles ──

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
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
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async =>
      _store[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
    WebOptions? webOptions,
  }) async {
    _store.clear();
  }
}

/// Recording HTTP client that lets each test script the response. Captures
/// every request for assertions.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final Future<http.Response> Function(http.Request) _handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;
    requests.add(req);
    final resp = await _handler(req);
    return http.StreamedResponse(
      Stream.value(resp.bodyBytes),
      resp.statusCode,
      contentLength: resp.bodyBytes.length,
      request: request,
      headers: resp.headers,
      reasonPhrase: resp.reasonPhrase,
    );
  }
}

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _ok() =>
    http.Response('{"ok":true}', 200, headers: _jsonHeaders);
http.Response _err(int code) =>
    http.Response('{"ok":false}', code, headers: _jsonHeaders);

TelemetryService _newService({
  required _FakeSecureStorage storage,
  required SharedPreferences prefs,
  required _RecordingClient client,
  String? installUuid = '11111111-1111-4111-8111-111111111111',
}) {
  // Reset shared instance then re-inject test doubles.
  TelemetryService.instance.dispose();
  final svc = TelemetryService.instance;
  svc.testSecureStorage = storage;
  svc.testPrefs = prefs;
  svc.testHttpClient = client;
  svc.testInstallUuid = installUuid;
  svc.testDefaultEndpoint = 'https://bucket.test/api/telemetry/event';
  return svc;
}

Future<void> _init(TelemetryService svc) async {
  await svc.init();
  // init() triggers a background flush that may consume events; wait one
  // microtask so callers see a stable queue snapshot before asserting.
  await Future.microtask(() {});
}

void main() {
  late _FakeSecureStorage storage;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = _FakeSecureStorage();
    TelemetryService.instance.dispose();
  });

  tearDown(() async {
    TelemetryService.instance.dispose();
    TelemetryService.instance.testSecureStorage = null;
    TelemetryService.instance.testPrefs = null;
    TelemetryService.instance.testHttpClient = null;
    TelemetryService.instance.testInstallUuid = null;
    TelemetryService.instance.testDefaultEndpoint = null;
    await TelemetryService.instance.resetForTesting();
  });

  group('install_uuid', () {
    test('init generates and persists a v4 uuid on first run', () async {
      final svc = _newService(
        storage: storage,
        prefs: prefs,
        client: _RecordingClient((_) async => _ok()),
        installUuid: null, // force generation path
      );
      svc.testSkipPersistence = false;
      await _init(svc);

      final stored = await storage.read(key: 'telemetry_install_uuid_v1');
      expect(stored, isNotNull);
      expect(
        RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
            .hasMatch(stored!),
        isTrue,
        reason: 'stored install_uuid must be a valid v4 UUID',
      );
    });

    test('init reuses existing v4 uuid', () async {
      const existing = '22222222-2222-4222-8222-222222222222';
      await storage.write(key: 'telemetry_install_uuid_v1', value: existing);

      final svc = _newService(
        storage: storage,
        prefs: prefs,
        client: _RecordingClient((_) async => _ok()),
        installUuid: null,
      );
      await _init(svc);

      expect(svc.installUuid, existing);
    });

    test('init ignores corrupt stored uuid and generates fresh', () async {
      await storage.write(key: 'telemetry_install_uuid_v1', value: 'not-a-uuid');
      final svc = _newService(
        storage: storage,
        prefs: prefs,
        client: _RecordingClient((_) async => _ok()),
        installUuid: null,
      );
      await _init(svc);

      expect(
        RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(svc.installUuid ?? ''),
        isTrue,
      );
    });
  });

  group('payload assembly', () {
    test('feature_used auto-injects install_uuid / app_version / os / ts', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(
        storage: storage,
        prefs: prefs,
        client: client,
      );
      svc.testAppVersion = '9.9.9';
      svc.testOs = 'linux';
      await _init(svc);

      svc.logFeatureUsed('schema_diff_compare');
      // Wait for the unawaited flush to consume the event.
      await Future.delayed(Duration.zero);

      expect(client.requests, hasLength(1));
      final body = jsonDecode(client.requests.last.body) as Map<String, dynamic>;
      expect(body['event_type'], 'feature_used');
      final payload = body['event_payload'] as Map<String, dynamic>;
      expect(payload['install_uuid'], '11111111-1111-4111-8111-111111111111');
      expect(payload['app_version'], '9.9.9');
      expect(payload['os'], 'linux');
      expect(payload['ts'], isA<String>());
      expect(payload['idempotency_key'], isA<String>());
      expect(payload['feature_id'], 'schema_diff_compare');
    });

    test('reserved keys supplied by caller are dropped (with warn)', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(
        storage: storage,
        prefs: prefs,
        client: client,
      );
      await _init(svc);

      svc.logFeatureUsed('feature', extra: {
        'install_uuid': 'attacker-attempt',
        'feature_id': 'feature',
        'custom': 'kept',
      });
      await Future.delayed(Duration.zero);

      final body = jsonDecode(client.requests.last.body) as Map<String, dynamic>;
      final payload = body['event_payload'] as Map<String, dynamic>;
      expect(payload['install_uuid'], '11111111-1111-4111-8111-111111111111',
          reason: 'caller cannot override reserved install_uuid');
      expect(payload['custom'], 'kept');
    });

    test('PII inside string values is masked before enqueue', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(
        storage: storage,
        prefs: prefs,
        client: client,
      );
      await _init(svc);

      svc.logFeatureUsed('feature', extra: {
        'leaked_email': 'user@example.com',
      });
      await Future.delayed(Duration.zero);

      final body = jsonDecode(client.requests.last.body) as Map<String, dynamic>;
      final payload = body['event_payload'] as Map<String, dynamic>;
      final value = payload['leaked_email'] as String;
      expect(value, isNot(contains('user@example.com')));
      expect(value, contains('@example.com'),
          reason: 'email masker preserves domain per pii_masker');
    });
  });

  group('flush semantics', () {
    test('2xx response removes event from queue', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logFeatureUsed('f1');
      await Future.delayed(Duration.zero);

      expect(svc.debugQueueSnapshot, isEmpty);
    });

    test('4xx (non-429) drops event as poison-pill', () async {
      final client = _RecordingClient((_) async => _err(400));
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logFeatureUsed('bad');
      // Allow several microtasks for flush + retries to settle.
      await Future.delayed(const Duration(milliseconds: 5));

      expect(svc.debugQueueSnapshot, isEmpty,
          reason: 'poison-pill 4xx must be removed, not retried');
    });

    test('5xx keeps event for later retry', () async {
      final client = _RecordingClient((_) async => _err(500));
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logFeatureUsed('retry_me');
      await Future.delayed(const Duration(milliseconds: 5));

      expect(svc.debugQueueSnapshot, hasLength(1));
      expect(
        (svc.debugQueueSnapshot.single['payload'] as Map)['feature_id'],
        'retry_me',
      );
    });

    test('network error keeps event for later retry', () async {
      final client =
          _RecordingClient((_) async => throw Exception('network down'));
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logFeatureUsed('will_queue');
      await Future.delayed(const Duration(milliseconds: 5));

      expect(svc.debugQueueSnapshot, hasLength(1));
    });
  });

  group('queue LRU', () {
    test('overflow drops oldest events', () async {
      final client =
          _RecordingClient((_) async => throw Exception('always fail'));
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      // Disable flush success so the queue actually fills.
      for (var i = 0; i < TelemetryService.maxQueueSize + 5; i++) {
        svc.logFeatureUsed('f_$i');
      }
      await Future.delayed(Duration.zero);

      expect(svc.debugQueueSnapshot.length, TelemetryService.maxQueueSize);
      // The earliest 5 ("f_0".."f_4") must have been dropped.
      final featureIds = svc.debugQueueSnapshot
          .map((e) => (e['payload'] as Map)['feature_id'] as String)
          .toSet();
      for (var i = 0; i < 5; i++) {
        expect(featureIds, isNot(contains('f_$i')),
            reason: 'oldest events must be evicted');
      }
    });
  });

  group('feature counter (lite gate input)', () {
    test('logFeatureUsed increments the counter', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logFeatureUsed('schema_diff_compare');
      svc.logFeatureUsed('schema_diff_compare');
      expect(svc.featureCount('schema_diff_compare'), 2);
    });

    test('isFeatureEligibleForLite respects default ≥3 threshold', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logFeatureUsed('f');
      expect(svc.isFeatureEligibleForLite('f'), isFalse);
      svc.logFeatureUsed('f');
      expect(svc.isFeatureEligibleForLite('f'), isFalse);
      svc.logFeatureUsed('f');
      expect(svc.isFeatureEligibleForLite('f'), isTrue);
    });

    test('resetInstallUuid clears the counter', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logFeatureUsed('f');
      svc.logFeatureUsed('f');
      await svc.resetInstallUuid();
      expect(svc.featureCount('f'), 0);
    });
  });

  group('kill switch', () {
    test('default ON', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);
      expect(svc.liteTouchpointEnabled, isTrue);
    });

    test('setLiteTouchpointEnabled persists to prefs', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      await svc.setLiteTouchpointEnabled(false);
      expect(svc.liteTouchpointEnabled, isFalse);
      expect(prefs.getBool('telemetry_lite_enabled_v1'), isFalse);
    });

    test('init loads persisted flag', () async {
      await prefs.setBool('telemetry_lite_enabled_v1', false);
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);
      expect(svc.liteTouchpointEnabled, isFalse);
    });
  });

  group('endpoint resolution', () {
    test('uses default bucket when not connected', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);
      svc.logFeatureUsed('f');
      await Future.delayed(Duration.zero);

      expect(
        client.requests.last.url.toString(),
        'https://bucket.test/api/telemetry/event',
      );
    });
  });

  group('dropped events when not initialized', () {
    test('events are dropped before init() with a warning', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      // Deliberately skip init.
      svc.logFeatureUsed('dropped');
      await Future.delayed(Duration.zero);

      expect(client.requests, isEmpty);
      expect(svc.debugQueueSnapshot, isEmpty);
    });
  });

  group('host_hash for server_connected', () {
    test('emits hash, not raw URL', () async {
      final client = _RecordingClient((_) async => _ok());
      final svc = _newService(storage: storage, prefs: prefs, client: client);
      await _init(svc);

      svc.logServerConnected('https://corp.internal:3000/path');
      await Future.delayed(Duration.zero);

      final body = jsonDecode(client.requests.last.body) as Map<String, dynamic>;
      final payload = body['event_payload'] as Map<String, dynamic>;
      final hash = payload['server_url_host_hash'] as String;
      expect(hash, hasLength(32));
      expect(hash, matches(RegExp(r'^[0-9a-f]{32}$')));
      // The original URL must never appear in the payload.
      expect(jsonEncode(payload), isNot(contains('corp.internal')));
    });
  });
}
