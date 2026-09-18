/// Doris 集成测试配置
///
/// 凭据不随仓库分发（开源剥离）：连接参数经 `--dart-define=DBMASTER_DORIS_*`
/// 注入；未提供时 [available] 为 false，消费方应跳过而非空跑。
class DorisTestConfig {
  static const String _defaultHost = '';
  static const int _defaultFePort = 9030;
  static const int _defaultHttpPort = 8030;
  static const String _defaultUser = '';
  static const String _defaultPassword = '';
  static const String _defaultDatabase = '';

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_DORIS_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port => fePort;

  static int get fePort {
    final portStr = const String.fromEnvironment(
      'DBMASTER_DORIS_FE_PORT',
      defaultValue: '$_defaultFePort',
    );
    return int.tryParse(portStr) ?? _defaultFePort;
  }

  static int get httpPort {
    final portStr = const String.fromEnvironment(
      'DBMASTER_DORIS_HTTP_PORT',
      defaultValue: '$_defaultHttpPort',
    );
    return int.tryParse(portStr) ?? _defaultHttpPort;
  }

  static String get username {
    return const String.fromEnvironment(
      'DBMASTER_DORIS_USER',
      defaultValue: _defaultUser,
    );
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_DORIS_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get database {
    return const String.fromEnvironment(
      'DBMASTER_DORIS_DATABASE',
      defaultValue: _defaultDatabase,
    );
  }

  /// 生成唯一测试数据库名，避免并行测试冲突
  static String generateTestDatabaseName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'dbmaster_test_$timestamp';
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
