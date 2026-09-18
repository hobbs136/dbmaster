// 第四波 D3 — 键空间通知监听(复用第一波 Pub/Sub 专用连接,零新增连接)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../models/redis_pubsub_message.dart';
import '../../../services/adapters/redis_adapter.dart';

class RedisKeyspacePanel extends StatefulWidget {
  final String connectionId;
  final AppProvider provider;

  const RedisKeyspacePanel({
    super.key,
    required this.connectionId,
    required this.provider,
  });

  @override
  State<RedisKeyspacePanel> createState() => _RedisKeyspacePanelState();
}

class _KeyEvent {
  final String db;
  final String key;
  final String event;
  final DateTime timestamp;
  const _KeyEvent({
    required this.db,
    required this.key,
    required this.event,
    required this.timestamp,
  });
}

class _RedisKeyspacePanelState extends State<RedisKeyspacePanel> {
  RedisAdapter? _adapter;
  StreamSubscription<PubSubMessage>? _streamSub;
  final List<_KeyEvent> _events = [];
  bool _watching = false;
  String? _error;
  String _mode = 'keyspace'; // keyspace / keyevent

  @override
  void initState() {
    super.initState();
    _adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (_adapter != null) {
      // 复用 Pub/Sub 消息流,过滤键空间通知前缀
      _streamSub = _adapter!.pubSubMessageStream.listen(
        _onMessage,
        onError: (Object e, StackTrace st) {
          if (!mounted) return;
          setState(() => _error = 'Stream error: $e');
        },
      );
    }
  }

  @override
  void dispose() {
    // 只 cancel 监听,不调 disposePubSub(避免拆掉 Pub/Sub Studio 订阅)
    unawaited(_streamSub?.cancel());
    final adapter = _adapter;
    if (adapter != null && _watching) {
      unawaited(
        adapter.pubSubUnsubscribe(
          _channelFor(adapter.currentDbIndex),
          isPattern: true,
        ),
      );
    }
    super.dispose();
  }

  void _onMessage(PubSubMessage msg) {
    if (!mounted) return;
    if (!msg.channel.startsWith('__keyspace@') &&
        !msg.channel.startsWith('__keyevent@')) {
      return;
    }
    final ev = _parse(msg);
    if (ev == null) return;
    setState(() {
      _events.insert(0, ev);
      if (_events.length > 200) _events.removeLast();
    });
  }

  /// 解析 channel 格式(用 db/key/event 占位):keyspace 或 keyevent 类型。
  _KeyEvent? _parse(PubSubMessage msg) {
    final parts = msg.channel.split('__'); // ['', 'keyspace@0', 'mykey']
    if (parts.length < 3) return null;
    final typeDb = parts[1].split('@');
    if (typeDb.length < 2) return null;
    final type = typeDb[0];
    final db = typeDb[1];
    final rest = parts.sublist(2).join('__');
    if (type == 'keyspace') {
      // rest=key, payload=event
      return _KeyEvent(
        db: db,
        key: rest,
        event: msg.payload,
        timestamp: msg.timestamp,
      );
    }
    // keyevent: rest=event, payload=key
    return _KeyEvent(
      db: db,
      key: msg.payload,
      event: rest,
      timestamp: msg.timestamp,
    );
  }

  // 键空间通知 channel 模式（Redis 实际发布到 `__keyspace@<db>__:<key>`，
  // 精确订阅 `__keyspace@<db>__` 收不到任何事件，必须 PSUBSCRIBE `...:*`）。
  // 花括号必要:db 后紧跟 __,否则 $db__ 会被解析为 db__。
  // ignore: unnecessary_brace_in_string_interps
  String _channelFor(int db) => '__${_mode}@${db}__:*';

  Future<void> _toggleWatching() async {
    if (_watching) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    final adapter = _adapter;
    if (adapter == null) return;
    final channel = _channelFor(adapter.currentDbIndex);
    setState(() => _error = null);
    try {
      await adapter.pubSubEnsureConnected();
      // 启用键空间通知(CONFIG SET notify-keyspace-events KEA,走 runCommand 绕过 forbidden)
      try {
        await adapter.runCommand(const [
          'CONFIG',
          'SET',
          'notify-keyspace-events',
          'KEA',
        ]);
      } catch (_) {
        // 权限不足或已启用,忽略
      }
      await adapter.pubSubSubscribe(channel, isPattern: true);
      if (!mounted) return;
      setState(() => _watching = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Start failed: $e');
    }
  }

  Future<void> _stop() async {
    final adapter = _adapter;
    if (adapter == null) return;
    try {
      await adapter.pubSubUnsubscribe(
        _channelFor(adapter.currentDbIndex),
        isPattern: true,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _watching = false);
  }

  Future<void> _switchMode(String m) async {
    if (m == _mode) return;
    final wasWatching = _watching;
    if (wasWatching) await _stop();
    setState(() => _mode = m);
    if (wasWatching) await _start();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 500,
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: AppDesignSystem.space2),
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              color: context.themeColors.accentRed.withValues(alpha: 0.1),
              child: Text(
                _error!,
                style: TextStyle(
                  color: context.themeColors.accentRed,
                  fontSize: AppDesignSystem.fontSizeXs,
                ),
              ),
            ),
          const SizedBox(height: AppDesignSystem.space2),
          Expanded(child: _buildEvents()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          LucideIcons.bellRing,
          color: context.themeColors.accentOrange,
          size: 24,
        ),
        const SizedBox(width: AppDesignSystem.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Keyspace Notifications',
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: AppDesignSystem.fontSizeLg,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'db${_adapter?.currentDbIndex ?? 0} · ${_watching ? 'watching' : 'stopped'}',
                style: TextStyle(
                  color: _watching
                      ? context.themeColors.accentGreen
                      : context.themeColors.textMuted,
                  fontSize: AppDesignSystem.fontSizeSm,
                ),
              ),
            ],
          ),
        ),
        ChoiceChip(
          label: const Text('Keyspace'),
          selected: _mode == 'keyspace',
          onSelected: (_) => _switchMode('keyspace'),
        ),
        const SizedBox(width: AppDesignSystem.space1),
        ChoiceChip(
          label: const Text('Keyevent'),
          selected: _mode == 'keyevent',
          onSelected: (_) => _switchMode('keyevent'),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        ElevatedButton.icon(
          onPressed: _toggleWatching,
          icon: Icon(
            _watching ? LucideIcons.square : LucideIcons.play,
            size: 18,
          ),
          label: Text(_watching ? 'Stop' : 'Start'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _watching
                ? context.themeColors.accentRed
                : context.themeColors.accentGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildEvents() {
    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.bellOff,
              size: 48,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              _watching
                  ? 'Waiting for key events...'
                  : 'Press Start to watch key events',
              style: TextStyle(color: context.themeColors.textSecondary),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              'Sets notify-keyspace-events=KEA on Start',
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: AppDesignSystem.fontSizeXs,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _events.length,
      itemBuilder: (context, i) {
        final ev = _events[i];
        final ts = ev.timestamp;
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.themeColors.borderSubtle,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space1,
                ),
                decoration: BoxDecoration(
                  color: _eventColor(ev.event).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  ev.event,
                  style: TextStyle(
                    color: _eventColor(ev.event),
                    fontSize: AppDesignSystem.fontSizeXs,
                    fontWeight: FontWeight.bold,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  ev.key,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    fontSize: AppDesignSystem.fontSizeXs,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '@${ev.db} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: AppDesignSystem.fontSizeXs,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _eventColor(String event) {
    switch (event) {
      case 'del':
      case 'expired':
      case 'evicted':
        return context.themeColors.accentRed;
      case 'set':
      case 'hset':
      case 'sadd':
      case 'zadd':
        return context.themeColors.accentGreen;
      default:
        return AppDesignSystem.accentPrimary;
    }
  }
}
