// ============================================================================
// 只读连接守卫（feature 039）—— ReadOnlyBlockedException + 守卫原语
//
// 中立文件：adapter 层（经 AiAdapterMixin）、服务层（DatabaseService/Trigger/
// StoredProcedure）、UI 层共享 import，不依赖 DatabaseService（解 IV 分层）。
// ============================================================================

import '../models/database_models.dart';

/// 只读连接上执行写操作时抛出。
///
/// 服务/adapter 层抛此异常（**不含用户可见文案**，FR-004）；UI 层捕获后映射到
/// `AppLocalizations`（`readOnlyModeBlocked`）。结构化字段供 UI 选 key / 审计消费。
class ReadOnlyBlockedException implements Exception {
  final DatabaseType? databaseType;
  final String? commandName;
  final String? operation;

  const ReadOnlyBlockedException({
    this.databaseType,
    this.commandName,
    this.operation,
  });

  @override
  String toString() {
    final parts = <String>['ReadOnlyBlockedException'];
    if (operation != null) parts.add('operation=$operation');
    if (commandName != null) parts.add('command=$commandName');
    return parts.join(' ');
  }
}

/// 核心守卫原语：`readOnly == true` 则抛 `ReadOnlyBlockedException`（fail-safe）。
///
/// 判定/取值自身异常时不得放行写操作（FR-003）——本函数保持纯判定（无外部依赖），
/// 调用方在取 readOnly 值失败时应按 true 处理（fail-closed）。
void ensureNotReadOnly(
  bool readOnly, {
  DatabaseType? databaseType,
  String? operation,
  String? commandName,
}) {
  if (readOnly) {
    throw ReadOnlyBlockedException(
      databaseType: databaseType,
      operation: operation,
      commandName: commandName,
    );
  }
}

/// 服务层封装（raw-conn 路径用：DatabaseService MySQL 分支 + Trigger/Procedure）。
///
/// `server == null` → **fail-closed**（抛）：写路径上 readOnly 读取失败 = 拒，
/// 宁可误拒不可漏放（FR-003 / contracts C5）。读路径不应调用本函数。
void ensureServerNotReadOnly(
  DbServer? server, {
  String? operation,
  String? commandName,
}) {
  if (server == null || server.readOnly) {
    throw ReadOnlyBlockedException(
      databaseType: server?.type,
      operation: operation,
      commandName: commandName,
    );
  }
}
