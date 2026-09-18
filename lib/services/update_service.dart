import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/version_compare.dart';

/// 更新检查结果状态。
enum UpdateCheckStatus { idle, checking, upToDate, available, unknown, failed }

/// 应用更新检查（U15）——查 GitHub Releases latest（`hobbs136/dbmaster`，
/// tag 为 CalVer `vYYYY-MM-DD`，与 tech-site 下载直链同源）。
///
/// 行为约定：
/// - **自动检查**：启动时经 [maybeAutoCheck]，24h 冷却 + 用户可关（默认开）；
/// - **手动检查**：设置页「检查更新」按钮走 [checkNow]，无视冷却；
/// - 当前版本来自构建期注入的 `APP_VERSION` dart-define（build 脚本取
///   `git describe --tags --abbrev=0`）。**开发构建（IDE 直跑 / 未注入）
///   版本未知**：仍能查到 latest 并展示，但不宣称「有新版本」（跨风格/
/// 未知版本不可排序，见 [compareVersions]）；
/// - 全程 best-effort：失败只置 failed 状态，绝不影响主流程。
class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final UpdateService _instance = UpdateService._();
  static UpdateService get instance => _instance;

  /// GitHub Releases latest API。构建期可覆盖（自建 mirror / 企业代理）。
  static const String _endpoint = String.fromEnvironment(
    'UPDATE_CHECK_URL',
    defaultValue:
        'https://api.github.com/repos/hobbs136/dbmaster/releases/latest',
  );

  /// tech-site 下载页（Snackbar「前往下载」的兜底链接；正常路径用 GitHub
  /// 响应里的 html_url）。
  static const String downloadPageUrl =
      'https://dbmaster.tech-site/server/download';

  static const String _lastCheckKey = 'update_last_check_v1';
  static const String _autoCheckKey = 'update_auto_check_enabled_v1';
  static const Duration _autoCheckCooldown = Duration(hours: 24);
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// 与 TelemetryService 同源的版本注入（构建脚本注入 git tag；未注入 =
  /// 开发构建，恒为该默认值）。
  static const String _defaultAppVersion = '0.0.1+1';

  // ── 测试注入口（对齐 TelemetryService 惯例）──
  @visibleForTesting
  http.Client? testHttpClient;
  @visibleForTesting
  SharedPreferences? testPrefs;
  @visibleForTesting
  String? testAppVersion;

  http.Client? _ownedClient;

  UpdateCheckStatus _status = UpdateCheckStatus.idle;
  String? _latestTag;
  Uri? _latestUrl;
  DateTime? _lastCheckedAt;
  bool _autoCheckEnabled = true;
  bool _prefsLoaded = false;
  bool _checking = false;

  // ── 只读状态（UI 消费）──

  UpdateCheckStatus get status => _status;

  /// Releases latest 的 tag（如 `v2026-08-17`），未查到为 null。
  String? get latestTag => _latestTag;

  /// Releases 页面链接（「前往下载」入口）。
  Uri get downloadUrl => _latestUrl ?? Uri.parse(downloadPageUrl);

  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// 当前应用版本（构建注入的 git tag；开发构建为 `0.0.1+1`）。
  String get appVersion =>
      testAppVersion ??
      const String.fromEnvironment('APP_VERSION',
          defaultValue: _defaultAppVersion);

  /// 当前版本是否可信（开发构建不可信 → 只展示不比对）。
  bool get appVersionKnown {
    final v = appVersion;
    final normalized = v.split('+').first;
    return v.isNotEmpty &&
        normalized != _defaultAppVersion.split('+').first &&
        v != 'dev';
  }

  bool get updateAvailable => _status == UpdateCheckStatus.available;

  bool get autoCheckEnabled => _autoCheckEnabled;

  // ── 持久化偏好 ──

  Future<void> setAutoCheckEnabled(bool value) async {
    _autoCheckEnabled = value;
    notifyListeners();
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      await prefs.setBool(_autoCheckKey, value);
    } catch (e) {
      AppLogger.w('UpdateService', 'persist autoCheck=$value failed: $e');
    }
  }

  /// 启动时的静默自动检查：冷却未过 / 用户已关闭时直接跳过。
  /// flutter_test 环境（flutter_tester 设 FLUTTER_TEST）下若未注入
  /// testHttpClient 同样跳过——任何 pump HomeScreen 的 widget 测试都会走到
  /// 这里，真网络请求会在 fake async 区域留下永不完成的 future / pending
  /// timer。注入了 mock client 的单测与手动 [checkNow] 不受限。
  Future<void> maybeAutoCheck() async {
    if (testHttpClient == null &&
        Platform.environment['FLUTTER_TEST'] == 'true') {
      return;
    }
    await _ensurePrefsLoaded();
    if (!_autoCheckEnabled) return;
    final last = _lastCheckedAt;
    if (last != null &&
        DateTime.now().difference(last) < _autoCheckCooldown) {
      return;
    }
    await checkNow();
  }

  /// 立即检查（手动入口 / 冷却已过的自动检查）。
  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    _status = UpdateCheckStatus.checking;
    notifyListeners();
    try {
      final client = testHttpClient ?? (_ownedClient ??= http.Client());
      final resp = await client
          .get(Uri.parse(_endpoint))
          .timeout(_requestTimeout);
      if (resp.statusCode != 200) {
        _status = UpdateCheckStatus.failed;
        AppLogger.w('UpdateService',
            'update check failed: HTTP ${resp.statusCode}');
      } else {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final tag = body['tag_name'] as String?;
        if (tag == null || tag.isEmpty) {
          _status = UpdateCheckStatus.failed;
        } else {
          _latestTag = tag;
          final htmlUrl = body['html_url'] as String?;
          if (htmlUrl != null && htmlUrl.isNotEmpty) {
            _latestUrl = Uri.parse(htmlUrl);
          }
          _status = _decideStatus(tag);
        }
        _lastCheckedAt = DateTime.now();
        _persistLastCheck();
      }
    } catch (e) {
      _status = UpdateCheckStatus.failed;
      _lastCheckedAt = DateTime.now();
      _persistLastCheck();
      AppLogger.i('UpdateService', 'update check skipped: $e');
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  UpdateCheckStatus _decideStatus(String latestTag) {
    if (!appVersionKnown) return UpdateCheckStatus.unknown;
    final cmp = compareVersions(appVersion, latestTag);
    if (cmp == null) return UpdateCheckStatus.unknown; // 跨风格不可排序
    return cmp >= 0 ? UpdateCheckStatus.upToDate : UpdateCheckStatus.available;
  }

  Future<void> _ensurePrefsLoaded() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      _autoCheckEnabled = prefs.getBool(_autoCheckKey) ?? true;
      final last = prefs.getString(_lastCheckKey);
      if (last != null) _lastCheckedAt = DateTime.tryParse(last);
    } catch (_) {
      // prefs 不可用 → 默认值照常工作
    }
  }

  Future<void> _persistLastCheck() async {
    final last = _lastCheckedAt;
    if (last == null) return;
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_lastCheckKey, last.toIso8601String());
    } catch (_) {}
  }

  /// 测试隔离。
  @visibleForTesting
  static void resetForTesting() {
    final s = _instance;
    s._status = UpdateCheckStatus.idle;
    s._latestTag = null;
    s._latestUrl = null;
    s._lastCheckedAt = null;
    s._autoCheckEnabled = true;
    s._prefsLoaded = false;
    s._checking = false;
    s.testHttpClient = null;
    s.testPrefs = null;
    s.testAppVersion = null;
    s._ownedClient?.close();
    s._ownedClient = null;
  }
}
