//! AI 工作台上下文芯片（design-ai-workbench §4.2/§4.3/§5.1/§7.3，T11；
//! R2 修订 2026-09-22：全态可点开上下文选择器，T18）。
//!
//! 三态（R3）：
//! - 跟随态：`effectiveWorkbenchContext` 派生值（锁定快照优先，否则
//!   `resolveWorkbenchContext`），展示连接名 + 库名 + 来源标识
//!   （「活动 tab / 侧栏」徽标），提供锁定动作。
//! - 锁定态：`provider.workbenchContextLock != null` 判定（⚠ T08 契约：
//!   锁定时 effectiveWorkbenchContext 的 source 不可用于渲染来源徽标，
//!   本组件以锁定徽标呈现「已锁定」语义），提供解锁动作。
//! - 未设置态（AC3.6）：source == none → 「未设置」+ 选择引导
//!   （打开上下文选择器），不阻塞对话输入。
//!
//! R2 交互（选择即锁定）：三态主体均可点开 `WorkbenchContextPicker`；
//! 跟随/锁定态主体 tooltip = workbenchContextSwitchTip；未设置态主按钮
//! 语义 =「选择已有连接」（label 复用 aiPanelSelectConnection，tooltip =
//! workbenchContextSetupGuide）。锁定/解锁动作与 key 不变。
//!
//! 生效上下文同步（design §5.1）：工作台可见期间（aiPanelOpen &&
//! aiPanelFullscreen）把 effectiveWorkbenchContext 经既有
//! `setSelectedConnection/setSelectedDatabase` 写为 AI 生效上下文；
//! 退出工作台（Offstage 保活挂载仍在树上）期间停止写入——芯片写入
//! 仅限工作台可见期间（任务书约束）。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../services/ai/workbench_context_resolver.dart';
import '../../theme/app_colors.dart';
import 'workbench_context_change_hint.dart';
import 'workbench_context_picker.dart';

/// AI 工作台上下文芯片。
class WorkbenchContextChip extends StatefulWidget {
  const WorkbenchContextChip({super.key});

  @override
  State<WorkbenchContextChip> createState() => _WorkbenchContextChipState();
}

class _WorkbenchContextChipState extends State<WorkbenchContextChip> {
  AppProvider? _observedProvider;
  bool _syncScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    if (!identical(provider, _observedProvider)) {
      _observedProvider?.removeListener(_onProviderChanged);
      _observedProvider = provider;
      provider.addListener(_onProviderChanged);
      _scheduleContextSync();
    }
  }

  @override
  void dispose() {
    _observedProvider?.removeListener(_onProviderChanged);
    _observedProvider = null;
    super.dispose();
  }

  void _onProviderChanged() => _scheduleContextSync();

  /// 生效上下文同步（design §5.1）。经 post-frame 执行，避免在通知/build
  /// 相位同步修改 provider；目标 setter 自带「值不变不通知」守卫，本同步
  /// 与解析序（tab/侧栏）无反馈回路，收敛不循环。
  void _scheduleContextSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      // 芯片写入仅限工作台可见期间（Offstage 保活期间不写，§5.1）。
      if (!provider.aiPanelOpen || !provider.aiPanelFullscreen) return;
      final aiPanel = provider.aiPanel;
      final ctx = effectiveWorkbenchContext(
        aiPanel.aiConversationService.currentSession,
        provider,
      );
      if (aiPanel.selectedConnectionId != ctx.connectionId) {
        aiPanel.setSelectedConnection(ctx.connectionId);
      }
      if (aiPanel.selectedDatabaseName != ctx.databaseName) {
        aiPanel.setSelectedDatabase(ctx.databaseName);
      }
    });
  }

  void _lockContext() {
    final provider = context.read<AppProvider>();
    final aiPanel = provider.aiPanel;
    final ctx = effectiveWorkbenchContext(
      aiPanel.aiConversationService.currentSession,
      provider,
    );
    final connectionId = ctx.connectionId;
    if (connectionId == null) return;
    aiPanel.lockWorkbenchContext(connectionId, ctx.databaseName);
  }

  void _unlockContext() {
    final aiPanel = context.read<AppProvider>().aiPanel;
    aiPanel.unlockWorkbenchContext();
    // T6：run 活跃时提示「改选下次运行生效」（D15 快照契约的显示面）。
    WorkbenchContextChangeHint.showIfRunActive(context, aiPanel);
  }

  /// R2：打开上下文选择器（三态全态出口；选择即锁定）。
  Future<void> _openContextPicker() {
    return WorkbenchContextPicker.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final aiPanel = provider.aiPanel;
    final locked = aiPanel.workbenchContextLock != null;
    final ctx = effectiveWorkbenchContext(
      aiPanel.aiConversationService.currentSession,
      provider,
    );

    if (!ctx.isAvailable) return _buildUnsetChip(context);
    if (locked) return _buildLockedChip(context, ctx);
    return _buildFollowingChip(context, ctx);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 跟随态（来源标识 + 锁定动作；主体可点开 picker）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildFollowingChip(BuildContext context, WorkbenchContextValue ctx) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      child: _ChipBody(
        onTap: _openContextPicker,
        tooltip: l10n.workbenchContextSwitchTip,
        child: Row(
          children: [
            Icon(
              LucideIcons.database,
              size: 13,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            ..._buildNameAndDatabase(context, ctx),
            const SizedBox(width: AppDesignSystem.space2),
            _buildSourceBadge(context, ctx.source),
            const Spacer(),
            IconButton(
              key: const ValueKey('workbench_context_chip_lock_button'),
              icon: const Icon(LucideIcons.lock, size: 14),
              color: context.themeColors.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: l10n.workbenchContextLock,
              onPressed: _lockContext,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBadge(BuildContext context, WorkbenchContextSource source) {
    final l10n = AppLocalizations.of(context)!;
    final label = switch (source) {
      WorkbenchContextSource.activeTab => l10n.workbenchContextSourceTab,
      WorkbenchContextSource.sidebar => l10n.workbenchContextSourceSidebar,
      WorkbenchContextSource.none => l10n.workbenchContextUnset,
    };
    return Container(
      key: const ValueKey('workbench_context_chip_source_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: context.themeColors.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 锁定态（锁定徽标 + 解锁动作；不渲染来源徽标——T08 契约；主体可点开 picker）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLockedChip(BuildContext context, WorkbenchContextValue ctx) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      child: _ChipBody(
        onTap: _openContextPicker,
        tooltip: l10n.workbenchContextSwitchTip,
        child: Row(
          children: [
            Container(
              key: const ValueKey('workbench_context_chip_locked_badge'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.accentPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Icon(
                LucideIcons.lock,
                size: 11,
                color: context.themeColors.accentPurple,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            ..._buildNameAndDatabase(context, ctx),
            const Spacer(),
            IconButton(
              key: const ValueKey('workbench_context_chip_unlock_button'),
              icon: const Icon(LucideIcons.lockOpen, size: 14),
              color: context.themeColors.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: l10n.workbenchContextUnlock,
              onPressed: _unlockContext,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 未设置态（AC3.6：引导不阻塞输入；不显示错误连接名；R2 主出口 = 选择已有连接）
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildUnsetChip(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      child: _ChipBody(
        onTap: _openContextPicker,
        child: Row(
          children: [
            Icon(
              LucideIcons.circleHelp,
              size: 13,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            // T27 缺陷修复（舞台并置态对话列恒 360，芯片内行宽可低至 ~280）：
            // 未设置态文本包 Flexible + ellipsis（跟随/锁定态的名称文本本就
            // 如此）；宽屏（≥M1 对话列 360–760 居中实宽）渲染零变化。
            Flexible(
              child: Text(
                l10n.workbenchContextUnset,
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Tooltip(
              message: l10n.workbenchContextSetupGuide,
              child: TextButton.icon(
                key: const ValueKey('workbench_context_chip_setup'),
                onPressed: _openContextPicker,
                style: TextButton.styleFrom(
                  foregroundColor: context.themeColors.accentBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(LucideIcons.database, size: 12),
                label: Text(
                  l10n.aiPanelSelectConnection,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 公共片段
  // ──────────────────────────────────────────────────────────────────────────

  /// 连接名 + 库名（§7.3 错误路径：名字解析失败时 resolver 已以 id 兜底，
  /// 此处再兜一层，绝不显示 null）。
  ///
  /// T6 未选库标记：本方法仅在跟随/锁定态被调（未设置态走 _buildUnsetChip，
  /// 不经过此槽位）——有连接但 databaseName 空时，库名槽位显示
  /// workbenchContextNoDatabase 标记（同槽位、textMuted 11px 同款样式）。
  List<Widget> _buildNameAndDatabase(
    BuildContext context,
    WorkbenchContextValue ctx,
  ) {
    final name = ctx.connectionName ?? ctx.connectionId ?? '';
    final databaseName = ctx.databaseName;
    final hasDatabase = databaseName != null && databaseName.isNotEmpty;
    final l10n = AppLocalizations.of(context)!;
    return [
      Flexible(
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: AppDesignSystem.space1_5),
      Flexible(
        child: Text(
          hasDatabase
              ? '· $databaseName'
              : '· ${l10n.workbenchContextNoDatabase}',
          style: TextStyle(
            fontSize: 11,
            color: context.themeColors.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
  }
}

/// 芯片主体壳（R2）：Semantics(button) + FocusableActionDetector（Enter/Space
/// 激活）+ hover/焦点视觉。三态全态可点开上下文选择器（主体 key
/// `workbench_context_chip_body`，design §4.2 R2）；内嵌 IconButton
/// （锁定/解锁）的命中优先于主体，语义不变。
class _ChipBody extends StatefulWidget {
  const _ChipBody({required this.onTap, this.tooltip, required this.child});

  final VoidCallback onTap;
  final String? tooltip;
  final Widget child;

  @override
  State<_ChipBody> createState() => _ChipBodyState();
}

class _ChipBodyState extends State<_ChipBody> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final body = FocusableActionDetector(
      // 三态共用主体 key（design §4.2 R2 状态覆盖）：测试定位主体出口用。
      key: const ValueKey('workbench_context_chip_body'),
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (hovering) => setState(() => _hovering = hovering),
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: _hovering || _focused ? colors.bgTertiary : null,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          foregroundDecoration: _focused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: colors.accentBlue, width: 1.5),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
    final withSemantics = Semantics(button: true, child: body);
    final tooltip = widget.tooltip;
    if (tooltip == null) return withSemantics;
    return Tooltip(message: tooltip, child: withSemantics);
  }
}
