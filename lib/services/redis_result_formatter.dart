// 第三波 C1 — Redis 命令返回值格式化器(供 Workbench/Pipeline/事务器复用)
//
// 从 RedisAdapter._formatResult 提升为 public,并增强对 scalar(nil/String/int)的处理。
// 适配 VirtualizedDataTable 的 List<Map<String,dynamic>> 输入。

/// 将 Redis 命令返回值格式化为表格行。
class RedisResultFormatter {
  /// 格式化 [result]([command] 用于区分 SCAN/HGETALL 等结构)。
  /// - nil → 单行 (nil)
  /// - scalar(String/int/double/bool)→ 单行 value
  /// - List → SCAN/SSCAN/HSCAN/ZSCAN 游标展开 / HGETALL 键值对 / 普通数组逐元素
  /// - 其他 → 单行原始 toString
  static List<Map<String, dynamic>> format(dynamic result, String command) {
    if (result == null) return const [{'result': '(nil)'}];

    if (result is List) return _formatList(result, command);

    // scalar — 用 'result' key 对齐 executeQuery 的 fallback 约定
    return [{'result': result.toString()}];
  }

  static List<Map<String, dynamic>> _formatList(List result, String command) {
    if (result.isEmpty) return const [];

    // SCAN/SSCAN/HSCAN/ZSCAN: [cursor, [items]]
    if (result.length == 2 && result[1] is List) {
      final cursor = result[0]?.toString() ?? '0';
      final items = result[1] as List;

      // HSCAN/ZSCAN 键值对(field-value / member-score)
      if ((command == 'HSCAN' || command == 'ZSCAN') &&
          items.length % 2 == 0 &&
          items.isNotEmpty) {
        final rows = <Map<String, dynamic>>[
          {'cursor': cursor, 'field': '(next cursor)', 'value': ''},
        ];
        for (var i = 0; i < items.length; i += 2) {
          rows.add({
            'cursor': '',
            'field': items[i]?.toString() ?? '',
            'value': items[i + 1]?.toString() ?? '',
          });
        }
        return rows;
      }

      // SCAN/SSCAN 普通列表
      final rows = <Map<String, dynamic>>[
        {'cursor': cursor, 'value': '(next cursor)'},
      ];
      for (final item in items) {
        rows.add({'cursor': '', 'value': item?.toString() ?? ''});
      }
      return rows;
    }

    // HGETALL 平铺键值对(仅 HGETALL 确证,避免误判偶数长度普通数组)
    if (command == 'HGETALL' && result.length % 2 == 0) {
      final map = <String, dynamic>{};
      for (var i = 0; i < result.length - 1; i += 2) {
        map[result[i].toString()] = result[i + 1];
      }
      if (map.length == result.length ~/ 2) return [map];
    }

    // 普通数组(LRANGE/SMEMBERS/ZRANGE/CONFIG GET 等:逐元素一行)
    return result
        .asMap()
        .entries
        .map((e) => {'index': e.key, 'value': e.value})
        .toList();
  }
}
