// UIRV-A1 · AI dock 头部上下文卡（跟随 + 手动改选）。
//
// 设计稿 ui-review-fixes-mockup.html #a1 为视觉/交互权威；语义按
// tasks-ui-review-fixes.md §1.1：FOLLOW = 只读消费 AppProvider
// activeContextConnection（侧栏选中 → 活动 tab → currentServer），
// MANUAL = 会话级内存覆盖（不落盘），EMPTY = 三级全空才出现。
// 手动改选不移植工作台 ContextChip 锁定语义；本卡零连接切换
// （无 switchToConnection / connectToServer 调用）。
// 真机走查修订（2026-10-25）：连接行升级为恒显 chevron 的整行触发器，
// FOLLOW/MANUAL/EMPTY 三态均可直接打开已保存连接菜单（删除原右上角
// 「Manual select」小链接与手动态两跳流程）；表段仅在指定表时显示。
// v0.3.5 批1 T2（UI35-121~128）：紧凑态（44px 两行）改版——行 1 = 状态标识
// （● Auto-follow / ▲ Manual）+ MANUAL 恢复链接；行 2 = [库图标] 连接名 /
// 库名 / 表名 ▾ 整行触发器，复用 WorkbenchContextPicker 级联选择器
// （连接名中间省略，截断优先级 表名 > 库名 > 连接名）。完整态三行卡不动。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../providers/ai_panel_provider.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../ai_workbench/workbench_context_picker.dart';

/// 连接触发器稳定 Key（测试与自动化定位用）。
const Key kAiDockContextConnectionTrigger = Key(
  'aiDockContextConnectionTrigger',
);

/// 紧凑态行 2 触发器稳定 Key（整行打开 WorkbenchContextPicker）。
const Key kAiDockCompactContextTrigger = Key('aiDockCompactContextTrigger');

/// dock 头部上下文卡。
///
/// 三态由入参派生（宿主 ai_panel_widget 计算，本卡纯呈现）：
/// - EMPTY：[connection] 为 null 且非 [isManual]（三级全空）；
/// - MANUAL：[isManual] = true（warning 语义 + 「恢复跟随」入口）；
/// - FOLLOW：其余（accent 语义 + 第 1 行来源标注）。
/// 三态的连接选择器行均可直接打开已保存连接菜单。
class AiDockContextCard extends StatelessWidget {
  /// 生效上下文连接（FOLLOW = activeContextConnection 锚定；MANUAL = 手动
  /// 选择且仍在已保存列表，删除降级由宿主处理）。
  final DbServer? connection;

  /// 生效库名（null = 未指定/全部库）。
  final String? databaseName;

  /// 活动 browse tab 的表对象（null = 未指定，隐藏表段，不阻塞输入）。
  final String? tableName;

  /// 会话级手动覆盖标记（MANUAL 态）。
  final bool isManual;

  /// FOLLOW 态实际命中的锚定级（第 1 行来源标注）；MANUAL 态不消费。
  final AiDockContextSource? followSource;

  /// 手动改选候选（已保存连接列表）。
  final List<DbServer> connections;

  /// 手动选择回调（宿主写 setManualDockContext；本卡零连接切换）。
  final ValueChanged<DbServer> onManualSelect;

  /// 恢复跟随回调（宿主写 restoreFollowContext）。
  final VoidCallback onRestoreFollow;

  /// MANUAL 态内联库选择器（宿主传入，通常为既有库下拉；null 不显示）。
  final Widget? databaseSelector;

  /// 紧凑模式（矮面板 <420 档，44px 头）：两行卡（连接行 + 库/表行），
  /// 来源标注与库型徽章省略（高度预算内保连接/库表两级语义）。
  final bool compact;

  const AiDockContextCard({
    super.key,
    required this.connection,
    required this.databaseName,
    required this.tableName,
    required this.isManual,
    required this.followSource,
    required this.connections,
    required this.onManualSelect,
    required this.onRestoreFollow,
    this.databaseSelector,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final conn = connection;

    if (compact) {
      return _buildCompact(context, l10n, colors, conn);
    }

    if (conn == null && !isManual) {
      // EMPTY：单行整行触发器（状态点 + 空态文案 + chevron）。
      return _cardShell(
        context,
        isManual: false,
        child: _connectionTrigger(
          context,
          l10n,
          colors,
          triggerLabel: l10n.uirvDockContextEmptyTitle,
          prefix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _statusDot(colors, colors.textMuted.withValues(alpha: 0.5)),
              const SizedBox(width: AppDesignSystem.space2),
            ],
          ),
          labelStyle: TextStyle(fontSize: AppDesignSystem.fontSizeSm),
          labelColor: colors.textMuted,
          showTypeBadge: false,
        ),
      );
    }

    final Color semanticColor = isManual ? colors.warning : colors.accentBlue;
    final String stateLabel = isManual
        ? l10n.uirvDockContextManual
        : l10n.uirvDockContextFollow;
    final String triggerLabel = _connectionLabel(conn);

    return _cardShell(
      context,
      isManual: isManual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第 1 行：状态标识 + 态标签（FOLLOW 附实际来源标注）+ MANUAL 恢复入口
          Row(
            children: [
              _statusDot(colors, semanticColor),
              const SizedBox(width: AppDesignSystem.space2),
              Flexible(
                child: Text(
                  stateLabel,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isManual && followSource != null) ...[
                const SizedBox(width: AppDesignSystem.space1),
                Flexible(
                  child: Text(
                    _followSourceLabel(l10n),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (isManual)
                _linkAction(
                  context,
                  label: l10n.uirvDockContextRestoreFollow,
                  color: colors.accentBlue,
                  onTap: onRestoreFollow,
                ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space0_5),
          // 第 2 行：连接选择器（类型图标 + 连接名 + 类型徽章 + 恒显 chevron），
          // 整行可点，三态均可直接打开已保存连接菜单。
          _connectionTrigger(
            context,
            l10n,
            colors,
            triggerLabel: triggerLabel,
            prefix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  conn?.type.typeIcon ?? LucideIcons.database,
                  size: 14,
                  color: conn == null
                      ? colors.textMuted
                      : colors.brandColor(conn.type),
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
              ],
            ),
            labelStyle: TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.w600,
            ),
            labelColor: colors.textPrimary,
            showTypeBadge: conn != null,
          ),
          const SizedBox(height: AppDesignSystem.space0_5),
          // 第 3 行：库 / 表（表对象来自活动 browse tab）。MANUAL 态库段
          // 换成宿主注入的内联库选择器（沿用既有库下拉）；未指定表时
          // 整个表段（含分隔符）隐藏，避免暗示可点选。
          Row(
            children: [
              if (isManual && databaseSelector != null)
                Expanded(child: databaseSelector!)
              else ...[
                Icon(LucideIcons.database, size: 12, color: colors.textMuted),
                const SizedBox(width: AppDesignSystem.space1_5),
                Expanded(
                  child: Text(
                    databaseName ?? l10n.aiPanelAllDatabases,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (tableName != null) ...[
                Text(
                  '/',
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Expanded(
                  flex: 2,
                  child: Text(
                    tableName!,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space1),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1_5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentSubtle,
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Text(
                    l10n.uirvDockContextCurrentTableTag,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.accentBlue,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _followSourceLabel(AppLocalizations l10n) {
    switch (followSource) {
      case AiDockContextSource.sidebar:
        return l10n.uirvDockContextSourceSidebar;
      case AiDockContextSource.activeTab:
        return l10n.uirvDockContextSourceActiveTab;
      case AiDockContextSource.currentServer:
        return l10n.uirvDockContextSourceCurrentServer;
      case null:
        return l10n.uirvDockContextFollow;
    }
  }

  /// 紧凑两行卡（44px 头预算，UI35-121~128）：行 1（18px）= 状态标识
  /// （● Auto-follow / ▲ Manual / ● 空态）+ MANUAL 右端恢复链接；行 2
  /// （24px）= [库图标] 连接名 / 库名 / 表名 ▾ 整行触发器，点击复用
  /// WorkbenchContextPicker 级联选择器（连接/库双栏）。连接名中间省略
  /// （~100px 预算），截断优先级 表名 > 库名 > 连接名；表段仅指定表时显示。
  Widget _buildCompact(
    BuildContext context,
    AppLocalizations l10n,
    ThemeColors colors,
    DbServer? conn,
  ) {
    final bool isEmpty = conn == null && !isManual;
    return _cardShell(
      context,
      isManual: isManual,
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 行 1（18px）：状态标识 + 态标签（+ MANUAL 恢复链接，右端）。
          // Flexible 松弛包裹：宿主给 44 预算减边框后的净高约 42px 时，
          // 两行按 flex 比例（18:24）收缩不溢出；不受限时取自然高。
          Flexible(
            flex: 18,
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  _statusDot(
                    colors,
                    isEmpty
                        ? colors.textMuted.withValues(alpha: 0.5)
                        : isManual
                        ? colors.warning
                        : colors.accentBlue,
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isManual) ...[
                          Icon(
                            LucideIcons.triangleAlert,
                            size: 10,
                            color: colors.warning,
                          ),
                          const SizedBox(width: AppDesignSystem.space1),
                        ],
                        Flexible(
                          child: Text(
                            isEmpty
                                ? l10n.uirvDockContextEmptyTitle
                                : isManual
                                ? l10n.uirvDockContextManual
                                : l10n.uirvDockContextFollow,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: AppDesignSystem.fontSizeXs,
                              color: isEmpty
                                  ? colors.textMuted
                                  : colors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isManual) ...[
                    const Spacer(),
                    _linkAction(
                      context,
                      label: l10n.uirvDockContextRestoreFollow,
                      color: colors.accentBlue,
                      onTap: onRestoreFollow,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppDesignSystem.space0_5),
          // 行 2（24px）：[库图标] 连接名 / 库名 / 表名 ▾，整行打开级联选择器。
          Flexible(
            flex: 24,
            child: SizedBox(
              height: 24,
              child: _compactPathTrigger(context, l10n, colors, conn),
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑行 2 触发器：连接名中间省略（固定 ~100px 预算，连接名截断最狠）；
  /// 库名 / 表名走 Flexible（表名 flex 更大优先保完整，库名其次）；整行
  /// 点击复用 WorkbenchContextPicker.show（连接/库级联；表选择入口批 2）。
  Widget _compactPathTrigger(
    BuildContext context,
    AppLocalizations l10n,
    ThemeColors colors,
    DbServer? conn,
  ) {
    final bool isEmpty = conn == null && !isManual;
    final String connLabel = isEmpty
        ? l10n.uirvDockContextEmptyTitle
        : _connectionLabel(conn);
    return InkWell(
      key: kAiDockCompactContextTrigger,
      // 批1 返工 T2b：经典 dock 入口传 onSelected——确认写 dock 手动上下文
      // （setManualDockContext），不落工作台锁定；不传则 picker 走 R2 锁定。
      onTap: () => WorkbenchContextPicker.show(
        context,
        onSelected: (connectionId, databaseName) => context
            .read<AppProvider>()
            .aiPanel
            .setManualDockContext(connectionId, databaseName: databaseName),
      ),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space1),
        child: Row(
          children: [
            Icon(
              conn?.type.typeIcon ?? LucideIcons.database,
              size: 14,
              color: conn == null
                  ? colors.textMuted
                  : colors.brandColor(conn.type),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            // 连接名：数据级中间省略（非 Flexible，固定预算），截断最狠。
            Text(
              _middleTruncate(connLabel, 13),
              maxLines: 1,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                fontWeight: FontWeight.w600,
                color: isEmpty ? colors.textMuted : colors.textPrimary,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              '/',
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            // 库名：次优先截断（尾部省略）。
            Flexible(
              flex: 1,
              child: Text(
                databaseName ?? l10n.aiPanelAllDatabases,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  color: colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tableName != null) ...[
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                '/',
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              // 表名：截断优先级最高（flex 最大，优先保完整）。
              Flexible(
                flex: 2,
                child: Text(
                  tableName!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: AppDesignSystem.space1),
            Icon(LucideIcons.chevronDown, size: 12, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  /// 连接名中间省略：超预算时保留头尾、中间以 … 连接（数据级截断，
  /// 保证截断结果可断言；预算 ~100px ≈ fontSizeSm w600 × 13 字符）。
  String _middleTruncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final int keep = maxChars - 1;
    final int tail = keep ~/ 2;
    final int head = keep - tail;
    return '${text.substring(0, head)}…${text.substring(text.length - tail)}';
  }

  String _connectionLabel(DbServer? conn) {
    final c = conn;
    if (c == null) return '';
    return c.name.isNotEmpty ? c.name : '${c.host}:${c.port}';
  }

  Widget _cardShell(
    BuildContext context, {
    required Widget child,
    required bool isManual,
    bool dense = false,
  }) {
    final colors = context.themeColors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1,
        // 紧凑态 44px 预算 = 18 + 2 + 24，上下不再加 padding。
        vertical: dense ? 0 : AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          // MANUAL 外卡 warning 边框（设计稿漂移修正，2026-10-25 走查）。
          color: isManual ? colors.warning : colors.borderLight,
        ),
      ),
      child: child,
    );
  }

  Widget _statusDot(ThemeColors colors, Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  /// 连接选择器触发器：整行可点，恒显 chevron，PopupMenu 列已保存连接
  /// （数据项，零连接切换——选择仅写 AI 面板上下文）。tooltip /
  /// 无障碍名为「切换 AI 连接：<连接名>」。
  /// [prefix] 必须只含定宽小组件（状态点/图标等，不得再嵌 Flexible 文本），
  /// 连接名文本由本方法直接以 Flexible 放进行 Row（Row 不约束非 flex
  /// 子项宽度，嵌套 min Row + Flexible 文本会在窄卡下溢出）。
  Widget _connectionTrigger(
    BuildContext context,
    AppLocalizations l10n,
    ThemeColors colors, {
    required String triggerLabel,
    required Widget prefix,
    required TextStyle labelStyle,
    required Color labelColor,
    required bool showTypeBadge,
  }) {
    final conn = connection;
    return PopupMenuButton<DbServer>(
      key: kAiDockContextConnectionTrigger,
      tooltip: l10n.uirvDockContextChangeConnection(triggerLabel),
      padding: EdgeInsets.zero,
      color: colors.bgSecondary,
      onSelected: onManualSelect,
      itemBuilder: (ctx) => connections
          .map(
            (server) => PopupMenuItem<DbServer>(
              value: server,
              child: Row(
                children: [
                  Icon(
                    server.type.typeIcon,
                    size: 14,
                    color: ctx.themeColors.brandColor(server.type),
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  Expanded(
                    child: Text(
                      server.name.isNotEmpty
                          ? server.name
                          : '${server.host}:${server.port}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space1),
        child: Row(
          children: [
            prefix,
            Flexible(
              child: Text(
                triggerLabel,
                maxLines: 1,
                style: labelStyle.copyWith(color: labelColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showTypeBadge && conn != null) ...[
              const SizedBox(width: AppDesignSystem.space1_5),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1_5,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: colors.accentSubtle,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  conn.type.name,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.accentBlue,
                  ),
                ),
              ),
            ],
            const SizedBox(width: AppDesignSystem.space1),
            Icon(LucideIcons.chevronDown, size: 12, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _linkAction(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1,
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
