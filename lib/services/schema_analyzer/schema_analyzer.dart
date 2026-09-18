import 'dart:developer' as developer;

import '../../models/schema_analyzer/ddl_algorithm.dart';
import '../../models/schema_analyzer/impact_report.dart';
import 'ddl_algorithm_inferrer.dart';
import 'dependency_analyzer.dart';
import 'impact_assessor.dart';
import 'rollback_generator.dart';

export '../../models/schema_analyzer/impact_report.dart';

/// Schema 影响分析器
/// 分析 DDL 变更的影响范围和风险等级
class SchemaAnalyzer {
  /// 分析 DDL 语句的影响
  ///
  /// 第四阶段扩展（design §4.3）：新增 [getServerVersion] 回调用于锁语义推断。
  /// 不传 → 锁字段为 unknown，评级回落既有行数阈值（向后兼容）。
  static Future<ImpactReport> analyzeDdl({
    required String ddlStatement,
    required String databaseType,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    String? targetTable,
    String? columnName,
    String? columnType,
    int? estimatedAffectedRows,
    /// 第四阶段：版本查询回调（可选）。
    /// 返回 SELECT VERSION() 结果（如 '8.0.32'）。失败/不传 → 锁语义标 unknown。
    Future<String?> Function()? getServerVersion,
    /// B2：INPLACE 评级的行数阈值。小表（≤ 阈值）INPLACE 操作 → low（不骚扰）；
    /// 大表 → medium（提示耗时）。默认 100000。由调用方从
    /// `SafetyConfig.fullScanRowThreshold` 传入。
    int inplaceMediumRowThreshold = 100000,
  }) async {
    // 1. 解析 DDL 类型和目标表
    final ddlType = ImpactAssessor.extractDdlType(ddlStatement);
    final tableName =
        targetTable ?? ImpactAssessor.extractTargetTable(ddlStatement);

    developer.log(
      'Analyzing DDL: $ddlType on $tableName',
      name: 'SchemaAnalyzer',
    );

    // 2. 获取表行数（如果未提供）
    int rowCount = estimatedAffectedRows ?? 0;
    if (rowCount == 0 && tableName != 'unknown') {
      try {
        final countResult = await executeQuery(
          'SELECT COUNT(*) as count FROM $tableName',
        );
        if (countResult.isNotEmpty) {
          // 兼容多驱动的 count 返回类型：mysql_client 返 String、
          // postgres/sqlite 可能返 int/num。统一解析避免 cast 异常。
          final raw = countResult.first['count'];
          rowCount = _parseRowCount(raw);
        }
      } catch (e) {
        developer.log('Could not get row count: $e', name: 'SchemaAnalyzer');
      }
    }

    // 3. 分析依赖关系
    List<SchemaDependency> dependencies = [];
    if (tableName != 'unknown') {
      dependencies = await DependencyAnalyzer.analyzeTableDependencies(
        tableName: tableName,
        executeQuery: executeQuery,
        databaseType: databaseType,
      );

      // 如果是列级操作，额外分析列依赖
      if (columnName != null || ddlType.contains('COLUMN')) {
        final colName =
            columnName ??
            RollbackGenerator.extractColumnName(ddlStatement, ddlType);
        if (colName != null) {
          final columnDeps = await DependencyAnalyzer.analyzeColumnDependencies(
            tableName: tableName,
            columnName: colName,
            executeQuery: executeQuery,
            databaseType: databaseType,
          );
          dependencies.addAll(columnDeps);
        }
      }
    }

    // 4.【第四阶段】推断锁语义（DDL 类型 + MySQL 版本 → algorithm）。
    //    getServerVersion 失败/不传 → null → inferrer 返回 unknown（保守降级）。
    String? serverVersion;
    if (getServerVersion != null) {
      try {
        serverVersion = await getServerVersion();
      } catch (e) {
        developer.log(
          'Could not get server version: $e',
          name: 'SchemaAnalyzer',
        );
        serverVersion = null;
      }
    }
    final algoResult = DdlAlgorithmInferrer.infer(
      ddlStatement: ddlStatement,
      ddlType: ddlType,
      databaseType: databaseType,
      serverVersion: serverVersion,
    );

    // 5. 评估风险等级（第四阶段：传入 algorithm 维度；B2：传入 INPLACE 行数阈值）
    final riskLevel = ImpactAssessor.assessRiskLevel(
      ddlStatement: ddlStatement,
      ddlType: ddlType,
      dependencies: dependencies,
      estimatedAffectedRows: rowCount,
      algorithmResult: algoResult,
      inplaceMediumRowThreshold: inplaceMediumRowThreshold,
    );

    // 6. 生成受影响对象列表
    final affectedObjects = _convertToAffectedObjects(dependencies);

    // 7. 生成警告
    final warnings = ImpactAssessor.generateWarnings(
      ddlStatement: ddlStatement,
      ddlType: ddlType,
      dependencies: dependencies,
      estimatedAffectedRows: rowCount,
    );

    // 8. 生成建议
    final recommendations = ImpactAssessor.generateRecommendations(
      ddlType: ddlType,
      riskLevel: riskLevel,
      dependencies: dependencies,
    );

    // 9. 生成回滚脚本
    final rollbackScript = RollbackGenerator.generateRollback(
      ddlStatement: ddlStatement,
      ddlType: ddlType,
      tableName: tableName,
      columnName: columnName,
      columnType: columnType,
      databaseType: databaseType,
    );

    // 10. 确定是否需要确认
    final requiresConfirmation = ImpactAssessor.requiresConfirmation(riskLevel);

    return ImpactReport(
      ddlStatement: ddlStatement,
      targetTable: tableName,
      ddlType: ddlType,
      riskLevel: riskLevel,
      affectedObjects: affectedObjects,
      dependencies: dependencies,
      rollbackScript: rollbackScript,
      warnings: warnings,
      recommendations: recommendations,
      requiresConfirmation: requiresConfirmation,
      // 第四阶段锁字段。
      ddlAlgorithm: algoResult.algorithm,
      lockType: algoResult.lockType,
      concurrencyImpact: algoResult.concurrencyImpact,
      algorithmNote: algoResult.note,
      analyzedAt: DateTime.now(),
    );
  }

  /// 快速分析（用于 AI Tool 调用）
  ///
  /// 第四阶段：新增可选 [getServerVersion] 回调（透传给 analyzeDdl 做锁语义推断）。
  static Future<Map<String, dynamic>> analyzeDdlForAI({
    required String ddlStatement,
    required String databaseType,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    Future<String?> Function()? getServerVersion,
  }) async {
    final report = await analyzeDdl(
      ddlStatement: ddlStatement,
      databaseType: databaseType,
      executeQuery: executeQuery,
      getServerVersion: getServerVersion,
    );

    return {
      'success': true,
      'ddlType': report.ddlType,
      'targetTable': report.targetTable,
      'riskLevel': report.riskLevel.name,
      'riskDisplayName': report.riskLevel.displayName,
      'affectedObjects': report.affectedObjects.map((o) => o.toJson()).toList(),
      'affectedObjectCounts': report.affectedObjectCounts,
      // 第四阶段锁字段。
      'ddlAlgorithm': report.ddlAlgorithm.name,
      'lockType': report.lockType,
      'concurrencyImpact': report.concurrencyImpact.name,
      'algorithmNote': report.algorithmNote,
      'dependencies': report.dependencies.map((d) => d.toJson()).toList(),
      'rollbackScript': report.rollbackScript?.toJson(),
      'warnings': report.warnings,
      'recommendations': report.recommendations,
      'requiresConfirmation': report.requiresConfirmation,
      'hasDataLossRisk': report.hasDataLossRisk,
    };
  }

  /// 格式化分析报告为 AI 友好的文本
  static String formatReportForAI(ImpactReport report) {
    final buffer = StringBuffer();

    // 风险等级标题
    final riskEmoji = switch (report.riskLevel) {
      RiskLevel.critical => '🚨',
      RiskLevel.high => '🔴',
      RiskLevel.medium => '🟡',
      RiskLevel.low => '🟢',
    };

    buffer.writeln('## Schema Impact Analysis');
    buffer.writeln();
    buffer.writeln('**DDL Type**: ${report.ddlType}');
    buffer.writeln('**Target Table**: `${report.targetTable}`');
    buffer.writeln(
      '**Risk Level**: $riskEmoji ${report.riskLevel.displayName}',
    );
    buffer.writeln();

    // 第四阶段：锁语义信息（algorithm 已知时才展示，避免噪音）。
    if (report.ddlAlgorithm != DdlAlgorithm.unknown) {
      buffer.writeln('### Lock Semantics');
      buffer.writeln(
        '**Algorithm**: ${report.ddlAlgorithm.name.toUpperCase()}',
      );
      if (report.lockType != null) {
        buffer.writeln('**Lock**: ${report.lockType}');
      }
      buffer.writeln(
        '**Concurrency**: ${report.concurrencyImpact.name}',
      );
      if (report.algorithmNote != null) {
        buffer.writeln('_${report.algorithmNote}_');
      }
      buffer.writeln();
    }

    // 受影响对象
    if (report.affectedObjects.isNotEmpty) {
      buffer.writeln('### Affected Objects');
      for (final obj in report.affectedObjects) {
        final typeEmoji = switch (obj.type) {
          AffectedObjectType.view => '👁️',
          AffectedObjectType.trigger => '⚡',
          AffectedObjectType.foreignKey => '🔗',
          AffectedObjectType.index_ => '📇',
          AffectedObjectType.constraint => '⛓️',
          _ => '📦',
        };
        buffer.writeln('$typeEmoji **${obj.name}** (${obj.type.name})');
        buffer.writeln('   ${obj.impactDescription}');
      }
      buffer.writeln();
    }

    // 警告
    if (report.warnings.isNotEmpty) {
      buffer.writeln('### Warnings');
      for (final warning in report.warnings) {
        buffer.writeln(warning);
      }
      buffer.writeln();
    }

    // 回滚脚本
    if (report.rollbackScript != null) {
      buffer.writeln('### Rollback Script');
      buffer.writeln('```sql');
      buffer.writeln(report.rollbackScript!.rollbackDdl);
      buffer.writeln('```');
      if (report.rollbackScript!.requiresDataBackup) {
        buffer.writeln('⚠️ **Data backup recommended before proceeding**');
      }
      buffer.writeln();
    }

    // 建议
    if (report.recommendations.isNotEmpty) {
      buffer.writeln('### Recommendations');
      for (final rec in report.recommendations) {
        buffer.writeln(rec);
      }
      buffer.writeln();
    }

    // 确认要求
    if (report.requiresConfirmation) {
      buffer.writeln('---');
      buffer.writeln(
        '⚠️ **This operation requires explicit confirmation due to high risk.**',
      );
    }

    return buffer.toString();
  }

  // === 私有方法 ===

  /// 解析 COUNT(*) 的返回值为 int。
  ///
  /// 兼容多驱动：mysql_client 默认返 String（'10'）、postgres/sqlite 可能返
  /// int/num/BigInt。String 解析失败或类型无法识别 → 返回 0（保守，不抛异常）。
  /// E2E 发现：此前 `as int?` 对 mysql_client 的 String 返回抛 cast 异常，
  /// 导致行数恒为 0，行数驱动的评级（inplace 大表 medium 等）失准。
  static int _parseRowCount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    // BigInt 等：toString 后解析。
    return int.tryParse(raw.toString()) ?? 0;
  }

  static List<AffectedObject> _convertToAffectedObjects(
    List<SchemaDependency> dependencies,
  ) {
    return dependencies.map((dep) {
      String description;
      switch (dep.dependentType) {
        case AffectedObjectType.view:
          description = 'View references this table';
          break;
        case AffectedObjectType.trigger:
          description = 'Trigger is associated with this table';
          break;
        case AffectedObjectType.foreignKey:
          description = 'Foreign key references this table';
          break;
        case AffectedObjectType.index_:
          description = 'Index on ${dep.sourceColumn ?? 'column'}';
          break;
        case AffectedObjectType.constraint:
          description = 'Constraint on ${dep.sourceColumn ?? 'column'}';
          break;
        default:
          description = dep.relationship;
      }

      return AffectedObject(
        type: dep.dependentType,
        name: dep.dependentObject,
        impactDescription: description,
        dependentColumn: dep.sourceColumn,
      );
    }).toList();
  }
}
