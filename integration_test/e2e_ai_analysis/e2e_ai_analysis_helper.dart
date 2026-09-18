// ============================================================================
// E2E AI Analysis Helper - 公共辅助工具
//
// 提供：
//   - DeepSeek API 调用封装
//   - 测试数据库创建和清理
//   - AI 分析结果验证
//
// 使用方式：
//   import 'e2e_ai_analysis_helper.dart';
// ============================================================================

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/database_abstract.dart';

/// DeepSeek API 配置
class E2EAIConfig {
  static String get apiKey {
    const key = String.fromEnvironment('DEEPSEEK_API_KEY', defaultValue: '');
    if (key.isEmpty) {
      throw Exception('DEEPSEEK_API_KEY not set. Run with: DEEPSEEK_API_KEY=sk-xxx flutter test ...');
    }
    return key;
  }

  static const String apiEndpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const String model = 'deepseek-chat';
  static const int apiTimeout = 30; // 30 秒超时
  static const int maxRetries = 3; // 最大重试次数
  static const Duration retryDelay = Duration(seconds: 1);
}

/// DeepSeek API 调用结果
class E2EAIResponse {
  final String content;
  final bool success;
  final String? error;

  E2EAIResponse({
    required this.content,
    required this.success,
    this.error,
  });
}

/// 调用 DeepSeek API 进行 AI 分析
///
/// [prompt] - 发送给 AI 的提示词
/// [databaseType] - 数据库类型（用于上下文）
/// 返回: AI 分析结果
Future<E2EAIResponse> callDeepSeekAPI(
  String prompt, {
  DatabaseType? databaseType,
}) async {
  final apiKey = E2EAIConfig.apiKey;

  // 构建请求
  final messages = [
    {
      'role': 'user',
      'content': prompt,
    },
  ];

  final requestBody = {
    'model': E2EAIConfig.model,
    'messages': messages,
    'temperature': 0.7,
    'max_tokens': 2000,
    'stream': false,
  };

  int attempts = 0;
  while (attempts < E2EAIConfig.maxRetries) {
    attempts++;

    try {
      final response = await http.post(
        Uri.parse(E2EAIConfig.apiEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: E2EAIConfig.apiTimeout),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        final content = responseBody['choices'][0]['message']['content'] as String;

        return E2EAIResponse(
          content: content,
          success: true,
        );
      } else {
        // 非 200 响应，记录错误
        final error = 'API 返回 ${response.statusCode}: ${response.body}';
        return E2EAIResponse(
          content: '',
          success: false,
          error: error,
        );
      }
    } catch (e) {
      // 错误处理
      if (attempts == E2EAIConfig.maxRetries) {
        return E2EAIResponse(
          content: '',
          success: false,
          error: 'API 调用失败: $e',
        );
      }

      // 等待后重试
      if (attempts < E2EAIConfig.maxRetries) {
        await Future.delayed(E2EAIConfig.retryDelay);
      }
    }
  }

  return E2EAIResponse(
    content: '',
    success: false,
    error: '未知错误',
  );
}

/// 为查询结果生成 AI 分析提示词
String generateQueryAnalysisPrompt(String sql, dynamic result) {
  return '''
请分析以下 SQL 查询及其结果，提供：
1. 查询目的说明
2. 执行计划分析
3. 结果数据洞察
4. 性能优化建议（如适用）

SQL:
$sql

结果:
$result
''';
}

/// 为查询历史生成 AI 分析提示词
String generateHistoryAnalysisPrompt(List<Map<String, dynamic>> history) {
  final historyText = history
      .map((h) => '- ${h['sql']}: ${h['timestamp'] ?? ''}')
      .join('\n');

  return '''
请分析以下查询历史，提供：
1. 查询模式识别（CRUD、分析、聚合等）
2. 数据访问趋势
3. 性能优化建议
4. 安全风险评估

查询历史:
$historyText
''';
}

/// 为 Schema 信息生成 AI 解释提示词
String generateSchemaExplanationPrompt(Map<String, dynamic> schema) {
  final tables = schema['tables'] ?? [];
  final indexes = schema['indexes'] ?? [];
  final foreignKeys = schema['foreignKeys'] ?? [];

  return '''
请解释以下数据库 Schema，提供：
1. 表结构设计评估
2. 索引优化建议
3. 外键关系说明
4. 规范性检查

表: ${tables.length} 个
索引: ${indexes.length} 个
外键: ${foreignKeys.length} 个

详细结构:
$schema
''';
}
