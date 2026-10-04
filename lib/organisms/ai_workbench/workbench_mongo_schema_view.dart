//! AI 工作台 structure kind 的 Mongo 集合 schema 内容件（2b.2a 任务卡 §6.2）。
//!
//! R5 接缝：不碰 `MongoVisualizationService.loadSchema`（绑
//! `dbService.currentAdapter` = 侧栏当前连接，挂到舞台会读到非锁定连接的
//! schema）——本件消费 AppProvider 既有 **per-connection** facade
//! （loadMongoDBSchema / getMongoDBSchema / isLoadingMongoDBSchema，
//! app_provider.dart:2890/2822/2845）。呈现复用孤挂三件套的模型与呈现件
//! （InferredDocumentSchema.fromAdapterOutput + SchemaNestedExpander /
//! SchemaFieldItem，零改动）；孤挂三件套本身本批不删不碰（R5 已知项）。
//!
//! 三态：加载（workbenchMongoSchemaLoading）/ 失败（workbenchMongoSchemaLoadFailed
//! + commonRetry，重试 = 再调 loadMongoDBSchema）/ 空集合
//! （workbenchMongoSchemaEmpty + hint）。零写路径、零 Timer（R2）。
//!
//! 首帧拉取：schema 缓存为 null 且未在加载（沿 schema_view_widget.dart:21-26
//! 同款判断）→ post-frame 调 loadMongoDBSchema；facade 内部 loading 守卫
//! 保证幂等（app_provider.dart:2898）。因 facade 无错误字段，失败态由本件
//! 本地推导（一次加载结束但缓存仍为 null = 失败），避免失败后每帧重拉的
//! 无限循环（StatelessWidget 照抄经典模式会踩此坑，故本件为 StatefulWidget）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/organisms/mongodb/schema_view/schema_nested_expander.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/theme/app_colors.dart';

/// structure kind 的 Mongo 集合 schema 内容件（2b.2b 接线目标）。
///
/// 只读投影：渲染推断文档 schema 字段树，无任何写手势（§5 纪律 6）。
class WorkbenchMongoSchemaView extends StatefulWidget {
  const WorkbenchMongoSchemaView({
    super.key,
    required this.connectionId,
    required this.databaseName,
    required this.collectionName,
  });

  final String connectionId;

  /// 集合所在库名——透传给 `loadMongoDBSchema`（facade 按连接+集合键缓存，
  /// 库名仅用于加载时路由）。
  final String databaseName;

  final String collectionName;

  @override
  State<WorkbenchMongoSchemaView> createState() =>
      _WorkbenchMongoSchemaViewState();
}

class _WorkbenchMongoSchemaViewState extends State<WorkbenchMongoSchemaView> {
  /// 首帧已排程加载（防每次 rebuild 重复排程；facade 侧另有 loading 守卫）。
  bool _loadScheduled = false;

  /// 上一次 build 观察到「加载中」——用于识别「加载已结束但缓存仍为 null」
  /// 的失败态（facade 无错误字段，需本地推导）。
  bool _wasLoading = false;

  /// 一次加载结束后仍无数据 = 失败态。
  bool _loadFailed = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final schema = provider.getMongoDBSchema(
      widget.connectionId,
      widget.collectionName,
    );
    final loading = provider.isLoadingMongoDBSchema(
      widget.connectionId,
      widget.collectionName,
    );

    if (loading) {
      _wasLoading = true;
      return const _LoadingView();
    }

    if (schema == null) {
      if (_wasLoading) {
        // 一次加载已结束但缓存仍为 null → 失败态。
        _loadFailed = true;
      } else if (!_loadScheduled && !_loadFailed) {
        // 首帧：无缓存且未在加载（schema_view_widget.dart:21-26 同款判断）
        // → post-frame 拉取；loadMongoDBSchema 内部 loading 守卫保证幂等。
        _loadScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_load(provider));
        });
      }
      if (_loadFailed) {
        return _ErrorView(onRetry: _retry);
      }
      // 已排程但 provider 尚未翻 loading（排程回调未跑）：加载态占位。
      return const _LoadingView();
    }

    final inferred = InferredDocumentSchema.fromAdapterOutput(schema);
    if (inferred.isEmpty) {
      return const _EmptyView();
    }
    return _SchemaContent(
      collectionName: widget.collectionName,
      fieldCount: inferred.fields.length,
      fields: inferred.fields,
    );
  }

  Future<void> _load(AppProvider provider) async {
    try {
      await provider.loadMongoDBSchema(
        widget.connectionId,
        widget.databaseName,
        widget.collectionName,
      );
      if (!mounted) return;
      final schema = provider.getMongoDBSchema(
        widget.connectionId,
        widget.collectionName,
      );
      final loading = provider.isLoadingMongoDBSchema(
        widget.connectionId,
        widget.collectionName,
      );
      if (schema == null && !loading) {
        // 守卫通过但加载静默结束（如非 Mongo 连接/连接缺失），显式进入
        // 失败态，避免永挂加载占位。
        setState(() => _loadFailed = true);
      }
    } catch (_) {
      // facade 在连接缺失等场景会抛异常（app_provider.dart:2902）→ 失败态。
      if (mounted) {
        setState(() => _loadFailed = true);
      }
    }
  }

  /// 重试 = 再调 loadMongoDBSchema（任务书 §6.2 三态文案条款）。
  void _retry() {
    setState(() {
      _loadFailed = false;
      _wasLoading = false;
    });
    unawaited(_load(context.read<AppProvider>()));
  }
}

/// 加载态。
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.workbenchMongoSchemaLoading,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 失败态：图标 error 色 + 标题 + 重试按钮（重试 = 再调 loadMongoDBSchema）。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleAlert, size: 40, color: colors.error),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.workbenchMongoSchemaLoadFailed,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2_5),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}

/// 空集合态。
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.package, size: 40, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.workbenchMongoSchemaEmpty,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space6,
            ),
            child: Text(
              l10n.workbenchMongoSchemaEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 内容态：头行（集合名 + 字段数徽标，token 化，零文案——集合名与字段数
/// 均为数据非文案）+ 字段树 ListView（SchemaNestedExpander 零改动复用）。
class _SchemaContent extends StatelessWidget {
  const _SchemaContent({
    required this.collectionName,
    required this.fieldCount,
    required this.fields,
  });

  final String collectionName;
  final int fieldCount;
  final List<SchemaField> fields;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(color: colors.bgSecondary),
          child: Row(
            children: [
              Icon(LucideIcons.table2, size: 16, color: colors.textMuted),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  collectionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeMd,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              // 字段数摘要徽标（primaryContainer 徽标 token 组合，沿经典
              // schema_view_widget.dart:224-241 同款语汇）。
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space0_5,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  '$fieldCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.dividerColor),
        Expanded(
          child: ListView.builder(
            itemCount: fields.length,
            itemBuilder: (context, index) {
              final field = fields[index];
              return SchemaNestedExpander(
                key: ValueKey('workbench_mongo_field_$index'),
                field: field,
                depth: 0,
              );
            },
          ),
        ),
      ],
    );
  }
}
