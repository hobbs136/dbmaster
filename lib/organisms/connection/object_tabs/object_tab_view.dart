import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart' show ObjectTabKind, ObjectTabRef;
import '../../../theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'er_diagram_content.dart';
import 'table_properties_content.dart';

/// 只读对象 tab 容器（T16 J4）：按 [ObjectTabRef] 分发内容件
/// （[ErDiagramContent] / [TablePropertiesContent]）+ 刷新 + 失效态。
///
/// 由 `EditorResultsSplit` 在活动 tab 为对象 tab 时占满渲染。
/// 失效态：锚定连接已断开 → 「对象不可用」+ 关闭按钮（不崩、不自动关闭，
/// 用户自决——任务书边界）。[ObjectTabRef.connectionId] 为 null（ER 图无
/// 上下文入口）不算失效：内容件内连接选择器兜底（原 dialog 语义同源）。
class ObjectTabView extends StatefulWidget {
  final String tabId;
  final ObjectTabRef ref;

  const ObjectTabView({super.key, required this.tabId, required this.ref});

  @override
  State<ObjectTabView> createState() => _ObjectTabViewState();
}

class _ObjectTabViewState extends State<ObjectTabView> {
  int _reloadCounter = 0;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final l10n = AppLocalizations.of(context)!;
    final ref = widget.ref;
    // 公共字段不做流提升，先收窄到局部变量。
    final connectionId = ref.connectionId;
    final connected =
        connectionId == null || provider.isConnectionConnected(connectionId);
    if (!connected) {
      return _buildUnavailable(context, provider, l10n);
    }
    return Column(
      children: [
        _buildToolbar(context, l10n),
        Expanded(
          // 刷新 = 重建内容件（重跑数据加载）。Key 含 _reloadCounter，
          // 同一 dedupKey 下 counter 变化即强制重建。
          child: KeyedSubtree(
            key: ValueKey('object_tab:${ref.dedupKey}:$_reloadCounter'),
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  /// 轻量工具栏：右侧刷新按钮（对象持有期间表被删/数据过期时用户自决
  /// 刷新，不自动关闭）。
  Widget _buildToolbar(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        border: Border(bottom: BorderSide(color: colors.dividerColor)),
      ),
      child: Row(
        children: [
          const Spacer(),
          Tooltip(
            message: l10n.objectTabRefresh,
            child: IconButton(
              icon: Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: colors.textSecondary,
              ),
              onPressed: () => setState(() => _reloadCounter++),
              padding: const EdgeInsets.all(AppDesignSystem.space1),
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final ref = widget.ref;
    switch (ref.kind) {
      case ObjectTabKind.erDiagram:
        return ErDiagramContent(
          initialConnectionId: ref.connectionId,
          initialDatabase: ref.databaseName,
        );
      case ObjectTabKind.tableProperties:
        return TablePropertiesContent(
          tableName: ref.objectName,
          dbName: ref.databaseName ?? '',
          connectionId: ref.connectionId,
          initialTabIndex: ref.initialTabIndex,
        );
    }
  }

  /// 失效态：对象锚定的连接已断开（对象 tab 不随 disconnectConnection
  /// 批量关闭的残留场景、或恢复的会话）。只读视图关闭无确认。
  Widget _buildUnavailable(
    BuildContext context,
    AppProvider provider,
    AppLocalizations l10n,
  ) {
    final colors = context.themeColors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.circleOff,
            size: 40,
            color: colors.textMuted,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.objectTabUnavailable,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: AppDesignSystem.fontSizeLg,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          OutlinedButton.icon(
            onPressed: () {
              final index = provider.tabs.indexWhere(
                (t) => t.id == widget.tabId,
              );
              if (index >= 0) {
                provider.forceCloseTab(index);
              }
            },
            icon: const Icon(LucideIcons.x, size: 14),
            label: Text(l10n.tabClose),
          ),
        ],
      ),
    );
  }
}
