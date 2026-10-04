//! observe 内存分析段（2b.1，Redis；R4 接缝：不复用经典 panel widget）。
//!
//! 数据源 = `provider.getRedisAdapter(connectionId)` →
//! `getTopKeysByMemory` / `memoryDoctor` / `memoryStats` 三方法同源
//! （与经典 redis_memory_analysis_panel 同款数据方法，零改动经典路径）。
//!
//! 内容内三子视图切换（Top-N / Doctor / Stats）：切换语汇用 token 化
//! segmented 形态（**不复用**经典 ChoiceChip 硬编码英文）；Top-N 用
//! VirtualizedDataTable（经典同款复用）；Doctor/Stats = mono 文本滚动。
//!
//! 刷新语义（R2）：mount 首载 + 锁切换各自动拉取一次；子视图切换 =
//! 打开新观察对象（沿经典 _switchTab 语义，切换即拉取）；手动刷新重载
//! 当前子视图。adapter 为 null（防御）→ commonError 语义。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';
import '../results/virtualized_data_table.dart';

/// observe 内存分析段（Redis）。
class WorkbenchObserveRedisSegment extends StatefulWidget {
  const WorkbenchObserveRedisSegment({
    super.key,
    required this.connectionId,
    required this.refreshTick,
    required this.onLoaded,
  });

  /// 锁定连接 id（数据键；变化 = 锁切换，自动拉取一次并归位 Top-N）。
  final String connectionId;

  /// 手动刷新序号（变化 = 手动刷新，重载当前子视图）。
  final int refreshTick;

  /// 成功加载完成回调（内容壳更新时间戳；失败不回调——R2 锁定）。
  final VoidCallback onLoaded;

  /// Top-N 表格探针。
  static const Key tableKey = ValueKey('workbench_observe_redis_table');

  /// Doctor/Stats 文本探针。
  static const Key textKey = ValueKey('workbench_observe_redis_text');

  /// 加载失败态探针。
  static const Key errorKey = ValueKey('workbench_observe_redis_error');

  /// adapter 缺失防御态探针。
  static const Key adapterMissingKey = ValueKey(
    'workbench_observe_redis_adapter_missing',
  );

  /// 子视图切换项探针（[index] = 0 Top-N / 1 Doctor / 2 Stats）。
  static Key viewSwitchKey(int index) =>
      ValueKey('workbench_observe_redis_view_$index');

  @override
  State<WorkbenchObserveRedisSegment> createState() =>
      _WorkbenchObserveRedisSegmentState();
}

class _WorkbenchObserveRedisSegmentState
    extends State<WorkbenchObserveRedisSegment> {
  int _tab = 0; // 0 = Top-N / 1 = Doctor / 2 = Stats
  List<Map<String, dynamic>> _topN = const [];
  String _text = '';
  bool _loading = false;
  bool _failed = false;
  bool _adapterMissing = false;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    // R2：mount 首载自动拉取一次（默认 Top-N）。
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkbenchObserveRedisSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionId != widget.connectionId) {
      // R1：锁切换 = 打开新观察对象 → 归位 Top-N + 自动拉取一次。
      setState(() {
        _tab = 0;
        _text = '';
        _topN = const [];
        _adapterMissing = false;
      });
      _load();
    } else if (oldWidget.refreshTick != widget.refreshTick) {
      // R2：此后仅手动刷新（重载当前子视图）。
      _load();
    }
  }

  /// 拉取当前子视图一次（R2：失败不更新时间戳）。
  Future<void> _load() async {
    final seq = ++_loadSeq;
    final provider = context.read<AppProvider>();
    final adapter = provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      // 防御：锁定的连接无 Redis adapter（连接未登记/已断开）。
      if (mounted && seq == _loadSeq) {
        setState(() => _adapterMissing = true);
      }
      return;
    }
    setState(() {
      _adapterMissing = false;
      _loading = true;
      _failed = false;
    });
    var ok = false;
    try {
      if (_tab == 0) {
        final items = await adapter.getTopKeysByMemory();
        if (!mounted || seq != _loadSeq) return;
        setState(() {
          _topN = items
              .map(
                (e) => {
                  'key': e['key'],
                  'bytes': e['bytes'],
                  'size': _fmtBytes(e['bytes'] as int),
                },
              )
              .toList();
        });
      } else if (_tab == 1) {
        final text = await adapter.memoryDoctor();
        if (!mounted || seq != _loadSeq) return;
        setState(() => _text = text);
      } else {
        final stats = await adapter.memoryStats();
        if (!mounted || seq != _loadSeq) return;
        setState(() => _text = stats?.toString() ?? '');
      }
      ok = true;
    } catch (_) {
      ok = false;
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _loading = false;
      _failed = !ok;
    });
    if (ok) widget.onLoaded();
  }

  /// 子视图切换（沿经典 _switchTab 语义：切换 = 打开新观察对象，即拉取）。
  void _switchTab(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
      _text = '';
      _topN = const [];
      _failed = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_adapterMissing) {
      return Center(
        key: WorkbenchObserveRedisSegment.adapterMissingKey,
        child: Text(
          l10n.commonError,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeSm,
            color: context.themeColors.textMuted,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildViewSwitch(context, l10n),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(child: _buildBody(context, l10n)),
      ],
    );
  }

  /// token 化 segmented 三子视图切换（不复用经典 ChoiceChip——R4）。
  Widget _buildViewSwitch(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewButton(context, 0, l10n.workbenchObserveRedisTopN),
          _buildViewButton(context, 1, l10n.workbenchObserveRedisDoctor),
          _buildViewButton(context, 2, l10n.workbenchObserveRedisStats),
        ],
      ),
    );
  }

  Widget _buildViewButton(BuildContext context, int index, String label) {
    final colors = context.themeColors;
    final selected = _tab == index;
    return InkWell(
      onTap: () => _switchTab(index),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm - 2),
      child: Container(
        key: WorkbenchObserveRedisSegment.viewSwitchKey(index),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space0_5,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm - 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeSm,
            fontWeight: selected
                ? AppDesignSystem.fontWeightMedium
                : FontWeight.w400,
            color: selected ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        key: WorkbenchObserveRedisSegment.errorKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert, size: 24, color: colors.textMuted),
            const SizedBox(height: AppDesignSystem.space1_5),
            Text(
              l10n.workbenchObserveLoadFailed,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            TextButton(onPressed: _load, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }
    if (_tab == 0) {
      if (_topN.isEmpty) {
        return Center(
          child: Text(
            l10n.workbenchObserveRedisNoKeys,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: colors.textMuted,
            ),
          ),
        );
      }
      return VirtualizedDataTable(
        key: WorkbenchObserveRedisSegment.tableKey,
        columns: const ['key', 'bytes', 'size'],
        data: _topN,
        showRowNumbers: false,
      );
    }
    return SingleChildScrollView(
      child: SelectableText(
        _text.isEmpty ? l10n.commonNoData : _text,
        key: WorkbenchObserveRedisSegment.textKey,
        style: TextStyle(
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontSize: AppDesignSystem.fontSizeXs,
          color: colors.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
