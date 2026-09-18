import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../models/schema_diff_models.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/server_connection_provider.dart';
import '../../../services/database_abstract.dart';
import '../../../services/schema_diff/schema_diff_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/lite_touchpoint_gate.dart';
import '../../../theme/app_colors.dart';
import '../../server/conversion_guide_row.dart';
import '../error_boundary.dart';
import 'schema_diff_tree.dart';
import 'schema_diff_detail.dart';
import 'schema_diff_ddl_preview.dart';

/// Landing page for the Schema Diff automation pitch.
/// TODO(marketing): final URL pending; harmless default for now.
const String _kSchemaDiffLearnMoreUrl =
    'https://dbmaster.tech-site/server/learn-more';

/// Schema Diff 三栏页面容器
/// AppBar + 筛选栏 + 三栏布局 + 底部操作栏
class SchemaDiffPage extends StatefulWidget {
  final String? initialConnectionId;
  final String? initialDatabaseName;

  const SchemaDiffPage({
    super.key,
    this.initialConnectionId,
    this.initialDatabaseName,
  });

  @override
  State<SchemaDiffPage> createState() => _SchemaDiffPageState();
}

class _SchemaDiffPageState extends State<SchemaDiffPage> {
  // Connection selection
  String? _sourceConnectionId;
  String? _sourceDatabase;
  String? _sourceSchema;
  String? _targetConnectionId;
  String? _targetDatabase;
  String? _targetSchema;

  // Diff state
  SchemaDiffReport? _diffReport;
  bool _isLoading = false;
  String? _error;

  // Filter & selection
  DiffCategory _activeFilter = DiffCategory.all;
  String? _selectedObjectKey;
  final List<DiffIgnoreRule> _ignoreRules = [];

  // Sync state
  SyncPlan? _syncPlan;
  bool _isExecuting = false;
  bool _isDryRun = false; // 当前执行的是 Dry Run（true）还是 Execute（false）——用于按钮状态

  // Keyboard navigation — focus node driving ↑/↓ selection within the
  // object tree while the diff report is loaded.
  final FocusNode _keyboardFocusNode = FocusNode();

  // Cached future for the schema-diff lite touchpoint gate; updated after
  // each successful compare so FutureBuilder re-evaluates against the latest
  // feature-completion counter.
  Future<bool> _schemaDiffLiteGateFuture = Future.value(false);

  @override
  void initState() {
    super.initState();
    _sourceConnectionId = widget.initialConnectionId;
    _sourceDatabase = widget.initialDatabaseName;
    _schemaDiffLiteGateFuture = LiteTouchpointGate.instance.shouldShowLite(
      guideId: 'schema-diff-result',
      featureId: 'schema_diff_compare',
    );
  }

  // Keyboard navigation — release the focus node.
  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // Keyboard navigation. ↑/↓ move the tree selection (clamped, no
  // wrap); Enter confirms/selects the first item when nothing is selected.
  // Space is intentionally ignored: the detail & DDL panels expose no
  // per-item "include in sync" checkbox, so there is no toggle target — sync
  // plans are generated from the whole report.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_diffReport == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.arrowDown ||
        logical == LogicalKeyboardKey.arrowUp) {
      final keys = SchemaDiffTree.objectKeys(_diffReport!, _activeFilter);
      if (keys.isEmpty) return KeyEventResult.ignored;
      final next = SchemaDiffTree.moveSelection(
        keys,
        _selectedObjectKey,
        logical == LogicalKeyboardKey.arrowDown,
      );
      if (next != null && next != _selectedObjectKey) {
        setState(() => _selectedObjectKey = next);
      }
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.enter) {
      if (_selectedObjectKey == null) {
        final keys = SchemaDiffTree.objectKeys(_diffReport!, _activeFilter);
        if (keys.isNotEmpty) {
          setState(() => _selectedObjectKey = keys.first);
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- Selection helpers ----

  TableDiff? get _selectedTableDiff {
    if (_selectedObjectKey == null ||
        !_selectedObjectKey!.startsWith('table:')) {
      return null;
    }
    final name = _selectedObjectKey!.substring(6);
    return _diffReport?.tableDiffs.where((t) => t.name == name).firstOrNull;
  }

  ViewDiff? get _selectedViewDiff {
    if (_selectedObjectKey == null ||
        !_selectedObjectKey!.startsWith('view:')) {
      return null;
    }
    final name = _selectedObjectKey!.substring(5);
    return _diffReport?.viewDiffs.where((v) => v.name == name).firstOrNull;
  }

  ProcedureDiff? get _selectedProcedureDiff {
    if (_selectedObjectKey == null ||
        !_selectedObjectKey!.startsWith('proc:')) {
      return null;
    }
    final name = _selectedObjectKey!.substring(5);
    return _diffReport?.procedureDiffs.where((p) => p.name == name).firstOrNull;
  }

  bool get _canCompare {
    if (_sourceConnectionId == null ||
        _sourceDatabase == null ||
        _targetConnectionId == null ||
        _targetDatabase == null) {
      return false;
    }
    if (!mounted) return false;
    final connections = context.read<AppProvider>().connection.savedConnections;
    final sourceType = connections
        .where((c) => c.id == _sourceConnectionId)
        .firstOrNull
        ?.type;
    final targetType = connections
        .where((c) => c.id == _targetConnectionId)
        .firstOrNull
        ?.type;
    return sourceType != null && targetType != null && sourceType == targetType;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with connection selectors
        _buildHeader(context),
        _buildConnectionSelector(context),
        const Divider(height: 1),
        // Capture error warnings
        if (_diffReport != null && _diffReport!.captureErrors.isNotEmpty)
          _buildCaptureWarnings(),
        // Filter bar
        if (_diffReport != null) _buildFilterBar(context),
        if (_diffReport != null) const Divider(height: 1),
        // Main content
        Expanded(child: _buildMainContent()),
        // Lite conversion touchpoint (telemetry-funnel-plan §1.B): shown only
        // after a comparison completes AND the user is NOT connected to a
        // Server AND the gate (≥3 prior compares + kill switch + exposure cap)
        // is open.
        if (_diffReport != null) _buildSchemaDiffLiteGuide(context),
        // Bottom action bar
        if (_diffReport != null) _buildBottomBar(context),
      ],
    );
  }

  Widget _buildSchemaDiffLiteGuide(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isConnected = context.watch<ServerConnectionProvider>().isConnected;
    if (isConnected) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _schemaDiffLiteGateFuture,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        // Record exposure so the per-guide lifetime cap advances (async, fire
        // and forget — best-effort, does not block render).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            LiteTouchpointGate.instance.recordExposure('schema-diff-result');
          }
        });
        // TODO(marketing): lite copy is an EN placeholder pending replacement.
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space4,
            vertical: AppDesignSystem.space2,
          ),
          child: ConversionGuideRow(
            icon: LucideIcons.sparkles,
            title: l10n.touchpointLiteSchemaDiffTitle,
            description: l10n.touchpointLiteSchemaDiffDesc,
            actionLabel: l10n.touchpointLiteLearnMore,
            guideId: 'schema-diff-result',
            serverConnected: false,
            variant: ConversionGuideVariant.lite,
            onAction: _launchLearnMoreUrl,
            actionUrl: _kSchemaDiffLearnMoreUrl,
          ),
        );
      },
    );
  }

  Future<void> _launchLearnMoreUrl() async {
    final uri = Uri.parse(_kSchemaDiffLearnMoreUrl);
    try {
      await launchUrl(uri);
    } catch (_) {
      // Best-effort launch; click already counted by ConversionGuideRow.
    }
  }

  // ---- Header ----

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Row(
        children: [
          Icon(
            LucideIcons.arrowRightLeft,
            color: context.themeColors.accentBlue,
            size: 24,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Text(
              'Schema Diff & Sync',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (_diffReport != null)
            Padding(
              padding: const EdgeInsets.only(right: AppDesignSystem.space2),
              child: Text(
                '${_diffReport!.sourceDatabase} → ${_diffReport!.targetDatabase}',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Connection Selector ----

  Widget _buildConnectionSelector(BuildContext context) {
    final provider = context.read<AppProvider>();
    final connections = provider.connection.savedConnections;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: _ConnectionDropdown(
              label: 'Source',
              connections: connections,
              selectedConnectionId: _sourceConnectionId,
              selectedDatabase: _sourceDatabase,
              selectedSchema: _sourceSchema,
              onConnectionChanged: (id) {
                setState(() {
                  _sourceConnectionId = id;
                  _sourceDatabase = null;
                  _sourceSchema = null;
                });
              },
              onDatabaseChanged: (db) {
                setState(() {
                  _sourceDatabase = db;
                  _sourceSchema = null;
                });
              },
              onSchemaChanged: (s) => setState(() => _sourceSchema = s),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space4,
            ),
            child: Icon(
              LucideIcons.arrowRight,
              color: context.themeColors.textSecondary,
            ),
          ),
          Expanded(
            child: _ConnectionDropdown(
              label: 'Target',
              connections: connections,
              selectedConnectionId: _targetConnectionId,
              selectedDatabase: _targetDatabase,
              selectedSchema: _targetSchema,
              onConnectionChanged: (id) {
                setState(() {
                  _targetConnectionId = id;
                  _targetDatabase = null;
                  _targetSchema = null;
                });
              },
              onDatabaseChanged: (db) {
                setState(() {
                  _targetDatabase = db;
                  _targetSchema = null;
                });
              },
              onSchemaChanged: (s) => setState(() => _targetSchema = s),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          ElevatedButton.icon(
            onPressed: (_canCompare && !_isLoading) ? _runComparison : null,
            icon: _isLoading
                ? _btnSpinner(Theme.of(context).colorScheme.onPrimary)
                : const Icon(LucideIcons.arrowRightLeft, size: 18),
            label: Text(_isLoading ? 'Comparing...' : 'Compare'),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureWarnings() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space1,
      ),
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 16,
            color: context.themeColors.warning,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              '${_diffReport!.captureErrors.length} table(s) had capture errors',
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Filter Bar ----

  Widget _buildFilterBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            selected: _activeFilter == DiffCategory.all,
            onSelected: () => setState(() => _activeFilter = DiffCategory.all),
          ),
          _FilterChip(
            label: 'Added',
            color: Colors.green,
            selected: _activeFilter == DiffCategory.added,
            onSelected: () =>
                setState(() => _activeFilter = DiffCategory.added),
          ),
          _FilterChip(
            label: 'Modified',
            color: Colors.orange,
            selected: _activeFilter == DiffCategory.modified,
            onSelected: () =>
                setState(() => _activeFilter = DiffCategory.modified),
          ),
          _FilterChip(
            label: 'Removed',
            color: Colors.red,
            selected: _activeFilter == DiffCategory.removed,
            onSelected: () =>
                setState(() => _activeFilter = DiffCategory.removed),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          VerticalDivider(
            width: 1,
            color: context.themeColors.borderSubtle,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          _FilterChip(
            label: 'Tables',
            selected: _activeFilter == DiffCategory.tables,
            onSelected: () =>
                setState(() => _activeFilter = DiffCategory.tables),
          ),
          _FilterChip(
            label: 'Indexes',
            selected: _activeFilter == DiffCategory.indexes,
            onSelected: () =>
                setState(() => _activeFilter = DiffCategory.indexes),
          ),
          _FilterChip(
            label: 'Views',
            selected: _activeFilter == DiffCategory.views,
            onSelected: () =>
                setState(() => _activeFilter = DiffCategory.views),
          ),
        ],
      ),
    );
  }

  // ---- Main Content ----

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorView();
    }
    if (_diffReport == null) {
      return _buildEmptyView();
    }

    // Keyboard navigation — capture ↑/↓/Enter while focus is anywhere
    // within the three-panel workspace (autofocus grabs focus once the report
    // loads; clicking tree items keeps focus inside this subtree).
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Row(
        children: [
          // Left panel: object tree
          SchemaDiffTree(
            report: _diffReport!,
            selectedObjectKey: _selectedObjectKey,
            filter: _activeFilter,
            onSelect: (key) {
              setState(() => _selectedObjectKey = key);
            },
          ),
          VerticalDivider(
            width: 1,
            color: context.themeColors.borderSubtle,
          ),
          // Center panel: detail
          Expanded(
            child: SchemaDiffDetail(
              report: _diffReport!,
              selectedObjectKey: _selectedObjectKey,
            ),
          ),
          VerticalDivider(
            width: 1,
            color: context.themeColors.borderSubtle,
          ),
          // Right panel: DDL preview
          SchemaDiffDdlPreview(
            selectedTableDiff: _selectedTableDiff,
            selectedViewDiff: _selectedViewDiff,
            selectedProcedureDiff: _selectedProcedureDiff,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 48,
            color: context.themeColors.error,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          SelectableText(
            'Error: $_error',
            style: TextStyle(color: context.themeColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          ElevatedButton(onPressed: _runComparison, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.arrowRightLeft,
            size: 64,
            color: context.themeColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            'Select source and target databases to compare',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Bottom Action Bar ----

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.themeColors.borderColor)),
      ),
      child: Row(
        children: [
          // Stats summary
          _StatBadge(
            label: 'Added',
            count: _diffReport!.addedTables,
            color: Colors.green,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          _StatBadge(
            label: 'Modified',
            count: _diffReport!.modifiedTables,
            color: Colors.orange,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          _StatBadge(
            label: 'Removed',
            count: _diffReport!.removedTables,
            color: Colors.red,
          ),
          const Spacer(),
          if (_isExecuting)
            const SizedBox(width: 200, child: LinearProgressIndicator()),
          if (_isExecuting) const SizedBox(width: AppDesignSystem.space3),
          OutlinedButton.icon(
            onPressed: _isExecuting ? null : _generateSyncPlan,
            icon: const Icon(LucideIcons.wandSparkles, size: 16),
            label: const Text('Generate Plan'),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          OutlinedButton.icon(
            onPressed: (_syncPlan != null && !_isExecuting)
                ? () => _executeSync(dryRun: true)
                : null,
            icon: (_isExecuting && _isDryRun)
                ? _btnSpinner(Theme.of(context).colorScheme.primary)
                : const Icon(LucideIcons.eye, size: 16),
            label: Text((_isExecuting && _isDryRun) ? 'Running...' : 'Dry Run'),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: (_syncPlan != null && !_isExecuting)
                ? () => _executeSync(dryRun: false)
                : null,
            icon: (_isExecuting && !_isDryRun)
                ? _btnSpinner(Theme.of(context).colorScheme.onPrimary)
                : const Icon(LucideIcons.play, size: 16),
            label: Text(
              (_isExecuting && !_isDryRun) ? 'Executing...' : 'Execute',
            ),
          ),
        ],
      ),
    );
  }

  /// 按钮内的小转圈（执行中状态）。
  Widget _btnSpinner(Color color) => SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );

  // ---- Actions ----

  Future<void> _runComparison() async {
    if (!_canCompare) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _diffReport = null;
      _syncPlan = null;
      _selectedObjectKey = null;
    });

    try {
      final dbService = context.read<AppProvider>().dbService;
      final diffService = SchemaDiffService(dbService);

      final provider = context.read<AppProvider>();
      final connections = provider.connection.savedConnections;

      final sourceConnection = connections.firstWhere(
        (c) => c.id == _sourceConnectionId,
      );
      final targetConnection = connections.firstWhere(
        (c) => c.id == _targetConnectionId,
      );

      final sourceSnapshot = await diffService.captureSnapshot(
        connectionId: _sourceConnectionId!,
        connectionName: sourceConnection.name,
        databaseName: _sourceDatabase!,
        schemas: _sourceSchema == null ? null : [_sourceSchema!],
      );

      final targetSnapshot = await diffService.captureSnapshot(
        connectionId: _targetConnectionId!,
        connectionName: targetConnection.name,
        databaseName: _targetDatabase!,
        schemas: _targetSchema == null ? null : [_targetSchema!],
      );

      var report = diffService.compareSnapshots(
        source: sourceSnapshot,
        target: targetSnapshot,
      );

      // Apply ignore rules if configured
      if (_ignoreRules.isNotEmpty) {
        report = diffService.applyIgnoreRules(report, _ignoreRules);
      }

      setState(() {
        _diffReport = report;
        _isLoading = false;
      });
      // Manual Schema Diff compare completed (telemetry §4.1). Counter
      // increment is synchronous so the gate future observes the post-increment
      // count.
      TelemetryService.instance.logFeatureUsed('schema_diff_compare');
      // Refresh cached gate future so FutureBuilder in the completion surface
      // re-evaluates against the latest counter.
      _schemaDiffLiteGateFuture = LiteTouchpointGate.instance.shouldShowLite(
        guideId: 'schema-diff-result',
        featureId: 'schema_diff_compare',
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _generateSyncPlan() {
    if (_diffReport == null) return;

    // Schema Diff 同步：Pro 专属，Free 走试用（US4）
    final appProvider = context.read<AppProvider>();
    if (!appProvider.trySchemaSync(
      'schema_diff_plan_${DateTime.now().millisecondsSinceEpoch}',
    )) {
      return;
    }

    // open-core Phase B.2：同步计划生成经 SchemaSyncStrategy SPI 注入
    // （OSS=null → short-circuit，门禁已拦截，此分支理论上不可达）。
    final strategy = appProvider.proModule.schemaSyncStrategy;
    if (strategy == null) return;

    final dbService = appProvider.dbService;

    final targetConnection = context
        .read<AppProvider>()
        .connection
        .savedConnections
        .firstWhere((c) => c.id == _targetConnectionId);

    // Use generateSyncPlan which already handles FK dependency ordering
    final plan = strategy.generateSyncPlan(
      dbService,
      report: _diffReport!,
      targetConnectionId: _targetConnectionId!,
      targetDatabase: _targetDatabase!,
      dbType: targetConnection.type,
    );

    setState(() {
      _syncPlan = plan;
    });
  }

  Future<void> _executeSync({required bool dryRun}) async {
    if (_syncPlan == null) return;

    setState(() {
      _isExecuting = true;
      _isDryRun = dryRun;
    });

    // Hoisted out of try so the finally block can observe the final phase for
    // the feature_used payload.
    SyncProgress? lastProgress;
    try {
      final appProvider = context.read<AppProvider>();
      // open-core Phase B.2：经 SPI 注入执行；OSS=null → 不应达此分支
      // （_syncPlan 仅由 _generateSyncPlan 设置，后者 null 时 short-circuit）。
      final strategy = appProvider.proModule.schemaSyncStrategy;
      if (strategy == null) {
        setState(() {
          _isExecuting = false;
        });
        return;
      }
      final dbService = appProvider.dbService;

      final targetConnection = appProvider.connection.savedConnections
          .firstWhere((c) => c.id == _targetConnectionId);

      // Use Stream-based execution for real-time progress
      final stream = strategy.executeWithProgress(
        dbService,
        plan: _syncPlan!,
        connectionId: _targetConnectionId!,
        databaseName: _targetDatabase!,
        dbType: targetConnection.type,
        dryRun: dryRun,
      );

      await for (final progress in stream) {
        lastProgress = progress;
        if (!mounted) break;
      }

      if (!mounted) return;

      if (lastProgress != null) {
        // 有语句失败时（PG 事务会整体回滚，目标库无变化），
        // 明确报失败并展示首条失败语句 + 错误——不再以橙色「Sync completed」误导。
        final hasFailures =
            lastProgress.failureCount > 0 ||
            lastProgress.phase == SyncExecutionPhase.failed;

        if (!dryRun && hasFailures) {
          final failedSteps = lastProgress.completedSteps
              .where((s) => s.status == SyncStepStatus.failed)
              .toList();
          final detail = failedSteps.isEmpty
              ? (lastProgress.error ?? 'Unknown error')
              : '${failedSteps.first.operation.description} → ${failedSteps.first.error ?? lastProgress.error ?? 'Unknown error'}';
          AppErrorHandler.showErrorSnackBar(
            context,
            '同步失败：${lastProgress.failureCount}/${lastProgress.totalSteps} 条语句未成功。\n$detail',
            duration: const Duration(seconds: 8),
          );
        } else if (lastProgress.phase == SyncExecutionPhase.completed) {
          // 裸色 SnackBar → helper（F-15）
          AppErrorHandler.showSuccessSnackBar(
            context,
            dryRun
                ? 'Dry run completed — ${lastProgress.totalSteps} operations validated'
                : 'Sync completed: ${lastProgress.successCount} succeeded, ${lastProgress.failureCount} failed, ${lastProgress.skippedCount} skipped',
            duration: const Duration(seconds: 3),
          );
        } else if (lastProgress.phase == SyncExecutionPhase.failed) {
          AppErrorHandler.showErrorSnackBar(
            context,
            'Sync failed: ${lastProgress.error ?? "Unknown error"}',
          );
        }

        // 无论成败都刷新目标库——之前仅 failureCount==0 才刷新，
        // 导致回滚后 UI 仍显示陈旧结构，用户误以为"同步没生效 / 目标无变化"。
        if (!dryRun && _targetConnectionId != null) {
          final provider = context.read<AppProvider>();
          await provider.refreshDatabases(connectionId: _targetConnectionId);
          if (_targetDatabase != null) {
            await provider.loadDatabaseInfo(
              _targetConnectionId!,
              _targetDatabase!,
              forceRefresh: true,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, 'Sync error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExecuting = false);
      }
      // Manual Schema Diff sync executed (telemetry §4.1). `dry_run` and
      // `success` are not PII.
      final success =
          lastProgress?.phase == SyncExecutionPhase.completed &&
          (lastProgress?.failureCount ?? 0) == 0;
      TelemetryService.instance.logFeatureUsed(
        'schema_diff_sync',
        extra: {'dry_run': dryRun, 'success': success},
      );
    }
  }
}

// ---- Shared sub-widgets ----

class _ConnectionDropdown extends StatefulWidget {
  final String label;
  final List<DbServer> connections;
  final String? selectedConnectionId;
  final String? selectedDatabase;
  final String? selectedSchema;
  final ValueChanged<String?> onConnectionChanged;
  final ValueChanged<String?> onDatabaseChanged;
  final ValueChanged<String?> onSchemaChanged;

  const _ConnectionDropdown({
    required this.label,
    required this.connections,
    this.selectedConnectionId,
    this.selectedDatabase,
    this.selectedSchema,
    required this.onConnectionChanged,
    required this.onDatabaseChanged,
    required this.onSchemaChanged,
  });

  @override
  State<_ConnectionDropdown> createState() => _ConnectionDropdownState();
}

class _ConnectionDropdownState extends State<_ConnectionDropdown> {
  List<String> _schemas = [];
  bool _loadingSchemas = false;
  String? _loadedForConn;
  String? _loadedForDb;

  DbServer? get _selectedConnection {
    for (final c in widget.connections) {
      if (c.id == widget.selectedConnectionId) return c;
    }
    return null;
  }

  /// 仅 PG/SQLServer 显示 schema 选择（支持 schema 命名空间）。
  bool get _supportsSchemaNamespace {
    final conn = _selectedConnection;
    return conn != null &&
        (conn.type == DatabaseType.postgresql ||
            conn.type == DatabaseType.sqlserver);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadSchemas());
  }

  @override
  void didUpdateWidget(covariant _ConnectionDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedConnectionId != widget.selectedConnectionId ||
        oldWidget.selectedDatabase != widget.selectedDatabase) {
      _maybeLoadSchemas();
    }
  }

  Future<void> _maybeLoadSchemas() async {
    if (!_supportsSchemaNamespace ||
        widget.selectedConnectionId == null ||
        widget.selectedDatabase == null) {
      if (_schemas.isNotEmpty) setState(() => _schemas = []);
      return;
    }
    // 同一 (connection, database) 已加载则跳过，避免重复请求
    if (_loadedForConn == widget.selectedConnectionId &&
        _loadedForDb == widget.selectedDatabase &&
        _schemas.isNotEmpty) {
      return;
    }
    setState(() => _loadingSchemas = true);
    try {
      final adapter = context.read<AppProvider>().dbService.getAdapter(
        widget.selectedConnectionId!,
      );
      final List<String> list;
      if (adapter is SchemaAwareAdapter) {
        list = await (adapter as SchemaAwareAdapter).getSchemas();
      } else {
        list = const <String>[];
      }
      if (mounted) {
        setState(() {
          _schemas = list;
          _loadingSchemas = false;
          _loadedForConn = widget.selectedConnectionId;
          _loadedForDb = widget.selectedDatabase;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _schemas = [];
          _loadingSchemas = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final databases = widget.selectedConnectionId != null
        ? context.read<AppProvider>().connection.getConnectionDatabases(
            widget.selectedConnectionId!,
          )
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        DropdownButtonFormField<String>(
          initialValue: widget.selectedConnectionId,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select connection'),
          items: widget.connections.map((conn) {
            return DropdownMenuItem(
              value: conn.id,
              child: Row(
                children: [
                  Icon(conn.type.typeIcon, size: 18),
                  const SizedBox(width: AppDesignSystem.space2),
                  Expanded(
                    child: Text(conn.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) => widget.onConnectionChanged(value),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        DropdownButtonFormField<String>(
          initialValue: widget.selectedDatabase,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select database'),
          items: databases.map((db) {
            return DropdownMenuItem(value: db, child: Text(db));
          }).toList(),
          onChanged: widget.selectedConnectionId != null
              ? (value) => widget.onDatabaseChanged(value)
              : null,
        ),
        // schema 选择（仅 PG/SQLServer）；null = 全部 schema
        if (_supportsSchemaNamespace) ...[
          const SizedBox(height: AppDesignSystem.space2),
          DropdownButtonFormField<String?>(
            initialValue: widget.selectedSchema,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space2,
              ),
              border: const OutlineInputBorder(),
              suffixIcon: _loadingSchemas
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            hint: const Text('All schemas'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All schemas'),
              ),
              ..._schemas.map(
                (s) => DropdownMenuItem<String?>(value: s, child: Text(s)),
              ),
            ],
            onChanged: widget.selectedDatabase != null
                ? (value) => widget.onSchemaChanged(value)
                : null,
          ),
        ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    this.color,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.themeColors.accentBlue;
    return Padding(
      padding: const EdgeInsets.only(right: AppDesignSystem.space1),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? effectiveColor : null,
          ),
        ),
        selected: selected,
        onSelected: (_) => onSelected(),
        selectedColor: effectiveColor.withValues(alpha: 0.15),
        checkmarkColor: effectiveColor,
        side: BorderSide(
          color: selected
              ? effectiveColor.withValues(alpha: 0.5)
              : context.themeColors.borderSubtle,
        ),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
