// C08 · per-type 连接表单 —— 网络型数据库表单会话基类。
//
// 承载所有网络型类型（MySQL/PG/Mongo/Redis/Doris/TD/CH/SS）共享的表单段：
// host/port、凭据、默认库、保存密码、高级折叠（超时/SSL/自动重连/只读）、
// SSH 隧道（全类型统一入口，c03 §2 契约结论 2）。类型差异经 protected
// 钩子注入（见各 hook 注释），子类不得重写 build/collect 本体。
//
// 会话 = ChangeNotifier：开关态变更经 notifyListeners 驱动 ListenableBuilder
// 重建（控制器自带监听，无需额外通知）——满足 C01a「无状态插件 + 会话持
// 可变资源」的生命周期契约。
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../theme/app_theme.dart';
import 'connection_form_fields.dart';

/// 网络型连接表单会话基类（C08）。
abstract class NetworkConnectionFormSession extends ChangeNotifier
    implements ConnectionFormSession {
  NetworkConnectionFormSession(this.ctx) {
    final s = ctx.draft.value;
    hostController = TextEditingController(
      text: s.host.isEmpty ? 'localhost' : s.host,
    );
    portController = TextEditingController(text: s.port.toString());
    usernameController = TextEditingController(text: s.username ?? '');
    passwordController = TextEditingController(text: s.password ?? '');
    databaseController = TextEditingController(text: s.database ?? '');
    timeoutController =
        TextEditingController(text: (s.timeoutSeconds).toString());
    sshHostController = TextEditingController(text: s.sshHost ?? '');
    sshPortController =
        TextEditingController(text: (s.sshPort ?? 22).toString());
    sshUsernameController = TextEditingController(text: s.sshUsername ?? '');
    sshPasswordController = TextEditingController(text: s.sshPassword ?? '');
    sshPrivateKeyController =
        TextEditingController(text: s.sshPrivateKey ?? '');
    sshPassphraseController =
        TextEditingController(text: s.sshPassphrase ?? '');

    savePassword = s.password?.isNotEmpty ?? false;
    useSSL = s.useSSL;
    useTls = s.useTls;
    tlsInsecure = s.tlsInsecure;
    autoReconnect = s.autoReconnect;
    readOnly = s.readOnly;
    useSshTunnel = s.useSshTunnel;
    sshAuthMode = s.sshAuthMode ?? SshAuthMode.password;
  }

  @protected
  final ConnectionFormPluginContext ctx;

  DatabaseType get type => ctx.type;

  DbServer get initial => ctx.draft.value;

  // ── 控制器（dispose 统一释放）────────────────────────────────────
  late final TextEditingController hostController;
  late final TextEditingController portController;
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  late final TextEditingController databaseController;
  late final TextEditingController timeoutController;
  late final TextEditingController sshHostController;
  late final TextEditingController sshPortController;
  late final TextEditingController sshUsernameController;
  late final TextEditingController sshPasswordController;
  late final TextEditingController sshPrivateKeyController;
  late final TextEditingController sshPassphraseController;

  // ── 开关态（子类/宿主经带 notify 的 setter 变更）──────────────────
  bool savePassword = true;
  bool useSSL = false;

  /// 网关 TLS 透传（Redis/Mongo/TDengine）：与 useSSL（本地直连时代开关）
  /// 独立——这两键经网关 draft 的 extra 交给 server 侧组 TLS 连接。
  bool useTls = false;
  bool tlsInsecure = false;
  bool autoReconnect = false;
  bool readOnly = false;
  bool showAdvanced = false;
  bool useSshTunnel = false;
  SshAuthMode sshAuthMode = SshAuthMode.password;

  @protected
  void toggle(void Function() mutate) {
    mutate();
    notifyListeners();
  }

  // ── 子类钩子 ───────────────────────────────────────────────────

  /// host/port 行是否渲染（Mongo 集群三模式隐藏，凭据走集群字段）。
  bool get showHostPort => true;

  /// 用户名字段是否渲染（Redis 无认证态隐藏）。
  bool get showUsername => true;

  /// 密码字段是否渲染（Redis 无认证态隐藏）。
  bool get showPassword => true;

  /// 用户名是否必填（Redis 可选）。
  bool get usernameRequired => true;

  /// 凭据字段是否可编辑（Mongo advanced 模式改为从连接串解析，只读展示）。
  bool get credentialsEnabled => true;

  /// 数据库字段 label（Redis=数据库索引、Mongo=认证数据库）。
  String databaseLabel(AppLocalizations l10n) =>
      l10n.connectionDefaultDatabase;

  /// 数据库字段 hint。
  String get databaseHint => '(Optional)';

  /// SSL 开关是否渲染（CH/TD 链路不透传 SSL——死 UI 不画，c03 §1.2-14 拍板）。
  bool get showSslToggle => true;

  /// 网关 TLS 透传开关是否渲染（Redis/Mongo/TDengine 三类型——server 侧
  /// 驱动 TLS；其余类型网关暂无 TLS 字段，不画死 UI）。
  bool get showTlsToggle => false;

  /// SSH 隧道段是否渲染（全网络类型都是网关壳——SSH 语义为 server 侧
  /// 隧道，配置随网关 draft 透传）。
  bool get showSshSection => true;

  /// 类型专属字段（凭据/数据库之后、高级折叠之前）。
  List<Widget> buildTypeFields(BuildContext context) => const <Widget>[];

  /// host/port 行之前的类型专属字段（Mongo 连接模式选择器——模式决定
  /// host/port 行是否渲染）。
  List<Widget> buildLeadingFields(BuildContext context) => const <Widget>[];

  /// host/port 行与凭据之间的类型专属字段（Redis 认证三态选择器——
  /// 认证态决定凭据字段可见性）。
  List<Widget> buildPreCredentialFields(BuildContext context) =>
      const <Widget>[];

  /// 高级折叠区内、通用开关之后的类型专属项（charset/timezone 等）。
  List<Widget> buildAdvancedFields(BuildContext context) => const <Widget>[];

  /// collect 时覆写 charset（MySQL/Doris 下拉值）。
  String? get charsetValue => null;

  /// collect 时覆写 timezone（MySQL/Doris 下拉值）。
  String? get timezoneValue => null;

  /// collect 时覆写 host/port 终值（Mongo 集群模式派生首节点）。
  ({String host, int port}) resolveHostPort() => (
        host: hostController.text,
        port: int.tryParse(portController.text) ?? type.defaultPort,
      );

  /// collect 时覆写凭据终值（Redis 三态、Mongo advanced 解析）。
  ({String? username, String? password}) resolveCredentials({
    required bool includePassword,
  }) => (
        username: usernameController.text,
        password: includePassword ? passwordController.text : null,
      );

  /// collect 时写入 extra（null = 不写）。
  Map<String, dynamic>? buildExtra() => null;

  // ── ConnectionFormSession 实现 ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) => buildFields(context),
    );
  }

  @protected
  Widget buildFields(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._withGap(buildLeadingFields(context)),
        if (showHostPort) ...[
          ConnectionHostPortFields(
            hostController: hostController,
            portController: portController,
            portHint: type.defaultPort.toString(),
          ),
          const SizedBox(height: AppDesignSystem.space4),
        ],
        ..._withGap(buildPreCredentialFields(context)),
        if (showUsername) ...[
          ConnectionTextField(
            controller: usernameController,
            label: l10n.connectionUsername,
            hint: usernameHint,
            icon: LucideIcons.user,
            enabled: credentialsEnabled,
            validator: usernameRequired
                ? (v) =>
                    v?.isEmpty ?? true ? l10n.connUsernameRequired : null
                : null,
          ),
          const SizedBox(height: AppDesignSystem.space4),
        ],
        if (showPassword) ...[
          ConnectionPasswordField(
            controller: passwordController,
            label: l10n.connectionPassword,
          ),
          const SizedBox(height: AppDesignSystem.space4),
        ],
        ConnectionTextField(
          controller: databaseController,
          label: databaseLabel(l10n),
          hint: databaseHint,
          icon: LucideIcons.database,
        ),
        const SizedBox(height: AppDesignSystem.space3),
        CheckboxListTile(
          value: savePassword,
          onChanged: (v) => toggle(() => savePassword = v ?? true),
          title: Text(
            l10n.connectionSavePassword,
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: 13,
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: context.themeColors.accentBlue,
        ),
        ..._withGap(buildTypeFields(context)),
        const SizedBox(height: AppDesignSystem.space2),
        _buildAdvancedSection(context),
        if (showSshSection) ...[
          const SizedBox(height: AppDesignSystem.space2),
          _buildSshSection(context),
        ],
      ],
    );
  }

  /// 钩子字段列表统一追加段间距（空列表无残留间距）。
  @protected
  List<Widget> _withGap(List<Widget> fields) {
    if (fields.isEmpty) return fields;
    return [...fields, const SizedBox(height: AppDesignSystem.space4)];
  }

  /// 用户名输入框 hint（类型默认值展示）。
  @protected
  String get usernameHint => 'root';

  Widget _buildAdvancedSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => toggle(() => showAdvanced = !showAdvanced),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
            child: Row(
              children: [
                Icon(
                  showAdvanced
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  color: context.themeColors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: AppDesignSystem.space1),
                Text(
                  l10n.connectionAdvancedOptions,
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showAdvanced) ...[
          const SizedBox(height: AppDesignSystem.space2),
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              border: Border.all(color: context.themeColors.borderLight),
            ),
            child: Column(
              children: [
                ConnectionTextField(
                  controller: timeoutController,
                  label: l10n.connectionTimeout,
                  hint: '30',
                  icon: LucideIcons.timer,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppDesignSystem.space3),
                if (showSslToggle) ...[
                  ConnectionSwitchTile(
                    title: l10n.connectionUseSSL,
                    subtitle: l10n.connectionEnableSecureConnection,
                    value: useSSL,
                    onChanged: (v) => toggle(() => useSSL = v),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                ],
                if (showTlsToggle) ..._buildTlsSection(context),
                ConnectionSwitchTile(
                  title: l10n.connectionAutoReconnect,
                  subtitle: l10n.connectionAutoReconnectDesc,
                  value: autoReconnect,
                  onChanged: (v) => toggle(() => autoReconnect = v),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                ConnectionSwitchTile(
                  title: l10n.connectionReadOnlyMode,
                  subtitle: l10n.connectionReadOnlyModeDesc,
                  value: readOnly,
                  onChanged: (v) => toggle(() => readOnly = v),
                ),
                ...buildAdvancedFields(context),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 网关 TLS 透传段（Redis/Mongo/TDengine）：开关 + 「忽略证书校验」
  /// 子选项（仅开关开启时可交互；关闭时一并复位，避免残留半开状态）。
  List<Widget> _buildTlsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      ConnectionSwitchTile(
        title: l10n.connectionUseTls,
        subtitle: l10n.connectionUseTlsDesc,
        value: useTls,
        onChanged: (v) => toggle(() {
          useTls = v;
          if (!v) tlsInsecure = false;
        }),
      ),
      const SizedBox(height: AppDesignSystem.space2),
      if (useTls) ...[
        ConnectionSwitchTile(
          title: l10n.connectionTlsInsecure,
          subtitle: l10n.connectionTlsInsecureDesc,
          value: tlsInsecure,
          onChanged: (v) => toggle(() => tlsInsecure = v),
        ),
        const SizedBox(height: AppDesignSystem.space2),
      ],
    ];
  }

  Widget _buildSshSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConnectionSwitchTile(
          title: 'SSH Tunnel',
          // 全网络类型均为网关壳——隧道由 server 侧建立（配置随 draft
          // 透传），提示文案与本地直连时代的 jump host 语义区分。
          subtitle: l10n.connectionSshSubtitleGateway,
          value: useSshTunnel,
          onChanged: (v) => toggle(() => useSshTunnel = v),
        ),
        if (useSshTunnel) ...[
          const SizedBox(height: AppDesignSystem.space3),
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              border: Border.all(color: context.themeColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConnectionSectionLabel(l10n.connectionSshConfig),
                const SizedBox(height: AppDesignSystem.space3),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ConnectionTextField(
                        controller: sshHostController,
                        label: l10n.connectionSshHost,
                        hint: 'jump.example.com',
                        icon: LucideIcons.monitor,
                        validator: (v) => v?.isEmpty ?? true
                            ? l10n.connSshHostRequired
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space3),
                    Expanded(
                      flex: 1,
                      child: ConnectionTextField(
                        controller: sshPortController,
                        label: l10n.connectionPort,
                        hint: '22',
                        icon: LucideIcons.network,
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v?.isEmpty ?? true) return l10n.connRequired;
                          if (int.tryParse(v!) == null) {
                            return l10n.connInvalidPort;
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space3),
                ConnectionTextField(
                  controller: sshUsernameController,
                  label: l10n.connectionSshUsername,
                  hint: 'user',
                  icon: LucideIcons.user,
                  validator: (v) =>
                      v?.isEmpty ?? true ? l10n.connUsernameRequired : null,
                ),
                const SizedBox(height: AppDesignSystem.space3),
                Text(
                  l10n.connectionAuthSection,
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                ConnectionDropdownField<SshAuthMode>(
                  value: sshAuthMode,
                  items: SshAuthMode.values.map((mode) {
                    return DropdownMenuItem<SshAuthMode>(
                      value: mode,
                      child: Text(
                        sshAuthModeLabel(mode, l10n),
                        style: TextStyle(
                          color: context.themeColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      toggle(() => sshAuthMode = value);
                    }
                  },
                ),
                const SizedBox(height: AppDesignSystem.space3),
                if (sshAuthMode == SshAuthMode.password)
                  ConnectionPasswordField(
                    controller: sshPasswordController,
                    label: l10n.connectionSshPassword,
                  )
                else ...[
                  ConnectionTextField(
                    controller: sshPrivateKeyController,
                    label: l10n.connectionPrivateKey,
                    hint: l10n.connectionPasteKeyHint,
                    icon: LucideIcons.keyRound,
                    maxLines: 6,
                    suffix: IconButton(
                      icon: Icon(
                        LucideIcons.folderOpen,
                        size: 18,
                        color: context.themeColors.textMuted,
                      ),
                      onPressed: () => _pickSshKeyFile(context),
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  ConnectionPasswordField(
                    controller: sshPassphraseController,
                    label: l10n.connectionKeyPassphrase,
                    hint: l10n.connectionPassphrase,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// SSH 认证方式的本地化显示名。
  @protected
  String sshAuthModeLabel(SshAuthMode mode, AppLocalizations l10n) {
    switch (mode) {
      case SshAuthMode.password:
        return l10n.connectionSshAuthPassword;
      case SshAuthMode.privateKey:
        return l10n.connectionSshAuthPrivateKey;
    }
  }

  Future<void> _pickSshKeyFile(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: l10n.connectionSelectSshKey,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    String? content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content != null) {
      sshPrivateKeyController.text = content;
    }
  }

  @override
  DbServer? collect({bool forSave = false}) {
    final includePassword = !forSave || savePassword;
    final creds = resolveCredentials(includePassword: includePassword);
    final hp = resolveHostPort();
    final v = ctx.draft.value;
    return DbServer(
      id: v.id,
      name: v.name,
      type: type,
      host: hp.host,
      port: hp.port,
      username: creds.username,
      password: creds.password,
      database:
          databaseController.text.isNotEmpty ? databaseController.text : null,
      useSSL: useSSL,
      useTls: useTls,
      tlsInsecure: tlsInsecure,
      timeoutSeconds: int.tryParse(timeoutController.text) ?? 30,
      autoReconnect: autoReconnect,
      charset: charsetValue ?? 'utf8mb4',
      timezone: timezoneValue,
      groupId: v.groupId,
      lastConnected: v.lastConnected,
      environment: v.environment,
      readOnly: readOnly,
      useSshTunnel: useSshTunnel,
      sshHost: useSshTunnel ? sshHostController.text : null,
      sshPort:
          useSshTunnel ? (int.tryParse(sshPortController.text) ?? 22) : null,
      sshUsername: useSshTunnel ? sshUsernameController.text : null,
      sshAuthMode: useSshTunnel ? sshAuthMode : null,
      sshPassword: useSshTunnel && sshAuthMode == SshAuthMode.password
          ? sshPasswordController.text
          : null,
      sshPrivateKey: useSshTunnel && sshAuthMode == SshAuthMode.privateKey
          ? sshPrivateKeyController.text
          : null,
      sshPassphrase: useSshTunnel && sshAuthMode == SshAuthMode.privateKey
          ? sshPassphraseController.text
          : null,
      extra: buildExtra(),
    );
  }

  @override
  void dispose() {
    hostController.dispose();
    portController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    databaseController.dispose();
    timeoutController.dispose();
    sshHostController.dispose();
    sshPortController.dispose();
    sshUsernameController.dispose();
    sshPasswordController.dispose();
    sshPrivateKeyController.dispose();
    sshPassphraseController.dispose();
    super.dispose();
  }
}

/// 通用网络表单会话：无类型专属字段的兜底形态（SQL Server 在 C20 前走此
/// 形态，行为与重建前表单对 SS 类型等价）。
class GenericNetworkConnectionFormSession extends NetworkConnectionFormSession {
  GenericNetworkConnectionFormSession(super.ctx);

  @override
  String get usernameHint => 'sa';
}

/// 通用兜底表单插件（宿主在注册表无命中时使用，不入注册表——避免与
/// 类型专属插件冲突；SQL Server 专属表单 C20 落地后自然替代）。
class GenericConnectionFormPlugin implements ConnectionFormPlugin {
  const GenericConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'core-connection-form',
        source: PluginSource.core,
        icon: LucideIcons.plug,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      GenericNetworkConnectionFormSession(context);
}
