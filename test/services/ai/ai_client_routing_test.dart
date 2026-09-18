import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/ai/ai_client.dart';

/// 捕获请求的 mock HTTP client，按 URL 返回对应协议的响应。
/// 照 tdengine_adapter_security_test.dart 的 _CapturingMockClient 模式。
class _CapturingMockClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    requestCount++;
    final isAnthropic = request.url.path.endsWith('/v1/messages');
    final body = isAnthropic
        ? '{"content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":1,"output_tokens":1}}'
        : '{"choices":[{"message":{"content":"hi"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}';
    return http.StreamedResponse(
      Stream.fromIterable([utf8.encode(body)]),
      200,
    );
  }
}

void main() {
  group('AiClient 路由（_resolveApiProvider）', () {
    test('注册 provider + 默认 baseUrl → 走注册表 apiVersion（Claude messages 分支）', () async {
      // 回归用例——上游 getBaseUrl 会回退注册表默认值，
      // 此前这种调用被强制打到 /chat/completions（发现 A）
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'test-key',
        baseUrl: 'https://api.anthropic.com',
        message: 'hello',
      );

      expect(mock.lastRequest?.url.path, equals('/v1/messages'));
      expect(mock.lastRequest?.headers['x-api-key'], equals('test-key'));
      expect(mock.lastRequest?.headers['anthropic-version'], isNotNull);
    });

    test('注册 provider + baseUrl 为 null → 走注册表 apiVersion', () async {
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'test-key',
        message: 'hello',
      );

      expect(mock.lastRequest?.url.host, equals('api.anthropic.com'));
      expect(mock.lastRequest?.url.path, equals('/v1/messages'));
    });

    test('默认 baseUrl 带尾部斜杠 → 仍识别为默认，走注册表 apiVersion', () async {
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'test-key',
        baseUrl: 'https://api.anthropic.com/',
        message: 'hello',
      );

      expect(mock.lastRequest?.url.path, equals('/v1/messages'));
    });

    test('真正自定义 baseUrl → 强制 chatCompletions（OpenAI 网关逃生门）', () async {
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'test-key',
        baseUrl: 'https://my-gateway.example.com/v1',
        message: 'hello',
      );

      expect(
        mock.lastRequest?.url.toString(),
        equals('https://my-gateway.example.com/v1/chat/completions'),
      );
      expect(mock.lastRequest?.headers['Authorization'], equals('Bearer test-key'));
    });

    test('未知 provider + 无 baseUrl → 抛「不支持的AI厂商」', () async {
      final client = AiClient(httpClient: _CapturingMockClient());

      expect(
        () => client.chat(
          provider: 'NotAProvider',
          model: 'm',
          apiKey: 'k',
          message: 'hello',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('注入的 httpClient 不被 cancel() 关闭，可连续复用', () async {
      // _newRequest() 内部会调 cancel()，若误关注入 client，
      // 第二次请求就会拿到已关闭的 client
      final mock = _CapturingMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        apiKey: 'k',
        message: 'one',
      );
      client.cancel();
      await client.chat(
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        apiKey: 'k',
        message: 'two',
      );

      expect(mock.requestCount, equals(2));
    });
  });
}
