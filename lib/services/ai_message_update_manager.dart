import 'dart:async';
import '../models/database_models.dart';

class MessageUpdateEvent {
  final String messageId;
  final AiMessage message;
  final UpdateType type;

  MessageUpdateEvent({
    required this.messageId,
    required this.message,
    required this.type,
  });
}

enum UpdateType { content, reasoning, loading, full }

class AiMessageUpdateManager {
  static final AiMessageUpdateManager _instance =
      AiMessageUpdateManager._internal();
  factory AiMessageUpdateManager() => _instance;
  AiMessageUpdateManager._internal();

  final Map<String, StreamController<MessageUpdateEvent>> _controllers = {};
  final Map<String, AiMessage> _messageCache = {};

  Stream<MessageUpdateEvent> watchMessage(String messageId) {
    _controllers.putIfAbsent(
      messageId,
      () => StreamController<MessageUpdateEvent>.broadcast(),
    );
    return _controllers[messageId]!.stream;
  }

  AiMessage? getCachedMessage(String messageId) => _messageCache[messageId];

  void notifyUpdate(MessageUpdateEvent event) {
    _messageCache[event.messageId] = event.message;
    _controllers[event.messageId]?.add(event);
  }

  void notifyBatchUpdates(List<MessageUpdateEvent> events) {
    for (final event in events) {
      _messageCache[event.messageId] = event.message;
      _controllers[event.messageId]?.add(event);
    }
  }

  void clearMessage(String messageId) {
    _messageCache.remove(messageId);
    _controllers[messageId]?.close();
    _controllers.remove(messageId);
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _messageCache.clear();
  }
}
