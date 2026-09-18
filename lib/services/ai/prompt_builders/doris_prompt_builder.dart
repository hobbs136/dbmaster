import 'sql_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class DorisPromptBuilder extends SqlPromptBuilder {
  DorisPromptBuilder(super.dbService, {super.locale});

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptDorisGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptDorisPerformanceRules;

  @override
  String get quoteChar => '`';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    final quote = quoteChar;
    return 'SELECT ${quote}id$quote, ${quote}email$quote FROM ${quote}users$quote WHERE ${quote}created_at$quote >= DATE_SUB(NOW(), INTERVAL 7 DAY);';
  }
}
