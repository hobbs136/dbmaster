import 'sql_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class PostgreSqlPromptBuilder extends SqlPromptBuilder {
  PostgreSqlPromptBuilder(super.dbService, {super.locale});

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptPostgresqlGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptPostgresqlPerformanceRules;

  @override
  String get quoteChar => '"';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    final quote = quoteChar;
    return 'SELECT ${quote}id$quote, ${quote}email$quote FROM ${quote}users$quote WHERE ${quote}created_at$quote >= NOW() - INTERVAL \'7 days\';';
  }
}
