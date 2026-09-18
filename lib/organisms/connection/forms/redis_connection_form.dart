// C08 · Redis 连接表单模块（插件形）——「用最怪的类型打磨接口」的靶区
//（交接文档 §6.1；怪点：auth 三态、db index 非默认库语义）。
//
// - 认证三态：none / passwordOnly（AUTH pass，Redis<6.0）/ usernamePassword
//   （ACL，adapter 已支持 username 非空即 ACL——C08 前核实项结论）
// - db index 落 DbServer.database（adapter 解析 'db0'/'0' 双格式，现状
//   约定；表单统一存纯数字串）
// - SSL：本地直连时代零代码路径（不画 useSSL）；网关 TLS 透传已开
//  （showTlsToggle——server 侧驱动 TLS）；SSH 保留（网关模式 = server
//   侧隧道，配置随 draft 透传）
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../theme/app_theme.dart';
import 'connection_form_fields.dart';
import 'network_connection_form.dart';

class RedisConnectionFormSession extends NetworkConnectionFormSession {
  RedisConnectionFormSession(super.ctx) {
    final s = initial;
    if (s.username != null && s.password != null) {
      authMode = RedisAuthMode.usernamePassword;
    } else if (s.password != null) {
      authMode = RedisAuthMode.passwordOnly;
    } else {
      authMode = RedisAuthMode.none;
    }
    // adapter 侧 database 可能存 'db0' 或 '0'——回填统一还原为纯数字
    final raw = s.database ?? '';
    databaseController.text =
        raw.startsWith('db') ? raw.substring(2) : raw;
  }

  RedisAuthMode authMode = RedisAuthMode.none;

  @override
  String get usernameHint => 'default';

  @override
  bool get usernameRequired => false;

  @override
  bool get showUsername => authMode == RedisAuthMode.usernamePassword;

  @override
  bool get showPassword => authMode != RedisAuthMode.none;

  @override
  bool get showSslToggle => false;

  /// 网关 TLS 透传（server 侧驱动 TLS，经 draft extra 传 useTls 两键）。
  @override
  bool get showTlsToggle => true;

  @override
  String databaseLabel(AppLocalizations l10n) => l10n.connectionDbIndex;

  @override
  String get databaseHint => '0';

  @override
  List<Widget> buildPreCredentialFields(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      ConnectionDropdownField<RedisAuthMode>(
        label: l10n.connectionAuthSection,
        value: authMode,
        items: RedisAuthMode.values.map((mode) {
          return DropdownMenuItem<RedisAuthMode>(
            value: mode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _authModeLabel(mode, l10n),
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                Text(
                  _authModeDescription(mode, l10n),
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value == null) return;
          toggle(() {
            authMode = value;
            if (value == RedisAuthMode.none) {
              usernameController.text = '';
              passwordController.text = '';
            } else if (value == RedisAuthMode.passwordOnly) {
              usernameController.text = '';
            }
          });
        },
      ),
    ];
  }

  String _authModeLabel(RedisAuthMode mode, AppLocalizations l10n) {
    switch (mode) {
      case RedisAuthMode.none:
        return l10n.connectionRedisAuthNone;
      case RedisAuthMode.passwordOnly:
        return l10n.connectionRedisAuthPasswordOnly;
      case RedisAuthMode.usernamePassword:
        return l10n.connectionRedisAuthUsernamePassword;
    }
  }

  String _authModeDescription(RedisAuthMode mode, AppLocalizations l10n) {
    switch (mode) {
      case RedisAuthMode.none:
        return l10n.connectionRedisAuthNoneDesc;
      case RedisAuthMode.passwordOnly:
        return l10n.connectionRedisAuthPasswordOnlyDesc;
      case RedisAuthMode.usernamePassword:
        return l10n.connectionRedisAuthUsernamePasswordDesc;
    }
  }

  @override
  ({String? username, String? password}) resolveCredentials({
    required bool includePassword,
  }) {
    switch (authMode) {
      case RedisAuthMode.none:
        return (username: null, password: null);
      case RedisAuthMode.passwordOnly:
        return (
          username: null,
          password: includePassword ? passwordController.text : null,
        );
      case RedisAuthMode.usernamePassword:
        return (
          username: usernameController.text,
          password: includePassword ? passwordController.text : null,
        );
    }
  }
}

class RedisConnectionFormPlugin implements ConnectionFormPlugin {
  const RedisConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'redis-connection-plugin',
        supportedTypes: const {DatabaseType.redis},
        source: PluginSource.databaseType,
        icon: DatabaseType.redis.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      RedisConnectionFormSession(context);
}
