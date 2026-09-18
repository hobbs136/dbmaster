import '../../database_service.dart';
import '../../database_abstract.dart' show DatabaseConnection;

/// AI 系统提示词构建器接口
///
/// 每种数据库类型应有独立的实现，以隔离不同数据库的：
/// - 性能规则
/// - 语法规范
/// - 响应格式要求
/// - 安全规则
abstract class AiPromptBuilder {
  final DatabaseService dbService;
  final String locale;

  AiPromptBuilder(this.dbService, {this.locale = 'en'});

  bool get isChinese => locale == 'zh' || locale == 'zh_TW';

  /// 构建完整的系统提示词
  Future<String> buildSystemPrompt({
    required DatabaseConnection connection,
    required String? databaseName,
    bool includeSchema = true,
    int maxTables = 30,
  });

  /// 响应格式说明（不同数据库类型可以有不同的格式要求）
  String buildResponseFormatInstructions();

  /// 安全规则
  String buildSafetyRules();

  /// 数据库特定的语法规范
  String buildDatabaseSpecificGuidelines();

  /// 性能规则
  String buildPerformanceRules();

  /// 标识符引号字符
  String get quoteChar;
}
