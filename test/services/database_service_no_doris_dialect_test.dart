import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 结构性不变量（spec 028 SC-003 / FR-002）：
/// 重构后服务层不得含任何 Doris 方言字符串——Doris DDL 方言唯一真相为 `DorisAdapter`。
/// 本测试读取 `database_service.dart` 源码断言之，防未来回退（把 Doris 方言再内联回服务层）。
void main() {
  test('database_service.dart 不含 Doris 方言字符串（方言单一真相 = adapter）', () {
    final src = File('lib/services/database_service.dart').readAsStringSync();

    // 027 曾在服务层内联这些 Doris 方言；028 重构后必须为 0（只活在 DorisAdapter）。
    const dorisDialectMarkers = <String>[
      'DISTRIBUTED BY HASH',
      'USING INVERTED',
      'replication_num',
    ];

    for (final marker in dorisDialectMarkers) {
      expect(
        src.contains(marker),
        isFalse,
        reason:
            '服务层不得含 Doris 方言字符串 "$marker"——Doris DDL 方言应只在 DorisAdapter。',
      );
    }
  });
}
