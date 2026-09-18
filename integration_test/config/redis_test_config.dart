/// Redis 集成测试配置
///
/// 凭据不随仓库分发（开源剥离）：连接参数经 `--dart-define=DBMASTER_REDIS_*`
/// 注入；未提供时 [available] 为 false，消费方应跳过而非空跑。
class RedisTestConfig {
  static const String _defaultHost = '';
  static const int _defaultPort = 6379;
  static const String _defaultPassword = '';
  static const int _defaultDatabase = 15; // 使用 db15 避免干扰现有数据

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_REDIS_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_REDIS_PORT',
      defaultValue: '$_defaultPort',
    );
    return int.tryParse(portStr) ?? _defaultPort;
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_REDIS_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get database {
    final dbIndex = const String.fromEnvironment(
      'DBMASTER_REDIS_DATABASE',
      defaultValue: '$_defaultDatabase',
    );
    return 'db$dbIndex';
  }

  static int get dbIndex {
    final dbIndex = const String.fromEnvironment(
      'DBMASTER_REDIS_DATABASE',
      defaultValue: '$_defaultDatabase',
    );
    return int.tryParse(dbIndex) ?? _defaultDatabase;
  }

  /// 生成唯一测试键前缀，避免并行测试冲突
  static String generateTestKeyPrefix() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'dbmaster_test_$timestamp';
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
