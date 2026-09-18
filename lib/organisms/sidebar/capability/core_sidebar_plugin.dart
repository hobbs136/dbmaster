// C14 · core 侧边栏插件 —— 跨类型通用能力菜单层（原型徽章「core」项）。
//
// 与 per-type 插件（C15-C18 落地）的关系：本插件只提供**通用件**——入口
// 是跨类型一致的对话框/面板（存储过程/触发器/Schema 对比/AI 面板）；
// 类型专有能力（Kill Query/Engine Status/超级表…）归各类型插件的
// capabilityGroups，经同一装配合并（后者同 id 项覆盖前者）。
//
// 铁律 2/3 落点：①每个能力项都带 capabilityId，展示与否由宿主经
// DbCapabilityPort 门控（本文件零 DatabaseType 分支）；②onActivate 只调
// 既有通用入口（AppProvider / 通用对话框），不 import 任何 adapter。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../connection/schema_diff_dialog.dart';
import '../../dialogs/stored_procedures_dialog.dart';
import '../../dialogs/triggers_dialog.dart';
import '../../../services/stored_procedure_service.dart';
import '../../../services/trigger_service.dart';
import 'generic_sql_database_tree.dart';

class CoreSidebarPlugin implements SidebarPlugin {
  const CoreSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'core-sidebar',
        source: PluginSource.core,
        icon: LucideIcons.layoutGrid,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) {
    return [
      SidebarCapabilityGroup(
        id: 'database-objects',
        label: (l10n) => l10n.sidebarCapGroupDatabaseObjects,
        icon: LucideIcons.database,
        items: [
          SidebarCapabilityItem(
            id: 'proc.list',
            capabilityId: 'proc.list',
            label: (l10n) => l10n.sidebarProcedures,
            icon: LucideIcons.terminal,
            onActivate: () => _showStoredProcedures(context),
          ),
          SidebarCapabilityItem(
            id: 'func.list',
            capabilityId: 'func.list',
            label: (l10n) => l10n.sidebarFunctions,
            icon: LucideIcons.sigma,
            onActivate: () => _showStoredProcedures(context),
          ),
          SidebarCapabilityItem(
            id: 'trigger.list',
            capabilityId: 'trigger.list',
            label: (l10n) => l10n.sidebarTriggers,
            icon: LucideIcons.zap,
            onActivate: () => _showTriggers(context),
          ),
        ],
      ),
      SidebarCapabilityGroup(
        id: 'advanced',
        label: (l10n) => l10n.sidebarCapGroupAdvanced,
        icon: LucideIcons.wrench,
        items: [
          SidebarCapabilityItem(
            id: 'schema.diff',
            capabilityId: 'schema.diff',
            label: (l10n) => l10n.schemaDiffMenuItem,
            icon: LucideIcons.gitCompare,
            onActivate: () => _showSchemaDiff(context),
          ),
          SidebarCapabilityItem(
            id: 'ai.assistant',
            capabilityId: 'ai.assistant',
            label: (l10n) => l10n.aiAssistant,
            icon: LucideIcons.bot,
            highlight: true,
            onActivate: () => context.read<AppProvider>().toggleAiPanel(),
          ),
        ],
      ),
    ];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    // core 插件只供能力菜单；对象树由 per-type 插件（C15+）提供。
    // 空树 = 宿主回退旧装配（sidebar_tree 分缝契约，C19 删旧路径）。
    return const [];
  }

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) {
    // C19 反转：树分缝遍历序 per-type 先、core 殿后——本树是泛 SQL 库级
    // 共享兜底（MySQL/Doris/CH + 未来 gateway-only 新类型），per-type 插件
    // （PG/Mongo/TD/SS）非空即在其前接管。
    return buildGenericSqlDatabaseTree(context, db);
  }

  // ── 通用入口（复用 SidebarWidget 既有对话框路由的接线模式）──

  /// 当前工作库（对话框数据目标）：活动 tab → 侧栏选中库 → 连接当前库。
  String? _currentDatabase(AppProvider provider) =>
      provider.tab.activeTab?.databaseName ??
      provider.sidebar.selectedDatabaseName ??
      provider.connection.currentDatabase?.name;

  void _showStoredProcedures(BuildContext context) {
    final provider = context.read<AppProvider>();
    final service = StoredProcedureService(provider.dbService);
    showDialog(
      context: context,
      builder: (_) => StoredProceduresDialog(
        service: service,
        initialDatabase: _currentDatabase(provider),
      ),
    );
  }

  void _showTriggers(BuildContext context) {
    final service = TriggerService(context.read<AppProvider>().dbService);
    showDialog(
      context: context,
      builder: (_) => TriggersDialog(service: service),
    );
  }

  void _showSchemaDiff(BuildContext context) {
    final provider = context.read<AppProvider>();
    final activeTab = provider.tab.activeTab;
    SchemaDiffDialog.show(
      context: context,
      initialConnectionId:
          activeTab?.connectionId ?? provider.sidebar.selectedConnectionId,
      initialDatabaseName:
          activeTab?.databaseName ?? provider.sidebar.selectedDatabaseName,
    );
  }
}
