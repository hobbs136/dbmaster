import 'dart:math';

/// Doris 集成测试配置
///
/// 默认指向 WSL 本地测试矩阵（127.0.0.1，Doris 3.0 FE 9030 / HTTP 8030）——
/// 引擎/端口/账号表唯一来源见仓库外
/// `D:\workspace\dbmaster\test_db_local_wsl.txt`。口令不入库：经
/// `--dart-define=DBMASTER_DORIS_PASSWORD` 注入（WSL root 为无口令，
/// 缺省即匹配）；其它参数仍可用同名 dart-define 覆盖。
class DorisTestConfig {
  static const String _defaultHost = '127.0.0.1';
  static const int _defaultFePort = 9030;
  static const int _defaultHttpPort = 8030;
  static const String _defaultUser = 'root';
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
    final rand = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return 'dbmaster_test_${timestamp}_$rand';
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
