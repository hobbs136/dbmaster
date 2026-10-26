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

/// UIRV-B2（软门）· 表单测试状态（设计规格 §2.4 四态矩阵）：
/// dirty = 未测试/草稿已变更（Test 主动作，Save 次样式但可点）；
/// testing = 测试进行中（字段只读；主槽 = Testing… × 取消；Save 禁用）；
/// tested = 测试通过（success 摘要条 + Save 接手主动作 + Test 变「重新测试」）；
/// reverted = tested 后白名单字段变更（warning 条：旧结果失效，Test 回主样式）。
/// 测试失败不走独立态——结构化面（ConnectFailureDialog）呈现后回 dirty。
enum _ConnectionTestState { dirty, testing, tested, reverted }

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
  // 测试代际守卫：取消（或新测试开启）即递增；迟到的 provider 结果按代际
  // 丢弃（provider.testConnection 不可取消，取消只在 UI 层生效）。
  int _testEpoch = 0;

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
    // UIRV-B2 四态：头部字段（Name/Environment）不在回退白名单——tested 后
    // 修改不失效旧结果，故 `_draft` 不再整体挂失效监听；类型切换（白名单内）
    // 在 `_switchType` 中显式回退。表单会话（host/port/凭据/路径/开关）仍逐
    // 控制器挂 `_invalidateTestState`。
    _createSession();
  }

  /// 连通性指纹（UIRV-B2 §2.4 白名单）：仅决定「连到哪台/怎么连」的字段
  /// 参与回退判定——纯 UI 折叠态（如 showAdvanced 的 session 通知）不构成
  /// 变更。用字符串拼指纹而非 `==`：DbServer 相等按 id 判定，不可用。
  /// 含 host（SQLite path 落 host，同口径覆盖）、SSL/TLS 全部开关、SSH
  /// 全部字段与认证模式；autoReconnect/readOnly 一并纳入（开关变更即测试
  /// 语义变更，保守同向——多报回退只多提示一次，漏报才危险）。
  ///
  /// port/timeout 额外比对控制器原文（UI35-226a 口径）：collect 里非法
  /// 文本经 tryParse 回落默认值，仅比对解析结果会漏报「原文已变」。
  String? _connectivityFingerprint() {
    final s = _session?.collect(forSave: false);
    if (s == null) return null;
    final session = _session;
    return _connectivityFingerprintOf(
      s,
      portRaw: session is NetworkConnectionFormSession
          ? session.portController.text
          : null,
      timeoutRaw: session is NetworkConnectionFormSession
          ? session.timeoutController.text
          : null,
    );
  }

  String _connectivityFingerprintOf(
    DbServer s, {
    String? portRaw,
    String? timeoutRaw,
  }) {
    return [
      s.type.name,
      s.host,
      portRaw ?? '${s.port}',
      s.username,
      s.password,
      s.database,
      timeoutRaw ?? '${s.timeoutSeconds}',
      s.useSSL,
      s.useTls,
      s.tlsInsecure,
      s.autoReconnect,
      s.readOnly,
      s.useSshTunnel,
      s.sshHost,
      s.sshPort,
      s.sshUsername,
      s.sshAuthMode?.name,
      s.sshPassword,
      s.sshPrivateKey,
      s.sshPassphrase,
    ].join('\u{241F}');
  }

  /// 脏态失效（UIRV-B2 四态）：白名单内字段变更（表单会话控制器/开关）→
  /// tested 回退为 reverted（warning 条：旧结果失效）；dirty/testing 不动
  /// （testing 字段只读，理论不触发）。session 整体通知（含 showAdvanced
  /// 等纯 UI 折叠态）先做连通性指纹比对，指纹未变不回退（UI35-229）；
  /// collect 返回 null（校验失败）按「有变化」保守回退。会话接口只读
  /// 消费，不改其契约。
  void _invalidateTestState() {
    if (_testState != _ConnectionTestState.tested) return;
    final snapshot = _lastTestedServer;
    final changed = snapshot == null ||
        _connectivityFingerprint() != _connectivityFingerprintOf(snapshot);
    if (!changed) return;
    setState(() => _testState = _ConnectionTestState.reverted);
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
      // UIRV-B2 四态：Database Type 在回退白名单内——类型切换使旧测试结果
      // 失效（目标已换库，warning 条比 dirty 提示更准确）。
      if (_testState == _ConnectionTestState.tested) {
        _testState = _ConnectionTestState.reverted;
      }
    });
  }

  @override
  void dispose() {
    _detachSessionListeners();
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
    // UI35-228：testing 中同锁——表单字段只读期切类型会让表单与测试目标
    // 脱节（迟到结果按代际落在新类型上，产出跨类型 stale tested）。
    final bool navEnabled = widget.existingServer == null &&
        _testState != _ConnectionTestState.testing;
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
                // UIRV-B2 四态：testing 中字段只读（设计 §2.4）——整段
                // IgnorePointer 锁定，取消后自动恢复。
                IgnorePointer(
                  ignoring: _testState == _ConnectionTestState.testing,
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
                    ],
                  ),
                ),
                // UIRV-B2 四态提示区：tested=success 摘要；testing=accent
                // 进度条（含取消）；reverted=warning 变更条；dirty=弱提示。
                if (_testState == _ConnectionTestState.tested)
                  _buildTestSummary(context)
                else if (_testState == _ConnectionTestState.testing)
                  _buildTestInProgressBar(context)
                else if (_testState == _ConnectionTestState.reverted)
                  _buildTestRevertedBar(context)
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

  /// UIRV-B2 四态：testing 进度条（accent tint + 「Testing…」+ 取消入口）。
  /// 取消只在 UI 层生效（provider.testConnection 无 cancel API），迟到结果
  /// 由 `_testEpoch` 代际守卫丢弃。
  Widget _buildTestInProgressBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Container(
      key: const ValueKey('connection-test-inprogress'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppDesignSystem.space4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: colors.accentSubtle,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.accentBlue.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accentBlue),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              l10n.connectionTestInProgress,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancelTest,
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
              ),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              l10n.connectionTestCancel,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// UIRV-B2 四态：reverted 变更条（warning tint——tested 后白名单字段变更，
  /// 旧测试结果失效）。
  Widget _buildTestRevertedBar(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      key: const ValueKey('connection-test-reverted'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppDesignSystem.space4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2_5,
      ),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 14, color: colors.warning),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.connectionTestSettingsChanged,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppLocalizations l10n) {
    final descriptor = _sessionDescriptor;
    final colors = context.themeColors;
    // UIRV-B2 四态：按钮槽位固定为 [Cancel] [次槽] [主槽]，仅权重在态间
    // 交接（UI35-222），不发生位移。
    final testing = _testState == _ConnectionTestState.testing;
    final tested = _testState == _ConnectionTestState.tested;
    final Widget secondarySlot;
    final Widget primarySlot;
    if (testing) {
      // testing：Save 次槽禁用；主槽 = Testing… ×（可点 = 取消测试）
      secondarySlot = LoadingButton(
        key: const ValueKey('connection-dialog-save-button'),
        label: l10n.commonSave,
        onPressed: null,
        backgroundColor: colors.bgTertiary,
        textColor: colors.textPrimary,
      );
      primarySlot = OutlinedButton.icon(
        key: const ValueKey('connection-dialog-test-button'),
        onPressed: _cancelTest,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.accentBlue,
          side: BorderSide(color: colors.accentBlue),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space4,
            vertical: AppDesignSystem.space2,
          ),
        ),
        icon: const Icon(LucideIcons.x, size: 14),
        label: Text(l10n.connectionTestInProgress),
      );
    } else if (tested) {
      // tested：Test Again 次槽 + Save 主槽（接手主动作）
      secondarySlot = LoadingButton(
        key: const ValueKey('connection-dialog-test-button'),
        label: l10n.connectionRetest,
        onPressed: _testConnection,
        backgroundColor: colors.bgTertiary,
        textColor: colors.textPrimary,
      );
      primarySlot = LoadingButton(
        key: const ValueKey('connection-dialog-save-button'),
        label: l10n.commonSave,
        onPressed: _saveConnection,
        isLoading: _isLoading,
        backgroundColor: colors.accentBlue,
      );
    } else {
      // dirty / reverted：Save 次槽（可点）+ Test 主槽
      secondarySlot = LoadingButton(
        key: const ValueKey('connection-dialog-save-button'),
        label: l10n.commonSave,
        onPressed: _saveConnection,
        isLoading: _isLoading,
        backgroundColor: colors.bgTertiary,
        textColor: colors.textPrimary,
      );
      primarySlot = LoadingButton(
        key: const ValueKey('connection-dialog-test-button'),
        label: l10n.connectionTestConnection,
        onPressed: _testConnection,
        backgroundColor: colors.accentBlue,
      );
    }
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
          secondarySlot,
          const SizedBox(width: AppDesignSystem.space2),
          primarySlot,
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

  /// UIRV-B2 四态：取消进行中的测试——UI 立即回 dirty、字段解锁；provider
  /// 侧请求不可取消，迟到的结果由代际守卫（`_testEpoch`）在 `_runTest` 中
  /// 丢弃，不产生二次副作用。
  void _cancelTest() {
    if (_testState != _ConnectionTestState.testing) return;
    _testEpoch++;
    setState(() => _testState = _ConnectionTestState.dirty);
  }

  /// UIRV-B2 四态：执行一次连接测试（dirty/reverted→testing→tested/dirty）。
  /// 返回 true = 通过；false = 失败（`_lastFailure` 已就位，等待展示方走
  /// 结构化面）或取消/迟到丢弃。代际守卫：取消或状态机并发变更后，迟到的
  /// provider 结果整体丢弃（不改状态、不设失败、不弹窗）。
  Future<bool> _runTest() async {
    if (_testState == _ConnectionTestState.testing) return false;
    if (!_formKey.currentState!.validate()) return false;
    final server = _session?.collect(forSave: false);
    if (server == null) return false;

    _lastFailure = null;
    final epoch = ++_testEpoch;
    setState(() => _testState = _ConnectionTestState.testing);

    try {
      final error = await context.read<AppProvider>().testConnection(server);
      if (!mounted || epoch != _testEpoch) return false;
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
      if (!mounted || epoch != _testEpoch) return false;
      _lastFailure = ConnectionFailure(
        kind: ConnectionFailureKind.unknown,
        errorCode: '',
        target: _targetLabel(server),
        rawMessage: e.toString(),
        occurredAt: DateTime.now(),
      );
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
