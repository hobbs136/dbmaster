import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/ai_config_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiConfigProvider', () {
    late AiConfigProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      provider = AiConfigProvider();
    });

    group('默认配置', () {
      test('默认厂商应为 DeepSeek', () {
        expect(provider.selectedAiProvider, equals('DeepSeek'));
      });

      test('默认模型应为 deepseek-chat', () {
        expect(provider.selectedAiModel, equals('deepseek-chat'));
      });

      test('默认不自动执行 SQL', () {
        expect(provider.autoExecuteSql, isFalse);
      });

      test('默认启用自动补全', () {
        expect(provider.autocompleteEnabled, isTrue);
      });

      test('默认超时 60 秒', () {
        expect(provider.aiTimeout, equals(const Duration(seconds: 60)));
      });

      test('API 配置默认为空', () {
        expect(provider.aiApiConfigs, isEmpty);
      });
    });

    group('setProvider / setModel', () {
      test('setProvider 更新厂商并持久化', () async {
        provider.setProvider('Claude');
        expect(provider.selectedAiProvider, equals('Claude'));
      });

      test('setModel 更新模型并持久化', () async {
        provider.setModel('claude-3-opus');
        expect(provider.selectedAiModel, equals('claude-3-opus'));
      });
    });

    group('setAutoExecuteSql / setAutocompleteEnabled', () {
      test('setAutoExecuteSql 正确设置', () async {
        provider.setAutoExecuteSql(true);
        expect(provider.autoExecuteSql, isTrue);
      });

      test('setAutocompleteEnabled 正确设置', () async {
        provider.setAutocompleteEnabled(false);
        expect(provider.autocompleteEnabled, isFalse);
      });
    });

    group('setAiTimeout', () {
      test('setAiTimeout 正确设置', () async {
        provider.setAiTimeout(const Duration(seconds: 120));
        expect(provider.aiTimeout, equals(const Duration(seconds: 120)));
      });
    });

    group('save() 完整保存', () {
      test('save() 正确保存所有配置', () async {
        final configs = {
          'DeepSeek': {'apiKey': 'test-key-123'},
          'Claude': {'apiKey': 'claude-key-456'},
        };
        await provider.save(
          provider: 'Claude',
          model: 'claude-3-sonnet',
          configs: configs,
        );
        expect(provider.selectedAiProvider, equals('Claude'));
        expect(provider.selectedAiModel, equals('claude-3-sonnet'));
        expect(provider.aiApiConfigs, equals(configs));
      });
    });

    group('getApiKey / getBaseUrl', () {
      test('getApiKey 返回正确 key', () async {
        final configs = {
          'DeepSeek': {'apiKey': 'ds-key'},
        };
        await provider.save(
          provider: 'DeepSeek',
          model: 'deepseek-chat',
          configs: configs,
        );
        expect(provider.getApiKey('DeepSeek'), equals('ds-key'));
      });

      test('getApiKey 不存在的厂商返回 null', () {
        expect(provider.getApiKey('NonExistent'), isNull);
      });

      test('getBaseUrl 返回正确 URL', () async {
        final configs = {
          'OpenAI': {'baseUrl': 'https://api.openai.com/v1'},
        };
        await provider.save(
          provider: 'OpenAI',
          model: 'gpt-4',
          configs: configs,
        );
        expect(
          provider.getBaseUrl('OpenAI'),
          equals('https://api.openai.com/v1'),
        );
      });

      test('getBaseUrl 不存在的厂商返回 null', () {
        expect(provider.getBaseUrl('NonExistent'), isNull);
      });
    });

    group('load() 从 SharedPreferences 恢复', () {
      test('load() 恢复保存的配置', () async {
        SharedPreferences.setMockInitialValues({
          'ai_provider': 'Claude',
          'ai_model': 'claude-3-sonnet',
          'ai_auto_execute': true,
          'autocomplete_enabled': false,
          'ai_timeout_seconds': 120,
          'ai_api_configs': '{"Claude": {"apiKey": "loaded-key"}}',
        });

        final p2 = AiConfigProvider();
        await p2.load();

        expect(p2.selectedAiProvider, equals('Claude'));
        expect(p2.selectedAiModel, equals('claude-3-sonnet'));
        expect(p2.autoExecuteSql, isTrue);
        expect(p2.autocompleteEnabled, isFalse);
        expect(p2.aiTimeout, equals(const Duration(seconds: 120)));
        expect(p2.getApiKey('Claude'), equals('loaded-key'));
      });

      test('load() 无数据时使用默认值', () async {
        SharedPreferences.setMockInitialValues({});
        final p2 = AiConfigProvider();
        await p2.load();

        expect(p2.selectedAiProvider, equals('DeepSeek'));
        expect(p2.selectedAiModel, equals('deepseek-chat'));
      });
    });

    group('Gemini baseUrl 迁移', () {
      // 决策 B（发现 C）——旧默认 baseUrl 曾被设置对话框当用户
      // 配置持久化，load() 必须迁移到 OpenAI 兼容端点
      test('旧默认 baseUrl（注册键 Gemini）迁移到 OpenAI 兼容端点', () async {
        SharedPreferences.setMockInitialValues({
          'ai_api_configs':
              '{"Gemini": {"baseUrl": "https://generativelanguage.googleapis.com/v1beta"}}',
        });
        final p2 = AiConfigProvider();
        await p2.load();

        expect(
          p2.getBaseUrl('Gemini'),
          equals(
            'https://generativelanguage.googleapis.com/v1beta/openai',
          ),
        );
      });

      test('旧默认 baseUrl 带尾斜杠（display name 键）同样迁移', () async {
        SharedPreferences.setMockInitialValues({
          'ai_api_configs':
              '{"Google Gemini": {"baseUrl": "https://generativelanguage.googleapis.com/v1beta/"}}',
        });
        final p2 = AiConfigProvider();
        await p2.load();

        expect(
          p2.getBaseUrl('Google Gemini'),
          equals(
            'https://generativelanguage.googleapis.com/v1beta/openai',
          ),
        );
      });

      test('用户自定义的 Gemini 代理地址不被迁移', () async {
        SharedPreferences.setMockInitialValues({
          'ai_api_configs':
              '{"Gemini": {"baseUrl": "https://my-gemini-proxy.example.com/v1"}}',
        });
        final p2 = AiConfigProvider();
        await p2.load();

        expect(
          p2.getBaseUrl('Gemini'),
          equals('https://my-gemini-proxy.example.com/v1'),
        );
      });
    });
  });
}
