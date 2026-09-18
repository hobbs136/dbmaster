import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/dml_risk_models.dart';
import 'package:dbmaster/organisms/connection/settings_dialog.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/utils/app_logger.dart';
import 'package:dbmaster/services/update_service.dart';

// ============================================================================
// Settings Dialog Widget Tests
// Tests the SettingsDialog UI and its interaction with providers.
//
// C22 M2 整窗迁移后：左导航六分区（外观/AI/查询/语言/安全/关于），
// 开关分布在不同页——find.byType(Switch) 只命中当前页，tapSwitch 索引
// 为页内序。导航点击用 nav 标签文本（从非目标页发起，无歧义）。
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      await prefs.remove(key);
    }
  });

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  AppLocalizations l10nOf(WidgetTester tester) {
    return AppLocalizations.of(tester.element(find.byType(SettingsDialog)))!;
  }

  Future<AppProvider> pumpSettingsDialog(WidgetTester tester) async {
    // Use a tall viewport so all dialog content is visible and tappable
    tester.binding.setSurfaceSize(const Size(800, 1200));

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    await themeProvider.load();
    await localeProvider.load();

    late AppProvider capturedProvider;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          // Phase B：SettingsDialog 经 ProPurchaseUi SPI 订阅（OSS 注入 NoOp）
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
          ChangeNotifierProvider<AppProvider>(
            create: (_) {
              final provider = AppProvider();
              capturedProvider = provider;
              return provider;
            },
          ),
        ],
        child: Consumer2<LocaleProvider, ThemeProvider>(
          builder: (context, locale, theme, _) {
            return MaterialApp(
              locale: locale.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(theme.accentColorValue),
              home: Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const SettingsDialog(),
                      );
                    },
                    child: const Text('Open Settings'),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Open the dialog
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    // Verify dialog is open
    expect(find.byType(SettingsDialog), findsOneWidget);

    return capturedProvider;
  }

  /// 切换左侧导航到目标分区（nav 标签从非目标页发起时全局唯一）。
  Future<void> openPage(WidgetTester tester, String navLabel) async {
    await tester.tap(find.text(navLabel));
    await tester.pumpAndSettle();
  }

  /// Scroll a widget into view and tap it（索引 = 当前页内开关序）。
  Future<void> tapSwitch(WidgetTester tester, int index) async {
    final switches = find.byType(Switch);
    expect(switches, findsWidgets);
    final target = switches.at(index);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  // --------------------------------------------------------------------------
  // Tests
  // --------------------------------------------------------------------------

  group('MAN-SET: Settings Dialog Rendering', () {
    testWidgets('应渲染左导航六分区，默认外观页', (tester) async {
      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      // 六个导航项常驻。C22 M2 续：主题控件内联后外观页不再有
      // 「外观」分区头（改为主题模式/强调色子分区头）→ nav 文案全局唯一。
      expect(find.text(l10n.settingsNavAppearance), findsOneWidget);
      expect(find.text(l10n.settingsNavAi), findsOneWidget);
      expect(find.text(l10n.settingsNavQuery), findsOneWidget);
      expect(find.text(l10n.settingsNavLanguage), findsOneWidget);
      expect(find.text(l10n.settingsNavSecurity), findsOneWidget);
      expect(find.text(l10n.settingsNavAbout), findsOneWidget);

      // 默认页 = 外观：主题项 + 编辑器（自动补全）分区。
      expect(
        find.text(l10n.settingsEditorSettings),
        findsOneWidget,
        reason: '默认外观页应含编辑器设置分区',
      );
      expect(find.text(l10n.settingsEnableAutocomplete), findsOneWidget);
    });

    testWidgets('导航切页：查询/安全/关于内容各就各位', (tester) async {
      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      await openPage(tester, l10n.settingsNavQuery);
      expect(
        find.text(l10n.settingsAutoLimitEnabled),
        findsOneWidget,
        reason: '查询页应含自动 LIMIT 开关',
      );

      await openPage(tester, l10n.settingsNavSecurity);
      expect(
        find.text(l10n.safetyRulesSectionTitle),
        findsOneWidget,
        reason: '安全页应含安全审查规则分区',
      );

      await openPage(tester, l10n.settingsNavAbout);
      expect(find.text(l10n.settingsLogs), findsOneWidget, reason: '关于页应含日志区块');
    });

    testWidgets('应显示语言设置项', (tester) async {
      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      await openPage(tester, l10n.settingsNavLanguage);
      expect(
        find.text(l10n.settingsGeneralSettings),
        findsOneWidget,
        reason: '语言页应显示常规设置分区头',
      );
      expect(find.byType(DropdownButton<Locale>), findsOneWidget);
    });

    testWidgets('应显示主题设置项（内联控件，C22 M2 续）', (tester) async {
      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      // 主题控件内联外观页（退役 ThemePreviewDialog 跳转）。
      expect(find.text(l10n.settingsThemeMode), findsOneWidget);
      expect(find.text(l10n.settingsThemeColor), findsOneWidget);
      expect(find.byIcon(LucideIcons.moon), findsOneWidget);
      expect(find.byIcon(LucideIcons.sun), findsOneWidget);
      expect(find.byIcon(LucideIcons.sunMoon), findsOneWidget);
    });

    testWidgets('主题控件即点即生效：模式卡/强调色/冷主题', (tester) async {
      await pumpSettingsDialog(tester);

      final themeProvider = Provider.of<ThemeProvider>(
        tester.element(find.byType(SettingsDialog)),
        listen: false,
      );

      // 点 Light 模式卡 → 立即生效（无暂存-应用态）。
      await tester.tap(find.byIcon(LucideIcons.sun));
      await tester.pumpAndSettle();
      expect(themeProvider.themeMode, AppThemeMode.light);

      // 点第一个强调色圆点（ValueKey 测试钩子）→ 强调色立即切换。
      await tester.tap(
        find.byKey(ValueKey('accent_dot_${AccentColorType.values.first.name}')),
      );
      await tester.pumpAndSettle();
      expect(themeProvider.accentColor, AccentColorType.values.first);

      // 外观页开关序 0 = SQL 冷主题（内联新增开关；默认开 → 点 → 关）。
      await tapSwitch(tester, 0);
      expect(themeProvider.sqlCoolTheme, isFalse);
    });
  });

  group('MAN-SET: 编辑器设置 - 自动补全', () {
    testWidgets('切换自动补全开关应更新 AppProvider', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);

      // 外观页开关序：SQL 冷主题(0) + 自动补全(1)。
      await tapSwitch(tester, 1);

      expect(
        appProvider.autocompleteEnabled,
        isFalse,
        reason: '切换后 autocompleteEnabled 应为 false',
      );
    });
  });

  group('MAN-SET: 查询限制设置', () {
    testWidgets('切换自动 LIMIT 开关应更新 AppProvider', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      await openPage(tester, l10n.settingsNavQuery);
      await tapSwitch(tester, 0);

      expect(
        appProvider.autoLimitEnabled,
        isFalse,
        reason: '切换后 autoLimitEnabled 应为 false',
      );
    });

    testWidgets('修改 LIMIT 数值应更新 AppProvider', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      await openPage(tester, l10n.settingsNavQuery);
      expect(find.byType(TextField), findsOneWidget, reason: '查询页仅一个数值框');

      await tester.enterText(find.byType(TextField), '7500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(appProvider.autoLimitValue, equals(7500));
    });

    testWidgets('无效 LIMIT 数值不应更新 AppProvider', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);
      final before = appProvider.autoLimitValue;

      await openPage(tester, l10n.settingsNavQuery);
      await tester.enterText(find.byType(TextField), 'not-a-number');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(appProvider.autoLimitValue, equals(before));
    });
  });

  group('MAN-SET: AI 设置', () {
    testWidgets('切换自动执行 SQL 开关应更新 AppProvider', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      // Default should be false
      expect(appProvider.autoExecuteSql, isFalse);

      await openPage(tester, l10n.settingsNavAi);
      await tapSwitch(tester, 0);

      expect(
        appProvider.autoExecuteSql,
        isTrue,
        reason: '打开开关后 autoExecuteSql 应为 true',
      );
    });
  });

  group('MAN-SET: 安全审查规则', () {
    Future<void> openSecurityPage(WidgetTester tester) async {
      final l10n = l10nOf(tester);
      await openPage(tester, l10n.settingsNavSecurity);
    }

    testWidgets('应渲染安全审查规则分区及 12 个开关（B1 六 + B6 六）', (tester) async {
      await pumpSettingsDialog(tester);
      await openSecurityPage(tester);
      final l10n = l10nOf(tester);

      await tester.ensureVisible(find.text(l10n.safetyRulesSectionTitle));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.safetyRulesSectionTitle),
        findsOneWidget,
        reason: '应显示安全审查规则分区标题',
      );
      expect(find.text(l10n.safetyRuleSchemaCompat), findsOneWidget);
      expect(find.text(l10n.safetyRuleExplainEstimatedRows), findsOneWidget);
      expect(
        find.text(l10n.safetyRuleReviewFailClosed),
        findsOneWidget,
        reason: 'B6（T14）末位规则开关应渲染',
      );

      // C22 M2 迁移：级别圆点以 Tooltip 标注严重度（真相源 = 规则文件
      // 的 severity 字段，改规则严重度时同步本断言与设置区映射）。
      expect(
        find.byTooltip(l10n.safetySeverityHigh),
        findsNWidgets(6),
        reason: '高危规则 6 条',
      );
      expect(
        find.byTooltip(l10n.safetySeverityMedium),
        findsNWidgets(5),
        reason: '警告规则 5 条',
      );
      expect(
        find.byTooltip(l10n.safetySeverityPolicy),
        findsOneWidget,
        reason: 'reviewFailClosed 是降级策略开关（非检测规则）',
      );
    });

    testWidgets('切换规则开关应更新 QuerySettingsProvider', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      await openSecurityPage(tester);

      // 默认全开。
      expect(
        appProvider.querySettings.safetyConfig.schemaCompatEnabled,
        isTrue,
      );

      // 安全页内序 0：schemaCompat。
      await tapSwitch(tester, 0);

      expect(
        appProvider.querySettings.safetyConfig.schemaCompatEnabled,
        isFalse,
        reason: '关闭后 schemaCompatEnabled 应为 false',
      );
    });

    testWidgets('切换最后一个规则开关应更新对应字段', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      await openSecurityPage(tester);

      // 安全页内序 5：既有 6 个安全规则里最后一个（explainEstimatedRows）。
      await tapSwitch(tester, 5);

      expect(
        appProvider.querySettings.safetyConfig.explainEstimatedRowsEnabled,
        isFalse,
      );
    });

    testWidgets('B6 规则开关（T14）：末位 reviewFailClosed 可切换', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      await openSecurityPage(tester);

      // 安全页内序 11：B6 六开关（6-11）里最后一个（reviewFailClosed）。
      await tapSwitch(tester, 11);

      expect(
        appProvider.querySettings.safetyConfig.reviewFailClosedEnabled,
        isFalse,
        reason: '关闭后 reviewFailClosedEnabled 应为 false',
      );
    });

    testWidgets('阈值输入应更新 fullScanRowThreshold', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      await openSecurityPage(tester);

      expect(
        appProvider.querySettings.safetyConfig.fullScanRowThreshold,
        equals(100000),
      );

      // C22 M2 分页后安全页只有一个数值框（旧 Row-ancestor 定位因外层
      // 布局 Row 新增会命中多个）。
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '50000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        appProvider.querySettings.safetyConfig.fullScanRowThreshold,
        equals(50000),
      );
    });

    testWidgets('阈值低于下限应被 clamp', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      await openSecurityPage(tester);

      await tester.enterText(find.byType(TextField), '100'); // below min 1000
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        appProvider.querySettings.safetyConfig.fullScanRowThreshold,
        equals(SafetyConfig.minFullScanRowThreshold),
        reason: '低于下限应 clamp 到 minFullScanRowThreshold',
      );
    });
  });

  group('MAN-SET-006: 设置持久化', () {
    testWidgets('修改设置后重启 Provider 应保留值', (tester) async {
      final appProvider = await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      // 外观页：关自动补全（页内序 1——序 0 是 SQL 冷主题内联开关）。
      await tapSwitch(tester, 1);

      // 查询页：关自动 LIMIT。
      await openPage(tester, l10n.settingsNavQuery);
      await tapSwitch(tester, 0);

      // AI 页：开自动执行 SQL。
      await openPage(tester, l10n.settingsNavAi);
      await tapSwitch(tester, 0);

      // Close dialog
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();

      // Create a new provider instance to simulate "restart"
      final newProvider = AppProvider();
      await newProvider.aiConfig.load();
      await newProvider.querySettings.load();

      // Verify persisted values
      expect(
        newProvider.autocompleteEnabled,
        isFalse,
        reason: '持久化后 autocompleteEnabled 应为 false',
      );
      expect(
        newProvider.autoLimitEnabled,
        isFalse,
        reason: '持久化后 autoLimitEnabled 应为 false',
      );
      expect(
        newProvider.autoExecuteSql,
        isTrue,
        reason: '持久化后 autoExecuteSql 应为 true',
      );
    });

    testWidgets('LIMIT 数值修改后应持久化', (tester) async {
      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      await openPage(tester, l10n.settingsNavQuery);
      await tester.enterText(find.byType(TextField), '7500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Close dialog
      await tester.tap(find.text(l10n.commonClose));
      await tester.pumpAndSettle();

      // Verify persistence
      final newProvider = AppProvider();
      await newProvider.querySettings.load();

      expect(
        newProvider.autoLimitValue,
        equals(7500),
        reason: '持久化后 autoLimitValue 应为 7500',
      );
    });
  });

  // ===========================================================================
  // U14：诊断日志区块（打开目录 / 导出）——关于页
  // ===========================================================================
  group('MAN-SET: 诊断日志区块（U14）', () {
    testWidgets('应渲染日志区块；文件日志未启用时按钮禁用', (tester) async {
      await AppLogger.resetForTesting();
      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      await openPage(tester, l10n.settingsNavAbout);
      await tester.ensureVisible(find.text(l10n.settingsLogs));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.logsUnavailable),
        findsOneWidget,
        reason: '未启用时应显示占位文案',
      );

      final openBtn = find.widgetWithText(TextButton, l10n.logsOpenFolder);
      final exportBtn = find.widgetWithText(TextButton, l10n.logsExport);
      expect(openBtn, findsOneWidget);
      expect(exportBtn, findsOneWidget);
      expect(
        tester.widget<TextButton>(openBtn).enabled,
        isFalse,
        reason: '未启用文件日志时「打开目录」应禁用',
      );
      expect(
        tester.widget<TextButton>(exportBtn).enabled,
        isFalse,
        reason: '未启用文件日志时「导出」应禁用',
      );
    });

    testWidgets('init 后按钮启用并显示当前日志文件名', (tester) async {
      // testWidgets 的 fake async 区域不推进真 IO 事件——文件操作必须包进
      // runAsync，否则 await 永远不回来（10 分钟超时）。
      final info = await tester.runAsync(() async {
        final tmp = await Directory.systemTemp.createTemp('settings_logs_test');
        await AppLogger.init(tmp);
        return (tmp, AppLogger.currentLogFile!);
      });
      final (tmp, logFile) = info!;

      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);
      await openPage(tester, l10n.settingsNavAbout);

      expect(
        find.text(logFile.uri.pathSegments.last),
        findsOneWidget,
        reason: '应显示当前会话日志文件名',
      );
      final openBtn = find.widgetWithText(TextButton, l10n.logsOpenFolder);
      final exportBtn = find.widgetWithText(TextButton, l10n.logsExport);
      expect(tester.widget<TextButton>(openBtn).enabled, isTrue);
      expect(tester.widget<TextButton>(exportBtn).enabled, isTrue);

      // 清理同样必须在 runAsync 里做。
      await tester.runAsync(() async {
        await AppLogger.resetForTesting();
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
    });
  });

  // ===========================================================================
  // U15：更新检查区块——关于页
  // ===========================================================================
  group('MAN-SET: 更新检查区块（U15）', () {
    setUp(() {
      UpdateService.resetForTesting();
    });

    tearDown(() {
      UpdateService.resetForTesting();
    });

    testWidgets('应渲染更新区块：标题/检查按钮/自动检查开关', (tester) async {
      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);

      await openPage(tester, l10n.settingsNavAbout);
      await tester.ensureVisible(find.text(l10n.updateSectionTitle));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.updateSectionTitle),
        findsOneWidget,
        reason: '应显示更新分区标题',
      );
      final checkBtn = find.widgetWithText(TextButton, l10n.updateCheckButton);
      expect(checkBtn, findsOneWidget);
      expect(
        tester.widget<TextButton>(checkBtn).enabled,
        isTrue,
        reason: '空闲态检查按钮应可点',
      );
      expect(
        find.text(l10n.updateAutoCheck),
        findsOneWidget,
        reason: '应显示自动检查开关行',
      );
    });

    testWidgets('点击检查按钮触发检查并随状态重建', (tester) async {
      // 注入罐头响应：latest v2026-08-17 vs 本地 v2026-07-27 → available。
      UpdateService.instance.testAppVersion = 'v2026-07-27';
      UpdateService.instance.testHttpClient = _UpdateMockClient((_) async {
        return ' {"tag_name":"v2026-08-17","html_url":"https://x/y"} ';
      });

      await pumpSettingsDialog(tester);
      final l10n = l10nOf(tester);
      await openPage(tester, l10n.settingsNavAbout);

      final checkBtn = find.widgetWithText(TextButton, l10n.updateCheckButton);
      await tester.ensureVisible(checkBtn);
      await tester.pumpAndSettle();

      await tester.tap(checkBtn);
      await tester.pumpAndSettle();

      expect(UpdateService.instance.status, UpdateCheckStatus.available);
      expect(
        find.text(l10n.updateStatusAvailable('v2026-08-17')),
        findsOneWidget,
        reason: '检查完成后应显示新版提示',
      );
      expect(
        find.text(l10n.updateGoDownload),
        findsOneWidget,
        reason: '有新版时应出现「前往下载」',
      );
    });
  });
}

/// U15 测试用：返回固定 JSON 字符串的极简 http client。
class _UpdateMockClient extends http.BaseClient {
  final Future<String> Function(http.Request request) _body;
  _UpdateMockClient(this._body);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await _body(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      contentLength: utf8.encode(body).length,
      request: request,
    );
  }
}
