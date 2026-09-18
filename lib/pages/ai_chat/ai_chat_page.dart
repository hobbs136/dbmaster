import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../organisms/ai_panel/ai_panel_widget.dart';
import '../../providers/ai_panel_provider.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

class AiChatPage extends StatelessWidget {
  const AiChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: context.read<AiPanelProvider>(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(
                LucideIcons.bot,
                size: 20,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                AppLocalizations.of(context)!.aiChatPageTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textPrimary,
                ),
              ),
            ],
          ),
          backgroundColor: context.themeColors.bgPrimary,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: context.themeColors.borderLight, height: 1),
          ),
        ),
        body: const SafeArea(child: AiPanelWidget()),
      ),
    );
  }
}
