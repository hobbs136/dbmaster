import 'sql_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class MySqlPromptBuilder extends SqlPromptBuilder {
  MySqlPromptBuilder(super.dbService, {super.locale});

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptMysqlGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptMysqlPerformanceRules;

  @override
  String get quoteChar => '`';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    final quote = quoteChar;
    return 'SELECT ${quote}id$quote, ${quote}email$quote FROM ${quote}users$quote WHERE ${quote}created_at$quote >= DATE_SUB(NOW(), INTERVAL 7 DAY);';
  }
}
