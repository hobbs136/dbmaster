import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/schema_diff_models.dart';
import '../../../services/schema_diff/schema_snapshot_service.dart';
import '../../../services/schema_diff/schema_diff_service.dart';
import '../../../theme/app_colors.dart';
import '../error_boundary.dart';
import '../../../molecules/compact_popup_menu_item.dart';

/// 快照管理面板 — 列出已保存的快照，支持加载/对比/删除/导出
class SchemaSnapshotPanel extends StatefulWidget {
  final SchemaSnapshotService snapshotService;
  final SchemaDiffService diffService;

  const SchemaSnapshotPanel({
    super.key,
    required this.snapshotService,
    required this.diffService,
  });

  @override
  State<SchemaSnapshotPanel> createState() => _SchemaSnapshotPanelState();
}

class _SchemaSnapshotPanelState extends State<SchemaSnapshotPanel> {
  List<PersistedSnapshot>? _snapshots;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshots = await widget.snapshotService.listSnapshots();
      if (mounted) {
        setState(() {
          _snapshots = snapshots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteSnapshot(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Snapshot'),
        content: const Text(
          'Are you sure you want to delete this snapshot? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.snapshotService.deleteSnapshot(id);
        await _loadSnapshots();
      } catch (e) {
        if (mounted) {
          AppErrorHandler.showErrorSnackBar(context, 'Failed to delete: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Row(
        children: [
          Icon(
            LucideIcons.camera,
            size: 20,
            color: context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              'Schema Snapshots',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Refresh',
            onPressed: _loadSnapshots,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: context.themeColors.error,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            SelectableText(
              'Error: $_error',
              style: TextStyle(color: context.themeColors.error),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            ElevatedButton(
              onPressed: _loadSnapshots,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_snapshots == null || _snapshots!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.camera,
              size: 48,
              color: context.themeColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              'No snapshots saved yet',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              'Right-click a database and select "Save Schema Snapshot"',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      itemCount: _snapshots!.length,
      itemBuilder: (context, index) {
        final snap = _snapshots![index];
        return _SnapshotCard(
          snapshot: snap,
          onDelete: () => _deleteSnapshot(snap.id),
          onLoad: () {
            // Return the snapshot to the caller
            Navigator.of(context).pop(snap);
          },
        );
      },
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  final PersistedSnapshot snapshot;
  final VoidCallback onDelete;
  final VoidCallback onLoad;

  const _SnapshotCard({
    required this.snapshot,
    required this.onDelete,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      child: ListTile(
        leading: Icon(
          LucideIcons.camera,
          color: context.themeColors.accentBlue,
        ),
        title: Text(
          snapshot.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${snapshot.connectionName} / ${snapshot.databaseName}\n'
          '${snapshot.tableCount} tables · ${_formatDate(snapshot.capturedAt)}\n'
          '${_formatSize(snapshot.fileSizeBytes)}',
          style: TextStyle(
            fontSize: 12,
            color: context.themeColors.textSecondary,
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            const CompactPopupMenuItem(value: 'load', child: Text('Load')),
            const CompactPopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
          onSelected: (action) {
            switch (action) {
              case 'load':
                onLoad();
              case 'delete':
                onDelete();
            }
          },
        ),
        onTap: onLoad,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
