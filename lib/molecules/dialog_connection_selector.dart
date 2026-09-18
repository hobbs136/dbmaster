import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../providers/app_provider.dart';
import '../../models/database_models.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'compact_popup_menu_item.dart';
import '../theme/app_colors.dart';

class DialogConnectionSelector extends StatelessWidget {
  final String? selectedConnectionId;
  final String? selectedDatabase;
  final List<String> databases;
  final ValueChanged<String?> onConnectionChanged;
  final ValueChanged<String?> onDatabaseChanged;
  final bool showDatabaseSelector;

  const DialogConnectionSelector({
    super.key,
    this.selectedConnectionId,
    this.selectedDatabase,
    required this.databases,
    required this.onConnectionChanged,
    required this.onDatabaseChanged,
    this.showDatabaseSelector = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final connectedServers = context
        .watch<AppProvider>()
        .connection
        .savedConnections
        .where(
          (s) => context.watch<AppProvider>().connection.isConnectionConnected(
            s.id,
          ),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.server,
            size: 16,
            color: context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          _buildConnectionDropdown(context, connectedServers, l10n),
          if (showDatabaseSelector) ...[
            const SizedBox(width: AppDesignSystem.space4),
            Icon(
              LucideIcons.database,
              size: 16,
              color: context.themeColors.success,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            _buildDatabaseDropdown(context, databases, l10n),
          ],
          const Spacer(),
          if (selectedConnectionId != null)
            Text(
              l10n.connectionStatusConnected,
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.accentGreen,
              ),
            )
          else
            Text(
              l10n.connectionStatusNotConnected,
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionDropdown(
    BuildContext context,
    List<DbServer> servers,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<String?>(
      onSelected: onConnectionChanged,
      initialValue: selectedConnectionId,
      enabled: servers.isNotEmpty,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1,
        ),
        decoration: BoxDecoration(
          color: context.themeColors.bgSecondary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(color: context.themeColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getConnectionDisplayName(servers, l10n),
              style: TextStyle(
                fontSize: 12,
                color: servers.isEmpty
                    ? context.themeColors.textMuted
                    : context.themeColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: context.themeColors.textMuted,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        CompactPopupMenuItem<String?>(
          value: null,
          child: Text(
            l10n.selectConnection,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (servers.isNotEmpty) const PopupMenuDivider(height: 6),
        ...servers.map(
          (server) => CompactPopupMenuItem<String?>(
            value: server.id,
            child: Text(server.name, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildDatabaseDropdown(
    BuildContext context,
    List<String> databases,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<String?>(
      onSelected: onDatabaseChanged,
      initialValue: selectedDatabase,
      enabled: databases.isNotEmpty,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1,
        ),
        decoration: BoxDecoration(
          color: context.themeColors.bgSecondary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(color: context.themeColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedDatabase ?? l10n.selectDatabase,
              style: TextStyle(
                fontSize: 12,
                color: databases.isEmpty
                    ? context.themeColors.textMuted
                    : context.themeColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: context.themeColors.textMuted,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        CompactPopupMenuItem<String?>(
          value: null,
          child: Text(
            l10n.selectDatabase,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (databases.isNotEmpty) const PopupMenuDivider(height: 6),
        ...databases.map(
          (db) => CompactPopupMenuItem<String?>(
            value: db,
            child: Text(db, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  String _getConnectionDisplayName(
    List<DbServer> servers,
    AppLocalizations l10n,
  ) {
    if (selectedConnectionId == null) return l10n.selectConnection;
    try {
      final server = servers.firstWhere((s) => s.id == selectedConnectionId);
      return server.name;
    } catch (e) {
      return l10n.notConnected;
    }
  }
}
