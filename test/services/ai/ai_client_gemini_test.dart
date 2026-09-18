import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/ai/ai_client.dart';

/// Gemini（OpenAI 兼容端点）请求路由测试。
class _CapturingMockClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  String? lastRequestBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) {
      lastRequestBody = request.body;
    }
    final isModels = request.url.path.endsWith('/models');
    final body = isModels
        ? '{"data":[{"id":"gemini-2.5-flash"}]}'
        : '{"choices":[{"message":{"content":"hi"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}';
    return http.StreamedResponse(
      Stream.fromIterable([utf8.encode(body)]),
      200,
    );
  }
}

void main() {
  group('AiClient Gemini（OpenAI 兼容端点）', () {
    const geminiBaseUrl =
        'https://generativelanguage.googleapis.com/v1beta/openai';

    test('chat 请求打到 /v1beta/openai/chat/completions + Bearer 鉴权', () async {
      // 决策 B——Gemini 走官方 OpenAI 兼容端点，复用
      // _chatOpenAICompat（含 tools 透传）
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Google Gemini',
        model: 'gemini-2.5-flash',
        apiKey: 'test-key',
        baseUrl: geminiBaseUrl,
        message: 'hello',
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'list_tables',
              'description': '列出表',
              'parameters': {'type': 'object', 'properties': {}},
            },
          },
        ],
      );

      expect(
        mock.lastRequest?.url.toString(),
        equals('$geminiBaseUrl/chat/completions'),
      );
      expect(
        mock.lastRequest?.headers['Authorization'],
        equals('Bearer test-key'),
      );
      // tools 按 OpenAI 格式透传（Gemini 兼容端点原生支持）
      final body = jsonDecode(mock.lastRequestBody!) as Map<String, dynamic>;
      expect(body['tools'], isA<List>());
      expect(body['tool_choice'], equals('auto'));
    });

    test('display name 经 getByName 兜底也能命中注册表（发现 B）', () async {
      // baseUrl 传 null——迫使走注册表路由；'Google Gemini' 必须能解析
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Google Gemini',
        model: 'gemini-2.5-flash',
        apiKey: 'test-key',
        message: 'hello',
      );

      expect(
        mock.lastRequest?.url.toString(),
        equals('$geminiBaseUrl/chat/completions'),
      );
    });

    test('fetchModels 对已含版本段的 baseUrl 不追加 /v1', () async {
      // 归一化回归——.../v1beta/openai 不应被拼成
      // .../v1beta/openai/v1/models
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      final models = await client.fetchModels(
        baseUrl: geminiBaseUrl,
        apiKey: 'test-key',
      );

      expect(
        mock.lastRequest?.url.toString(),
        equals('$geminiBaseUrl/models'),
      );
      expect(models, contains('gemini-2.5-flash'));
    });

    test('fetchModels 对无版本段的 baseUrl 仍追加 /v1（原行为不变）', () async {
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.fetchModels(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'test-key',
      );

      expect(
        mock.lastRequest?.url.toString(),
        equals('https://api.deepseek.com/v1/models'),
      );
    });
  });
}
