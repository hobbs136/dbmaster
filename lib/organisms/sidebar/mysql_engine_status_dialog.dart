// T017 — MySQL Engine Status dialog (SHOW ENGINE INNODB STATUS)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../l10n/app_localizations.dart';

class MysqlEngineStatusDialog extends StatefulWidget {
  final String connectionId;

  const MysqlEngineStatusDialog({super.key, required this.connectionId});

  static Future<void> show(BuildContext context, String connectionId) {
    return showDialog(
      context: context,
      builder: (_) => MysqlEngineStatusDialog(connectionId: connectionId),
    );
  }

  @override
  State<MysqlEngineStatusDialog> createState() =>
      _MysqlEngineStatusDialogState();
}

class _MysqlEngineStatusDialogState extends State<MysqlEngineStatusDialog> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<AppProvider>();
    await provider.loadEngineStatus(widget.connectionId);
    if (mounted) {
      setState(() {
        _status = provider.getEngineStatus(widget.connectionId);
        _isLoading = false;
      });
    }
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
            LucideIcons.database,
            color: context.themeColors.accentBlue,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.engineStatusTitle),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: context.themeColors.accentBlue,
                ),
              )
            : _status == null
            ? Center(
                child: Text(
                  'Engine status not available for this connection.',
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
              )
            : SingleChildScrollView(
                child: SelectableText(
                  _status!['status']?.toString() ?? '',
                  style: TextStyle(
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    fontSize: 11,
                    color: colors.textPrimary,
                    height: 1.5,
                  ),
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
}
