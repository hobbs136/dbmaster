import '../models/database_models.dart';
import 'ai_service.dart';
import 'ai/ai_service_localizations.dart';
import 'result_statistics_service.dart';
import '../models/result_filter.dart';

class AiSummaryService {
  final AiService _aiService;

  AiSummaryService(this._aiService);

  Future<String> generateSessionSummary({
    required List<AiMessage> messages,
    required String apiKey,
    required String provider,
    required String model,
    String? baseUrl,
    String locale = 'en',
  }) async {
    if (messages.isEmpty) return AiServiceLocalizations(locale).summaryEmptyConversation;

    final l10n = AiServiceLocalizations(locale);
    final buffer = StringBuffer();
    buffer.writeln(l10n.aiSummaryConversationDigestHeader);
    buffer.writeln('');

    for (final msg in messages.take(10)) {
      final role = msg.isUser ? l10n.aiSummaryRoleUser : 'AI';
      final preview = msg.content.length > 100
          ? '${msg.content.substring(0, 100)}...'
          : msg.content;
      buffer.writeln('- $role: $preview');
    }

    if (messages.length > 10) {
      buffer.writeln(l10n.aiSummaryMoreMessagesHint(messages.length));
    }

    final summaryPrompt =
        '${l10n.aiSummarySummarizePrompt}\n${buffer.toString()}\n';

    try {
      final summary = await _aiService.chat(
        provider: provider,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        message: summaryPrompt,
        timeout: const Duration(seconds: 30),
      );
      return summary.content?.trim() ?? AiServiceLocalizations(locale).summaryDefaultFallback;
    } catch (e) {
      return AiServiceLocalizations(locale).summaryDefaultFallback;
    }
  }

  /// R5: 分析查询结果的趋势（图表视角）。
  ///
  /// 传**聚合摘要**给 LLM（不传原始数据，避免 token 爆炸 + PII 泄露）：
  /// 行数 + 各列统计（数值列的 min/max/avg + 趋势）+ 用户选定的图表轴。
  /// AI 不可用时返回降级提示。
  Future<String> analyzeResultTrend({
    required List<Map<String, dynamic>> data,
    required Map<String, ColumnDataType> columnTypes,
    required String apiKey,
    required String provider,
    required String model,
    String? baseUrl,
    String locale = 'en',
  }) async {
    if (data.isEmpty) {
      return AiServiceLocalizations(locale).summaryDefaultFallback;
    }

    // 构造聚合摘要（NF5: 不含原始 PII 值，只含统计指标）
    final summary = StringBuffer();
    summary.writeln('数据集：${data.length} 行 × ${columnTypes.length} 列');
    try {
      final stats = ResultStatisticsService.compute(
        data: data,
        columnTypes: columnTypes,
      );
      summary.writeln('数值列统计：');
      for (final s in stats.where((s) => s.isNumeric).take(5)) {
        summary.writeln(
          '- $s: min=${s.min?.toStringAsFixed(2)}, max=${s.max?.toStringAsFixed(2)}, '
          'avg=${s.avg?.toStringAsFixed(2)}, 中位数=${s.median?.toStringAsFixed(2)}',
        );
      }
      final cat = stats.where((s) => s.isCategorical).toList();
      if (cat.isNotEmpty) {
        summary.writeln('分类列（TOP）：');
        for (final s in cat.take(3)) {
          final top = s.topValues?.take(3).map((e) => '${e.key}(${e.value})').join(', ');
          summary.writeln('- $s: $top');
        }
      }
    } on DatasetTooLargeException {
      summary.writeln('（数据量过大，仅基于行数分析）');
    }

    final prompt = '你是数据分析助手。请基于以下查询结果的统计摘要，'
        '用简洁的语言分析数据趋势、分布特征和值得关注的点（不超过 200 字）：\n\n'
        '${summary.toString()}\n';

    try {
      final result = await _aiService.chat(
        provider: provider,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        message: prompt,
        timeout: const Duration(seconds: 30),
      );
      return result.content?.trim() ?? AiServiceLocalizations(locale).summaryDefaultFallback;
    } catch (e) {
      return AiServiceLocalizations(locale).summaryDefaultFallback;
    }
  }
}
