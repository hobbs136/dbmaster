// C08 · MongoDB 连接表单模块（插件形）。
//
// spec 044 四模式（Direct / Replica Set / Sharded / Advanced-URI）完整
// 保留——比原型稿的 Standard/URI 两模式更丰富且已端到端接线（adapter
// 策略 + 测试 + Pro 门控），重建以现状语义为准（c03 §1.1 同精神）。
// extra 键沿用 spec 044 既有键（见 ConnectionExtraKeys）；FR-007：密码
// 绝不进 URI/extra，仅经 DbServer.password。
// Advanced 模式下凭据字段改只读展示（值从连接串解析）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../providers/app_provider.dart';
import '../../../services/adapters/parsed_mongo_uri.dart';
import '../../../theme/app_theme.dart';
import 'connection_extra_keys.dart';
import 'connection_form_fields.dart';
import 'mongo_connection_mode.dart';
import 'network_connection_form.dart';

class MongodbConnectionFormSession extends NetworkConnectionFormSession {
  MongodbConnectionFormSession(super.ctx) {
    final extra = initial.extra;
    mode = MongoConnectionMode.fromExtra(extra?[ConnectionExtraKeys.mongoConnectionMode]);
    hostsController = TextEditingController(
      text: _joinHosts(extra?[ConnectionExtraKeys.mongoHosts]),
    );
    replicaSetController = TextEditingController(
      text: (extra?[ConnectionExtraKeys.mongoReplicaSet] as String?) ?? '',
    );
    connStringController = TextEditingController(
      text: (extra?[ConnectionExtraKeys.mongoConnectionString] as String?) ??
          '',
    );
  }

  late final TextEditingController hostsController;
  late final TextEditingController replicaSetController;
  late final TextEditingController connStringController;

  MongoConnectionMode mode = MongoConnectionMode.direct;

  bool get _isClusterMode => mode != MongoConnectionMode.direct;

  bool get _isAdvanced => mode == MongoConnectionMode.advanced;

  // ── 钩子覆写 ─────────────────────────────────────────────────

  @override
  String get usernameHint => 'admin';

  @override
  bool get showHostPort => !_isClusterMode;

  /// Advanced 模式：凭据来自连接串解析，字段改只读展示。
  @override
  bool get credentialsEnabled => !_isAdvanced;

  /// 网关 TLS 透传（server 侧驱动 TLS，经 draft extra 传 useTls 两键，
  /// 与集群四模式键合并同一段 extra）。
  @override
  bool get showTlsToggle => true;

  @override
  String databaseLabel(AppLocalizations l10n) => l10n.connectionAuthDatabase;

  @override
  String get databaseHint => 'admin';

  @override
  List<Widget> buildLeadingFields(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      ConnectionDropdownField<MongoConnectionMode>(
        label: l10n.connectionMongoMode,
        value: mode,
        items: [
          DropdownMenuItem(
            value: MongoConnectionMode.direct,
            child: Text(l10n.connectionMongoModeDirect),
          ),
          DropdownMenuItem(
            value: MongoConnectionMode.replicaSet,
            child: Text(l10n.connectionMongoModeReplicaSet),
          ),
          DropdownMenuItem(
            value: MongoConnectionMode.sharded,
            child: Text(l10n.connectionMongoModeSharded),
          ),
          DropdownMenuItem(
            value: MongoConnectionMode.advanced,
            child: Text(l10n.connectionMongoModeAdvanced),
          ),
        ],
        onChanged: (value) => _switchMode(context, value),
      ),
    ];
  }

  @override
  List<Widget> buildTypeFields(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      if (mode == MongoConnectionMode.replicaSet) ...[
        const SizedBox(height: AppDesignSystem.space3),
        Text(
          l10n.connectionMongoSeedHostsHint,
          style: TextStyle(
            color: context.themeColors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        ConnectionTextField(
          controller: hostsController,
          label: l10n.connectionMongoSeedHosts,
          hint: 'host1:27017\nhost2:27017\nhost3:27017',
          icon: LucideIcons.server,
          maxLines: 4,
          validator: (v) => _validateHostList(
            v ?? '',
            l10n.connectionMongoSeedHostsRequired,
            l10n.connectionMongoInvalidHostPort,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space3),
        ConnectionTextField(
          controller: replicaSetController,
          label: l10n.connectionMongoReplicaSetName,
          hint: 'rs0',
          icon: LucideIcons.share2,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? l10n.connectionMongoReplicaSetNameRequired
              : null,
        ),
      ],
      if (mode == MongoConnectionMode.sharded) ...[
        const SizedBox(height: AppDesignSystem.space3),
        Text(
          l10n.connectionMongoMongosHostsHint,
          style: TextStyle(
            color: context.themeColors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        ConnectionTextField(
          controller: hostsController,
          label: l10n.connectionMongoMongosHosts,
          hint: 'mongos1.example.net:27017\nmongos2.example.net:27017',
          icon: LucideIcons.server,
          maxLines: 4,
          validator: (v) => _validateHostList(
            v ?? '',
            l10n.connectionMongoMongosHostsRequired,
            l10n.connectionMongoInvalidHostPort,
          ),
        ),
      ],
      if (_isAdvanced) ...[
        const SizedBox(height: AppDesignSystem.space3),
        Text(
          l10n.connectionMongoConnectionStringHint,
          style: TextStyle(
            color: context.themeColors.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        ConnectionTextField(
          controller: connStringController,
          label: l10n.connectionMongoConnectionString,
          hint:
              'mongodb://user:pass@host:27017/?authSource=admin\nmongodb+srv://user:pass@cluster.mongodb.net/',
          icon: LucideIcons.link,
          maxLines: 4,
          validator: (v) {
            final raw = (v ?? '').trim();
            if (raw.isEmpty) {
              return l10n.connectionMongoConnectionStringRequired;
            }
            try {
              ParsedMongoUri.parse(raw);
              return null;
            } catch (_) {
              return l10n.connectionMongoConnectionStringInvalid;
            }
          },
        ),
      ],
    ];
  }

  void _switchMode(BuildContext context, MongoConnectionMode? value) {
    if (value == null || value == mode) return;
    // Pro 模式（非 direct）切换前过 tryMongoCluster 门控；false 则不改状态
    //（DropdownButton 自动回退原值）——spec 045 接缝，门控当前整体禁用。
    if (value != MongoConnectionMode.direct &&
        !context.read<AppProvider>().tryMongoCluster(
              'mongo_cluster_${DateTime.now().millisecondsSinceEpoch}',
            )) {
      return;
    }
    toggle(() {
      mode = value;
      // 切模式清空各模式字段，防 replicaSet↔sharded 共享 hostsController
      // 致种子/路由数据跨拓扑泄漏（spec 044 既有防御）
      hostsController.clear();
      replicaSetController.clear();
      connStringController.clear();
    });
  }

  // ── 列表解析/校验（spec 044 契约）─────────────────────────────

  List<String> _parseHostList(String raw) => raw
      .split(RegExp(r'[\n,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String? _validateHostList(String v, String emptyMsg, String invalidMsg) {
    final hosts = _parseHostList(v);
    if (hosts.isEmpty) return emptyMsg;
    for (final h in hosts) {
      if (!_isValidHostPort(h)) return invalidMsg;
    }
    return null;
  }

  /// host 或 host:port（端口须为整数）；IPv6/多冒号暂不支持。
  bool _isValidHostPort(String hp) {
    final parts = hp.split(':');
    if (parts.length == 1) return parts.first.trim().isNotEmpty;
    if (parts.length == 2) {
      return parts.first.trim().isNotEmpty &&
          int.tryParse(parts[1].trim()) != null;
    }
    return false;
  }

  String _joinHosts(Object? raw) {
    if (raw is! List) return '';
    return raw.map((e) => e.toString()).join('\n');
  }

  /// 拆 "host" / "host:port" → (host, port)，端口缺失用默认端口。
  (String, int)? _splitHostPort(String hp) {
    final parts = hp.split(':');
    final host = parts.firstOrNull?.trim() ?? '';
    if (host.isEmpty) return null;
    final port = parts.length >= 2 ? int.tryParse(parts[1].trim()) : null;
    return (host, port ?? type.defaultPort);
  }

  /// 集群三模式下派生 (host, port) 供侧栏显示用（host/port 行已隐藏）。
  /// Direct 返回 null（走表单字段）。
  (String, int)? _displayHostPort() {
    switch (mode) {
      case MongoConnectionMode.replicaSet:
      case MongoConnectionMode.sharded:
        final first = _parseHostList(hostsController.text).firstOrNull;
        if (first == null) return null;
        return _splitHostPort(first);
      case MongoConnectionMode.advanced:
        final raw = connStringController.text.trim();
        if (raw.isEmpty) return null;
        try {
          final p = ParsedMongoUri.parse(raw);
          final uri = p.credentialFreeUri;
          final afterScheme = uri.contains('://')
              ? uri.substring(uri.indexOf('://') + 3)
              : uri;
          final delim = afterScheme.indexOf(RegExp(r'[/?#]'));
          final authority =
              delim < 0 ? afterScheme : afterScheme.substring(0, delim);
          final first = authority.split(',').first.trim();
          if (first.isEmpty) return null;
          return _splitHostPort(first);
        } catch (_) {
          return null;
        }
      case MongoConnectionMode.direct:
        return null;
    }
  }

  // ── collect 终值 ─────────────────────────────────────────────

  @override
  ({String host, int port}) resolveHostPort() {
    final hp = _displayHostPort();
    if (hp != null) return (host: hp.$1, port: hp.$2);
    return super.resolveHostPort();
  }

  @override
  ({String? username, String? password}) resolveCredentials({
    required bool includePassword,
  }) {
    // Advanced 模式：user/password 来自粘贴串解析（FR-007：密码仅进
    // DbServer.password）；解析失败保持字段值（校验已拦截）。
    if (_isAdvanced) {
      final raw = connStringController.text.trim();
      if (raw.isNotEmpty) {
        try {
          final p = ParsedMongoUri.parse(raw);
          return (
            username: p.username,
            password: includePassword ? p.password : null,
          );
        } catch (_) {
          // 字段校验已展示错误；collect 返回字段值兜底
        }
      }
    }
    return super.resolveCredentials(includePassword: includePassword);
  }

  @override
  Map<String, dynamic>? buildExtra() {
    switch (mode) {
      case MongoConnectionMode.direct:
        return null; // 向后兼容：等价于旧单 host 连接
      case MongoConnectionMode.replicaSet:
        return <String, dynamic>{
          ConnectionExtraKeys.mongoConnectionMode: mode.extraValue,
          ConnectionExtraKeys.mongoHosts: _parseHostList(hostsController.text),
          ConnectionExtraKeys.mongoReplicaSet:
              replicaSetController.text.trim(),
        };
      case MongoConnectionMode.advanced:
        final raw = connStringController.text.trim();
        if (raw.isEmpty) return null;
        final p = ParsedMongoUri.parse(raw);
        return <String, dynamic>{
          ConnectionExtraKeys.mongoConnectionMode: 'advanced',
          ConnectionExtraKeys.mongoConnectionString: p.credentialFreeUri,
        };
      case MongoConnectionMode.sharded:
        return <String, dynamic>{
          ConnectionExtraKeys.mongoConnectionMode: mode.extraValue,
          ConnectionExtraKeys.mongoHosts: _parseHostList(hostsController.text),
        };
    }
  }

  @override
  void dispose() {
    hostsController.dispose();
    replicaSetController.dispose();
    connStringController.dispose();
    super.dispose();
  }
}

class MongodbConnectionFormPlugin implements ConnectionFormPlugin {
  const MongodbConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'mongodb-connection-plugin',
        supportedTypes: const {DatabaseType.mongodb},
        source: PluginSource.databaseType,
        icon: DatabaseType.mongodb.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      MongodbConnectionFormSession(context);
}
