import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai_service.dart';

/// 临时集成测试：验证 DeepSeek API 连通性
/// 运行方式：
///   DEEPSEEK_API_KEY=sk-xxx flutter test integration_test/ai_deepseek_test.dart
void main() {
  final apiKey = Platform.environment['DEEPSEEK_API_KEY'] ?? '';

  group('DeepSeek API integration', () {
    test('skips when DEEPSEEK_API_KEY is not provided', () {
      if (apiKey.isEmpty) {
        markTestSkipped('DEEPSEEK_API_KEY not set');
      }
      expect(apiKey, isNotEmpty);
    }, skip: false);

    test('chat returns non-empty response', () async {
      if (apiKey.isEmpty) {
        markTestSkipped('DEEPSEEK_API_KEY not set');
        return;
      }

      final response = await AiService().chat(
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        apiKey: apiKey,
        message: 'Say exactly "pong"',
        systemPrompt: 'You are a helpful assistant. Keep answers short.',
        timeout: const Duration(seconds: 60),
      );

      expect(response.content, isNotNull);
      expect(response.content!.trim().isNotEmpty, isTrue);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('chatStream emits content', () async {
      if (apiKey.isEmpty) {
        markTestSkipped('DEEPSEEK_API_KEY not set');
        return;
      }

      final chunks = <String>[];
      await for (final chunk in AiService().chatStream(
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        apiKey: apiKey,
        message: 'Say exactly "pong"',
        systemPrompt: 'You are a helpful assistant. Keep answers short.',
        timeout: const Duration(seconds: 60),
      )) {
        if (chunk.isNotEmpty) chunks.add(chunk);
      }

      expect(chunks, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
