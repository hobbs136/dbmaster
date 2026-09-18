import 'base_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class MongoDbPromptBuilder extends BasePromptBuilder {
  MongoDbPromptBuilder(super.dbService, {super.locale});

  @override
  Future<String> buildSystemPrompt({
    required DatabaseConnection connection,
    required String? databaseName,
    bool includeSchema = true,
    int maxTables = 30,
  }) async {
    final buffer = StringBuffer();

    // 1. 角色定义
    buffer.writeln(buildRoleSection(connection));
    buffer.writeln();

    // 2. 安全规则（MongoDB 简化版）
    buffer.writeln(buildSafetyRules());
    buffer.writeln();

    // 3. 上下文信息
    buffer.writeln(buildContextSection(connection, databaseName));
    buffer.writeln();

    // 4. Schema 信息（集合结构）
    if (includeSchema && databaseName != null) {
      final schemaInfo = await getCompactSchema(
        databaseName: databaseName,
        connection: connection,
        maxTables: maxTables,
      );
      if (schemaInfo.isNotEmpty) {
        buffer.writeln(l10n.sqlPromptSchemaTitle);
        buffer.writeln(schemaInfo);
        buffer.writeln();
      }
    }

    // 5. 性能规则
    buffer.writeln(buildPerformanceRules());
    buffer.writeln();

    // 6. 数据库特定语法规范
    buffer.writeln(buildDatabaseSpecificGuidelines());
    buffer.writeln();

    // 7. 响应格式
    buffer.writeln(buildResponseFormatInstructions());
    buffer.writeln();

    // 8. MongoDB 查询格式要求
    buffer.writeln(l10n.sqlPromptMongoQueryFormatTitle);
    buffer.writeln(l10n.sqlPromptMongoQueryFormatMandatory);
    buffer.writeln(l10n.sqlPromptSqlTagRule2);
    buffer.writeln(l10n.sqlPromptSqlTagRule3);
    buffer.writeln(l10n.sqlPromptSqlTagRule4);
    buffer.writeln(l10n.sqlPromptSqlTagRule5);
    buffer.writeln(l10n.sqlPromptSqlTagRule7);
    buffer.writeln();

    // 9. 语气
    buffer.writeln(buildToneSection());
    buffer.writeln();

    return buffer.toString();
  }

  @override
  String buildResponseFormatInstructions() =>
      l10n.sqlPromptMongoResponseFormatBlock;

  @override
  String buildSafetyRules() {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptSafetyRulesTitle);
    buffer.writeln(l10n.sqlPromptMongoSafetyRulesBlock);
    return buffer.toString();
  }

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptMongoGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptMongoPerformanceRules;

  @override
  String get quoteChar => '';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    return r"db.users.find({createdAt: {\$gte: new Date(Date.now() - 7*24*60*60*1000)}}).limit(10)";
  }
}
