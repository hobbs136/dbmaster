import '../database_service.dart';
import 'prompt_builders/ai_prompt_builder.dart';
import 'prompt_builders/mysql_prompt_builder.dart';
import 'prompt_builders/postgresql_prompt_builder.dart';
import 'prompt_builders/sqlite_prompt_builder.dart';
import 'prompt_builders/doris_prompt_builder.dart';
import 'prompt_builders/tdengine_prompt_builder.dart';
import 'prompt_builders/sqlserver_prompt_builder.dart';
import 'prompt_builders/mongodb_prompt_builder.dart';
import 'prompt_builders/redis_prompt_builder.dart';
import '../../models/database_models.dart';

/// AI PromptBuilder 工厂
///
/// 根据数据库类型创建对应的 PromptBuilder 实例。
class AiPromptFactory {
  static final Map<
    DatabaseType,
    AiPromptBuilder Function(DatabaseService, {String locale})
  >
  _builderMap = {
    DatabaseType.mysql: (db, {locale = 'en'}) =>
        MySqlPromptBuilder(db, locale: locale),
    DatabaseType.postgresql: (db, {locale = 'en'}) =>
        PostgreSqlPromptBuilder(db, locale: locale),
    DatabaseType.sqlite: (db, {locale = 'en'}) =>
        SqlitePromptBuilder(db, locale: locale),
    DatabaseType.doris: (db, {locale = 'en'}) =>
        DorisPromptBuilder(db, locale: locale),
    DatabaseType.tdengine: (db, {locale = 'en'}) =>
        TdenginePromptBuilder(db, locale: locale),
    DatabaseType.sqlserver: (db, {locale = 'en'}) =>
        SqlServerPromptBuilder(db, locale: locale),
    DatabaseType.mongodb: (db, {locale = 'en'}) =>
        MongoDbPromptBuilder(db, locale: locale),
    DatabaseType.redis: (db, {locale = 'en'}) =>
        RedisPromptBuilder(db, locale: locale),
  };

  static AiPromptBuilder createBuilder({
    required DatabaseType type,
    required DatabaseService dbService,
    String locale = 'en',
  }) {
    final builder = _builderMap[type];
    if (builder != null) return builder(dbService, locale: locale);
    throw UnsupportedError('Unsupported database type: $type');
  }
}
