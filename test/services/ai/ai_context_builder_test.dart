import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/ai/ai_context_builder.dart';

void main() {
  group('AiContextBuilder', () {
    late AiContextBuilder builder;

    setUp(() {
      builder = AiContextBuilder();
    });

    group('状态管理', () {
      test('初始状态应为空', () {
        expect(builder.currentTable, isNull);
        expect(builder.currentConnection, isNull);
        expect(builder.currentDatabase, isNull);
        expect(builder.recentQueries, isEmpty);
      });

      test('setCurrentTable 应更新当前表', () {
        builder.setCurrentTable('users');
        expect(builder.currentTable, 'users');
      });

      test('setCurrentConnection 应更新当前连接', () {
        builder.setCurrentConnection('conn_1');
        expect(builder.currentConnection, 'conn_1');
      });

      test('setCurrentDatabase 应更新当前数据库并清除缓存', () {
        builder.cacheTableSchema('users', 'CREATE TABLE users');
        builder.setCurrentDatabase('mydb');
        expect(builder.currentDatabase, 'mydb');
        expect(builder.getCachedTableSchema('users'), isNull);
      });

      test('clear 应重置所有状态', () {
        builder.setCurrentTable('users');
        builder.setCurrentConnection('conn_1');
        builder.setCurrentDatabase('mydb');
        builder.addRecentQuery('SELECT 1');

        builder.clear();

        expect(builder.currentTable, isNull);
        expect(builder.currentConnection, isNull);
        expect(builder.currentDatabase, isNull);
        expect(builder.recentQueries, isEmpty);
      });
    });

    group('缓存', () {
      test('cacheTableSchema / getCachedTableSchema', () {
        builder.cacheTableSchema('users', 'CREATE TABLE users (id INT)');
        expect(
          builder.getCachedTableSchema('users'),
          'CREATE TABLE users (id INT)',
        );
      });

      test('不同表的缓存应独立', () {
        builder.cacheTableSchema('users', 'schema_users');
        builder.cacheTableSchema('posts', 'schema_posts');
        expect(builder.getCachedTableSchema('users'), 'schema_users');
        expect(builder.getCachedTableSchema('posts'), 'schema_posts');
      });
    });

    group('recentQueries', () {
      test('addRecentQuery 应添加到头部', () {
        builder.addRecentQuery('SELECT 1');
        builder.addRecentQuery('SELECT 2');
        expect(builder.recentQueries.first, 'SELECT 2');
        expect(builder.recentQueries.last, 'SELECT 1');
      });

      test('recentQueries 应限制为 20 条', () {
        for (var i = 0; i < 25; i++) {
          builder.addRecentQuery('SELECT $i');
        }
        expect(builder.recentQueries.length, 20);
      });

      test('recentQueries 应不可变', () {
        builder.addRecentQuery('SELECT 1');
        final queries = builder.recentQueries;
        expect(() => queries.add('SELECT 2'), throwsUnsupportedError);
      });
    });

    group('buildContextPrompt', () {
      test('空状态时应返回空字符串', () {
        final prompt = builder.buildContextPrompt();
        expect(prompt, isEmpty);
      });

      test('应包含数据库名', () {
        builder.setCurrentDatabase('mydb');
        final prompt = builder.buildContextPrompt();
        expect(prompt, contains('mydb'));
      });

      test('应包含表名', () {
        builder.setCurrentTable('users');
        final prompt = builder.buildContextPrompt();
        expect(prompt, contains('users'));
      });

      test('应包含最近查询', () {
        builder.addRecentQuery('SELECT * FROM users');
        final prompt = builder.buildContextPrompt();
        expect(prompt, contains('SELECT * FROM users'));
      });

      test('应限制最近查询为 3 条', () {
        builder.addRecentQuery('SELECT 1');
        builder.addRecentQuery('SELECT 2');
        builder.addRecentQuery('SELECT 3');
        builder.addRecentQuery('SELECT 4');
        final prompt = builder.buildContextPrompt();
        expect(prompt, isNot(contains('SELECT 1')));
      });
    });

    group('pickFastModel', () {
      test('moonshot 应返回 8k 模型', () {
        expect(
          AiContextBuilder.pickFastModel('moonshot-v1-32k'),
          'moonshot-v1-8k',
        );
      });

      test('deepseek 应返回 deepseek-chat', () {
        expect(
          AiContextBuilder.pickFastModel('deepseek-coder'),
          'deepseek-chat',
        );
      });

      test('glm 应返回 glm-4-flash', () {
        expect(AiContextBuilder.pickFastModel('glm-4'), 'glm-4-flash');
      });

      test('gpt 应返回 gpt-4o-mini', () {
        expect(AiContextBuilder.pickFastModel('gpt-4o'), 'gpt-4o-mini');
      });

      test('未知模型应返回原模型', () {
        expect(AiContextBuilder.pickFastModel('custom-model'), 'custom-model');
      });
    });

    group('buildContext', () {
      test('空消息应返回最小上下文', () {
        final result = AiContextBuilder.buildContext(
          fixedSystemPrompt: 'You are a helpful assistant',
          allMessages: [],
          goalSummary: null,
          model: 'deepseek-chat',
        );
        expect(result.systemPrompt, isNotEmpty);
        expect(result.messages, isEmpty);
      });

      test('应过滤 toolCall/toolResult 消息', () {
        final now = DateTime.now();
        final messages = [
          AiMessage(
            id: '1',
            type: AiMessageType.chat,
            content: 'Hello',
            isUser: true,
            timestamp: now,
          ),
          AiMessage(
            id: '2',
            type: AiMessageType.toolCall,
            content: '{}',
            isUser: false,
            timestamp: now,
          ),
          AiMessage(
            id: '3',
            type: AiMessageType.toolResult,
            content: '{}',
            isUser: false,
            timestamp: now,
          ),
        ];
        final result = AiContextBuilder.buildContext(
          fixedSystemPrompt: 'Sys',
          allMessages: messages,
          goalSummary: null,
          model: 'deepseek-chat',
        );
        expect(result.messages.length, 1);
      });

      test('应转换消息为 history 格式', () {
        final now = DateTime.now();
        final messages = [
          AiMessage(
            id: '1',
            type: AiMessageType.chat,
            content: 'Hello',
            isUser: true,
            timestamp: now,
          ),
          AiMessage(
            id: '2',
            type: AiMessageType.chat,
            content: 'Hi there',
            isUser: false,
            timestamp: now,
          ),
        ];
        final result = AiContextBuilder.buildContext(
          fixedSystemPrompt: 'Sys',
          allMessages: messages,
          goalSummary: null,
          model: 'deepseek-chat',
        );
        expect(result.messages.length, 2);
        expect(result.messages[0]['role'], 'user');
        expect(result.messages[1]['role'], 'assistant');
      });

      test('应包含 reasoning_content', () {
        final now = DateTime.now();
        final messages = [
          AiMessage(
            id: '1',
            type: AiMessageType.chat,
            content: 'Answer',
            isUser: false,
            reasoningContent: 'Let me think...',
            timestamp: now,
          ),
        ];
        final result = AiContextBuilder.buildContext(
          fixedSystemPrompt: 'Sys',
          allMessages: messages,
          goalSummary: null,
          model: 'deepseek-chat',
        );
        expect(result.messages[0]['reasoning_content'], 'Let me think...');
      });

      test('goalSummary 应添加到 system prompt', () {
        final result = AiContextBuilder.buildContext(
          fixedSystemPrompt: 'You are an assistant',
          allMessages: [],
          goalSummary: 'The user wants to optimize queries',
          model: 'deepseek-chat',
        );
        expect(result.systemPrompt, contains('optimize queries'));
      });
    });
  });
}
