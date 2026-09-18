import 'ai_prompt_builder.dart';
import '../../database_abstract.dart' show DatabaseConnection;
import '../ai_service_localizations.dart';

/// PromptBuilder 共享基类
///
/// 提供所有数据库类型通用的逻辑：
/// - Schema 信息获取
/// - 字符转义（防止 prompt injection）
/// - 本地化辅助
/// - 系统提示词组装流程
abstract class BasePromptBuilder extends AiPromptBuilder {
  BasePromptBuilder(super.dbService, {super.locale});

  AiServiceLocalizations get l10n => AiServiceLocalizations(locale);

  /// Escape potentially dangerous characters to prevent prompt injection.
  static String escapeForPrompt(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// 获取数据库 Schema 的紧凑描述
  Future<String> getCompactSchema({
    required String? databaseName,
    required DatabaseConnection connection,
    int maxTables = 30,
  }) async {
    // 临时切换到用户选择的数据库获取 schema
    final originalDb = connection.database;
    var switched = false;
    if (originalDb != databaseName && databaseName != null) {
      try {
        await dbService.useDatabase(databaseName);
        switched = true;
      } catch (e) {
        // 切换失败，继续使用当前数据库
      }
    }

    try {
      final buffer = StringBuffer();
      final tables = await dbService.getTables();
      final limitedTables = tables.take(maxTables).toList();

      for (final tableName in limitedTables) {
        final columns = await dbService.getTableColumns(tableName);
        final columnDefs = columns
            .map((col) {
              final pk = col.isPrimaryKey ? ' [PK]' : '';
              final nullable = col.isNullable ? '' : ' NOT NULL';
              return '${escapeForPrompt(col.name)}: ${escapeForPrompt(col.type)}$nullable$pk';
            })
            .join(', ');
        buffer.writeln('- ${escapeForPrompt(tableName)}: $columnDefs');
      }

      if (tables.length > maxTables) {
        buffer.writeln(
          '... ${tables.length - maxTables} ${l10n.sqlPromptSchemaRemainingTables} ${l10n.sqlPromptSchemaTablesSuffix}',
        );
      }

      return buffer.toString();
    } catch (e) {
      return '';
    } finally {
      // 恢复原始数据库
      if (switched && originalDb != null) {
        try {
          await dbService.useDatabase(originalDb);
        } catch (_) {
          // 忽略恢复失败
        }
      }
    }
  }

  /// 构建角色定义部分
  String buildRoleSection(DatabaseConnection connection) {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptRoleTitle);
    buffer.writeln(l10n.sqlPromptRoleIdentity);
    buffer.writeln(l10n.sqlPromptRoleWorkflow);
    buffer.writeln(l10n.sqlPromptRoleStep1);
    buffer.writeln(l10n.sqlPromptRoleStep2);
    buffer.writeln(l10n.sqlPromptRoleStep3);
    buffer.writeln(l10n.sqlPromptRoleStep4);
    return buffer.toString();
  }

  /// 构建上下文信息部分
  String buildContextSection(
    DatabaseConnection connection,
    String? databaseName,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptContextTitle);
    buffer.writeln(
      '- ${l10n.sqlPromptContextConnection}: ${connection.type.displayName} @ ${connection.host}:${connection.port}',
    );
    buffer.writeln('- ${l10n.sqlPromptContextInstance}: ${connection.name}');
    if (databaseName != null) {
      buffer.writeln('- ${l10n.sqlPromptContextDatabase}: $databaseName');
    }
    return buffer.toString();
  }

  /// 构建 SQL 标签格式要求
  String buildSqlTagSection() {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptSqlTagTitle);
    buffer.writeln(l10n.sqlPromptSqlTagRule1);
    buffer.writeln(l10n.sqlPromptSqlTagRule2);
    buffer.writeln(l10n.sqlPromptSqlTagRule3);
    buffer.writeln(l10n.sqlPromptSqlTagRule4);
    buffer.writeln(l10n.sqlPromptSqlTagRule5);
    buffer.writeln(l10n.sqlPromptSqlTagRule6);
    buffer.writeln(l10n.sqlPromptSqlTagRule7);
    return buffer.toString();
  }

  /// 构建语法规范部分
  String buildSyntaxSection(DatabaseConnection connection) {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptSyntaxTitle);
    buffer.writeln(
      '- ${connection.type.displayName} ${l10n.sqlPromptSyntaxStandard}',
    );
    if (connection.type.isSqlLike) {
      buffer.writeln('- ${l10n.sqlPromptSyntaxQuoteChar}：$quoteChar');
      buffer.writeln('- ${l10n.sqlPromptSyntaxStringQuote}$quoteChar');
    }
    return buffer.toString();
  }

  /// 构建示例部分
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

  /// 构建语气部分
  String buildToneSection() {
    final buffer = StringBuffer();
    buffer.writeln(l10n.sqlPromptToneTitle);
    buffer.writeln(l10n.sqlPromptToneRule1);
    buffer.writeln(l10n.sqlPromptToneRule2);
    buffer.writeln(l10n.sqlPromptToneRule3);
    return buffer.toString();
  }

  /// 获取示例查询（各数据库类型不同）
  String getExampleQuery(DatabaseConnection connection);

  /// 工具说明部分（默认包含 Query Performance Analysis 和 Schema Impact Analysis）
  String buildToolInstructions() => l10n.sqlPromptToolInstructionsBlock;
}
