import 'package:flutter/material.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'schema_field_item.dart';

/// Widget for recursive nested field expansion
class SchemaNestedExpander extends StatefulWidget {
  final SchemaField field;
  final int depth;

  const SchemaNestedExpander({
    super.key,
    required this.field,
    this.depth = 0,
  });

  @override
  State<SchemaNestedExpander> createState() => _SchemaNestedExpanderState();
}

class _SchemaNestedExpanderState extends State<SchemaNestedExpander> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main field item
        SchemaFieldItem(
          field: widget.field,
          depth: widget.depth,
          onToggleExpand: widget.field.isNested
              ? () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                }
              : null,
        ),
        
        // Nested sub-fields (expanded when toggled)
        if (widget.field.isNested && _isExpanded && widget.field.subFields != null)
          Padding(
            padding: EdgeInsets.only(
              left: AppDesignSystem.space4 * (widget.depth + 1),
              bottom: AppDesignSystem.space1,
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.field.subFields!.map((subField) {
                  return SchemaNestedExpander(
                    key: ValueKey('${widget.field.name}_${subField.name}'),
                    field: subField,
                    depth: widget.depth + 1,
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}
