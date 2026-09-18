//! 安全审查状态指示器（ADR-0003 Part A D5）。
//!
//! 轻量的全局状态：编辑器审查后写入结果，状态栏读取展示。
//! 用 ChangeNotifier + ValueNotifier 模式，不改 AppProvider。

import 'package:flutter/foundation.dart';

/// 一次安全审查的结果摘要（供状态栏展示）。
class SafetyReviewResult {
  /// 审查的 SQL（截断展示，前 40 字符）。
  final String sqlPreview;

  /// 发现的 finding 总数。
  final int findingCount;

  /// 是否有 high 级别 finding。
  final bool hasHigh;

  /// 是否有 medium 级别 finding。
  final bool hasMedium;

  /// 审查时间。
  final DateTime at;

  const SafetyReviewResult({
    required this.sqlPreview,
    required this.findingCount,
    required this.hasHigh,
    required this.hasMedium,
    required this.at,
  });

  /// 「已审查」/「已审查 · N」的简短文案（N = finding 总数）。
  ///
  /// U17：新增 [localizedLabel]（前缀由调用方传入 l10n 文案）——本类是纯
  /// Dart 模型无 BuildContext。严重度经调用方着色表达（状态栏 icon/text
  /// 按 hasHigh/hasMedium 取 error/warning/success 色），不再内嵌 emoji。
  String localizedLabel(String reviewedText) {
    if (findingCount == 0) return reviewedText;
    return '$reviewedText · $findingCount';
  }
}

/// 全局单例：安全审查状态。编辑器写入，状态栏读取。
class SafetyReviewIndicator extends ChangeNotifier {
  static final SafetyReviewIndicator instance = SafetyReviewIndicator._();

  SafetyReviewIndicator._();

  SafetyReviewResult? _lastResult;
  SafetyReviewResult? get lastResult => _lastResult;

  /// 编辑器审查后调用。
  void update(SafetyReviewResult result) {
    _lastResult = result;
    notifyListeners();
  }

  /// 清除（切换连接时）。
  void clear() {
    _lastResult = null;
    notifyListeners();
  }
}
