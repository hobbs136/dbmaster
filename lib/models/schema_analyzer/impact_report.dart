import 'package:flutter/foundation.dart';

import 'ddl_algorithm.dart';

/// 受影响的对象类型
enum AffectedObjectType {
  view,
  procedure,
  function,
  trigger,
  foreignKey,
  index_,
  constraint,
}

/// 受影响的对象
@immutable
class AffectedObject {
  final AffectedObjectType type;
  final String name;
  final String? schema;
  final String impactDescription;
  final String? dependentColumn;

  const AffectedObject({
    required this.type,
    required this.name,
    this.schema,
    required this.impactDescription,
    this.dependentColumn,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'name': name,
    'schema': schema,
    'impactDescription': impactDescription,
    'dependentColumn': dependentColumn,
  };
}

/// 风险等级
enum RiskLevel {
  low('LOW', 'Low Risk', '低风险'),
  medium('MEDIUM', 'Medium Risk', '中等风险'),
  high('HIGH', 'High Risk', '高风险'),
  critical('CRITICAL', 'Critical Risk', '严重风险');

  final String code;
  final String displayName;
  final String description;

  const RiskLevel(this.code, this.displayName, this.description);

  bool get isHighOrAbove =>
      this == RiskLevel.high || this == RiskLevel.critical;
}

/// Schema 依赖关系
@immutable
class SchemaDependency {
  final String sourceTable;
  final String? sourceColumn;
  final String dependentObject;
  final AffectedObjectType dependentType;
  final String relationship;

  const SchemaDependency({
    required this.sourceTable,
    this.sourceColumn,
    required this.dependentObject,
    required this.dependentType,
    required this.relationship,
  });

  Map<String, dynamic> toJson() => {
    'sourceTable': sourceTable,
    'sourceColumn': sourceColumn,
    'dependentObject': dependentObject,
    'dependentType': dependentType.name,
    'relationship': relationship,
  };
}

/// 回滚脚本
@immutable
class RollbackScript {
  final String originalDdl;
  final String rollbackDdl;
  final String description;
  final bool requiresDataBackup;

  const RollbackScript({
    required this.originalDdl,
    required this.rollbackDdl,
    required this.description,
    this.requiresDataBackup = false,
  });

  Map<String, dynamic> toJson() => {
    'originalDdl': originalDdl,
    'rollbackDdl': rollbackDdl,
    'description': description,
    'requiresDataBackup': requiresDataBackup,
  };
}

/// Schema 影响分析报告
@immutable
class ImpactReport {
  final String ddlStatement;
  final String targetTable;
  final String ddlType;
  final RiskLevel riskLevel;
  final List<AffectedObject> affectedObjects;
  final List<SchemaDependency> dependencies;
  final RollbackScript? rollbackScript;
  final List<String> warnings;
  final List<String> recommendations;
  final bool requiresConfirmation;

  /// 第四阶段 DDL 锁分析：DDL 执行算法（INSTANT/INPLACE/COPY/metadataOnly/unknown）。
  /// 默认 unknown 保证既有调用方零改动可编译（向后兼容）。
  final DdlAlgorithm ddlAlgorithm;

  /// 第四阶段：人类可读锁类型（如「无锁」「全表锁（阻塞写）」）。null = 无信息。
  final String? lockType;

  /// 第四阶段：并发影响（是否阻塞业务写操作）。
  final ConcurrencyImpact concurrencyImpact;

  /// 第四阶段：推断理由（如「MySQL 8.0.12+ ADD COLUMN 默认 INSTANT」）。null = 无信息。
  final String? algorithmNote;

  final DateTime analyzedAt;

  const ImpactReport({
    required this.ddlStatement,
    required this.targetTable,
    required this.ddlType,
    required this.riskLevel,
    required this.affectedObjects,
    required this.dependencies,
    this.rollbackScript,
    required this.warnings,
    required this.recommendations,
    required this.requiresConfirmation,
    // 第四阶段新增：全部有默认值，既有调用方零改动可编译。
    this.ddlAlgorithm = DdlAlgorithm.unknown,
    this.lockType,
    this.concurrencyImpact = ConcurrencyImpact.unknown,
    this.algorithmNote,
    required this.analyzedAt,
  });

  /// 获取各类受影响对象的数量统计
  Map<String, int> get affectedObjectCounts {
    final counts = <String, int>{};
    for (final obj in affectedObjects) {
      counts[obj.type.name] = (counts[obj.type.name] ?? 0) + 1;
    }
    return counts;
  }

  /// 是否有数据丢失风险
  bool get hasDataLossRisk =>
      warnings.any((w) => w.toLowerCase().contains('data loss'));

  Map<String, dynamic> toJson() => {
    'ddlStatement': ddlStatement,
    'targetTable': targetTable,
    'ddlType': ddlType,
    'riskLevel': riskLevel.name,
    'affectedObjects': affectedObjects.map((o) => o.toJson()).toList(),
    'dependencies': dependencies.map((d) => d.toJson()).toList(),
    'rollbackScript': rollbackScript?.toJson(),
    'warnings': warnings,
    'recommendations': recommendations,
    'requiresConfirmation': requiresConfirmation,
    'affectedObjectCounts': affectedObjectCounts,
    'hasDataLossRisk': hasDataLossRisk,
    // 第四阶段 DDL 锁字段。
    'ddlAlgorithm': ddlAlgorithm.name,
    'lockType': lockType,
    'concurrencyImpact': concurrencyImpact.name,
    'algorithmNote': algorithmNote,
    'analyzedAt': analyzedAt.toIso8601String(),
  };
}
