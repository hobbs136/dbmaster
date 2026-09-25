import 'package:flutter/foundation.dart';

import '../../models/ai_conversation_session.dart';
import '../../models/workbench_context_lock.dart';
import '../../organisms/sidebar/sidebar_current_connection.dart';
import '../../providers/app_provider.dart';

/// 上下文芯片来源（R3 AC3.2 明示：芯片展示「活动 tab / 侧栏」来源标识）。
enum WorkbenchContextSource { activeTab, sidebar, none }

/// 工作台生效上下文的解析值（design-ai-workbench §4.2，纯数据）。
///
/// [source] == [WorkbenchContextSource.none] 时其余字段为 null（未设置态，
/// AC3.6：不阻塞输入，芯片显示设置引导）。
@immutable
class WorkbenchContextValue {
  final String? connectionId;

  /// 展示用连接名（由 connectionId 从 savedConnections 解析；找不到时以
  /// id 兜底显示，§7.3 错误路径——不显示 null）。
  final String? connectionName;

  final String? databaseName;

  final WorkbenchContextSource source;

  const WorkbenchContextValue({
    this.connectionId,
    this.connectionName,
    this.databaseName,
    required this.source,
  }) : assert(
         source == WorkbenchContextSource.none || connectionId != null,
         '非 none 来源必须携带 connectionId',
       );

  /// 是否有可用上下文（执行流 T13 的复核判据）。
  bool get isAvailable => connectionId != null;
}

/// 跟随态解析（R3 AC3.3/AC3.4 继承序：活动 tab 优先 → 侧栏次之 → none）。
///
/// ⚠ 继承序与侧栏锚定序**不同**，两序各自独立存在，不复用不合并
/// （design §5.1 专门警告）：
/// - [resolveSidebarCurrentConnection] 的序 = currentServer → 活动 tab →
///   侧栏选中——那是「树锚定」序：显式切换语义高于 tab 上下文，倒序会导致
///   「开着旧连接 tab 时切换永远被抢回」（SST-C22-003 回归守卫）。
/// - 本函数的序 = 活动 tab（isContextBound）→ 侧栏三源 → none——这是
///   「AI 对谁说话」的序，按需求 R3.3 锁定：用户正在编辑的 tab 上下文
///   即 AI 的默认对话对象，仅在 tab 未绑定上下文时才看侧栏。
/// 因此活动 tab 已绑定而用户又显式切换侧栏连接时，本函数仍取 tab——
/// 这是需求语义，不是 bug；侧栏树渲染仍由锚定序保证跟随显式切换。
WorkbenchContextValue resolveWorkbenchContext(AppProvider provider) {
  final tab = provider.tab.activeTab;
  final tabConnectionId = tab?.connectionId;
  if (tab != null && tab.isContextBound && tabConnectionId != null) {
    return WorkbenchContextValue(
      connectionId: tabConnectionId,
      connectionName: _connectionNameOf(provider, tabConnectionId),
      databaseName: tab.databaseName,
      source: WorkbenchContextSource.activeTab,
    );
  }
  // 未绑定 tab：走侧栏三源解析（currentServer → 活动 tab → 侧栏选中）。
  // 注意 tab.connectionId 在侧栏序内仍可能作为第二优先级浮出——结果值
  // 相同但来源标识为 sidebar，这正是两序差异的可观察面。
  final server = resolveSidebarCurrentConnection(provider);
  if (server != null) {
    return WorkbenchContextValue(
      connectionId: server.id,
      connectionName: server.name,
      databaseName: server.database ?? tab?.databaseName,
      source: WorkbenchContextSource.sidebar,
    );
  }
  return const WorkbenchContextValue(source: WorkbenchContextSource.none);
}

/// 生效上下文 = 锁定快照优先，否则跟随解析（纯函数，芯片与执行流共用，
/// design §4.2）。[session] 为当前会话（`sessionManager.currentSession`），
/// null 会话视同未锁定。
WorkbenchContextValue effectiveWorkbenchContext(
  AiConversationSession? session,
  AppProvider provider,
) {
  final lock = WorkbenchContextLock.fromMetadata(session?.metadata);
  if (lock != null) {
    return WorkbenchContextValue(
      connectionId: lock.connectionId,
      connectionName: _connectionNameOf(provider, lock.connectionId),
      databaseName: lock.databaseName,
      // 锁定快照不携带来源，source 不参与锁定态展示：消费方（T11 芯片）
      // 应以 provider.workbenchContextLock != null 判定锁定态并展示锁定
      // 徽标，而非来源徽标。枚举面按 design §4.2 契约不扩值，此处取
      // sidebar 仅为满足「非 none 来源 ⇒ connectionId != null」约束。
      source: WorkbenchContextSource.sidebar,
    );
  }
  return resolveWorkbenchContext(provider);
}

/// 连接名解析：savedConnections 命中返回展示名，未命中以 id 兜底（§7.3）。
String _connectionNameOf(AppProvider provider, String connectionId) {
  for (final server in provider.savedConnections) {
    if (server.id == connectionId) return server.name;
  }
  return connectionId;
}
