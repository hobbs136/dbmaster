import 'dart:convert';

import '../../models/ai_models.dart';

/// Anthropic（Claude Messages API）↔ OpenAI 格式双向转换层。
///
/// 背景：agent 循环（ai_agent_service.dart）的 history 永远保持 OpenAI
/// 格式（checkpoint 序列化不变、存量零迁移、跨 provider 恢复可用），
/// 在 AiClient 的 Claude 分支边界调用本转换器做协议适配。
///
/// Anthropic 协议要点：
/// - tools 用 {name, description, input_schema}（无 type:'function' 包装）
/// - tool_use 是 assistant 消息的 content block
/// - tool_result 必须放在 user role 消息的 content block 里，且紧跟在
///   含 tool_use 的 assistant 消息之后；连续多个工具结果合并进同一条
///   user 消息
/// - 拒绝空字符串 text block
class AnthropicConverter {
  AnthropicConverter._();

  /// OpenAI tools → Anthropic tools。
  /// {'type':'function','function':{name,description,parameters}}
  ///   → {name, description, input_schema}
  static List<Map<String, dynamic>> convertTools(
    List<Map<String, dynamic>> openAiTools,
  ) {
    return openAiTools.map((tool) {
      final function = tool['function'] as Map<String, dynamic>? ?? const {};
      final parameters =
          function['parameters'] as Map<String, dynamic>? ??
          const {'type': 'object', 'properties': <String, dynamic>{}};
      return <String, dynamic>{
        'name': function['name'] as String? ?? '',
        'description': function['description'] as String? ?? '',
        'input_schema': parameters,
      };
    }).toList();
  }

  /// OpenAI history → Anthropic messages。
  ///
  /// - assistant 带 tool_calls → content blocks（text? + tool_use*）
  /// - 连续 role:'tool' 消息 → 合并为一条 user 消息的多个 tool_result block
  /// - role:'system' 跳过（systemPrompt 走请求体顶层 system 字段）
  /// - 'reasoning_content' 字段一律丢弃（Anthropic 非流式不启用 thinking）
  /// - 空 content 补 ' '（Anthropic 拒绝空 text）
  static List<Map<String, dynamic>> convertHistory(
    List<Map<String, dynamic>> history,
  ) {
    final out = <Map<String, dynamic>>[];
    var pendingToolResults = <Map<String, dynamic>>[];

    void flushToolResults() {
      if (pendingToolResults.isEmpty) return;
      out.add(<String, dynamic>{
        'role': 'user',
        'content': pendingToolResults,
      });
      pendingToolResults = <Map<String, dynamic>>[];
    }

    for (final m in history) {
      final role = m['role'] as String? ?? 'user';
      if (role == 'tool') {
        // 不 flush——连续 tool 消息合并进同一条 user 消息
        pendingToolResults.add(<String, dynamic>{
          'type': 'tool_result',
          'tool_use_id': m['tool_call_id'] as String? ?? '',
          'content': (m['content'] ?? '').toString(),
        });
        continue;
      }
      flushToolResults();

      if (role == 'system') continue; // systemPrompt 走 body['system']

      final toolCalls = m['tool_calls'] as List<dynamic>?;
      if (role == 'assistant' && toolCalls != null && toolCalls.isNotEmpty) {
        final blocks = <Map<String, dynamic>>[];
        final text = (m['content'] as String? ?? '');
        if (text.isNotEmpty) {
          blocks.add(<String, dynamic>{'type': 'text', 'text': text});
        }
        for (final tc in toolCalls) {
          final call = tc as Map<String, dynamic>;
          final function =
              call['function'] as Map<String, dynamic>? ?? const {};
          blocks.add(<String, dynamic>{
            'type': 'tool_use',
            'id': call['id'] as String? ?? '',
            'name': function['name'] as String? ?? '',
            'input': _decodeArguments(function['arguments']),
          });
        }
        out.add(<String, dynamic>{'role': 'assistant', 'content': blocks});
        continue;
      }

      final content = (m['content'] as String? ?? '');
      out.add(<String, dynamic>{
        'role': role,
        'content': content.isEmpty ? ' ' : content,
      });
    }
    flushToolResults();
    return out;
  }

  /// Anthropic 响应 → ChatResponse。
  /// 遍历所有 content blocks：text 拼接为 content，tool_use 转 AiToolCall
  /// （input Map 经 jsonEncode 塞进 functionArguments，保持 OpenAI 形态）。
  static ChatResponse parseResponse(Map<String, dynamic> data) {
    final texts = <String>[];
    final toolCalls = <AiToolCall>[];
    final blocks = data['content'] as List<dynamic>? ?? const [];
    for (final block in blocks) {
      if (block is! Map<String, dynamic>) continue;
      switch (block['type']) {
        case 'text':
          final text = block['text'] as String?;
          if (text != null) texts.add(text);
        case 'tool_use':
          toolCalls.add(
            AiToolCall(
              id: block['id'] as String? ?? '',
              type: 'function',
              functionName: block['name'] as String? ?? '',
              functionArguments: jsonEncode(
                block['input'] ?? <String, dynamic>{},
              ),
            ),
          );
      }
    }
    return ChatResponse(
      content: texts.isEmpty ? null : texts.join(),
      toolCalls: toolCalls,
    );
  }

  /// OpenAI tool_calls 的 arguments 是 JSON 字符串；DeepSeek 偶发产生
  /// 非法 JSON——兜底为 {}（防一次脏数据打断整个 Agent 循环）。
  static Map<String, dynamic> _decodeArguments(dynamic arguments) {
    if (arguments is Map<String, dynamic>) return arguments;
    if (arguments is String) {
      try {
        final decoded = jsonDecode(arguments);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // 非法 JSON → 兜底 {}
      }
    }
    return <String, dynamic>{};
  }
}
