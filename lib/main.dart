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
import 'services/app_lifecycle_observer.dart';
import 'services/app_shutdown_coordinator.dart';
import 'services/embedded_server_service.dart';
import 'services/error_reporter.dart';
import 'services/server_connection.dart';
import 'services/telemetry_service.dart';
import 'services/workbench_usage_stats_service.dart';
import 'screens/boot/boot_shell.dart';
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
import 'utils/secret_redactor.dart';

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

  // UIRV-B4：runApp 提前——窗口显示后的首帧即 BootShell（品牌 + 阶段状态 +
  // 结构骨架），消除「先 show 后串行初始化」造成的纯白帧。原 runApp 前的
  // 启动初始化序列（日志落盘 / Pro 模块 / 遥测 / embedded server / 远程会话
  // 恢复）整体移入 [_BootRoot] 的可重跑序列，完成后无缝换壳为 DbmasterApp。
  // U16：runZonedGuarded 兜住 widget 树之外的异步错误（main 区 / 裸 Future /
  // Timer 回调）——ErrorBoundary 只覆盖 FlutterError + PlatformDispatcher。
  // report 会脱敏（FR-011）并经 AppLogger 落盘（U14）；不上 UI（zone 错误
  // 无可靠的重建上下文）。
  final proModule = ProModuleImpl();
  runZonedGuarded(
    () {
      runApp(_BootRoot(proModule: proModule));
    },
    (error, stackTrace) {
      ErrorReporter.instance.report(error, stackTrace: stackTrace, tag: 'Zone');
    },
  );
}

/// 启动宿主（UIRV-B4）：先渲染 BootShell，后台跑初始化序列；序列完成换壳
/// DbmasterApp，意外失败在同一容器内切结构化错误卡（重试 = 重跑序列），
/// 不回到白屏。
///
/// 不变量保持：Provider 创建顺序在 DbmasterApp build 内不变；`globalAppProvider`
/// 语义不变；runZonedGuarded 包裹 runApp；`_WindowCloseGuard` / ErrorBoundary
/// 层级不动。
class _BootRoot extends StatefulWidget {
  const _BootRoot({required this.proModule});

  final ProModule proModule;

  @override
  State<_BootRoot> createState() => _BootRootState();
}

enum _BootPhase { booting, ready, error }

class _BootRootState extends State<_BootRoot> {
  _BootPhase _phase = _BootPhase.booting;
  BootStage _stage = BootStage.generic;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _runBootSequence();
  }

  /// 重跑完整初始化序列（首启与错误卡「重试」共用；幂等面由各服务自身保证）。
  Future<void> _runBootSequence() async {
    if (!mounted) return;
    setState(() {
      _phase = _BootPhase.booting;
      _errorDetail = null;
      _stage = BootStage.generic;
    });
    try {
      await _initializeApp();
      if (!mounted) return;
      setState(() => _phase = _BootPhase.ready);
    } catch (e, st) {
      // 防御性包装：序列内已各自 try/catch 的非致命失败不会走到这里；
      // 到这里的意外异常 → BootShell 错误卡（不回白屏）。
      AppLogger.e('boot', 'Startup initialization failed', e, st);
      if (!mounted) return;
      setState(() {
        _phase = _BootPhase.error;
        // security P3：错误卡详情先脱敏再展示（防异常文本携带凭据上 UI）。
        _errorDetail = redactSecrets(e.toString());
      });
    }
  }

  void _setStage(BootStage stage) {
    if (!mounted) return;
    setState(() => _stage = stage);
  }

  /// 原 main() 中 runApp 前的串行初始化序列，顺序与失败语义保持不变：
  /// 单步自带 try/catch 的失败仍记日志继续（非致命）；无内部捕获的步骤
  /// （Pro 模块）抛出时由 [_runBootSequence] 的防御包装转错误卡。
  Future<void> _initializeApp() async {
    // U14 日志落盘：之后的启动日志（embedded/远程会话恢复等）全部进文件。
    // 失败非致命——退化为仅 developer.log，排障入口自动置灰。
    _setStage(BootStage.logger);
    try {
      final support = await getApplicationSupportDirectory();
      await AppLogger.init(
        Directory('${support.path}${Platform.pathSeparator}logs'),
      );
    } catch (e, st) {
      AppLogger.e('main', 'Log file init failed (non-fatal)', e, st);
    }

    // Pro 能力模块（全免费，isPro 恒 true）。
    _setStage(BootStage.extensions);
    await widget.proModule.initialize();

    // Initialize anonymous telemetry. Failure is non-fatal — the app continues
    // regardless; events are queued locally until the next successful flush.
    _setStage(BootStage.telemetry);
    try {
      await TelemetryService.instance.init();
    } catch (e, st) {
      AppLogger.e('main', 'Telemetry init failed (non-fatal)', e, st);
    }

    // AI 工作台本地使用统计：启动读盘 + 滚动裁剪（design-ai-workbench §7.7）。
    // fire-and-forget：load 内部吞错永不抛出，失败非致命，不阻塞启动序列，
    // 不影响 Provider 初始化顺序纪律（Provider 在 DbmasterApp 的 build 内创建）。
    unawaited(WorkbenchUsageStatsService.instance.load());

    // U12 模式持久化：用户显式登录过远程 server（preferred_mode == 'remote'）
    // 时，跳过 embedded 自动拉起、改为恢复远程会话——否则打包版每次启动都
    // 无条件进 embedded，远程用户的会话永远恢复不了。无偏好（首次运行）保持
    // embedded-first 默认。远程登出会清掉偏好，下次启动回默认。
    //
    // Start the embedded server child process. If a server binary is found
    // beside the app (or via DBMASTER_SERVER_BIN), the app runs in embedded
    // local mode and all API services route to 127.0.0.1. If the binary isn't
    // found, start() returns binaryNotFound and the app falls back to the
    // existing remote-server connect flow (zero regression). Failure is
    // non-fatal: a failed spawn leaves ServerConnection disconnected, which
    // the user can recover via the remote connect dialog.
    try {
      final preferRemote =
          await ServerConnection().readPreferredMode() == 'remote';
      if (!preferRemote) {
        _setStage(BootStage.server);
        final result = await EmbeddedServerService.instance.start();
        if (result == EmbeddedStartResult.started) {
          EmbeddedServerService.instance.applyTo(ServerConnection());
        }
      } else {
        AppLogger.i(
          'main',
          'Remote server preferred; skipping embedded auto-start, restoring session',
        );
        _setStage(BootStage.session);
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
  }

  @override
  Widget build(BuildContext context) {
    // UIRV-B4 T4b：换壳带 150ms opacity 渐隐（BootShell ↔ 真实工作区交叉
    // 渐隐），`MediaQuery.disableAnimations` 时 0ms 直切（reduced-motion）。
    // 状态机语义不变：booting/error 仍渲染启动壳（error 为错误卡），ready
    // 渲染 DbmasterApp；error phase 的重试路径（重新 _runBootSequence）会
    // 经历一次 0→150ms 的回切渐入，与首启一致。
    if (_phase == _BootPhase.ready) {
      return BootShellCrossFade(
        ready: true,
        bootChild: BootShellHost(
          stage: _stage,
          errorDetail: _errorDetail,
          onRetry: _runBootSequence,
        ),
        appChild: DbmasterApp(
          proModule: widget.proModule,
          proSyncUi: const RealProSyncUi(),
          proImportUi: const RealProImportUi(),
        ),
      );
    }
    // UIRV-B4 返工：启动壳 MaterialApp 配置（l10n delegates/supportedLocales/
    // 亮暗主题）收敛到 BootShellHost 单一事实源（boot_shell.dart），与本批
    // UI-B4-107 回归锁同源——漏配 delegates 时测试与生产同红。
    return BootShellCrossFade(
      ready: false,
      bootChild: BootShellHost(
        stage: _stage,
        errorDetail: _errorDetail,
        onRetry: _runBootSequence,
      ),
      appChild: DbmasterApp(
        proModule: widget.proModule,
        proSyncUi: const RealProSyncUi(),
        proImportUi: const RealProImportUi(),
      ),
    );
  }
}

/// 换壳渐隐包装件（UIRV-B4 T4b，可测公开件——单测受限导入，见
/// test/screens/boot/boot_shell_crossfade_test.dart 头注）。
///
/// 用 [AnimatedSwitcher] 承载 BootShellHost ↔ DbmasterApp 的 150ms opacity
/// 交叉渐隐；`MediaQuery.disableAnimations` 时 duration 取 0（无中间帧）。
/// 过渡期间两个子树（各含一个 MaterialApp）短暂并存于 AnimatedSwitcher 的
/// Stack 布局中：appNavigatorKey 仅挂在 DbmasterApp 侧且此刻 BootShellHost
/// 不持有任何 GlobalKey，无键冲突；过渡结束旧子树即被移除。
/// BootShellHost 单源宿主规则不变：delegates/supportedLocales/主题仍只在
/// boot_shell.dart 内配置，本件不新增配置源。
class BootShellCrossFade extends StatelessWidget {
  const BootShellCrossFade({
    super.key,
    required this.ready,
    required this.bootChild,
    required this.appChild,
  });

  /// true = 已换壳为真实工作区子树；false = 仍处启动壳。
  final bool ready;

  /// 启动壳子树（生产 = [BootShellHost]）。
  final Widget bootChild;

  /// 真实工作区子树（生产 = [DbmasterApp]）。
  final Widget appChild;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 150);
    return AnimatedSwitcher(
      key: const ValueKey('boot-shell-switcher'),
      duration: duration,
      switchInCurve: AppDesignSystem.curveDefault,
      switchOutCurve: AppDesignSystem.curveDefault,
      child: ready
          ? KeyedSubtree(
              key: const ValueKey('boot-shell-app'),
              child: appChild,
            )
          : KeyedSubtree(
              key: const ValueKey('boot-shell-boot'),
              child: bootChild,
            ),
    );
  }
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
        child: const _AppLifecycleProbe(
          child: _WindowCloseGuard(child: _DbmasterAppContent()),
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
      AppLogger.w('WindowCloseGuard', '窗口关闭时 Navigator 尚未就绪，暂不关闭窗口');
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
    // 在首个 await 之前捕获——prepareForCleanExit 的闭包在下方组装（跨
    // await 的 context 访问是 analyzer 违例）。
    final appProvider = context.read<AppProvider>();
    // 关窗清理四步委托 AppShutdownCoordinator（sleep-resume 修复批 D1）：
    // 前三步（embedded stop / clean-exit 标记 / logger dispose）整体套 12s
    // 总 deadline，任何路径（步骤异常 / 永挂 / 超时）都保证放行闭包执行，
    // 且 setPreventClose(false) 先于 close()——窗口永不再被门控锁死；
    // 放行闭包自身不被 deadline 罩（D1 不变量④）。
    await const AppShutdownCoordinator().run(
      stopEmbeddedServer: () async {
        await EmbeddedServerService.instance.stop();
      },
      prepareCleanExit: () async {
        await appProvider.prepareForCleanExit();
      },
      disposeLogger: () async {
        await AppLogger.dispose();
      },
      releaseWindowClose: () async {
        await windowManager.setPreventClose(false);
        await windowManager.close();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// 唤醒生命周期探活挂载件(sleep-resume 修复批 D6/T8)。
///
/// 纯挂载壳:生命周期打点与探活逻辑全部在 [AppLifecycleObserver](独立
/// 服务类,可单测——单测禁 import main.dart,§0 MUST NOT #7),本件只在
/// 树中注册/注销观察者。挂在 [_WindowCloseGuard] 同层根级,应用存活期间
/// 常驻;probe 回调接 `ServerConnection().probeNow`(唤醒瞬间判定 embedded
/// 子进程死活,不等 30s 心跳 tick)。
class _AppLifecycleProbe extends StatefulWidget {
  const _AppLifecycleProbe({required this.child});

  final Widget child;

  @override
  State<_AppLifecycleProbe> createState() => _AppLifecycleProbeState();
}

class _AppLifecycleProbeState extends State<_AppLifecycleProbe> {
  // initState 先于一切读取赋值、dispose 后不再读取——late final 安全。
  late final AppLifecycleObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = AppLifecycleObserver(probe: ServerConnection().probeNow);
    _observer.attach();
  }

  @override
  void dispose() {
    _observer.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
