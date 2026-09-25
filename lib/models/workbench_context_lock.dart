import 'package:flutter/foundation.dart';

/// 工作台上下文锁定快照（design-ai-workbench §4.3/§5.1，T08）。
///
/// 存储位置：`AiConversationSession.metadata['workbench.contextLock']`——会话级
/// 存储，随会话持久化、随会话切换各自携带、随会话删除而消亡（AC3.5）。
/// 读写经 `AiPanelProvider.lockWorkbenchContext` / `unlockWorkbenchContext` /
/// `workbenchContextLock` 三个薄成员（AiSessionManager 不感知锁定，锁定作为
/// metadata 数据透传、经既有 toJson/fromJson 序列化路径落盘）。
///
/// C-3 升级口：M2「会话显式持有上下文」= 同一 `workbench.context*` 命名空间从
/// 「锁定快照」升级为「默认持有」，加法扩展，不破坏旧会话 JSON（无键 = 跟随态，
/// 键在 = 持有）。
@immutable
class WorkbenchContextLock {
  /// 会话 metadata 内的存储键（`workbench.context` 命名空间族，C-3）。
  static const String metadataKey = 'workbench.contextLock';

  final String connectionId;

  /// 锁定时的库名快照；null = 锁定到连接级（未指定库）。
  final String? databaseName;

  final DateTime lockedAt;

  const WorkbenchContextLock({
    required this.connectionId,
    this.databaseName,
    required this.lockedAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'connectionId': connectionId,
    'databaseName': databaseName,
    'lockedAt': lockedAt.toIso8601String(),
  };

  /// 从会话 metadata 解析锁定快照。
  ///
  /// metadata 为空 / 无键 / 数据畸形（类型不符、时间不可解析）时返回 null
  /// （null = 跟随态或损坏数据兜底，不抛异常——旧会话与手改文件都要安全）。
  /// [lockedAt] 无法解析时回退当前时间（该字段仅作展示，不影响锁定语义）。
  static WorkbenchContextLock? fromMetadata(Map<String, dynamic>? metadata) {
    final raw = metadata?[metadataKey];
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final connectionId = json['connectionId'];
    if (connectionId is! String || connectionId.isEmpty) return null;
    final databaseName = json['databaseName'];
    final lockedAtRaw = json['lockedAt'];
    final lockedAt = lockedAtRaw is String
        ? DateTime.tryParse(lockedAtRaw)
        : null;
    return WorkbenchContextLock(
      connectionId: connectionId,
      databaseName: databaseName is String ? databaseName : null,
      lockedAt: lockedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkbenchContextLock &&
          runtimeType == other.runtimeType &&
          connectionId == other.connectionId &&
          databaseName == other.databaseName &&
          lockedAt == other.lockedAt;

  @override
  int get hashCode => Object.hash(connectionId, databaseName, lockedAt);
}
