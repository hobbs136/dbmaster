import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/services/ai_conversation_service.dart';
import 'package:dbmaster/models/ai_conversation_session.dart';

AiConversationService _newService() {
  SharedPreferences.setMockInitialValues({});
  return AiConversationService();
}

void main() {
  group('AiConversationService — session CRUD', () {
    test('initial state has no sessions', () {
      final s = _newService();
      expect(s.sessions, isEmpty);
      expect(s.currentSession, isNull);
      s.dispose();
    });

    test('createSession creates a new session', () {
      final s = _newService();
      final session = s.createSession(title: 'My Chat');
      expect(session.title, 'My Chat');
      expect(s.sessions.length, 1);
      expect(s.currentSession, session);
      s.dispose();
    });

    test('createSession default title follows locale (i18n)', () {
      final s = _newService();
      expect(s.createSession().title, contains('New Chat'));
      expect(s.createSession(locale: 'zh').title, contains('新对话'));
      s.dispose();
    });

    test('createSession gives unique IDs', () {
      final s = _newService();
      final s1 = s.createSession();
      final s2 = s.createSession();
      expect(s1.id, isNot(s2.id));
      expect(s.sessions.length, 2);
      s.dispose();
    });

    test('switchSession changes current session', () {
      final s = _newService();
      final s1 = s.createSession(title: 'Chat 1');
      final s2 = s.createSession(title: 'Chat 2');
      expect(s.currentSession, s2);
      s.switchSession(s1.id);
      expect(s.currentSession, s1);
      s.dispose();
    });

    test('switchSession to non-existent falls back to first', () {
      final s = _newService();
      final s1 = s.createSession();
      s.switchSession('nonexistent');
      expect(s.currentSession, s1);
      s.dispose();
    });

    test('deleteSession removes and handles empty', () {
      final s = _newService();
      final session = s.createSession();
      s.deleteSession(session.id);
      expect(s.sessions, isEmpty);
      expect(s.currentSession, isNull);
      s.dispose();
    });

    test('deleteSession with multiple sessions keeps others', () {
      final s = _newService();
      final s1 = s.createSession(title: 'C1');
      final s2 = s.createSession(title: 'C2');
      expect(s.sessions.length, 2);
      s.deleteSession(s1.id);
      expect(s.sessions.length, 1);
      expect(s.currentSession, s2);
      s.dispose();
    });

    test('deleteSession of current switches to first remaining', () {
      final s = _newService();
      final s1 = s.createSession(title: 'First');
      final s2 = s.createSession(title: 'Second');
      s.switchSession(s1.id);
      s.deleteSession(s1.id);
      expect(s.currentSession, s2);
      s.dispose();
    });

    test('archiveSession marks as archived', () {
      final s = _newService();
      final session = s.createSession();
      s.archiveSession(session.id);
      final archived = s.sessions.firstWhere((x) => x.id == session.id);
      expect(archived.isArchived, true);
      s.dispose();
    });

    test('updateSessionTitle updates title', () {
      final s = _newService();
      final session = s.createSession(title: 'Original');
      s.updateSessionTitle(session.id, 'Renamed');
      final updated = s.sessions.firstWhere((x) => x.id == session.id);
      expect(updated.title, 'Renamed');
      s.dispose();
    });

    test('bookmarks CRUD', () {
      final s = _newService();
      final bookmark = AiBookmark(
        id: 'bk-1',
        messageId: 'm-1',
        createdAt: DateTime.now(),
        note: 'Important answer',
      );
      s.setBookmarks([bookmark]);
      expect(s.bookmarks.length, 1);
      expect(s.bookmarks.first.note, 'Important answer');
      s.setBookmarks([]);
      expect(s.bookmarks, isEmpty);
      s.dispose();
    });

    test('bookmarks with tags', () {
      final s = _newService();
      final bookmark = AiBookmark(
        id: 'bk-2',
        messageId: 'm-2',
        createdAt: DateTime.now(),
        tags: ['important', 'todo'],
      );
      s.setBookmarks([bookmark]);
      expect(s.bookmarks.first.tags, ['important', 'todo']);
      s.dispose();
    });

    test('notifyListeners fires on mutation', () {
      final s = _newService();
      bool notified = false;
      s.addListener(() => notified = true);
      s.createSession();
      expect(notified, true);
      s.dispose();
    });

    test('branchFromMessage with no current session returns null', () {
      final s = _newService();
      final branched = s.branchFromMessage('msg', 'content');
      expect(branched, isNull);
      s.dispose();
    });

    test('branchFromMessage creates child session', () {
      final s = _newService();
      s.createSession(title: 'Parent');
      final branched = s.branchFromMessage(
        'msg-1',
        'This is a very long message that exceeds twenty characters',
        locale: 'zh',
      );
      expect(branched, isNotNull);
      // The title is built as: 基于: ${substring(0,20)}...
      // which becomes "基于: This is a very long..."
      expect(branched!.title, contains('基于:'));
      s.dispose();
    });

    test('branchFromMessage with short content', () {
      final s = _newService();
      s.createSession();
      final branched = s.branchFromMessage('msg-2', 'Short msg', locale: 'zh');
      expect(branched, isNotNull);
      expect(branched!.title, '基于: Short msg');
      s.dispose();
    });
  });

  group('AiConversationSession (model)', () {
    test('toJson/fromJson round-trip', () {
      final session = AiConversationSession(
        id: 's-1',
        title: 'Test Chat',
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 6),
        messageIds: ['m1', 'm2'],
        parentSessionId: 'parent-1',
        isArchived: false,
      );
      final restored = AiConversationSession.fromJson(session.toJson());
      expect(restored.id, 's-1');
      expect(restored.title, 'Test Chat');
      expect(restored.messageIds, ['m1', 'm2']);
      expect(restored.parentSessionId, 'parent-1');
      expect(restored.isArchived, false);
    });

    test('copyWith updates fields', () {
      final s = AiConversationSession(
        id: 's',
        title: 'T',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messageIds: [],
      );
      final copied = s.copyWith(title: 'New Title', isArchived: true);
      expect(copied.title, 'New Title');
      expect(copied.isArchived, true);
      expect(copied.id, 's');
    });
  });
}
