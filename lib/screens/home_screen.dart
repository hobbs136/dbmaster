// ============================================================================
// DbMaster HomeScreen - Main application shell (refactored)
// ============================================================================
//
// 拆分记录：
//   2026-06-09 — AiPanelOverlay / AiMiniFab 各自独立到 organisms/ai_panel/。
//   2026-08-14 (layout plan §3.1) — Stack 4 层语义化解耦，本文件退化为薄壳
//                （不 watch 任何 provider，build < 60 行）。4 层在 lib/screens/home/：
//                  z0 MainWorkspaceLayer / z1 ExecutionCenterOverlay /
//                  z2 AiFullscreenOverlay / z3 AiMiniFabLayer
//                每层只订阅自己的状态切片；本地 UI 状态（resizer/GlobalKey）
//                下沉到 z0；shell 仅保留 dialog / 命令面板 / _onProviderChange /
//                布局投影 toggle（用 _lastConstraints）。
// ============================================================================

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:async';
import '../utils/app_logger.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../atoms/app_transitions.dart';
import '../providers/app_provider.dart';
import '../providers/server_connection_provider.dart';
import '../services/server_connection.dart';
import '../organisms/server/server_connect_dialog.dart';
import '../providers/connection_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/layout_preferences_provider.dart';
import '../layout/effective_layout.dart';
import '../l10n/app_localizations.dart';
import '../organisms/connection/connection_dialog.dart';
import '../organisms/connection/connect_failure_dialog.dart';
import '../organisms/connection/error_boundary.dart';
import '../organisms/connection/status_bar_widget.dart';
import '../organisms/pro/pro_purchase_ui.dart';
import '../organisms/connection/er_diagram_dialog.dart';
import '../organisms/dialogs/performance_analyzer_dialog.dart';
import '../organisms/connection/command_palette.dart';
import '../organisms/dialogs/shortcuts_dialog.dart';
import '../organisms/dialogs/audit_log_dialog.dart';
import '../models/connection_event.dart';
import '../models/connection_failure.dart';
import '../core/shortcuts/global_shortcuts_wrapper.dart';
import '../core/commands/app_commands.dart';
// 查询执行编排单一真相源（spec 040 Phase 2.1）
import '../core/commands/query_execution_helper.dart';
import '../theme/app_colors.dart';
// Stack 4 层（layout plan §3.1）——z-order 由 build() 内 Stack 代码顺序决定
import 'home/ai_mini_fab_layer.dart';
import 'home/ai_fullscreen_overlay.dart';
import 'home/execution_center_overlay.dart';
import 'home/main_workspace_layer.dart';

// ============================================================================
// HomeScreen - Main entry point
// ============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // -------------------------------------------------------------------------
  // State fields
  // -------------------------------------------------------------------------
  // 仅保留 shell 级状态：resizer / GlobalKey / sidebar 折叠已下沉到
  // MainWorkspaceLayer（z0），sidebar 折叠改为读 LayoutPreferencesProvider。
  /// 最近一次 build 的 constraints——供 toggle 回调计算 projected 降级态（plan §3.2）
  BoxConstraints? _lastConstraints;

  /// 上次会话过期弹窗时间——并行 API 调用同时 401 时只弹一次（30s 冷却）。
  DateTime? _lastAuthPromptAt;

  /// 挂接 _onProviderChange 时缓存的引用——dispose 时 widget 已停用，
  /// 不能再 context.read（deactivated-ancestor 断言）。
  AppProvider? _attachedProvider;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AppProvider>();
      _attachedProvider = provider;
      provider.addListener(_onProviderChange);

      // API services report 401s via ServerConnection.authFailures so the
      // shell can surface one "session expired" prompt with a re-login entry.
      ServerConnection().authFailures.addListener(_onAuthFailure);

      // U15：启动静默检查更新（24h 冷却 + 可在设置关闭）；有新版时经
      // _onUpdateCheck 弹一次性提示条。
      UpdateService.instance.addListener(_onUpdateCheck);
      unawaited(UpdateService.instance.maybeAutoCheck());

      // sidebar 折叠态：不再镜像到本地，由 MainWorkspaceLayer(z0) 直读
      // LayoutPreferencesProvider.sidebarCollapsed 驱动（plan §3.1）。

      // 初始化应用数据，捕获可能的异常
      _initializeProvider(provider);

      // initialize the server connection provider. In
      // embedded mode this is a no-op (already connected). In remote mode it
      // attempts session restore so users don't re-enter credentials on restart.
      _initializeServerConnection();

      // 同步标题栏主题（确保启动时标题栏颜色与应用主题一致）
      context.read<ThemeProvider>().syncTitleBarTheme();
    });
  }

  Future<void> _initializeProvider(AppProvider provider) async {
    try {
      await provider.initialize();
      // Note: AiPanelOverlay 和 AiMiniFab 各自在 initState 中从
      // LayoutPreferencesProvider 加载自己的偏移量，无需在此处集中加载。
    } catch (e, stackTrace) {
      AppLogger.e(
        'HomeScreen',
        'Failed to initialize provider: $e\n$stackTrace',
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.scrInitFailed(e.toString()),
          duration: const Duration(seconds: 5),
          onRetry: () => _initializeProvider(provider),
        );
      }
    }
  }

  // kick off server-connection provider init
  // (embedded-mode no-op / remote-mode session restore). Fire-and-forget;
  // failures just leave the connection disconnected (recoverable via the
  // connect dialog).
  Future<void> _initializeServerConnection() async {
    try {
      final serverProvider = context.read<ServerConnectionProvider>();
      await serverProvider.initialize();
    } catch (e, stackTrace) {
      AppLogger.w(
        'HomeScreen',
        'Server connection init failed: $e\n$stackTrace',
      );
    }
  }

  @override
  void dispose() {
    _attachedProvider?.removeListener(_onProviderChange);
    ServerConnection().authFailures.removeListener(_onAuthFailure);
    UpdateService.instance.removeListener(_onUpdateCheck);
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Update-available prompt（#32 U15）
  // -------------------------------------------------------------------------
  bool _updatePromptShown = false;

  void _onUpdateCheck() {
    final svc = UpdateService.instance;
    if (_updatePromptShown || !svc.updateAvailable) return;
    _updatePromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.updateAvailableSnackbar(svc.latestTag ?? '')),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: l10n.updateGoDownload,
            onPressed: () async {
              try {
                await launchUrl(svc.downloadUrl);
              } catch (_) {} // best-effort
            },
          ),
        ),
      );
    });
  }

  // -------------------------------------------------------------------------
  // Provider change listener
  // -------------------------------------------------------------------------
  void _onProviderChange() {
    final provider = context.read<AppProvider>();
    if (provider.errorMessage != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && provider.errorMessage != null) {
          _showErrorDialog(provider.errorMessage!);
          provider.clearError();
        }
      });
    }

    // 检测事务回滚警告
    if (provider.hasPendingTransactionRollback && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && provider.hasPendingTransactionRollback) {
          _showTransactionRollbackWarning();
          provider.clearTransactionRollbackWarning();
        }
      });
    }

    // 检测会话恢复通知
    if (provider.lastSessionRestored != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && provider.lastSessionRestored != null) {
          _showSessionRestoredNotification(provider.lastSessionRestored!);
          provider.clearSessionRestoredNotification();
        }
      });
    }

    // U16：崩溃恢复提示（异常退出后恢复了 N 个标签页，一次性）
    if (provider.lastCrashRestoreTabCount != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || provider.lastCrashRestoreTabCount == null) return;
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.crashRestoredTabs(provider.lastCrashRestoreTabCount!),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        provider.clearCrashRestoreNotification();
      });
    }

    // 检测升级提示
    if (provider.pendingUpgradeFeature != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && provider.pendingUpgradeFeature != null) {
          // open-core Phase B：升级对话框经 ProPurchaseUi SPI 注入（OSS NoOp）。
          context.read<ProPurchaseUi>().showUpgradeDialog(context);
          provider.clearPendingUpgradeFeature();
        }
      });
    }

    // 试用消费就地提示剩余次数（FR-013）
    if (provider.lastTrialConsumed != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || provider.lastTrialConsumed == null) return;
        final l10n = AppLocalizations.of(context)!;
        final tc = provider.lastTrialConsumed!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.trialRemaining(tc.remaining, tc.feature.name)),
            duration: const Duration(seconds: 2),
          ),
        );
        provider.clearLastTrialConsumed();
      });
    }
  }

  // -------------------------------------------------------------------------
  // Session-expired prompt（#32 U02）
  // -------------------------------------------------------------------------
  // API services 在抛 *ApiAuthException 前调 ServerConnection
  // .reportAuthFailure()；这里统一弹一次「会话已过期」，给重登入口——
  // 之前各对话框只显示英文裸错误且状态栏恒绿，用户无路可走。
  void _onAuthFailure() {
    if (!mounted) return;
    // 仍在连接态说明 token 刷新已恢复（瞬时 401 与刷新竞态），不打扰。
    if (ServerConnection().connectionState == ServerConnectionState.connected) {
      return;
    }
    final now = DateTime.now();
    if (_lastAuthPromptAt != null &&
        now.difference(_lastAuthPromptAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastAuthPromptAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSessionExpiredDialog();
    });
  }

  Future<void> _showSessionExpiredDialog() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final relogin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.serverSessionExpiredTitle),
        content: Text(l10n.serverSessionExpiredMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.serverSessionRelogin),
          ),
        ],
      ),
    );
    if (relogin == true && mounted) {
      await showServerConnectDialog(
        context,
        context.read<ServerConnectionProvider>(),
      );
    }
  }

  void _showErrorDialog(String errorMessage) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Row(
          children: [
            Icon(LucideIcons.circleAlert, color: context.themeColors.error),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              l10n.commonError,
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
          child: Text(
            errorMessage,
            style: TextStyle(color: context.themeColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  void _showTransactionRollbackWarning() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(LucideIcons.triangleAlert, color: context.themeColors.warning),
            const SizedBox(width: AppDesignSystem.space2),
            const Expanded(
              child: Text(
                'Connection lost. Uncommitted transaction has been automatically rolled back.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: context.themeColors.warning.withValues(alpha: 0.9),
        duration: const Duration(seconds: 8),
        persist:
            false, // 带 action 默认 persist=true 不自动消失（Flutter 3.41）；Dismiss 仍可提前关闭
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showSessionRestoredNotification(SessionRestored event) {
    if (!mounted) return;

    final restoredCount = event.restoredItems.length;
    final failedCount = event.failedItems.length;

    String message;
    if (restoredCount > 0 && failedCount == 0) {
      message =
          'Connection restored. Session state recovered: ${event.restoredItems.join(', ')}.';
    } else if (restoredCount > 0 && failedCount > 0) {
      message =
          'Connection restored. Recovered: ${event.restoredItems.join(', ')}. Failed: ${event.failedItems.join(', ')}.';
    } else {
      message = 'Connection restored. Session state recovery failed.';
    }

    if (event.wasInTransaction) {
      message += ' Note: Previous transaction was lost due to disconnection.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              LucideIcons.circleCheckBig,
              color: context.themeColors.success,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: context.themeColors.success.withValues(alpha: 0.9),
        duration: const Duration(seconds: 8),
        persist:
            false, // 带 action 默认 persist=true 不自动消失（Flutter 3.41）；Dismiss 仍可提前关闭
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sidebar toggle
  // -------------------------------------------------------------------------
  void _toggleSidebar() {
    final layoutProvider = context.read<LayoutPreferencesProvider>();
    final targetCollapsed = !layoutProvider.sidebarCollapsed;
    // 用户想展开（targetCollapsed=false），但拥挤态 effective 会强制折叠 → 阻止 + 提示
    if (!targetCollapsed && _wouldSidebarBeForcedCollapsed()) {
      _showInsufficientSpaceSnack();
      return;
    }
    // 不 setState——provider notify 驱动 MainWorkspaceLayer(z0) 重建（plan §3.1）
    layoutProvider.setSidebarCollapsed(targetCollapsed);
  }

  /// 用户若展开 sidebar，effective 是否会因空间不足把它强制折叠回去（plan §3.2）。
  bool _wouldSidebarBeForcedCollapsed() {
    final constraints = _lastConstraints;
    if (constraints == null) return false;
    final appProvider = context.read<AppProvider>();
    final layoutProvider = context.read<LayoutPreferencesProvider>();
    final projected = computeEffectiveLayout(
      totalWidth: constraints.maxWidth,
      sidebarWidth: layoutProvider.sidebarWidth,
      aiPanelWidth: layoutProvider.aiPanelWidth,
      ecWidth: appProvider.executionCenter.width,
      sidebarCollapsed: false, // 用户想要的目标：展开
      aiOpen: appProvider.aiPanelOpen,
      aiFullscreen: appProvider.aiPanelFullscreen,
      ecOpen: appProvider.executionCenter.isOpen,
      ecPinned: appProvider.executionCenter.isPinned,
    );
    return projected.collapseSidebar;
  }

  /// 用户若把 AI 切回 docked，effective 是否会强制浮层（plan §3.2）。
  bool _wouldAiBeForcedOverlay() {
    final constraints = _lastConstraints;
    if (constraints == null) return false;
    final appProvider = context.read<AppProvider>();
    final layoutProvider = context.read<LayoutPreferencesProvider>();
    final projected = computeEffectiveLayout(
      totalWidth: constraints.maxWidth,
      sidebarWidth: layoutProvider.sidebarWidth,
      aiPanelWidth: layoutProvider.aiPanelWidth,
      ecWidth: appProvider.executionCenter.width,
      sidebarCollapsed: layoutProvider.sidebarCollapsed,
      aiOpen: appProvider.aiPanelOpen,
      aiFullscreen: false, // 用户想要的目标：docked
      ecOpen: appProvider.executionCenter.isOpen,
      ecPinned: appProvider.executionCenter.isPinned,
    );
    return projected.aiAsOverlay;
  }

  /// 切换 AI 全屏/浮层态；拥挤态从浮层切回 docked 时阻止 + 提示（plan §3.2）。
  void _toggleAiFullscreen() {
    final appProvider = context.read<AppProvider>();
    final targetFullscreen = !appProvider.aiPanelFullscreen;
    if (!targetFullscreen && _wouldAiBeForcedOverlay()) {
      _showInsufficientSpaceSnack();
      return;
    }
    appProvider.toggleAiPanelFullscreen();
  }

  void _showInsufficientSpaceSnack() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.layoutInsufficientSpace),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Dialogs
  // -------------------------------------------------------------------------
  void _showConnectionDialog() {
    context.showAnimatedDialog(builder: (ctx) => const ConnectionDialog());
  }

  void _showConnectionManager() {
    context.showAnimatedDialog(
      builder: (ctx) => const ConnectionManagerDialog(),
    );
  }

  // 零摩擦打开 SQLite 文件 —— 文件选择器取路径后交给 _connectSqlitePath
  Future<void> _openSqliteFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ConnectionProvider.sqliteFileExtensions,
    );
    final path = result?.files.single.path;
    if (path == null) return; // 用户取消选择
    await _connectSqlitePath(path);
  }

  /// 连接 SQLite 文件路径（按钮与拖拽共用）：openSqliteFile + 选中 / 失败对话框。
  Future<void> _connectSqlitePath(String path) async {
    final provider = context.read<AppProvider>();

    final success = await provider.connection.openSqliteFile(path);
    if (!mounted) return;

    if (success) {
      _selectSqliteConnection(provider, path);
    } else {
      _showSqliteConnectFailure(provider, path);
    }
  }

  /// 成功后定位刚保存/复用的连接，在侧边栏选中。
  void _selectSqliteConnection(AppProvider provider, String path) {
    final conn = ConnectionProvider.findExistingSqlite(
      provider.connection.savedConnections,
      ConnectionProvider.normalizeSqlitePath(path),
    );
    if (conn != null) {
      provider.sidebar.selectConnection(conn.id);
    }
  }

  /// 失败 → 结构化失败对话框（连接失败 UX 重构 T8，替代原固定文案 snackbar）。
  ///
  /// 重试复用同一条 openSqliteFile 路径（成功时顺带选中连接）；
  /// latestFailure 取 provider 最新结构化失败供对话框原地更新；
  /// 重新选择文件走 _openSqliteFile 自带的重入。
  void _showSqliteConnectFailure(AppProvider provider, String path) {
    final l10n = AppLocalizations.of(context)!;
    // errorMessage 兼容面（T3）会被 _onProviderChange 兜底成原始异常的通用
    // 错误弹窗，叠在本结构化对话框之上盖住重试动作——SQLite 打开失败路径
    // 的失败展示已由 ConnectFailureDialog 接管，清掉兼容面避免双重弹窗
    // （clearError 不影响 lastConnectFailure，结构化失败照常可用）。
    provider.clearError();
    final failure = provider.connection.lastConnectFailure;
    // T3 契约：lastConnectFailure 与失败结果同生共死；null 仅防御性兜底。
    unawaited(
      ConnectFailureDialog.show(
        context,
        failure: failure ??
            ConnectionFailure(
              kind: ConnectionFailureKind.unknown,
              errorCode: '',
              target: path,
              rawMessage: l10n.sqliteOpenError,
              occurredAt: DateTime.now(),
            ),
        onRetry: () async {
          final ok = await provider.connection.openSqliteFile(path);
          if (ok) {
            _selectSqliteConnection(provider, path);
          } else {
            // 重试失败同样由本对话框原地更新，压掉遗留通用弹窗兜底。
            provider.clearError();
          }
          return ok;
        },
        onChooseFile: _openSqliteFile,
        latestFailure: () => provider.connection.lastConnectFailure,
      ),
    );
  }

  // 拖拽打开 SQLite 文件 —— 取首个 SQLite 路径后连接
  Future<void> _handleFileDrop(DropDoneDetails detail) async {
    final path = ConnectionProvider.firstSqlitePath(
      detail.files.map((item) => item.path),
    );
    if (path == null) return; // 非 SQLite 文件，忽略
    await _connectSqlitePath(path);
  }

  void _showCommandPalette() {
    CommandPaletteDialog.show(context, commands: _buildCommands());
  }

  void _showERDiagramDialog() {
    final provider = context.read<AppProvider>();
    final currentTab = provider.activeTab;
    context.showAnimatedDialog(
      builder: (ctx) => ERDiagramDialog(
        initialConnectionId:
            currentTab?.connectionId ?? provider.sidebar.selectedConnectionId,
        initialDatabase:
            currentTab?.databaseName ?? provider.sidebar.selectedDatabaseName,
      ),
    );
  }

  void _showPerformanceDialog() {
    final provider = context.read<AppProvider>();
    final currentTab = provider.activeTab;
    context.showAnimatedDialog(
      builder: (ctx) => PerformanceAnalyzerDialog(
        initialConnectionId:
            currentTab?.connectionId ?? provider.sidebar.selectedConnectionId,
        initialDatabase:
            currentTab?.databaseName ?? provider.sidebar.selectedDatabaseName,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Command palette commands (使用单一数据源)
  // -------------------------------------------------------------------------
  List<Command> _buildCommands() {
    final l10n = AppLocalizations.of(context)!;

    return buildCommands(l10n, (
      onNewTab: () async => await context.read<AppProvider>().addNewTab(),
      onCloseTab: () async {
        final provider = context.read<AppProvider>();
        if (provider.activeTabIndex >= 0 && provider.tabs.isNotEmpty) {
          await provider.closeTab(provider.activeTabIndex);
        }
        return;
      },
      onExecuteQuery: () => _executeCurrentQuery(),
      onFormatSql: () => context.read<AppProvider>().formatCurrentSql(),
      onToggleAiPanel: () => context.read<AppProvider>().toggleAiPanel(),
      onToggleAiFullscreen: () {
        final provider = context.read<AppProvider>();
        if (!provider.aiPanelOpen) {
          provider.toggleAiPanel();
        }
        _toggleAiFullscreen();
        return;
      },
      onIncreaseOpacity: () {
        context.read<AppProvider>().increaseOverlayOpacity();
        return;
      },
      onDecreaseOpacity: () {
        context.read<AppProvider>().decreaseOverlayOpacity();
        return;
      },
      onShortcuts: () => ShortcutsDialog.show(context),
      onPerformanceAnalyzer: _showPerformanceDialog,
      onERDiagram: _showERDiagramDialog,
      onAuditLog: () => AuditLogDialog.show(context),
    ));
  }

  // 委托 QueryExecutionHelper（spec 040 Phase 2.1）——修原 DDL-only 分叉 bug
  //（原仅处理 DDL 确认、缺 DML 臂），现 DML/DDL/只读统一由 helper 编排。
  Future<void> _executeCurrentQuery() async {
    await QueryExecutionHelper.executeWithConfirm(context);
  }

  // -------------------------------------------------------------------------
  // Main build（薄壳：不 watch 任何 provider，布局态由 4 层自订阅；plan §3.1）
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // 薄壳（plan §3.1）：不 watch 任何 provider，布局态由 Stack 内 4 层各自订阅；
    // executionCenter 一次性 read 后在 Stack 外统一注入供 z0/z1 共享。
    final executionCenter = context.read<AppProvider>().executionCenter;

    return DropTarget(
      onDragDone: _handleFileDrop,
      child: Scaffold(
        body: GlobalShortcutsWrapper(
          child: ChangeNotifierProvider.value(
            value: executionCenter,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _lastConstraints =
                    constraints; // 供 shell 级 toggle 投影（plan §3.2）
                return Column(
                  children: [
                    // C22-1：AppHeader 整条下掉（品牌在侧栏 header、连接入口在
                    // 侧栏选择器、命令面板在面包屑栏、AI/主题/设置在侧栏
                    // footer、Server 状态在底部状态栏）——顶部垂直空间让给
                    // 工作区。
                    // Main content——4 层 Stack，z-order 由代码顺序决定（plan §3.1）：
                    //   z0 MainWorkspaceLayer / z1 ExecutionCenterOverlay /
                    //   z2 AiFullscreenOverlay / z3 AiMiniFabLayer
                    Expanded(
                      child: Stack(
                        children: [
                          MainWorkspaceLayer(
                            constraints: constraints,
                            onToggleSidebar: _toggleSidebar,
                            onShowConnectionDialog: _showConnectionDialog,
                            onShowConnectionManager: _showConnectionManager,
                            onOpenSqliteFile: _openSqliteFile,
                            onCommandPalette: _showCommandPalette,
                          ),
                          ExecutionCenterOverlay(constraints: constraints),
                          AiFullscreenOverlay(
                            constraints: constraints,
                            onToggleFullscreen: _toggleAiFullscreen,
                          ),
                          const AiMiniFabLayer(),
                        ],
                      ),
                    ),
                    Container(
                      height: 1,
                      color: context.themeColors.dividerColor,
                    ),
                    // Status bar
                    StatusBarWidget(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
