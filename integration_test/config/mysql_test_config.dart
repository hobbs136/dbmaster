/// MySQL 集成测试配置
///
/// 凭据不随仓库分发（开源剥离）：所有连接参数经
/// `--dart-define=DBMASTER_MYSQL_*` 注入；未提供时 [available] 为 false，
/// 消费方应以可 grep 的 MYSQL_E2E_SKIP 跳过（不连真实库的空跑禁止）。
///
/// 键（主服务器）：DBMASTER_MYSQL_HOST / PORT / USER / PASSWORD / DATABASE；
/// 键（从服务器 3307 remote_user）：DBMASTER_MYSQL_ALT_HOST / ALT_PORT /
/// ALT_USER / ALT_PASSWORD（altUseSSL 固定 true）；
/// 键（从服务器 3307 MySQL 5.7 root）：DBMASTER_MYSQL57_HOST / PORT / USER /
/// PASSWORD。
class MySQLTestConfig {
  // ===== 主服务器 =====
  static const String _defaultHost = '';
  static const int _defaultPort = 3306;
  static const String _defaultUser = '';
  static const String _defaultPassword = '';
  static const String _defaultDatabase = ''; // 不指定默认数据库，在测试中动态创建

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_MYSQL_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_MYSQL_PORT',
      defaultValue: '$_defaultPort',
    );
    return int.tryParse(portStr) ?? _defaultPort;
  }

  static String get username {
    return const String.fromEnvironment(
      'DBMASTER_MYSQL_USER',
      defaultValue: _defaultUser,
    );
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_MYSQL_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get database {
    return const String.fromEnvironment(
      'DBMASTER_MYSQL_DATABASE',
      defaultValue: _defaultDatabase,
    );
  }

  // ===== 从服务器: 3307 remote_user (SSL必须) =====
  static const int _altDefaultPort = 3307;

  static String get altHost => const String.fromEnvironment(
        'DBMASTER_MYSQL_ALT_HOST',
        defaultValue: '',
      );

  static int get altPort {
    final portStr = const String.fromEnvironment(
      'DBMASTER_MYSQL_ALT_PORT',
      defaultValue: '$_altDefaultPort',
    );
    return int.tryParse(portStr) ?? _altDefaultPort;
  }

  static String get altUsername => const String.fromEnvironment(
        'DBMASTER_MYSQL_ALT_USER',
        defaultValue: '',
      );

  static String get altPassword => const String.fromEnvironment(
        'DBMASTER_MYSQL_ALT_PASSWORD',
        defaultValue: '',
      );

  /// alt 通路必须 SSL（server 端账号策略，与凭据无关）。
  static bool get altUseSSL => true;

  /// 从服务器（3307 remote_user）是否已配置。
  static bool get isAltConfigured => altHost.isNotEmpty;

  // 兼容旧测试代码别名
  static String get remoteHost => altHost;
  static int get remotePort => altPort;
  static String get remoteUsername => altUsername;
  static String get remotePassword => altPassword;

  // ===== 从服务器: 3307 MySQL 5.7 (root) =====
  static const int _legacy57DefaultPort = 3307;

  static String get legacy57Host => const String.fromEnvironment(
        'DBMASTER_MYSQL57_HOST',
        defaultValue: '',
      );

  static int get legacy57Port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_MYSQL57_PORT',
      defaultValue: '$_legacy57DefaultPort',
    );
    return int.tryParse(portStr) ?? _legacy57DefaultPort;
  }

  static String get legacy57Username => const String.fromEnvironment(
        'DBMASTER_MYSQL57_USER',
        defaultValue: '',
      );

  static String get legacy57Password => const String.fromEnvironment(
        'DBMASTER_MYSQL57_PASSWORD',
        defaultValue: '',
      );

  /// 从服务器（3307 MySQL 5.7 root）是否已配置。
  static bool get isLegacy57Configured => legacy57Host.isNotEmpty;

  /// 生成唯一测试数据库名，避免并行测试冲突
  static String generateTestDatabaseName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'dbmaster_test_$timestamp';
  }

  /// 主环境是否已配置（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
