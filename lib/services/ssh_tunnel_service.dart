import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import '../models/database_models.dart';
import '../utils/app_logger.dart';

/// SSH 隧道服务
///
/// 管理 SSH 连接和本地端口转发，使数据库连接可以通过 SSH 跳板主机安全传输。
class SshTunnelService {
  SSHClient? _client;
  ServerSocket? _localServer;
  Socket? _forwardSocket;
  StreamSubscription? _forwardSubscription;

  bool get isConnected => _client?.isClosed == false;

  int? _localPort;
  int? get localPort => _localPort;

  /// 建立 SSH 隧道
  ///
  /// [server] 包含 SSH 配置的数据库服务器
  /// [targetHost] 目标数据库主机（通常是 localhost 或数据库内网地址）
  /// [targetPort] 目标数据库端口
  ///
  /// 返回本地转发端口，数据库驱动应连接到此端口
  Future<int> connect({
    required DbServer server,
    required String targetHost,
    required int targetPort,
  }) async {
    if (_client != null && !_client!.isClosed) {
      AppLogger.d('SshTunnelService', 'SSH tunnel already exists, reusing');
      return _localPort!;
    }

    try {
      // 建立 SSH 连接
      _client = await _createSshClient(server);

      // 创建本地端口转发
      _localPort = await _createLocalForward(server, targetHost, targetPort);

      AppLogger.i(
        'SshTunnelService',
        'SSH tunnel established: localhost:$_localPort -> ${server.sshHost}:${server.sshPort} -> $targetHost:$targetPort',
      );

      return _localPort!;
    } catch (e) {
      await disconnect();
      throw Exception('SSH tunnel connection failed: $e');
    }
  }

  /// 关闭 SSH 隧道并释放资源
  Future<void> disconnect() async {
    AppLogger.d('SshTunnelService', 'Closing SSH tunnel');

    await _forwardSubscription?.cancel();
    _forwardSubscription = null;

    await _forwardSocket?.close();
    _forwardSocket = null;

    await _localServer?.close();
    _localServer = null;

    _client?.close();
    _client = null;

    _localPort = null;

    AppLogger.d('SshTunnelService', 'SSH tunnel closed');
  }

  /// 测试 SSH 连接（不建立隧道）
  Future<String?> testConnection(DbServer server) async {
    SSHClient? client;
    try {
      client = await _createSshClient(server);
      await client.run('echo ok');
      return null;
    } catch (e) {
      return 'SSH connection failed: $e';
    } finally {
      client?.close();
    }
  }

  /// 创建 SSH 客户端
  Future<SSHClient> _createSshClient(DbServer server) async {
    if (server.sshHost == null || server.sshHost!.isEmpty) {
      throw Exception('SSH host is required');
    }

    if (server.sshUsername == null || server.sshUsername!.isEmpty) {
      throw Exception('SSH username is required');
    }

    // Validate credentials before attempting connection
    if (server.sshAuthMode == SshAuthMode.privateKey) {
      if (server.sshPrivateKey == null || server.sshPrivateKey!.isEmpty) {
        throw Exception('SSH private key is required for key authentication');
      }
    } else {
      // Password auth (default)
      if (server.sshPassword == null || server.sshPassword!.isEmpty) {
        throw Exception('SSH password is required for password authentication');
      }
    }

    final socket = await SSHSocket.connect(
      server.sshHost!,
      server.sshPort ?? 22,
      timeout: Duration(seconds: server.timeoutSeconds),
    );

    late SSHClient client;

    if (server.sshAuthMode == SshAuthMode.privateKey) {
      try {
        // Debug: log private key info (without exposing the actual key)
        final keyPreview = server.sshPrivateKey!.length > 50
            ? '${server.sshPrivateKey!.substring(0, 30)}...${server.sshPrivateKey!.substring(server.sshPrivateKey!.length - 20)}'
            : server.sshPrivateKey!;
        AppLogger.d(
          'SshTunnelService',
          'Private key length: ${server.sshPrivateKey!.length}, preview: $keyPreview',
        );

        // Validate private key format
        final keyContent = server.sshPrivateKey!.trim();
        if (!keyContent.contains('-----BEGIN') ||
            !keyContent.contains('-----END')) {
          throw Exception('Invalid private key format: missing PEM headers');
        }
        if (!keyContent.contains('\n')) {
          AppLogger.w(
            'SshTunnelService',
            'Private key appears to be missing newline characters',
          );
        }

        final privateKeys = SSHKeyPair.fromPem(
          keyContent,
          server.sshPassphrase?.isNotEmpty == true
              ? server.sshPassphrase
              : null,
        );

        AppLogger.d(
          'SshTunnelService',
          'Attempting SSH key auth with ${privateKeys.length} key(s) for user ${server.sshUsername}',
        );

        client = SSHClient(
          socket,
          username: server.sshUsername!,
          identities: privateKeys,
          printDebug: (message) {
            if (message != null) AppLogger.d('SSH', message);
          },
        );
      } catch (e) {
        socket.destroy();
        throw Exception('Invalid SSH private key: $e');
      }
    } else {
      AppLogger.d(
        'SshTunnelService',
        'Attempting SSH password auth for user ${server.sshUsername}',
      );

      client = SSHClient(
        socket,
        username: server.sshUsername!,
        onPasswordRequest: () => server.sshPassword!,
        onUserInfoRequest: (request) {
          // Handle keyboard-interactive auth by providing the password for single prompt
          if (request.prompts.length == 1) {
            return [server.sshPassword!];
          }
          return null;
        },
        printDebug: (message) {
          if (message != null) AppLogger.d('SSH', message);
        },
      );
    }

    // 等待认证完成
    try {
      await client.authenticated;
      AppLogger.i('SshTunnelService', 'SSH authentication successful');
    } on SSHAuthFailError {
      socket.destroy();
      final authMethod = server.sshAuthMode == SshAuthMode.privateKey
          ? 'private key'
          : 'password';
      throw Exception(
        'SSH authentication failed for user "${server.sshUsername}" using $authMethod. '
        'Please verify:\n'
        '1. The username is correct\n'
        '2. The ${server.sshAuthMode == SshAuthMode.privateKey ? "private key" : "password"} is correct\n'
        '3. The SSH server allows $authMethod authentication',
      );
    } catch (e) {
      socket.destroy();
      rethrow;
    }

    return client;
  }

  /// 创建本地端口转发
  Future<int> _createLocalForward(
    DbServer server,
    String targetHost,
    int targetPort,
  ) async {
    // 绑定到本地随机端口
    _localServer = await ServerSocket.bind('127.0.0.1', 0);
    final localPort = _localServer!.port;

    AppLogger.d(
      'SshTunnelService',
      'Local forward server listening on port $localPort',
    );

    // 接受连接并通过 SSH 隧道转发
    _forwardSubscription = _localServer!.listen(
      (localSocket) async {
        try {
          final forward = await _client!.forwardLocal(targetHost, targetPort);

          // 双向转发数据
          localSocket.listen(
            (data) => forward.sink.add(data),
            onDone: () => forward.sink.close(),
            onError: (e) {
              AppLogger.e('SshTunnelService', 'Local socket error', e);
              forward.sink.close();
            },
          );

          forward.stream.listen(
            (data) => localSocket.add(data),
            onDone: () => localSocket.close(),
            onError: (e) {
              AppLogger.e('SshTunnelService', 'Forward stream error', e);
              localSocket.close();
            },
          );
        } catch (e) {
          AppLogger.e('SshTunnelService', 'Failed to forward connection', e);
          await localSocket.close();
        }
      },
      onError: (error, stackTrace) {
        AppLogger.e(
          'SshTunnelService',
          'Local server listen error',
          error,
          stackTrace,
        );
      },
    );

    return localPort;
  }
}

/// SSH 隧道管理器（用于管理多个隧道的单例）
class SshTunnelManager {
  static final SshTunnelManager _instance = SshTunnelManager._internal();
  factory SshTunnelManager() => _instance;
  SshTunnelManager._internal();

  final Map<String, SshTunnelService> _tunnels = {};

  /// 获取或创建指定连接的 SSH 隧道
  Future<int> getOrCreateTunnel({
    required String connectionId,
    required DbServer server,
    required String targetHost,
    required int targetPort,
  }) async {
    var tunnel = _tunnels[connectionId];

    if (tunnel == null || !tunnel.isConnected) {
      tunnel = SshTunnelService();
      _tunnels[connectionId] = tunnel;
    }

    return await tunnel.connect(
      server: server,
      targetHost: targetHost,
      targetPort: targetPort,
    );
  }

  /// 关闭指定连接的 SSH 隧道
  Future<void> closeTunnel(String connectionId) async {
    final tunnel = _tunnels.remove(connectionId);
    await tunnel?.disconnect();
  }

  /// 关闭所有 SSH 隧道
  Future<void> closeAllTunnels() async {
    final tunnels = _tunnels.values.toList();
    _tunnels.clear();

    for (final tunnel in tunnels) {
      await tunnel.disconnect();
    }
  }

  /// 检查指定连接是否有活跃的 SSH 隧道
  bool hasTunnel(String connectionId) {
    final tunnel = _tunnels[connectionId];
    return tunnel != null && tunnel.isConnected;
  }

  /// 获取指定连接的本地端口
  int? getLocalPort(String connectionId) {
    return _tunnels[connectionId]?.localPort;
  }
}
