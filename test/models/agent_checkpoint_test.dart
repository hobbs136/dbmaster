import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/agent_checkpoint.dart';

void main() {
  group('AgentCheckpoint', () {
    final now = DateTime(2026, 6, 1, 12, 0);
    final checkpoint = AgentCheckpoint(
      id: 'cp-1',
      sessionId: 'session-abc',
      userMessage: 'Create a users table',
      history: [
        {'role': 'user', 'content': 'Create a users table'},
        {'role': 'assistant', 'content': 'I will create the table...'},
      ],
      toolExecutions: [
        {
          'tool': 'execute_sql',
          'sql': 'CREATE TABLE users (...)',
          'result': 'success',
        },
      ],
      accumulatedReasoning:
          'The user needs a users table with standard columns.',
      toolCallCount: 1,
      currentIteration: 1,
      provider: 'anthropic',
      model: 'claude-opus-4-8',
      baseUrl: null,
      thinkingEnabled: true,
      createdAt: now,
    );

    test('toJson produces correct map', () {
      final json = checkpoint.toJson();
      expect(json['id'], 'cp-1');
      expect(json['sessionId'], 'session-abc');
      expect(json['toolCallCount'], 1);
      expect(json['currentIteration'], 1);
      expect(json['provider'], 'anthropic');
      expect(json['thinkingEnabled'], true);
      expect(json['isResumed'], false);
      expect(json['baseUrl'], isNull);
      expect(json['resumedAt'], isNull);
    });

    test('fromJson creates correct object', () {
      final json = checkpoint.toJson();
      final restored = AgentCheckpoint.fromJson(json);
      expect(restored.id, 'cp-1');
      expect(restored.sessionId, 'session-abc');
      expect(restored.userMessage, 'Create a users table');
      expect(restored.history.length, 2);
      expect(restored.toolExecutions.length, 1);
      expect(
        restored.accumulatedReasoning,
        'The user needs a users table with standard columns.',
      );
      expect(restored.toolCallCount, 1);
      expect(restored.currentIteration, 1);
      expect(restored.provider, 'anthropic');
      expect(restored.model, 'claude-opus-4-8');
      expect(restored.thinkingEnabled, true);
      expect(restored.createdAt, now);
      expect(restored.isResumed, false);
    });

    test('fromJson handles missing optional fields', () {
      final restored = AgentCheckpoint.fromJson({
        'id': 'minimal',
        'sessionId': 's',
        'userMessage': 'hello',
        'history': [],
        'toolExecutions': [],
        'toolCallCount': 0,
        'currentIteration': 0,
        'provider': 'openai',
        'model': 'gpt-4',
        'thinkingEnabled': false,
        'createdAt': '2026-06-01T12:00:00.000',
      });
      expect(restored.accumulatedReasoning, isNull);
      expect(restored.baseUrl, isNull);
      expect(restored.resumedAt, isNull);
      expect(restored.isResumed, false);
    });

    test('fromJson handles resumed checkpoint', () {
      final restored = AgentCheckpoint.fromJson({
        'id': 'cp-r',
        'sessionId': 's',
        'userMessage': 'continue',
        'history': [],
        'toolExecutions': [],
        'toolCallCount': 5,
        'currentIteration': 2,
        'provider': 'anthropic',
        'model': 'claude',
        'thinkingEnabled': true,
        'createdAt': '2026-06-01T12:00:00.000',
        'resumedAt': '2026-06-02T12:00:00.000',
        'isResumed': true,
      });
      expect(restored.isResumed, true);
      expect(restored.resumedAt, DateTime(2026, 6, 2, 12, 0));
    });

    test('fromJson handles baseUrl', () {
      final restored = AgentCheckpoint.fromJson({
        'id': 'cp',
        'sessionId': 's',
        'userMessage': 'h',
        'history': [],
        'toolExecutions': [],
        'toolCallCount': 0,
        'currentIteration': 0,
        'provider': 'custom',
        'model': 'custom-model',
        'baseUrl': 'https://custom.api.com/v1',
        'thinkingEnabled': false,
        'createdAt': '2026-06-01T12:00:00.000',
      });
      expect(restored.baseUrl, 'https://custom.api.com/v1');
    });

    test('copyWith preserves unchanged fields', () {
      final copied = checkpoint.copyWith();
      expect(copied.id, checkpoint.id);
      expect(copied.sessionId, checkpoint.sessionId);
    });

    test('copyWith updates specified fields', () {
      final resumed = DateTime(2026, 6, 6);
      final copied = checkpoint.copyWith(
        currentIteration: 3,
        toolCallCount: 2,
        accumulatedReasoning: 'Updated reasoning',
        resumedAt: resumed,
        isResumed: true,
      );
      expect(copied.currentIteration, 3);
      expect(copied.toolCallCount, 2);
      expect(copied.accumulatedReasoning, 'Updated reasoning');
      expect(copied.resumedAt, resumed);
      expect(copied.isResumed, true);
      expect(copied.id, checkpoint.id);
    });
  });
}
