import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/ai_conversation_session.dart';

void main() {
  test('AiMessage serializes with type toolCall', () {
    final msg = AiMessage(
      id: '1',
      isUser: false,
      content: '',
      type: AiMessageType.toolCall,
      toolName: 'execute_sql',
      toolArguments: {'sql': 'SELECT 1'},
      timestamp: DateTime.parse('2026-01-01T00:00:00Z'),
    );
    final json = msg.toJson();
    expect(json['type'], 'toolCall');
    expect(json['toolName'], 'execute_sql');
    final restored = AiMessage.fromJson(json);
    expect(restored.type, AiMessageType.toolCall);
    expect(restored.toolArguments?['sql'], 'SELECT 1');
  });

  test('AiMessage defaults to chat when type missing in json', () {
    final restored = AiMessage.fromJson({
      'id': '2',
      'isUser': true,
      'content': 'hello',
      'timestamp': '2026-01-01T00:00:00Z',
    });
    expect(restored.type, AiMessageType.chat);
  });

  test('AiConversationSession serializes new fields', () {
    final session = AiConversationSession(
      id: 's1',
      title: 'Test',
      createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      updatedAt: DateTime.parse('2026-01-01T00:00:00Z'),
      messageIds: ['1'],
      goalSummary: 'Query users',
      userMessageCount: 3,
      isArchived: true,
    );
    final json = session.toJson();
    expect(json['goalSummary'], 'Query users');
    expect(json['userMessageCount'], 3);
    expect(json['isArchived'], true);
    final restored = AiConversationSession.fromJson(json);
    expect(restored.goalSummary, 'Query users');
    expect(restored.userMessageCount, 3);
    expect(restored.isArchived, true);
  });
}
