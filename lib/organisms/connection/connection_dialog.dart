// C08 · 连接对话框 —— 两栏结构壳（原型 connection-*.html：左侧类型导航 +
// 右侧动态表单）。per-type 表单经 PluginRegistry 分发（C01a 框架的宿主），
// 头部字段（名称/环境）与测试/保存/取消由本壳持有；SQL Server 在 C20 前
// 走通用兜底表单（GenericConnectionFormPlugin）。
// 旧的单文件 per-type 分支实现已由本壳取代；SQLite 独立对话框与 Mongo
// 子组件的收编删除见 C09。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../plugins/bootstrap.dart';
import '../../plugins/connection_form_plugin.dart';
import '../../plugins/plugin_descriptor.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../atoms/app_loading.dart';
import 'connect_failure_dialog.dart';
import 'connection_export_import_dialog.dart';
import 'error_boundary.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../models/connection_failure.dart';
import '../../theme/app_colors.dart';
import 'forms/connection_form_fields.dart';
import 'forms/network_connection_form.dart';
import 'forms/sqlite_connection_form.dart';

/// UIRV-B2（软门）· 表单测试状态：
/// dirty = 未测试/草稿已变更（Test 主动作，Save 次样式但始终可点）；
/// testing = 测试进行中（主动作 loading 禁点防重）；
/// tested = 测试通过（摘要条 + Save 接手主动作 + Test 变「重新测试」）。
/// 测试失败不走独立态——结构化面（ConnectFailureDialog）呈现后回 dirty。
enum _ConnectionTestState { dirty, testing, tested }

class ConnectionDialog extends StatefulWidget {
  final DbServer? existingServer;

  const ConnectionDialog({super.key, this.existingServer});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final ConnectionDraft _draft;
  late DatabaseType _selectedType;
  ConnectionFormSession? _session;
  PluginDescriptor? _sessionDescriptor;
  bool _isLoading = false;

  // UIRV-B2（软门）：测试状态机与最近一次测试的草稿快照/结构化失败。
  _ConnectionTestState _testState = _ConnectionTestState.dirty;
  DbServer? _lastTestedServer;
  ConnectionFailure? _lastFailure;

  @override
  void initState() {
    super.initState();
    final server = widget.existingServer;
    _selectedType = server?.type ?? DatabaseType.mysql;
    _draft = ConnectionDraft(
      server ??
          DbServer(
            id: '',
            name: '',
            type: _selectedType,
            host: 'localhost',
            port: _selectedType.defaultPort,
            username: _defaultUsername(_selectedType),
          ),
    );
    _nameController = TextEditingController(text: server?.name ?? '');
    _draft.addListener(_invalidateTestState);
    _createSession();
  }

  /// 脏态失效（UIRV-B2）：任意影响连接的草稿/表单字段变更 → 回 dirty，
  /// 旧测试态失效、成功摘要条清除。按字段来源分两条监听：
  /// ① `_draft`（名称/环境/类型切换）；② 表单会话（host/port/凭据/
  /// 文件路径等 per-type 控制器与开关）——会话接口只读消费，不改其契约。
  void _invalidateTestState() {
    if (_testState == _ConnectionTestState.dirty) return;
    setState(() {
      _testState = _ConnectionTestState.dirty;
      _lastTestedServer = null;
    });
  }

  void _attachSessionListeners() {
    final session = _session;
    if (session == null) return;
    if (session is ChangeNotifier) {
      (session as ChangeNotifier).addListener(_invalidateTestState);
    }
    if (session is NetworkConnectionFormSession) {
      for (final controller in [
        session.hostController,
        session.portController,
        session.usernameController,
        session.passwordController,
        session.databaseController,
        session.timeoutController,
        session.sshHostController,
        session.sshPortController,
        session.sshUsernameController,
        session.sshPasswordController,
        session.sshPrivateKeyController,
        session.sshPassphraseController,
      ]) {
        controller.addListener(_invalidateTestState);
      }
    }
    if (session is SqliteConnectionFormSession) {
      session.pathController.addListener(_invalidateTestState);
    }
  }

  void _detachSessionListeners() {
    final session = _session;
    if (session == null) return;
    if (session is ChangeNotifier) {
      (session as ChangeNotifier).removeListener(_invalidateTestState);
    }
    if (session is NetworkConnectionFormSession) {
      for (final controller in [
        session.hostController,
        session.portController,
        session.usernameController,
        session.passwordController,
        session.databaseController,
        session.timeoutController,
        session.sshHostController,
        session.sshPortController,
        session.sshUsernameController,
        session.sshPasswordController,
        session.sshPrivateKeyController,
        session.sshPassphraseController,
      ]) {
        controller.removeListener(_invalidateTestState);
      }
    }
    if (session is SqliteConnectionFormSession) {
      session.pathController.removeListener(_invalidateTestState);
    }
  }

  String _defaultUsername(DatabaseType type) {
    switch (type) {
      case DatabaseType.sqlserver:
        return 'sa';
      case DatabaseType.redis:
      case DatabaseType.sqlite:
        return '';
      case DatabaseType.mongodb:
        return 'admin';
      default:
        return 'root';
    }
  }

  void _createSession() {
    _detachSessionListeners();
    _session?.dispose();
    final plugin = defaultPluginRegistry.connectionFormFor(_selectedType) ??
        const GenericConnectionFormPlugin();
    _sessionDescriptor = plugin.descriptor;
    _session = plugin.createSession(
      ConnectionFormPluginContext(type: _selectedType, draft: _draft),
    );
    _attachSessionListeners();
  }

  /// 切换类型：全量重建草稿——保留身份/头部字段（id/name/groupId/
  /// environment/host），类型相关字段重置为该类型默认值（防跨类型残留，
  /// 如 mysql 库名泄成 redis db index）。
  ///
  /// 仅新建态可切换：编辑既有连接时类型是固有属性（保存的配置按类型
  /// 语义落库），切到其他类型表单会造出语义错乱的连接——左栏导航同步
  /// 禁用，此处兜底拦截。
  void _switchType(DatabaseType type) {
    if (type == _selectedType) return;
    if (widget.existingServer != null) return;
    setState(() {
      _selectedType = type;
      final old = _draft.value;
      _draft.update(
        DbServer(
          id: old.id,
          name: old.name,
          type: type,
          host: old.host.isEmpty ? 'localhost' : old.host,
          port: type == DatabaseType.sqlite ? 0 : type.defaultPort,
          username: type == DatabaseType.sqlite ? null : _defaultUsername(type),
          timeoutSeconds: old.timeoutSeconds,
          charset: 'utf8mb4',
          groupId: old.groupId,
          environment: old.environment,
        ),
      );
      _createSession();
    });
  }

  @override
  void dispose() {
    _detachSessionListeners();
    _draft.removeListener(_invalidateTestState);
    _session?.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 680),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTypeNav(context),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: context.themeColors.borderColor,
            ),
            Expanded(child: _buildFormPane(context)),
          ],
        ),
      ),
    );
  }

  // ── 左栏：类型导航 ──────────────────────────────────────────────

  Widget _buildTypeNav(BuildContext context) {
    return Container(
      width: 190,
      color: context.themeColors.bgPrimary,
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space3),
      child: ListView(
        children: [
          for (final type in DatabaseType.uiSelectableValues)
            _buildTypeNavItem(context, type),
        ],
      ),
    );
  }

  Widget _buildTypeNavItem(BuildContext context, DatabaseType type) {
    final selected = type == _selectedType;
    // 编辑态：类型不可改（见 _switchType 注释）——整栏禁点，非当前项
    // 按禁用色渲染；当前项保持高亮标识连接类型。
    final bool navEnabled = widget.existingServer == null;
    final brandColor = selected || navEnabled
        ? context.themeColors.brandColor(type)
        : context.themeColors.textDisabled;
    return InkWell(
      onTap: navEnabled ? () => _switchType(type) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2_5,
        ),
        decoration: BoxDecoration(
          color: selected ? context.themeColors.bgTertiary : null,
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected ? brandColor : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(type.typeIcon, size: 18, color: brandColor),
            const SizedBox(width: AppDesignSystem.space3),
            Expanded(
              child: Text(
                type.displayName,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? context.themeColors.textPrimary
                      : (navEnabled
                          ? context.themeColors.textSecondary
                          : context.themeColors.textDisabled),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (type != DatabaseType.sqlite)
              Text(
                '${type.defaultPort}',
                style: TextStyle(
                  fontSize: 11,
                  color: selected || navEnabled
                      ? context.themeColors.textMuted
                      : context.themeColors.textDisabled,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 右栏：头部字段 + 动态表单 ──────────────────────────────────

  Widget _buildFormPane(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDesignSystem.space5,
            AppDesignSystem.space4,
            AppDesignSystem.space3,
            AppDesignSystem.space2,
          ),
          child: Row(
            children: [
              Icon(
                _selectedType.typeIcon,
                size: 20,
                color: context.themeColors.brandColor(_selectedType),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                widget.existingServer == null
                    ? l10n.connectionNewConnection
                    : l10n.connectionEditConnection,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXl,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  LucideIcons.x,
                  size: 18,
                  color: context.themeColors.textMuted,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppDesignSystem.space5,
                0,
                AppDesignSystem.space5,
                AppDesignSystem.space3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConnectionTextField(
                    controller: _nameController,
                    label: l10n.connectionConnectionName,
                    hint: '${_selectedType.displayName} Server',
                    icon: LucideIcons.tag,
                    validator: (v) =>
                        v?.isEmpty ?? true ? l10n.connNameRequired : null,
                    onChanged: (v) =>
                        _draft.update(_draft.value.copyWith(name: v)),
                  ),
                  const SizedBox(height: AppDesignSystem.space4),
                  _buildEnvironmentSelector(),
                  const SizedBox(height: AppDesignSystem.space5),
                  if (_session != null) _session!.build(context),
                  if (_testState == _ConnectionTestState.tested)
                    _buildTestSummary(context)
                  else
                    _buildTestPendingHint(context),
                ],
              ),
            ),
          ),
        ),
        _buildFooter(context, l10n),
      ],
    );
  }

  /// UIRV-B2：tested 态成功摘要条（success token；SQLite 目标为文件名，
  /// socket 型为 host:port，port==0 不拼 `:0`——与 B5 副信息口径同源）。
  Widget _buildTestSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final target = _lastTestedServer == null
        ? ''
        : _targetLabel(_lastTestedServer!);
    return Container(
      key: const ValueKey('connection-test-summary'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppDesignSystem.space4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2_5,
      ),
      decoration: BoxDecoration(
        color: colors.successContainer,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.circleCheck, size: 14, color: colors.success),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.connectionTestPassedSummary(target),
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.connectionTestResultScope,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// UIRV-B2：dirty 态未测试提示（弱提示，不构成硬门——Save 始终可点）。
  Widget _buildTestPendingHint(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesignSystem.space4),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 14, color: colors.textMuted),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.connectionTestPendingHint,
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppLocalizations l10n) {
    final descriptor = _sessionDescriptor;
    final tested = _testState == _ConnectionTestState.tested;
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space5,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.themeColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          if (descriptor != null)
            Expanded(
              child: Text(
                l10n.connectionFormProvidedBy(descriptor.id),
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textMuted,
                ),
              ),
            )
          else
            const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          if (tested) ...[
            // UIRV-B2：tested 态——重新测试（次样式）+ Save（主样式接手）
            LoadingButton(
              key: const ValueKey('connection-dialog-test-button'),
              label: l10n.connectionRetest,
              onPressed: _testConnection,
              isLoading: _testState == _ConnectionTestState.testing,
              backgroundColor: colors.bgTertiary,
              textColor: colors.textPrimary,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            LoadingButton(
              key: const ValueKey('connection-dialog-save-button'),
              label: l10n.commonSave,
              onPressed: _saveConnection,
              isLoading: _isLoading,
              backgroundColor: colors.accentBlue,
            ),
          ] else ...[
            // UIRV-B2：dirty 态——Save（次样式，始终可点）+ Test（主动作）
            LoadingButton(
              key: const ValueKey('connection-dialog-save-button'),
              label: l10n.commonSave,
              onPressed: _saveConnection,
              isLoading: _isLoading,
              backgroundColor: colors.bgTertiary,
              textColor: colors.textPrimary,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            LoadingButton(
              key: const ValueKey('connection-dialog-test-button'),
              label: l10n.connectionTestConnection,
              onPressed: _testConnection,
              isLoading: _testState == _ConnectionTestState.testing,
              backgroundColor: colors.accentBlue,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnvironmentSelector() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.connectionEnvironment,
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ConnectionEnvironment?>(
              value: _draft.value.environment,
              isExpanded: true,
              dropdownColor: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              hint: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                ),
                child: Text(
                  l10n.connectionEnvironmentNone,
                  style: TextStyle(color: context.themeColors.textMuted),
                ),
              ),
              items: [
                DropdownMenuItem<ConnectionEnvironment?>(
                  value: null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space3,
                    ),
                    child: Text(
                      l10n.connectionEnvironmentNone,
                      style: TextStyle(color: context.themeColors.textPrimary),
                    ),
                  ),
                ),
                ...ConnectionEnvironment.values.map((env) {
                  return DropdownMenuItem<ConnectionEnvironment?>(
                    value: env,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: env.badgeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppDesignSystem.space2_5),
                          Text(
                            env.displayName,
                            style: TextStyle(
                              color: context.themeColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _draft.update(
                    _draft.value.copyWith(
                      environment: value,
                      clearEnvironment: value == null,
                    ),
                  );
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── 保存 / 测试 ───────────────────────────────────────────────

  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final collected = _session?.collect(forSave: true);
    if (collected == null) return;

    setState(() => _isLoading = true);

    // 走 AppProvider 门面（含 Free 连接数门禁），不直连子 Provider；
    // await 前捕获引用，避免 catch 中跨异步间隙使用 context
    final appProvider = context.read<AppProvider>();
    try {
      final server = collected.copyWith(
        id: widget.existingServer?.id ??
            'conn_${DateTime.now().millisecondsSinceEpoch}',
      );
      await appProvider.saveConnection(server);
      if (mounted) Navigator.pop(context, server);
    } catch (e, stackTrace) {
      AppLogger.e(
        'ConnectionDialog',
        'Failed to save connection: $e\n$stackTrace',
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.connSaveConnectionFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 目标标签：SQLite = 文件路径；socket 型 = host:port（port==0 不拼，
  /// 与 UIRV-B5 副信息口径同源）。
  String _targetLabel(DbServer server) {
    if (server.type == DatabaseType.sqlite) return server.host;
    if (server.port == 0) return server.host;
    return '${server.host}:${server.port}';
  }

  /// UIRV-B2：执行一次连接测试（状态机推进 dirty→testing→tested/dirty）。
  /// 返回 true = 通过；false = 失败（`_lastFailure` 已就位，等待展示方
  /// 走结构化面）。testing 中重入直接拒绝（防重，请求只发一次）。
  Future<bool> _runTest() async {
    if (_testState == _ConnectionTestState.testing) return false;
    if (!_formKey.currentState!.validate()) return false;
    final server = _session?.collect(forSave: false);
    if (server == null) return false;

    setState(() => _testState = _ConnectionTestState.testing);

    try {
      final error = await context.read<AppProvider>().testConnection(server);
      if (!mounted) return false;
      if (error == null) {
        setState(() {
          _lastTestedServer = server;
          _testState = _ConnectionTestState.tested;
        });
        return true;
      }
      // provider.testConnection 返回 String?（无结构化失败，偏差清单 #9）
      // → 映射 unknown 分型；ConnectFailureDialog 展示边界自带脱敏。
      _lastFailure = ConnectionFailure(
        kind: ConnectionFailureKind.unknown,
        errorCode: '',
        target: _targetLabel(server),
        rawMessage: error,
        occurredAt: DateTime.now(),
      );
    } catch (e) {
      AppLogger.e('ConnectionDialog', 'Test connection error: $e');
      _lastFailure = ConnectionFailure(
        kind: ConnectionFailureKind.unknown,
        errorCode: '',
        target: _targetLabel(server),
        rawMessage: e.toString(),
        occurredAt: DateTime.now(),
      );
      if (!mounted) return false;
    }
    // 失败不设独立态：回 dirty，由调用方弹结构化面（验收 6）
    setState(() => _testState = _ConnectionTestState.dirty);
    return false;
  }

  Future<void> _testConnection() async {
    final ok = await _runTest();
    if (ok || !mounted || _lastFailure == null) return;
    final failure = _lastFailure!;
    await ConnectFailureDialog.show(
      context,
      failure: failure,
      // 重试闭包 = 同一连接调用（对话框内原地更新，不叠窗）
      onRetry: _runTest,
      latestFailure: () => _lastFailure,
    );
  }
}

class ConnectionManagerDialog extends StatelessWidget {
  const ConnectionManagerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Overlay style: semi-transparent backdrop with centered panel
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent backdrop - click to close
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.black54),
          ),
          // Centered content panel
          Center(
            child: Container(
              width: 600,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
                border: Border.all(color: context.themeColors.borderColor),
                boxShadow: AppDesignSystem.shadowModal,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with close button
                  Padding(
                    padding: const EdgeInsets.all(AppDesignSystem.space3),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.share2,
                          color: context.themeColors.accentBlue,
                          size: 20,
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        Text(
                          l10n.connectionManager,
                          style: TextStyle(
                            fontSize: AppDesignSystem.fontSize2xl,
                            fontWeight: FontWeight.w600,
                            color: context.themeColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Consumer<AppProvider>(
                          builder: (context, provider, _) {
                            if (provider.connection.activeConnectionCount > 0) {
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppDesignSystem.space2,
                                  vertical: AppDesignSystem.space1,
                                ),
                                decoration: BoxDecoration(
                                  color: context.themeColors.success.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppDesignSystem.radiusSm,
                                  ),
                                ),
                                child: Text(
                                  '${provider.connection.activeConnectionCount} ${l10n.connectionConnected}',
                                  style: TextStyle(
                                    color: context.themeColors.success,
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            LucideIcons.x,
                            color: context.themeColors.textSecondary,
                          ),
                          onPressed: () => Navigator.pop(context),
                          tooltip: l10n.commonClose,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: context.themeColors.borderColor),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppDesignSystem.space3),
                      child: Consumer<AppProvider>(
                        builder: (context, provider, _) {
                          final connections =
                              provider.connection.savedConnections;

                          if (connections.isEmpty) {
                            return _buildEmptyState(context, l10n);
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.connectionSavedConnections,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.themeColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppDesignSystem.space2),
                              ...connections.map((conn) {
                                final isConnected = provider.connection
                                    .isConnectionConnected(conn.id);
                                final isActive = provider.connection
                                    .isConnectionActive(conn.id);
                                return _buildConnectionItem(
                                  context,
                                  provider,
                                  conn,
                                  isConnected,
                                  isActive,
                                  l10n,
                                );
                              }),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Divider(height: 1, color: context.themeColors.borderColor),
                  // Footer
                  Padding(
                    padding: const EdgeInsets.all(AppDesignSystem.space3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Consumer<AppProvider>(
                          builder: (context, provider, _) {
                            if (provider.connection.activeConnectionCount > 0) {
                              return TextButton.icon(
                                onPressed: () async {
                                  await provider.connection
                                      .disconnectAllConnections();
                                },
                                icon: const Icon(LucideIcons.unlink, size: 14),
                                label: Text(l10n.connectionDisconnectAll),
                                style: TextButton.styleFrom(
                                  foregroundColor: context.themeColors.error,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        const Spacer(),
                        Consumer<AppProvider>(
                          builder: (context, provider, _) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: l10n.exportConnectionsTitle,
                                  child: IconButton(
                                    onPressed: () =>
                                        ConnectionExportImportDialog.showExport(
                                          context,
                                          connections:
                                              provider.savedConnections,
                                        ),
                                    icon: const Icon(LucideIcons.fileUp),
                                  ),
                                ),
                                const SizedBox(width: AppDesignSystem.space2),
                                Tooltip(
                                  message: l10n.importConnectionsTitle,
                                  child: IconButton(
                                    onPressed: () =>
                                        ConnectionExportImportDialog.showImport(
                                          context,
                                        ),
                                    icon: const Icon(LucideIcons.fileDown),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l10n.commonClose),
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        ElevatedButton.icon(
                          onPressed: () => _showNewConnectionDialog(context),
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: Text(l10n.connectionNewConnection),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.themeColors.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.database,
              size: 48,
              color: context.themeColors.textSecondary,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              l10n.connectionNoSavedConnections,
              style: TextStyle(color: context.themeColors.textSecondary),
            ),
            const SizedBox(height: AppDesignSystem.space4),
            ElevatedButton.icon(
              onPressed: () => _showNewConnectionDialog(context),
              icon: const Icon(LucideIcons.plus),
              label: Text(l10n.connectionNewConnection),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionItem(
    BuildContext context,
    AppProvider provider,
    DbServer conn,
    bool isConnected,
    bool isActive,
    AppLocalizations l10n,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: isActive
              ? context.themeColors.accentBlue.withValues(alpha: 0.5)
              : context.themeColors.borderLight,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color:
                (isConnected
                        ? context.themeColors.success
                        : context.themeColors.textSecondary)
                    .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Center(
            // emoji→矢量图标+品牌色（F-37）
            child: Icon(
              conn.type.typeIcon,
              size: 16,
              color: context.themeColors.brandColor(conn.type),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                conn.name,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                conn.type.displayName,
                style: TextStyle(
                  // 徽章例外（契约 C4）：角标类 supplementary 文本允许 10px，
                  // 见 AppDesignSystem.fontSizeXs 注释。
                  fontSize: 10,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ),
            if (conn.useSSL) ...[
              const SizedBox(width: AppDesignSystem.space1),
              Icon(
                LucideIcons.lock,
                size: 10,
                color: context.themeColors.success,
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${conn.host}:${conn.port}',
          style: TextStyle(color: context.themeColors.textMuted, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conn.environment != null)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: conn.environment!.badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
            if (conn.environment != null)
              const SizedBox(width: AppDesignSystem.space1_5),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive
                    ? context.themeColors.success
                    : isConnected
                    ? context.themeColors.accentBlue
                    : context.themeColors.textMuted.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            PopupMenuButton<String>(
              icon: Icon(
                LucideIcons.ellipsisVertical,
                color: context.themeColors.textSecondary,
                size: 16,
              ),
              padding: EdgeInsets.zero,
              onSelected: (value) =>
                  _handleAction(context, provider, conn, value),
              itemBuilder: (context) => [
                if (!isConnected)
                  CompactPopupMenuItem(
                    value: 'connect',
                    child: Text(
                      l10n.connectionConnect,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (isConnected && !isActive)
                  CompactPopupMenuItem(
                    value: 'switch',
                    child: Text(
                      l10n.connectionSwitchToConnection,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (isConnected)
                  CompactPopupMenuItem(
                    value: 'disconnect',
                    child: Text(
                      l10n.connectionDisconnect,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                CompactPopupMenuItem(
                  value: 'edit',
                  child: Text(
                    l10n.commonEdit,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                CompactPopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l10n.commonDelete,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () async {
          if (isConnected && !isActive) {
            await provider.switchToConnection(conn.id);
          } else if (!isConnected) {
            await provider.connectToServer(conn);
          }
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  void _handleAction(
    BuildContext context,
    AppProvider provider,
    DbServer conn,
    String action,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    switch (action) {
      case 'connect':
        await provider.connectToServer(conn);
        break;
      case 'switch':
        await provider.switchToConnection(conn.id);
        break;
      case 'disconnect':
        await provider.disconnectConnection(connectionId: conn.id);
        break;
      case 'clone':
        await provider.connection.cloneConnection(conn);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.connectionCloned} "${conn.name}"')),
          );
        }
        break;
      case 'edit':
        // C08：SQLite 并入新壳（sqlite-connection-plugin 表单模块），
        // 全类型统一走 ConnectionDialog；旧独立对话框由 C09 删除。
        await showDialog<DbServer>(
          context: context,
          builder: (context) => ConnectionDialog(existingServer: conn),
        );
        break;
      case 'delete':
        _deleteConnection(context, provider, conn);
        break;
    }
  }

  Future<void> _showNewConnectionDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<DbServer>(
      context: context,
      builder: (context) => const ConnectionDialog(),
    );
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.commonSave} "${result.name}"')),
      );
    }
  }

  void _deleteConnection(
    BuildContext context,
    AppProvider provider,
    DbServer server,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(
          l10n.connectionDeleteConnectionTitle,
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
        ),
        content: Text(
          '${l10n.connectionDeleteConnectionConfirm} "${server.name}"?',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await provider.connection.deleteConnection(server.id);
      } catch (e, stackTrace) {
        AppLogger.e(
          'ConnectionDialog',
          'Failed to delete connection: $e\n$stackTrace',
        );
        if (context.mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            l10n.connDeleteConnectionFailed(e.toString()),
          );
        }
      }
    }
  }
}
