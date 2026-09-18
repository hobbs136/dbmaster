import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/database_models.dart';
import '../utils/app_logger.dart';

/// 当安全存储（keychain）不可用时抛出
class SecureStorageException implements Exception {
  final String message;
  SecureStorageException(this.message);
  @override
  String toString() => 'SecureStorageException: $message';
}

/// 凭据保险箱服务。
///
/// 为了避免 macOS/iOS 上 `flutter_secure_storage.readAll` 在 legacy keychain 下返回
/// -50 (paramErr)，并减少逐条钥匙串授权弹窗，所有数据库密码与 SSH 凭据统一存储在
/// 单个 keychain 项 `dbmaster_credentials_vault` 中，以 JSON 形式保存。
///
/// 旧版按连接单独存储的 key（`dbmaster_password_*`、`dbmaster_ssh_*`）会在首次读取时
/// 被迁移到保险箱；迁移完成后即可通过一次 keychain 读取获取全部凭据。
class SecureStorageService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accountName: 'dbmaster_secure_storage',
      accessibility: KeychainAccessibility.first_unlock_this_device,
      // 使用 legacy macOS keychain，避免 Data Protection Keychain 在开发/本地构建时
      // 要求 provisioning profile 和 keychain-access-groups 签名。
      // Release (App Store) 构建仍会在 entitlements 中声明 keychain-access-groups。
      useDataProtectionKeyChain: false,
    ),
  );

  static const _vaultKey = 'dbmaster_credentials_vault';
  static const _vaultVersion = 1;

  // 旧版 key 前缀，仅用于迁移
  static const _legacyPasswordPrefix = 'dbmaster_password_';
  static const _legacyFallbackPrefix = 'fallback_password_';
  static const _legacySshPasswordPrefix = 'dbmaster_ssh_password_';
  static const _legacySshPrivateKeyPrefix = 'dbmaster_ssh_private_key_';
  static const _legacySshPassphrasePrefix = 'dbmaster_ssh_passphrase_';

  // ==================== 保险箱读写 ====================

  static Future<Map<String, dynamic>> _readVault() async {
    try {
      final raw = await _secureStorage.read(key: _vaultKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded;
    } catch (e) {
      AppLogger.w(
        'SecureStorageService',
        'Failed to read credentials vault: $e',
      );
      return {};
    }
  }

  static Future<void> _writeVault(Map<String, dynamic> vault) async {
    try {
      await _secureStorage.write(key: _vaultKey, value: jsonEncode(vault));
    } catch (e) {
      AppLogger.e(
        'SecureStorageService',
        'Failed to write credentials vault: $e',
      );
      throw SecureStorageException(
        'Unable to save credentials vault securely. Please check keychain access.',
      );
    }
  }

  static Map<String, String> _castPasswords(dynamic value) {
    if (value is! Map) return {};
    return value.cast<String, String>();
  }

  static Map<String, Map<String, String?>> _castSsh(dynamic value) {
    if (value is! Map) return {};
    final result = <String, Map<String, String?>>{};
    for (final entry in value.entries) {
      final id = entry.key as String;
      final map = entry.value;
      if (map is Map) {
        result[id] = map.map((k, v) => MapEntry(k as String, v as String?));
      }
    }
    return result;
  }

  /// 读取保险箱，并尝试把 [connectionIds] 对应的旧版单独存储项迁移进来。
  ///
  /// 返回结构：
  /// ```json
  /// {
  ///   "version": 1,
  ///   "passwords": {"connId": "password", ...},
  ///   "ssh": {
  ///     "connId": {"password": "...", "privateKey": "...", "passphrase": "..."},
  ///     ...
  ///   }
  /// }
  /// ```
  static Future<Map<String, dynamic>> readCredentialsVault(
    List<String> connectionIds,
  ) async {
    var vault = await _readVault();
    var passwords = _castPasswords(vault['passwords']);
    var ssh = _castSsh(vault['ssh']);

    var migrated = false;
    for (final id in connectionIds) {
      if (!passwords.containsKey(id)) {
        final legacy = await _legacyReadPassword(id);
        if (legacy != null && legacy.isNotEmpty) {
          passwords[id] = legacy;
          migrated = true;
        }
      }
      if (!ssh.containsKey(id)) {
        final legacySsh = await _legacyReadSshCredentials(id);
        if (legacySsh['password'] != null ||
            legacySsh['privateKey'] != null ||
            legacySsh['passphrase'] != null) {
          ssh[id] = legacySsh;
          migrated = true;
        }
      }
    }

    if (migrated) {
      vault = {'version': _vaultVersion, 'passwords': passwords, 'ssh': ssh};
      await _writeVault(vault);
    }

    return {'version': _vaultVersion, 'passwords': passwords, 'ssh': ssh};
  }

  // ==================== 密码操作 ====================

  static Future<void> savePassword(String connectionId, String password) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    final ssh = _castSsh(vault['ssh']);
    passwords[connectionId] = password;
    await _writeVault({
      'version': _vaultVersion,
      'passwords': passwords,
      'ssh': ssh,
    });
    await _legacyDeletePassword(connectionId);
    await _legacyDeleteFallbackPassword(connectionId);
  }

  static Future<void> deletePassword(String connectionId) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    final ssh = _castSsh(vault['ssh']);
    passwords.remove(connectionId);
    await _writeVault({
      'version': _vaultVersion,
      'passwords': passwords,
      'ssh': ssh,
    });
    await _legacyDeletePassword(connectionId);
    await _legacyDeleteFallbackPassword(connectionId);
  }

  // ==================== SSH 凭据操作 ====================

  static Future<void> saveSshCredentials(
    String connectionId, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    var ssh = _castSsh(vault['ssh']);
    ssh[connectionId] = {
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
    };
    await _writeVault({
      'version': _vaultVersion,
      'passwords': passwords,
      'ssh': ssh,
    });
    await _legacyDeleteSshCredentials(connectionId);
  }

  static Future<void> deleteSshCredentials(String connectionId) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    final ssh = _castSsh(vault['ssh']);
    ssh.remove(connectionId);
    await _writeVault({
      'version': _vaultVersion,
      'passwords': passwords,
      'ssh': ssh,
    });
    await _legacyDeleteSshCredentials(connectionId);
  }

  // ==================== 连接级操作 ====================

  static Future<void> saveConnection(DbServer server) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    var ssh = _castSsh(vault['ssh']);

    if (server.password != null && server.password!.isNotEmpty) {
      passwords[server.id] = server.password!;
    } else {
      passwords.remove(server.id);
    }

    if (server.useSshTunnel) {
      ssh[server.id] = {
        'password': server.sshPassword,
        'privateKey': server.sshPrivateKey,
        'passphrase': server.sshPassphrase,
      };
    } else {
      ssh.remove(server.id);
    }

    await _writeVault({
      'version': _vaultVersion,
      'passwords': passwords,
      'ssh': ssh,
    });
    await _legacyDeleteConnection(server.id);
  }

  static Future<void> deleteConnection(String connectionId) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    final ssh = _castSsh(vault['ssh']);
    passwords.remove(connectionId);
    ssh.remove(connectionId);
    await _writeVault({
      'version': _vaultVersion,
      'passwords': passwords,
      'ssh': ssh,
    });
    await _legacyDeleteConnection(connectionId);
  }

  // ==================== 旧版迁移与清理 ====================

  static Future<String?> _legacyReadPassword(String connectionId) async {
    try {
      return await _secureStorage.read(
        key: '$_legacyPasswordPrefix$connectionId',
      );
    } catch (e) {
      AppLogger.w(
        'SecureStorageService',
        'Failed to read legacy password for $connectionId: $e',
      );
      return null;
    }
  }

  static Future<Map<String, String?>> _legacyReadSshCredentials(
    String connectionId,
  ) async {
    try {
      final password = await _secureStorage.read(
        key: '$_legacySshPasswordPrefix$connectionId',
      );
      final privateKey = await _secureStorage.read(
        key: '$_legacySshPrivateKeyPrefix$connectionId',
      );
      final passphrase = await _secureStorage.read(
        key: '$_legacySshPassphrasePrefix$connectionId',
      );
      return {
        'password': password,
        'privateKey': privateKey,
        'passphrase': passphrase,
      };
    } catch (e) {
      AppLogger.w(
        'SecureStorageService',
        'Failed to read legacy SSH credentials for $connectionId: $e',
      );
      return {};
    }
  }

  static Future<void> _legacyDeletePassword(String connectionId) async {
    try {
      await _secureStorage.delete(key: '$_legacyPasswordPrefix$connectionId');
    } catch (e) {
      AppLogger.w(
        'SecureStorageService',
        'Failed to delete legacy password for $connectionId: $e',
      );
    }
  }

  static Future<void> _legacyDeleteSshCredentials(String connectionId) async {
    try {
      await _secureStorage.delete(
        key: '$_legacySshPasswordPrefix$connectionId',
      );
      await _secureStorage.delete(
        key: '$_legacySshPrivateKeyPrefix$connectionId',
      );
      await _secureStorage.delete(
        key: '$_legacySshPassphrasePrefix$connectionId',
      );
    } catch (e) {
      AppLogger.w(
        'SecureStorageService',
        'Failed to delete legacy SSH credentials for $connectionId: $e',
      );
    }
  }

  static Future<void> _legacyDeleteConnection(String connectionId) async {
    await _legacyDeletePassword(connectionId);
    await _legacyDeleteSshCredentials(connectionId);
    await _legacyDeleteFallbackPassword(connectionId);
  }

  static Future<void> _legacyDeleteFallbackPassword(String connectionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_legacyFallbackPrefix$connectionId');
    } catch (e) {
      AppLogger.w(
        'SecureStorageService',
        'Failed to delete fallback password for $connectionId: $e',
      );
    }
  }

  /// 一次性清理旧版 fallback 密码（从 SharedPreferences 中移除）。
  /// 仅用于迁移：keychain 可用时把旧密码移到 secure storage；不可用则保留在 fallback 并提示用户。
  static Future<void> migrateFallbackPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    final fallbackKeys = prefs
        .getKeys()
        .where((k) => k.startsWith(_legacyFallbackPrefix))
        .toList();

    for (final key in fallbackKeys) {
      final connectionId = key.substring(_legacyFallbackPrefix.length);
      final password = prefs.getString(key);
      if (password != null && password.isNotEmpty) {
        try {
          await savePassword(connectionId, password);
          await prefs.remove(key);
          AppLogger.i(
            'SecureStorageService',
            'Migrated fallback password for $connectionId',
          );
        } catch (e) {
          AppLogger.w(
            'SecureStorageService',
            'Failed to migrate fallback for $connectionId: $e',
          );
        }
      }
    }
  }

  /// 清空所有凭据（保险箱 + 旧版单独项）。
  static Future<void> clearAll() async {
    try {
      await _secureStorage.delete(key: _vaultKey);
    } catch (e) {
      AppLogger.w('SecureStorageService', 'Vault delete failed: $e');
    }

    // 尝试清理旧版单独项（readAll 在某些平台可能失败，因此 best-effort）
    try {
      final all = await _secureStorage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_legacyPasswordPrefix) ||
            key.startsWith(_legacySshPasswordPrefix) ||
            key.startsWith(_legacySshPrivateKeyPrefix) ||
            key.startsWith(_legacySshPassphrasePrefix)) {
          await _secureStorage.delete(key: key);
        }
      }
    } catch (e) {
      AppLogger.w('SecureStorageService', 'Legacy clear failed: $e');
    }

    // 清理旧 fallback 密码
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (k) => k.startsWith(_legacyFallbackPrefix),
    );
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  // ==================== 兼容性 helper（仍按连接返回） ====================

  static Future<bool> hasPassword(String connectionId) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    return passwords.containsKey(connectionId) &&
        passwords[connectionId]!.isNotEmpty;
  }

  static Future<DbServer> attachPassword(DbServer server) async {
    final vault = await _readVault();
    final passwords = _castPasswords(vault['passwords']);
    return server.copyWith(password: passwords[server.id]);
  }

  static Future<DbServer> attachSshCredentials(DbServer server) async {
    if (!server.useSshTunnel) return server;
    final vault = await _readVault();
    final ssh = _castSsh(vault['ssh']);
    final creds = ssh[server.id];
    if (creds == null) return server;
    return server.copyWith(
      sshPassword: creds['password'],
      sshPrivateKey: creds['privateKey'],
      sshPassphrase: creds['passphrase'],
    );
  }
}
