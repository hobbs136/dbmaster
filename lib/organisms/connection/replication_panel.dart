// T021 — Replication detail panel (SHOW SLAVE STATUS)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../models/database_models.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

class ReplicationDetailDialog extends StatelessWidget {
  final ReplicationStatus status;

  const ReplicationDetailDialog({super.key, required this.status});

  static Future<void> show(BuildContext context, ReplicationStatus status) {
    return showDialog(
      context: context,
      builder: (_) => ReplicationDetailDialog(status: status),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(
            status.isRunning ? LucideIcons.refreshCw : LucideIcons.refreshCcw,
            color: status.isRunning
                ? context.themeColors.success
                : context.themeColors.error,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.replicationDetailTitle),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDesignSystem.space3),
                decoration: BoxDecoration(
                  color: status.isRunning
                      ? context.themeColors.success.withValues(alpha: 0.1)
                      : context.themeColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(
                    color: status.isRunning
                        ? context.themeColors.success.withValues(alpha: 0.3)
                        : context.themeColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  status.isRunning
                      ? l10n.replicationRunning
                      : l10n.replicationStopped,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: status.isRunning
                        ? context.themeColors.success
                        : context.themeColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space3),

              // Thread statuses
              _buildField(
                context,
                l10n.replicationIoThread,
                status.slaveIoRunning ?? '?',
                status.slaveIoRunning == 'Yes',
              ),
              _buildField(
                context,
                l10n.replicationSqlThread,
                status.slaveSqlRunning ?? '?',
                status.slaveSqlRunning == 'Yes',
              ),

              // Lag
              if (status.secondsBehindMaster != null)
                _buildField(
                  context,
                  'Seconds Behind Master',
                  '${status.secondsBehindMaster}s',
                  status.secondsBehindMaster! < 30,
                ),

              const Divider(height: 24),

              // Master log coordinates
              _buildField(
                context,
                'Master Log File',
                status.masterLogFile ?? '-',
                true,
              ),
              _buildField(
                context,
                'Read Master Log Pos',
                status.readMasterLogPos?.toString() ?? '-',
                true,
              ),

              const Divider(height: 24),

              // Relay log coordinates (from raw)
              _buildField(
                context,
                'Relay Log File',
                status.raw['Relay_Log_File']?.toString() ?? '-',
                true,
              ),
              _buildField(
                context,
                'Relay Log Pos',
                status.raw['Relay_Log_Pos']?.toString() ?? '-',
                true,
              ),
              _buildField(
                context,
                'Exec Master Log Pos',
                status.raw['Exec_Master_Log_Pos']?.toString() ?? '-',
                true,
              ),

              const Divider(height: 24),

              // Errors (only shown when present)
              if (status.hasError) ...[
                if (status.lastIoError != null &&
                    status.lastIoError!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDesignSystem.space2),
                    margin: const EdgeInsets.only(
                      bottom: AppDesignSystem.space2,
                    ),
                    decoration: BoxDecoration(
                      color: context.themeColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last IO Error',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.themeColors.error,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status.lastIoError!,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (status.lastSqlError != null &&
                    status.lastSqlError!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDesignSystem.space2),
                    decoration: BoxDecoration(
                      color: context.themeColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last SQL Error',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.themeColors.error,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status.lastSqlError!,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontFamily: AppDesignSystem.monoFontFamily,

                            fontFamilyFallback:
                                AppDesignSystem.monoFontFamilyFallback,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildField(
    BuildContext ctx,
    String label,
    String value,
    bool isHealthy,
  ) {
    final colors = ctx.themeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isHealthy ? colors.textPrimary : colors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
