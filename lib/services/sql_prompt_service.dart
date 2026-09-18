import 'database_abstract.dart';
import 'database_service.dart';
import 'ai/ai_service_localizations.dart';

/// SQL提示词服务 - 定位为谨慎的数据库顾问
///
/// 职责：
/// - 根据数据库类型生成对应的可执行语句
/// - 包含性能规则、安全规则、上下文感知
/// - 要求AI按特定格式返回，便于提取和一键发送
///
/// @Deprecated: 已被按数据库类型隔离的 AiPromptBuilder 和 AiResponseParser 体系取代。
/// 请使用 AiPromptFactory 和 AiParserFactory 创建对应数据库类型的实例。
@Deprecated('Use AiPromptFactory and AiParserFactory instead')
class SqlPromptService {
  final DatabaseService _dbService;
  final String locale;

  SqlPromptService(this._dbService, {this.locale = 'en'});

  bool get _isChinese => locale == 'zh' || locale == 'zh_TW';

  /// 构建系统提示词
  Future<String> buildSystemPrompt({
    required DatabaseConnection connection,
    required String? databaseName,
    bool includeSchema = true,
    int maxTables = 30,
  }) async {
    final l10n = AiServiceLocalizations(locale);
    final buffer = StringBuffer();

    // 角色定义
    buffer.writeln(l10n.sqlPromptRoleTitle);
    buffer.writeln(l10n.sqlPromptRoleIdentity);
    buffer.writeln(l10n.sqlPromptRoleWorkflow);
    buffer.writeln(l10n.sqlPromptRoleStep1);
    if (connection.type.isSqlLike) {
      buffer.writeln(l10n.sqlPromptRoleStep2);
    } else if (connection.type == DatabaseType.redis) {
      buffer.writeln(
        _isChinese
            ? '2. 生成Redis命令供用户审阅'
            : '2. Generate Redis commands for user review',
      );
    } else if (connection.type == DatabaseType.mongodb) {
      buffer.writeln(
        _isChinese
            ? '2. 生成MongoDB查询供用户审阅'
            : '2. Generate MongoDB queries for user review',
      );
    }
    buffer.writeln(l10n.sqlPromptRoleStep3);
    buffer.writeln(l10n.sqlPromptRoleStep4);
    buffer.writeln();

    // 安全规则
    buffer.writeln(l10n.sqlPromptSafetyRulesTitle);
    buffer.writeln(l10n.sqlPromptSafetyRule1);
    buffer.writeln(l10n.sqlPromptSafetyRule2Prefix);
    buffer.writeln(l10n.sqlPromptSafetyRule2a);
    buffer.writeln(l10n.sqlPromptSafetyRule2b);
    buffer.writeln(l10n.sqlPromptSafetyRule2c);
    buffer.writeln(l10n.sqlPromptSafetyRule3);
    if (connection.type.isSqlLike) {
      buffer.writeln(l10n.sqlPromptSafetyRule4);
    } else {
      buffer.writeln(
        _isChinese
            ? '4. 始终优先只读操作'
            : '4. Always prioritize read-only operations',
      );
    }
    buffer.writeln();

    // 上下文信息
    buffer.writeln(l10n.sqlPromptContextTitle);
    buffer.writeln(
      '- ${l10n.sqlPromptContextConnection}: ${connection.type.displayName} @ ${connection.host}:${connection.port}',
    );
    buffer.writeln('- ${l10n.sqlPromptContextInstance}: ${connection.name}');
    if (databaseName != null) {
      buffer.writeln('- ${l10n.sqlPromptContextDatabase}: $databaseName');
    }
    buffer.writeln();

    // Schema信息
    if (includeSchema && databaseName != null) {
      // 临时切换到用户选择的数据库获取schema
      final originalDb = connection.database;
      var switched = false;
      if (originalDb != databaseName) {
        try {
          await _dbService.useDatabase(databaseName);
          switched = true;
        } catch (e) {
          // 切换失败，继续使用当前数据库
        }
      }

      try {
        final schemaInfo = await _getCompactSchema(maxTables);
        if (schemaInfo.isNotEmpty) {
          buffer.writeln(l10n.sqlPromptSchemaTitle);
          buffer.writeln(schemaInfo);
          buffer.writeln();
        }
      } finally {
        // 恢复原始数据库
        if (switched && originalDb != null) {
          try {
            await _dbService.useDatabase(originalDb);
          } catch (_) {
            // 忽略恢复失败
          }
        }
      }
    }

    // 性能规则
    buffer.writeln(_getPerformanceRules(connection.type));
    buffer.writeln();

    // AI Query Optimizer 工具说明
    buffer.writeln('## Query Performance Analysis');
    buffer.writeln('When users ask about query performance or optimization:');
    buffer.writeln('1. First use `explain_query` to get raw execution plan');
    buffer.writeln(
      '2. Then use `analyze_query_performance` to get detailed analysis with:',
    );
    buffer.writeln(
      '   - Bottleneck identification (full table scans, missing indexes, etc.)',
    );
    buffer.writeln('   - Index recommendations with CREATE INDEX statements');
    buffer.writeln('   - Query rewrite suggestions');
    buffer.writeln('3. Present findings in a clear, actionable format');
    buffer.writeln(
      '4. For index recommendations, emphasize that CREATE INDEX requires user confirmation',
    );
    buffer.writeln(
      '5. Warn users about running optimizations on production databases',
    );
    buffer.writeln();

    // Schema Impact Analysis 工具说明
    buffer.writeln('## Schema Impact Analysis (DDL Safety)');
    buffer.writeln(
      'CRITICAL: Before generating or executing ANY DDL statement (CREATE, ALTER, DROP, TRUNCATE, RENAME):',
    );
    buffer.writeln(
      '1. ALWAYS use `analyze_schema_impact` first to assess the impact',
    );
    buffer.writeln(
      '2. Present the risk level and affected objects to the user',
    );
    buffer.writeln('3. If the risk level is HIGH or CRITICAL:');
    buffer.writeln('   - Show the warnings and recommendations');
    buffer.writeln('   - Display the rollback script');
    buffer.writeln(
      '   - EXPLICITLY ask for user confirmation before proceeding',
    );
    buffer.writeln(
      '4. Never execute DDL without user confirmation when risk is high',
    );
    buffer.writeln('5. For DROP operations, always warn about data loss');
    buffer.writeln();

    // 数据库特定语法规范
    buffer.writeln(_getDatabaseSpecificGuidelines(connection.type));
    buffer.writeln();

    // 输出格式
    buffer.writeln(l10n.sqlPromptResponseFormatTitle);
    buffer.writeln(l10n.sqlPromptResponseAnalysis);
    if (connection.type.isSqlLike) {
      buffer.writeln(l10n.sqlPromptResponseQuery);
    } else if (connection.type == DatabaseType.redis) {
      buffer.writeln(
        _isChinese
            ? '2. **Query**: Redis命令，必须用 <sql> 和 </sql> 标签包裹'
            : '2. **Query**: Redis commands must be wrapped in <sql> and </sql> tags',
      );
    } else if (connection.type == DatabaseType.mongodb) {
      buffer.writeln(
        _isChinese
            ? '2. **Query**: MongoDB查询，必须用 <sql> 和 </sql> 标签包裹'
            : '2. **Query**: MongoDB queries must be wrapped in <sql> and </sql> tags',
      );
    }
    buffer.writeln(l10n.sqlPromptResponseExecutionPlan);
    buffer.writeln(l10n.sqlPromptResponseWarning);
    buffer.writeln();

    // SQL标签格式要求
    if (connection.type.isSqlLike) {
      buffer.writeln(l10n.sqlPromptSqlTagTitle);
      buffer.writeln(l10n.sqlPromptSqlTagRule1);
    } else if (connection.type == DatabaseType.redis) {
      buffer.writeln(
        _isChinese
            ? '## Redis命令格式（必须遵守）'
            : '## Redis Command Format (MUST follow)',
      );
      buffer.writeln(
        _isChinese
            ? '- 【强制】所有可执行Redis命令必须用 <sql> 和 </sql> 标签包裹，否则无法被提取执行'
            : '- [MANDATORY] All executable Redis commands must be wrapped in <sql> and </sql> tags, otherwise they cannot be extracted for execution',
      );
    } else if (connection.type == DatabaseType.mongodb) {
      buffer.writeln(
        _isChinese
            ? '## MongoDB查询格式（必须遵守）'
            : '## MongoDB Query Format (MUST follow)',
      );
      buffer.writeln(
        _isChinese
            ? '- 【强制】所有可执行MongoDB查询必须用 <sql> 和 </sql> 标签包裹，否则无法被提取执行'
            : '- [MANDATORY] All executable MongoDB queries must be wrapped in <sql> and </sql> tags, otherwise they cannot be extracted for execution',
      );
    }
    buffer.writeln(l10n.sqlPromptSqlTagRule2);
    buffer.writeln(l10n.sqlPromptSqlTagRule3);
    buffer.writeln(l10n.sqlPromptSqlTagRule4);
    buffer.writeln(l10n.sqlPromptSqlTagRule5);
    buffer.writeln(l10n.sqlPromptSqlTagRule6);
    buffer.writeln(l10n.sqlPromptSqlTagRule7);
    buffer.writeln();

    // 语法规范
    buffer.writeln(l10n.sqlPromptSyntaxTitle);
    buffer.writeln(
      '- ${connection.type.displayName} ${l10n.sqlPromptSyntaxStandard}',
    );
    if (connection.type.isSqlLike) {
      buffer.writeln(
        '- ${l10n.sqlPromptSyntaxQuoteChar}：${_getQuoteChar(connection.type)}',
      );
      buffer.writeln(
        '- ${l10n.sqlPromptSyntaxStringQuote}${_getQuoteChar(connection.type)}',
      );
    }
    buffer.writeln();

    // 示例
    buffer.writeln(l10n.sqlPromptExampleTitle);
    final quote = _getQuoteChar(connection.type);
    buffer.writeln('User: ${l10n.sqlPromptExampleUserQuery}');
    buffer.writeln('You:');
    buffer.writeln('**Analysis**: ${l10n.sqlPromptExampleAnalysis}');
    buffer.writeln('**Query**:');
    buffer.writeln('\u003csql\u003e');
    if (connection.type == DatabaseType.redis) {
      buffer.writeln('SCAN 0 MATCH user:* COUNT 100');
    } else if (connection.type == DatabaseType.mongodb) {
      buffer.writeln(
        r"db.users.find({createdAt: {\$gte: new Date(Date.now() - 7*24*60*60*1000)}}).limit(10)",
      );
    } else {
      buffer.writeln(
        'SELECT ${quote}id$quote, ${quote}email$quote FROM ${quote}users$quote WHERE ${quote}created_at$quote >= DATE_SUB(NOW(), INTERVAL 7 DAY);',
      );
    }
    buffer.writeln('\u003c/sql\u003e');
    buffer.writeln('**Execution Plan**: ${l10n.sqlPromptExampleExecutionPlan}');
    buffer.writeln('**Warning**: ${l10n.sqlPromptExampleWarning}');
    buffer.writeln();

    // 语气
    buffer.writeln(l10n.sqlPromptToneTitle);
    buffer.writeln(l10n.sqlPromptToneRule1);
    buffer.writeln(l10n.sqlPromptToneRule2);
    buffer.writeln(l10n.sqlPromptToneRule3);
    buffer.writeln();

    return buffer.toString();
  }

  /// 解析AI返回内容，提取所有可执行语句（SQL 或 MongoDB 等）
  /// 支持多格式混合提取：
  /// 1. <sql>...</sql> 标签（主要格式）
  /// 2. ```sql ... ``` markdown代码块
  /// 3. 纯SQL语句（以SQL关键字开头）
  /// 4. MongoDB 查询语句（db.collection.method(...)）
  /// 5. 混合格式
  List<String> extractSqlStatements(String response) {
    final results = <String>[];
    final processedRanges = <List<int>>[]; // 记录已处理的位置范围，避免重复

    // 1. 提取 <sql>...</sql> 标签（最高优先级）
    final sqlTagPattern = RegExp(
      r'<sql>\s*([\s\S]*?)\s*</sql>',
      caseSensitive: false,
    );
    for (final match in sqlTagPattern.allMatches(response)) {
      final sql = _cleanSqlContent(match.group(1) ?? '');
      if (sql.isNotEmpty) {
        results.add(sql);
        processedRanges.add([match.start, match.end]);
      }
    }

    // 2. 提取 ```sql ... ``` 以及 ```javascript/js/mongodb``` 代码块
    final markdownPattern = RegExp(
      r'```(?:sql|javascript|js|mongodb)?\s*\n?([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final match in markdownPattern.allMatches(response)) {
      // 检查是否与已处理范围重叠
      if (_isRangeOverlapping(match.start, match.end, processedRanges))
        continue;

      final sql = _cleanSqlContent(match.group(1) ?? '');
      if (sql.isNotEmpty && _isValidSql(sql)) {
        results.add(sql);
        processedRanges.add([match.start, match.end]);
      }
    }

    // 3. 如果前两种格式都未匹配到，尝试提取纯SQL语句或MongoDB查询
    if (results.isEmpty) {
      // SQL 语句
      final plainSqlPattern = RegExp(
        r'(?:^|\n)\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|WITH|EXPLAIN|DESCRIBE|SHOW)\b[\s\S]*?(?=\n\s*(?:SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|WITH|EXPLAIN|DESCRIBE|SHOW)\b|$)',
        caseSensitive: false,
        multiLine: true,
      );
      for (final match in plainSqlPattern.allMatches(response)) {
        final sql = _cleanSqlContent(match.group(0) ?? '');
        if (sql.isNotEmpty && _isValidSql(sql) && !_isDuplicate(sql, results)) {
          results.add(sql);
        }
      }

      // MongoDB 查询语句
      final mongoPattern = RegExp(
        r'(?:^|\n)\s*db\.[a-zA-Z_]\w*\.\w+\s*\(.*?\)(?:\s*\.\w+\s*\(.*?\))*\s*;?',
        caseSensitive: false,
        multiLine: true,
      );
      for (final match in mongoPattern.allMatches(response)) {
        if (_isRangeOverlapping(match.start, match.end, processedRanges))
          continue;
        final mongo = _cleanSqlContent(match.group(0) ?? '');
        if (mongo.isNotEmpty &&
            _isValidMongoCommand(mongo) &&
            !_isDuplicate(mongo, results)) {
          results.add(mongo);
        }
      }
    }

    return results;
  }

  /// 检查位置范围是否与已处理范围重叠
  bool _isRangeOverlapping(int start, int end, List<List<int>> ranges) {
    for (final range in ranges) {
      if (start < range[1] && end > range[0]) {
        return true;
      }
    }
    return false;
  }

  /// 检查SQL是否与已有结果重复（简化比较）
  bool _isDuplicate(String sql, List<String> existing) {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final existingSql in existing) {
      final existingNormalized = existingSql
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalized == existingNormalized) return true;
    }
    return false;
  }

  /// 清理SQL内容中的非SQL文字
  String _cleanSqlContent(String sql) {
    // 如果包含明显的markdown代码块标记，去掉它
    sql = sql.replaceAll(RegExp(r'^\s*```\w*\s*', multiLine: true), '');
    sql = sql.replaceAll(RegExp(r'\s*```\s*$', multiLine: true), '');

    // 去掉行首的中文说明（如"查询："、"示例："等）
    final lines = sql.split('\n');
    final cleanedLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      // 过滤掉纯中文说明行（不含SQL关键字）
      if (RegExp(r'^[\u4e00-\u9fa5\s：:]+$').hasMatch(trimmed)) return false;
      // 过滤掉纯注释行（-- 或 # 开头）
      if (trimmed.startsWith('--') || trimmed.startsWith('#')) return false;
      return true;
    }).toList();

    var result = cleanedLines.join('\n').trim();

    // 去除末尾的分号（如果有），避免执行时多一个分号
    if (result.endsWith(';')) {
      result = result.substring(0, result.length - 1).trim();
    }

    return result;
  }

  /// 判断是否为有效的SQL语句
  bool _isValidSql(String sql) {
    // 检查是否包含SQL关键字或数据库命令
    // MongoDB 查询
    if (_isValidMongoCommand(sql)) return true;
    final basicKeywords = RegExp(
      r'\b(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|EXPLAIN|SHOW|DESCRIBE|USE|GRANT|REVOKE|CALL|EXEC|WITH|SET|BEGIN|COMMIT|ROLLBACK|ANALYZE|OPTIMIZE|CHECK|REPAIR|COPY|MERGE|UPSERT|REPLACE|VALUES|FROM|WHERE|JOIN|GROUP|ORDER|LIMIT|HAVING|UNION|CASE|WHEN|THEN|ELSE|END|IF|FOR|CURSOR|FETCH|OPEN|CLOSE|DECLARE|CONSTRAINT|PRIMARY|FOREIGN|KEY|INDEX|UNIQUE|NOT|NULL|AUTO_INCREMENT|IDENTITY|REFERENCES|CASCADE|ON|AS|BY|ASC|DESC|DISTINCT|AND|OR|IN|EXISTS|BETWEEN|LIKE|IS|TRUE|FALSE|NOW|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|DATE|TIME|TIMESTAMP|INTERVAL|COUNT|SUM|AVG|MAX|MIN|LENGTH|SUBSTRING|CONCAT|UPPER|LOWER|TRIM|ROUND|ABS|MOD|POWER|SQRT|LOG|RAND|UUID|MD5|SHA1|COALESCE|NULLIF|IFNULL|GREATEST|LEAST|DATABASE|USER|VERSION|SCHEMA|FOUND_ROWS|ROW_COUNT|LAST_INSERT_ID|CONNECTION_ID|CHARSET|COLLATION|FORMAT|GET_LOCK|RELEASE_LOCK|SLEEP|BENCHMARK|ST_|INET_|JSON_|JSONB_|TO_|PG_|ARRAY_|GENERATE_|WIDTH_BUCKET|ACOS|ASIN|ATAN|ATN2|CEILING|COS|COT|DEGREES|EXP|FLOOR|LN|PI|RADIANS|SIGN|SIN|TAN|Cbrt|Ceil|Factorial|GCD|LCM|Random|SetSeed|ACOSD|ASIND|ATAND|ATAN2D|COSD|COTD|SIND|TAND|BIT_AND|BIT_OR|BIT_XOR|BOOL_AND|BOOL_OR|EVERY|CORR|COVAR_POP|COVAR_SAMP|REGR_AVGX|REGR_AVGY|REGR_COUNT|REGR_INTERCEPT|REGR_R2|REGR_SLOPE|REGR_SXX|REGR_SXY|REGR_SYY|STDDEV|STDDEV_POP|STDDEV_SAMP|VARIANCE|VAR_POP|VAR_SAMP|MODE|PERCENTILE_CONT|PERCENTILE_DISC|RANK|DENSE_RANK|PERCENT_RANK|CUME_DIST|NTILE|LAG|LEAD|FIRST_VALUE|LAST_VALUE|NTH_VALUE|ROW_NUMBER|CUBE|ROLLUP|GROUPING|GROUPING_ID|CAST|CONVERT|TRY_CAST|TRY_CONVERT|PARSE|TRY_PARSE|COLLATE|COALESCE|NULLIF|ISNULL|CHECKSUM|COMPRESS|DECOMPRESS|FORMATMESSAGE|GET_FILESTREAM_TRANSACTION_CONTEXT|PATINDEX|QUOTENAME|REPLICATE|REVERSE|STR|STRING_ESCAPE|STRING_SPLIT|STUFF|UNICODE|UNISTR|CONCAT|CONCAT_WS|FORMAT|LEFT|RIGHT|LEN|DATALENGTH|CHARINDEX|REPLACE|SUBSTRING|LOWER|UPPER|LTRIM|RTRIM|TRIM|SPACE|REPLICATE|REVERSE|STRING_AGG|TRANSLATE|ASCII|CHAR|CHARINDEX|DIFFERENCE|NCHAR|PATINDEX|SOUNDEX|ABS|ACOS|ASIN|ATAN|ATN2|CEILING|COS|COT|DEGREES|EXP|FLOOR|LOG|LOG10|PI|POWER|RADIANS|RAND|ROUND|SIGN|SIN|SQRT|SQUARE|TAN|TRY_CAST|TRY_CONVERT|AVG|COUNT|COUNT_BIG|GROUPING|GROUPING_ID|MAX|MIN|SUM|STDEV|STDEVP|VAR|VARP|CHECK|DEFAULT|RULE|UNIQUE|CLUSTERED|NONCLUSTERED|COLUMN|CONSTRAINT|CURSOR|DATABASE|INDEX|TABLE|VIEW|PROC|PROCEDURE|TRIGGER|SCHEMA|LOGIN|USER|ROLE|ASSEMBLY|CERTIFICATE|SYMMETRIC|ASYMMETRIC|CONTRACT|ENDPOINT|EVENT|FUNCTION|MESSAGE|REMOTE|ROUTE|QUEUE|SERVICE|SYNONYM|TYPE|XML|FULLTEXT|AGGREGATE|PARTITION|RANGE|SCHEME|FILE|FILEGROUP|PATH|SEARCH|PROPERTY|LIST|STATISTICS|SECURITY|AUDIT|CREDENTIAL|CRYPTOGRAPHIC|MASTER|KEY|BACKUP|RESTORE|CHECKPOINT|DBCC|KILL|PRINT|RAISERROR|READTEXT|WRITETEXT|UPDATETEXT|BULK|INSERT|OPENROWSET|OPENDATASOURCE|OPENQUERY|CONTAINSTABLE|FREETEXTTABLE|SEMANTICKEYPHRASETABLE|SEMANTICSIMILARITYDETAILSTABLE|SEMANTICSIMILARITYTABLE|FILETABLE|FULLTEXT|FREETEXT|CONTAINS|NEAR|FORMSOF|INFLECTIONAL|THESAURUS|ISABOUT|WEIGHTED|AND NOT|OR NOT|PROXIMITY|GENERATION|REVOKE|DENY|EXECUTE|REFERENCES|CONTROL|TAKE|OWNERSHIP|VIEW|DEFINITION|ALTER|IMPERSONATE|CREATE|ANY|ASSEMBLY|ASYMMETRIC|CERTIFICATE|CONTRACT|DATABASE|DDL|DEFAULT|ENDPOINT|FULLTEXT|FUNCTION|MESSAGE|PROCEDURE|QUEUE|REMOTE|ROLE|ROUTE|RULE|SCHEMA|SERVICE|SYMMETRIC|SYNONYM|TABLE|TYPE|VIEW|XML|ALL|ALTER|ANY|AS|ASC|AUTHORIZATION|BACKUP|BEGIN|BREAK|BROWSE|BULK|BY|CASCADE|CASE|CHECK|CHECKPOINT|CLOSE|CLUSTERED|COALESCE|COLLATE|COLUMN|COMMIT|COMPUTE|CONNECT|CONSTRAINT|CONTAINS|CONTAINSTABLE|CONTINUE|CONVERT|CREATE|CROSS|CURRENT|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|CURSOR|DATABASE|DBCC|DEALLOCATE|DECLARE|DEFAULT|DELETE|DENY|DESC|DISK|DISTINCT|DISTRIBUTED|DOUBLE|DROP|DUMP|ELSE|END|ERRLVL|ESCAPE|EXCEPT|EXEC|EXECUTE|EXISTS|EXIT|EXTERNAL|FETCH|FILE|FILLFACTOR|FOR|FOREIGN|FREETEXT|FREETEXTTABLE|FROM|FULL|FUNCTION|GOTO|GRANT|GROUP|HAVING|HOLDLOCK|IDENTITY|IDENTITYCOL|IDENTITY_INSERT|IF|IN|INDEX|INNER|INSERT|INTERSECT|INTO|IS|JOIN|KEY|KILL|LEFT|LIKE|LINENO|LOAD|MERGE|NATIONAL|NOCHECK|NONCLUSTERED|NOT|NULL|NULLIF|OF|OFF|OFFSETS|ON|OPEN|OPENDATASOURCE|OPENQUERY|OPENROWSET|OPENXML|OPTION|OR|ORDER|OUTER|OVER|PERCENT|PLAN|PRECISION|PRIMARY|PRINT|PROC|PROCEDURE|PUBLIC|RAISERROR|READ|READTEXT|RECONFIGURE|REFERENCES|REPLICATION|RESTORE|RESTRICT|RETURN|REVERT|REVOKE|RIGHT|ROLLBACK|ROWCOUNT|ROWGUIDCOL|RULE|SAVE|SCHEMA|SECURITYAUDIT|SELECT|SEMANTICKEYPHRASETABLE|SEMANTICSIMILARITYDETAILSTABLE|SEMANTICSIMILARITYTABLE|SESSION_USER|SET|SETUSER|SHUTDOWN|SOME|STATISTICS|SYSTEM_USER|TABLE|TABLESAMPLE|TEXTSIZE|THEN|TO|TOP|TRAN|TRANSACTION|TRIGGER|TRUNCATE|TRY_CONVERT|TSEQUAL|UNION|UNIQUE|UNPIVOT|UPDATE|UPDATETEXT|USE|USER|VALUES|VARYING|VIEW|WAITFOR|WHEN|WHERE|WHILE|WITH|WITHIN|WRITETEXT)\b',
      caseSensitive: false,
    );
    return basicKeywords.hasMatch(sql);
  }

  /// 判断是否为有效的 MongoDB 查询语句
  bool _isValidMongoCommand(String sql) {
    final trimmed = sql.trim();
    // 以 db.collection.method(...) 格式开头
    if (!trimmed.startsWith('db.')) return false;
    // 包含常见的 MongoDB 方法调用
    final mongoMethods = RegExp(
      r'\b(find|findOne|aggregate|insertOne|insertMany|updateOne|updateMany|deleteOne|deleteMany|countDocuments|estimatedDocumentCount|distinct|replaceOne|findOneAndUpdate|findOneAndReplace|findOneAndDelete|bulkWrite|createIndex|dropIndex|dropIndexes|listIndexes|renameCollection|drop)\s*\(',
      caseSensitive: false,
    );
    return mongoMethods.hasMatch(trimmed);
  }
  // 私有方法

  /// Escape potentially dangerous characters to prevent prompt injection.
  static String _escapeForPrompt(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  Future<String> _getCompactSchema(int maxTables) async {
    try {
      final buffer = StringBuffer();
      final tables = await _dbService.getTables();

      final limitedTables = tables.take(maxTables).toList();

      for (final tableName in limitedTables) {
        final columns = await _dbService.getTableColumns(tableName);
        final columnDefs = columns
            .map((col) {
              final pk = col.isPrimaryKey ? ' [PK]' : '';
              final nullable = col.isNullable ? '' : ' NOT NULL';
              return '${_escapeForPrompt(col.name)}: ${_escapeForPrompt(col.type)}$nullable$pk';
            })
            .join(', ');
        buffer.writeln('- ${_escapeForPrompt(tableName)}: $columnDefs');
      }

      if (tables.length > maxTables) {
        final l10n = AiServiceLocalizations(locale);
        buffer.writeln(
          '... ${tables.length - maxTables} ${l10n.sqlPromptSchemaRemainingTables} ${l10n.sqlPromptSchemaTablesSuffix}',
        );
      }

      return buffer.toString();
    } catch (e) {
      return '';
    }
  }

  String _getQuoteChar(DatabaseType type) {
    switch (type) {
            case DatabaseType.mysql:
            case DatabaseType.clickhouse:
      case DatabaseType.doris:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return '`';
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
        return '"';
      case DatabaseType.sqlserver:
        return '"';
      case DatabaseType.mongodb:
      case DatabaseType.redis:
        return '';
      case DatabaseType.tdengine:
        return '`';
    }
  }

  String _getPerformanceRules(DatabaseType type) {
    final rules = <String>[];

    rules.add('# Performance Rules');

    final l10n = AiServiceLocalizations(locale);
    rules.add(l10n.sqlPromptResponseExecutionPlan);

    switch (type) {
            case DatabaseType.mysql:
            case DatabaseType.clickhouse:
      // T22-T25 四成员暂并 MySQL 规则组（方言近似，随反馈滚动细化）。
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        rules.add('## MySQL / InnoDB Critical Rules');
        rules.add('- InnoDB表无条件COUNT(*)会触发全表扫描，必须避免');
        rules.add('  替代方案：');
        rules.add('  1. 使用COUNT(*)带WHERE条件');
        rules.add('  2. 维护计数表（trigger更新）');
        rules.add('  3. 使用SHOW TABLE STATUS（近似值）');
        rules.add('- 避免SELECT *，明确列出所需字段');
        rules.add('- 大表深翻页（LIMIT 1000000, 10）必须改用延迟关联或游标');
        rules.add('- UPDATE/DELETE必须有WHERE条件且使用索引');
        rules.add('- 批量插入使用INSERT ... VALUES (), ()语法');
        rules.add('- JOIN操作确保关联字段有索引');
        rules.add('- 避免在索引列上使用函数（如DATE(created_at)）');
        rules.add('- 大表ALTER操作会锁表，建议使用pt-online-schema-change');

      case DatabaseType.postgresql:
        rules.add('## PostgreSQL Critical Rules');
        rules.add('- 大表COUNT(*)仍较慢，考虑使用pg_class近似值');
        rules.add('- 避免SELECT *，明确列出所需字段');
        rules.add('- 善用覆盖索引（Index-Only Scan）');
        rules.add('- 大表分页使用KEYSET分页（WHERE id > last_id）');
        rules.add('- CTE递归查询必须设置max_execution_time');
        rules.add('- 避免在WHERE中使用函数（无法使用索引）');
        rules.add('- VACUUM ANALYZE后查询统计信息才准确');
        rules.add('- 大表ALTER使用CONCURRENTLY避免锁表');

      case DatabaseType.sqlite:
        rules.add('## SQLite Critical Rules');
        rules.add('- 使用正确的索引，特别是 WHERE、JOIN、ORDER BY 列');
        rules.add('- 避免 SELECT *，明确列出所需字段');
        rules.add('- 大表分页使用 LIMIT/OFFSET，但深分页性能会下降');
        rules.add('- 批量插入使用事务包裹（BEGIN...COMMIT）');
        rules.add('- 使用 EXPLAIN QUERY PLAN 分析查询计划');
        rules.add('- 避免在索引列上使用函数或类型转换');
        rules.add('- 定期执行 VACUUM 优化数据库文件大小');

      case DatabaseType.doris:
        rules.add('## Apache Doris Critical Rules');
        rules.add('- COUNT(*)性能较好，但大表仍要注意');
        rules.add('- 避免SELECT *，明确列出所需字段');
        rules.add('- 利用Rollup和物化视图加速查询');
        rules.add('- 分区键选择查询过滤最频繁的列');
        rules.add('- Bitmap类型用于高效去重计数');
        rules.add('- 避免高频小批量导入，建议攒批后导入');
        rules.add('- JOIN操作确保关联字段有索引');

      case DatabaseType.mongodb:
        rules.add('## MongoDB Critical Rules');
        rules.add('- count()在大集合上较慢，考虑使用estimatedDocumentCount()');
        rules.add('- 避免返回大文档，使用projection限制字段');
        rules.add('- 大数据集分页使用范围查询（skip/limit性能差）');
        rules.add('- 聚合管道善用索引，确保\$match在最前面');
        rules.add('- 避免文档嵌套深度超过3层');
        rules.add('- 数组字段避免过大（小于1000元素）');

      case DatabaseType.redis:
        rules.add('## Redis Critical Rules');
        rules.add('- 关注命令时间复杂度，避免O(N)操作在大数据量时执行');
        rules.add('- KEYS命令绝对禁止在大数据量时使用，必须用SCAN');
        rules.add('- 使用Pipeline批量执行命令减少RTT');
        rules.add('- 大对象使用Hash分片（如超过512个字段）');
        rules.add('- 热Key使用本地缓存或读写分离');
        rules.add('- 过期策略：合理设置TTL，避免同时过期');

      case DatabaseType.tdengine:
        rules.add('## TDengine Critical Rules');
        rules.add('- 区分超级表（STable）和普通表');
        rules.add('- 子表按设备或实体创建，标签用于分组过滤');
        rules.add('- 时间戳是主键，必须存在');
        rules.add('- 利用LAST/LAST_ROW函数获取最新数据');
        rules.add('- 数据订阅使用topic加consumer group');
        rules.add('- 注意数据类型选择，NCHAR存储变长字符串');

      case DatabaseType.sqlserver:
        rules.add('## SQL Server Critical Rules');
        rules.add('- 避免SELECT *，明确列出所需字段');
        rules.add('- 大表分页使用OFFSET/FETCH而非TOP');
        rules.add('- 善用覆盖索引，减少Key Lookup');
        rules.add('- 避免在WHERE中使用函数（导致索引失效）');
        rules.add('- 批量插入使用BULK INSERT或表值参数');
        rules.add('- 使用TRY...CATCH处理事务错误');
        rules.add('- 定期更新统计信息（UPDATE STATISTICS）');
    }

    return rules.join('\n');
  }

  String _getDatabaseSpecificGuidelines(DatabaseType type) {
    final guidelines = <String>[];

    switch (type) {
            case DatabaseType.mysql:
            case DatabaseType.clickhouse:
      // T22-T25 四成员暂并 MySQL 指南组（方言近似，随反馈滚动细化）。
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        guidelines.add('# MySQL Guidelines');
        guidelines.add('- 使用InnoDB引擎，字符集utf8mb4');
        guidelines.add('- 善用EXPLAIN分析查询，关注type、key、rows字段');
        guidelines.add('- 优先覆盖索引（Covering Index），减少回表');
        guidelines.add('- 批量插入使用INSERT ... VALUES (), ()语法');
        guidelines.add('- JSON字段使用JSON函数操作（MySQL 5.7+）');
        guidelines.add('- 时间字段使用DATETIME(3)或TIMESTAMP');

      case DatabaseType.postgresql:
        guidelines.add('# PostgreSQL Guidelines');
        guidelines.add('- 善用JSONB操作符（箭头、双箭头、包含操作符）');
        guidelines.add('- 使用CTE（WITH子句）简化复杂查询');
        guidelines.add('- 窗口函数（ROW_NUMBER, LAG, LEAD）替代子查询');
        guidelines.add('- 利用GIN/GiST索引加速JSONB和全文搜索');
        guidelines.add('- 使用pg_stat_statements分析慢查询');
        guidelines.add('- 分区表使用声明式分区（Declarative Partitioning）');
        guidelines.add('- 数组类型使用ANY操作符：WHERE id = ANY(array)');

      case DatabaseType.sqlite:
        guidelines.add('# SQLite Guidelines');
        guidelines.add('- 类型亲和性：声明类型但实际存储灵活（INTEGER/REAL/TEXT/BLOB/NULL）');
        guidelines.add('- 整数主键使用 ROWID 别名，自动自增');
        guidelines.add('- 外键约束默认关闭，需 PRAGMA foreign_keys = ON 启用');
        guidelines.add('- 使用事务包裹批量操作（BEGIN IMMEDIATE...COMMIT）');
        guidelines.add('- JSON1 扩展支持 JSON 操作（json_extract, json_array 等）');
        guidelines.add('- 全文搜索使用 FTS5 虚拟表');

      case DatabaseType.doris:
        guidelines.add('# Apache Doris Guidelines');
        guidelines.add('- 选择合适的数据模型：明细（DUPLICATE）、聚合（AGGREGATE）、更新（UNIQUE）');
        guidelines.add('- 利用Rollup和物化视图加速查询');
        guidelines.add('- Bitmap类型用于高效去重计数');
        guidelines.add('- 分区键选择查询过滤最频繁的列');
        guidelines.add('- 数据导入使用Stream Load或Broker Load');

      case DatabaseType.mongodb:
        guidelines.add('# MongoDB Guidelines');
        guidelines.add('- 查询使用find()或aggregate()管道');
        guidelines.add('- 索引使用createIndex()，关注复合索引前缀');
        guidelines.add('- 聚合管道善用match、group、lookup阶段');
        guidelines.add('- 大数据集使用分页：skip/limit或范围查询');
        guidelines.add('- 文档嵌套深度不超过3层');
        guidelines.add('- 数组字段避免过大（小于1000元素）');

      case DatabaseType.redis:
        guidelines.add('# Redis Guidelines');
        guidelines.add('- 关注命令时间复杂度，避免O(N)操作在大数据量时执行');
        guidelines.add('- 使用Pipeline批量执行命令减少RTT');
        guidelines.add('- 大对象使用Hash分片（如超过512个字段）');
        guidelines.add('- 热Key使用本地缓存或读写分离');
        guidelines.add('- 过期策略：合理设置TTL，避免同时过期');
        guidelines.add('- 使用SCAN替代KEYS遍历大数据集');

      case DatabaseType.tdengine:
        guidelines.add('# TDengine Guidelines');
        guidelines.add('- 区分超级表（STable）和普通表，超级表定义schema和标签');
        guidelines.add('- 子表按设备或实体创建，标签用于分组过滤');
        guidelines.add('- 时间戳是主键，必须存在');
        guidelines.add('- 利用LAST/LAST_ROW函数获取最新数据');
        guidelines.add('- 数据订阅使用topic加consumer group');
        guidelines.add('- 注意数据类型的选择，NCHAR存储变长字符串');

      case DatabaseType.sqlserver:
        guidelines.add('# SQL Server Guidelines');
        guidelines.add('- 使用方括号[]引用标识符，避免关键字冲突');
        guidelines.add('- T-SQL支持CTE、窗口函数、PIVOT/UNPIVOT');
        guidelines.add('- 善用SQL Server Agent进行定时任务');
        guidelines.add('- 使用TRY...CATCH进行错误处理');
        guidelines.add('- 分区表用于大表管理（SWITCH分区）');
        guidelines.add('- 使用OUTPUT子句获取DML操作影响的数据');
    }

    return guidelines.join('\n');
  }
}
