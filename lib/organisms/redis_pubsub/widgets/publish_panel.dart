// 全功能 Redis GUI — 阶段4: 发布面板(回调,接真实 adapter)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';

class PublishPanel extends StatefulWidget {
  /// 发布回调(由父级 RedisPubSubPanel 调真实 adapter.publish)。
  final Future<void> Function(String channel, String message) onPublish;

  const PublishPanel({super.key, required this.onPublish});

  @override
  State<PublishPanel> createState() => _PublishPanelState();
}

class _PublishPanelState extends State<PublishPanel> {
  final TextEditingController _channelController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<_PubRecord> _history = [];
  bool _busy = false;

  @override
  void dispose() {
    _channelController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final channel = _channelController.text.trim();
    final message = _messageController.text;
    if (channel.isEmpty || message.isEmpty) return;

    setState(() => _busy = true);
    try {
      // 委托父级调真实 adapter.publish(走主连接 runCommand)
      await widget.onPublish(channel, message);
      if (!mounted) return;
      setState(() {
        _history.insert(0, _PubRecord(channel, message, DateTime.now()));
        if (_history.length > 10) _history.removeLast();
      });
      _messageController.clear();
    } catch (_) {
      // 错误由父级统一显示
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          child: TextField(
            controller: _channelController,
            style: TextStyle(color: context.themeColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Channel',
              labelStyle: TextStyle(color: context.themeColors.textMuted),
              hintText: 'Enter channel name',
              hintStyle: TextStyle(color: context.themeColors.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              filled: true,
              fillColor: context.themeColors.bgTertiary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          child: TextField(
            controller: _messageController,
            maxLines: null,
            minLines: 4,
            keyboardType: TextInputType.multiline,
            style: TextStyle(color: context.themeColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Message',
              labelStyle: TextStyle(color: context.themeColors.textMuted),
              hintText: 'Enter message to publish',
              hintStyle: TextStyle(color: context.themeColors.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              filled: true,
              fillColor: context.themeColors.bgTertiary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _publish,
              icon: const Icon(LucideIcons.send, size: 18),
              label: const Text('Publish'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentCyan,
                padding: const EdgeInsets.all(AppDesignSystem.space3),
              ),
            ),
          ),
        ),
        if (_history.isNotEmpty) _buildHistory(context),
      ],
    );
  }

  Widget _buildHeader() {
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
            LucideIcons.send,
            size: 20,
            color: context.themeColors.accentCyan,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'Publish',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Publications',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeXs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          ..._history.take(5).map((pub) => _buildHistoryItem(context, pub)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, _PubRecord pub) {
    final truncated = pub.message.length > 30
        ? '${pub.message.substring(0, 30)}...'
        : pub.message;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      child: Row(
        children: [
          Icon(
            LucideIcons.arrowRight,
            size: 14,
            color: context.themeColors.accentCyan,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pub.channel,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeXs,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  truncated,
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '${pub.timestamp.hour}:${pub.timestamp.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              color: context.themeColors.textMuted,
              fontSize: AppDesignSystem.fontSizeXs,
            ),
          ),
        ],
      ),
    );
  }
}

class _PubRecord {
  final String channel;
  final String message;
  final DateTime timestamp;
  const _PubRecord(this.channel, this.message, this.timestamp);
}
