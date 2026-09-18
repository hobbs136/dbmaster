import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/anthropic_converter.dart';

void main() {
  group('AnthropicConverter.convertTools', () {
    test('OpenAI function 包装 → Anthropic input_schema', () {
      final result = AnthropicConverter.convertTools([
        {
          'type': 'function',
          'function': {
            'name': 'list_tables',
            'description': '列出所有表',
            'parameters': {
              'type': 'object',
              'properties': {
                'database': {'type': 'string'},
              },
            },
          },
        },
      ]);

      expect(result, hasLength(1));
      expect(result[0]['name'], equals('list_tables'));
      expect(result[0]['description'], equals('列出所有表'));
      expect(result[0]['input_schema'], isA<Map<String, dynamic>>());
      expect(
        (result[0]['input_schema'] as Map)['properties'],
        isNotNull,
      );
      expect(result[0].containsKey('type'), isFalse);
      expect(result[0].containsKey('function'), isFalse);
    });

    test('缺 parameters → 兜底空 object schema', () {
      final result = AnthropicConverter.convertTools([
        {
          'type': 'function',
          'function': {'name': 'ping', 'description': 'ping'},
        },
      ]);

      expect(result[0]['input_schema'], equals({
        'type': 'object',
        'properties': <String, dynamic>{},
      }));
    });
  });

  group('AnthropicConverter.convertHistory', () {
    test('纯文本 user/assistant 消息原样转换', () {
      final result = AnthropicConverter.convertHistory([
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '你好，有什么可以帮你？'},
      ]);

      expect(result, equals([
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '你好，有什么可以帮你？'},
      ]));
    });

    test('assistant tool_calls → content blocks（text + tool_use，arguments 回 Map）', () {
      final result = AnthropicConverter.convertHistory([
        {
          'role': 'assistant',
          'content': '我先看看有哪些表',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'list_tables',
                'arguments': '{"database":"test"}',
              },
            },
          ],
        },
      ]);

      expect(result, hasLength(1));
      final content = result[0]['content'] as List;
      expect(content[0], equals({'type': 'text', 'text': '我先看看有哪些表'}));
      expect(content[1]['type'], equals('tool_use'));
      expect(content[1]['id'], equals('call_1'));
      expect(content[1]['name'], equals('list_tables'));
      expect(content[1]['input'], equals({'database': 'test'}));
    });

    test('连续 role:tool 消息合并为一条 user 消息的多个 tool_result block', () {
      // 合并语义——agent 循环并行执行工具后逐个 add role:'tool'，
      // Anthropic 要求它们合并进同一条 user 消息
      final result = AnthropicConverter.convertHistory([
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'a', 'arguments': '{}'},
            },
            {
              'id': 'call_2',
              'type': 'function',
              'function': {'name': 'b', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': '结果1'},
        {'role': 'tool', 'tool_call_id': 'call_2', 'content': '结果2'},
      ]);

      expect(result, hasLength(2));
      expect(result[0]['role'], equals('assistant'));
      expect(result[1]['role'], equals('user'));
      final blocks = result[1]['content'] as List;
      expect(blocks, hasLength(2));
      expect(blocks[0], equals({
        'type': 'tool_result',
        'tool_use_id': 'call_1',
        'content': '结果1',
      }));
      expect(blocks[1]['tool_use_id'], equals('call_2'));
    });

    test('tool 结果后的普通消息正确分隔（flush 语义）', () {
      final result = AnthropicConverter.convertHistory([
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': '结果'},
        {'role': 'assistant', 'content': '完成'},
        {'role': 'user', 'content': '谢谢'},
      ]);

      expect(result, hasLength(3));
      expect(result[0]['role'], equals('user')); // tool_result 合并消息
      expect(result[1], equals({'role': 'assistant', 'content': '完成'}));
      expect(result[2], equals({'role': 'user', 'content': '谢谢'}));
    });

    test('role:system 跳过；reasoning_content 丢弃', () {
      final result = AnthropicConverter.convertHistory([
        {'role': 'system', 'content': '你是 DBA 助手'},
        {
          'role': 'assistant',
          'content': '思考结果',
          'reasoning_content': '大段思维链……',
        },
      ]);

      expect(result, hasLength(1));
      expect(result[0], equals({'role': 'assistant', 'content': '思考结果'}));
    });

    test('空 content 补空格（Anthropic 拒绝空 text）', () {
      final result = AnthropicConverter.convertHistory([
        {'role': 'assistant', 'content': ''},
      ]);

      expect(result[0]['content'], equals(' '));
    });

    test('tool_calls arguments 为非法 JSON → 兜底 {}', () {
      // DeepSeek 偶发产生非法 JSON arguments，防脏数据打断循环
      final result = AnthropicConverter.convertHistory([
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'a', 'arguments': '{bad json'},
            },
          ],
        },
      ]);

      final content = result[0]['content'] as List;
      expect(content[0]['input'], equals(<String, dynamic>{}));
    });
  });

  group('AnthropicConverter.parseResponse', () {
    test('纯 text 响应', () {
      final response = AnthropicConverter.parseResponse({
        'content': [
          {'type': 'text', 'text': '你好'},
        ],
      });

      expect(response.content, equals('你好'));
      expect(response.hasToolCalls, isFalse);
    });

    test('tool_use block → AiToolCall（input Map 编码为 JSON 字符串）', () {
      final response = AnthropicConverter.parseResponse({
        'content': [
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'list_tables',
            'input': {'database': 'test'},
          },
        ],
        'stop_reason': 'tool_use',
      });

      expect(response.content, isNull);
      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls[0].id, equals('toolu_1'));
      expect(response.toolCalls[0].functionName, equals('list_tables'));
      expect(
        jsonDecode(response.toolCalls[0].functionArguments),
        equals({'database': 'test'}),
      );
    });

    test('text + tool_use 混合 block', () {
      final response = AnthropicConverter.parseResponse({
        'content': [
          {'type': 'text', 'text': '我先查一下'},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'get_table_schema',
            'input': {'table': 'users'},
          },
        ],
      });

      expect(response.content, equals('我先查一下'));
      expect(response.toolCalls, hasLength(1));
    });

    test('多个 text block 拼接', () {
      final response = AnthropicConverter.parseResponse({
        'content': [
          {'type': 'text', 'text': '第一部分'},
          {'type': 'text', 'text': '第二部分'},
        ],
      });

      expect(response.content, equals('第一部分第二部分'));
    });

    test('空 content 数组 → content 为 null 且无 toolCalls', () {
      final response = AnthropicConverter.parseResponse({'content': []});

      expect(response.content, isNull);
      expect(response.hasToolCalls, isFalse);
    });
  });
}
