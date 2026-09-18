/// MongoDB 集成测试配置
///
/// 凭据不随仓库分发（开源剥离）：连接参数经 `--dart-define=DBMASTER_MONGO_*`
/// 注入；未提供时 [available] 为 false，消费方应跳过而非空跑。
class MongoDBTestConfig {
  static const String _defaultHost = '';
  static const int _defaultPort = 27017;
  static const String _defaultUser = '';
  static const String _defaultPassword = '';
  static const String _defaultAuthDatabase = 'admin';

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_MONGO_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_MONGO_PORT',
      defaultValue: '$_defaultPort',
    );
    return int.tryParse(portStr) ?? _defaultPort;
  }

  static String get username {
    return const String.fromEnvironment(
      'DBMASTER_MONGO_USER',
      defaultValue: _defaultUser,
    );
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_MONGO_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get authDatabase {
    return const String.fromEnvironment(
      'DBMASTER_MONGO_AUTH_DB',
      defaultValue: _defaultAuthDatabase,
    );
  }

  /// 生成唯一测试数据库名，避免并行测试冲突
  static String generateTestDatabaseName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'dbmaster_test_$timestamp';
  }

  /// 生成唯一集合名前缀
  static String generateTestCollectionPrefix() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'test_$timestamp';
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;

  // ==================== Replica Set (spec 044 / US1) ====================
  static const String _defaultRsName = 'rs0';
  static const String _defaultRsSeeds = '';

  /// 副本集名（默认 rs0），可通过 DBMASTER_MONGO_RS_NAME 覆盖。
  static String get rsName => const String.fromEnvironment(
        'DBMASTER_MONGO_RS_NAME',
        defaultValue: _defaultRsName,
      );

  /// 副本集 seed 列表（host:port，逗号分隔），通过 DBMASTER_MONGO_RS_SEEDS
  /// 提供（开源剥离：不随仓库分发默认值）。
  static List<String> get rsSeeds {
    final raw = const String.fromEnvironment(
      'DBMASTER_MONGO_RS_SEEDS',
      defaultValue: _defaultRsSeeds,
    );
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 副本集 admin 密码——通过 DBMASTER_MONGO_RS_PASSWORD 提供（**不入库**；
  /// 真值见测试服务器 /root/mongo-rs0-admin-pwd.txt）。
  static String get rsPassword => const String.fromEnvironment(
        'DBMASTER_MONGO_RS_PASSWORD',
        defaultValue: '',
      );

  /// RS E2E 仅在配置了 RS 密码 + seed 列表时可运行（无则 CI / 无 RS 环境
  /// skip；开源剥离后 seeds 无默认值，需一并提供）。
  static bool get isReplicaSetConfigured =>
      rsPassword.isNotEmpty && rsSeeds.isNotEmpty;

  /// T033 failover E2E 开关：设 DBMASTER_MONGO_RS_FAILOVER=1 才执行 stepDown +
  /// 重连验证（破坏性——会触发主切换，仅隔离测试库上跑）。默认 skip。
  static bool get rsFailoverEnabled => const bool.hasEnvironment(
        'DBMASTER_MONGO_RS_FAILOVER',
      );

  // ==================== Sharded via mongos (spec 044 / US2) ====================
  /// mongos 路由 seed 列表（host:port，逗号分隔），DBMASTER_MONGO_MONGOS_SEEDS 覆盖。
  /// 默认空——无 mongos 测试库时 Sharded E2E skip。
  static List<String> get mongosSeeds {
    final raw = const String.fromEnvironment(
      'DBMASTER_MONGO_MONGOS_SEEDS',
      defaultValue: '',
    );
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// mongos admin 密码——DBMASTER_MONGO_MONGOS_PASSWORD 提供（**不入库**）。
  static String get mongosPassword => const String.fromEnvironment(
        'DBMASTER_MONGO_MONGOS_PASSWORD',
        defaultValue: '',
      );

  /// Sharded E2E 仅在配置了 mongos 密码 + seed 列表时可运行（无则 skip）。
  static bool get isShardedConfigured =>
      mongosPassword.isNotEmpty && mongosSeeds.isNotEmpty;
}