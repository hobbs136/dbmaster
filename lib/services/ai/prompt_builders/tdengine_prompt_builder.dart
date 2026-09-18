import 'sql_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class TdenginePromptBuilder extends SqlPromptBuilder {
  TdenginePromptBuilder(super.dbService, {super.locale});

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptTdengineGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptTdenginePerformanceRules;

  @override
  String get quoteChar => '`';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    final quote = quoteChar;
    return 'SELECT ${quote}id$quote, ${quote}email$quote FROM ${quote}users$quote WHERE ${quote}created_at$quote >= NOW() - 7d;';
  }
}
