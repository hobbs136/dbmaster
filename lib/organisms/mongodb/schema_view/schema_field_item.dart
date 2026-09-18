import 'package:flutter/material.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Widget for displaying a single schema field
class SchemaFieldItem extends StatelessWidget {
  final SchemaField field;
  final int depth;
  final VoidCallback? onToggleExpand;

  const SchemaFieldItem({
    super.key,
    required this.field,
    this.depth = 0,
    this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final nestedFieldsTooltip =
        AppLocalizations.of(context)?.mongoNestedFields ?? 'Nested fields';

    return Padding(
      padding: EdgeInsets.only(
        left: AppDesignSystem.space4 * (depth + 1),
        right: AppDesignSystem.space3,
        top: AppDesignSystem.space1,
        bottom: AppDesignSystem.space1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expand/collapse icon for nested fields
              if (field.isNested)
                IconButton(
                  icon: const Icon(LucideIcons.chevronDown, size: 18),
                  onPressed: onToggleExpand,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: nestedFieldsTooltip,
                )
              else
                const SizedBox(width: AppDesignSystem.space4 + 4),

              // Field name
              Expanded(
                child: Text(
                  field.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),

              // BSON type badge
              _TypeBadge(type: field.bsonType),

              const SizedBox(width: AppDesignSystem.space2),

              // Presence ratio
              _PresenceRatio(ratio: field.presenceRatio),
            ],
          ),

          // Mixed types indicator (if applicable)
          if (field.mixedTypes != null && field.mixedTypes!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: AppDesignSystem.space4 * (depth + 2),
                top: AppDesignSystem.space1,
              ),
              child: Wrap(
                spacing: AppDesignSystem.space1,
                children: field.mixedTypes!
                    .map(
                      (type) => Chip(
                        label: Text(type, style: const TextStyle(fontSize: 11)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget for displaying BSON type badge
class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: _getTypeColor(context, type),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: _getTypeTextColor(context, type),
        ),
      ),
    );
  }

  Color _getTypeColor(BuildContext context, String type) {
    final theme = Theme.of(context);

    // Color coding for common BSON types
    switch (type.toLowerCase()) {
      case 'string':
        return theme.colorScheme.primary.withValues(alpha: 0.1);
      case 'int':
      case 'long':
      case 'double':
        return Colors.blue.withValues(alpha: 0.1);
      case 'bool':
        return Colors.green.withValues(alpha: 0.1);
      case 'document':
        return Colors.orange.withValues(alpha: 0.1);
      case 'array':
        return Colors.purple.withValues(alpha: 0.1);
      case 'date':
        return Colors.teal.withValues(alpha: 0.1);
      case 'objectid':
        return Colors.red.withValues(alpha: 0.1);
      case 'mixed':
        return Colors.grey.withValues(alpha: 0.1);
      default:
        return theme.colorScheme.surfaceContainerHighest;
    }
  }

  Color _getTypeTextColor(BuildContext context, String type) {
    switch (type.toLowerCase()) {
      case 'string':
        return const Color(0xFF1976D2);
      case 'int':
      case 'long':
      case 'double':
        return Colors.blue.shade700;
      case 'bool':
        return Colors.green.shade700;
      case 'document':
        return Colors.orange.shade700;
      case 'array':
        return Colors.purple.shade700;
      case 'date':
        return Colors.teal.shade700;
      case 'objectid':
        return Colors.red.shade700;
      case 'mixed':
        return Colors.grey.shade700;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}

/// Widget for displaying presence ratio
class _PresenceRatio extends StatelessWidget {
  final double ratio;

  const _PresenceRatio({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final percentage = (ratio * 100).toStringAsFixed(0);
    final color = _getPercentageColor(ratio);

    return Text(
      '$percentage%',
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
    );
  }

  Color _getPercentageColor(double ratio) {
    if (ratio >= 0.9) return Colors.green;
    if (ratio >= 0.7) return Colors.blue;
    if (ratio >= 0.5) return Colors.orange;
    return Colors.red;
  }
}
