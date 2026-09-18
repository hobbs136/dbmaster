import 'base_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;

/// SQL 类数据库的 PromptBuilder 基类
///
/// 为 MySQL / PostgreSQL / SQLite / Doris / TDengine / SQL Server 提供共享逻辑。
/// 子类只需要实现数据库特定的规则和方法。
abstract class SqlPromptBuilder extends BasePromptBuilder {
  SqlPromptBuilder(super.dbService, {super.locale});

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

    // 2. 安全规则
    buffer.writeln(buildSafetyRules());
    buffer.writeln();

    // 2.5 自主探索工作流 + 数据修改请求规范（通用数据库 Agent 行为核心）
    buffer.writeln(l10n.sqlPromptExplorationTitle);
    buffer.writeln(l10n.sqlPromptExplorationRules);
    buffer.writeln();
    buffer.writeln(l10n.sqlPromptDataModTitle);
    buffer.writeln(l10n.sqlPromptDataModRules);
    buffer.writeln();

    // 3. 上下文信息
    buffer.writeln(buildContextSection(connection, databaseName));
    buffer.writeln();

    // 4. Schema 信息
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

    // 6. 工具说明
    buffer.writeln(buildToolInstructions());
    buffer.writeln();

    // 7. 数据库特定语法规范
    buffer.writeln(buildDatabaseSpecificGuidelines());
    buffer.writeln();

    // 8. 响应格式（关键修复：简化为只输出 Analysis + Query）
    buffer.writeln(buildResponseFormatInstructions());
    buffer.writeln();

    // 9. SQL 标签格式要求
    buffer.writeln(buildSqlTagSection());
    buffer.writeln();

    // 10. 语法规范
    buffer.writeln(buildSyntaxSection(connection));
    buffer.writeln();

    // 11. 示例
    buffer.writeln(buildExampleSection(connection));
    buffer.writeln();

    // 12. 语气
    buffer.writeln(buildToneSection());
    buffer.writeln();

    return buffer.toString();
  }

  @override
  String buildResponseFormatInstructions() => l10n.sqlPromptResponseFormatBlock;

  @override
  String buildSafetyRules() {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptSafetyRulesTitle);
    buffer.writeln(l10n.sqlPromptSafetyRule1);
    buffer.writeln(l10n.sqlPromptSafetyRule2Prefix);
    buffer.writeln(l10n.sqlPromptSafetyRule2a);
    buffer.writeln(l10n.sqlPromptSafetyRule2b);
    buffer.writeln(l10n.sqlPromptSafetyRule2c);
    buffer.writeln(l10n.sqlPromptSafetyRule3);
    buffer.writeln(l10n.sqlPromptSafetyRule4);
    return buffer.toString();
  }

  @override
  String buildExampleSection(DatabaseConnection connection) {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptExampleTitle);
    buffer.writeln('User: ${l10n.sqlPromptExampleUserQuery}');
    buffer.writeln('You:');
    buffer.writeln('**Analysis**: ${l10n.sqlPromptExampleAnalysis}');
    buffer.writeln('**Query**:');
    buffer.writeln('\u003csql\u003e');
    buffer.writeln(getExampleQuery(connection));
    buffer.writeln('\u003c/sql\u003e');
    return buffer.toString();
  }
}
