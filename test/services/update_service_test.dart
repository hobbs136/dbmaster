import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/services/update_service.dart';

/// Handler 型 mock client（对齐 server_connection_test 的 _TestClient）。
class _TestClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) _handler;
  _TestClient(this._handler);

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

http.Response _release(String tag, {int status = 200}) => http.Response(
      jsonEncode({
        'tag_name': tag,
        'name': 'DbMaster $tag',
        'html_url': 'https://github.com/hobbs136/dbmaster/releases/tag/$tag',
      }),
      status,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    UpdateService.resetForTesting();
    // 每个用例拿干净的 prefs（setMockInitialValues 重建底层存储）。
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    UpdateService.instance.testPrefs = prefs;
  });

  tearDown(() {
    UpdateService.resetForTesting();
  });

  group('UpdateService.checkNow（U15）', () {
    test('有新版本（CalVer）：status available + updateAvailable', () async {
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient = _TestClient((_) async => _release('v2026-08-17'));

      await svc.checkNow();

      expect(svc.status, UpdateCheckStatus.available);
      expect(svc.updateAvailable, isTrue);
      expect(svc.latestTag, 'v2026-08-17');
      expect(svc.downloadUrl.toString(),
          'https://github.com/hobbs136/dbmaster/releases/tag/v2026-08-17');
      expect(svc.lastCheckedAt, isNotNull);
    });

    test('已是最新（同 tag）：upToDate', () async {
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-08-17'
        ..testHttpClient = _TestClient((_) async => _release('v2026-08-17'));

      await svc.checkNow();

      expect(svc.status, UpdateCheckStatus.upToDate);
      expect(svc.updateAvailable, isFalse);
    });

    test('已是最新（SemVer）', () async {
      final svc = UpdateService.instance
        ..testAppVersion = 'v1.7.1'
        ..testHttpClient = _TestClient((_) async => _release('v1.7.1'));

      await svc.checkNow();

      expect(svc.status, UpdateCheckStatus.upToDate);
    });

    test('开发构建（默认版本号）不宣称有新版：unknown', () async {
      final svc = UpdateService.instance
        ..testHttpClient = _TestClient((_) async => _release('v2026-08-17'));

      expect(svc.appVersionKnown, isFalse);
      await svc.checkNow();

      expect(svc.status, UpdateCheckStatus.unknown);
      expect(svc.updateAvailable, isFalse);
      // latest 仍可展示
      expect(svc.latestTag, 'v2026-08-17');
    });

    test('HTTP 非 200 → failed', () async {
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient =
            _TestClient((_) async => _release('x', status: 500));

      await svc.checkNow();

      expect(svc.status, UpdateCheckStatus.failed);
      expect(svc.updateAvailable, isFalse);
    });

    test('网络异常 → failed（不抛出）', () async {
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient =
            _TestClient((_) async => throw Exception('no network'));

      await svc.checkNow();

      expect(svc.status, UpdateCheckStatus.failed);
    });

    test('响应缺 tag_name → failed', () async {
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient = _TestClient((_) async => http.Response(
              jsonEncode({'message': 'Not Found'}),
              200,
            ));

      await svc.checkNow();

      expect(svc.status, UpdateCheckStatus.failed);
    });

    test('并发 checkNow 单飞（只发一次请求）', () async {
      var calls = 0;
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient = _TestClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _release('v2026-08-17');
        });

      await Future.wait([svc.checkNow(), svc.checkNow()]);

      expect(calls, 1);
      expect(svc.status, UpdateCheckStatus.available);
    });
  });

  group('maybeAutoCheck（冷却与开关）', () {
    test('冷却期内跳过（不发请求）', () async {
      await prefs.setString('update_last_check_v1',
          DateTime.now().toIso8601String());
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient = _TestClient((_) async {
          fail('cooldown 内不应发请求');
        });

      await svc.maybeAutoCheck();

      expect(svc.status, UpdateCheckStatus.idle);
    });

    test('自动检查关闭时跳过', () async {
      await prefs.setBool('update_auto_check_enabled_v1', false);
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient = _TestClient((_) async {
          fail('开关关闭时不应发请求');
        });

      await svc.maybeAutoCheck();

      expect(svc.status, UpdateCheckStatus.idle);
      expect(svc.autoCheckEnabled, isFalse);
    });

    test('冷却已过 → 发起检查并落冷却时间', () async {
      await prefs.setString('update_last_check_v1',
          DateTime.now().subtract(const Duration(hours: 25)).toIso8601String());
      final svc = UpdateService.instance
        ..testAppVersion = 'v2026-07-27'
        ..testHttpClient = _TestClient((_) async => _release('v2026-08-17'));

      await svc.maybeAutoCheck();

      expect(svc.status, UpdateCheckStatus.available);
      expect(
        prefs.getString('update_last_check_v1'),
        isNotNull,
      );
    });
  });

  group('偏好持久化', () {
    test('setAutoCheckEnabled 持久化并通知', () async {
      final svc = UpdateService.instance;
      var notified = 0;
      svc.addListener(() => notified++);

      await svc.setAutoCheckEnabled(false);

      expect(svc.autoCheckEnabled, isFalse);
      expect(prefs.getBool('update_auto_check_enabled_v1'), isFalse);
      expect(notified, greaterThan(0));
    });
  });
}
