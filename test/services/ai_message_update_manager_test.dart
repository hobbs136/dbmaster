import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai_message_update_manager.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('UpdateType', () {
    test('has 4 values', () {
      expect(UpdateType.values.length, 4);
      expect(
        UpdateType.values,
        containsAll([
          UpdateType.content,
          UpdateType.reasoning,
          UpdateType.loading,
          UpdateType.full,
        ]),
      );
    });
  });

  group('MessageUpdateEvent', () {
    test('fields are correct', () {
      final msg = AiMessage(
        id: 'msg-1',
        isUser: false,
        content: 'Partial...',
        timestamp: DateTime.now(),
      );
      final event = MessageUpdateEvent(
        messageId: 'msg-1',
        message: msg,
        type: UpdateType.content,
      );
      expect(event.messageId, 'msg-1');
      expect(event.message, msg);
      expect(event.type, UpdateType.content);
    });
  });

  group('AiMessageUpdateManager', () {
    test('is a singleton', () {
      final a = AiMessageUpdateManager();
      final b = AiMessageUpdateManager();
      expect(identical(a, b), true);
    });

    test('watchMessage returns a stream', () {
      final manager = AiMessageUpdateManager();
      final stream = manager.watchMessage('msg-stream');
      expect(stream, isA<Stream<MessageUpdateEvent>>());
      manager.clearMessage('msg-stream');
    });

    test('getCachedMessage returns null for unknown message', () {
      final manager = AiMessageUpdateManager();
      expect(manager.getCachedMessage('nonexistent'), isNull);
    });

    test('notifyUpdate broadcasts to listener and caches', () async {
      final manager = AiMessageUpdateManager();
      final msg = AiMessage(
        id: 'msg-a',
        isUser: false,
        content: 'Streaming...',
        timestamp: DateTime.now(),
      );

      final stream = manager.watchMessage('msg-a');
      final event = MessageUpdateEvent(
        messageId: 'msg-a',
        message: msg,
        type: UpdateType.content,
      );

      // Listen first, then trigger
      final future = stream.first;
      manager.notifyUpdate(event);

      final received = await future.timeout(const Duration(seconds: 2));

      expect(received.messageId, 'msg-a');
      expect(received.type, UpdateType.content);
      expect(manager.getCachedMessage('msg-a'), msg);

      manager.clearMessage('msg-a');
    });

    test('notifyBatchUpdates broadcasts multiple events', () async {
      final manager = AiMessageUpdateManager();
      final msg1 = AiMessage(
        id: 'b1',
        isUser: false,
        content: 'A',
        timestamp: DateTime.now(),
      );
      final msg2 = AiMessage(
        id: 'b2',
        isUser: false,
        content: 'B',
        timestamp: DateTime.now(),
      );

      final stream1 = manager.watchMessage('b1');
      final stream2 = manager.watchMessage('b2');

      final received1 = <MessageUpdateEvent>[];
      final received2 = <MessageUpdateEvent>[];
      final sub1 = stream1.listen(received1.add);
      final sub2 = stream2.listen(received2.add);

      manager.notifyBatchUpdates([
        MessageUpdateEvent(
          messageId: 'b1',
          message: msg1,
          type: UpdateType.content,
        ),
        MessageUpdateEvent(
          messageId: 'b2',
          message: msg2,
          type: UpdateType.content,
        ),
      ]);

      // Wait for async stream delivery
      await Future.delayed(const Duration(milliseconds: 200));

      await sub1.cancel();
      await sub2.cancel();

      expect(received1.length, 1);
      expect(received2.length, 1);
      expect(received1.first.messageId, 'b1');
      expect(received2.first.messageId, 'b2');

      manager.clearMessage('b1');
      manager.clearMessage('b2');
    });

    test('clearMessage removes cache', () {
      final manager = AiMessageUpdateManager();
      final msg = AiMessage(
        id: 'clear-me',
        isUser: true,
        content: 'X',
        timestamp: DateTime.now(),
      );
      manager.watchMessage('clear-me');
      manager.notifyUpdate(
        MessageUpdateEvent(
          messageId: 'clear-me',
          message: msg,
          type: UpdateType.content,
        ),
      );
      expect(manager.getCachedMessage('clear-me'), isNotNull);

      manager.clearMessage('clear-me');
      expect(manager.getCachedMessage('clear-me'), isNull);
    });

    test('dispose cleans up all controllers', () {
      final manager = AiMessageUpdateManager();
      manager.watchMessage('d1');
      manager.watchMessage('d2');

      manager.dispose();

      // After dispose, new stream should still work
      final stream = manager.watchMessage('d3');
      expect(stream, isA<Stream>());
      manager.clearMessage('d3');
    });
  });
}
