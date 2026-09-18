import 'dart:convert';
import '../utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/ai_models.dart';

class AiConfigProvider extends ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String _selectedAiProvider = 'DeepSeek';
  String _selectedAiModel = 'deepseek-chat';
  Map<String, Map<String, String>> _aiApiConfigs = {};
  bool _autoExecuteSql = false;
  bool _autocompleteEnabled = true;
  Duration _aiTimeout = const Duration(seconds: 60);

  /// 持久化的模型列表：{providerName: [model1, model2, ...]}
  Map<String, List<String>> _fetchedModelLists = {};

  // ==================== Getters ====================

  String get selectedAiProvider => _selectedAiProvider;
  String get selectedAiModel => _selectedAiModel;
  Map<String, Map<String, String>> get aiApiConfigs => _aiApiConfigs;
  bool get autoExecuteSql => _autoExecuteSql;
  bool get autocompleteEnabled => _autocompleteEnabled;
  Duration get aiTimeout => _aiTimeout;
  Map<String, List<String>> get fetchedModelLists =>
      Map.unmodifiable(_fetchedModelLists);

  /// 获取指定厂商的 API Key
  String? getApiKey(String provider) => _aiApiConfigs[provider]?['apiKey'];

  /// 获取指定厂商的 Base URL（优先返回用户配置的，否则返回默认值）
  String? getBaseUrl(String provider) {
    final userUrl = _aiApiConfigs[provider]?['baseUrl'];
    if (userUrl != null && userUrl.isNotEmpty) {
      return userUrl;
    }
    return AiApiProviders.getByName(provider)?.defaultBaseUrl;
  }

  /// 获取指定厂商的配置信息
  AiApiProvider? getProviderConfig(String provider) =>
      AiApiProviders.getByName(provider);

  List<AiApiProvider> get availableProviders =>
      AiApiProviders.all.values.toList();

  // ==================== 配置加载/保存 ====================

  /// 从本地存储加载 AI 配置
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedAiProvider = prefs.getString('ai_provider') ?? 'DeepSeek';
    // 迁移旧的中文存储值到新的逻辑键
    if (_selectedAiProvider == '自定义模型') {
      _selectedAiProvider = AiApiProviders.customModelKey;
    }
    _selectedAiModel = prefs.getString('ai_model') ?? 'deepseek-chat';
    _autoExecuteSql = prefs.getBool('ai_auto_execute') ?? false;
    _autocompleteEnabled = prefs.getBool('autocomplete_enabled') ?? true;
    final timeoutSeconds = prefs.getInt('ai_timeout_seconds') ?? 60;
    _aiTimeout = Duration(seconds: timeoutSeconds);

    final configsJson = prefs.getString('ai_api_configs');
    if (configsJson != null && configsJson.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(configsJson);
        _aiApiConfigs = decoded.map(
          (key, value) => MapEntry(key, Map<String, String>.from(value as Map)),
        );

        // 迁移旧的中文 provider 键到新的逻辑键
        if (_aiApiConfigs.containsKey('自定义模型')) {
          _aiApiConfigs[AiApiProviders.customModelKey] = _aiApiConfigs.remove(
            '自定义模型',
          )!;
        }

        bool migrated = false;
        for (final entry in _aiApiConfigs.entries) {
          final apiKey = entry.value['apiKey'];
          if (apiKey != null && apiKey.isNotEmpty) {
            try {
              await _secureStorage.write(
                key: 'ai_api_key_${entry.key}',
                value: apiKey,
              );
              entry.value.remove('apiKey');
              migrated = true;
            } catch (e) {
              // Secure storage 不可用（如测试环境），保留 apiKey 在内存中
              AppLogger.d(
                'AiConfig',
                'Secure storage write failed for ${entry.key}: $e',
              );
            }
          }
        }
        // 迁移 Gemini 旧默认 baseUrl（发现 C：设置对话框预填+保存
        // 机制曾把旧默认当用户配置持久化）——旧默认 .../v1beta 指向不存在
        // 的端点，改写为官方 OpenAI 兼容端点；真正手填过自定义代理的值
        // 不受影响。key 兼容注册键 'Gemini' 与 display name 'Google Gemini'
        const legacyGeminiBaseUrls = {
          'https://generativelanguage.googleapis.com/v1beta',
          'https://generativelanguage.googleapis.com/v1beta/',
        };
        for (final key in ['Gemini', 'Google Gemini']) {
          final config = _aiApiConfigs[key];
          final stored = config?['baseUrl'];
          if (config != null &&
              stored != null &&
              legacyGeminiBaseUrls.contains(stored.trim())) {
            config['baseUrl'] =
                'https://generativelanguage.googleapis.com/v1beta/openai';
            migrated = true;
          }
        }

        if (migrated) {
          await prefs.setString('ai_api_configs', jsonEncode(_aiApiConfigs));
        }
      } catch (e) {
        _aiApiConfigs = {};
      }
    }

    for (final entry in _aiApiConfigs.entries) {
      try {
        final secureKey = await _secureStorage.read(
          key: 'ai_api_key_${entry.key}',
        );
        if (secureKey != null) {
          entry.value['apiKey'] = secureKey;
        }
      } catch (e) {
        // Secure storage 不可用（如测试环境），保留内存中的 apiKey
        AppLogger.d(
          'AiConfig',
          'Secure storage read failed for ${entry.key}: $e',
        );
      }
    }

    // 加载持久化的模型列表
    final modelListsJson = prefs.getString('ai_fetched_model_lists');
    if (modelListsJson != null && modelListsJson.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(modelListsJson);
        _fetchedModelLists = decoded.map(
          (key, value) => MapEntry(key, List<String>.from(value as List)),
        );
      } catch (e) {
        _fetchedModelLists = {};
      }
    }

    notifyListeners();
  }

  /// 保存 AI 配置到本地
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', _selectedAiProvider);
    await prefs.setString('ai_model', _selectedAiModel);
    await prefs.setBool('ai_auto_execute', _autoExecuteSql);
    await prefs.setBool('autocomplete_enabled', _autocompleteEnabled);
    await prefs.setInt('ai_timeout_seconds', _aiTimeout.inSeconds);

    final configsWithoutKeys = <String, Map<String, String>>{};
    for (final entry in _aiApiConfigs.entries) {
      final config = Map<String, String>.from(entry.value);
      final apiKey = config.remove('apiKey');
      if (apiKey != null && apiKey.isNotEmpty) {
        try {
          await _secureStorage.write(
            key: 'ai_api_key_${entry.key}',
            value: apiKey,
          );
        } catch (e) {
          AppLogger.d(
            'AiConfig',
            'Failed to write secure storage for ${entry.key}: $e',
          );
        }
      } else {
        try {
          await _secureStorage.delete(key: 'ai_api_key_${entry.key}');
        } catch (e) {
          AppLogger.d(
            'AiConfig',
            'Failed to delete secure storage for ${entry.key}: $e',
          );
        }
      }
      configsWithoutKeys[entry.key] = config;
    }

    await prefs.setString('ai_api_configs', jsonEncode(configsWithoutKeys));

    // 保存模型列表
    if (_fetchedModelLists.isNotEmpty) {
      await prefs.setString(
        'ai_fetched_model_lists',
        jsonEncode(_fetchedModelLists),
      );
    }
  }

  /// 完整保存（保存所有配置并持久化）
  Future<void> save({
    required String provider,
    required String model,
    required Map<String, Map<String, String>> configs,
  }) async {
    _selectedAiProvider = provider;
    _selectedAiModel = model;
    _aiApiConfigs = configs;
    await _persist();
    notifyListeners();
  }

  // ==================== Setter ====================

  void setProvider(String provider) {
    _selectedAiProvider = provider;
    _persist();
    notifyListeners();
  }

  void setModel(String model) {
    _selectedAiModel = model;
    _persist();
    notifyListeners();
  }

  void setAutoExecuteSql(bool value) {
    _autoExecuteSql = value;
    _persist();
    notifyListeners();
  }

  void setAutocompleteEnabled(bool value) {
    _autocompleteEnabled = value;
    _persist();
    notifyListeners();
  }

  void setAiTimeout(Duration timeout) {
    _aiTimeout = timeout;
    _persist();
    notifyListeners();
  }

  /// 保存获取到的模型列表（持久化）
  void saveFetchedModelLists(Map<String, List<String>> modelLists) {
    _fetchedModelLists = Map.from(modelLists);
    _persist();
    notifyListeners();
  }

  /// 获取指定 provider 的持久化模型列表
  List<String>? getFetchedModelsForProvider(String provider) {
    return _fetchedModelLists[provider];
  }
}
