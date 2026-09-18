import 'dart:async';

import '../providers/bulk_close_controller.dart' show BulkCloseDecision;
import '../providers/tab_provider.dart' show QueryTab;
import '../molecules/bulk_close_dialog.dart' show BulkCloseResult;
import 'app_logger.dart';

/// 将用户在批量关闭对话框中的决定应用到实际 Tab 列表。
///
/// 该工具类不依赖任何 Provider 或 UI，只操作传入的 Tab 列表与回调，
/// 因此可以在单元测试中直接验证，也避免了在 `main.dart` 中写难以测试的
/// 关闭逻辑。
class CloseDecisionApplier {
  const CloseDecisionApplier._();

  /// 应用 [result] 中的决定：保存标记为 save 的 Tab，丢弃标记为 discard 的 Tab。
  ///
  /// - [tabs]：当前打开的 Tab 列表（调用时快照）。
  /// - [saveTab]：保存单个 Tab 的回调，返回是否保存成功。
  /// - [closeTabAtIndex]：按索引强制关闭 Tab 的回调。
  /// - [result]：用户确认后的批量关闭决定。
  ///
  /// 返回 `true` 表示所有决定都已成功应用（窗口可以继续关闭）；
  /// 返回 `false` 表示至少有一个 save 失败，调用方应保持窗口打开。
  static Future<bool> applyDecisions({
    required List<QueryTab> tabs,
    required Future<bool> Function(QueryTab tab) saveTab,
    required Future<void> Function(int index) closeTabAtIndex,
    required BulkCloseResult result,
  }) async {
    if (!result.confirmed) {
      return false;
    }

    final tabsToSave = <QueryTab>[];
    final tabsToDiscard = <QueryTab>[];

    for (final entry in result.decisions.entries) {
      final tab = _findTabById(tabs, entry.key);
      if (tab == null) {
        // Tab 在确认期间已被关闭或不存在，忽略该决定。
        AppLogger.w(
          'CloseDecisionApplier',
          '忽略对已不存在 Tab 的关闭决定: ${entry.key}',
        );
        continue;
      }
      switch (entry.value) {
        case BulkCloseDecision.save:
          tabsToSave.add(tab);
        case BulkCloseDecision.discard:
          tabsToDiscard.add(tab);
        case BulkCloseDecision.pending:
          break;
      }
    }

    var allSaved = true;
    final savedIndices = <int>[];

    // 先保存需要保存的 Tab；保存成功后立即关闭。
    for (final tab in tabsToSave) {
      try {
        final saved = await saveTab(tab);
        if (saved) {
          final index = tabs.indexOf(tab);
          if (index >= 0) {
            savedIndices.add(index);
          }
        } else {
          allSaved = false;
        }
      } catch (e, stack) {
        AppLogger.e('CloseDecisionApplier', '保存 Tab 失败: ${tab.id}', e, stack);
        allSaved = false;
      }
    }

    // 关闭已保存的 Tab（从高索引到低索引，避免索引错位）。
    savedIndices.sort((a, b) => b.compareTo(a));
    for (final index in savedIndices) {
      try {
        await closeTabAtIndex(index);
      } catch (e, stack) {
        AppLogger.e('CloseDecisionApplier', '关闭已保存 Tab 失败: $index', e, stack);
      }
    }

    // 关闭标记为丢弃的 Tab（从高索引到低索引，避免索引错位）。
    final discardIndices = tabsToDiscard
        .map((tab) => tabs.indexOf(tab))
        .where((index) => index >= 0)
        .toList();
    discardIndices.sort((a, b) => b.compareTo(a));
    for (final index in discardIndices) {
      try {
        await closeTabAtIndex(index);
      } catch (e, stack) {
        AppLogger.e('CloseDecisionApplier', '关闭丢弃 Tab 失败: $index', e, stack);
      }
    }

    return allSaved;
  }

  static QueryTab? _findTabById(List<QueryTab> tabs, String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }
}
