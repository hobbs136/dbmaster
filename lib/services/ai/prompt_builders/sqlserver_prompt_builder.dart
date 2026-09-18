import 'sql_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class SqlServerPromptBuilder extends SqlPromptBuilder {
  SqlServerPromptBuilder(super.dbService, {super.locale});

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptSqlserverGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptSqlserverPerformanceRules;

  @override
  String get quoteChar => '[';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    final quote = quoteChar;
    final closeQuote = ']';
    return 'SELECT ${quote}id$closeQuote, ${quote}email$closeQuote FROM ${quote}users$closeQuote WHERE ${quote}created_at$closeQuote >= DATEADD(day, -7, GETDATE());';
  }
}
