import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/ai/ai_client.dart';

/// 可编程响应 + 捕获请求体的 mock client（Claude tools 测试用）。
class _ProgrammableMockClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  String? lastRequestBody;
  int statusCode = 200;
  String responseBody =
      '{"content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":1,"output_tokens":1}}';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) {
      lastRequestBody = request.body;
    }
    return http.StreamedResponse(
      Stream.fromIterable([utf8.encode(responseBody)]),
      statusCode,
    );
  }
}

Map<String, dynamic> _tool(String name) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': '$name 描述',
        'parameters': {
          'type': 'object',
          'properties': {
            'table': {'type': 'string'},
          },
        },
      },
    };

void main() {
  group('AiClient Claude tool calling（_chatClaude）', () {
    test('请求体：tools 转为 Anthropic input_schema + tool_choice auto', () async {
      final mock = _ProgrammableMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'k',
        message: '看看有哪些表',
        tools: [_tool('list_tables')],
      );

      final body = jsonDecode(mock.lastRequestBody!) as Map<String, dynamic>;
      final tools = body['tools'] as List;
      expect(tools, hasLength(1));
      expect(tools[0]['name'], equals('list_tables'));
      expect(tools[0]['input_schema'], isA<Map<String, dynamic>>());
      expect(tools[0].containsKey('type'), isFalse);
      expect(tools[0].containsKey('function'), isFalse);
      expect(body['tool_choice'], equals({'type': 'auto'}));
    });

    test('请求体：OpenAI 格式 history 转为 Anthropic blocks 形态', () async {
      final mock = _ProgrammableMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'k',
        message: '继续',
        history: [
          {'role': 'user', 'content': '看看有哪些表'},
          {
            'role': 'assistant',
            'content': '我查一下',
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'list_tables', 'arguments': '{}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'users,orders'},
        ],
        tools: [_tool('list_tables')],
      );

      final body = jsonDecode(mock.lastRequestBody!) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages, hasLength(4));
      // user 纯文本
      expect(messages[0], equals({'role': 'user', 'content': '看看有哪些表'}));
      // assistant → content blocks
      expect(messages[1]['role'], equals('assistant'));
      final assistantBlocks = messages[1]['content'] as List;
      expect(assistantBlocks[0]['type'], equals('text'));
      expect(assistantBlocks[1]['type'], equals('tool_use'));
      expect(assistantBlocks[1]['id'], equals('call_1'));
      // role:'tool' → user + tool_result block
      expect(messages[2]['role'], equals('user'));
      final toolResults = messages[2]['content'] as List;
      expect(toolResults[0]['type'], equals('tool_result'));
      expect(toolResults[0]['tool_use_id'], equals('call_1'));
      expect(toolResults[0]['content'], equals('users,orders'));
      // 当前轮用户输入追加在最后
      expect(messages[3], equals({'role': 'user', 'content': '继续'}));
    });

    test('systemPrompt 放顶层 system 字段', () async {
      final mock = _ProgrammableMockClient();
      final client = AiClient(httpClient: mock);

      await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'k',
        message: 'hi',
        systemPrompt: '你是 DBA 助手',
      );

      final body = jsonDecode(mock.lastRequestBody!) as Map<String, dynamic>;
      expect(body['system'], equals('你是 DBA 助手'));
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
    });

    test('响应含 tool_use → ChatResponse.toolCalls（arguments 为 JSON 字符串）', () async {
      final mock = _ProgrammableMockClient()
        ..responseBody = jsonEncode({
          'content': [
            {'type': 'text', 'text': '我先看看表'},
            {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'list_tables',
              'input': {'database': 'test'},
            },
          ],
          'stop_reason': 'tool_use',
          'usage': {'input_tokens': 10, 'output_tokens': 5},
        });
      final client = AiClient(httpClient: mock);

      final response = await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'k',
        message: '看看有哪些表',
        tools: [_tool('list_tables')],
      );

      expect(response.content, equals('我先看看表'));
      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls[0].id, equals('toolu_1'));
      expect(response.toolCalls[0].functionName, equals('list_tables'));
      expect(
        jsonDecode(response.toolCalls[0].functionArguments),
        equals({'database': 'test'}),
      );
      expect(response.usage?.promptTokens, equals(10));
      expect(response.usage?.completionTokens, equals(5));
    });

    test('首个 block 是 tool_use 时不崩溃（修 [0][text] 直取的老 bug）', () async {
      final mock = _ProgrammableMockClient()
        ..responseBody = jsonEncode({
          'content': [
            {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'list_tables',
              'input': <String, dynamic>{},
            },
          ],
        });
      final client = AiClient(httpClient: mock);

      final response = await client.chat(
        provider: 'Claude',
        model: 'claude-3-haiku',
        apiKey: 'k',
        message: 'hi',
      );

      expect(response.content, isNull);
      expect(response.toolCalls, hasLength(1));
    });

    test('非 200 → 抛 API错误 异常', () async {
      final mock = _ProgrammableMockClient()
        ..statusCode = 400
        ..responseBody = '{"error":{"message":"invalid request"}}';
      final client = AiClient(httpClient: mock);

      expect(
        () => client.chat(
          provider: 'Claude',
          model: 'claude-3-haiku',
          apiKey: 'k',
          message: 'hi',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('invalid request'),
          ),
        ),
      );
    });
  });
}
