/// AI 响应解析器接口
///
/// 负责从 AI 返回的文本中提取可执行语句。
/// 不同数据库类型（SQL / MongoDB / Redis）有不同的语句格式，
/// 因此需要独立的解析逻辑。
abstract class AiResponseParser {
  final String locale;

  AiResponseParser({this.locale = 'en'});

  /// 从 AI 响应中提取所有可执行语句
  ///
  /// 支持的格式（按优先级）：
  /// 1. `\u003csql\u003e...\u003c/sql\u003e` 标签（主要格式）
  /// 2. Markdown 代码块
  /// 3. 纯语句（数据库特定语法）
  List<String> extractExecutableStatements(String response);

  /// 判断字符串是否为有效的可执行语句
  bool isValidCommand(String command);
}
