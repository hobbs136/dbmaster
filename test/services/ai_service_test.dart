import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai_service.dart';

void main() {
  group('AiService', () {
    test('is a singleton', () {
      final a = AiService();
      final b = AiService();
      expect(identical(a, b), true);
    });

    test('implements IAiClient', () {
      final service = AiService();
      expect(service, isA<IAiClient>());
    });

    test('has client accessor', () {
      final service = AiService();
      expect(service.client, isNotNull);
      expect(service.client, isA<AiClient>());
    });

    test('chat method exists with required signature', () {
      final service = AiService();
      expect(service.chat, isA<Function>());
    });

    test('chatStream method exists', () {
      final service = AiService();
      expect(service.chatStream, isA<Function>());
    });

    test('chatStreamWithReasoning method exists', () {
      final service = AiService();
      expect(service.chatStreamWithReasoning, isA<Function>());
    });

    test('loadPendingRequests returns a List', () async {
      final service = AiService();
      final requests = await service.loadPendingRequests();
      expect(requests, isA<List<PendingRequest>>());
    });

    test('getPendingRequest returns null for unknown id', () {
      final service = AiService();
      final result = service.getPendingRequest('nonexistent-id-99999');
      expect(result, isNull);
    });

    test('allPendingRequests is a Map', () {
      final service = AiService();
      expect(service.allPendingRequests, isA<Map<String, PendingRequest>>());
    });
  });
}
