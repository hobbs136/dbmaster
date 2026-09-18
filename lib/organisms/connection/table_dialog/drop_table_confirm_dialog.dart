import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../molecules/destructive_confirm_dialog.dart';
import '../../../providers/app_provider.dart';
import '../../../services/schema_analyzer/dependency_analyzer.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

class DropTableConfirmDialog extends StatefulWidget {
  final String tableName;
  final String? databaseName;
  final AppProvider? provider;

  const DropTableConfirmDialog({
    super.key,
    required this.tableName,
    this.databaseName,
    this.provider,
  });

  @override
  State<DropTableConfirmDialog> createState() => _DropTableConfirmDialogState();
}

class _DropTableConfirmDialogState extends State<DropTableConfirmDialog> {
  List<String>? _warnings;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.provider != null) {
      _loadWarnings();
    }
  }

  Future<void> _loadWarnings() async {
    setState(() => _loading = true);
    try {
      final dbService = widget.provider!.dbService;
      final server = dbService.currentServer;
      if (server == null) return;

      final deps = await DependencyAnalyzer.analyzeTableDependencies(
        tableName: widget.tableName,
        executeQuery: (sql) => dbService.executeQuery(
          sql,
          connectionId: server.id,
          database: widget.databaseName ?? server.database,
        ),
        databaseType: server.type.name,
      );

      if (deps.isNotEmpty && mounted) {
        setState(() {
          _warnings = deps
              .map((d) => '${d.dependentObject} (${d.relationship})')
              .toList();
        });
      }
    } catch (_) {
      // 静默失败，不显示警告
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DestructiveConfirmDialog(
      icon: LucideIcons.triangleAlert,
      title: l10n.tableDeleteTable,
      impactTone: DestructiveTone.error,
      body: l10n.dropTableDeleteConfirmBody(widget.tableName),
      impactDescription: l10n.dropTableDeleteImpact,
      confirmLabel: l10n.commonDelete,
      onConfirm: () => Navigator.pop(context, true),
      extraContent: _buildDependencySlot(context, l10n),
    );
  }

  /// 依赖查询结果插槽：加载指示 + 依赖警告（查询逻辑保留在本壳内）。
  Widget? _buildDependencySlot(BuildContext context, AppLocalizations l10n) {
    final hasWarnings = _warnings != null && _warnings!.isNotEmpty;
    if (!_loading && !hasWarnings) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading)
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.themeColors.textMuted,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.dropTableCheckingDependencies,
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        if (hasWarnings) ...[
          if (_loading) const SizedBox(height: AppDesignSystem.space3),
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.triangleAlert,
                      size: 16,
                      color: context.themeColors.warning,
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Text(
                      l10n.dropTableDependencyWarning,
                      style: TextStyle(
                        color: context.themeColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space1_5),
                ..._warnings!.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $w',
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
