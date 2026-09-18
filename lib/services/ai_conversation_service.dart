import 'dart:async';
import '../utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_conversation_session.dart';
import '../models/database_models.dart';
import 'ai/ai_service_localizations.dart';
import 'ai_session_store.dart';

class AiConversationService extends ChangeNotifier {
  final List<AiConversationSession> _sessions = [];
  AiConversationSession? _currentSession;
  int _sessionCounter = 0;

  final Map<String, List<AiMessage>> _sessionMessages = {};
  final List<AiBookmark> _bookmarks = [];

  List<AiConversationSession> get sessions => List.unmodifiable(_sessions);
  AiConversationSession? get currentSession => _currentSession;
  List<AiBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  Timer? _persistDebounceTimer;

  void setBookmarks(List<AiBookmark> value) {
    _bookmarks.clear();
    _bookmarks.addAll(value);
    _requestPersist();
    notifyListeners();
  }

  AiConversationSession createSession({
    String? title,
    String? parentMessageId,
    String locale = 'en',
  }) {
    _sessionCounter++;
    final session = AiConversationSession(
      id: '${DateTime.now().millisecondsSinceEpoch}_$_sessionCounter',
      title: title ?? AiServiceLocalizations(locale).newChatTitle(_sessions.length + 1),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messageIds: [],
      parentSessionId: parentMessageId != null ? _currentSession?.id : null,
    );
    _sessions.insert(0, session);
    _currentSession = session;
    _sessionMessages[session.id] = [];
    _requestPersist();
    _saveActiveSessionId();
    notifyListeners();
    return session;
  }

  void switchSession(String sessionId) {
    _currentSession = _sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => _sessions.first,
    );
    _saveActiveSessionId();
    notifyListeners();
  }

  void addMessageToSession(String messageId, AiMessage message) {
    final session = _currentSession;
    if (session == null) return;
    session.messageIds.add(messageId);
    _sessionMessages.putIfAbsent(session.id, () => []);
    _sessionMessages[session.id]!.add(message);
    final index = _sessions.indexWhere((s) => s.id == session.id);
    if (index != -1) {
      _sessions[index] = session.copyWith(updatedAt: DateTime.now());
      _currentSession = _sessions[index];
    }
    _requestPersist();
    notifyListeners();
  }

  List<AiMessage> getCurrentSessionMessages() {
    if (_currentSession == null) return [];
    return List.unmodifiable(_sessionMessages[_currentSession!.id] ?? []);
  }

  List<AiMessage> getSessionMessages(String sessionId) {
    return List.unmodifiable(_sessionMessages[sessionId] ?? []);
  }

  void updateCurrentSessionMessages(List<AiMessage> messages) {
    if (_currentSession == null) return;
    _sessionMessages[_currentSession!.id] = List.from(messages);
    _requestPersist();
    notifyListeners();
  }

  AiConversationSession? branchFromMessage(
    String messageId,
    String messageContent, {
    String locale = 'en',
  }) {
    if (_currentSession == null) return null;

    final preview = messageContent.length > 20
        ? '${messageContent.substring(0, 20)}...'
        : messageContent;
    return createSession(
      title: AiServiceLocalizations(locale).branchSessionTitle(preview),
      parentMessageId: messageId,
      locale: locale,
    );
  }

  void archiveSession(String sessionId) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      _sessions[index] = _sessions[index].copyWith(isArchived: true);
      _requestPersist();
      notifyListeners();
    }
  }

  void deleteSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    _sessionMessages.remove(sessionId);
    if (_currentSession?.id == sessionId) {
      _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
    }
    _requestPersist();
    _saveActiveSessionId();
    notifyListeners();
  }

  void restoreSession(AiConversationSession session) {
    _sessions.insert(0, session);
    _requestPersist();
    _saveActiveSessionId();
    notifyListeners();
  }

  void updateSessionTitle(String sessionId, String title) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      _sessions[index] = _sessions[index].copyWith(
        title: title,
        updatedAt: DateTime.now(),
      );
      _requestPersist();
      notifyListeners();
    }
  }

  void updateSessionMetadata(
    String sessionId, {
    String? goalSummary,
    int? userMessageCount,
    DateTime? lastSummarizedAt,
  }) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;
    _sessions[index] = _sessions[index].copyWith(
      goalSummary: goalSummary,
      userMessageCount: userMessageCount,
      lastSummarizedAt: lastSummarizedAt,
    );
    if (_currentSession?.id == sessionId) {
      _currentSession = _sessions[index];
    }
    _requestPersist();
    notifyListeners();
  }

  Future<void> loadFromStore() async {
    try {
      final store = AiSessionStore();
      final sessions = await store.loadSessions();
      final bookmarks = await store.loadBookmarks();
      _sessions.clear();
      _sessions.addAll(
        sessions.where((s) => !s.isArchived).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );
      _sessions.addAll(
        sessions.where((s) => s.isArchived).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );
      _sessionMessages.clear();
      for (final s in sessions) {
        final messages = await store.loadMessages(s.id);
        _sessionMessages[s.id] = messages;
      }
      _bookmarks.clear();
      _bookmarks.addAll(bookmarks);
      final prefs = await SharedPreferences.getInstance();
      final activeId = prefs.getString('ai_active_session_id');
      if (activeId != null && _sessions.any((s) => s.id == activeId)) {
        _currentSession = _sessions.firstWhere((s) => s.id == activeId);
      } else {
        _currentSession = _sessions.isNotEmpty ? _sessions.first : null;
      }
      notifyListeners();
    } catch (e) {
      _sessions.clear();
      _sessionMessages.clear();
      _currentSession = null;
      notifyListeners();
    }
  }

  void _requestPersist() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _persist();
    });
  }

  Future<void> _persist() async {
    try {
      final store = AiSessionStore();
      await store.saveSessions(_sessions);
      await store.saveBookmarks(_bookmarks);
      for (final entry in _sessionMessages.entries) {
        await store.saveMessages(entry.key, entry.value);
      }
    } catch (e) {
      AppLogger.d(
        'AiConversation',
        'AiConversationService persistence failed: $e',
      );
    }
  }

  Future<void> _saveActiveSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentSession != null) {
      await prefs.setString('ai_active_session_id', _currentSession!.id);
    } else {
      await prefs.remove('ai_active_session_id');
    }
  }

  @override
  void dispose() {
    _persistDebounceTimer?.cancel();
    super.dispose();
  }
}
