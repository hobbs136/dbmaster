import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../models/database_models.dart';
import '../../utils/app_logger.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Widget showing pgvector vector indexes for display within the
/// pgvector extension detail panel.
class PgVectorPanel extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;

  const PgVectorPanel({
    super.key,
    required this.provider,
    required this.connectionId,
  });

  @override
  State<PgVectorPanel> createState() => _PgVectorPanelState();
}

class _PgVectorPanelState extends State<PgVectorPanel> {
  List<VectorIndex>? _indexes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // T29 第二批 E2E 实锤（与 pg_extension_panel 同型）：_load 内同步读
    // AppLocalizations.of(context) —— initState 里 dependOnInheritedWidget
    // 非法（断言中断加载 → loading 永转 → 调用方 pumpAndSettle 超时）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    try {
      final adapter = widget.provider.dbService.getAdapter(widget.connectionId);
      if (adapter == null) {
        if (!mounted) return;
        setState(() {
          _error = l10n?.vectorNoAdapter ?? 'No adapter';
          _loading = false;
        });
        return;
      }

      final indexes = await adapter.getVectorIndexes();
      if (!mounted) return;
      setState(() {
        _indexes = indexes;
        _loading = false;
      });
    } catch (e) {
      AppLogger.e('PgVectorPanel', 'Failed to load vector indexes', e);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppDesignSystem.space2),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space2),
        child: Row(
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 16,
              color: context.themeColors.error,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.error,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              child: Text(
                l10n?.commonRetry ?? 'Retry',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    final indexes = _indexes ?? [];
    if (indexes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space2),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 14, color: colors.textMuted),
            const SizedBox(width: AppDesignSystem.space1),
            Text(
              l10n?.vectorNoIndexes ?? 'No vector indexes defined',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppDesignSystem.space2,
            bottom: AppDesignSystem.space1,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.database,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                'Vector Indexes (${indexes.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...indexes.map((idx) => _buildIndexRow(idx, colors)),
      ],
    );
  }

  Widget _buildIndexRow(VectorIndex idx, dynamic colors) {
    final typeLabel = idx.indexType == VectorIndexType.hnsw
        ? 'HNSW'
        : 'IVFFlat';
    final typeColor = idx.indexType == VectorIndexType.hnsw
        ? context.themeColors.brandColor(DatabaseType.postgresql)
        : context.themeColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      padding: const EdgeInsets.all(AppDesignSystem.space1_5),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.layoutGrid, size: 12, color: colors.textMuted),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                idx.name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(fontSize: 11, color: typeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${idx.tableName}.${idx.columnName}',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          if (idx.dimensions != null || idx.distanceFunction != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (idx.dimensions != null) '${idx.dimensions} dims',
                  if (idx.distanceFunction != null) idx.distanceFunction!,
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
