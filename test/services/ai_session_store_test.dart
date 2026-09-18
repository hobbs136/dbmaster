import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai_session_store.dart';

void main() {
  group('AiSessionStore', () {
    test('is a singleton', () {
      final a = AiSessionStore();
      final b = AiSessionStore();
      expect(identical(a, b), true);
    });

    test('resetForTests clears internal state without crash', () {
      final store = AiSessionStore();
      store.resetForTests();
      // After reset, internal _docsDir should be null, but external interface unchanged
    });
  });
}
