import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// 封装认证 Token 的安全存储逻辑
///
/// 使用 flutter_secure_storage (keychain) 作为主力存储，
/// 保留从旧版 SharedPreferences 读取的能力以兼容已登录用户。
class AuthTokenStorage {
  static const _secure = FlutterSecureStorage();
  static const _tokenKey = 'dbmaster_auth_token';
  static const _refreshTokenKey = 'dbmaster_refresh_token';

  // 旧版 SharedPreferences key（用于迁移和向后兼容读取）
  static const _legacyTokenKey = 'auth_token';
  static const _legacyRefreshTokenKey = 'refresh_token';

  /// 保存 token 到 secure storage
  static Future<void> save(String token, String? refreshToken) async {
    await _secure.write(key: _tokenKey, value: token);
    if (refreshToken != null) {
      await _secure.write(key: _refreshTokenKey, value: refreshToken);
    }
    AppLogger.d('AuthTokenStorage', 'Tokens saved to secure storage');
  }

  /// 从 secure storage 读取 token；若失败则回退到旧版 SharedPreferences
  static Future<Map<String, String?>> load() async {
    try {
      final token = await _secure.read(key: _tokenKey);
      final refreshToken = await _secure.read(key: _refreshTokenKey);
      if (token != null) {
        return {'token': token, 'refreshToken': refreshToken};
      }
    } catch (e) {
      AppLogger.w('AuthTokenStorage', 'Secure storage read failed: $e');
    }

    // 向后兼容：尝试从旧版 SharedPreferences 读取
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_legacyTokenKey);
    final legacyRefresh = prefs.getString(_legacyRefreshTokenKey);
    return {'token': legacyToken, 'refreshToken': legacyRefresh};
  }

  /// 清除所有存储位置的 token
  static Future<void> clear() async {
    try {
      await _secure.delete(key: _tokenKey);
      await _secure.delete(key: _refreshTokenKey);
    } catch (e) {
      AppLogger.w('AuthTokenStorage', 'Secure storage clear failed: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyTokenKey);
    await prefs.remove(_legacyRefreshTokenKey);
  }

  /// 从旧版 SharedPreferences 迁移 token 到 secure storage
  static Future<void> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_legacyTokenKey);
    final legacyRefresh = prefs.getString(_legacyRefreshTokenKey);

    if (legacyToken != null) {
      try {
        await _secure.write(key: _tokenKey, value: legacyToken);
        await prefs.remove(_legacyTokenKey);
        AppLogger.i(
          'AuthTokenStorage',
          'Migrated auth token to secure storage',
        );
      } catch (e) {
        AppLogger.w('AuthTokenStorage', 'Failed to migrate auth token: $e');
      }
    }

    if (legacyRefresh != null) {
      try {
        await _secure.write(key: _refreshTokenKey, value: legacyRefresh);
        await prefs.remove(_legacyRefreshTokenKey);
        AppLogger.i(
          'AuthTokenStorage',
          'Migrated refresh token to secure storage',
        );
      } catch (e) {
        AppLogger.w('AuthTokenStorage', 'Failed to migrate refresh token: $e');
      }
    }
  }
}
