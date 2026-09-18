/// Redis Key 信息模型
class RedisKeyInfo {
  final String name;
  final String type;
  final int ttl;
  final int size;

  const RedisKeyInfo({
    required this.name,
    this.type = '',
    this.ttl = -2,
    this.size = 0,
  });

  RedisKeyInfo copyWith({String? name, String? type, int? ttl, int? size}) {
    return RedisKeyInfo(
      name: name ?? this.name,
      type: type ?? this.type,
      ttl: ttl ?? this.ttl,
      size: size ?? this.size,
    );
  }

  bool get hasNoExpiry => ttl == -1;
  bool get isExpired => ttl == -2;
  bool get isExpiringSoon => ttl >= 0 && ttl < 60;
  bool get isShortTtl => ttl >= 60 && ttl < 3600;

  String get ttlDisplay {
    if (ttl == -1) return 'No TTL';
    if (ttl == -2) return 'Expired';
    if (ttl < 60) return '${ttl}s';
    if (ttl < 3600) return '${ttl ~/ 60}m';
    if (ttl < 86400) return '${ttl ~/ 3600}h';
    return '${ttl ~/ 86400}d';
  }

  String get sizeDisplay {
    if (size <= 0) return '';
    switch (type) {
      case 'string':
        if (size < 1024) return '$size B';
        if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      case 'hash':
        return '$size fields';
      case 'list':
      case 'set':
      case 'zset':
        return '$size items';
      case 'stream':
        return '$size entries';
      case 'bitmap':
      case 'hyperloglog':
        if (size < 1024) return '$size B';
        if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      case 'geo':
        return '$size items';
      case 'bitfield':
      case 'json':
      case 'rejson-rl':
        if (size < 1024) return '$size B';
        if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      case 'bloom':
      case 'cuckoo':
      case 'tdigest':
      case 'topk':
      case 'cms':
      case 'timeseries':
      case 'vectorset':
        if (size < 1024) return '$size B';
        if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      default:
        return '$size';
    }
  }
}

/// SCAN 分页结果
class RedisScanResult {
  final int cursor;
  final List<String> keys;

  const RedisScanResult({required this.cursor, required this.keys});
}

/// HSCAN 分页结果(字段-值对)
class RedisHashScanResult {
  final int cursor;
  final List<MapEntry<String, String>> fields;

  const RedisHashScanResult({required this.cursor, required this.fields});
}

/// ZSCAN 分页结果(成员-分数对)
class RedisZSetScanResult {
  final int cursor;
  final List<MapEntry<String, double>> members;

  const RedisZSetScanResult({required this.cursor, required this.members});
}

/// Redis 数据类型工具
class RedisTypeUtils {
  static const Map<String, String> typeIcons = {
    'string': '🔤',
    'hash': '🗂️',
    'list': '📋',
    'set': '🏷️',
    'zset': '📊',
    'stream': '🌊',
    'bitmap': '🖼️',
    'bitfield': '🔲',
    'hyperloglog': '🔢',
    'geo': '📍',
    'json': '📄',
    'rejson-rl': '📄',
    'bloom': '🌸',
    'cuckoo': '🐦',
    'tdigest': '📉',
    'topk': '🏆',
    'cms': '📊',
    'timeseries': '⏱️',
    'vectorset': '🔍',
    'none': '❓',
  };

  static const Map<String, String> typeLabels = {
    'string': 'string',
    'hash': 'hash',
    'list': 'list',
    'set': 'set',
    'zset': 'zset',
    'stream': 'stream',
    'bitmap': 'bitmap',
    'bitfield': 'bitfield',
    'hyperloglog': 'hyperloglog',
    'geo': 'geo',
    'json': 'json',
    'rejson-rl': 'json',
    'bloom': 'bloom',
    'cuckoo': 'cuckoo',
    'tdigest': 't-digest',
    'topk': 'top-k',
    'cms': 'cms',
    'timeseries': 'time series',
    'vectorset': 'vector set',
    'none': 'none',
  };

  static String getIcon(String type) => typeIcons[type.toLowerCase()] ?? '🔑';
  static String getLabel(String type) => typeLabels[type.toLowerCase()] ?? type;
}
