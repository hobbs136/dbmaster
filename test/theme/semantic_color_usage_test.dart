import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

/// C-THEME-006：契约 C1 静态扫描——lib/ 界面代码禁止直用
/// `AppDesignSystem.error / success / warning / info`，必须经
/// `context.themeColors.*` 主题分发取色。
///
/// 豁免（契约 C1 例外条款）：`lib/theme/` 主题定义文件自身
/// （design_system / app_theme / app_colors）。
void main() {
  // 直用模式：词边界排除 errorLight / successLight 等 *Light 变体名
  final directUsePattern = RegExp(
    r'AppDesignSystem\.(error|success|warning|info)(?![A-Za-z])',
  );

  bool isExempt(String normalizedPath) {
    return normalizedPath.startsWith('lib/theme/');
  }

  /// 返回 {文件路径: 直用处数}，仅含未豁免文件
  Map<String, int> scanDirectUsages() {
    final violations = <String, int>{};
    final libDir = io.Directory('lib');
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! io.File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (isExempt(path)) continue;
      final count = directUsePattern
          .allMatches(entity.readAsStringSync())
          .length;
      if (count > 0) violations[path] = count;
    }
    return violations;
  }

  test(
    'C-THEME-006: lib/ 语义色直用点为零（契约 C1）',
    () {
      final violations = scanDirectUsages();
      expect(
        violations,
        isEmpty,
        reason: '契约 C1：以下文件仍直用 AppDesignSystem 语义色，'
            '须改用 context.themeColors.*：\n'
            '${violations.entries.map((e) => '  ${e.key}: ${e.value} 处').join('\n')}',
      );
    },
  );
}
