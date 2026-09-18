// C14 · 能力菜单装配 —— 插件合并 + port 门控 + 来源徽章解析。
//
// 原型 `sidebar-capability-menu.html` 的数据装配半边：多个 SidebarPlugin
// （core 通用件 + per-type 件，注册序）的 capabilityGroups 按「组 id 合并、
// 项 id 去重（后者覆盖前者 = 更具体的 per-type/Pro 插件可整体替换 core 项，
// 与 PluginRegistry override 同精神）」合成，再按铁律 2 经
// `DbCapabilityPort.hasCapability` 逐项门控——位取 false（含未知位 id）即
// 隐藏，组内清空即整组隐藏。UI 层不做任何 `DatabaseType.` 能力分支。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../services/ports/db_capability_port.dart';

/// 装配后的单项（原始项 + 徽章元数据）。
@immutable
class AssembledCapabilityItem {
  final SidebarCapabilityItem item;

  /// 来源徽章文本：`core` / `<type>-plugin` / `ai-plugin`（原型徽章形态）。
  final String badge;

  /// ai 来源徽章用品牌色（原型 ai-plugin 徽章 = 主色底白字）。
  final bool fromAi;

  const AssembledCapabilityItem({
    required this.item,
    required this.badge,
    required this.fromAi,
  });
}

/// 装配后的分组（标签已按 l10n 解析为纯文本）。
@immutable
class AssembledCapabilityGroup {
  final String id;
  final String label;
  final IconData icon;
  final List<AssembledCapabilityItem> items;

  const AssembledCapabilityGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.items,
  });
}

/// 来源徽章文本。铁律 2 的 UI 侧落点：徽章只反映「谁提供的这块 UI」，
/// 不携带能力语义（能力真值永远来自 port）。
String capabilityBadgeLabel(PluginDescriptor descriptor, DatabaseType type) {
  switch (descriptor.source) {
    case PluginSource.core:
      return 'core';
    case PluginSource.databaseType:
      return '${type.name}-plugin';
    case PluginSource.ai:
      return 'ai-plugin';
  }
}

/// 能力菜单的活动连接锚定（C14）：currentServer 优先；为空时回退
/// 「活动 tab 的连接 → 侧栏选中节点」（与折叠 rail 同源解析），且仅在该
/// 连接**已连接**时提供——菜单动作（对话框/面板）假定活连接，选中但
/// 未连接的节点不提供锚点（动作会打到错误连接上）。
DbServer? resolveCapabilityMenuServer({
  required DbServer? currentServer,
  required String? activeTabConnectionId,
  required String? selectedConnectionId,
  required bool Function(String connectionId) isConnected,
  required Iterable<DbServer> savedConnections,
}) {
  if (currentServer != null) return currentServer;
  final id =
      activeTabConnectionId ?? selectedConnectionId;
  if (id == null) return null;
  if (!isConnected(id)) return null;
  for (final server in savedConnections) {
    if (server.id == id) return server;
  }
  return null;
}

/// 插件侧便捷锚定（C15）：capabilityGroups/onActivate 闭包里解析活动连接。
/// 与菜单 widget 的锚定同源同参（[resolveCapabilityMenuServer] 的 provider
/// 读值包装）——菜单渲染用哪个连接，插件动作就打到哪个连接。
DbServer? resolveSidebarActionServer(BuildContext context) {
  final provider = context.read<AppProvider>();
  return resolveCapabilityMenuServer(
    currentServer: provider.connection.currentServer,
    activeTabConnectionId: provider.tab.activeTab?.connectionId,
    selectedConnectionId: provider.sidebar.selectedConnectionId,
    isConnected: provider.isConnectionConnected,
    savedConnections: provider.savedConnections,
  );
}

/// 合并 [plugins]（注册序）的能力分组并按 [port] 门控。
///
/// [context] 是宿主 build 上下文，透传给 `capabilityGroups`——插件的
/// onActivate 闭包在构造期捕获它（见 SidebarCapabilityItem.onActivate 契约），
/// 因此装配必须在真实 widget 生命周期内调用。
///
/// 返回可直接渲染的组列表；无可见项时返回空列表（宿主隐藏整段）。
List<AssembledCapabilityGroup> assembleCapabilityMenu({
  required BuildContext context,
  required DatabaseType type,
  required DbCapabilityPort port,
  required List<SidebarPlugin> plugins,
  required AppLocalizations l10n,
}) {
  // 组 id → 合并中的组数据（保持首次出现顺序）
  final groupOrder = <String>[];
  final labels = <String, String>{};
  final icons = <String, IconData>{};
  // 项 id → 所属组 id（跨组移动 = 先移除再追加，覆盖语义）
  final itemGroup = <String, String>{};
  final items = <String, AssembledCapabilityItem>{};

  for (final plugin in plugins) {
    final badge = capabilityBadgeLabel(plugin.descriptor, type);
    final fromAi = plugin.descriptor.source == PluginSource.ai;
    for (final group in plugin.capabilityGroups(context)) {
      if (!groupOrder.contains(group.id)) {
        groupOrder.add(group.id);
        labels[group.id] = group.label(l10n);
        icons[group.id] = group.icon;
      }
      for (final item in group.items) {
        if (item.capabilityId != null &&
            !port.hasCapability(type, item.capabilityId!)) {
          continue;
        }
        final previousGroup = itemGroup[item.id];
        if (previousGroup != null && previousGroup != group.id) {
          itemGroup.remove(item.id);
        }
        itemGroup[item.id] = group.id;
        items[item.id] = AssembledCapabilityItem(
          item: item,
          badge: badge,
          fromAi: fromAi,
        );
      }
    }
  }

  final grouped = <String, List<AssembledCapabilityItem>>{};
  for (final entry in items.entries) {
    grouped.putIfAbsent(itemGroup[entry.key]!, () => []).add(entry.value);
  }
  return [
    for (final id in groupOrder)
      if ((grouped[id] ?? const []).isNotEmpty)
        AssembledCapabilityGroup(
          id: id,
          label: labels[id]!,
          icon: icons[id]!,
          items: grouped[id]!,
        ),
  ];
}
