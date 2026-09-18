/// Redis Pub/Sub 消息模型。
///
/// 由 [RedisAdapter] 的 Pub/Sub 订阅流产生:[pubSubMessageStream]。
/// - [isPattern] 为 true 表示经 PSUBSCRIBE 模式订阅收到,此时 [pattern] 为匹配的模式。
class PubSubMessage {
  final String channel;
  final String payload;
  final bool isPattern;
  final String? pattern;
  final DateTime timestamp;

  const PubSubMessage({
    required this.channel,
    required this.payload,
    required this.isPattern,
    this.pattern,
    required this.timestamp,
  });
}
