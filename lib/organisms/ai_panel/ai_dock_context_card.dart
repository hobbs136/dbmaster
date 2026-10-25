// UIRV-A1 · AI dock 头部上下文卡（跟随 + 手动改选）。
//
// 设计稿 ui-review-fixes-mockup.html #a1 为视觉/交互权威；语义按
// tasks-ui-review-fixes.md §1.1：FOLLOW = 只读消费 AppProvider
// activeContextConnection（侧栏选中 → 活动 tab → currentServer），
// MANUAL = 会话级内存覆盖（不落盘），EMPTY = 三级全空才出现。
// 手动改选不移植工作台 ContextChip 锁定语义；本卡零连接切换
// （无 switchToConnection / connectToServer 调用）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../providers/ai_panel_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// dock 头部上下文卡。
///
/// 三态由入参派生（宿主 ai_panel_widget 计算，本卡纯呈现）：
/// - EMPTY：[connection] 为 null 且非 [isManual]（三级全空）；
/// - MANUAL：[isManual] = true（warning 语义 + 「恢复跟随」入口）；
/// - FOLLOW：其余（accent 语义 + 来源徽章 + 「手动改选」入口）。
class AiDockContextCard extends StatelessWidget {
  /// 生效上下文连接（FOLLOW = activeContextConnection 锚定；MANUAL = 手动
  /// 选择且仍在已保存列表，删除降级由宿主处理）。
  final DbServer? connection;

  /// 生效库名（null = 未指定/全部库）。
  final String? databaseName;

  /// 活动 browse tab 的表对象（null = 未指定表占位，不阻塞输入）。
  final String? tableName;

  /// 会话级手动覆盖标记（MANUAL 态）。
  final bool isManual;

  /// FOLLOW 态实际命中的锚定级（来源徽章）；MANUAL 态不消费。
  final AiDockContextSource? followSource;

  /// 手动改选候选（已保存连接列表）。
  final List<DbServer> connections;

  /// 手动选择回调（宿主写 setManualDockContext；本卡零连接切换）。
  final ValueChanged<DbServer> onManualSelect;

  /// 恢复跟随回调（宿主写 restoreFollowContext）。
  final VoidCallback onRestoreFollow;

  /// MANUAL 态内联库选择器（宿主传入，通常为既有库下拉；null 不显示）。
  final Widget? databaseSelector;

  /// 紧凑模式（矮面板 <420 档，44px 头）：双行卡（连接行 + 库/表行），
  /// 来源徽章与完整态脚注省略（自决：高度预算内保连接/库表两级语义）。
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
      return _cardShell(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusDot(colors, colors.textMuted.withValues(alpha: 0.5)),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    l10n.uirvDockContextEmptyTitle,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeSm,
                      color: colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _connectionMenu(
                  context,
                  label: l10n.uirvDockContextChooseConnection,
                  accent: colors.accentBlue,
                ),
              ],
            ),
          ],
        ),
      );
    }

    final Color semanticColor = isManual ? colors.warning : colors.accentBlue;
    final String stateLabel = isManual
        ? l10n.uirvDockContextManual
        : l10n.uirvDockContextFollow;

    return _cardShell(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶行：状态标识 + 态标签 + 动作入口
          Row(
            children: [
              _statusDot(colors, semanticColor),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
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
              if (isManual)
                _linkAction(
                  context,
                  label: l10n.uirvDockContextRestoreFollow,
                  color: colors.accentBlue,
                  onTap: onRestoreFollow,
                )
              else
                _connectionMenu(
                  context,
                  label: l10n.uirvDockContextManualSelect,
                  accent: colors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space0_5),
          // 连接行：类型图标 + 连接名 + 类型徽章（数据非文案，Q1 header 先例）
          Row(
            children: [
              Icon(
                conn?.type.typeIcon ?? LucideIcons.database,
                size: 14,
                color: conn == null
                    ? colors.textMuted
                    : context.themeColors.brandColor(conn.type),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  _connectionLabel(conn),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (conn != null) ...[
                const SizedBox(width: AppDesignSystem.space1_5),
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
                    conn.type.name,
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
          const SizedBox(height: AppDesignSystem.space0_5),
          // 路径行：库 / 表（表对象来自活动 browse tab）。MANUAL 态库段
          // 换成宿主注入的内联库选择器（沿用既有库下拉）。
          Row(
            children: [
              if (isManual && databaseSelector != null)
                Expanded(child: databaseSelector!)
              else ...[
                Icon(
                  LucideIcons.database,
                  size: 12,
                  color: colors.textMuted,
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Expanded(
                  child: Text(
                    databaseName ??
                        AppLocalizations.of(context)!.aiPanelAllDatabases,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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
                  tableName ?? l10n.uirvDockContextNoTable,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: tableName != null
                        ? colors.textPrimary
                        : colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (tableName != null) ...[
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
          // FOLLOW 脚注：来源徽章（实际命中的锚定级，设计稿 #a1 foot 行）
          if (!isManual) ...[
            const SizedBox(height: AppDesignSystem.space1),
            Row(
              children: [
                Icon(
                  LucideIcons.check,
                  size: 12,
                  color: colors.success,
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Expanded(
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
            ),
          ],
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

  /// 紧凑双行卡（44px 头预算）：行 1 = 状态点 + 连接名（+态动作），行 2 =
  /// 库 / 表（MANUAL 紧凑态库为文本，不挂库下拉——高度放不下，自决申报）。
  Widget _buildCompact(
    BuildContext context,
    AppLocalizations l10n,
    ThemeColors colors,
    DbServer? conn,
  ) {
    final bool isEmpty = conn == null && !isManual;
    return _cardShell(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _statusDot(
                colors,
                isEmpty
                    ? colors.textMuted.withValues(alpha: 0.5)
                    : isManual
                        ? colors.warning
                        : colors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Expanded(
                child: Text(
                  isEmpty
                      ? l10n.uirvDockContextEmptyTitle
                      : _connectionLabel(conn),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.w600,
                    color: isEmpty ? colors.textMuted : colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isManual)
                _linkAction(
                  context,
                  label: l10n.uirvDockContextRestoreFollow,
                  color: colors.accentBlue,
                  onTap: onRestoreFollow,
                )
              else
                _connectionMenu(
                  context,
                  label: isEmpty
                      ? l10n.uirvDockContextChooseConnection
                      : l10n.uirvDockContextManualSelect,
                  accent: isEmpty ? colors.accentBlue : colors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space0_5),
          Row(
            children: [
              Expanded(
                child: Text(
                  databaseName ??
                      AppLocalizations.of(context)!.aiPanelAllDatabases,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '/',
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Expanded(
                flex: 2,
                child: Text(
                  tableName ?? l10n.uirvDockContextNoTable,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: tableName != null
                        ? colors.textPrimary
                        : colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _connectionLabel(DbServer? conn) {
    final c = conn;
    if (c == null) return '';
    return c.name.isNotEmpty ? c.name : '${c.host}:${c.port}';
  }

  Widget _cardShell(BuildContext context, {required Widget child}) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1,
        vertical: AppDesignSystem.space0_5,
      ),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.borderLight),
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

  /// 「手动改选 / 选择已有连接」入口：PopupMenu 列已保存连接（数据项，
  /// 零连接切换——选择仅写 AI 面板上下文）。
  Widget _connectionMenu(
    BuildContext context, {
    required String label,
    required Color accent,
  }) {
    final colors = context.themeColors;
    return PopupMenuButton<DbServer>(
      tooltip: label,
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppDesignSystem.space1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 12, color: accent),
            ],
          ),
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
          padding:
              const EdgeInsets.symmetric(horizontal: AppDesignSystem.space1),
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
