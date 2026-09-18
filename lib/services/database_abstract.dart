import '../models/database_models.dart';
import '../models/sql_script_exception.dart' show SqlScriptExecutionException;

export '../models/database_models.dart' show DatabaseType;

enum CommandRiskLevel { safe, warning, dangerous }

class SecurityCheckResult {
  final bool allowed;
  final CommandRiskLevel riskLevel;
  final String? reason;

  const SecurityCheckResult(this.allowed, this.riskLevel, {this.reason});

  static const ok = SecurityCheckResult(true, CommandRiskLevel.safe);
}

class QueryResult {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int? affectedRows;
  final String? message;
  final int? executionTime;
  final Map<String, String>? columnTypes;

  /// Server-side thread id (MySQL CONNECTION_ID) for S10 txn_query responses.
  /// Used by the client to KILL a long-running statement inside a transaction.
  /// Null for non-txn paths (db_query) where the pool is dropped post-query.
  final int? threadId;
  // 被 (max)→capped CAST 截断的列名集合（列级；真长度 CAST 后不可知，
  // 故只标记「可能被截断」，非 cell 级精确）。非 final：adapter 在 varmax fallback CAST
  // 发射点捕获后赋值；查询路径正常时保持空集。
  Set<String> truncatedColumns = const <String>{};

  QueryResult({
    required this.columns,
    required this.rows,
    this.affectedRows,
    this.message,
    this.executionTime,
    this.columnTypes,
    this.threadId,
  });

  QueryResult.empty()
    : columns = [],
      rows = [],
      affectedRows = 0,
      message = null,
      executionTime = 0,
      columnTypes = null,
      threadId = null;
}

class DatabaseConnection {
  final String id;
  final String name;
  final DatabaseType type;
  final String host;
  final int port;
  final String? username;
  String? password;
  final String? database;
  final bool connected;
  final DateTime? connectedAt;
  final bool readOnly;
  final Map<String, dynamic>? extra;

  DatabaseConnection({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.database,
    this.connected = false,
    this.connectedAt,
    this.readOnly = false,
    this.extra,
  });

  DatabaseConnection copyWith({
    String? id,
    String? name,
    DatabaseType? type,
    String? host,
    int? port,
    String? username,
    String? password,
    String? database,
    bool? connected,
    DateTime? connectedAt,
    bool? readOnly,
    Map<String, dynamic>? extra,
  }) {
    return DatabaseConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      database: database ?? this.database,
      connected: connected ?? this.connected,
      connectedAt: connectedAt ?? this.connectedAt,
      readOnly: readOnly ?? this.readOnly,
      extra: extra ?? this.extra,
    );
  }

  String get connectionString {
    final parts = <String>[type.displayName, host, port.toString()];
    if (database != null) parts.add(database!);
    return parts.join('/');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'database': database,
      'connected': connected,
      'connectedAt': connectedAt?.toIso8601String(),
      'readOnly': readOnly,
      'extra': extra,
    };
  }

  factory DatabaseConnection.fromJson(Map<String, dynamic> json) {
    return DatabaseConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      type: DatabaseType.fromName(json['type'] as String? ?? 'mysql'),
      host: json['host'] as String,
      port: json['port'] as int,
      username: json['username'] as String?,
      password: json['password'] as String?,
      database: json['database'] as String?,
      connected: json['connected'] as bool? ?? false,
      connectedAt: json['connectedAt'] != null
          ? DateTime.parse(json['connectedAt'] as String)
          : null,
      readOnly: json['readOnly'] as bool? ?? false,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  factory DatabaseConnection.fromDbServer(DbServer server) {
    return DatabaseConnection(
      id: server.id,
      name: server.name,
      type: server.type,
      host: server.host,
      port: server.port,
      username: server.username,
      password: server.password,
      database: server.database,
      connected: server.connected,
      readOnly: server.readOnly,
      // Spread server.extra FIRST so DB-specific keys (e.g. MongoDB cluster
      // settings) survive into the adapter; the 4 fixed keys follow and only
      // override on collision (they do not collide with namespaced keys like
      // 'mongo*'). Previously server.extra was dropped, silently losing every
      // extra-based setting before the adapter saw it.
      extra: {
        ...?server.extra,
        'useSSL': server.useSSL,
        'timeout': server.timeoutSeconds,
        'charset': server.charset,
        'timezone': server.timezone,
        // 网关 TLS 透传（Redis/Mongo/TD）：server 侧驱动 TLS 的两键。
        'useTls': server.useTls,
        'tlsInsecure': server.tlsInsecure,
        // server 侧 SSH 隧道 wire 投影（网关类型生效）：与既有本地直连
        // 隧道（database_service 的 SshTunnelManager）互斥——网关模式下
        // 由 adapter 把该对象原样放进 draft/test body 交给 server 建隧道。
        if (server.useSshTunnel &&
            server.sshHost != null &&
            server.sshHost!.isNotEmpty)
          'ssh': {
            'host': server.sshHost,
            'port': server.sshPort ?? 22,
            if (server.sshUsername != null && server.sshUsername!.isNotEmpty)
              'username': server.sshUsername,
            'authMode': (server.sshAuthMode ?? SshAuthMode.password).name,
            if (server.sshAuthMode != SshAuthMode.privateKey &&
                server.sshPassword != null &&
                server.sshPassword!.isNotEmpty)
              'password': server.sshPassword,
            if (server.sshAuthMode == SshAuthMode.privateKey &&
                server.sshPrivateKey != null &&
                server.sshPrivateKey!.isNotEmpty)
              'privateKey': server.sshPrivateKey,
            if (server.sshAuthMode == SshAuthMode.privateKey &&
                server.sshPassphrase != null &&
                server.sshPassphrase!.isNotEmpty)
              'passphrase': server.sshPassphrase,
          },
      },
    );
  }
}

// ============================================================================
// 网关 wire 投影 helper —— 各网关壳 adapter 的 draft/test body 组包共用
// ============================================================================

/// 连接 extra 中的 server 侧 SSH 隧道对象（由 [DatabaseConnection.fromDbServer]
/// 从 DbServer SSH 字段映射而来）。存在即代表 server 需建隧道；不存在返回
/// null（本地直连 / 未启用 SSH 的连接）。
Map<String, dynamic>? gatewaySshWire(DatabaseConnection connection) {
  final ssh = connection.extra?['ssh'];
  return ssh is Map<String, dynamic> ? ssh : null;
}

/// TLS 透传两键（Redis/Mongo/TDengine 网关）：useTls 未开时返回空 map
/// （不下发），开启时固定携带 useTls/tlsInsecure——server 侧按这两键
/// 组 TLS ClientOptions。
Map<String, dynamic> gatewayTlsWire(Map<String, dynamic>? extra) {
  if (extra == null || extra['useTls'] != true) return const {};
  return {'useTls': true, 'tlsInsecure': extra['tlsInsecure'] == true};
}

/// 该类型的执行面是否在 server 侧（网关壳 adapter）：当前除 sqlite
/// （本地文件，永久直连）外的全部类型都是网关壳。网关壳类型不能建
/// 客户端本地 SSH 隧道——host 会被改写为 127.0.0.1，server 会连自己的
/// 回环；SSH 配置改为经 draft 传给 server 建隧道。
bool isServerSideExecutedType(DatabaseType type) => type != DatabaseType.sqlite;

// ============================================================================
// 能力接口（标记性）—— 各适配器通过 implements 声明自身能力
// ============================================================================

/// 支持事务的数据库适配器
abstract interface class TransactionalAdapter {
  Future<void> beginTransaction();
  Future<void> commit();
  Future<void> rollback();
  bool get isInTransaction;
}

/// 支持 SQL 高级 Schema 发现（视图、存储过程、触发器、索引、外键等）
abstract interface class SqlSchemaAdapter {
  Future<List<String>> getViews();
  Future<List<String>> getProcedures();
  Future<List<String>> getFunctions();
  Future<List<String>> getEvents();
  Future<List<DbTrigger>> getTriggers();
  Future<List<String>> getMaterializedViews();
  Future<List<String>> getSequences();
  Future<List<DbIndex>> getTableIndexes(String tableName);
  Future<List<ForeignKey>> getForeignKeys(String tableName);
}

/// 支持 DDL 操作的数据库适配器
abstract interface class DdlAdapter {
  bool get supportsSchemaOperations;
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    Map<String, dynamic>? options,
  });
  Future<bool> dropTable(String tableName);
  Future<bool> renameTable(String oldName, String newName);
  Future<bool> truncateTable(String tableName, {TruncateOptions? options});
  Future<bool> addColumn(String tableName, DbColumn column);
  Future<bool> dropColumn(String tableName, String columnName);
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  );
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  );
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  });
  Future<bool> dropIndex(String tableName, String indexName);
}

/// 支持 SQL 脚本和结构导出的数据库适配器
abstract interface class SqlScriptAdapter {
  Future<String> exportDatabaseStructure(String dbName);

  /// 执行多语句脚本（SQL-aware 分割，逐条执行）。
  ///
  /// 失败时抛 [SqlScriptExecutionException]（定位失败语句 + 已执行条数），
  /// 成功返回 true；不再以 `false` 吞掉失败原因（U08）。
  Future<bool> executeSqlScript(String script);
}

/// 支持字符集和排序规则的数据库适配器
abstract interface class CharsetAdapter {
  Future<List<String>> getCharsets();
  Future<List<Map<String, String>>> getCollations({String? charset});
}

/// 支持查看和终止服务器进程列表的数据库适配器
abstract interface class ProcessListAdapter {
  Future<List<ProcessInfo>> getProcessList();
  Future<bool> killProcess(int processId);
}

/// 支持复制状态监控的数据库适配器（MySQL 主从复制）
abstract interface class ReplicationAdapter {
  Future<ReplicationStatus?> getReplicationStatus();
}

/// 支持 schema 命名空间的数据库适配器（PostgreSQL、SQL Server）
/// 用于侧边栏 schema 优先导航和 search_path 管理
abstract interface class SchemaAwareAdapter {
  Future<List<String>> getSchemas();
  String? getCurrentSchema();
  Future<void> setSearchPath(List<String> schemas);
}

/// 实现：PostgreSQLAdapter、SqlServerAdapter——它们的 getTables/Views/Functions/Procedures
/// 已带可选 {schemaName}，故 implements 无需新增方法。SchemaDiffService 据此走多 schema 路径。
abstract interface class MultiSchemaObjectAdapter {
  Future<List<String>> getTables({String? schemaName});
  Future<List<String>> getViews({String? schemaName});
  Future<List<String>> getFunctions({String? schemaName});
  Future<List<String>> getProcedures({String? schemaName});
}

/// 支持 PostgreSQL 扩展查询的数据库适配器。
/// 实现：PostgreSQLAdapter
abstract interface class ExtensionAdapter {
  /// 返回当前数据库安装的所有扩展。
  Future<List<PgExtension>> getExtensions();

  /// 返回所有 pgvector 向量索引（如果 pgvector 已安装）。
  Future<List<VectorIndex>> getVectorIndexes();
}

/// 支持 JSON/JSONB 列检测的数据库适配器。
/// 实现：PostgreSQLAdapter、MySQLGatewayBaseAdapter（T29 起）、SQLiteAdapter
abstract interface class JsonAdapter {
  /// 返回指定表中包含 JSON 数据的列名列表。
  Future<List<String>> getJsonColumns(String tableName);

  /// 返回指定列是否包含 JSON 数据。
  Future<bool> isJsonColumn(String tableName, String columnName);
}

/// 支持 PRAGMA 查询和修改的数据库适配器（仅 SQLite）。
/// 实现方在 adapter 上 `implements PragmaAdapter`，调用方用 `adapter is PragmaAdapter` 判定。
abstract interface class PragmaAdapter {
  /// 查询所有已知 PRAGMA 的当前值。
  Future<List<PragmaInfo>> getPragmas();

  /// 设置 PRAGMA 值（仅可写项）。返回更新后的 PragmaInfo（含确认的新值）。
  /// 只读模式应抛异常拒绝。
  Future<PragmaInfo> setPragma(String name, String value);
}

/// 支持 ATTACH 跨库的数据库适配器（仅 SQLite）。
///
/// spec 050：SQLite 连接可挂载附加数据库（ATTACH DATABASE），从而支持跨库查询
/// （`alias.table`）。实现方在 adapter 上 `implements AttachAwareAdapter`，
/// 调用方用 `adapter is AttachAwareAdapter` 判定（与 [PragmaAdapter] 模式一致）。
abstract interface class AttachAwareAdapter {
  /// 附加一个数据库文件到当前连接。
  ///
  /// [path] 文件绝对路径（走参数化绑定）；[alias] 附加后的访问名。
  /// alias 是 SQLite 标识符，**不能参数化**（`ATTACH ? AS ?` 第二个占位符
  /// SQLite 不接受），故由调用方在 UI 层经 [SqliteAliasValidator] 校验后再传入。
  /// adapter 层不重复校验，直接执行；失败抛原生 SQLite 错误。
  Future<void> attachDatabase(String path, String alias);

  /// 分离一个已附加的数据库。alias 同样由调用方校验。
  Future<void> detachDatabase(String alias);

  /// 列出当前连接所有数据库（含 main / temp / 已附加 alias）。
  /// 数据源 `PRAGMA database_list`，是附加库状态的唯一真相源。
  Future<List<AttachedDatabaseInfo>> listAttachedDatabases();
}

/// `PRAGMA database_list` 的一行（seq / name / file）。
///
/// [name] 取值：`main`（主库）、`temp`（SQLite 内置临时库，UI 不显示）、
/// `<alias>`（已附加库）。[file] 为文件绝对路径；内存库（如 `:memory:`）时为 null。
class AttachedDatabaseInfo {
  final int seq;
  final String name;
  final String? file;

  const AttachedDatabaseInfo({
    required this.seq,
    required this.name,
    this.file,
  });

  @override
  String toString() =>
      'AttachedDatabaseInfo(seq: $seq, name: $name, file: $file)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachedDatabaseInfo &&
          seq == other.seq &&
          name == other.name &&
          file == other.file;

  @override
  int get hashCode => Object.hash(seq, name, file);
}

// ============================================================================
// DatabaseAdapter —— 保留所有方法签名，但为 NoSQL 不适用的方法提供默认实现
// ============================================================================

abstract class DatabaseAdapter {
  Future<bool> connect(DatabaseConnection connection);
  Future<void> disconnect();
  Future<String?> testConnection(DatabaseConnection connection);
  bool get isConnected;
  DatabaseType get databaseType;
  DatabaseConnection? get currentConnection;

  /// feature 039 D3：刷新连接 readOnly（运行时开关实时生效，避免重连）。
  /// 默认 no-op；缓存 `_currentConnection` 的 adapter 覆盖之。
  void updateReadOnly(bool value) {}

  /// 连接断开时的回调（由 DatabaseService 设置）
  void Function()? get onDisconnect;
  set onDisconnect(void Function()? callback);

  Future<List<String>> getDatabases();
  Future<void> useDatabase(String dbName);

  /// 是否支持 schema 命名空间（PostgreSQL、SQL Server）。
  bool get supportsSchemaNamespace => false;

  /// 该 adapter 是否正处于"切库过程中"（关闭旧物理连接、打开新连接）。
  /// 仅 PostgreSQL 覆盖为 true（PG 无 `USE` 命令，切库须 close+reopen）。
  /// DatabaseService 据此跳过对"被自己主动关闭的连接"触发的连接丢失判定，
  /// 避免 useDatabase 期间的在途查询失败被误判为掉线而级联 disconnect（见 #1 崩溃）。
  bool get isSwitchingDatabase => false;

  /// 获取当前数据库的 schema 列表。
  Future<List<String>> getSchemas({String? database}) async => [];

  /// 设置当前 schema（后续查询将限定在该 schema 下）。
  Future<void> setSchema(String schemaName) async {}

  Future<List<String>> getTables();

  /// NoSQL 数据库默认返回空列表
  Future<List<String>> getViews() async => [];
  Future<List<String>> getProcedures() async => [];
  Future<List<String>> getFunctions() async => [];
  Future<List<String>> getEvents() async => [];
  Future<List<DbTrigger>> getTriggers() async => [];
  Future<List<String>> getMaterializedViews() async => [];
  Future<List<String>> getSequences() async => [];

  Future<List<DbColumn>> getTableColumns(String tableName);

  /// NoSQL 数据库默认返回空列表
  Future<List<DbIndex>> getTableIndexes(String tableName) async => [];
  Future<List<ForeignKey>> getForeignKeys(String tableName) async => [];

  /// 反向外键查询：返回引用 [tableName] 的外键（其他表 → 本表）。
  ///
  /// 用于删除/更新影响分析（找出删主表数据前需先处理的子表）。默认实现
  /// 遍历当前库全部表的正向外键后过滤，通用覆盖所有已实现 [getForeignKeys]
  /// 的库，但代价是 O(表数) 次元数据查询；表数超过
  /// [_maxTablesForReferencingScan] 时放弃扫描返回空列表，防大库 N+1。
  /// MySQL / PostgreSQL 覆写了 information_schema 单查快路径。
  /// 保留自引用（如 tasks.parent_id → tasks.id，删数据需先删子行）。
  Future<List<ForeignKey>> getReferencingForeignKeys(String tableName) async {
    final List<String> tables;
    try {
      tables = await getTables();
    } catch (_) {
      // 表清单都拿不到时无从扫描（该 API 属元数据增强，静默降级为空）
      return [];
    }
    if (tables.length > _maxTablesForReferencingScan) return [];
    final lowered = tableName.toLowerCase();
    final references = <ForeignKey>[];
    for (final table in tables) {
      try {
        final fks = await getForeignKeys(table);
        for (final fk in fks) {
          if (fk.referencedTable.toLowerCase() == lowered) {
            references.add(fk);
          }
        }
      } catch (_) {
        // 单表元数据查询失败不影响其余表
      }
    }
    return references;
  }

  /// 默认反向外键扫描的表数上限（超过视为大库，退化为空结果由快路径覆盖）。
  static const int _maxTablesForReferencingScan = 200;

  Future<DbTable> getTableDetails(String tableName);
  Future<QueryResult> executeQuery(String sql, {String? database});
  Future<QueryResult> getExplainPlan(String sql);

  /// 获取带元信息的表列表（可选实现，默认退化到 getTables()）
  Future<List<DbTableMetadata>> getTablesWithMetadata({
    String? database,
  }) async {
    final tableNames = await getTables();
    return tableNames.map((name) => DbTableMetadata(name: name)).toList();
  }

  /// 获取单表元信息（可选实现，默认返回空元信息）
  Future<DbTableMetadata> getTableMetadata(String tableName) async {
    return DbTableMetadata(name: tableName);
  }

  Future<Map<String, dynamic>?> getServerVersion();
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName);
  Future<bool> createDatabase(
    String dbName, {
    Map<String, dynamic>? options,
  }) async => false;
  Future<bool> dropDatabase(String dbName) async => false;

  /// NoSQL 数据库默认返回 false
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    Map<String, dynamic>? options,
  }) async => false;
  Future<bool> dropTable(String tableName) async => false;
  Future<bool> renameTable(String oldName, String newName) async => false;
  Future<bool> truncateTable(
    String tableName, {
    TruncateOptions? options,
  }) async => false;

  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  });
  Future<int> getTableRowCount(String tableName);

  /// NoSQL 数据库默认返回 false
  Future<bool> addColumn(String tableName, DbColumn column) async => false;
  Future<bool> dropColumn(String tableName, String columnName) async => false;
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) async => false;
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) async => false;
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  }) async => false;
  Future<bool> dropIndex(String tableName, String indexName) async => false;

  /// NoSQL 数据库默认返回空字符串
  Future<String> exportDatabaseStructure(String dbName) async => '';
  Future<bool> executeSqlScript(String script) async => false;

  /// NoSQL 数据库默认返回空列表
  Future<List<String>> getCharsets() async => [];

  /// 生成浏览表数据的默认查询语句
  String getDefaultBrowseQuery(String tableName, {int limit = 100});

  /// NoSQL 数据库默认返回空列表
  Future<List<Map<String, String>>> getCollations({String? charset}) async =>
      [];

  /// Schema操作支持（可选实现，默认识别为支持）
  bool get supportsSchemaOperations => true;

  /// 事务管理（可选实现，默认不支持事务）
  Future<void> beginTransaction() async {}
  Future<void> commit() async {}
  Future<void> rollback() async {}
  bool get isInTransaction => false;

  /// 终止指定进程/连接（默认不支持，MySQL/PG 覆盖）
  Future<bool> killProcess(int processId) async => false;

  /// 获取复制状态（默认不支持，MySQL 覆盖）
  Future<ReplicationStatus?> getReplicationStatus() async => null;

  /// 获取扩展列表（默认不支持，PostgreSQL 覆盖）
  Future<List<PgExtension>> getExtensions() async => [];

  /// 获取向量索引列表（默认不支持，PostgreSQL 覆盖）
  Future<List<VectorIndex>> getVectorIndexes() async => [];

  /// 获取 JSON 列名列表（默认不支持，PG/MySQL/SQLite 覆盖）
  Future<List<String>> getJsonColumns(String tableName) async => [];

  /// 判断列是否为 JSON 类型（默认不支持，PG/MySQL/SQLite 覆盖）
  Future<bool> isJsonColumn(String tableName, String columnName) async => false;

  /// AI Agent extensions
  Future<String> getAiSchemaSummary({
    String? target,
    String? databaseName,
    String locale = 'en',
  });
  Future<AiExecutionResult> executeAiCommand(
    String command, {
    String locale = 'en',
  });
  SecurityCheckResult validateCommand(String command);
}

class AiExecutionResult {
  final bool success;
  final String output;
  final Map<String, dynamic>? structuredData;
  final String? error;

  AiExecutionResult({
    required this.success,
    required this.output,
    this.structuredData,
    this.error,
  });

  factory AiExecutionResult.success(
    String output, {
    Map<String, dynamic>? data,
  }) {
    return AiExecutionResult(
      success: true,
      output: output,
      structuredData: data,
    );
  }

  factory AiExecutionResult.failure(String error, {String? output}) {
    return AiExecutionResult(
      success: false,
      output: output ?? error,
      error: error,
    );
  }
}

/// 为 DatabaseAdapter 提供 onDisconnect 的默认实现
mixin DisconnectAware {
  void Function()? _onDisconnect;

  void Function()? get onDisconnect => _onDisconnect;
  set onDisconnect(void Function()? callback) => _onDisconnect = callback;
}
