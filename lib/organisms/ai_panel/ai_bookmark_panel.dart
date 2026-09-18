import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/database_models.dart';
import '../../models/ai_conversation_session.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

class AiBookmarkPanel extends StatelessWidget {
  final List<AiBookmark> bookmarks;
  final Map<String, AiMessage> messageMap;
  final Function(String messageId) onBookmarkSelected;
  final Function(String bookmarkId) onBookmarkDeleted;

  const AiBookmarkPanel({
    super.key,
    required this.bookmarks,
    required this.messageMap,
    required this.onBookmarkSelected,
    required this.onBookmarkDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (bookmarks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.bookmark,
              size: 48,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              l10n.aiPanelNoBookmarks,
              style: TextStyle(
                fontSize: 14,
                color: context.themeColors.textMuted,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              l10n.aiPanelClickBookmarkIcon,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        final message = messageMap[bookmark.messageId];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.bookmark,
                    size: 14,
                    color: context.themeColors.accentYellow,
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  Text(
                    _formatTime(bookmark.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => onBookmarkDeleted(bookmark.id),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        LucideIcons.x,
                        size: 14,
                        color: context.themeColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              if (bookmark.note != null && bookmark.note!.isNotEmpty) ...[
                const SizedBox(height: AppDesignSystem.space1_5),
                Text(
                  bookmark.note!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.themeColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (bookmark.tags.isNotEmpty) ...[
                const SizedBox(height: AppDesignSystem.space1_5),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: bookmark.tags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDesignSystem.space1_5,
                            vertical: AppDesignSystem.space0_5,
                          ),
                          decoration: BoxDecoration(
                            color: context.themeColors.accentPurple.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppDesignSystem.radiusSm,
                            ),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.accentPurple,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (message != null) ...[
                const SizedBox(height: AppDesignSystem.space2),
                InkWell(
                  onTap: () => onBookmarkSelected(bookmark.messageId),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.themeColors.bgSecondary,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.content,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.textSecondary,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppDesignSystem.space1),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 10,
                          color: context.themeColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
