import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';

/// 生产守卫分级（B-07 冻结）。
enum ProductionGuardLevel {
  /// L1 破坏性操作（DROP/TRUNCATE 族）：输入目标名完全匹配后解锁确认钮。
  l1Destructive,

  /// L2 无范围写（无 WHERE 的 UPDATE/DELETE 族）：免输入，默认焦点锁 Cancel。
  l2UnboundedWrite,
}

/// 生产高危分级拦截弹窗（B-07）。
///
/// 返回 `true` = 用户确认执行；`false` / AI 分流 / Esc = 取消（AI 分流回调
/// 独立，返回 `false`）。弹窗本体不做任何执行——不跑 SQL、不开 AI 面板、
/// 不写 prefill；AI 备份仅回调 [onAiBackup] 后关闭弹窗并返回 `false`，
/// 由调用方接管后续（开 AI 面板 / 预填 prompt 是调用方的事）。
///
/// [connectionId] 为派生 environment/riskLevel 的锚，弹窗内用于展示环境
/// 标签（按已保存连接的 environment 解析；不可解析时按生产口径回落——
/// 守卫只对生产连接打开）。[estimatedRows] 为 null 表示未知行数，展示
/// `prodGuardUnknownRows`，禁止以 0 冒充。
Future<bool> showProductionGuardDialog(
  BuildContext context, {
  required String connectionId,
  required ProductionGuardLevel level,
  required String sqlPreview,
  required String targetObjectName,
  int? estimatedRows,
  VoidCallback? onAiBackup,
}) async {
  // 关闭后焦点回触发点：快照弹窗打开前的主焦点，关闭时还原（节点仍挂载时）。
  final previousFocus = FocusManager.instance.primaryFocus;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ProductionGuardDialog(
      connectionId: connectionId,
      level: level,
      sqlPreview: sqlPreview,
      targetObjectName: targetObjectName,
      estimatedRows: estimatedRows,
      onAiBackup: onAiBackup,
    ),
  );
  // 关闭后焦点回触发点：快照弹窗打开前的主焦点，关闭时还原。当前
  // Flutter 按钮点击不请求焦点（pointer 激活路径无 requestFocus），点击
  // 打开时快照往往是路由 FocusScope 本身——此时回落到该作用域的首个
  // 可聚焦节点（触发点近邻），保证关闭后键盘上下文有明确落点。路由
  // 销毁期间弹窗 FocusScope 拆卸会再裁决主焦点，故立即还原一次 +
  // post-frame 复原一次（幂等）；节点仍挂载（context != null）才还原。
  void restoreTriggerFocus() {
    final FocusNode? node = previousFocus;
    if (node == null || node.context == null) return;
    if (node is FocusScopeNode) {
      FocusNode? first;
      try {
        first = FocusTraversalGroup.of(
          node.context!,
        ).findFirstFocus(node, ignoreCurrentFocus: true);
      } catch (_) {
        // 无遍历组上下文：按作用域整体还原。
      }
      (first ?? node).requestFocus();
      return;
    }
    node.requestFocus();
  }

  restoreTriggerFocus();
  WidgetsBinding.instance.addPostFrameCallback((_) => restoreTriggerFocus());
  return result ?? false;
}

/// 生产守卫弹窗本体（视觉沿 [AlertDialog] + error 语义 token 惯例）。
class ProductionGuardDialog extends StatefulWidget {
  /// 派生环境标签的锚（已保存连接 id）。
  final String connectionId;

  /// 守卫分级（决定是否需要目标名输入匹配与初始焦点策略）。
  final ProductionGuardLevel level;

  /// 只读 SQL 预览全文。
  final String sqlPreview;

  /// L1 输入匹配目标（trim + 小写比较）。
  final String targetObjectName;

  /// 预估影响行数；null = 未知。
  final int? estimatedRows;

  /// AI 备份入口回调；null 时不渲染入口。
  final VoidCallback? onAiBackup;

  const ProductionGuardDialog({
    super.key,
    required this.connectionId,
    required this.level,
    required this.sqlPreview,
    required this.targetObjectName,
    this.estimatedRows,
    this.onAiBackup,
  });

  @override
  State<ProductionGuardDialog> createState() => _ProductionGuardDialogState();
}

class _ProductionGuardDialogState extends State<ProductionGuardDialog> {
  final TextEditingController _nameController = TextEditingController();

  /// 确认钮焦点节点：L1 随匹配态切换 canRequestFocus（锁定 = 焦点遍历不可达）。
  late final FocusNode _confirmFocusNode;

  /// 环境标签（initState 一次性解析；late 自证安全——build 只在 initState
  /// 赋值之后运行）。
  late final ConnectionEnvironment _environment;

  bool _nameMatched = false;

  bool get _isL1 => widget.level == ProductionGuardLevel.l1Destructive;

  /// 确认钮可激活：L2 免输入恒可激活；L1 需目标名完全匹配。
  bool get _confirmEnabled => !_isL1 || _nameMatched;

  @override
  void initState() {
    super.initState();
    // L1 初始锁定（目标名完全匹配后解锁）；L2 免输入直接可达（仅不聚焦）。
    _confirmFocusNode = FocusNode(
      canRequestFocus: !_isL1,
      debugLabel: 'prodGuardConfirm',
    );
    _environment = _resolveEnvironment(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _confirmFocusNode.dispose();
    super.dispose();
  }

  void _handleNameChanged(String value) {
    final matched =
        value.trim().toLowerCase() ==
        widget.targetObjectName.trim().toLowerCase();
    if (matched != _nameMatched) {
      setState(() => _nameMatched = matched);
    }
    _confirmFocusNode.canRequestFocus = matched;
  }

  void _confirm() => Navigator.of(context).pop(true);

  void _cancel() => Navigator.of(context).pop(false);

  void _handleAiBackup() {
    widget.onAiBackup?.call();
    Navigator.of(context).pop(false);
  }

  /// 按 [ProductionGuardDialog.connectionId] 从已保存连接解析环境标签；
  /// 无 Provider 环境（widget 单测浅树）或未命中 id 时按生产口径回落——
  /// 守卫只对生产连接打开。
  ConnectionEnvironment _resolveEnvironment(BuildContext context) {
    try {
      final saved = context.read<AppProvider>().connection.savedConnections;
      for (final server in saved) {
        if (server.id == widget.connectionId) {
          return server.environment ?? ConnectionEnvironment.production;
        }
      }
    } catch (_) {
      // 无 Provider 环境（单测浅树）：按生产口径回落。
    }
    return ConnectionEnvironment.production;
  }

  /// 环境三态显示名（第三处本地映射，沿 status_bar_widget /
  /// tabs_bar_widget「消费面各持副本、不建共享文件」惯例——模型层
  /// displayName 禁 l10n 依赖的分层原则）。
  String _environmentLabel(AppLocalizations? l10n, ConnectionEnvironment env) {
    switch (env) {
      case ConnectionEnvironment.production:
        return l10n?.environmentProduction ?? 'Production environment';
      case ConnectionEnvironment.testing:
        return l10n?.environmentTesting ?? 'Testing environment';
      case ConnectionEnvironment.development:
        return l10n?.environmentDevelopment ?? 'Development environment';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {
        // Esc 任意位置（含 L1 输入框聚焦）取消，返回 false。
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: _buildTitle(context, l10n),
        content: _buildContent(context, l10n),
        actions: _buildActions(context, l10n),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, AppLocalizations? l10n) {
    final colors = context.themeColors;
    return Row(
      children: [
        Icon(
          _isL1 ? LucideIcons.triangleAlert : LucideIcons.zap,
          color: colors.error,
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: Text(
            _isL1
                ? l10n?.prodGuardTitleL1 ?? 'Production · destructive operation'
                : l10n?.prodGuardTitleL2 ?? 'Production · unbounded write',
            style: TextStyle(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations? l10n) {
    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEnvironmentChip(context, l10n),
            const SizedBox(height: AppDesignSystem.space2),
            _buildRowsLine(context, l10n),
            const SizedBox(height: AppDesignSystem.space3),
            if (_isL1)
              ..._buildL1Block(context, l10n)
            else
              ..._buildL2Block(context, l10n),
            const SizedBox(height: AppDesignSystem.space3),
            _buildSqlPreview(context),
            if (widget.onAiBackup != null) ...[
              const SizedBox(height: AppDesignSystem.space2),
              _buildAiBackupEntry(context, l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentChip(BuildContext context, AppLocalizations? l10n) {
    final colors = context.themeColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.database, size: 12, color: colors.error),
        const SizedBox(width: AppDesignSystem.space1_5),
        Text(
          _environmentLabel(l10n, _environment),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.error,
          ),
        ),
      ],
    );
  }

  /// 影响行数行（L1/L2 共用）：null = 未知（prodGuardUnknownRows，禁 0 冒充）；
  /// 非 null = prodGuardNoWhereWarning(count)。容器沿 DestructiveConfirmDialog
  /// 影响说明惯例（语义色 10% 底 + info 图标）。
  Widget _buildRowsLine(BuildContext context, AppLocalizations? l10n) {
    final colors = context.themeColors;
    final rows = widget.estimatedRows;
    final text = rows == null
        ? l10n?.prodGuardUnknownRows ?? 'Estimated rows: unknown'
        : l10n?.prodGuardNoWhereWarning(rows) ??
              'No WHERE clause. Estimated $rows rows affected.';
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: colors.error),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: colors.error.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// L1：type-to-confirm（交互沿 DestructiveConfirmDialog 先例——trim +
  /// lowercase 完全匹配解锁；提示文案随匹配态切换）。
  List<Widget> _buildL1Block(BuildContext context, AppLocalizations? l10n) {
    final colors = context.themeColors;
    return [
      Text(
        l10n?.ddlTypeToConfirmDestructive(widget.targetObjectName) ??
            'Type "${widget.targetObjectName}" to confirm this destructive operation:',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: AppDesignSystem.space2),
      TextField(
        controller: _nameController,
        autofocus: true,
        onChanged: _handleNameChanged,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
        decoration: InputDecoration(
          hintText: widget.targetObjectName,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2_5,
            vertical: AppDesignSystem.space1,
          ),
        ),
      ),
      const SizedBox(height: AppDesignSystem.space1_5),
      Text(
        _nameMatched
            ? l10n?.prodGuardUnlockedHint ??
                  'Name matched. The confirm button is now enabled.'
            : l10n?.prodGuardLockedHint ??
                  'Confirm button is locked until the name matches exactly.',
        style: TextStyle(
          fontSize: 11,
          color: _nameMatched ? colors.success : colors.warning,
        ),
      ),
    ];
  }

  /// L2：免输入；焦点提示行（初始焦点锁 Cancel，Enter = 取消）。
  List<Widget> _buildL2Block(BuildContext context, AppLocalizations? l10n) {
    final colors = context.themeColors;
    return [
      Row(
        children: [
          Icon(LucideIcons.keyboard, size: 14, color: colors.textMuted),
          const SizedBox(width: AppDesignSystem.space1_5),
          Expanded(
            child: Text(
              l10n?.prodGuardFocusCancelHint ??
                  'Focus starts on Cancel. Enter cancels; press Tab to reach the destructive button.',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ),
        ],
      ),
    ];
  }

  /// 只读 SQL 预览：codeBlockBg mono 底、max 高约 86 可滚（纯 [Text] 承载，
  /// 天然只读——沿 dml_confirm_dialog 的 SQL 预览惯例）。
  Widget _buildSqlPreview(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 86),
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: colors.codeBlockBg,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: SingleChildScrollView(
        child: Text(
          widget.sqlPreview,
          style: TextStyle(
            color: colors.textPrimary,
            fontFamily: AppDesignSystem.monoFontFamily,
            fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// AI 备份左下入口（onAiBackup 非 null 才渲染）：点击 = 回调 + 关闭 +
  /// 返回 false；弹窗不执行 openAiPanel/prefill。
  Widget _buildAiBackupEntry(BuildContext context, AppLocalizations? l10n) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _handleAiBackup,
        icon: const Icon(LucideIcons.sparkles, size: 14),
        label: Text(
          l10n?.prodGuardAiBackup ?? 'Generate backup script with AI',
        ),
        style: TextButton.styleFrom(
          foregroundColor: context.themeColors.accentBlue,
          textStyle: const TextStyle(fontSize: 12),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
            vertical: AppDesignSystem.space1,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, AppLocalizations? l10n) {
    final colors = context.themeColors;
    return [
      TextButton(
        // L2 打开默认焦点锁 Cancel（Enter = 取消）；L1 焦点在目标名输入框。
        autofocus: !_isL1,
        onPressed: _cancel,
        child: Text(l10n?.commonCancel ?? 'Cancel'),
      ),
      Opacity(
        // 未匹配锁定态视觉（opacity .45）；不可聚焦由 _confirmFocusNode 承载。
        opacity: _confirmEnabled ? 1.0 : 0.45,
        child: ElevatedButton(
          focusNode: _confirmFocusNode,
          onPressed: _confirmEnabled ? _confirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.textInverted,
          ),
          child: Text(l10n?.prodGuardConfirmDrop ?? 'Delete permanently'),
        ),
      ),
    ];
  }
}
