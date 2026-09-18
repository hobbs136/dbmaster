import 'package:flutter/foundation.dart';

import '../models/error_event.dart';

/// 执行中心 Tab。
enum ExecutionCenterTab { tasks, errors }

/// 执行中心 Provider——错误环形缓冲（LRU [maxErrors]）+ 面板 UI 状态
///（开关 / 高度 / 当前 Tab）。
///
/// 任务仍以 `TaskProvider` 为唯一真相源；本 Provider 只持有错误列表与面板状态，
/// 并通过 [items] 提供合并视图。仅依赖 foundation（constitution I.2：Provider 不耦合 UI）。
class ExecutionCenterProvider extends ChangeNotifier {
  ExecutionCenterProvider();

  /// 错误历史容量上限（LRU）。
  static const int maxErrors = 100;

  final List<ErrorEvent> _errors = []; // newest first
  bool _isOpen = false;
  double _height = 260; // legacy（原底部高度，保留兼容）
  final double _width = 360; // plan §3.4：右侧抽屉宽度（固定，无 resizer）
  // plan §3.4：true=钉住（docked，workspace 收缩）；false=浮动（overlay，不收缩）
  bool _isPinned = true;
  ExecutionCenterTab _activeTab = ExecutionCenterTab.tasks;

  List<ErrorEvent> get errors => List.unmodifiable(_errors);
  bool get isOpen => _isOpen;
  double get height => _height;
  double get width => _width;
  bool get isPinned => _isPinned;
  ExecutionCenterTab get activeTab => _activeTab;

  void addError(ErrorEvent event) {
    _errors.insert(0, event);
    if (_errors.length > maxErrors) {
      _errors.removeLast();
    }
    notifyListeners();
  }

  void dismissError(String id) {
    final before = _errors.length;
    _errors.removeWhere((e) => e.id == id);
    if (_errors.length != before) notifyListeners();
  }

  void clearErrors() {
    if (_errors.isEmpty) return;
    _errors.clear();
    notifyListeners();
  }

  void open() {
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    _isOpen = false;
    notifyListeners();
  }

  void toggle() {
    _isOpen = !_isOpen;
    notifyListeners();
  }

  void setHeight(double h) {
    _height = h;
    notifyListeners();
  }

  void setActiveTab(ExecutionCenterTab tab) {
    _activeTab = tab;
    notifyListeners();
  }

  /// plan §3.4：切换钉住/浮动模式（true=docked 收缩 workspace，false=overlay 浮动）
  void togglePin() {
    _isPinned = !_isPinned;
    notifyListeners();
  }

  @override
  void dispose() {
    _errors.clear();
    super.dispose();
  }
}
