import 'sql_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class SqlitePromptBuilder extends SqlPromptBuilder {
  SqlitePromptBuilder(super.dbService, {super.locale});

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptSqliteGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptSqlitePerformanceRules;

  @override
  String get quoteChar => '"';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    final quote = quoteChar;
    return 'SELECT ${quote}id$quote, ${quote}email$quote FROM ${quote}users$quote WHERE ${quote}created_at$quote >= datetime(\'now\', \'-7 days\');';
  }
}
