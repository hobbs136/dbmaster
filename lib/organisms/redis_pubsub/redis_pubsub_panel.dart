// 全功能 Redis GUI — 阶段4: Pub/Sub Studio(接通真实订阅)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../models/redis_pubsub_message.dart';
import '../../../services/adapters/redis_adapter.dart';
import 'widgets/subscription_tree.dart';
import 'widgets/message_stream_view.dart';
import 'widgets/publish_panel.dart';

class RedisPubSubPanel extends StatefulWidget {
  final String connectionId;
  final String databaseName;
  final AppProvider provider;

  const RedisPubSubPanel({
    super.key,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
  });

  @override
  State<RedisPubSubPanel> createState() => _RedisPubSubPanelState();
}

class _RedisPubSubPanelState extends State<RedisPubSubPanel> {
  RedisAdapter? _adapter;
  StreamSubscription<PubSubMessage>? _streamSub;
  final List<PubSubMessage> _messages = [];
  final Set<String> _channels = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    // 拿到共享 adapter 并订阅真实消息流(带 onError)
    _adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (_adapter != null) {
      _streamSub = _adapter!.pubSubMessageStream.listen(
        (msg) {
          if (!mounted) return;
          setState(() {
            _messages.insert(0, msg);
            if (_messages.length > 100) _messages.removeLast();
          });
        },
        onError: (Object e, StackTrace st) {
          if (!mounted) return;
          setState(() => _error = 'Stream error: $e');
        },
      );
    }
  }

  @override
  void dispose() {
    // 取消监听 + 释放 Pub/Sub 专用连接(本 Dialog 拥有,避免泄漏)
    final sub = _streamSub;
    final adapter = _adapter;
    if (sub != null) unawaited(sub.cancel());
    if (adapter != null) unawaited(adapter.disposePubSub());
    super.dispose();
  }

  Future<void> _subscribe(String channel) async {
    if (_adapter == null || channel.isEmpty) return;
    try {
      await _adapter!.pubSubSubscribe(channel);
      if (!mounted) return;
      setState(() {
        _channels.add(channel);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Subscribe failed: $e');
    }
  }

  Future<void> _unsubscribe(String channel) async {
    if (_adapter == null) return;
    try {
      await _adapter!.pubSubUnsubscribe(channel);
      if (!mounted) return;
      setState(() => _channels.remove(channel));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Unsubscribe failed: $e');
    }
  }

  Future<void> _publish(String channel, String message) async {
    if (_adapter == null || channel.isEmpty || message.isEmpty) return;
    try {
      await _adapter!.publish(channel, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Publish failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _adapter != null;
    return Container(
      height: 600,
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context, ready),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space4,
                vertical: AppDesignSystem.space2,
              ),
              color: context.themeColors.accentRed.withValues(alpha: 0.1),
              child: Text(
                _error!,
                style: TextStyle(
                  color: context.themeColors.accentRed,
                  fontSize: AppDesignSystem.fontSizeXs,
                ),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: SubscriptionTree(
                    channels: _channels.toList(),
                    onSubscribe: _subscribe,
                    onUnsubscribe: _unsubscribe,
                  ),
                ),
                Container(width: 1, color: Theme.of(context).dividerColor),
                Expanded(
                  flex: 5,
                  child: MessageStreamView(
                    messages: _messages,
                    onClear: () => setState(_messages.clear),
                  ),
                ),
                Container(width: 1, color: Theme.of(context).dividerColor),
                SizedBox(width: 250, child: PublishPanel(onPublish: _publish)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool ready) {
    final color = ready
        ? context.themeColors.accentGreen
        : context.themeColors.accentOrange;
    final label = ready ? 'Connected' : 'No Adapter';
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.wifi,
            color: context.themeColors.accentCyan,
            size: 24,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pub/Sub Studio',
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Real-time message monitoring and publishing',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: AppDesignSystem.fontSizeSm,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circle, size: 8, color: color),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
