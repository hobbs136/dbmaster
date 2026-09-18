import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/schema_diff_models.dart';
import '../../../theme/app_colors.dart';

/// 右栏：选中项的迁移 DDL 预览
/// 显示为选中对象生成的 DDL 语句（CREATE/ALTER/DROP）
class SchemaDiffDdlPreview extends StatelessWidget {
  final TableDiff? selectedTableDiff;
  final ViewDiff? selectedViewDiff;
  final ProcedureDiff? selectedProcedureDiff;

  const SchemaDiffDdlPreview({
    super.key,
    this.selectedTableDiff,
    this.selectedViewDiff,
    this.selectedProcedureDiff,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: context.themeColors.borderSubtle,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      child: Row(
        children: [
          Icon(
            LucideIcons.code,
            size: 18,
            color: context.themeColors.textSecondary,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'Migration DDL',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (_hasContent)
            IconButton(
              icon: const Icon(LucideIcons.copy, size: 16),
              tooltip: 'Copy DDL',
              onPressed: () => _copyDdl(context),
            ),
        ],
      ),
    );
  }

  bool get _hasContent =>
      selectedTableDiff != null ||
      selectedViewDiff != null ||
      selectedProcedureDiff != null;

  void _copyDdl(BuildContext context) {
    final sqls = _generateDdl();
    if (sqls.isEmpty) return;
    // 每条 DDL 去掉尾部分号后统一加分号，避免拼接出 `;;` 或缺分号
    final text = sqls
        .map((e) => e.sql.trim().replaceAll(RegExp(r';\s*$'), ''))
        .join(';\n\n');
    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.copiedToClipboard),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (!_hasContent) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.arrowLeft,
              size: 32,
              color: context.themeColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              'Select an object to view its migration DDL',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final sqls = _generateDdl();
    if (sqls.isEmpty) {
      return Center(
        child: Text(
          'No DDL changes needed',
          style: TextStyle(color: context.themeColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      itemCount: sqls.length,
      itemBuilder: (context, index) {
        final entry = sqls[index];
        return _DdlCard(label: entry.label, sql: entry.sql, color: entry.color);
      },
    );
  }

  List<_DdlEntry> _generateDdl() {
    final entries = <_DdlEntry>[];

    if (selectedTableDiff != null) {
      final t = selectedTableDiff!;
      switch (t.type) {
        case DiffType.added:
          if (t.sourceCreateSql != null && t.sourceCreateSql!.isNotEmpty) {
            entries.add(
              _DdlEntry(
                label: 'CREATE TABLE',
                sql: t.sourceCreateSql!,
                color: Colors.green,
              ),
            );
          }
          break;
        case DiffType.removed:
          entries.add(
            _DdlEntry(
              label: 'DROP TABLE',
              sql: 'DROP TABLE IF EXISTS "${t.name}";',
              color: Colors.red,
            ),
          );
          break;
        case DiffType.modified:
          // Column DDLs
          for (final colDiff in t.columnDiffs) {
            if (colDiff.type == DiffType.unchanged) continue;
            final label = switch (colDiff.type) {
              DiffType.added => 'ADD COLUMN',
              DiffType.removed => 'DROP COLUMN',
              DiffType.modified => 'MODIFY COLUMN',
              _ => '',
            };
            if (label.isNotEmpty) {
              entries.add(
                _DdlEntry(
                  label: label,
                  sql: _formatColumnDdl(t.name, colDiff),
                  color: _colorForType(colDiff.type),
                ),
              );
            }
          }
          // Index DDLs
          for (final idxDiff in t.indexDiffs) {
            if (idxDiff.type == DiffType.unchanged) continue;
            final label = switch (idxDiff.type) {
              DiffType.added => 'CREATE INDEX',
              DiffType.removed => 'DROP INDEX',
              DiffType.modified => 'RECREATE INDEX',
              _ => '',
            };
            if (label.isNotEmpty) {
              entries.add(
                _DdlEntry(
                  label: label,
                  sql: _formatIndexDdl(t.name, idxDiff),
                  color: _colorForType(idxDiff.type),
                ),
              );
            }
          }
          break;
        case DiffType.unchanged:
          break;
      }
    }

    if (selectedViewDiff != null) {
      final v = selectedViewDiff!;
      switch (v.type) {
        case DiffType.added:
          if (v.createStatement != null && v.createStatement!.isNotEmpty) {
            entries.add(
              _DdlEntry(
                label: 'CREATE VIEW',
                sql: v.createStatement!,
                color: Colors.green,
              ),
            );
          }
          break;
        case DiffType.removed:
          entries.add(
            _DdlEntry(
              label: 'DROP VIEW',
              sql: 'DROP VIEW IF EXISTS "${v.name}";',
              color: Colors.red,
            ),
          );
          break;
        default:
          break;
      }
    }

    if (selectedProcedureDiff != null) {
      final p = selectedProcedureDiff!;
      switch (p.type) {
        case DiffType.added:
          if (p.createStatement != null && p.createStatement!.isNotEmpty) {
            entries.add(
              _DdlEntry(
                label: 'CREATE PROCEDURE/FUNCTION',
                sql: p.createStatement!,
                color: Colors.green,
              ),
            );
          }
          break;
        case DiffType.removed:
          entries.add(
            _DdlEntry(
              label: 'DROP PROCEDURE/FUNCTION',
              sql:
                  'DROP PROCEDURE IF EXISTS "${p.name}";\nDROP FUNCTION IF EXISTS "${p.name}";',
              color: Colors.red,
            ),
          );
          break;
        default:
          break;
      }
    }

    return entries;
  }

  Color _colorForType(DiffType type) {
    switch (type) {
      case DiffType.added:
        return Colors.green;
      case DiffType.removed:
        return Colors.red;
      case DiffType.modified:
        return Colors.orange;
      case DiffType.unchanged:
        return Colors.grey;
    }
  }

  String _formatColumnDdl(String tableName, ColumnDiff colDiff) {
    final name = colDiff.name;
    switch (colDiff.type) {
      case DiffType.added:
        final col = colDiff.sourceColumn;
        if (col == null) return '';
        final buf = StringBuffer();
        buf.write('ALTER TABLE "$tableName" ADD COLUMN "$name" ${col.type}');
        if (!col.isNullable) buf.write(' NOT NULL');
        if (col.defaultValue != null) buf.write(' DEFAULT ${col.defaultValue}');
        buf.write(';');
        return buf.toString();
      case DiffType.removed:
        return 'ALTER TABLE "$tableName" DROP COLUMN "$name";';
      case DiffType.modified:
        final col = colDiff.sourceColumn;
        if (col == null) return '';
        final buf = StringBuffer();
        buf.write('ALTER TABLE "$tableName" MODIFY COLUMN "$name" ${col.type}');
        if (!col.isNullable) buf.write(' NOT NULL');
        if (col.defaultValue != null) buf.write(' DEFAULT ${col.defaultValue}');
        buf.write(';');
        return buf.toString();
      default:
        return '';
    }
  }

  String _formatIndexDdl(String tableName, IndexDiff idxDiff) {
    final name = idxDiff.name;
    switch (idxDiff.type) {
      case DiffType.added:
      case DiffType.modified:
        final idx = idxDiff.sourceIndex;
        if (idx == null) return '';
        final unique = idx.isUnique ? 'UNIQUE ' : '';
        final cols = idx.columns.map((c) => '"$c"').join(', ');
        return 'CREATE ${unique}INDEX "$name" ON "$tableName" ($cols);';
      case DiffType.removed:
        return 'DROP INDEX "$name" ON "$tableName";';
      default:
        return '';
    }
  }
}

class _DdlEntry {
  final String label;
  final String sql;
  final Color color;
  const _DdlEntry({
    required this.label,
    required this.sql,
    required this.color,
  });
}

class _DdlCard extends StatelessWidget {
  final String label;
  final String sql;
  final Color color;

  const _DdlCard({required this.label, required this.sql, required this.color});

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
