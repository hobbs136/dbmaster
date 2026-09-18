// C22-1 · 当前活动连接解析 —— 单实例专注树的锚定源。
//
// 解析序：currentServer → 活动 tab → 侧栏选中。
// ⚠ currentServer 必须优先于活动 tab（2026-08-20 走查反馈修复）：用户开着
// 连接 A 的查询 tab 时经选择器切换连接 B，switchToConnection 写入
// currentServer=B 但 activeTab 仍属 A——若 tab 优先，树永远停留在 A，
// 呈现「切换不成功」。显式切换动作的语义高于 tab 上下文；tab 优先仅在
// 无显式当前连接时兜底（与 C14 resolveCapabilityMenuServer 同序）。
// 选择器、SidebarTree、visible_nodes 三处共用，
// 保证「选择器显示谁、树就渲染谁、键盘导航就覆盖谁」。
import '../../models/database_models.dart' show DbServer;
import '../../providers/app_provider.dart';

DbServer? resolveSidebarCurrentConnection(AppProvider provider) {
  final id =
      provider.connection.currentServer?.id ??
      provider.tab.activeTab?.connectionId ??
      provider.sidebar.selectedConnectionId;
  if (id == null) return null;
  for (final server in provider.savedConnections) {
    if (server.id == id) return server;
  }
  return null;
}
