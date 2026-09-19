// 连接失败统一结构化载体（连接失败 UX 重构 T1）。
//
// 背景：适配器连接失败后的错误信息被多层吞掉，UI 只弹固定文案。本文件是
// 全部下游任务（SQLite 适配器改造、失败对话框、网关族推广）的契约基石：
// 适配器在 connect 失败路径构造 ConnectionFailure 并以 AdapterConnectException
// 包装抛出（保留原始异常链），展示层按 ConnectionFailureKind 分型呈现，
// 而不是解析原始错误字符串。
//
// 契约冻结：字段命名与函数签名以 docs/tasks/task_error_ux.md 契约快照为准，
// 不得更改。本文件保持纯 model——零第三方 import（仅隐式 dart:core），
// 下游 import 本模型不会连带引入 sqflite/sqlite3 等适配器侧包。
// rawMessage 为原始异常消息（未脱敏；展示边界负责脱敏），
// AdapterConnectException.cause 保留原始异常供日志排查。

/// 连接失败的语义分型。
///
/// 展示层与诊断逻辑按此分派，而非解析原始消息文本。
enum ConnectionFailureKind {
  /// 文件被锁（SQLite 结果码 5/6：BUSY/LOCKED，如 journal/WAL 占用）。
  fileLocked,

  /// 文件不存在（SQLite 结果码 14：CANTOPEN）。
  fileNotFound,

  /// 权限拒绝（SQLite 结果码 3/8：PERM/READONLY）。
  permissionDenied,

  /// 不是数据库文件（SQLite 结果码 26：NOTADB）。
  notADatabase,

  /// 数据库损坏（SQLite 结果码 11：CORRUPT）。
  corrupt,

  /// 凭据/认证被拒（网关稳定码 AUTH_DENIED：用户名/密码/认证机制失败）。
  authFailed,

  /// 网络不可达（网关稳定码 UNREACHABLE：DNS 解析失败、TCP 拒绝/重置、
  /// SSH 隧道建立失败）。
  unreachable,

  /// 未归类失败（网关 envelope 无码/未列码（含 TIMEOUT、DB_ERROR）时此型；
  /// 无码或未列码的 SQLite 失败同）。
  unknown,
}

/// 一次连接失败的结构化描述。
class ConnectionFailure {
  /// 失败语义分型。
  final ConnectionFailureKind kind;

  /// 原始错误码（SQLite='5'；网关=envelope code/engineCode；无码=''）。
  final String errorCode;

  /// 出错语句（如 'PRAGMA journal_mode = DELETE'）；未知为 null。
  final String? offendingStatement;

  /// 失败目标：SQLite=文件路径；网关族=host:port；未知为 null。
  final String? target;

  /// 原始异常消息（未脱敏；展示边界负责脱敏）。
  final String rawMessage;

  /// 失败发生时间。
  final DateTime occurredAt;

  const ConnectionFailure({
    required this.kind,
    required this.errorCode,
    this.offendingStatement,
    this.target,
    required this.rawMessage,
    required this.occurredAt,
  });
}

/// 适配器 connect 失败的统一异常类型。
///
/// 携带结构化 [failure] 供展示层分型；[cause] 保留原始异常（异常链不断）。
class AdapterConnectException implements Exception {
  /// 结构化失败描述。
  final ConnectionFailure failure;

  /// 原始异常，保留链。
  final Object cause;

  const AdapterConnectException(this.failure, this.cause);

  @override
  String toString() =>
      'AdapterConnectException(${failure.kind}, code=${failure.errorCode}): ${failure.rawMessage}';
}

/// SQLite 原生结果码 → [ConnectionFailureKind]（设计锁定）。
///
/// 映射：5/6→fileLocked；14→fileNotFound；3/8→permissionDenied；
/// 26→notADatabase；11→corrupt；null/其余→unknown。
ConnectionFailureKind sqliteKindFromResultCode(int? code) => switch (code) {
  5 || 6 => ConnectionFailureKind.fileLocked,
  14 => ConnectionFailureKind.fileNotFound,
  3 || 8 => ConnectionFailureKind.permissionDenied,
  26 => ConnectionFailureKind.notADatabase,
  11 => ConnectionFailureKind.corrupt,
  _ => ConnectionFailureKind.unknown,
};

/// 网关 envelope → [ConnectionFailure]。
///
/// 设计锁定：errorCode = code ?? engineCode ?? ''；kind 按 [code] 稳定码
/// 映射（T12c：AUTH_DENIED→authFailed、UNREACHABLE→unreachable，TIMEOUT/
/// DB_ERROR 及其余未列码→unknown；TIMEOUT 不唯一指"端口没开"，文案不断言
/// 单一成因）；rawMessage = message（envelope 含 engineCode 时追加
/// engineCode 后缀，后缀格式为 ` (engine code: <engineCode>)`，属实现自决
/// 项）。[occurredAt] 缺省取当前时间。
ConnectionFailure gatewayEnvelopeFailure({
  required String? code,
  String? engineCode,
  required String message,
  String? target,
  DateTime? occurredAt,
}) {
  final resolvedCode = code ?? engineCode ?? '';
  final kind = switch (code) {
    'AUTH_DENIED' => ConnectionFailureKind.authFailed,
    'UNREACHABLE' => ConnectionFailureKind.unreachable,
    _ => ConnectionFailureKind.unknown,
  };
  final rawMessage = engineCode == null
      ? message
      : '$message (engine code: $engineCode)';
  return ConnectionFailure(
    kind: kind,
    errorCode: resolvedCode,
    target: target,
    rawMessage: rawMessage,
    occurredAt: occurredAt ?? DateTime.now(),
  );
}
