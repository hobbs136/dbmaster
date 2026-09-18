import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'l10n/app_localizations.dart';
import 'plugins/bootstrap.dart';
import 'molecules/bulk_close_dialog.dart';
import 'providers/app_provider.dart';
import 'providers/tab_provider.dart' show QueryTab, TabProvider;
import 'utils/close_decision_applier.dart';
import 'providers/theme_provider.dart';
import 'providers/task_provider.dart';
import 'pro/pro_module_impl.dart';
import 'pro/ui/pro_import_ui_real.dart';
import 'pro/ui/pro_sync_ui_real.dart';
import 'services/pro_module.dart';
import 'services/embedded_server_service.dart';
import 'services/error_reporter.dart';
import 'services/server_connection.dart';
import 'services/telemetry_service.dart';
import 'theme/app_theme.dart';
import 'providers/locale_provider.dart';
import 'providers/layout_preferences_provider.dart';
import 'providers/server_connection_provider.dart';
import 'providers/health_check_provider.dart';
import 'providers/approval_provider.dart';
import 'providers/workspace_provider.dart';
import 'screens/home_screen.dart';
import 'organisms/connection/error_boundary.dart';
import 'organisms/pro/pro_import_ui.dart';
import 'organisms/pro/pro_purchase_ui.dart';
import 'organisms/pro/pro_sync_ui.dart';
import 'utils/app_logger.dart';

// 添加全局 NavigatorKey，用于 _WindowCloseGuard 在 MaterialApp 之上展示 Dialog
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 全局 AppProvider 引用，用于 VM Service 自动化测试
AppProvider? globalAppProvider;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // C08/C15 · UI 插件注册表创建即含默认件（bootstrap.dart），此处仅封口。
  // Pro fork 在 seal 前追加 registerProUiPlugins（spec 045 接缝）。
  defaultPluginRegistry.seal();

  // U14 日志落盘：尽早初始化，之后的启动日志（embedded/远程会话恢复等）全部
  // 进文件。失败非致命——退化为仅 developer.log，排障入口自动置灰。
  try {
    final support = await getApplicationSupportDirectory();
    await AppLogger.init(
      Directory('${support.path}${Platform.pathSeparator}logs'),
    );
  } catch (e, st) {
    AppLogger.e('main', 'Log file init failed (non-fatal)', e, st);
  }

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    center: true,
    minimumSize: Size(800, 600),
    title: 'DbMaster',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final proModule = ProModuleImpl();
  await proModule.initialize();

  // Initialize anonymous telemetry. Failure is non-fatal — the app continues
  // regardless; events are queued locally until the next successful flush.
  try {
    await TelemetryService.instance.init();
  } catch (e, st) {
    AppLogger.e('main', 'Telemetry init failed (non-fatal)', e, st);
  }

  // U12 模式持久化：用户显式登录过远程 server（preferred_mode == 'remote'）
  // 时，跳过 embedded 自动拉起、改为恢复远程会话——否则打包版每次启动都
  // 无条件进 embedded，远程用户的会话永远恢复不了。无偏好（首次运行）保持
  // embedded-first 默认。远程登出会清掉偏好，下次启动回默认。
  //
  // start the embedded server child process. If a
  // server binary is found beside the app (or via DBMASTER_SERVER_BIN), the
  // app runs in embedded/local mode and all API services route to 127.0.0.1.
  // If the binary isn't found, start() returns binaryNotFound and the app
  // falls back to the existing remote-server connect flow (zero regression).
  // Failure is non-fatal: a failed spawn leaves ServerConnection disconnected,
  // which the user can recover via the remote connect dialog.
  try {
    final preferRemote =
        await ServerConnection().readPreferredMode() == 'remote';
    if (!preferRemote) {
      final result = await EmbeddedServerService.instance.start();
      if (result == EmbeddedStartResult.started) {
        EmbeddedServerService.instance.applyTo(ServerConnection());
      }
    } else {
      AppLogger.i('main',
          'Remote server preferred; skipping embedded auto-start, restoring session');
      // Best-effort restore; failures leave the app disconnected with the
      // connect dialog (prefilled) as the recovery path.
      final restored = await ServerConnection().restoreSession();
      if (!restored) {
        AppLogger.i('main', 'Remote session restore failed; disconnected');
      }
    }
  } catch (e, st) {
    AppLogger.e('main', 'Embedded server start failed (non-fatal)', e, st);
  }

  // U16：runZonedGuarded 兜住 widget 树之外的异步错误（main 区 / 裸 Future /
  // Timer 回调）——ErrorBoundary 只覆盖 FlutterError + PlatformDispatcher。
  // report 会脱敏（FR-011）并经 AppLogger 落盘（U14）；不上 UI（zone 错误
  // 无可靠的重建上下文）。
  runZonedGuarded(
    () {
      runApp(
        DbmasterApp(
          proModule: proModule,
          proSyncUi: const RealProSyncUi(),
          proImportUi: const RealProImportUi(),
        ),
      );
    },
    (error, stackTrace) {
      ErrorReporter.instance
          .report(error, stackTrace: stackTrace, tag: 'Zone');
    },
  );
}

class DbmasterApp extends StatelessWidget {
  DbmasterApp({
    super.key,
    required this.proModule,
    this.proPurchaseUi = const NoOpProPurchaseUi(),
    this.proSyncUi = const NoOpProSyncUi(),
    this.proImportUi = const NoOpProImportUi(),
  });

  /// Pro 能力模块——注入 [ProModuleImpl]（全免费，isPro 恒 true）。
  final ProModule proModule;

  /// Pro 购买/升级 UI 注入点——全免费客户端无需购买 UI，保留 NoOp。
  final ProPurchaseUi proPurchaseUi;

  /// 数据同步对话框注入点——注入 [RealProSyncUi]。
  final ProSyncUi proSyncUi;

  /// 智能导入向导注入点——注入 [RealProImportUi]。
  final ProImportUi proImportUi;

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      child: MultiProvider(
        providers: [
          Provider<ProPurchaseUi>.value(value: proPurchaseUi),
          Provider<ProSyncUi>.value(value: proSyncUi),
          Provider<ProImportUi>.value(value: proImportUi),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          ChangeNotifierProvider(create: (_) => ServerConnectionProvider()),
          ChangeNotifierProvider(create: (_) => HealthCheckProvider()),
          ChangeNotifierProvider(create: (_) => ApprovalProvider()),
          ChangeNotifierProvider(create: (_) => WorkspaceProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
          ChangeNotifierProvider(
            create: (_) => LayoutPreferencesProvider()..load(),
          ),
          ChangeNotifierProxyProvider<TaskProvider, AppProvider>(
            create: (_) => AppProvider(proModule: proModule),
            update: (_, taskProvider, appProvider) {
              if (appProvider == null) {
                return AppProvider(
                  proModule: proModule,
                  taskProvider: taskProvider,
                );
              }
              appProvider.updateTaskProvider(taskProvider);
              taskProvider.setDatabaseService(appProvider.connection.dbService);
              return appProvider;
            },
          ),
        ],
        child: const _WindowCloseGuard(
          child: _DbmasterAppContent(),
        ),
      ),
    );
  }
}

class _DbmasterAppContent extends StatelessWidget {
  const _DbmasterAppContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return MaterialApp(
              title: 'DbMaster',
              debugShowCheckedModeBanner: false,
              // plan §2.3：亮/暗底用不同明度的 accent 变体
              theme: AppTheme.light(themeProvider.accentColorLight),
              darkTheme: AppTheme.dark(themeProvider.accentColorDark),
              themeMode: switch (themeProvider.themeMode) {
                AppThemeMode.light => ThemeMode.light,
                AppThemeMode.dark => ThemeMode.dark,
                AppThemeMode.system => ThemeMode.system,
              },
              locale: localeProvider.locale,
              // 绑定全局 NavigatorKey，让 _WindowCloseGuard 能使用有效的导航上下文
              navigatorKey: appNavigatorKey,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const HomeScreen(),
            );
          },
        );
      },
    );
  }
}

/// 拦截桌面窗口关闭事件，在存在未保存查询标签页时显示批量确认对话框。
class _WindowCloseGuard extends StatefulWidget {
  final Widget child;

  const _WindowCloseGuard({required this.child});

  @override
  State<_WindowCloseGuard> createState() => _WindowCloseGuardState();
}

class _WindowCloseGuardState extends State<_WindowCloseGuard>
    with WindowListener {
  bool _closing = false;
  bool _showingDialog = false;

  @override
  void initState() {
    super.initState();
    windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_closing || _showingDialog) return;

    // 防御性检查：State 未挂载或 Navigator 未就绪时直接返回，避免 null 异常
    if (!mounted) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      AppLogger.w(
        'WindowCloseGuard',
        '窗口关闭时 Navigator 尚未就绪，暂不关闭窗口',
      );
      return;
    }

    final appProvider = context.read<AppProvider>();
    final unsavedTabs = _collectUnsavedTabs(appProvider);

    if (unsavedTabs.isEmpty) {
      await _doClose();
      return;
    }

    _showingDialog = true;
    // 使用全局 NavigatorKey 的上下文展示 Dialog，避免使用 _WindowCloseGuard 自身的 context
    final result = await showBulkCloseDialog(
      navigator.context,
      tabs: unsavedTabs,
    );
    _showingDialog = false;

    // 使用 navigator.context.mounted 检查对话框关闭后上下文是否仍然有效
    if (!navigator.context.mounted) return;

    if (!result.confirmed) return;

    final allSaved = await CloseDecisionApplier.applyDecisions(
      tabs: List.unmodifiable(appProvider.tabs),
      saveTab: appProvider.saveQuery,
      closeTabAtIndex: appProvider.forceCloseTab,
      result: result,
    );
    if (!mounted) return;

    // 若有 Tab 保存失败，保持窗口打开以便用户处理。
    if (!allSaved) {
      return;
    }

    await _doClose();
  }

  List<QueryTab> _collectUnsavedTabs(AppProvider provider) {
    return provider.tabs.where(TabProvider.isTabUnsaved).toList();
  }


  Future<void> _doClose() async {
    _closing = true;
    // 在首个 await 之前捕获——后面 prepareForCleanExit 要用（跨 await 的
    // context 访问是 analyzer 违例）。
    final appProvider = context.read<AppProvider>();
    // tear down the embedded server child process
    // (closes its stdin → server's EOF shutdown path). Best-effort: never
    // block window close on child teardown.
    try {
      await EmbeddedServerService.instance.stop();
    } catch (e, stack) {
      AppLogger.e('WindowCloseGuard', 'Embedded server stop failed', e, stack);
    }
    // U16：clean 退出标记 + 清空崩溃恢复会话文件（用户在批量关闭确认里
    // 「丢弃」的决定必须被尊重——只有异常退出才恢复标签页）。
    try {
      await appProvider.prepareForCleanExit();
    } catch (e, stack) {
      AppLogger.e('WindowCloseGuard', 'Clean-exit mark failed', e, stack);
    }
    // 冲刷并关闭日志文件（含子进程退出前的 stderr 尾巴），尽力而为。
    await AppLogger.dispose();
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (e, stack) {
      AppLogger.e('WindowCloseGuard', '关闭窗口失败', e, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
