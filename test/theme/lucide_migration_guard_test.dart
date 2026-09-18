import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// C07（D9：全面切 Lucide）守卫：lib/ 禁止新增 Material `Icons.*` 引用。
/// 裸 `Icons.`（前面无字母，即不属于 LucideIcons./TreeIcons. 等）= 违例。
/// 扫描逻辑纯 Dart 实现（不依赖平台 grep），逐文件逐行检查。
void main() {
  test('lib/ 无 Material Icons 残留（D9 Lucide 单一图标体系）', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: '应在仓库根目录运行');
    final violations = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        var idx = line.indexOf('Icons.');
        while (idx != -1) {
          final prev = idx == 0 ? ' ' : line[idx - 1];
          final bare = prev.contains(RegExp('[A-Za-z]')) == false;
          if (bare) {
            violations.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
          idx = line.indexOf('Icons.', idx + 1);
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          '图标体系已全面切 Lucide（D9），新代码用 LucideIcons.*；'
          '若需 Material 特有图标先在 lucide_migration 映射表登记：${violations.take(5).join(' | ')}',
    );
  });

  test('DatabaseType.typeIcon 应为 Lucide 图标且全部已定义', () {
    for (final type in DatabaseType.values) {
      expect(type.typeIcon, isNotNull, reason: type.name);
    }
    // 抽查映射落位（C07 一次性切换的中央映射）
    expect(DatabaseType.mysql.typeIcon, LucideIcons.database);
    expect(DatabaseType.sqlite.typeIcon, LucideIcons.database);
    expect(DatabaseType.tdengine.typeIcon, LucideIcons.activity);
    expect(DatabaseType.clickhouse.typeIcon, LucideIcons.zap);
  });
}
