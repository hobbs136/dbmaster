import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/ai_session_orchestrator.dart';

/// DeepSeek 端到端验证
/// 配置 AppProvider + AiConfig + Mock Adapter，通过 Orchestrator 调用 DeepSeek API
/// 运行方式：
///   DEEPSEEK_API_KEY=sk-xxx flutter test integration_test/ai_deepseek_end_to_end_test.dart
class _MockAdapter implements DatabaseAdapter {
  @override
  bool get isConnected => true;

  @override
  DatabaseType get databaseType => DatabaseType.mysql;

  @override
  DatabaseConnection? get currentConnection => null;

  @override
  void Function()? get onDisconnect => null;

  @override
  set onDisconnect(void Function()? callback) {}

  @override
  Future<List<String>> getTables() async => const [];

  @override
  Future<String> getAiSchemaSummary({
    String? target,
    String? databaseName,
    String locale = 'en',
  }) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final apiKey = Platform.environment['DEEPSEEK_API_KEY'] ?? '';

  group('DeepSeek end-to-end via AppProvider + Orchestrator', () {
    test('full flow: configure DeepSeek, send message, receive AI response',
        () async {
      if (apiKey.isEmpty) {
        markTestSkipped('DEEPSEEK_API_KEY not set');
        return;
      }

      final provider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

      // 1. 配置 DeepSeek provider / model / apiKey
      await provider.saveAiConfig(
        'DeepSeek',
        'deepseek-chat',
        {
          'DeepSeek': {
            'apiKey': apiKey,
            'baseUrl': 'https://api.deepseek.com/v1',
          },
        },
      );

      expect(provider.selectedAiProvider, 'DeepSeek');
      expect(provider.selectedAiModel, 'deepseek-chat');
      expect(provider.getAiApiKey('DeepSeek'), apiKey);

      // 2. 确保会话存在
      provider.aiPanel.ensureSession();
      expect(provider.aiPanel.aiConversationService.currentSession, isNotNull);

      // 3. 使用 mock adapter 调用完整 Orchestrator 链路
      final adapter = _MockAdapter();
      final completer = Completer<void>();
      String? assistantContent;

      final subscription = provider.aiPanel.orchestrator.stateStream.listen((delta) {
        if (delta.type == MessageDeltaType.add && delta.message != null && !delta.message!.isUser) {
          assistantContent = delta.message!.content;
          if (!completer.isCompleted) completer.complete();
        }
      });

      await provider.aiPanel.orchestrator.sendUserMessage(
        text: 'Say exactly "pong"',
        adapter: adapter,
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        apiKey: apiKey,
        baseUrl: 'https://api.deepseek.com/v1',
        timeout: const Duration(seconds: 60),
        selectedDatabase: 'test_db',
        locale: 'en',
      );

      await completer.future.timeout(const Duration(seconds: 90));
      await subscription.cancel();

      expect(assistantContent, isNotNull);
      expect(assistantContent!.trim().isNotEmpty, isTrue);
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
