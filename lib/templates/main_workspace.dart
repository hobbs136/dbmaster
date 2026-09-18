// ============================================================================
// DbMaster Main Workspace - Tab bar + Editor/Results split
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../providers/layout_preferences_provider.dart';
import '../../theme/app_theme.dart';
import '../../atoms/app_widgets.dart';
import '../../organisms/connection/tabs_bar_widget.dart';
import '../../organisms/results/results_widget.dart';
import 'connecting_screen.dart';
import 'editor_results_split.dart';
import 'welcome_screen.dart';

class MainWorkspace extends StatefulWidget {
  final bool isResizingEditorResults;
  final VoidCallback onResizeEditorStart;
  final VoidCallback onResizeEditorEnd;
  final GlobalKey<ResultsWidgetState> resultsWidgetKey;
  final VoidCallback onNewConnection;
  final VoidCallback onOpenConnectionManager;
  // SQLite 文件打开回调（转发给 WelcomeScreen）
  final VoidCallback onOpenSqliteFile;
  // 命令面板入口（C22-1：AppHeader 下掉后迁入 BreadcrumbBar 右端）
  final VoidCallback onCommandPalette;

  const MainWorkspace({
    super.key,
    required this.isResizingEditorResults,
    required this.onResizeEditorStart,
    required this.onResizeEditorEnd,
    required this.resultsWidgetKey,
    required this.onNewConnection,
    required this.onOpenConnectionManager,
    required this.onOpenSqliteFile,
    required this.onCommandPalette,
  });

  @override
  State<MainWorkspace> createState() => _MainWorkspaceState();
}

class _MainWorkspaceState extends State<MainWorkspace> {
  @override
  Widget build(BuildContext context) {
    // 精确选择：仅连接状态变化时切换 AnimatedSwitcher 的 key
    // Tab / sidebar / results / AI 等变更不再触发整个工作区重建
    final switchKey = context.select<AppProvider, String>((p) {
      final hasConn = p.savedConnections.any(
        (s) => p.isConnectionConnected(s.id),
      );
      if (!hasConn) return 'welcome';
      if (p.connection.isConnecting) return 'connecting';
      return 'workspace';
    });

    Widget content;
    if (switchKey == 'welcome') {
      content = WelcomeScreen(
        onNewConnection: widget.onNewConnection,
        onOpenConnectionManager: widget.onOpenConnectionManager,
        onOpenSqliteFile: widget.onOpenSqliteFile,
      );
    } else if (switchKey == 'connecting') {
      content = const ConnectingScreen();
    } else {
      // context.read 不会触发重建，workspace 内部的 Tab/Editor/Results
      // 各自有自己的 Consumer/Selector 监听变化
      final provider = context.read<AppProvider>();
      content = _buildMainContent(context, provider);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(key: ValueKey(switchKey), child: content),
    );
  }

  Widget _buildMainContent(BuildContext context, AppProvider provider) {
    return Consumer<LayoutPreferencesProvider>(
      builder: (context, layoutProvider, _) {
        return Column(
          key: const ValueKey('main_workspace'),
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final hasTabs = provider.tabs.isNotEmpty;
                  // C21 M3：BreadcrumbBar 退役（连接/库显示并入工具栏右端上下文
                  // 芯片，消解双显；命令面板入口随迁）——tab 栏下直接接编辑区。
                  // tabBarDividerHeight：TabsBarWidget 底部分隔线像素预留（plan §3.6）
                  final fixedHeight =
                      AppDesignSystem.tabBarHeight +
                      AppDesignSystem.tabBarDividerHeight;
                  final availableHeight = (constraints.maxHeight - fixedHeight)
                      .clamp(100.0, double.infinity);
                  return Column(
                    children: [
                      TabsBarWidget(),
                      SizedBox(
                        height: availableHeight,
                        child: hasTabs
                            ? EditorResultsSplit(
                                provider: provider,
                                layoutProvider: layoutProvider,
                                isResizing: widget.isResizingEditorResults,
                                onResizeStart: widget.onResizeEditorStart,
                                onResizeEnd: widget.onResizeEditorEnd,
                                resultsWidgetKey: widget.resultsWidgetKey,
                                onCommandPalette: widget.onCommandPalette,
                              )
                            : _buildEmptyWorkspace(context, provider),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyWorkspace(BuildContext context, AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    if (provider.tab.activeTab != null) {
      return AppEmptyState(
        icon: LucideIcons.code,
        title: l10n.workspaceEmptyTitle,
        description: l10n.workspaceEmptyHint,
      );
    }
    return AppEmptyState(
      icon: LucideIcons.database,
      title: l10n.selectDatabase,
      description: l10n.selectDatabaseHint,
    );
  }
}
