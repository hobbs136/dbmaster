import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/redis_script.dart';

/// Redis Lua 脚本本地管理服务
///
/// 所有脚本存储在客户端本地（SharedPreferences），按全局/连接级隔离。
/// 不依赖 Redis 服务器版本，支持 4.x ~ 7.x+。
class RedisScriptService {
  static const String _storageKey = 'redis_scripts_v1';
  static const int _maxScripts = 100;

  SharedPreferences? _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  /// 获取符合条件的脚本列表
  ///
  /// [connectionId] 当前连接 ID。返回全局脚本 + 该连接绑定的脚本。
  Future<List<RedisScript>> getScripts({String? connectionId}) async {
    await init();
    final all = await _loadAll();
    return all.where((s) {
      if (s.isGlobal) return true;
      if (connectionId != null && s.connectionId == connectionId) return true;
      return false;
    }).toList()..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
  }

  Future<RedisScript?> getScript(String id) async {
    final all = await _loadAll();
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveScript(RedisScript script) async {
    await init();
    final all = await _loadAll();
    final index = all.indexWhere((s) => s.id == script.id);
    if (index >= 0) {
      all[index] = script;
    } else {
      if (all.length >= _maxScripts) {
        throw StateError(
          'Maximum number of Redis scripts ($_maxScripts) reached',
        );
      }
      all.add(script);
    }
    await _saveAll(all);
  }

  Future<void> deleteScript(String id) async {
    await init();
    final all = await _loadAll();
    all.removeWhere((s) => s.id == id);
    await _saveAll(all);
  }

  Future<void> duplicateScript(String id, {String? newName}) async {
    final script = await getScript(id);
    if (script == null) throw ArgumentError('Script not found: $id');

    final copy = script.copyWith(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      name: newName ?? '${script.name} (Copy)',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
    await saveScript(copy);
  }

  Future<List<RedisScript>> searchScripts(
    String query, {
    String? connectionId,
  }) async {
    final lower = query.toLowerCase();
    final scripts = await getScripts(connectionId: connectionId);
    return scripts.where((s) {
      return s.name.toLowerCase().contains(lower) ||
          s.code.toLowerCase().contains(lower) ||
          s.tags.any((t) => t.toLowerCase().contains(lower));
    }).toList();
  }

  Future<List<RedisScript>> getScriptsByTag(
    String tag, {
    String? connectionId,
  }) async {
    final scripts = await getScripts(connectionId: connectionId);
    return scripts.where((s) => s.tags.contains(tag)).toList();
  }

  Future<List<String>> getAllTags({String? connectionId}) async {
    final scripts = await getScripts(connectionId: connectionId);
    final tags = <String>{};
    for (final s in scripts) {
      tags.addAll(s.tags);
    }
    return tags.toList()..sort();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<List<RedisScript>> _loadAll() async {
    final jsonString = _prefs?.getString(_storageKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((j) => RedisScript.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<RedisScript> scripts) async {
    final jsonList = scripts.map((s) => s.toJson()).toList();
    await _prefs?.setString(_storageKey, jsonEncode(jsonList));
  }
}
