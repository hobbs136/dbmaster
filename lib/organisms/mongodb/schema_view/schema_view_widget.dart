import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/providers/mongodb_visualization_provider.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'schema_nested_expander.dart';

/// Main widget for Schema View
/// Displays inferred document schema with field types and presence ratios
class SchemaViewWidget extends StatelessWidget {
  final String collectionName;

  const SchemaViewWidget({super.key, required this.collectionName});

  @override
  Widget build(BuildContext context) {
    return Consumer<MongoVisualizationProvider>(
      builder: (context, provider, child) {
        // Auto-load schema when provider doesn't have current schema
        if (provider.currentSchema == null && !provider.loadingSchema) {
          // Load schema on first build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.loadSchema(collectionName);
          });
        }

        if (provider.loadingSchema) {
          return const _LoadingView();
        }

        if (provider.schemaError != null) {
          return _ErrorView(
            error: provider.schemaError!,
            onRetry: () => provider.loadSchema(collectionName),
          );
        }

        final schema = provider.currentSchema;
        if (schema == null || schema.isEmpty) {
          return const _EmptyView();
        }

        return _SchemaListView(schema: schema);
      },
    );
  }
}

/// Loading state view
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: AppDesignSystem.space3),
          Text(
            'Loading schema...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Error state view
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          SizedBox(height: AppDesignSystem.space3),
          Text('Schema Error', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: AppDesignSystem.space2),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDesignSystem.space6),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          SizedBox(height: AppDesignSystem.space3),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Empty state view (no data to infer)
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.package,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(height: AppDesignSystem.space3),
          Text(
            'No schema data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: AppDesignSystem.space2),
          Text(
            'This collection is empty or has no documents to analyze',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Schema list view
class _SchemaListView extends StatelessWidget {
  final InferredDocumentSchema schema;

  const _SchemaListView({required this.schema});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with collection info
        _SchemaHeader(schema: schema),

        const Divider(height: 1),

        // Field list
        Expanded(
          child: ListView.builder(
            itemCount: schema.fields.length,
            itemBuilder: (context, index) {
              final field = schema.fields[index];
              return SchemaNestedExpander(
                key: ValueKey('field_$index'),
                field: field,
                depth: 0,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Schema header with collection info
class _SchemaHeader extends StatelessWidget {
  final InferredDocumentSchema schema;

  const _SchemaHeader({required this.schema});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.table2,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collection: ${schema.collectionName}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  'Sampled: ${schema.totalSampled} documents',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '${schema.fields.length} fields',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
