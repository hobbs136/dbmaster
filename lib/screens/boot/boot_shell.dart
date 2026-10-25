import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/layout_preferences_provider.dart';
import '../../services/layout_preferences_service.dart';
import '../../theme/app_theme.dart';

/// 启动初始化阶段（UIRV-B4）。
///
/// 由 main.dart 的启动编排按真实初始化步骤推进；[generic] 为无阶段事件时
/// 的兜底（停留通用「正在准备工作区」文案）。纯枚举，不含任何业务逻辑。
enum BootStage {
  /// 未接到阶段事件（兜底，不显示具体阶段行）。
  generic,

  /// 日志落盘初始化（U14）。
  logger,

  /// Pro 能力模块 / 插件注册。
  extensions,

  /// 匿名遥测初始化。
  telemetry,

  /// embedded server 拉起 / 远程 server 定位。
  server,

  /// 远程会话恢复。
  session,
}

/// UIRV-B4 · 启动骨架屏：窗口显示后的首帧。
///
/// 品牌 Logo + 「正在准备工作区」+ 不定态指示器 + 工作区结构骨架（侧栏 /
/// 编辑器 / 网格占位）。纯表现层：不执行任何业务初始化，阶段与错误状态由
/// 调用方（main.dart 启动编排）传入；初始化意外失败时在同一容器内切换为
/// 结构化错误卡（标题 / 详情 / 重试），不回到白屏。
///
/// 减少动态效果（`MediaQuery.disableAnimations`）时停用循环动画——不定态
/// 指示器降级为静态圆点，骨架本身为纯静态色块（永不闪烁）。
class BootShell extends StatelessWidget {
  const BootShell({
    super.key,
    this.stage = BootStage.generic,
    this.errorDetail,
    this.onRetry,
    this.sidebarWidth,
  });

  /// 当前初始化阶段（驱动阶段文案行）。
  final BootStage stage;

  /// 初始化意外失败的详情文本（非空时渲染错误卡）；null = 启动态。
  final String? errorDetail;

  /// 错误卡重试按钮回调（= 重跑初始化序列）；null 时按钮禁用。
  final VoidCallback? onRetry;

  /// 侧栏宽度真相（UI35-151）：生产由 BootShellHost 从
  /// LayoutPreferencesProvider 解析后透传；null 时回落
  /// LayoutPreferencesService.defaultSidebarWidth。
  final double? sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    // 本组件仅在注册了 AppLocalizations delegates 的 MaterialApp 内渲染：
    // main.dart 启动壳经 AppLocalizations.localizationsDelegates 注册
    //（UIRV-B4 打回修复；无 delegates 的宿主会取到 null）。
    final l10n = AppLocalizations.of(context)!;
    // 宽度真相（UI35-151 / 裁决 #13）：侧栏骨架宽跟随运行时偏好；provider
    // 未注入或未加载完成时回落服务层默认宽（与真实首帧的侧栏渲染一致）。
    final sidebarWidth =
        this.sidebarWidth ?? LayoutPreferencesService.defaultSidebarWidth;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final windowWidth = constraints.maxWidth;
          // UI35-153：状态区/错误卡锚定主区中心（x = sidebarWidth +
          // (W − sidebarWidth)/2），与主区 400 宽欢迎卡同坐标——换壳后内容
          // 不横跳；不再用窗口 Center（会落在侧栏骨架之上）。
          final mainRegionLeft = sidebarWidth;
          return Stack(
            children: [
              // 结构骨架：描述即将到来的侧栏 / 编辑器 / 网格布局（纯静态色块）。
              Positioned.fill(
                child: _BootSkeleton(
                  colors: colors,
                  sidebarWidth: sidebarWidth,
                ),
              ),
              Positioned(
                key: const ValueKey('uirvBootStatusRegion'),
                left: mainRegionLeft,
                top: 0,
                bottom: 0,
                width: windowWidth - mainRegionLeft,
                child: Center(
                  child: errorDetail != null
                      ? _BootErrorCard(
                          colors: colors,
                          l10n: l10n,
                          detail: errorDetail ?? '',
                          onRetry: onRetry,
                        )
                      : _BootStatus(colors: colors, l10n: l10n, stage: stage),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 中心状态区：Logo + 字标 + 准备文案 + 不定态指示 + 阶段行。
class _BootStatus extends StatelessWidget {
  const _BootStatus({
    required this.colors,
    required this.l10n,
    required this.stage,
  });

  final ThemeColors colors;
  final AppLocalizations l10n;
  final BootStage stage;

  String _stageText(BootStage stage) {
    switch (stage) {
      case BootStage.generic:
        return l10n.uirvBootPreparing;
      case BootStage.logger:
        return l10n.uirvBootStageLogger;
      case BootStage.extensions:
        return l10n.uirvBootStageExtensions;
      case BootStage.telemetry:
        return l10n.uirvBootStageTelemetry;
      case BootStage.server:
        return l10n.uirvBootStageServer;
      case BootStage.session:
        return l10n.uirvBootStageSession;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 系统减少动态效果：不定态指示器降级为静态圆点（无循环动画）。
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.accentSubtle,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusLg),
          ),
          child: Icon(LucideIcons.database, size: 28, color: colors.accentBlue),
        ),
        const SizedBox(height: AppDesignSystem.space4),
        Text(
          'DbMaster',
          style: TextStyle(
            fontSize: AppDesignSystem.fontSize3xl,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        Text(
          l10n.uirvBootPreparing,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        const SizedBox(height: AppDesignSystem.space6),
        SizedBox(
          width: 20,
          height: 20,
          child: reducedMotion
              ? Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accentBlue,
                    ),
                  ),
                )
              : CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accentBlue),
                ),
        ),
        if (stage != BootStage.generic) ...[
          const SizedBox(height: AppDesignSystem.space3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accentBlue,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                _stageText(stage),
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 启动壳宿主（UIRV-B4 返工）：启动壳必需的 MaterialApp 配置——l10n
/// delegates / supportedLocales / 亮暗主题——的单一事实源。main.dart 的
/// `_BootRoot` 与 UI-B4-107 回归锁共用本件：漏配 delegates 时测试与生产
/// 同红（BootShell 首帧消费 `AppLocalizations.of(context)`，无 delegates
/// 即 null → build 抛错）。
class BootShellHost extends StatelessWidget {
  const BootShellHost({
    super.key,
    this.stage = BootStage.generic,
    this.errorDetail,
    this.onRetry,
  });

  /// 当前初始化阶段（透传 [BootShell]）。
  final BootStage stage;

  /// 初始化意外失败详情（非空时透传 [BootShell] 渲染错误卡）。
  final String? errorDetail;

  /// 错误卡重试回调（= 重跑初始化序列）。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DbMaster',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // 亮暗双主题最小例外（UIRV-B4 AC6）：ThemeProvider 尚未就绪（其 load
      // 在 DbmasterApp build 内才发生），启动壳按平台亮度直读分发亮暗主题；
      // 换壳后由 _DbmasterAppContent 的 ThemeProvider 接管主题。
      theme: AppTheme.light(AppDesignSystem.accentPrimary),
      darkTheme: AppTheme.dark(AppDesignSystem.accentPrimaryDark),
      themeMode: MediaQuery.platformBrightnessOf(context) == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: BootShell(
        stage: stage,
        errorDetail: errorDetail,
        onRetry: onRetry,
        // 宽度真相（UI35-151 / 裁决 #13）：启动序列期间 provider 尚未创建
        //（LayoutPreferencesProvider 在 DbmasterApp 内注册），回落服务层
        // 默认宽；provider 已就绪时跟随运行时 sidebarWidth。
        sidebarWidth: _resolveSidebarWidth(context),
      ),
    );
  }

  /// 从上游解析侧栏宽度真相；provider 缺席或未加载完成时返回 null
  ///（由 [BootShell] 回落 [LayoutPreferencesService.defaultSidebarWidth]）。
  double? _resolveSidebarWidth(BuildContext context) {
    try {
      final prefs = Provider.of<LayoutPreferencesProvider>(
        context,
        listen: false,
      );
      if (prefs.isLoaded) return prefs.sidebarWidth;
    } on ProviderNotFoundException {
      // 启动壳阶段 provider 尚未创建（生产常态）：走默认宽回落。
    }
    return null;
  }
}

/// 初始化意外失败的结构化错误卡（同一容器内换卡，不回白屏）。
class _BootErrorCard extends StatelessWidget {
  const _BootErrorCard({
    required this.colors,
    required this.l10n,
    required this.detail,
    this.onRetry,
  });

  final ThemeColors colors;
  final AppLocalizations l10n;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.borderLight),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.alertTriangle,
                size: 18,
                color: colors.accentRed,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  l10n.uirvBootErrorTitle,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeLg,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            detail,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: Text(l10n.retry),
            ),
          ),
        ],
      ),
    );
  }
}

/// 工作区结构骨架：左侧栏（搜索 + 树行缩进节奏）+ 主区（tab 条 / 编辑器 / 网格）
/// + 底部状态栏。纯静态色块，不随时间变化（骨架不闪烁）；颜色经 ThemeColors
/// 分发（bg 层级）。侧栏宽跟随运行时偏好（UI35-151），色块宽度按可用宽钳制。
class _BootSkeleton extends StatelessWidget {
  const _BootSkeleton({required this.colors, required this.sidebarWidth});

  final ThemeColors colors;

  /// 侧栏宽度真相（provider 值或服务层默认，已在 [BootShell] 回落）。
  final double sidebarWidth;

  Widget _bar(double height, double width, Color color, {double? indent}) {
    return Padding(
      padding: EdgeInsets.only(left: indent ?? 0),
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
      ),
    );
  }

  /// 树行色块按注入宽钳制（不写死基准宽），窄侧栏不溢出。
  double _treeWidth(double nominal, double available) =>
      nominal > available ? available : nominal;

  @override
  Widget build(BuildContext context) {
    final innerWidth =
        sidebarWidth - AppDesignSystem.space4 * 2; // 减去侧栏左右内距
    return KeyedSubtree(
      key: const ValueKey('uirvBootSkeleton'),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 侧栏骨架：搜索条 + 缩进树行（宽度跟随运行时偏好）。
                SizedBox(
                  key: const ValueKey('uirvBootSidebarSkeleton'),
                  width: sidebarWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDesignSystem.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(28, double.infinity, colors.bgTertiary),
                        const SizedBox(height: AppDesignSystem.space3),
                        _bar(12, _treeWidth(220, innerWidth), colors.bgTertiary),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, _treeWidth(190, innerWidth), colors.bgTertiary, indent: 16),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, _treeWidth(160, innerWidth - 32), colors.bgTertiary, indent: 32),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, _treeWidth(150, innerWidth - 32), colors.bgTertiary, indent: 32),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, _treeWidth(180, innerWidth - 16), colors.bgTertiary, indent: 16),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, _treeWidth(140, innerWidth - 32), colors.bgTertiary, indent: 32),
                      ],
                    ),
                  ),
                ),
                // 主区骨架：tab 条 + 编辑器行 + 网格行。
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDesignSystem.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(28, 320, colors.bgTertiary),
                        const SizedBox(height: AppDesignSystem.space3),
                        _bar(12, 480, colors.bgTertiary),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, 420, colors.bgTertiary),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, 460, colors.bgTertiary),
                        const SizedBox(height: AppDesignSystem.space2),
                        _bar(12, 300, colors.bgTertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // UI35-152：24px 状态栏骨架（3 个 6px 色块），沿 _bar 静态风格。
          Container(
            key: const ValueKey('uirvBootStatusbarSkeleton'),
            height: AppDesignSystem.statusHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space4,
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bar(6, 80, colors.bgTertiary),
                const SizedBox(width: 3),
                _bar(6, 56, colors.bgTertiary),
                const SizedBox(width: 3),
                _bar(6, 40, colors.bgTertiary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
