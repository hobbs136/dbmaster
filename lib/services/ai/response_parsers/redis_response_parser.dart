import 'ai_response_parser.dart';

/// Redis 命令响应解析器
///
/// 从 AI 返回的文本中提取 Redis 命令。
class RedisResponseParser extends AiResponseParser {
  RedisResponseParser({super.locale});

  @override
  List<String> extractExecutableStatements(String response) {
    final results = <String>[];
    final processedRanges = <List<int>>[];

    // 1. 提取 <sql>...</sql> 标签（最高优先级）
    final sqlTagPattern = RegExp(
      r'<sql>\s*([\s\S]*?)\s*</sql>',
      caseSensitive: false,
    );
    for (final match in sqlTagPattern.allMatches(response)) {
      final cmd = _cleanContent(match.group(1) ?? '');
      if (cmd.isNotEmpty && isValidCommand(cmd)) {
        results.add(cmd);
        processedRanges.add([match.start, match.end]);
      }
    }

    // 2. 提取 ```redis ... ``` 代码块
    final markdownPattern = RegExp(
      r'```(?:redis)?\s*\n?([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final match in markdownPattern.allMatches(response)) {
      if (_isRangeOverlapping(match.start, match.end, processedRanges))
        continue;

      final cmd = _cleanContent(match.group(1) ?? '');
      if (cmd.isNotEmpty && isValidCommand(cmd)) {
        results.add(cmd);
        processedRanges.add([match.start, match.end]);
      }
    }

    // 3. 纯 Redis 命令回退（简单匹配常见的 Redis 命令）
    if (results.isEmpty) {
      final redisPattern = RegExp(
        r'(?:^|\n)\s*(GET|SET|DEL|HGET|HSET|HDEL|LPUSH|RPUSH|LPOP|RPOP|LRANGE|SADD|SREM|SMEMBERS|SCARD|ZADD|ZREM|ZRANGE|ZREVRANGE|ZCARD|EXISTS|EXPIRE|TTL|KEYS|SCAN|FLUSHDB|FLUSHALL|MGET|MSET|INCR|DECR|INCRBY|DECRBY|HGETALL|HMGET|HMSET|HINCRBY|LLEN|SISMEMBER|ZSCORE|ZCOUNT|ZRANGEBYSCORE|ZREVRANGEBYSCORE|PING|INFO|CONFIG|DBSIZE|SELECT|AUTH|QUIT|MULTI|EXEC|DISCARD|WATCH|UNWATCH|SORT|BRPOP|BLPOP|RPOPLPUSH|BRPOPLPUSH|PUBLISH|SUBSCRIBE|UNSUBSCRIBE|PSUBSCRIBE|PUNSUBSCRIBE)\b[\s\S]*?(?=\n\s*(?:GET|SET|DEL|HGET|HSET|HDEL|LPUSH|RPUSH|LPOP|RPOP|LRANGE|SADD|SREM|SMEMBERS|SCARD|ZADD|ZREM|ZRANGE|ZREVRANGE|ZCARD|EXISTS|EXPIRE|TTL|KEYS|SCAN|FLUSHDB|FLUSHALL|MGET|MSET|INCR|DECR|INCRBY|DECRBY|HGETALL|HMGET|HMSET|HINCRBY|LLEN|SISMEMBER|ZSCORE|ZCOUNT|ZRANGEBYSCORE|ZREVRANGEBYSCORE|PING|INFO|CONFIG|DBSIZE|SELECT|AUTH|QUIT|MULTI|EXEC|DISCARD|WATCH|UNWATCH|SORT|BRPOP|BLPOP|RPOPLPUSH|BRPOPLPUSH|PUBLISH|SUBSCRIBE|UNSUBSCRIBE|PSUBSCRIBE|PUNSUBSCRIBE)\b|$)',
        caseSensitive: false,
        multiLine: true,
      );
      for (final match in redisPattern.allMatches(response)) {
        final cmd = _cleanContent(match.group(0) ?? '');
        if (cmd.isNotEmpty &&
            isValidCommand(cmd) &&
            !_isDuplicate(cmd, results)) {
          results.add(cmd);
        }
      }
    }

    return results;
  }

  @override
  bool isValidCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;

    // 排除明显的 SQL 语句
    final sqlKeywords = RegExp(
      r'\b(FROM|WHERE|JOIN|GROUP|ORDER|HAVING|UNION|VALUES|INTO|TABLE)\b',
      caseSensitive: false,
    );
    if (sqlKeywords.hasMatch(trimmed)) return false;

    final redisCommands = RegExp(
      r'^(GET|SET|DEL|HGET|HSET|HDEL|LPUSH|RPUSH|LPOP|RPOP|LRANGE|SADD|SREM|SMEMBERS|SCARD|ZADD|ZREM|ZRANGE|ZREVRANGE|ZCARD|EXISTS|EXPIRE|TTL|KEYS|SCAN|FLUSHDB|FLUSHALL|MGET|MSET|INCR|DECR|INCRBY|DECRBY|HGETALL|HMGET|HMSET|HINCRBY|LLEN|SISMEMBER|ZSCORE|ZCOUNT|ZRANGEBYSCORE|ZREVRANGEBYSCORE|PING|INFO|CONFIG|DBSIZE|SELECT|AUTH|QUIT|MULTI|EXEC|DISCARD|WATCH|UNWATCH|SORT|BRPOP|BLPOP|RPOPLPUSH|BRPOPLPUSH|PUBLISH|SUBSCRIBE|UNSUBSCRIBE|PSUBSCRIBE|PUNSUBSCRIBE)',
      caseSensitive: false,
    );
    return redisCommands.hasMatch(trimmed);
  }

  String _cleanContent(String content) {
    content = content.replaceAll(RegExp(r'^\s*```\w*\s*', multiLine: true), '');
    content = content.replaceAll(RegExp(r'\s*```\s*$', multiLine: true), '');

    final lines = content.split('\n');
    final cleanedLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      if (RegExp(r'^[\u4e00-\u9fa5\s：:]+$').hasMatch(trimmed)) return false;
      return true;
    }).toList();

    return cleanedLines.join('\n').trim();
  }

  bool _isRangeOverlapping(int start, int end, List<List<int>> ranges) {
    for (final range in ranges) {
      if (start < range[1] && end > range[0]) {
        return true;
      }
    }
    return false;
  }

  bool _isDuplicate(String cmd, List<String> existing) {
    final normalized = cmd.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final existingCmd in existing) {
      final existingNormalized = existingCmd
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalized == existingNormalized) return true;
    }
    return false;
  }
}
