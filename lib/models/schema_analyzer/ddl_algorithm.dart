import 'package:flutter/foundation.dart';

/// DDL 执行算法（业务语义分类，基于 MySQL Online DDL）。
///
/// 第四阶段 DDL 锁分析（requirements-phase4.md R13）。
/// 用于 [ImpactReport] 的锁语义展示 + [ImpactAssessor] 评级修正。
enum DdlAlgorithm {
  /// INSTANT：只改元数据，秒级，无锁。
  /// （MySQL 8.0.12+ ADD COLUMN 末尾 / 8.0.29+ DROP COLUMN）。
  instant,

  /// INPLACE：InnoDB 内部重建，LOCK=NONE 时允许并发 DML。
  /// （ADD INDEX / 多数 ADD COLUMN 非末尾）。
  inplace,

  /// COPY：创建新表 + 拷贝数据 + 改名，全表锁，阻塞写。
  /// （改列类型 / 改字符集退化路径）。
  copy,

  /// 元数据锁：只改元数据表（TRUNCATE / DROP / RENAME），瞬间但破坏性。
  metadataOnly,

  /// 未知：非 MySQL 库 / 版本探测失败 / 不支持的 DDL。
  /// 保守按 INPLACE/COPY 处理。
  unknown;

  /// 是否阻塞并发 DML（COPY 全表锁，阻塞业务写）。
  bool get blocksDml => this == DdlAlgorithm.copy;

  /// 是否允许并发 DML（INPLACE + LOCK=NONE，轻微影响）。
  bool get allowsConcurrentDml => this == DdlAlgorithm.inplace;

  /// 是否无锁（可在线执行）：INSTANT 与 metadataOnly 都只动元数据。
  bool get isLockFree =>
      this == DdlAlgorithm.instant || this == DdlAlgorithm.metadataOnly;
}

/// 并发影响（是否阻塞业务写操作）。
///
/// 与 [DdlAlgorithm] 的并发语义对应，用于 UI 直观展示 + 评级。
enum ConcurrencyImpact {
  /// 无影响（INSTANT / metadataOnly，秒级无锁）。
  none,

  /// 轻微（INPLACE + LOCK=NONE 允许并发 DML）。
  allowsConcurrentDml,

  /// 阻塞写（COPY 全表锁，业务写全卡）。
  blocksDml,

  /// 未知（版本探测失败 / 非 MySQL / 不支持的 DDL）。
  unknown,
}

/// 锁语义推断结果（来自 [DdlAlgorithmInferrer.infer]）。
///
/// 第四阶段 DDL 锁分析（design-phase4.md §4.1）。
/// 不可变值对象，承载 algorithm + 人类可读锁类型 + 并发影响 + 推断理由。
@immutable
class DdlAlgorithmResult {
  /// 推断出的 DDL 执行算法。
  final DdlAlgorithm algorithm;

  /// 人类可读锁类型（如「无锁」「元数据锁（允许并发 DML）」「全表锁（阻塞写）」）。
  /// null 时 UI 可回退到 [algorithm] 的默认描述。
  final String? lockType;

  /// 并发影响（是否阻塞业务写）。
  final ConcurrencyImpact concurrencyImpact;

  /// 推断理由（如「MySQL 8.0.12+ ADD COLUMN 默认 INSTANT」）。
  /// null 时 UI 不展示该行。
  final String? note;

  const DdlAlgorithmResult({
    required this.algorithm,
    this.lockType,
    required this.concurrencyImpact,
    this.note,
  });

  /// 未知结果（非 MySQL / 探测失败）的便捷常量。
  /// algorithm=unknown + concurrencyImpact=unknown，无 lockType/note。
  static const DdlAlgorithmResult unknown = DdlAlgorithmResult(
    algorithm: DdlAlgorithm.unknown,
    concurrencyImpact: ConcurrencyImpact.unknown,
  );
}
