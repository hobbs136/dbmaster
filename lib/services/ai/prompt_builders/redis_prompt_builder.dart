import 'base_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

class RedisPromptBuilder extends BasePromptBuilder {
  RedisPromptBuilder(super.dbService, {super.locale});

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

    // 2. 安全规则（Redis 简化版）
    buffer.writeln(buildSafetyRules());
    buffer.writeln();

    // 3. 上下文信息
    buffer.writeln(buildContextSection(connection, databaseName));
    buffer.writeln();

    // 4. 性能规则
    buffer.writeln(buildPerformanceRules());
    buffer.writeln();

    // 5. 数据库特定语法规范
    buffer.writeln(buildDatabaseSpecificGuidelines());
    buffer.writeln();

    // 6. 响应格式
    buffer.writeln(buildResponseFormatInstructions());
    buffer.writeln();

    // 7. Redis 命令格式要求
    buffer.writeln(l10n.sqlPromptRedisCommandFormatTitle);
    buffer.writeln(l10n.sqlPromptRedisCommandFormatMandatory);
    buffer.writeln(l10n.sqlPromptSqlTagRule2);
    buffer.writeln(l10n.sqlPromptSqlTagRule3);
    buffer.writeln(l10n.sqlPromptSqlTagRule4);
    buffer.writeln(l10n.sqlPromptSqlTagRule5);
    buffer.writeln(l10n.sqlPromptSqlTagRule7);
    buffer.writeln();

    // 8. 语气
    buffer.writeln(buildToneSection());
    buffer.writeln();

    return buffer.toString();
  }

  @override
  String buildResponseFormatInstructions() =>
      l10n.sqlPromptRedisResponseFormatBlock;

  @override
  String buildSafetyRules() {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptSafetyRulesTitle);
    buffer.writeln(l10n.sqlPromptRedisSafetyRulesBlock);
    return buffer.toString();
  }

  @override
  String buildDatabaseSpecificGuidelines() => l10n.sqlPromptRedisGuidelines;

  @override
  String buildPerformanceRules() => l10n.sqlPromptRedisPerformanceRules;

  @override
  String get quoteChar => '';

  @override
  String getExampleQuery(DatabaseConnection connection) {
    return 'SCAN 0 MATCH user:* COUNT 100';
  }
}
