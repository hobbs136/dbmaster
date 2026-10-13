// C22-1 → J3 · 侧栏「当前锚定」解析（执行默认优先序）。
//
// 解析序：currentServer → 活动 tab → 侧栏选中。
// ⚠ currentServer 必须优先于活动 tab（2026-08-20 走查反馈修复，序位保留）：
// 用户显式切换连接后 switchToConnection 写入 currentServer，显式切换动作
// 的语义高于 tab 上下文；tab 优先仅在无显式当前连接时兜底。
// ⚠ 与 C14 resolveCapabilityMenuServer **不再同序**（T25 序位反转：能力
// 菜单锚定改「活动 tab 优先」——J3 多连接长驻树删除连接切换入口后
// 「开着旧 tab 时切换被抢回」场景消亡）；本函数服务执行默认/命令动作/
// 键盘导航锚定，两序并存为 T25 定案。
// SidebarTree、控制器键盘导航、命令面板、workbench 上下文解析共用。
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
