import 'package:flutter/foundation.dart';
import 'tab_provider.dart' show QueryTab;

/// 用户在批量关闭对话框中对单个 Tab 做出的决定。
enum BulkCloseDecision {
  /// 尚未决定；确认时该 Tab 将保持打开。
  pending,

  /// 保存后关闭。
  save,

  /// 不保存直接关闭。
  discard,
}

/// 批量关闭对话框中的单行数据。
class BulkCloseItem {
  final QueryTab tab;
  BulkCloseDecision decision;

  BulkCloseItem({required this.tab, this.decision = BulkCloseDecision.pending});

  bool get isPending => decision == BulkCloseDecision.pending;
  bool get isSave => decision == BulkCloseDecision.save;
  bool get isDiscard => decision == BulkCloseDecision.discard;
}

/// 批量未保存 Tab 关闭控制器。
///
/// 负责维护每个待关闭 Tab 的决定状态，并提供批量操作入口。
/// 不直接操作 UI，也不持有其他 Provider 引用。
class BulkCloseController extends ChangeNotifier {
  final List<BulkCloseItem> _items;

  BulkCloseController(List<QueryTab> tabs)
    : _items = tabs.map((tab) => BulkCloseItem(tab: tab)).toList();

  List<BulkCloseItem> get items => List.unmodifiable(_items);

  /// 是否所有 Tab 都已做出决定。
  bool get allDecided => _items.every((item) => !item.isPending);

  /// 是否存在未决定的 Tab。
  bool get hasPendingItems => _items.any((item) => item.isPending);

  BulkCloseItem? _itemForTab(QueryTab tab) {
    for (final item in _items) {
      if (item.tab.id == tab.id) {
        return item;
      }
    }
    return null;
  }

  /// 获取指定 Tab 的当前决定。
  ///
  /// 若该 Tab 不在当前列表中，返回 [BulkCloseDecision.pending] 而不是抛出异常，
  /// 避免关闭流程中 Tab 已被移除时崩溃。
  BulkCloseDecision decisionFor(QueryTab tab) {
    final item = _itemForTab(tab);
    return item?.decision ?? BulkCloseDecision.pending;
  }

  /// 设置单个 Tab 的决定。
  ///
  /// 若该 Tab 不在当前列表中则静默忽略，避免关闭流程中 Tab 已被移除时崩溃。
  void setDecision(QueryTab tab, BulkCloseDecision decision) {
    final item = _itemForTab(tab);
    if (item == null || item.decision == decision) {
      return;
    }
    item.decision = decision;
    notifyListeners();
  }

  /// 将全部仍处于待定状态的 Tab 标记为保存。
  void saveAllPending() {
    for (final item in _items) {
      if (item.isPending) {
        item.decision = BulkCloseDecision.save;
      }
    }
    notifyListeners();
  }

  /// 将全部仍处于待定状态的 Tab 标记为丢弃。
  void discardAllPending() {
    for (final item in _items) {
      if (item.isPending) {
        item.decision = BulkCloseDecision.discard;
      }
    }
    notifyListeners();
  }

  /// 将全部 Tab 重置为未决定。
  void pendingAll() {
    for (final item in _items) {
      item.decision = BulkCloseDecision.pending;
    }
    notifyListeners();
  }

  /// 返回所有被标记为保存的 Tab。
  List<QueryTab> get tabsToSave =>
      _items.where((item) => item.isSave).map((item) => item.tab).toList();

  /// 返回所有被标记为丢弃的 Tab。
  List<QueryTab> get tabsToDiscard =>
      _items.where((item) => item.isDiscard).map((item) => item.tab).toList();

  /// 返回所有仍处于未决定状态的 Tab。
  List<QueryTab> get tabsToKeep =>
      _items.where((item) => item.isPending).map((item) => item.tab).toList();
}
