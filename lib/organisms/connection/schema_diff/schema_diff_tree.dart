import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/schema_diff_models.dart';
import '../../../theme/app_colors.dart';

/// 左栏：源库对象树 + 差异计数徽章
/// 按类型分组：Tables, Views, Procedures
class SchemaDiffTree extends StatelessWidget {
  final SchemaDiffReport report;
  final String? selectedObjectKey;
  final DiffCategory filter;
  final ValueChanged<String> onSelect;

  const SchemaDiffTree({
    super.key,
    required this.report,
    this.selectedObjectKey,
    required this.filter,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: context.themeColors.borderSubtle,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          Expanded(child: _buildTree(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      child: Text(
        'Schema Objects',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTree(BuildContext context) {
    final tableItems = _filteredTables;
    final viewItems = _filteredViews;
    final procedureItems = _filteredProcedures;

    if (tableItems.isEmpty && viewItems.isEmpty && procedureItems.isEmpty) {
      return Center(
        child: Text(
          'No matching objects',
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space4),
      children: [
        if (tableItems.isNotEmpty) ...[
          _SectionHeader(
            title: 'Tables',
            icon: LucideIcons.table2,
            count: tableItems.length,
            totalChanges: _totalTableChanges(tableItems),
          ),
          ...tableItems.map(
            (t) => _TreeItem(
              key: ValueKey('table:${t.name}'),
              icon: LucideIcons.rows3,
              label: t.name,
              diffType: t.type,
              changeCount: t.changeCount,
              isSelected: selectedObjectKey == 'table:${t.name}',
              onTap: () => onSelect('table:${t.name}'),
            ),
          ),
        ],
        if (viewItems.isNotEmpty) ...[
          const SizedBox(height: AppDesignSystem.space2),
          _SectionHeader(
            title: 'Views',
            icon: LucideIcons.eye,
            count: viewItems.length,
          ),
          ...viewItems.map(
            (v) => _TreeItem(
              key: ValueKey('view:${v.name}'),
              icon: LucideIcons.eye,
              label: v.name,
              diffType: v.type,
              changeCount: 0,
              isSelected: selectedObjectKey == 'view:${v.name}',
              onTap: () => onSelect('view:${v.name}'),
            ),
          ),
        ],
        if (procedureItems.isNotEmpty) ...[
          const SizedBox(height: AppDesignSystem.space2),
          _SectionHeader(
            title: 'Procedures',
            icon: LucideIcons.code,
            count: procedureItems.length,
          ),
          ...procedureItems.map(
            (p) => _TreeItem(
              key: ValueKey('proc:${p.name}'),
              icon: LucideIcons.code,
              label: p.name,
              diffType: p.type,
              changeCount: 0,
              isSelected: selectedObjectKey == 'proc:${p.name}',
              onTap: () => onSelect('proc:${p.name}'),
            ),
          ),
        ],
      ],
    );
  }

  int _totalTableChanges(List<TableDiff> tables) {
    return tables.fold(0, (sum, t) => sum + t.changeCount);
  }

  // ---- Filtered views ----

  List<TableDiff> get _filteredTables => filteredTables(report, filter);

  List<ViewDiff> get _filteredViews => filteredViews(report, filter);

  List<ProcedureDiff> get _filteredProcedures =>
      filteredProcedures(report, filter);

  //Keyboard navigation — flatten the filtered object keys in render
  // order (tables → views → procedures) so the page can drive ↑/↓ selection
  // against the exact same ordering the tree renders. Logic shared with the
  // filtered getters below to avoid duplication.
  static List<String> objectKeys(SchemaDiffReport report, DiffCategory filter) {
    return [
      for (final t in filteredTables(report, filter)) 'table:${t.name}',
      for (final v in filteredViews(report, filter)) 'view:${v.name}',
      for (final p in filteredProcedures(report, filter)) 'proc:${p.name}',
    ];
  }

  //Keyboard navigation — pure selection-movement logic over the
  // ordered [keys] list (the same list objectKeys produces). Extracted as a
  // static pure function so it is unit-testable without pumping the page.
  //
  // Semantics:
  // - empty keys → null (nothing to navigate)
  // - no valid current selection → ↓ enters at first, ↑ enters at last
  // - otherwise move one step, clamping at the list boundary (no wrap)
  static String? moveSelection(
    List<String> keys,
    String? current,
    bool forward,
  ) {
    if (keys.isEmpty) return null;
    final index = (current != null && keys.contains(current))
        ? keys.indexOf(current)
        : -1;
    if (index == -1) {
      return forward ? keys.first : keys.last;
    }
    if (forward) {
      final next = index + 1;
      return next < keys.length ? keys[next] : keys.last;
    }
    final prev = index - 1;
    return prev >= 0 ? keys[prev] : keys.first;
  }

  static List<TableDiff> filteredTables(
    SchemaDiffReport report,
    DiffCategory filter,
  ) {
    var tables = report.tableDiffs;
    switch (filter) {
      case DiffCategory.added:
        tables = tables.where((t) => t.type == DiffType.added).toList();
        break;
      case DiffCategory.modified:
        tables = tables.where((t) => t.type == DiffType.modified).toList();
        break;
      case DiffCategory.removed:
        tables = tables.where((t) => t.type == DiffType.removed).toList();
        break;
      case DiffCategory.tables:
        break; // Show all tables
      case DiffCategory.indexes:
        tables = tables
            .where((t) => t.indexDiffs.any((i) => i.type != DiffType.unchanged))
            .toList();
        break;
      case DiffCategory.views:
      case DiffCategory.procedures:
        return []; // filtering by view/procedure hides tables
      case DiffCategory.all:
        break;
    }
    return tables;
  }

  static List<ViewDiff> filteredViews(
    SchemaDiffReport report,
    DiffCategory filter,
  ) {
    if (filter == DiffCategory.tables ||
        filter == DiffCategory.indexes ||
        filter == DiffCategory.procedures) {
      return [];
    }
    var views = report.viewDiffs;
    switch (filter) {
      case DiffCategory.added:
        views = views.where((v) => v.type == DiffType.added).toList();
        break;
      case DiffCategory.modified:
        views = views.where((v) => v.type == DiffType.modified).toList();
        break;
      case DiffCategory.removed:
        views = views.where((v) => v.type == DiffType.removed).toList();
        break;
      default:
        break;
    }
    return views;
  }

  static List<ProcedureDiff> filteredProcedures(
    SchemaDiffReport report,
    DiffCategory filter,
  ) {
    if (filter == DiffCategory.tables ||
        filter == DiffCategory.indexes ||
        filter == DiffCategory.views) {
      return [];
    }
    var procs = report.procedureDiffs;
    switch (filter) {
      case DiffCategory.added:
        procs = procs.where((p) => p.type == DiffType.added).toList();
        break;
      case DiffCategory.modified:
        procs = procs.where((p) => p.type == DiffType.modified).toList();
        break;
      case DiffCategory.removed:
        procs = procs.where((p) => p.type == DiffType.removed).toList();
        break;
      default:
        break;
    }
    return procs;
  }
}

// ---- Sub-widgets ----

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final int? totalChanges;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.count,
    this.totalChanges,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space3,
        AppDesignSystem.space2,
        AppDesignSystem.space3,
        AppDesignSystem.space1,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: context.themeColors.textSecondary),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: context.themeColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (totalChanges != null && totalChanges! > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              ),
              child: Text(
                '${totalChanges!} changes',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.accentBlue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TreeItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final DiffType diffType;
  final int changeCount;
  final bool isSelected;
  final VoidCallback onTap;

  const _TreeItem({
    super.key,
    required this.icon,
    required this.label,
    required this.diffType,
    required this.changeCount,
    required this.isSelected,
    required this.onTap,
  });

  Color get _statusColor {
    switch (diffType) {
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space1,
        ),
        color: isSelected
            ? context.themeColors.accentBlue.withValues(alpha: 0.1)
            : null,
        child: Row(
          children: [
            Icon(icon, size: 14, color: _statusColor),
            const SizedBox(width: AppDesignSystem.space2),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (changeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
                ),
                child: Text(
                  changeCount.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
