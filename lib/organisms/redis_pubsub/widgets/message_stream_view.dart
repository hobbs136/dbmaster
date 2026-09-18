// 全功能 Redis GUI — 阶段4: 消息流视图(受控,由父级喂入消息)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../models/redis_pubsub_message.dart';

class MessageStreamView extends StatelessWidget {
  /// 消息列表(由父级 RedisPubSubPanel 维护,受控)。
  final List<PubSubMessage> messages;
  final VoidCallback? onClear;

  const MessageStreamView({super.key, required this.messages, this.onClear});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.messageCircle,
                        size: 48,
                        color: context.themeColors.textMuted,
                      ),
                      const SizedBox(height: AppDesignSystem.space3),
                      Text(
                        'No messages yet',
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppDesignSystem.space2),
                      Text(
                        'Subscribe to channels and publish messages to see them here',
                        style: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: AppDesignSystem.fontSizeXs,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _buildMessageItem(context, messages[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.waves,
            size: 20,
            color: context.themeColors.accentCyan,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'Message Stream (${messages.length})',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.eraser, size: 18),
            tooltip: 'Clear messages',
            onPressed: (messages.isEmpty || onClear == null) ? null : onClear,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BuildContext context, PubSubMessage msg) {
    final ts = msg.timestamp;
    final accent = msg.isPattern
        ? context.themeColors.accentPurple
        : context.themeColors.accentCyan;
    final label = msg.isPattern
        ? '${msg.pattern} → ${msg.channel}'
        : msg.channel;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.themeColors.borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space1,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: AppDesignSystem.fontSizeXs,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                '${ts.hour}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: AppDesignSystem.fontSizeXs,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            msg.payload,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: AppDesignSystem.fontSizeSm,
            ),
          ),
        ],
      ),
    );
  }
}
