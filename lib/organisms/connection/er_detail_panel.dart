import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';

class ERDetailPanel extends StatelessWidget {
  final Map<String, dynamic> tableDetails;
  final VoidCallback? onClose;

  const ERDetailPanel({super.key, required this.tableDetails, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppDesignSystem.space4),
              children: [
                _buildTableInfo(context),
                const SizedBox(height: AppDesignSystem.space4),
                _buildColumnsSection(context),
                const SizedBox(height: AppDesignSystem.space4),
                _buildIndexesSection(context),
                const SizedBox(height: AppDesignSystem.space4),
                _buildForeignKeysSection(context),
                const SizedBox(height: AppDesignSystem.space4),
                _buildCreateSqlSection(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.info,
            color: context.themeColors.accentBlue,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              tableDetails['tableName'] as String? ?? 'Table Details',
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: Icon(
                LucideIcons.x,
                color: context.themeColors.textSecondary,
                size: 18,
              ),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildTableInfo(BuildContext context) {
    final properties = tableDetails['properties'] as Map<String, dynamic>?;
    final rowCount = tableDetails['rowCount'] as int?;

    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Table Information',
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          _buildInfoRow(
            context,
            'Engine',
            properties?['engine']?.toString() ?? '-',
          ),
          _buildInfoRow(context, 'Rows', rowCount?.toString() ?? '0'),
          _buildInfoRow(
            context,
            'Collation',
            properties?['collation']?.toString() ?? '-',
          ),
          if (properties?['comment'] != null)
            _buildInfoRow(
              context,
              'Comment',
              properties!['comment'].toString(),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnsSection(BuildContext context) {
    final columns = tableDetails['columns'] as List<Map<String, dynamic>>?;

    if (columns == null || columns.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Columns',
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: Column(
            children: columns
                .map((col) => _buildColumnItem(context, col))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnItem(BuildContext context, Map<String, dynamic> column) {
    final isPk = column['isPrimaryKey'] as bool? ?? false;
    final isNullable = column['isNullable'] as bool? ?? true;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.themeColors.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (isPk)
            Icon(LucideIcons.star, color: context.themeColors.warning, size: 12)
          else
            const SizedBox(width: AppDesignSystem.space4),
          const SizedBox(width: AppDesignSystem.space1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  column['name'] as String? ?? '',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 11,
                    fontWeight: isPk ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      column['type'] as String? ?? '',
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (!isNullable) ...[
                      const SizedBox(width: AppDesignSystem.space1),
                      Text(
                        'NOT NULL',
                        style: TextStyle(
                          color: context.themeColors.error,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexesSection(BuildContext context) {
    final indexes = tableDetails['indexes'] as List<Map<String, dynamic>>?;

    if (indexes == null || indexes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Indexes',
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: Column(
            children: indexes
                .map((idx) => _buildIndexItem(context, idx))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildIndexItem(BuildContext context, Map<String, dynamic> index) {
    final isUnique = index['isUnique'] as bool? ?? false;
    final columns = index['columns'] as List<dynamic>?;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.themeColors.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isUnique ? LucideIcons.keyRound : LucideIcons.list,
            color: isUnique
                ? context.themeColors.accentPurple
                : context.themeColors.textSecondary,
            size: 12,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  index['name'] as String? ?? '',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  columns?.join(', ') ?? '',
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForeignKeysSection(BuildContext context) {
    final foreignKeys = tableDetails['foreignKeys'] as List<dynamic>?;

    if (foreignKeys == null || foreignKeys.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foreign Keys',
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: Column(
            children: foreignKeys
                .map(
                  (fk) =>
                      _buildForeignKeyItem(context, fk as Map<String, dynamic>),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildForeignKeyItem(BuildContext context, Map<String, dynamic> fk) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.themeColors.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.link, color: context.themeColors.info, size: 12),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fk['column']} → ${fk['referencedTable']}.${fk['referencedColumn']}',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 11,
                  ),
                ),
                if (fk['onDelete'] != null || fk['onUpdate'] != null)
                  Text(
                    'ON DELETE: ${fk['onDelete'] ?? 'NO ACTION'} | ON UPDATE: ${fk['onUpdate'] ?? 'NO ACTION'}',
                    style: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateSqlSection(BuildContext context) {
    final createSql = tableDetails['createSql'] as String?;

    if (createSql == null || createSql.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create Statement',
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Container(
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          ),
          child: SelectableText(
            createSql,
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: 11,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
        ),
      ],
    );
  }
}
