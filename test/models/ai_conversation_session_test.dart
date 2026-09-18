import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/ai_conversation_session.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('AiConversationSession', () {
    test('should support branching with parentSessionId', () {
      final parentSession = AiConversationSession(
        id: 'session-1',
        title: 'Parent Session',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 2),
        messageIds: ['msg-1', 'msg-2'],
      );

      final childSession = AiConversationSession(
        id: 'session-2',
        title: 'Child Session',
        createdAt: DateTime(2024, 1, 3),
        updatedAt: DateTime(2024, 1, 4),
        messageIds: ['msg-3'],
        parentSessionId: 'session-1',
      );

      expect(childSession.parentSessionId, equals('session-1'));
      expect(parentSession.parentSessionId, isNull);
    });

    test('should copyWith preserve fields correctly', () {
      final original = AiConversationSession(
        id: 'session-1',
        title: 'Original',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 2),
        messageIds: ['msg-1'],
        isArchived: false,
      );

      final copied = original.copyWith(
        title: 'Modified',
        messageIds: ['msg-1', 'msg-2'],
      );

      expect(copied.id, equals('session-1'));
      expect(copied.title, equals('Modified'));
      expect(copied.messageIds, equals(['msg-1', 'msg-2']));
      expect(copied.isArchived, isFalse);
    });
  });

  group('AiBookmark', () {
    test('should create bookmark with tags', () {
      final bookmark = AiBookmark(
        id: 'bookmark-1',
        messageId: 'msg-1',
        note: 'Important point',
        createdAt: DateTime(2024, 1, 1),
        tags: ['important', 'review'],
      );

      expect(bookmark.tags, contains('important'));
      expect(bookmark.tags, contains('review'));
      expect(bookmark.note, equals('Important point'));
    });

    test('should have default empty tags', () {
      final bookmark = AiBookmark(
        id: 'bookmark-1',
        messageId: 'msg-1',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(bookmark.tags, isEmpty);
    });
  });

  group('AiMessage with bookmark fields', () {
    test('should copy bookmark fields correctly', () {
      final message = AiMessage(
        id: 'msg-1',
        isUser: false,
        content: 'Hello',
        timestamp: DateTime(2024, 1, 1),
        isBookmarked: true,
        bookmarkNote: 'Great answer',
        replyToMessageId: 'msg-0',
        branchFromMessageId: null,
      );

      final copied = message.copyWith(
        isBookmarked: false,
        bookmarkNote: 'Updated note',
      );

      expect(copied.isBookmarked, isFalse);
      expect(copied.bookmarkNote, equals('Updated note'));
      expect(copied.replyToMessageId, equals('msg-0'));
      expect(copied.id, equals('msg-1'));
    });

    test('should have default bookmark values', () {
      final message = AiMessage(
        id: 'msg-1',
        isUser: true,
        content: 'Test',
        timestamp: DateTime(2024, 1, 1),
      );

      expect(message.isBookmarked, isFalse);
      expect(message.bookmarkNote, isNull);
      expect(message.replyToMessageId, isNull);
      expect(message.branchFromMessageId, isNull);
    });
  });

  group('AiMessageReference', () {
    test('should create reference with correct type', () {
      final reference = AiMessageReference(
        id: 'ref-1',
        sourceMessageId: 'msg-2',
        targetMessageId: 'msg-1',
        referenceType: 'reply',
      );

      expect(reference.referenceType, equals('reply'));
      expect(reference.sourceMessageId, equals('msg-2'));
      expect(reference.targetMessageId, equals('msg-1'));
    });
  });
}
