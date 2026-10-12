import 'dart:math';

/// TDengine 集成测试配置
///
/// 默认指向 WSL 本地测试矩阵（127.0.0.1，TDengine 3.3 REST 6041）——
/// 引擎/端口/账号表唯一来源见仓库外
/// `D:\workspace\dbmaster\test_db_local_wsl.txt`。口令不入库：经
/// `--dart-define=DBMASTER_TDENGINE_PASSWORD` 注入，缺省时真连认证
/// 失败；其它参数仍可用同名 dart-define 覆盖。
class TDengineTestConfig {
  static const String _defaultHost = '127.0.0.1';
  static const int _defaultPort = 6041;
  static const String _defaultUser = 'root';
  static const String _defaultPassword = '';
  static const String _defaultDatabase = 'test';

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_TDENGINE_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_TDENGINE_PORT',
      defaultValue: '$_defaultPort',
    );
    return int.tryParse(portStr) ?? _defaultPort;
  }

  static String get username {
    return const String.fromEnvironment(
      'DBMASTER_TDENGINE_USER',
      defaultValue: _defaultUser,
    );
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_TDENGINE_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get database {
    return const String.fromEnvironment(
      'DBMASTER_TDENGINE_DATABASE',
      defaultValue: _defaultDatabase,
    );
  }

  /// 生成唯一测试数据库名，避免并行测试冲突
  static String generateTestDatabaseName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return 'dbmaster_test_${timestamp}_$rand';
  }

  /// 生成唯一超级表名
  static String generateTestSuperTableName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'st_test_$timestamp';
  }

  /// 生成唯一子表名
  static String generateTestSubTableName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 't_test_$timestamp';
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
