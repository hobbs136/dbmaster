import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../models/er_diagram.dart';
import '../../theme/app_colors.dart';

class ERNodeWidget extends StatelessWidget {
  final ERNode node;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const ERNodeWidget({
    super.key,
    required this.node,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: node.size.width,
          height: node.size.height,
          decoration: BoxDecoration(
            color: isSelected
                ? context.themeColors.bgActive
                : isHighlighted
                ? context.themeColors.bgHover
                : context.themeColors.bgSecondary,
            border: Border.all(
              color: isSelected
                  ? context.themeColors.accentBlue
                  : isHighlighted
                  ? context.themeColors.info
                  : context.themeColors.borderColor,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with table name
              _buildHeader(context),
              // Divider
              Container(height: 1, color: context.themeColors.dividerColor),
              // Columns list
              Expanded(child: _buildColumnsList(context)),
              // Footer with row count
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: isSelected
            ? context.themeColors.accentBlue.withValues(alpha: 0.2)
            : context.themeColors.bgTertiary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDesignSystem.radiusMd),
          topRight: Radius.circular(AppDesignSystem.radiusMd),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.themeColors.accentPurple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Icon(
              LucideIcons.table2,
              size: 16,
              color: context.themeColors.accentPurple,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              node.tableName,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (node.primaryKeys.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.themeColors.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Icon(
                LucideIcons.keyRound,
                color: context.themeColors.warning,
                size: 12,
              ),
            ),
          if (node.foreignKeys.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.themeColors.info.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Icon(
                LucideIcons.link,
                color: context.themeColors.info,
                size: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildColumnsList(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: node.columns.length,
      itemBuilder: (context, index) {
        final columnName = node.columns[index];
        final isPrimaryKey = node.primaryKeys.contains(columnName);
        final isForeignKey = node.foreignKeys.any(
          (fk) => fk.column == columnName,
        );

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
            vertical: AppDesignSystem.space1,
          ),
          decoration: BoxDecoration(
            color: index % 2 == 0
                ? Colors.transparent
                : context.themeColors.bgHover.withValues(alpha: 0.3),
          ),
          child: Row(
            children: [
              if (isPrimaryKey)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: context.themeColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.star,
                    color: context.themeColors.warning,
                    size: 10,
                  ),
                )
              else if (isForeignKey)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: context.themeColors.info.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.link,
                    color: context.themeColors.info,
                    size: 10,
                  ),
                )
              else
                const SizedBox(width: 14),
              const SizedBox(width: AppDesignSystem.space1),
              Expanded(
                child: Text(
                  columnName,
                  style: TextStyle(
                    color: isPrimaryKey || isForeignKey
                        ? context.themeColors.textPrimary
                        : context.themeColors.textSecondary,
                    fontSize: 11,
                    fontWeight: isPrimaryKey
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppDesignSystem.radiusMd),
          bottomRight: Radius.circular(AppDesignSystem.radiusMd),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${node.columns.length} cols',
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 11,
            ),
          ),
          Text(
            '${node.rowCount} rows',
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
