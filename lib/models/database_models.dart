import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/design_system.dart';
import 'ai_message_type.dart';

enum ConnectionEnvironment {
  production,
  testing,
  development;

  String get displayName {
    switch (this) {
      case ConnectionEnvironment.production:
        return 'Production';
      case ConnectionEnvironment.testing:
        return 'Testing';
      case ConnectionEnvironment.development:
        return 'Development';
    }
  }

  Color get badgeColor {
    switch (this) {
      case ConnectionEnvironment.production:
        return const Color(0xFFEF4444); // red-500
      case ConnectionEnvironment.testing:
        return const Color(0xFFF59E0B); // amber-500
      case ConnectionEnvironment.development:
        return const Color(0xFF3B82F6); // blue-500
    }
  }
}

enum DatabaseType {
  mysql,
  postgresql,
  sqlite,
  doris,
  redis,
  mongodb,
  tdengine,
  sqlserver,
  clickhouse,

  // MySQL 协议族薄适配四成员（dbx-response M7 T22-T25）：server 侧经
  // 网关薄适配接入（automation mysql_family.rs），客户端复用 MySQL 形态
  // （连接表单/适配器均走 MySQL 通道，见 mysql_adapter.dart / mysql_
  // connection_form.dart 的注册面）。
  oceanbase,
  tidb,
  starrocks,
  mariadb;

  // ============================================================================
  // 表驱动：数据库类型基础属性
  // ============================================================================

  static const _sqlLikeTypes = {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.doris,
    DatabaseType.tdengine,
    DatabaseType.sqlserver,
    DatabaseType.clickhouse,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  };

  static const _sqlTypes = {
    DatabaseType.mysql,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.doris,
    DatabaseType.tdengine,
    DatabaseType.sqlserver,
    DatabaseType.clickhouse,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  };

  static const _noSqlTypes = {DatabaseType.redis, DatabaseType.mongodb};

  static const _schemaLessTypes = {DatabaseType.mongodb, DatabaseType.redis};

  static const _supportsTableStatsTypes = {
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.postgresql,
    DatabaseType.sqlite,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
  };

  static final Map<DatabaseType, String> _displayNameMap = {
    DatabaseType.mysql: 'MySQL',
    DatabaseType.postgresql: 'PostgreSQL',
    DatabaseType.sqlite: 'SQLite',
    DatabaseType.doris: 'Doris',
    DatabaseType.redis: 'Redis',
    DatabaseType.mongodb: 'MongoDB',
    DatabaseType.tdengine: 'TDengine',
    DatabaseType.sqlserver: 'SQL Server',
    DatabaseType.clickhouse: 'ClickHouse',
    DatabaseType.oceanbase: 'OceanBase',
    DatabaseType.tidb: 'TiDB',
    DatabaseType.starrocks: 'StarRocks',
    DatabaseType.mariadb: 'MariaDB',
  };

  // emoji 图标已全面下线（F-37），渲染点统一改用 typeIcon + brandColor。
  // D9（2026-08-18）：图标体系切 Lucide，此 map 即各类型 Lucide 图标。
  // T22-T25：四成员复用子集内既有图标（database/chartColumn——不引入新
  // 字形，免去 Lucide 子集重切）。
  static final Map<DatabaseType, IconData> _typeIconMap = {
    DatabaseType.mysql: LucideIcons.database,
    DatabaseType.postgresql: LucideIcons.table2,
    DatabaseType.sqlite: LucideIcons.database,
    DatabaseType.doris: LucideIcons.chartColumn,
    DatabaseType.redis: LucideIcons.memoryStick,
    DatabaseType.mongodb: LucideIcons.network,
    DatabaseType.tdengine: LucideIcons.activity,
    DatabaseType.sqlserver: LucideIcons.table2,
    DatabaseType.clickhouse: LucideIcons.zap,
    DatabaseType.oceanbase: LucideIcons.database,
    DatabaseType.tidb: LucideIcons.database,
    DatabaseType.starrocks: LucideIcons.chartColumn,
    DatabaseType.mariadb: LucideIcons.database,
  };

  // 品牌色集中到枚举（原 sidebar_tree._dbTypeColor 私有映射，现委托到此）。
  // 此处为官方品牌色单一真相源（亮色用）；暗色主题分发（四个 *Dark 变体）
  // 在 ThemeColors.brandColor（c02_token_spec §3.2），UI 勿直引本 map。
  static const Map<DatabaseType, Color> _brandColorMap = {
    DatabaseType.mysql: AppDesignSystem.dbMysql,
    DatabaseType.postgresql: AppDesignSystem.dbPostgresql,
    DatabaseType.sqlite: AppDesignSystem.dbSqlite,
    DatabaseType.doris: AppDesignSystem.dbDoris,
    DatabaseType.redis: AppDesignSystem.dbRedis,
    DatabaseType.mongodb: AppDesignSystem.dbMongodb,
    DatabaseType.tdengine: AppDesignSystem.dbTDengine,
    DatabaseType.sqlserver: AppDesignSystem.dbSqlserver,
    DatabaseType.clickhouse: AppDesignSystem.dbClickhouse,
    DatabaseType.oceanbase: AppDesignSystem.dbOceanbase,
    DatabaseType.tidb: AppDesignSystem.dbTidb,
    DatabaseType.starrocks: AppDesignSystem.dbStarrocks,
    DatabaseType.mariadb: AppDesignSystem.dbMariadb,
  };

  static final Map<DatabaseType, int> _defaultPortMap = {
    DatabaseType.mysql: 3306,
    DatabaseType.postgresql: 5432,
    DatabaseType.sqlite: 0,
    DatabaseType.doris: 9030,
    DatabaseType.redis: 6379,
    DatabaseType.mongodb: 27017,
    DatabaseType.tdengine: 6041,
    DatabaseType.sqlserver: 1433,
    DatabaseType.clickhouse: 9004, // CH MySQL-wire protocol port
    DatabaseType.oceanbase: 2881, // OB MySQL 协议口（sys/用户租户同端口）
    DatabaseType.tidb: 4000,
    DatabaseType.starrocks: 9030, // FE MySQL 协议口
    DatabaseType.mariadb: 3306,
  };

  /// 在 UI 中可供选择的数据库类型
  static List<DatabaseType> get uiSelectableValues => values;

  static final Map<DatabaseType, String> _entityPanelTableLabelMap = {
    DatabaseType.mongodb: 'Collections',
    DatabaseType.redis: 'Namespaces',
  };

  /// 是否为类SQL数据库（使用SQL语法）
  bool get isSqlLike => _sqlLikeTypes.contains(this);

  String get displayName => _displayNameMap[this]!;

  IconData get typeIcon => _typeIconMap[this]!;

  /// 数据库品牌色（图标着色、左缘标识条）
  Color get brandColor => _brandColorMap[this]!;

  int get defaultPort => _defaultPortMap[this]!;

  bool get isSQL => _sqlTypes.contains(this);
  bool get isNoSQL => _noSqlTypes.contains(this);

  static DatabaseType fromName(String name) {
    return DatabaseType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => DatabaseType.mysql,
    );
  }

  static DatabaseType? tryFromName(String name) {
    return DatabaseType.values.cast<DatabaseType?>().firstWhere(
      (e) => e?.name == name,
      orElse: () => null,
    );
  }

  // Schema capability checks
  bool get supportsColumnEdit => isSQL && this != DatabaseType.tdengine;

  bool get supportsIndexEdit =>
      isSQL && this != DatabaseType.tdengine && this != DatabaseType.redis;

  bool get supportsViews =>
      isSQL && this != DatabaseType.tdengine && this != DatabaseType.redis;

  bool get supportsForeignKeys => isSQL && this != DatabaseType.tdengine;

  bool get supportsProcedures =>
      this == DatabaseType.mysql ||
      this == DatabaseType.postgresql ||
      this == DatabaseType.sqlserver;

  bool get supportsFunctions => supportsProcedures;

  bool get supportsTriggers =>
      this == DatabaseType.mysql ||
      this == DatabaseType.sqlserver ||
      this == DatabaseType.postgresql;

  bool get supportsEvents => this == DatabaseType.mysql;

  bool get supportsAnalyzeTable =>
      this == DatabaseType.mysql ||
      this == DatabaseType.postgresql ||
      this == DatabaseType.doris;

  bool get supportsOptimizeTable =>
      this == DatabaseType.mysql || this == DatabaseType.postgresql;

  bool get supportsCheckTable =>
      this == DatabaseType.mysql || this == DatabaseType.postgresql;

  bool get supportsProgrammableObjects =>
      supportsViews ||
      supportsProcedures ||
      supportsFunctions ||
      supportsTriggers ||
      supportsEvents;

  bool get isSchemaLess => _schemaLessTypes.contains(this);

  /// 是否支持 schema 命名空间（PostgreSQL、SQL Server）。
  bool get supportsSchemas =>
      this == DatabaseType.postgresql || this == DatabaseType.sqlserver;

  /// 是否支持物化视图（PostgreSQL、Doris）。
  bool get supportsMaterializedViews =>
      this == DatabaseType.postgresql || this == DatabaseType.doris;

  /// 是否支持序列（PostgreSQL）。
  bool get supportsSequences => this == DatabaseType.postgresql;

  bool get supportsRenameTable => isSQL || this == DatabaseType.redis;

  /// 是否支持表统计信息（行数 / 数据大小）
  bool get supportsTableStats => _supportsTableStatsTypes.contains(this);

  // ── C19（侧边栏旧框架下线）增补：树形态与菜单路由声明面 ──
  // 以下 getter 是 UI 树形态 / 菜单动作路由的单一声明（非能力位——能力
  // 有无一律经 CapabilityTable 查询）。sidebar 区块按铁律 3 清零
  // `DatabaseType.` 字面量后，类型分派收编到本枚举或 utils/services 层。

  /// 连接级整树型：整棵对象树在连接卡片展开区直接渲染，宿主不渲染数据库
  /// 列表层（Redis = 逻辑库列表 + 全局面板经插件树；SQLite = main + ATTACH
  /// alias 扁平树经插件树）。
  bool get isConnectionLevelTree =>
      this == DatabaseType.redis || this == DatabaseType.sqlite;

  /// SQLite 专属形态：单文件扁平树，键盘导航 key 集走专用装配
  /// （sidebar_visible_nodes）。Redis 虽同为连接级整树，但其库列表与全局
  /// 节点 key 仍走宿主通用循环，故此处不含 Redis。
  bool get isFlatFileTree => this == DatabaseType.sqlite;

  /// 库节点是否有对象子树（侧边栏 db 节点的箭头与懒加载判定）。
  bool get hasDatabaseObjectLayer => isSQL || this == DatabaseType.mongodb;

  /// 库级右键「新建表」菜单动作 id（宿主 _handleDatabaseAction 的分派键，
  /// 同时是该项的显示门控——null = 不提供）。PG/TD 有专属创建对话框，
  /// 其余 SQL 类型走通用 CreateTableDialog（MySQL 方言，T22-T25 四成员
  /// 同走）。门控与路由同源，无双源漂移面。
  String? get createTableMenuAction => switch (this) {
        DatabaseType.postgresql => 'create_table_pg',
        DatabaseType.tdengine => 'create_supertable',
        DatabaseType.mysql ||
        DatabaseType.doris ||
        DatabaseType.sqlite ||
        DatabaseType.sqlserver ||
        DatabaseType.oceanbase ||
        DatabaseType.tidb ||
        DatabaseType.starrocks ||
        DatabaseType.mariadb => 'create_table',
        _ => null,
      };

  /// 存储过程调用动词（T-SQL 用 EXEC，其余方言 CALL）。
  String get procedureCallVerb =>
      this == DatabaseType.sqlserver ? 'EXEC' : 'CALL';

  String get entityPanelTableLabel =>
      _entityPanelTableLabelMap[this] ?? 'Tables';
}

/// Options for TRUNCATE TABLE operations (PostgreSQL-specific features).
///
/// [cascade] — automatically truncate tables with foreign-key references.
/// [restartIdentity] — true=RESTART IDENTITY, false=CONTINUE IDENTITY, null=neither.
class TruncateOptions {
  final bool cascade;
  final bool? restartIdentity;

  const TruncateOptions({this.cascade = false, this.restartIdentity});
}

enum RedisAuthMode {
  none,
  passwordOnly,
  usernamePassword;

  String get displayName {
    switch (this) {
      case RedisAuthMode.none:
        return 'No Auth';
      case RedisAuthMode.passwordOnly:
        return 'Password Only';
      case RedisAuthMode.usernamePassword:
        return 'Username + Password (ACL)';
    }
  }

  String get description {
    switch (this) {
      case RedisAuthMode.none:
        return 'No authentication required';
      case RedisAuthMode.passwordOnly:
        return 'AUTH password (Redis < 6.0)';
      case RedisAuthMode.usernamePassword:
        return 'AUTH username password (Redis 6.0+ ACL)';
    }
  }
}

enum SshAuthMode {
  password,
  privateKey;

  String get displayName {
    switch (this) {
      case SshAuthMode.password:
        return 'Password';
      case SshAuthMode.privateKey:
        return 'Private Key';
    }
  }
}

class DbServer {
  final String id;
  final String name;
  final DatabaseType type;
  final String host;
  final int port;
  final String? username;
  String? password;
  String? database;
  bool connected;

  final bool useSSL;
  final int timeoutSeconds;
  final bool autoReconnect;
  final String? charset;
  final String? timezone;
  final String? groupId;
  final DateTime? lastConnected;
  final ConnectionEnvironment? environment;
  final bool readOnly;

  // SSH Tunnel Configuration
  final bool useSshTunnel;
  final String? sshHost;
  final int? sshPort;
  final String? sshUsername;
  final SshAuthMode? sshAuthMode;
  final String? sshPassword; // Only for password auth
  final String?
  sshPrivateKey; // Only for private key auth (stored in SecureStorage)
  final String? sshPassphrase; // For encrypted private keys

  // TLS 透传（Redis/MongoDB/TDengine 网关连接）：与既有 useSSL（本地
  // 直连时代的开关，网关 draft 无对应字段）区分——这两个键经网关注册/
  // 测试 body 的 extra 透传给 server，由 server 侧驱动 TLS。
  final bool useTls;
  final bool tlsInsecure;

  /// 数据库特定的额外配置参数
  final Map<String, dynamic>? extra;

  // -------------------------------------------------------------------------
  // Equality (based on id)
  // -------------------------------------------------------------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbServer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  DbServer({
    required this.id,
    required this.name,
    this.type = DatabaseType.mysql,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.database,
    this.connected = false,
    this.useSSL = false,
    this.timeoutSeconds = 30,
    this.autoReconnect = false,
    this.charset = 'utf8mb4',
    this.timezone,
    this.groupId,
    this.lastConnected,
    this.environment,
    this.readOnly = false,
    this.useSshTunnel = false,
    this.sshHost,
    this.sshPort = 22,
    this.sshUsername,
    this.sshAuthMode,
    this.sshPassword,
    this.sshPrivateKey,
    this.sshPassphrase,
    this.useTls = false,
    this.tlsInsecure = false,
    this.extra,
  });

  DbServer copyWith({
    String? id,
    String? name,
    DatabaseType? type,
    String? host,
    int? port,
    String? username,
    String? password,
    String? database,
    bool? connected,
    bool? useSSL,
    int? timeoutSeconds,
    bool? autoReconnect,
    String? charset,
    String? timezone,
    String? groupId,
    DateTime? lastConnected,
    bool clearLastConnected = false,
    ConnectionEnvironment? environment,
    bool clearEnvironment = false,
    bool? readOnly,
    bool? useSshTunnel,
    String? sshHost,
    int? sshPort,
    String? sshUsername,
    SshAuthMode? sshAuthMode,
    String? sshPassword,
    String? sshPrivateKey,
    String? sshPassphrase,
    bool? useTls,
    bool? tlsInsecure,
    Map<String, dynamic>? extra,
  }) {
    return DbServer(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      database: database ?? this.database,
      connected: connected ?? this.connected,
      useSSL: useSSL ?? this.useSSL,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      charset: charset ?? this.charset,
      timezone: timezone ?? this.timezone,
      groupId: groupId ?? this.groupId,
      lastConnected: clearLastConnected
          ? null
          : (lastConnected ?? this.lastConnected),
      environment:
          clearEnvironment ? null : (environment ?? this.environment),
      readOnly: readOnly ?? this.readOnly,
      useSshTunnel: useSshTunnel ?? this.useSshTunnel,
      sshHost: sshHost ?? this.sshHost,
      sshPort: sshPort ?? this.sshPort,
      sshUsername: sshUsername ?? this.sshUsername,
      sshAuthMode: sshAuthMode ?? this.sshAuthMode,
      sshPassword: sshPassword ?? this.sshPassword,
      sshPrivateKey: sshPrivateKey ?? this.sshPrivateKey,
      sshPassphrase: sshPassphrase ?? this.sshPassphrase,
      useTls: useTls ?? this.useTls,
      tlsInsecure: tlsInsecure ?? this.tlsInsecure,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'host': host,
      'port': port,
      'username': username,
      // ⚠️ 密码不再序列化到 JSON，存于 flutter_secure_storage
      'database': database,
      'useSSL': useSSL,
      'timeoutSeconds': timeoutSeconds,
      'autoReconnect': autoReconnect,
      'charset': charset,
      'timezone': timezone,
      'groupId': groupId,
      'lastConnected': lastConnected?.toIso8601String(),
      'environment': environment?.name,
      'readOnly': readOnly,
      // SSH Tunnel Configuration
      'useSshTunnel': useSshTunnel,
      'sshHost': sshHost,
      'sshPort': sshPort,
      'sshUsername': sshUsername,
      'sshAuthMode': sshAuthMode?.name,
      'useTls': useTls,
      'tlsInsecure': tlsInsecure,
      'extra': extra,
      // ⚠️ SSH 敏感信息存于 flutter_secure_storage
    };
  }

  /// Parses a [DbServer] from JSON.
  ///
  /// ⚠️ This factory will read sensitive fields (`password`, `sshPassword`,
  /// `sshPrivateKey`, `sshPassphrase`) if present. It should only be used with
  /// trusted data, such as the encrypted payload produced by
  /// [ConnectionExportImportService].
  factory DbServer.fromJson(Map<String, dynamic> json) {
    return DbServer(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] != null
          ? DatabaseType.fromName(json['type'] as String)
          : DatabaseType.mysql,
      host: json['host'] as String,
      port: json['port'] as int,
      username: json['username'] as String?,
      password: json['password'] as String?,
      database: json['database'] as String?,
      useSSL: json['useSSL'] as bool? ?? false,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 30,
      autoReconnect: json['autoReconnect'] as bool? ?? false,
      charset: json['charset'] as String? ?? 'utf8mb4',
      timezone: json['timezone'] as String?,
      groupId: json['groupId'] as String?,
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
      environment: json['environment'] != null
          ? ConnectionEnvironment.values.firstWhere(
              (e) => e.name == json['environment'] as String,
              orElse: () => ConnectionEnvironment.development,
            )
          : null,
      readOnly: json['readOnly'] as bool? ?? false,
      // SSH Tunnel Configuration
      useSshTunnel: json['useSshTunnel'] as bool? ?? false,
      sshHost: json['sshHost'] as String?,
      sshPort: json['sshPort'] as int? ?? 22,
      sshUsername: json['sshUsername'] as String?,
      sshAuthMode: json['sshAuthMode'] != null
          ? SshAuthMode.values.firstWhere(
              (e) => e.name == json['sshAuthMode'] as String,
              orElse: () => SshAuthMode.password,
            )
          : null,
      sshPassword: json['sshPassword'] as String?,
      sshPrivateKey: json['sshPrivateKey'] as String?,
      sshPassphrase: json['sshPassphrase'] as String?,
      // 旧 JSON 无这两键 = false（向后兼容默认值）
      useTls: json['useTls'] as bool? ?? false,
      tlsInsecure: json['tlsInsecure'] as bool? ?? false,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }
}

class ConnectionGroup {
  final String id;
  final String name;
  final String? color;
  final int order;

  // -------------------------------------------------------------------------
  // Equality (based on id)
  // -------------------------------------------------------------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionGroup &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  ConnectionGroup({
    required this.id,
    required this.name,
    this.color,
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'order': order,
  };

  factory ConnectionGroup.fromJson(Map<String, dynamic> json) {
    return ConnectionGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String?,
      order: json['order'] as int? ?? 0,
    );
  }
}

class ActiveConnection {
  final DbServer server;
  final DatabaseServiceInfo? databaseInfo;
  final DateTime connectedAt;
  final bool isActive;

  ActiveConnection({
    required this.server,
    this.databaseInfo,
    required this.connectedAt,
    this.isActive = true,
  });

  ActiveConnection copyWith({
    DbServer? server,
    DatabaseServiceInfo? databaseInfo,
    DateTime? connectedAt,
    bool? isActive,
  }) {
    return ActiveConnection(
      server: server ?? this.server,
      databaseInfo: databaseInfo ?? this.databaseInfo,
      connectedAt: connectedAt ?? this.connectedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

class DatabaseServiceInfo {
  final List<String> databases;
  final String? currentDatabase;
  final Map<String, Database> databaseDetails;

  DatabaseServiceInfo({
    this.databases = const [],
    this.currentDatabase,
    this.databaseDetails = const {},
  });

  DatabaseServiceInfo copyWith({
    List<String>? databases,
    String? currentDatabase,
    Map<String, Database>? databaseDetails,
  }) {
    return DatabaseServiceInfo(
      databases: databases ?? this.databases,
      currentDatabase: currentDatabase ?? this.currentDatabase,
      databaseDetails: databaseDetails ?? this.databaseDetails,
    );
  }
}

class DbTrigger {
  final String name;
  final String event;
  final String table;
  final String timing;
  final String? statement;

  DbTrigger({
    required this.name,
    required this.event,
    required this.table,
    required this.timing,
    this.statement,
  });
}

/// PostgreSQL / SQL Server 等支持 schema 命名空间的数据库对象分组。
class DbSchema {
  final String name;
  final List<DbTable> tables;
  final List<String> views;
  final List<String> materializedViews;
  final List<String> functions;
  final List<String> procedures;
  final List<String> sequences;
  final List<DbTrigger> triggers;

  const DbSchema({
    required this.name,
    this.tables = const [],
    this.views = const [],
    this.materializedViews = const [],
    this.functions = const [],
    this.procedures = const [],
    this.sequences = const [],
    this.triggers = const [],
  });

  DbSchema copyWith({
    String? name,
    List<DbTable>? tables,
    List<String>? views,
    List<String>? materializedViews,
    List<String>? functions,
    List<String>? procedures,
    List<String>? sequences,
    List<DbTrigger>? triggers,
  }) {
    return DbSchema(
      name: name ?? this.name,
      tables: tables ?? this.tables,
      views: views ?? this.views,
      materializedViews: materializedViews ?? this.materializedViews,
      functions: functions ?? this.functions,
      procedures: procedures ?? this.procedures,
      sequences: sequences ?? this.sequences,
      triggers: triggers ?? this.triggers,
    );
  }
}

class Database {
  final String name;
  final List<DbTable> tables;
  final List<String> views;
  final List<String> procedures;
  final List<DbTrigger> triggers;
  final List<String> events;
  final List<String> functions;
  final List<String> materializedViews;
  final List<String> sequences;
  final List<DbSchema> schemas;

  Database({
    required this.name,
    this.tables = const [],
    this.views = const [],
    this.procedures = const [],
    this.triggers = const [],
    this.events = const [],
    this.functions = const [],
    this.materializedViews = const [],
    this.sequences = const [],
    this.schemas = const [],
  });
}

class DbTable {
  final String name;
  final List<DbColumn> columns;
  final List<DbIndex> indexes;
  final int? rowCount;
  final String? comment;

  DbTable({
    required this.name,
    this.columns = const [],
    this.indexes = const [],
    this.rowCount,
    this.comment,
  });
}

class DbColumn {
  final String name;
  final String type;
  final bool isPrimaryKey;
  final bool isNullable;
  final String? defaultValue;

  // -------------------------------------------------------------------------
  // Equality (based on name + type)
  // -------------------------------------------------------------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbColumn &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          type == other.type;

  @override
  int get hashCode => Object.hash(name, type);

  final bool isTag;

  DbColumn({
    required this.name,
    required this.type,
    this.isPrimaryKey = false,
    this.isNullable = true,
    this.defaultValue,
    this.isTag = false,
  });
}

class DbIndex {
  final String name;
  final List<String> columns;
  final bool isUnique;
  final bool isForeignKey;

  // -------------------------------------------------------------------------
  // Equality (based on name)
  // -------------------------------------------------------------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DbIndex &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  DbIndex({
    required this.name,
    required this.columns,
    this.isUnique = false,
    this.isForeignKey = false,
  });
}

class QueryTab {
  String id;
  String title;
  String sql;
  List<Map<String, dynamic>>? results;
  List<Map<String, dynamic>>? explainPlan;
  String? error;
  bool isExecuting;
  String? connectionId;
  String? databaseName;
  bool isSaved;

  // -------------------------------------------------------------------------
  // Equality (based on id)
  // -------------------------------------------------------------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryTab && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  QueryTab({
    required this.id,
    required this.title,
    this.sql = '',
    this.results,
    this.explainPlan,
    this.error,
    this.isExecuting = false,
    this.connectionId,
    this.databaseName,
    this.isSaved = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'sql': sql,
      'isSaved': isSaved,
      'connectionId': connectionId,
      'databaseName': databaseName,
    };
  }

  factory QueryTab.fromJson(Map<String, dynamic> json) => QueryTab(
    id: json['id'] as String,
    title: json['title'] as String,
    sql: json['sql'] as String? ?? '',
    isSaved: json['isSaved'] as bool? ?? false,
    connectionId: json['connectionId'] as String?,
    databaseName: json['databaseName'] as String?,
  );

  QueryTab copyWith({
    String? id,
    String? title,
    String? sql,
    List<Map<String, dynamic>>? results,
    List<Map<String, dynamic>>? explainPlan,
    String? error,
    bool? isExecuting,
    String? connectionId,
    String? databaseName,
    bool? isSaved,
  }) {
    return QueryTab(
      id: id ?? this.id,
      title: title ?? this.title,
      sql: sql ?? this.sql,
      results: results ?? this.results,
      explainPlan: explainPlan ?? this.explainPlan,
      error: error ?? this.error,
      isExecuting: isExecuting ?? this.isExecuting,
      connectionId: connectionId ?? this.connectionId,
      databaseName: databaseName ?? this.databaseName,
      isSaved: isSaved ?? this.isSaved,
    );
  }
}

class AiMessage {
  final String id;
  final bool isUser;
  final String content;
  final String? reasoningContent;
  final DateTime timestamp;
  final String? code;
  final List<String>? extractedCommands;
  final bool isLoading;
  final bool? isDangerous;
  final bool isBookmarked;
  final String? bookmarkNote;
  final String? replyToMessageId;
  final String? branchFromMessageId;
  final AiMessageType type;
  final String? toolName;
  final Map<String, dynamic>? toolArguments;
  final String? toolResultSummary;
  final Map<String, dynamic>? toolResultData;
  final AiMessageStatus status;
  final String? errorMessage;
  final String? checkpointId;

  /// C23 envelope 统一渲染：内容载体类型名（AiSkillEnvelopeType.name；
  /// null = 无显式声明，渲染层走启发式）。持久化兼容：存量消息无此字段。
  final String? envelopeType;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  AiMessage({
    required this.id,
    required this.isUser,
    required this.content,
    this.reasoningContent,
    required this.timestamp,
    this.code,
    this.extractedCommands,
    this.isLoading = false,
    this.isDangerous,
    this.isBookmarked = false,
    this.bookmarkNote,
    this.replyToMessageId,
    this.branchFromMessageId,
    this.type = AiMessageType.chat,
    this.toolName,
    this.toolArguments,
    this.toolResultSummary,
    this.toolResultData,
    this.status = AiMessageStatus.sent,
    this.errorMessage,
    this.checkpointId,
    this.envelopeType,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  AiMessage copyWith({
    String? id,
    bool? isUser,
    String? content,
    String? reasoningContent,
    DateTime? timestamp,
    String? code,
    List<String>? extractedCommands,
    bool? isLoading,
    bool? isDangerous,
    bool? isBookmarked,
    String? bookmarkNote,
    String? replyToMessageId,
    String? branchFromMessageId,
    AiMessageType? type,
    String? toolName,
    Map<String, dynamic>? toolArguments,
    String? toolResultSummary,
    Map<String, dynamic>? toolResultData,
    AiMessageStatus? status,
    String? errorMessage,
    String? checkpointId,
    String? envelopeType,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
  }) {
    return AiMessage(
      id: id ?? this.id,
      isUser: isUser ?? this.isUser,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      timestamp: timestamp ?? this.timestamp,
      code: code ?? this.code,
      extractedCommands: extractedCommands ?? this.extractedCommands,
      isLoading: isLoading ?? this.isLoading,
      isDangerous: isDangerous ?? this.isDangerous,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      bookmarkNote: bookmarkNote ?? this.bookmarkNote,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      branchFromMessageId: branchFromMessageId ?? this.branchFromMessageId,
      type: type ?? this.type,
      toolName: toolName ?? this.toolName,
      toolArguments: toolArguments ?? this.toolArguments,
      toolResultSummary: toolResultSummary ?? this.toolResultSummary,
      toolResultData: toolResultData ?? this.toolResultData,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      checkpointId: checkpointId ?? this.checkpointId,
      envelopeType: envelopeType ?? this.envelopeType,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      totalTokens: totalTokens ?? this.totalTokens,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isUser': isUser,
      'content': content,
      'reasoningContent': reasoningContent,
      'timestamp': timestamp.toIso8601String(),
      'code': code,
      'extractedCommands': extractedCommands,
      'isLoading': isLoading,
      'isDangerous': isDangerous,
      'isBookmarked': isBookmarked,
      'bookmarkNote': bookmarkNote,
      'replyToMessageId': replyToMessageId,
      'branchFromMessageId': branchFromMessageId,
      'type': type.name,
      'toolName': toolName,
      'toolArguments': toolArguments,
      'toolResultSummary': toolResultSummary,
      'toolResultData': toolResultData,
      'checkpointId': checkpointId,
      'envelopeType': envelopeType,
      'promptTokens': promptTokens,
      'completionTokens': completionTokens,
      'totalTokens': totalTokens,
    };
  }

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    return AiMessage(
      id: json['id'] as String,
      isUser: json['isUser'] as bool,
      content: json['content'] as String,
      reasoningContent: json['reasoningContent'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      code: json['code'] as String?,
      extractedCommands: (json['extractedCommands'] as List<dynamic>?)
          ?.cast<String>(),
      isLoading: json['isLoading'] as bool? ?? false,
      isDangerous: json['isDangerous'] as bool?,
      isBookmarked: json['isBookmarked'] as bool? ?? false,
      bookmarkNote: json['bookmarkNote'] as String?,
      replyToMessageId: json['replyToMessageId'] as String?,
      branchFromMessageId: json['branchFromMessageId'] as String?,
      type: _parseAiMessageType(json['type'] as String?),
      toolName: json['toolName'] as String?,
      toolArguments: json['toolArguments'] as Map<String, dynamic>?,
      toolResultSummary: json['toolResultSummary'] as String?,
      toolResultData: json['toolResultData'] as Map<String, dynamic>?,
      checkpointId: json['checkpointId'] as String?,
      envelopeType: json['envelopeType'] as String?,
      promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
      completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
      totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
    );
  }

  static AiMessageType _parseAiMessageType(String? value) {
    switch (value) {
      case 'toolCall':
        return AiMessageType.toolCall;
      case 'toolResult':
        return AiMessageType.toolResult;
      default:
        return AiMessageType.chat;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiMessage && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Represents a foreign key relationship between tables
class DbTableMetadata {
  final String name;
  final int? rowCount;
  final int? dataSize;
  final String? comment;
  final String? engine;
  final DateTime? updateTime;
  final DateTime? createTime;
  final bool isApproximateCount;

  DbTableMetadata({
    required this.name,
    this.rowCount,
    this.dataSize,
    this.comment,
    this.engine,
    this.updateTime,
    this.createTime,
    this.isApproximateCount = false,
  });

  String get formattedDataSize {
    final size = dataSize;
    if (size == null) return '';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  bool get isLargeTable =>
      (rowCount ?? 0) > 1000000 || (dataSize ?? 0) > 1024 * 1024 * 1024;
  bool get isMediumTable =>
      (rowCount ?? 0) > 100000 || (dataSize ?? 0) > 100 * 1024 * 1024;

  DbTableMetadata copyWith({
    String? name,
    int? rowCount,
    int? dataSize,
    String? comment,
    String? engine,
    DateTime? updateTime,
    DateTime? createTime,
    bool? isApproximateCount,
  }) {
    return DbTableMetadata(
      name: name ?? this.name,
      rowCount: rowCount ?? this.rowCount,
      dataSize: dataSize ?? this.dataSize,
      comment: comment ?? this.comment,
      engine: engine ?? this.engine,
      updateTime: updateTime ?? this.updateTime,
      createTime: createTime ?? this.createTime,
      isApproximateCount: isApproximateCount ?? this.isApproximateCount,
    );
  }
}

class ForeignKey {
  final String name;
  final String table;
  final String column;
  final String referencedTable;
  final String referencedColumn;
  final String? onUpdate;
  final String? onDelete;

  ForeignKey({
    required this.name,
    required this.table,
    required this.column,
    required this.referencedTable,
    required this.referencedColumn,
    this.onUpdate,
    this.onDelete,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'table': table,
      'column': column,
      'referencedTable': referencedTable,
      'referencedColumn': referencedColumn,
      'onUpdate': onUpdate,
      'onDelete': onDelete,
    };
  }

  factory ForeignKey.fromJson(Map<String, dynamic> json) {
    return ForeignKey(
      name: json['name'] as String,
      table: json['table'] as String,
      column: json['column'] as String,
      referencedTable: json['referencedTable'] as String,
      referencedColumn: json['referencedColumn'] as String,
      onUpdate: json['onUpdate'] as String?,
      onDelete: json['onDelete'] as String?,
    );
  }
}

// T002 — ProcessInfo model for MySQL/PG process list
class ProcessInfo {
  final int id;
  final String user;
  final String host;
  final String database;
  final String command;
  final int time;
  final String state;
  final String? info;

  const ProcessInfo({
    required this.id,
    required this.user,
    required this.host,
    required this.database,
    required this.command,
    required this.time,
    required this.state,
    this.info,
  });

  factory ProcessInfo.fromMap(Map<String, dynamic> map) {
    final timeRaw = map['Time'] ?? map['time'] ?? 0;
    return ProcessInfo(
      id:
          int.tryParse(map['Id']?.toString() ?? map['id']?.toString() ?? '') ??
          0,
      user: map['User']?.toString() ?? map['user']?.toString() ?? '',
      host: map['Host']?.toString() ?? map['host']?.toString() ?? '',
      database:
          map['db']?.toString() ??
          map['Database']?.toString() ??
          map['database']?.toString() ??
          '',
      command: map['Command']?.toString() ?? map['command']?.toString() ?? '',
      time: timeRaw is int ? timeRaw : int.tryParse(timeRaw.toString()) ?? 0,
      state: map['State']?.toString() ?? map['state']?.toString() ?? '',
      info: map['Info']?.toString() ?? map['info']?.toString(),
    );
  }
}

// T003 — ReplicationStatus model for MySQL replication monitoring
class ReplicationStatus {
  final String? slaveIoRunning;
  final String? slaveSqlRunning;
  final int? secondsBehindMaster;
  final String? lastIoError;
  final String? lastSqlError;
  final String? masterLogFile;
  final String? readMasterLogPos;
  final Map<String, dynamic> raw;

  const ReplicationStatus({
    this.slaveIoRunning,
    this.slaveSqlRunning,
    this.secondsBehindMaster,
    this.lastIoError,
    this.lastSqlError,
    this.masterLogFile,
    this.readMasterLogPos,
    required this.raw,
  });

  bool get isRunning =>
      slaveIoRunning?.toLowerCase() == 'yes' &&
      slaveSqlRunning?.toLowerCase() == 'yes';

  bool get hasError =>
      (lastIoError != null && lastIoError!.isNotEmpty) ||
      (lastSqlError != null && lastSqlError!.isNotEmpty);

  factory ReplicationStatus.fromMap(Map<String, dynamic> map) {
    final sbm = map['Seconds_Behind_Master'];
    return ReplicationStatus(
      slaveIoRunning: map['Slave_IO_Running']?.toString(),
      slaveSqlRunning: map['Slave_SQL_Running']?.toString(),
      secondsBehindMaster: sbm is int
          ? sbm
          : int.tryParse(sbm?.toString() ?? ''),
      lastIoError: map['Last_IO_Error']?.toString(),
      lastSqlError: map['Last_SQL_Error']?.toString(),
      masterLogFile: map['Master_Log_File']?.toString(),
      readMasterLogPos: map['Read_Master_Log_Pos']?.toString(),
      raw: map,
    );
  }
}

// ============================================================================
// PostgreSQL Extension Models (ExtensionAdapter)
// ============================================================================

/// Kind of object registered by a PostgreSQL extension.
enum PgExtensionMemberKind { type, function, operator }

/// Index access method for pgvector indexes.
enum VectorIndexType { ivfflat, hnsw }

/// A single type, function, or operator registered by a PostgreSQL extension.
class PgExtensionMember {
  final String name;
  final String schema;
  final String? signature;
  final PgExtensionMemberKind kind;

  const PgExtensionMember({
    required this.name,
    required this.schema,
    this.signature,
    required this.kind,
  });

  factory PgExtensionMember.fromMap(
    Map<String, dynamic> map,
    PgExtensionMemberKind kind,
  ) {
    return PgExtensionMember(
      name: map['name']?.toString() ?? '',
      schema: map['schema']?.toString() ?? '',
      signature: map['signature']?.toString(),
      kind: kind,
    );
  }
}

/// A PostgreSQL extension installed in a database.
class PgExtension {
  final String name;
  final String version;
  final String schema;
  final String description;
  final List<PgExtensionMember> types;
  final List<PgExtensionMember> functions;
  final List<PgExtensionMember> operators;

  const PgExtension({
    required this.name,
    required this.version,
    required this.schema,
    this.description = '',
    this.types = const [],
    this.functions = const [],
    this.operators = const [],
  });

  factory PgExtension.fromMap(Map<String, dynamic> map) {
    return PgExtension(
      name: map['extname']?.toString() ?? map['name']?.toString() ?? '',
      version:
          map['extversion']?.toString() ?? map['version']?.toString() ?? '',
      schema: map['schema']?.toString() ?? '',
      description:
          map['comment']?.toString() ?? map['description']?.toString() ?? '',
    );
  }
}

/// A pgvector vector index on a column.
class VectorIndex {
  final String name;
  final String tableName;
  final String columnName;
  final VectorIndexType indexType;
  final int? dimensions;
  final String? distanceFunction;
  final Map<String, String> options;

  const VectorIndex({
    required this.name,
    required this.tableName,
    required this.columnName,
    required this.indexType,
    this.dimensions,
    this.distanceFunction,
    this.options = const {},
  });

  factory VectorIndex.fromMap(Map<String, dynamic> map) {
    final amName =
        map['amname']?.toString() ?? map['index_type']?.toString() ?? '';
    VectorIndexType indexType;
    if (amName == 'hnsw') {
      indexType = VectorIndexType.hnsw;
    } else {
      indexType = VectorIndexType.ivfflat;
    }

    return VectorIndex(
      name: map['index_name']?.toString() ?? map['name']?.toString() ?? '',
      tableName:
          map['table_name']?.toString() ?? map['tableName']?.toString() ?? '',
      columnName:
          map['column_name']?.toString() ?? map['columnName']?.toString() ?? '',
      indexType: indexType,
      dimensions: map['dimensions'] is int
          ? map['dimensions'] as int
          : int.tryParse(map['dimensions']?.toString() ?? ''),
      distanceFunction:
          map['distance_function']?.toString() ??
          map['distanceFunction']?.toString(),
      options: map['options'] is Map<String, String>
          ? Map<String, String>.from(map['options'])
          : const {},
    );
  }
}

/// PRAGMA 配置项分类（SQLite PRAGMA Explorer）。
enum PragmaCategory {
  /// 缓存 / 页大小 / 内存映射等性能调优
  performance,

  /// 同步 / 日志模式 / WAL 检查点等持久性
  durability,

  /// 外键 / 触发器等安全约束
  security,

  /// 编码 / 完整性检查 / 版本等调试信息
  debug,
}

/// SQLite PRAGMA 配置项（PRAGMA Explorer）。
@immutable
class PragmaInfo {
  /// PRAGMA 名称（如 'journal_mode'）。
  final String name;

  /// 分类。
  final PragmaCategory category;

  /// 当前值（从 `PRAGMA name` 查得）。null = 查询失败或无值。
  final String? currentValue;

  /// 简短描述。
  final String description;

  /// 是否可写（`PRAGMA name = value` 可修改）。
  final bool writable;

  const PragmaInfo({
    required this.name,
    required this.category,
    required this.description,
    this.currentValue,
    this.writable = false,
  });

  /// 带更新值的副本（setPragma 后返回新实例）。
  PragmaInfo copyWithCurrentValue(String? value) => PragmaInfo(
    name: name,
    category: category,
    description: description,
    currentValue: value,
    writable: writable,
  );

  factory PragmaInfo.fromMap(Map<String, dynamic> map) => PragmaInfo(
    name: map['name']?.toString() ?? '',
    category: PragmaCategory.values.firstWhere(
      (c) => c.name == map['category']?.toString(),
      orElse: () => PragmaCategory.debug,
    ),
    description: map['description']?.toString() ?? '',
    currentValue: map['currentValue']?.toString(),
    writable: map['writable'] is bool ? map['writable'] as bool : false,
  );
}
