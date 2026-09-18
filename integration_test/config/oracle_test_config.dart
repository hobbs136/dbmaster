/// Oracle 集成测试配置
///
/// 凭据不随仓库分发（开源剥离）：连接参数经 `--dart-define=DBMASTER_ORACLE_*`
/// 注入；未提供时 [available] 为 false，消费方应跳过而非空跑。
class OracleTestConfig {
  static const String _defaultHost = '';
  static const int _defaultPort = 1521;
  static const String _defaultUser = '';
  static const String _defaultPassword = '';
  static const String _defaultSid = 'FREE';
  static const String _defaultPdb = 'FREEPDB1';
  static const String _defaultServiceName = 'FREEPDB1';

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_ORACLE_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_ORACLE_PORT',
      defaultValue: '$_defaultPort',
    );
    return int.tryParse(portStr) ?? _defaultPort;
  }

  static String get username {
    return const String.fromEnvironment(
      'DBMASTER_ORACLE_USER',
      defaultValue: _defaultUser,
    );
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_ORACLE_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get sid {
    return const String.fromEnvironment(
      'DBMASTER_ORACLE_SID',
      defaultValue: _defaultSid,
    );
  }

  static String get pdb {
    return const String.fromEnvironment(
      'DBMASTER_ORACLE_PDB',
      defaultValue: _defaultPdb,
    );
  }

  static String get serviceName {
    return const String.fromEnvironment(
      'DBMASTER_ORACLE_SERVICE_NAME',
      defaultValue: _defaultServiceName,
    );
  }

  /// 生成唯一测试表空间名/用户，避免并行测试冲突
  static String generateTestUserName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'DBMASTER_TEST_$timestamp';
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
