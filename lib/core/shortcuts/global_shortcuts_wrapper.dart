// ============================================================================
import '../../utils/app_logger.dart';
// Global Shortcuts Wrapper - 应用级全局快捷键包装器
// 使用 HardwareKeyboard 监听器，不依赖焦点树，确保快捷键始终可用
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../organisms/connection/quick_search_dialog.dart';
import '../../organisms/dialogs/shortcuts_dialog.dart';
import '../../organisms/connection/command_palette.dart';
import '../../organisms/dialogs/performance_analyzer_dialog.dart';
import '../../organisms/dialogs/audit_log_dialog.dart';
import '../../organisms/connection/er_diagram_dialog.dart';
// SettingsDialog（Ctrl+, 接线）
import '../../organisms/connection/settings_dialog.dart';
import '../../atoms/app_transitions.dart';
import '../../core/commands/app_commands.dart';
// 查询执行编排单一真相源（spec 040 Phase 2.1）
import '../../core/commands/query_execution_helper.dart';
// 编辑器焦点跟踪（spec 040 Phase 2.2）
import 'editor_focus_state.dart';
import '../../models/database_models.dart' show DbServer;
import '../../providers/tab_provider.dart'
    show DuplicateSavedQueryNameException, QueryTab;
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';

/// 全局快捷键包装器
/// 使用 HardwareKeyboard 添加全局监听器，不依赖 Flutter 焦点树
class GlobalShortcutsWrapper extends StatefulWidget {
  final Widget child;

  const GlobalShortcutsWrapper({super.key, required this.child});

  @override
  State<GlobalShortcutsWrapper> createState() => _GlobalShortcutsWrapperState();
}

class _GlobalShortcutsWrapperState extends State<GlobalShortcutsWrapper> {
  // 命令面板显示状态
  bool _isCommandPaletteVisible = false;

  // 快速搜索显示状态（防止键重复/连按导致弹窗叠堆）
  bool _isQuickSearchVisible = false;

  // 用于安全执行 UI 操作
  final List<VoidCallback> _pendingActions = [];
  bool _isProcessingPending = false;

  @override
  void initState() {
    super.initState();
    // 添加全局键盘事件监听器
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    // 移除全局键盘事件监听器
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _pendingActions.clear();
    super.dispose();
  }

  /// 安全地执行 UI 操作（推迟到下一帧）
  void _safeExecute(VoidCallback action) {
    if (!mounted) return;

    _pendingActions.add(action);

    if (!_isProcessingPending) {
      _isProcessingPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _pendingActions.clear();
          _isProcessingPending = false;
          return;
        }

        // 复制列表以避免并发修改
        final actions = List<VoidCallback>.from(_pendingActions);
        _pendingActions.clear();

        for (final action in actions) {
          try {
            action();
          } catch (e) {
            // 静默处理单个操作失败，避免影响其他操作
            AppLogger.d(
              'ShortcutWrapper',
              'GlobalShortcutsWrapper: Action failed: $e',
            );
          }
        }

        _isProcessingPending = false;
      });
    }
  }

  /// 处理键盘事件
  bool _handleKeyEvent(KeyEvent event) {
    // 只在 KeyDown 事件时处理
    if (event is! KeyDownEvent) return false;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final isControlPressed =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    final isShiftPressed =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final isMetaPressed =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);

    // 使用 Control (Windows/Linux) 或 Meta (macOS)
    final isModifierPressed = isControlPressed || isMetaPressed;

    // 如果当前有对话框或菜单打开，跳过某些快捷键（避免冲突）
    if (_isDialogOpen()) {
      // Escape 始终让系统处理（关闭对话框）
      return false;
    }

    // 编辑器获焦时，F5/Ctrl+S/Ctrl+Shift+F 让位给编辑器焦点链（避免双触发；
    // 全局 HardwareKeyboard 与编辑器 onKeyEvent 是两条独立管线）。仅无编辑器获焦时全局
    // 兜底。其它键（Ctrl+T/W/Tab 等）不受影响。（spec 040 Phase 2.2）
    if (isSqlEditorFocused) {
      final lk = event.logicalKey;
      final isEditorOwnedKey = lk == LogicalKeyboardKey.f5 ||
          (isModifierPressed && !isShiftPressed && lk == LogicalKeyboardKey.keyS) ||
          (isModifierPressed && isShiftPressed && lk == LogicalKeyboardKey.keyF);
      if (isEditorOwnedKey) return false;
    }

    // Ctrl+T: 新建标签页
    if (isModifierPressed &&
        !isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyT) {
      _safeExecute(_handleNewTab);
      return true;
    }

    // Ctrl+W: 关闭标签页
    if (isModifierPressed &&
        !isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      _safeExecute(_handleCloseTab);
      return true;
    }

    // Ctrl+Tab: 下一个标签页
    if (isModifierPressed &&
        !isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.tab) {
      _safeExecute(_handleNextTab);
      return true;
    }

    // Ctrl+Shift+Tab: 上一个标签页
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.tab) {
      _safeExecute(_handlePrevTab);
      return true;
    }

    // Ctrl+Shift+A: 切换 AI 面板
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyA) {
      _safeExecute(_handleToggleAi);
      return true;
    }

    // Ctrl+Shift+P: 显示命令面板
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyP) {
      _safeExecute(_handleShowCommandPalette);
      return true;
    }

    // Ctrl+K / ⌘K: 显示快速搜索（数据库实体搜索）
    if (isModifierPressed &&
        !isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      _safeExecute(_handleShowQuickSearch);
      return true;
    }

    // 移除 Ctrl+N 冗余别名（与 Ctrl+K 同一 handler；Ctrl+N 语义=「新建」违反
    // 惯例，且带 Windows focus/IME 卡死历史）。QuickSearch 仅由 Ctrl+K 触发（spec 040 T011）。

    // Ctrl+/: 显示快捷键帮助
    if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.slash) {
      _safeExecute(_handleShowShortcuts);
      return true;
    }

    // Ctrl+S: 保存/导出
    if (isModifierPressed &&
        !isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyS) {
      _safeExecute(_handleSaveExport);
      return true;
    }

    // Ctrl++ 或 Ctrl+=: 增加 AI 浮层透明度
    if (isModifierPressed &&
        !isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.add ||
            event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
      _safeExecute(_handleIncreaseOpacity);
      return true;
    }

    // Ctrl+- 或 Ctrl+_: 降低 AI 浮层透明度
    if (isModifierPressed &&
        !isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      _safeExecute(_handleDecreaseOpacity);
      return true;
    }

    // Ctrl+Shift+F: 格式化SQL
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyF) {
      _safeExecute(_handleFormatSql);
      return true;
    }

    // Ctrl+Shift+G: AI面板全屏
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyG) {
      _safeExecute(_handleToggleAiFullscreen);
      return true;
    }

    // Ctrl+Shift+L: 打开审计日志
    if (isModifierPressed &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyL) {
      _safeExecute(_handleAuditLog);
      return true;
    }

    // Ctrl+,: 打开设置
    if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.comma) {
      _safeExecute(_handleOpenSettings);
      return true;
    }

    // F5: 执行当前查询
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      _safeExecute(_handleExecuteQuery);
      return true;
    }

    return false; // 未处理，让其他处理器处理
  }

  /// 检查是否有对话框或菜单打开
  bool _isDialogOpen() {
    try {
      final navigator = Navigator.maybeOf(context);
      if (navigator != null) {
        return ModalRoute.of(context)?.isCurrent == false;
      }
    } catch (e) {
      // context 可能暂时不可用
    }
    return false;
  }

  // --------------------------------------------------------------------------
  // 快捷键处理函数
  // --------------------------------------------------------------------------

  Future<void> _handleNewTab() async {
    try {
      final provider = context.read<AppProvider>();
      await provider.addNewTab();
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleNewTab failed: $e',
      );
    }
  }

  Future<void> _handleCloseTab() async {
    try {
      final provider = context.read<AppProvider>();
      if (provider.activeTabIndex >= 0 && provider.tabs.isNotEmpty) {
        await provider.closeTab(provider.activeTabIndex);
      }
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleCloseTab failed: $e',
      );
    }
  }

  void _handleNextTab() {
    try {
      final provider = context.read<AppProvider>();
      final tabs = provider.tabs;
      if (tabs.isNotEmpty) {
        provider.setActiveTab((provider.activeTabIndex + 1) % tabs.length);
      }
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleNextTab failed: $e',
      );
    }
  }

  void _handlePrevTab() {
    try {
      final provider = context.read<AppProvider>();
      final tabs = provider.tabs;
      if (tabs.isNotEmpty) {
        provider.setActiveTab(
          (provider.activeTabIndex - 1 + tabs.length) % tabs.length,
        );
      }
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handlePrevTab failed: $e',
      );
    }
  }

  void _handleToggleAi() {
    try {
      context.read<AppProvider>().toggleAiPanel();
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleToggleAi failed: $e',
      );
    }
  }

  void _handleShowCommandPalette() {
    if (_isCommandPaletteVisible) return;

    try {
      _isCommandPaletteVisible = true;
      final commands = _buildCommands();

      CommandPaletteDialog.show(context, commands: commands).whenComplete(() {
        if (mounted) {
          _isCommandPaletteVisible = false;
        }
      });
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleShowCommandPalette failed: $e',
      );
      _isCommandPaletteVisible = false;
    }
  }

  void _handleShowQuickSearch() {
    if (_isQuickSearchVisible) return;

    try {
      _isQuickSearchVisible = true;
      QuickSearchDialog.show(context).whenComplete(() {
        if (mounted) {
          _isQuickSearchVisible = false;
        }
      });
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleShowQuickSearch failed: $e',
      );
      _isQuickSearchVisible = false;
    }
  }

  void _handleShowShortcuts() {
    try {
      ShortcutsDialog.show(context);
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleShowShortcuts failed: $e',
      );
    }
  }

  Future<void> _handleSaveExport() async {
    try {
      // 焦点在编辑器内时，Ctrl+S 会被本全局 HardwareKeyboard 处理器（focus-tree 无关）
      // 与编辑器自身的 onKeyEvent（focus chain）同时捕获。编辑器已在本次按键中弹出命名
      // 对话框（route 已 push）；本方法经 _safeExecute 延迟到下一帧才执行，此时若检测到
      // 已有对话框打开则直接退出，避免叠堆第二个命名对话框——否则点「保存」只关掉栈顶那
      // 一个，底层对话框仍在，表现为「命名输入框未消失」。编辑器读的是实时 _controller.text，
      // 由它胜出也保证了保存内容不滞后（tab.sql 经 200ms 防抖）。
      if (_isDialogOpen()) return;
      final provider = context.read<AppProvider>();
      final tab = provider.activeTab;
      if (tab == null) return;

      final sql = tab.sql.trim();
      if (sql.isEmpty) {
        _notifySaveBlocked(l10nSaveEmpty(context));
        return;
      }

      final connectionId =
          tab.connectionId ?? provider.connection.currentServer?.id;
      if (connectionId == null || connectionId.isEmpty) {
        _notifySaveBlocked(l10nSaveNoConnection(context));
        return;
      }

      final server = provider.connection.savedConnections.firstWhere(
        (s) => s.id == connectionId,
        orElse: () =>
            provider.connection.currentServer ??
            DbServer(id: '', name: '', host: '', port: 0),
      );
      if (server.readOnly) {
        _notifySaveBlocked(l10nSaveReadOnly(context));
        return;
      }

      final isUpdate = tab.savedQueryId != null;
      var title = tab.title;

      if (!isUpdate) {
        final suggestedTitle = _generateSavedQueryName(sql);
        final confirmedTitle = await _showSaveQueryNamingDialog(suggestedTitle);
        if (confirmedTitle == null || confirmedTitle.isEmpty) return;
        title = confirmedTitle;
      }

      final savedTab = QueryTab(
        id: tab.id,
        savedQueryId: tab.savedQueryId,
        title: title,
        sql: sql,
        isSaved: true,
        connectionId: connectionId,
        databaseName: tab.databaseName,
        databaseType: tab.databaseType ?? server.type,
      );

      final success = await provider.saveQuery(savedTab);
      if (success && mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.querySaved(title)),
            backgroundColor: context.themeColors.success,
          ),
        );
      } else if (!success && mounted) {
        // saveQuery 返回 false 的现实原因只有达上限（空标题已由对话框禁用、
        // 重名走异常分支）——U17 前此处静默。
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.saveQueryLimitReached),
            backgroundColor: context.themeColors.warning,
          ),
        );
      }
    } on DuplicateSavedQueryNameException catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.savedQueryNameExists(e.title)),
            backgroundColor: context.themeColors.warning,
          ),
        );
      }
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleSaveExport failed: $e',
      );
      if (mounted) {
        _notifySaveBlocked(l10nSaveFailed(context, e));
      }
    }
  }

  // ── U17：Ctrl+S 静默失败补提示（此前无连接/只读/空 SQL/未知异常直接 return）──

  void _notifySaveBlocked(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String l10nSaveEmpty(BuildContext ctx) =>
      AppLocalizations.of(ctx)!.queryEmptyCannotSave;

  String l10nSaveNoConnection(BuildContext ctx) =>
      AppLocalizations.of(ctx)!.saveQueryNoConnection;

  String l10nSaveReadOnly(BuildContext ctx) =>
      AppLocalizations.of(ctx)!.saveQueryReadOnly;

  String l10nSaveFailed(BuildContext ctx, Object error) =>
      AppLocalizations.of(ctx)!.saveQueryFailed(error.toString());

  Future<String?> _showSaveQueryNamingDialog(String initialTitle) async {
    final controller = TextEditingController(text: initialTitle);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final dialogL10n = AppLocalizations.of(dialogCtx)!;
        return AlertDialog(
          backgroundColor: dialogCtx.themeColors.bgSecondary,
          title: Text(
            dialogL10n.saveQueryTitle,
            style: TextStyle(color: dialogCtx.themeColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: TextStyle(color: dialogCtx.themeColors.textPrimary),
                decoration: InputDecoration(
                  labelText: dialogL10n.queryName,
                  labelStyle: TextStyle(
                    color: dialogCtx.themeColors.textSecondary,
                  ),
                  hintText: dialogL10n.enterQueryName,
                  hintStyle: TextStyle(color: dialogCtx.themeColors.textMuted),
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppDesignSystem.space3),
              Text(
                dialogL10n.saveQueryHint,
                style: TextStyle(
                  color: dialogCtx.themeColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(dialogL10n.commonCancel),
            ),
            // U17：空标题时禁用保存——此前空文本点「保存」对话框直接关闭、
            // 保存静默中止，表现为「Ctrl+S 没反应」。
            ListenableBuilder(
              listenable: controller,
              builder: (ctx, _) {
                final canSave = controller.text.trim().isNotEmpty;
                return ElevatedButton(
                  onPressed:
                      canSave ? () => Navigator.pop(dialogCtx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.themeColors.accentBlue,
                  ),
                  child: Text(dialogL10n.commonSave),
                );
              },
            ),
          ],
        );
      },
    );

    final text = controller.text.trim();
    // Dispose after the current frame to avoid accessing the controller while
    // the dialog's TextField is still being unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (result == true && text.isNotEmpty) {
      return text;
    }
    return null;
  }

  String _generateSavedQueryName(String sql) {
    final firstLine = sql
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();
    if (firstLine.isNotEmpty) {
      return firstLine.length > 40
          ? '${firstLine.substring(0, 40)}...'
          : firstLine;
    }
    return 'Saved Query';
  }

  void _handleIncreaseOpacity() {
    try {
      final provider = context.read<AppProvider>();
      provider.increaseOverlayOpacity();
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleIncreaseOpacity failed: $e',
      );
    }
  }

  void _handleDecreaseOpacity() {
    try {
      final provider = context.read<AppProvider>();
      provider.decreaseOverlayOpacity();
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleDecreaseOpacity failed: $e',
      );
    }
  }

  // 接线 Ctrl+, 打开设置（原为空 TODO）。复用 home_screen._showSettingsDialog 同一入口。
  void _handleOpenSettings() {
    context.showAnimatedDialog(builder: (ctx) => const SettingsDialog());
  }

  // 委托 QueryExecutionHelper（spec 040 Phase 2.1）——DML/DDL/只读编排单一真相源。
  Future<void> _handleExecuteQuery() =>
      QueryExecutionHelper.executeWithConfirm(context);

  void _handleFormatSql() {
    try {
      context.read<AppProvider>().formatCurrentSql();
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleFormatSql failed: $e',
      );
    }
  }

  void _handleToggleAiFullscreen() {
    try {
      final provider = context.read<AppProvider>();
      if (!provider.aiPanelOpen) {
        provider.toggleAiPanel();
      }
      provider.toggleAiPanelFullscreen();
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleToggleAiFullscreen failed: $e',
      );
    }
  }

  void _handlePerformanceAnalyzer() {
    try {
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
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handlePerformanceAnalyzer failed: $e',
      );
    }
  }

  void _handleERDiagram() {
    try {
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
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleERDiagram failed: $e',
      );
    }
  }

  void _handleAuditLog() {
    try {
      context.showAnimatedDialog(builder: (ctx) => const AuditLogDialog());
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _handleAuditLog failed: $e',
      );
    }
  }

  // --------------------------------------------------------------------------
  // 命令列表（使用单一数据源）
  // --------------------------------------------------------------------------

  List<Command> _buildCommands() {
    try {
      final l10n = AppLocalizations.of(context);
      if (l10n == null) return [];

      return buildCommands(l10n, (
        onNewTab: () => _safeExecute(_handleNewTab),
        onCloseTab: () => _safeExecute(_handleCloseTab),
        onExecuteQuery: () => _safeExecute(_handleExecuteQuery),
        onFormatSql: () => _safeExecute(_handleFormatSql),
        onToggleAiPanel: () => _safeExecute(_handleToggleAi),
        onToggleAiFullscreen: () => _safeExecute(_handleToggleAiFullscreen),
        onIncreaseOpacity: () => _safeExecute(_handleIncreaseOpacity),
        onDecreaseOpacity: () => _safeExecute(_handleDecreaseOpacity),
        onShortcuts: () => _safeExecute(_handleShowShortcuts),
        onPerformanceAnalyzer: () => _safeExecute(_handlePerformanceAnalyzer),
        onERDiagram: () => _safeExecute(_handleERDiagram),
        onAuditLog: () => _safeExecute(_handleAuditLog),
      ));
    } catch (e) {
      AppLogger.d(
        'ShortcutWrapper',
        'GlobalShortcutsWrapper: _buildCommands failed: $e',
      );
      return [];
    }
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
