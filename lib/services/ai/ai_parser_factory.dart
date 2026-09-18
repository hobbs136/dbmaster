import 'response_parsers/ai_response_parser.dart';
import 'response_parsers/sql_response_parser.dart';
import 'response_parsers/mongodb_response_parser.dart';
import 'response_parsers/redis_response_parser.dart';
import '../../models/database_models.dart';

/// AI ResponseParser 工厂
///
/// 根据数据库类型创建对应的响应解析器实例。
class AiParserFactory {
  static AiResponseParser createParser({
    required DatabaseType type,
    String locale = 'en',
  }) {
    switch (type) {
            case DatabaseType.mysql:
            case DatabaseType.clickhouse:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.doris:
      case DatabaseType.tdengine:
      case DatabaseType.sqlserver:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return SqlResponseParser(locale: locale);
      case DatabaseType.mongodb:
        return MongoDbResponseParser(locale: locale);
      case DatabaseType.redis:
        return RedisResponseParser(locale: locale);
    }
  }
}
