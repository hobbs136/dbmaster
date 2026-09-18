// 全功能 Redis GUI — 阶段4: 订阅树(受控,接真实 adapter)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';

class SubscriptionTree extends StatefulWidget {
  /// 已订阅频道列表(由父级 RedisPubSubPanel 维护,受控)。
  final List<String> channels;
  final Future<void> Function(String) onSubscribe;
  final Future<void> Function(String) onUnsubscribe;

  const SubscriptionTree({
    super.key,
    required this.channels,
    required this.onSubscribe,
    required this.onUnsubscribe,
  });

  @override
  State<SubscriptionTree> createState() => _SubscriptionTreeState();
}

class _SubscriptionTreeState extends State<SubscriptionTree> {
  final TextEditingController _channelController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _channelController.dispose();
    super.dispose();
  }

  Future<void> _doSubscribe() async {
    final ch = _channelController.text.trim();
    if (ch.isEmpty) return;
    setState(() => _busy = true);
    try {
      // 委托父级调真实 adapter.pubSubSubscribe
      await widget.onSubscribe(ch);
      if (mounted) _channelController.clear();
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
        Expanded(
          child: widget.channels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.wifiOff,
                        size: 48,
                        color: context.themeColors.textMuted,
                      ),
                      const SizedBox(height: AppDesignSystem.space3),
                      Text(
                        'No subscriptions',
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: widget.channels.length,
                  itemBuilder: (context, index) {
                    final channel = widget.channels[index];
                    return ListTile(
                      title: Text(
                        channel,
                        style: TextStyle(
                          color: context.themeColors.textPrimary,
                          fontSize: AppDesignSystem.fontSizeSm,
                        ),
                      ),
                      leading: Icon(
                        LucideIcons.circleDot,
                        color: context.themeColors.accentGreen,
                        size: 20,
                      ),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        tooltip: 'Unsubscribe',
                        onPressed: () => widget.onUnsubscribe(channel),
                      ),
                    );
                  },
                ),
        ),
        _buildAddSection(),
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
            LucideIcons.rss,
            size: 20,
            color: context.themeColors.accentCyan,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'Subscriptions (${widget.channels.length})',
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

  Widget _buildAddSection() {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
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
              onSubmitted: (_) => _doSubscribe(),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: _busy ? null : _doSubscribe,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Subscribe'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentCyan,
            ),
          ),
        ],
      ),
    );
  }
}
