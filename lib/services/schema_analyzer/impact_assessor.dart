import '../../models/schema_analyzer/ddl_algorithm.dart';
import '../../models/schema_analyzer/impact_report.dart';

/// 影响评估引擎
/// 评估 DDL 变更的风险等级和影响范围
class ImpactAssessor {
  /// 评估 DDL 语句的风险等级
  ///
  /// 第四阶段扩展（design §4.5）：新增 [algorithmResult] 维度。
  /// - 破坏性操作（DROP/TRUNCATE）→ 数据丢失维度优先于锁维度。
  /// - algorithm 已知（instant/inplace/copy）→ 锁语义驱动评级。
  /// - algorithm = unknown（非 MySQL / 版本探测失败 / 未传）→ 回落既有行数阈值。
  ///
  /// B2 扩展：[inplaceMediumRowThreshold] 让 INPLACE 评级看行数——小表（行数
  /// ≤ 阈值）建索引/改列虽 INPLACE 但毫秒级完成 → low（不骚扰）；大表 → medium
  /// （INPLACE 仍可能耗时数分钟 + 占磁盘，值得提示）。默认 100000，由调用方
  /// 从 `SafetyConfig.fullScanRowThreshold` 传入。向后兼容（不传 = 100000）。
  static RiskLevel assessRiskLevel({
    required String ddlStatement,
    required String ddlType,
    required List<SchemaDependency> dependencies,
    required int estimatedAffectedRows,
    DdlAlgorithmResult? algorithmResult,
    int inplaceMediumRowThreshold = 100000,
  }) {
    final algo = algorithmResult?.algorithm ?? DdlAlgorithm.unknown;

    // 1. 破坏性操作（DROP/TRUNCATE）→ 数据丢失维度优先。
    //    R18 修复：TRUNCATE_TABLE 之前落 UNKNOWN → 兜底 medium，现正确归 high。
    if (ddlType == 'DROP_TABLE' ||
        ddlType == 'DROP_COLUMN' ||
        ddlType == 'TRUNCATE_TABLE') {
      // 如果有外键引用，则为 CRITICAL
      final hasForeignKeys = dependencies.any(
        (d) => d.dependentType == AffectedObjectType.foreignKey,
      );
      if (hasForeignKeys) return RiskLevel.critical;

      // 如果有视图引用，则为 HIGH
      final hasViews = dependencies.any(
        (d) => d.dependentType == AffectedObjectType.view,
      );
      if (hasViews) return RiskLevel.high;

      // 如果有触发器，则为 HIGH
      final hasTriggers = dependencies.any(
        (d) => d.dependentType == AffectedObjectType.trigger,
      );
      if (hasTriggers) return RiskLevel.high;

      // 删除列/表/截断表总是有数据丢失风险
      return RiskLevel.high;
    }

    // 2. algorithm 驱动评级（MySQL 且 algorithm 已知时）。
    if (algo != DdlAlgorithm.unknown) {
      switch (algo) {
        case DdlAlgorithm.instant:
        case DdlAlgorithm.metadataOnly:
          // 秒级无锁 → 最高 low（破坏性操作上面已拦截）。
          return RiskLevel.low;
        case DdlAlgorithm.inplace:
          // INPLACE + 有依赖破坏 → high。
          if (dependencies.isNotEmpty) return RiskLevel.high;
          // B2：INPLACE 按行数分级。小表（≤ 阈值）毫秒级完成 → low；
          // 大表（> 阈值）虽允许并发 DML，仍可能耗时数分钟 + 占磁盘 → medium。
          if (estimatedAffectedRows > inplaceMediumRowThreshold) {
            return RiskLevel.medium;
          }
          return RiskLevel.low;
        case DdlAlgorithm.copy:
          // COPY 全表锁 → 按行数升级：>1M critical, >10K high, else medium。
          if (estimatedAffectedRows > 1000000) return RiskLevel.critical;
          if (estimatedAffectedRows > 10000) return RiskLevel.high;
          return RiskLevel.medium;
        case DdlAlgorithm.unknown:
          break; // 落既有逻辑
      }
    }

    // 3. 既有行数阈值逻辑（algorithm = unknown 时回落，保留原 case 不回归）。
    // 2. 检查是否为修改列类型
    if (ddlType == 'ALTER_COLUMN') {
      // 数据转换风险
      if (estimatedAffectedRows > 10000) return RiskLevel.high;
      if (estimatedAffectedRows > 1000) return RiskLevel.medium;
      return RiskLevel.low;
    }

    // 3. 检查是否为添加列
    if (ddlType == 'ADD_COLUMN') {
      // 添加列通常安全，但如果表很大可能影响性能
      if (estimatedAffectedRows > 100000) return RiskLevel.medium;
      return RiskLevel.low;
    }

    // 4. 检查是否为索引操作
    if (ddlType == 'CREATE_INDEX' || ddlType == 'DROP_INDEX') {
      if (ddlType == 'DROP_INDEX') {
        // 检查索引是否被使用
        return RiskLevel.medium;
      }
      return RiskLevel.low;
    }

    // 5. 检查是否为重命名
    if (ddlType == 'RENAME_TABLE' || ddlType == 'RENAME_COLUMN') {
      // 重命名可能破坏依赖关系
      if (dependencies.isNotEmpty) return RiskLevel.high;
      return RiskLevel.medium;
    }

    // 默认风险等级
    return RiskLevel.medium;
  }

  /// 生成警告信息
  static List<String> generateWarnings({
    required String ddlStatement,
    required String ddlType,
    required List<SchemaDependency> dependencies,
    required int estimatedAffectedRows,
  }) {
    final warnings = <String>[];

    // 1. 数据丢失警告
    if (ddlType == 'DROP_TABLE') {
      warnings.add(
        '⚠️ This will permanently delete the table and all its data',
      );
      if (estimatedAffectedRows > 0) {
        warnings.add('⚠️ $estimatedAffectedRows rows of data will be lost');
      }
    }

    if (ddlType == 'DROP_COLUMN') {
      warnings.add(
        '⚠️ This will permanently delete the column and all its data',
      );
      if (estimatedAffectedRows > 0) {
        warnings.add(
          '⚠️ Data in this column for $estimatedAffectedRows rows will be lost',
        );
      }
    }

    // 2. 依赖关系警告
    final dependentViews = dependencies
        .where((d) => d.dependentType == AffectedObjectType.view)
        .length;
    if (dependentViews > 0) {
      warnings.add(
        '⚠️ $dependentViews view(s) depend on this table and may become invalid',
      );
    }

    final dependentTriggers = dependencies
        .where((d) => d.dependentType == AffectedObjectType.trigger)
        .length;
    if (dependentTriggers > 0) {
      warnings.add(
        '⚠️ $dependentTriggers trigger(s) are associated with this table',
      );
    }

    final dependentForeignKeys = dependencies
        .where((d) => d.dependentType == AffectedObjectType.foreignKey)
        .length;
    if (dependentForeignKeys > 0) {
      warnings.add(
        '⚠️ $dependentForeignKeys foreign key(s) reference this table. '
        'Dropping this table may break referential integrity',
      );
    }

    // 3. 大表警告
    if (estimatedAffectedRows > 1000000) {
      warnings.add(
        '⚠️ This is a large table ($estimatedAffectedRows rows). '
        'The operation may take a long time and lock the table',
      );
    } else if (estimatedAffectedRows > 100000) {
      warnings.add(
        '⚠️ This table has $estimatedAffectedRows rows. '
        'The operation may take significant time',
      );
    }

    // 4. 类型转换警告
    if (ddlType == 'ALTER_COLUMN') {
      warnings.add(
        '⚠️ Altering column type may fail if existing data cannot be converted',
      );
    }

    return warnings;
  }

  /// 生成建议
  static List<String> generateRecommendations({
    required String ddlType,
    required RiskLevel riskLevel,
    required List<SchemaDependency> dependencies,
  }) {
    final recommendations = <String>[];

    // 1. 备份建议
    if (riskLevel.isHighOrAbove) {
      recommendations.add('💡 Create a backup of the table before proceeding');
      recommendations.add(
        '💡 Test this operation on a staging environment first',
      );
    }

    // 2. 低峰期执行建议
    if (riskLevel == RiskLevel.high || riskLevel == RiskLevel.critical) {
      recommendations.add(
        '💡 Consider performing this operation during off-peak hours',
      );
    }

    // 3. 依赖处理建议
    final dependentViews = dependencies.where(
      (d) => d.dependentType == AffectedObjectType.view,
    );
    if (dependentViews.isNotEmpty) {
      recommendations.add(
        '💡 Review and update the following views after this change:',
      );
      for (final view in dependentViews.take(5)) {
        recommendations.add('   - ${view.dependentObject}');
      }
    }

    // 4. 索引重建建议
    if (ddlType == 'ALTER_COLUMN') {
      recommendations.add(
        '💡 Indexes on this column may need to be rebuilt after type change',
      );
    }

    // 5. 外键检查建议
    final dependentFKs = dependencies.where(
      (d) => d.dependentType == AffectedObjectType.foreignKey,
    );
    if (dependentFKs.isNotEmpty) {
      recommendations.add(
        '💡 Check foreign key constraints in dependent tables before proceeding',
      );
    }

    return recommendations;
  }

  /// 移除 SQL 标识符引用符：反引号、双引号、方括号
  static String _stripIdentifierQuotes(String sql) {
    return sql.replaceAll(RegExp(r'[\["`\]]'), '');
  }

  /// 提取 DDL 类型
  static String extractDdlType(String ddlStatement) {
    // 先移除所有标识符引用符，统一处理 MySQL/PostgreSQL/SQL Server/SQLite 等语法
    final normalized = _stripIdentifierQuotes(
      ddlStatement.trim().toUpperCase(),
    );

    if (normalized.startsWith('DROP TABLE')) return 'DROP_TABLE';
    if (normalized.startsWith('ALTER TABLE') &&
        normalized.contains('DROP COLUMN')) {
      return 'DROP_COLUMN';
    }
    if (normalized.startsWith('ALTER TABLE') &&
        (normalized.contains('MODIFY') ||
            normalized.contains('ALTER COLUMN'))) {
      return 'ALTER_COLUMN';
    }
    // 字符集/排序规则变更（CONVERT TO CHARACTER SET / DEFAULT CHARACTER SET /
    // COLLATE）→ 归 ALTER_COLUMN，使 DdlAlgorithmInferrer 的 _isCharsetChange
    // 检查生效（触发 copy 判定）。无 MODIFY/ALTER COLUMN 关键字时此前落 UNKNOWN
    // → 漏报全表锁（修复 2026-08-09，requirements-phase4.md R13 字符集场景）。
    if (normalized.startsWith('ALTER TABLE') &&
        (normalized.contains('CHARACTER SET') ||
            normalized.contains('CONVERT TO') ||
            normalized.contains('COLLATE'))) {
      return 'ALTER_COLUMN';
    }
    // 标准 SQL: ADD COLUMN; SQL Server: ADD (无 COLUMN 关键字)
    if (normalized.startsWith('ALTER TABLE') &&
        normalized.contains('ADD COLUMN')) {
      return 'ADD_COLUMN';
    }
    if (normalized.startsWith('ALTER TABLE') &&
        RegExp(
          r'\bADD\s+(?!CONSTRAINT\b|PRIMARY\b|FOREIGN\b|UNIQUE\b|INDEX\b|CHECK\b|DEFAULT\b)\w+',
        ).hasMatch(normalized)) {
      return 'ADD_COLUMN';
    }
    if (normalized.startsWith('CREATE INDEX') ||
        normalized.startsWith('CREATE UNIQUE INDEX')) {
      return 'CREATE_INDEX';
    }
    if (normalized.startsWith('DROP INDEX')) return 'DROP_INDEX';
    // 第四阶段 R18 bug 修复：TRUNCATE TABLE 之前落 UNKNOWN → 兜底 medium（破坏性操作被低估）。
    if (normalized.startsWith('TRUNCATE')) return 'TRUNCATE_TABLE';
    if (normalized.startsWith('RENAME TABLE')) return 'RENAME_TABLE';
    if (normalized.startsWith('ALTER TABLE') && normalized.contains('RENAME')) {
      return 'RENAME_COLUMN';
    }

    return 'UNKNOWN';
  }

  /// 提取目标表名
  /// 支持所有数据库类型的标识符引用：`table` (MySQL), "table" (PostgreSQL), [table] (SQL Server)
  /// 支持 schema 前缀：dbo.table, [dbo].[table], "public"."table"
  static String extractTargetTable(String ddlStatement) {
    // 标识符模式：可选引用符 + 名称 + 可选引用符，可选 schema. 前缀
    final ident = r'(?:[\["`]?(\w+)[\]"`]?)';
    final schemaPart = r'(?:' + ident + r'\.)?';

    // DROP TABLE [IF EXISTS] [schema.]table
    final dropMatch = RegExp(
      r'DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?' + schemaPart + ident,
      caseSensitive: false,
    ).firstMatch(ddlStatement);
    if (dropMatch != null) return dropMatch.group(2) ?? 'unknown';

    // ALTER TABLE [schema.]table
    final alterMatch = RegExp(
      r'ALTER\s+TABLE\s+' + schemaPart + ident,
      caseSensitive: false,
    ).firstMatch(ddlStatement);
    if (alterMatch != null) return alterMatch.group(2) ?? 'unknown';

    // CREATE INDEX name ON [schema.]table
    final indexMatch = RegExp(
      r'CREATE\s+INDEX\s+' + ident + r'\s+ON\s+' + schemaPart + ident,
      caseSensitive: false,
    ).firstMatch(ddlStatement);
    if (indexMatch != null) return indexMatch.group(3) ?? 'unknown';

    // RENAME TABLE [schema.]table
    final renameMatch = RegExp(
      r'RENAME\s+TABLE\s+' + schemaPart + ident,
      caseSensitive: false,
    ).firstMatch(ddlStatement);
    if (renameMatch != null) return renameMatch.group(2) ?? 'unknown';

    return 'unknown';
  }

  /// 是否需要用户确认
  static bool requiresConfirmation(RiskLevel riskLevel) {
    return riskLevel == RiskLevel.high || riskLevel == RiskLevel.critical;
  }
}
