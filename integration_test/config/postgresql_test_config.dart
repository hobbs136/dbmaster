import 'dart:math';

/// PostgreSQL 集成测试配置
///
/// 默认指向 WSL 本地测试矩阵（127.0.0.1，PostgreSQL 17）——引擎/端口/账号
/// 表唯一来源见仓库外 `D:\workspace\dbmaster\test_db_local_wsl.txt`。
/// 口令不入库：经 `--dart-define=DBMASTER_PG_PASSWORD` 注入，缺省时真连
/// 认证失败；其它参数仍可用同名 dart-define 覆盖。
class PostgreSQLTestConfig {
  static const String _defaultHost = '127.0.0.1';
  static const int _defaultPort = 5432;
  static const String _defaultUser = 'postgres';
  static const String _defaultPassword = '';
  static const String _defaultDatabase = 'postgres'; // PostgreSQL 默认数据库

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_PG_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_PG_PORT',
      defaultValue: '$_defaultPort',
    );
    return int.tryParse(portStr) ?? _defaultPort;
  }

  static String get username {
    return const String.fromEnvironment(
      'DBMASTER_PG_USER',
      defaultValue: _defaultUser,
    );
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_PG_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get database {
    return const String.fromEnvironment(
      'DBMASTER_PG_DATABASE',
      defaultValue: _defaultDatabase,
    );
  }

  /// 生成唯一测试数据库名，避免并行测试冲突
  static String generateTestDatabaseName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return 'dbmaster_test_${timestamp}_$rand';
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
