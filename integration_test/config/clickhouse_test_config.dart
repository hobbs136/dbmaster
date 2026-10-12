/// ClickHouse 集成测试配置
///
/// 默认指向 WSL 本地测试矩阵（127.0.0.1，CH MySQL 兼容口 9004 非 HTTP
/// 8123）——引擎/端口/账号表唯一来源见仓库外
/// `D:\workspace\dbmaster\test_db_local_wsl.txt`。口令不入库：经
/// `--dart-define=DBMASTER_CH_PASSWORD` 注入，缺省时真连认证失败；
/// 其它参数仍可用同名 dart-define 覆盖。
/// 注意：测试账号无 DROP 授权——测试数据清理用 TRUNCATE
/// （与 server 侧 gw_clickhouse e2e 同约定）。
class ClickhouseTestConfig {
  static const String _defaultHost = '127.0.0.1';
  static const int _defaultPort = 9004; // CH MySQL 兼容口（非 HTTP 8123）
  static const String _defaultUser = 'ch_test';
  static const String _defaultPassword = '';
  static const String _defaultDatabase = 'ch_test_db';

  static String get host {
    return const String.fromEnvironment(
      'DBMASTER_CH_HOST',
      defaultValue: _defaultHost,
    );
  }

  static int get port {
    final portStr = const String.fromEnvironment(
      'DBMASTER_CH_PORT',
      defaultValue: '$_defaultPort',
    );
    return int.tryParse(portStr) ?? _defaultPort;
  }

  static String get username {
    return const String.fromEnvironment(
      'DBMASTER_CH_USER',
      defaultValue: _defaultUser,
    );
  }

  static String get password {
    return const String.fromEnvironment(
      'DBMASTER_CH_PASSWORD',
      defaultValue: _defaultPassword,
    );
  }

  static String get database {
    return const String.fromEnvironment(
      'DBMASTER_CH_DATABASE',
      defaultValue: _defaultDatabase,
    );
  }

  /// 是否已配置测试环境（host 经 dart-define 提供即视为可用）。
  static bool get available => host.isNotEmpty;

  /// 检查是否配置了测试环境（兼容旧名，等价于 [available]）。
  static bool get isConfigured => available;
}
