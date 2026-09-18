import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/ai_client.dart';

void main() {
  group('IAiClient static methods', () {
    group('supportsToolCalling', () {
      test('DeepSeek 应支持工具调用', () {
        expect(IAiClient.supportsToolCalling('DeepSeek'), isTrue);
      });

      test('OpenAI 应支持工具调用', () {
        expect(IAiClient.supportsToolCalling('OpenAI'), isTrue);
      });

      test('Kimi 应支持工具调用（注册表名，修复 Kimi/Kimi-Coding-Plan 名字错位）', () {
        // 回归用例——注册名 'Kimi' 必须能拿到 tool calling
        expect(IAiClient.supportsToolCalling('Kimi'), isTrue);
      });

      test('Claude 应支持工具调用（决策 B：_chatClaude 已接 tools）', () {
        // 决策 B 回归用例
        expect(IAiClient.supportsToolCalling('Claude'), isTrue);
      });

      test('Gemini 应支持工具调用（决策 B：走 OpenAI 兼容端点）', () {
        // 决策 B 回归用例
        expect(IAiClient.supportsToolCalling('Gemini'), isTrue);
      });

      test('Google Gemini（display name）应支持工具调用', () {
        // UI 层实际流转的是 display name（ai_panel_widget.dart）
        expect(IAiClient.supportsToolCalling('Google Gemini'), isTrue);
      });

      test('Kimi-Coding-Plan 应支持工具调用', () {
        expect(IAiClient.supportsToolCalling('Kimi-Coding-Plan'), isTrue);
      });

      test('MiniMax 应支持工具调用', () {
        expect(IAiClient.supportsToolCalling('MiniMax'), isTrue);
      });

      test('GLM-Coding-Plan 应支持工具调用', () {
        expect(IAiClient.supportsToolCalling('GLM-Coding-Plan'), isTrue);
      });

      test('未知 provider 不应支持工具调用', () {
        expect(IAiClient.supportsToolCalling('Unknown'), isFalse);
      });

      test('空字符串不应支持工具调用', () {
        expect(IAiClient.supportsToolCalling(''), isFalse);
      });
    });

    group('supportsThinking', () {
      test('Kimi-Coding-Plan + kimi-k2 应支持 thinking', () {
        expect(
          IAiClient.supportsThinking('Kimi-Coding-Plan', 'kimi-k2'),
          isTrue,
        );
      });

      test('Kimi-Coding-Plan + 其他模型不应支持 thinking', () {
        expect(
          IAiClient.supportsThinking('Kimi-Coding-Plan', 'other'),
          isFalse,
        );
      });

      test('其他 provider 不应支持 thinking', () {
        expect(
          IAiClient.supportsThinking('DeepSeek', 'deepseek-chat'),
          isFalse,
        );
      });
    });
  });
}
