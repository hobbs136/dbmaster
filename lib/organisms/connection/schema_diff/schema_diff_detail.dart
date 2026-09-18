import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/database_models.dart';
import '../../../models/schema_diff_models.dart';
import '../../../theme/app_colors.dart';

/// 中栏：差异明细，颜色编码，展开 side-by-side DDL
class SchemaDiffDetail extends StatelessWidget {
  final SchemaDiffReport report;
  final String? selectedObjectKey;

  const SchemaDiffDetail({
    super.key,
    required this.report,
    this.selectedObjectKey,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedObjectKey == null) {
      return _buildEmptyState(context);
    }

    final key = selectedObjectKey!;
    if (key.startsWith('table:')) {
      final tableName = key.substring(6);
      final tableDiff = report.tableDiffs
          .where((t) => t.name == tableName)
          .firstOrNull;
      if (tableDiff == null) {
        return _buildNotFound(context, tableName);
      }
      return _buildTableDetail(context, tableDiff);
    } else if (key.startsWith('view:')) {
      final viewName = key.substring(5);
      final viewDiff = report.viewDiffs
          .where((v) => v.name == viewName)
          .firstOrNull;
      if (viewDiff == null) {
        return _buildNotFound(context, viewName);
      }
      return _buildViewDetail(context, viewDiff);
    } else if (key.startsWith('proc:')) {
      final procName = key.substring(5);
      final procDiff = report.procedureDiffs
          .where((p) => p.name == procName)
          .firstOrNull;
      if (procDiff == null) {
        return _buildNotFound(context, procName);
      }
      return _buildProcedureDetail(context, procDiff);
    }

    return _buildEmptyState(context);
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.pointer,
            size: 40,
            color: context.themeColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            'Select an object from the tree\nto view detailed changes',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound(BuildContext context, String name) {
    return Center(
      child: Text(
        '"$name" not found in diff report',
        style: TextStyle(color: context.themeColors.textSecondary),
      ),
    );
  }

  // ---- Table Detail ----

  Widget _buildTableDetail(BuildContext context, TableDiff tableDiff) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTableHeader(context, tableDiff),
          const SizedBox(height: AppDesignSystem.space4),
          if (tableDiff.columnDiffs.isNotEmpty) ...[
            _buildSectionHeader(context, 'Columns', LucideIcons.columns2),
            const SizedBox(height: AppDesignSystem.space2),
            ...tableDiff.columnDiffs.map((c) => _ColumnDiffCard(colDiff: c)),
          ],
          if (tableDiff.indexDiffs.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space4),
            _buildSectionHeader(context, 'Indexes', LucideIcons.chartPie),
            const SizedBox(height: AppDesignSystem.space2),
            ...tableDiff.indexDiffs.map((i) => _IndexDiffCard(idxDiff: i)),
          ],
          if (tableDiff.sourceCreateSql != null ||
              tableDiff.targetCreateSql != null) ...[
            const SizedBox(height: AppDesignSystem.space4),
            _buildSectionHeader(context, 'DDL Comparison', LucideIcons.code),
            const SizedBox(height: AppDesignSystem.space2),
            if (tableDiff.sourceCreateSql != null)
              _DdlCompareBlock(
                label: 'Source',
                sql: tableDiff.sourceCreateSql!,
                color: Colors.red,
              ),
            if (tableDiff.targetCreateSql != null)
              _DdlCompareBlock(
                label: 'Target',
                sql: tableDiff.targetCreateSql!,
                color: Colors.green,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context, TableDiff tableDiff) {
    final (Color color, String label) = switch (tableDiff.type) {
      DiffType.added => (Colors.green, 'ADDED'),
      DiffType.removed => (Colors.red, 'REMOVED'),
      DiffType.modified => (Colors.orange, 'MODIFIED'),
      DiffType.unchanged => (Colors.grey, 'UNCHANGED'),
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space1,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space3),
        Expanded(
          child: Text(
            tableDiff.name,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.themeColors.textSecondary),
        const SizedBox(width: AppDesignSystem.space2),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: context.themeColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ---- View Detail ----

  Widget _buildViewDetail(BuildContext context, ViewDiff viewDiff) {
    final (Color color, String label) = switch (viewDiff.type) {
      DiffType.added => (Colors.green, 'ADDED'),
      DiffType.removed => (Colors.red, 'REMOVED'),
      _ => (Colors.grey, 'UNCHANGED'),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                  vertical: AppDesignSystem.space1,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space3),
              Expanded(
                child: Text(
                  viewDiff.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (viewDiff.createStatement != null) ...[
            const SizedBox(height: AppDesignSystem.space4),
            _DdlCompareBlock(
              label: 'CREATE VIEW',
              sql: viewDiff.createStatement!,
              color: Colors.blue,
            ),
          ],
        ],
      ),
    );
  }

  // ---- Procedure Detail ----

  Widget _buildProcedureDetail(BuildContext context, ProcedureDiff procDiff) {
    final (Color color, String label) = switch (procDiff.type) {
      DiffType.added => (Colors.green, 'ADDED'),
      DiffType.removed => (Colors.red, 'REMOVED'),
      _ => (Colors.grey, 'UNCHANGED'),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                  vertical: AppDesignSystem.space1,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space3),
              Expanded(
                child: Text(
                  procDiff.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (procDiff.createStatement != null) ...[
            const SizedBox(height: AppDesignSystem.space4),
            _DdlCompareBlock(
              label: 'CREATE STATEMENT',
              sql: procDiff.createStatement!,
              color: Colors.indigo,
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Column Diff Card ----

class _ColumnDiffCard extends StatelessWidget {
  final ColumnDiff colDiff;
  const _ColumnDiffCard({required this.colDiff});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (colDiff.type) {
      DiffType.added => (Colors.green, LucideIcons.circlePlus),
      DiffType.removed => (Colors.red, LucideIcons.circleMinus),
      DiffType.modified => (Colors.orange, LucideIcons.pencil),
      DiffType.unchanged => (Colors.grey, LucideIcons.circle),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              flex: 2,
              child: Text(
                colDiff.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (colDiff.sourceColumn != null)
              Expanded(
                flex: 3,
                child: _ValueBlock(
                  value: _formatColumn(colDiff.sourceColumn),
                  color: colDiff.type == DiffType.added
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            if (colDiff.type == DiffType.modified) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                ),
                child: Icon(
                  LucideIcons.arrowRight,
                  size: 16,
                  color: context.themeColors.textSecondary,
                ),
              ),
              Expanded(
                flex: 3,
                child: _ValueBlock(
                  value: _formatColumn(colDiff.targetColumn),
                  color: Colors.green,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatColumn(DbColumn? column) {
    if (column == null) return '';
    final parts = <String>[column.type];
    if (column.isPrimaryKey) parts.add('PK');
    if (!column.isNullable) parts.add('NOT NULL');
    if (column.defaultValue != null) {
      parts.add('DEFAULT ${column.defaultValue}');
    }
    return parts.join(' ');
  }
}

// ---- Index Diff Card ----

class _IndexDiffCard extends StatelessWidget {
  final IndexDiff idxDiff;
  const _IndexDiffCard({required this.idxDiff});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (idxDiff.type) {
      DiffType.added => (Colors.green, LucideIcons.circlePlus),
      DiffType.removed => (Colors.red, LucideIcons.circleMinus),
      DiffType.modified => (Colors.orange, LucideIcons.pencil),
      DiffType.unchanged => (Colors.grey, LucideIcons.circle),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              flex: 2,
              child: Text(
                idxDiff.name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(flex: 3, child: _formatIndexDiff(context, color)),
          ],
        ),
      ),
    );
  }

  Widget _formatIndexDiff(BuildContext context, Color color) {
    final source = idxDiff.sourceIndex;
    final target = idxDiff.targetIndex;
    switch (idxDiff.type) {
      case DiffType.added:
        return _ValueBlock(value: _formatIndex(source), color: Colors.green);
      case DiffType.removed:
        return _ValueBlock(value: _formatIndex(target), color: Colors.red);
      case DiffType.modified:
        return Row(
          children: [
            Expanded(
              child: _ValueBlock(
                value: _formatIndex(source),
                color: Colors.red,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1,
              ),
              child: Icon(
                LucideIcons.arrowRight,
                size: 14,
                color: context.themeColors.textSecondary,
              ),
            ),
            Expanded(
              child: _ValueBlock(
                value: _formatIndex(target),
                color: Colors.green,
              ),
            ),
          ],
        );
      case DiffType.unchanged:
        return Text(
          _formatIndex(source),
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: 12,
          ),
        );
    }
  }

  String _formatIndex(DbIndex? index) {
    if (index == null) return '';
    final parts = <String>[];
    if (index.isUnique) parts.add('UNIQUE');
    parts.add('(${index.columns.join(', ')})');
    return parts.join(' ');
  }
}

// ---- Shared widgets ----

class _ValueBlock extends StatelessWidget {
  final String value;
  final Color color;
  const _ValueBlock({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        value.isNotEmpty ? value : '(none)',
        style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _DdlCompareBlock extends StatelessWidget {
  final String label;
  final String sql;
  final Color color;
  const _DdlCompareBlock({
    required this.label,
    required this.sql,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border.all(color: context.themeColors.borderColor),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppDesignSystem.radiusMd - 1),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            child: SelectableText(
              sql,
              style: const TextStyle(
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
