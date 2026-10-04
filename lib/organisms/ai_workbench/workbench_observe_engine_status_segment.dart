//! observe 引擎状态段（2b.1，MySQL；R2 刷新语义）。
//!
//! 数据源 = `provider.connection.loadEngineStatus(connectionId)` 拉取 +
//! `getEngineStatus` 读缓存（connection_provider 既有 facade，SHOW ENGINE
//! INNODB STATUS 文本）。形态 = mono 11 SelectableText 单滚动区（沿
//! mysql_engine_status_dialog.dart 正文语义）。
//!
//! 状态三态：缓存 null = 加载中（首载）/ 加载失败 = workbenchObserveLoadFailed
//! + 重试 / 成功但文本空 = commonNoData。

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_colors.dart';

/// observe 引擎状态段（MySQL）。
class WorkbenchObserveEngineStatusSegment extends StatefulWidget {
  const WorkbenchObserveEngineStatusSegment({
    super.key,
    required this.connectionId,
    required this.refreshTick,
    required this.onLoaded,
  });

  /// 锁定连接 id（数据键；变化 = 锁切换，自动拉取一次）。
  final String connectionId;

  /// 手动刷新序号（变化 = 手动刷新，重载一次）。
  final int refreshTick;

  /// 成功加载完成回调（内容壳更新时间戳；失败不回调——R2 锁定）。
  final VoidCallback onLoaded;

  /// 引擎状态文本探针。
  static const Key textKey = ValueKey('workbench_observe_engine_status_text');

  /// 加载失败态探针。
  static const Key errorKey = ValueKey('workbench_observe_engine_status_error');

  @override
  State<WorkbenchObserveEngineStatusSegment> createState() =>
      _WorkbenchObserveEngineStatusSegmentState();
}

class _WorkbenchObserveEngineStatusSegmentState
    extends State<WorkbenchObserveEngineStatusSegment> {
  bool _failed = false;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    // R2：mount 首载自动拉取一次。
    _load();
  }

  @override
  void didUpdateWidget(
    covariant WorkbenchObserveEngineStatusSegment oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionId != widget.connectionId) {
      // R1：锁切换 = 打开新观察对象 → 自动拉取一次。
      _load();
    } else if (oldWidget.refreshTick != widget.refreshTick) {
      // R2：此后仅手动刷新。
      _load();
    }
  }

  /// 拉取一次：facade 失败（dbService catch → null）不落缓存——加载完成后
  /// 缓存仍 null = 失败（R2：失败不更新时间戳）。
  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() => _failed = false);
    final provider = context.read<AppProvider>();
    var ok = false;
    try {
      await provider.connection.loadEngineStatus(widget.connectionId);
      final data = provider.connection.getEngineStatus(widget.connectionId);
      ok = data != null;
    } catch (_) {
      ok = false;
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() => _failed = !ok);
    if (ok) widget.onLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<AppProvider>();
    final data = provider.connection.getEngineStatus(widget.connectionId);
    if (data == null) {
      return _failed
          ? _buildError(context, l10n)
          : const Center(child: CircularProgressIndicator());
    }
    final status = data['status']?.toString() ?? '';
    if (status.isEmpty) {
      return Center(
        child: Text(
          l10n.commonNoData,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeXs,
            color: context.themeColors.textMuted,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      child: SelectableText(
        status,
        key: WorkbenchObserveEngineStatusSegment.textKey,
        style: TextStyle(
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontSize: AppDesignSystem.fontSizeXs,
          color: context.themeColors.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, AppLocalizations l10n) {
    final colors = context.themeColors;
    return Center(
      key: WorkbenchObserveEngineStatusSegment.errorKey,
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
}
