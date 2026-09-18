import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../models/database_models.dart';
import '../../services/adapters/postgresql_adapter.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_logger.dart';
import 'pg_vector_panel.dart';
import '../../theme/app_colors.dart';

/// Dialog showing PostgreSQL extension details: metadata + member objects
/// (types, functions, operators) grouped by schema with search filter.
class PgExtensionDetailDialog extends StatefulWidget {
  final AppProvider provider;
  final String connectionId;
  final PgExtension extension;

  const PgExtensionDetailDialog({
    super.key,
    required this.provider,
    required this.connectionId,
    required this.extension,
  });

  @override
  State<PgExtensionDetailDialog> createState() =>
      _PgExtensionDetailDialogState();
}

class _PgExtensionDetailDialogState extends State<PgExtensionDetailDialog> {
  Map<String, List<PgExtensionMember>>? _members;
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // T29 第二批 E2E 实锤：_loadMembers 内同步读 AppLocalizations.of(context)
    // ——initState 里 dependOnInheritedWidget 非法（flutter 生命周期断言）。
    // 推迟到首帧后执行。
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  Future<void> _loadMembers() async {
    final l10n = AppLocalizations.of(context);
    try {
      final adapter = widget.provider.dbService.getAdapter(widget.connectionId);
      if (adapter == null) {
        if (!mounted) return;
        setState(() {
          _error = l10n?.extensionNoAdapter ?? 'No adapter';
          _loading = false;
        });
        return;
      }

      // getExtensionMembers is a public helper on PostgreSQLAdapter
      if (adapter is! PostgreSQLAdapter) {
        if (!mounted) return;
        setState(() {
          _error = l10n?.extensionNotPostgres ?? 'Not a PostgreSQL connection';
          _loading = false;
        });
        return;
      }

      final members = await adapter.getExtensionMembers(widget.extension.name);

      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      AppLogger.e('PgExtensionDetailDialog', 'Failed to load members', e);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ext = widget.extension;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(
            LucideIcons.puzzle,
            color: colors.brandColor(DatabaseType.postgresql),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Flexible(
            child: Text(
              '${ext.name} ${ext.version}',
              style: const TextStyle(
                fontSize: AppDesignSystem.fontSize2xl,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 520,
        child: _buildContent(l10n, colors),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildContent(AppLocalizations l10n, dynamic colors) {
    final ext = widget.extension;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: context.themeColors.error,
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              _error!,
              style: TextStyle(fontSize: 13, color: context.themeColors.error),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadMembers();
              },
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaCard(ext, colors),
          const SizedBox(height: AppDesignSystem.space3),
          TextField(
            decoration: InputDecoration(
              hintText: l10n.commonSearch,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          // T025 — show vector panel for pgvector extension
          if (widget.extension.name == 'vector')
            PgVectorPanel(
              provider: widget.provider,
              connectionId: widget.connectionId,
            ),
          if (_members != null) ...[
            _buildMemberSection(
              LucideIcons.shapes,
              l10n.extensionTypes,
              _members!['types'] ?? [],
              context.themeColors.accentBlue,
            ),
            _buildMemberSection(
              LucideIcons.functionSquare,
              l10n.extensionFunctions,
              _members!['functions'] ?? [],
              context.themeColors.brandColor(DatabaseType.postgresql),
            ),
            _buildMemberSection(
              LucideIcons.arrowRightLeft,
              l10n.extensionOperators,
              _members!['operators'] ?? [],
              context.themeColors.warning,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaCard(PgExtension ext, dynamic colors) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metaRow(l10n.extensionSchema, ext.schema, colors),
          if (ext.description.isNotEmpty)
            _metaRow(l10n.extensionDescription, ext.description, colors),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value, dynamic colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          Flexible(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildMemberSection(
    IconData icon,
    String title,
    List<PgExtensionMember> members,
    Color iconColor,
  ) {
    if (members.isEmpty) return const SizedBox.shrink();

    final filtered = _searchQuery.isEmpty
        ? members
        : members
              .where(
                (m) =>
                    m.name.toLowerCase().contains(_searchQuery) ||
                    m.schema.toLowerCase().contains(_searchQuery) ||
                    (m.signature?.toLowerCase().contains(_searchQuery) ??
                        false),
              )
              .toList();

    final grouped = <String, List<PgExtensionMember>>{};
    for (final m in filtered) {
      grouped.putIfAbsent(m.schema, () => []).add(m);
    }

    final colors = context.themeColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                '$title (${filtered.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1),
          ...grouped.entries.map((entry) {
            return _buildSchemaGroup(entry.key, entry.value, colors);
          }),
        ],
      ),
    );
  }

  Widget _buildSchemaGroup(
    String schema,
    List<PgExtensionMember> members,
    dynamic colors,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space1,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '$schema (${members.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 2),
          ...members.map(
            (m) => Padding(
              padding: const EdgeInsets.only(
                left: AppDesignSystem.space2,
                bottom: 2,
              ),
              child: Text(
                m.signature != null ? '${m.name}(${m.signature})' : m.name,
                style: const TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience function to show the dialog.
Future<void> showExtensionDetailDialog(
  BuildContext context,
  AppProvider provider,
  String connectionId,
  PgExtension extension,
) {
  return showDialog(
    context: context,
    builder: (_) => PgExtensionDetailDialog(
      provider: provider,
      connectionId: connectionId,
      extension: extension,
    ),
  );
}
