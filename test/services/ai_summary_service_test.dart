import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai_summary_service.dart';
import 'package:dbmaster/services/ai_service.dart';

void main() {
  group('AiSummaryService', () {
    test('empty-message summary follows locale (i18n)', () async {
      final aiService = AiService();
      final summaryService = AiSummaryService(aiService);

      final en = await summaryService.generateSessionSummary(
        messages: const [],
        apiKey: 'test',
        provider: 'DeepSeek',
        model: 'deepseek-chat',
      );
      expect(en, contains('Empty'));

      // zh → Chinese.
      final zh = await summaryService.generateSessionSummary(
        messages: const [],
        apiKey: 'test',
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        locale: 'zh',
      );
      expect(zh, equals('空对话'));
    });
  });
}
