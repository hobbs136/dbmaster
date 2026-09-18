import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/safety/safety_finding.dart' show Severity;
import '../../services/server_connection.dart';
import '../../services/update_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/open_directory.dart';
import '../pro/pro_purchase_ui.dart';

/// 设置分区导航页（C22 M2 整窗迁移，原型 settings-page.html 左导航）。
/// 原型的「快捷键」页无对应设置内容——descope 不落空页（记录于
/// task_ui_phase2.md）。
enum _SettingsPage { appearance, ai, query, language, security, about }

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  _SettingsPage _page = _SettingsPage.appearance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return AlertDialog(
          backgroundColor: context.themeColors.bgSecondary,
          title: Text(
            l10n.settingsTitle,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
          // C22 M2：单列长滚动 → 左导航 + 右分区（原型 settings-page）。
          // 安全规则区版式已在首项迁移（紧凑行 + 级别圆点），原样嵌入
          // 「安全」页。
          content: SizedBox(
            width: 640,
            height: 520,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 176, child: _buildNav(context)),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: context.themeColors.dividerColor,
                ),
                Expanded(child: _buildPageContent(context, provider)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                l10n.commonClose,
                style: TextStyle(color: context.themeColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── 左导航（原型：active = accent-subtle 底 + 3px 左描边 + 主色文本）──

  Widget _buildNav(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNavItem(
            context,
            icon: LucideIcons.palette,
            label: l10n.settingsNavAppearance,
            selected: _page == _SettingsPage.appearance,
            onTap: () => setState(() => _page = _SettingsPage.appearance),
          ),
          _buildNavItem(
            context,
            icon: LucideIcons.sparkles,
            label: l10n.settingsNavAi,
            selected: _page == _SettingsPage.ai,
            onTap: () => setState(() => _page = _SettingsPage.ai),
          ),
          _buildNavItem(
            context,
            icon: LucideIcons.database,
            label: l10n.settingsNavQuery,
            selected: _page == _SettingsPage.query,
            onTap: () => setState(() => _page = _SettingsPage.query),
          ),
          _buildNavItem(
            context,
            icon: LucideIcons.globe,
            label: l10n.settingsNavLanguage,
            selected: _page == _SettingsPage.language,
            onTap: () => setState(() => _page = _SettingsPage.language),
          ),
          _buildNavItem(
            context,
            icon: LucideIcons.shield,
            label: l10n.settingsNavSecurity,
            selected: _page == _SettingsPage.security,
            onTap: () => setState(() => _page = _SettingsPage.security),
          ),
          _buildNavItem(
            context,
            icon: LucideIcons.info,
            label: l10n.settingsNavAbout,
            selected: _page == _SettingsPage.about,
            onTap: () => setState(() => _page = _SettingsPage.about),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.themeColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentBlue.withValues(alpha: 0.10) : null,
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected ? colors.accentBlue : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? colors.accentBlue : colors.textSecondary,
            ),
            const SizedBox(width: AppDesignSystem.space2_5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeMd,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? colors.accentBlue : colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 右侧分区内容 ──

  Widget _buildPageContent(BuildContext context, AppProvider provider) {
    final Widget page = switch (_page) {
      _SettingsPage.appearance => _buildAppearancePage(context, provider),
      _SettingsPage.ai => _buildAiPage(context, provider),
      _SettingsPage.query => _buildQueryPage(context, provider),
      _SettingsPage.language => _buildLanguagePage(context),
      _SettingsPage.security => _buildSecurityPage(context, provider),
      _SettingsPage.about => _buildAboutPage(context),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: page,
    );
  }

  Widget _buildAppearancePage(BuildContext context, AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // C22 M2 续：主题控件按原型内联（即点即生效），退役
        // ThemePreviewDialog 跳转（原型 settings-page 外观分区语汇）。
        _buildThemeControlsSection(context),
        const SizedBox(height: AppDesignSystem.space4),
        _buildSectionHeader(context, l10n.settingsEditorSettings),
        _buildSettingItem(
          context,
          title: l10n.settingsEnableAutocomplete,
          description: l10n.settingsAutocompleteDescription,
          value: provider.autocompleteEnabled,
          onChanged: (value) {
            provider.setAutocompleteEnabled(value);
          },
        ),
      ],
    );
  }

  /// 内联主题控件（原型外观分区）：主题模式三卡 + 强调色圆点 + SQL 冷主题。
  /// 即点即生效（ThemeProvider setter 持久化），无暂存-应用态。
  Widget _buildThemeControlsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, l10n.settingsThemeMode),
            Row(
              children: [
                for (final mode in AppThemeMode.values) ...[
                  Expanded(
                    child: _buildThemeModeCard(context, themeProvider, mode),
                  ),
                  if (mode != AppThemeMode.values.last)
                    const SizedBox(width: AppDesignSystem.space3),
                ],
              ],
            ),
            const SizedBox(height: AppDesignSystem.space4),
            _buildSectionHeader(context, l10n.settingsThemeColor),
            Wrap(
              spacing: AppDesignSystem.space3,
              runSpacing: AppDesignSystem.space3,
              children: [
                for (final color in AccentColorType.values)
                  _buildAccentColorDot(context, themeProvider, color),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsSqlCoolThemeDesc,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeColors.textSecondary,
                    ),
                  ),
                ),
                Switch(
                  value: themeProvider.sqlCoolTheme,
                  onChanged: (v) =>
                      context.read<ThemeProvider>().setSqlCoolTheme(v),
                  activeThumbColor: context.themeColors.accentBlue,
                  activeTrackColor: context.themeColors.accentBlue.withValues(
                    alpha: 0.4,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeModeCard(
    BuildContext context,
    ThemeProvider themeProvider,
    AppThemeMode mode,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final accent = themeProvider.accentColor.color;
    final selected = themeProvider.themeMode == mode;
    const modeIcons = {
      AppThemeMode.dark: LucideIcons.moon,
      AppThemeMode.light: LucideIcons.sun,
      AppThemeMode.system: LucideIcons.sunMoon,
    };
    return InkWell(
      onTap: () => context.read<ThemeProvider>().setThemeMode(mode),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          border: Border.all(
            color: selected ? accent : context.themeColors.borderLight,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              modeIcons[mode],
              size: 20,
              color: selected ? accent : context.themeColors.textSecondary,
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              mode.displayName(l10n),
              style: TextStyle(
                fontSize: 12,
                color: selected ? accent : context.themeColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentColorDot(
    BuildContext context,
    ThemeProvider themeProvider,
    AccentColorType color,
  ) {
    final selected = themeProvider.accentColor == color;
    return InkWell(
      key: ValueKey('accent_dot_${color.name}'),
      onTap: () => context.read<ThemeProvider>().setAccentColor(color),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.color,
          shape: BoxShape.circle,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.color.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(LucideIcons.check, color: Colors.white, size: 14)
            : null,
      ),
    );
  }

  Widget _buildAiPage(BuildContext context, AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, l10n.settingsAiSettings),
        _buildSettingItem(
          context,
          title: l10n.settingsAutoExecuteSql,
          description: l10n.settingsAutoExecuteSqlDescription,
          value: provider.autoExecuteSql,
          onChanged: (value) {
            provider.setAutoExecuteSql(value);
          },
        ),
      ],
    );
  }

  Widget _buildQueryPage(BuildContext context, AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, l10n.settingsQueryLimit),
        _buildSettingItem(
          context,
          title: l10n.settingsAutoLimitEnabled,
          description: l10n.settingsAutoLimitEnabledDesc,
          value: provider.autoLimitEnabled,
          onChanged: (value) {
            provider.setAutoLimitEnabled(value);
          },
        ),
        if (provider.autoLimitEnabled)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: Row(
              children: [
                Text(
                  l10n.settingsAutoLimitValue,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.themeColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space3),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: TextEditingController(
                      text: provider.autoLimitValue.toString(),
                    ),
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.themeColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space2,
                        vertical: AppDesignSystem.space1_5,
                      ),
                      filled: true,
                      fillColor: context.themeColors.bgQuaternary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (value) {
                      final intValue = int.tryParse(value);
                      if (intValue != null &&
                          intValue >= 100 &&
                          intValue <= 100000) {
                        provider.setAutoLimitValue(intValue);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLanguagePage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, l10n.settingsGeneralSettings),
        _buildLanguageSettingItem(context),
      ],
    );
  }

  Widget _buildSecurityPage(BuildContext context, AppProvider provider) {
    return _buildSafetyRulesSection(context, provider);
  }

  Widget _buildAboutPage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubscriptionSection(context),
        const SizedBox(height: AppDesignSystem.space4),
        _buildLogsSection(context),
        const SizedBox(height: AppDesignSystem.space4),
        _buildUpdateSection(context),
        const SizedBox(height: AppDesignSystem.space4),
        _buildAboutSection(context),
      ],
    );
  }

  Widget _buildLanguageSettingItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.themeColors.accentBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            ),
            child: Icon(
              LucideIcons.languages,
              color: context.themeColors.accentBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Text(
              AppLocalizations.of(context)?.settingsLanguage ?? 'Language',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.themeColors.textPrimary,
              ),
            ),
          ),
          DropdownButton<Locale>(
            value: context.watch<LocaleProvider>().locale,
            onChanged: (Locale? newLocale) {
              if (newLocale != null) {
                context.read<LocaleProvider>().setLocale(newLocale);
              }
            },
            items: LocaleProvider.supportedLocales.map((locale) {
              return DropdownMenuItem(
                value: locale,
                child: Text(
                  context.watch<LocaleProvider>().getLocaleName(locale),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionSection(BuildContext context) {
    // open-core Phase B：订阅区块经 ProPurchaseUi SPI 注入（OSS 返回 null → 空）。
    return context.read<ProPurchaseUi>().buildSubscriptionSection(context) ??
        const SizedBox.shrink();
  }

  /// 诊断日志区块（U14）：打开日志目录 + 导出当前日志文件。文件通道未启用
  /// （init 失败 / 已 dispose）时按钮置灰。
  Widget _buildLogsSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final logsDir = AppLogger.logsDirectory;
    final logFile = AppLogger.currentLogFile;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.themeColors.accentBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            ),
            child: Icon(
              LucideIcons.fileText,
              color: context.themeColors.accentBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsLogs,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space0_5),
                Text(
                  logFile != null
                      ? logFile.uri.pathSegments.last
                      : l10n.logsUnavailable,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: logsDir != null ? () => _openLogsFolder(context) : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: context.themeColors.accentBlue,
            ),
            child: Text(l10n.logsOpenFolder),
          ),
          TextButton(
            onPressed: logFile != null ? () => _exportLogs(context) : null,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: context.themeColors.accentBlue,
            ),
            child: Text(l10n.logsExport),
          ),
        ],
      ),
    );
  }

  Future<void> _openLogsFolder(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final dir = AppLogger.logsDirectory;
    if (dir == null) return;
    final ok = await openDirectoryInFileManager(dir.path);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.logsOpenFolderFailed)));
    }
  }

  Future<void> _exportLogs(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final src = AppLogger.currentLogFile;
    if (src == null) return;
    try {
      // 先冲刷缓冲，拷贝必须包含最新行。
      await AppLogger.flush();
      final dest = await FilePicker.platform.saveFile(
        fileName: src.uri.pathSegments.last,
        type: FileType.custom,
        allowedExtensions: ['log'],
      );
      if (dest == null || dest.isEmpty) return;
      await src.copy(dest);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.logsExportSuccess)));
      }
    } catch (e) {
      AppLogger.e('Settings', 'Log export failed', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.logsExportFailed(e.toString()))),
        );
      }
    }
  }

  /// 安全审查规则配置分区（B1 + B6，C22 M2 迁移新语汇：紧凑分区头 +
  /// 单容器行列表 + 级别圆点，替代 12 张独立重卡片）。
  ///
  /// 12 条规则开关（B1 六条 + T14 六条）+ 1 个统一行数阈值。开关/阈值经
  /// QuerySettingsProvider 持久化，query_editor_widget._buildSafetyService
  /// 每次执行前读取构造。级别圆点取规则产出的 finding 严重度（真相源 =
  /// rules/*.dart 的 severity 字段，此处静态映射；改规则严重度时同步）。
  /// reviewFailClosed 是降级策略开关非检测规则，圆点用 info 色区分。
  ///
  /// 门控：Pro 规则（FullTableScan/SqlInjection/ExplainFullScan/
  /// ExplainEstimatedRows）在此全显示不拦截——与桌面端门控整体禁用语义
  /// 一致。门控恢复时在此加 isProFeatureEnabled 判断。
  Widget _buildSafetyRulesSection(BuildContext context, AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final config = provider.querySettings.safetyConfig;
    final qs = provider.querySettings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 紧凑分区头（C22-0/C23 语汇：14px 图标 + 11px w600 次级色）。
        Padding(
          padding: const EdgeInsets.only(
            left: AppDesignSystem.space1,
            bottom: AppDesignSystem.space2,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.listChecks,
                size: 14,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                l10n.safetyRulesSectionTitle,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(color: context.themeColors.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleSchemaCompat,
                description: l10n.safetyRuleSchemaCompatDesc,
                value: config.schemaCompatEnabled,
                onChanged: qs.setSchemaCompatEnabled,
                severity: Severity.high,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleMissingLimit,
                description: l10n.safetyRuleMissingLimitDesc,
                value: config.missingLimitEnabled,
                onChanged: qs.setMissingLimitEnabled,
                severity: Severity.medium,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleFullTableScan,
                description: l10n.safetyRuleFullTableScanDesc,
                value: config.fullTableScanEnabled,
                onChanged: qs.setFullTableScanEnabled,
                severity: Severity.medium,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleSqlInjection,
                description: l10n.safetyRuleSqlInjectionDesc,
                value: config.sqlInjectionEnabled,
                onChanged: qs.setSqlInjectionEnabled,
                severity: Severity.high,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleExplainFullScan,
                description: l10n.safetyRuleExplainFullScanDesc,
                value: config.explainFullScanEnabled,
                onChanged: qs.setExplainFullScanEnabled,
                severity: Severity.medium,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleExplainEstimatedRows,
                description: l10n.safetyRuleExplainEstimatedRowsDesc,
                value: config.explainEstimatedRowsEnabled,
                onChanged: qs.setExplainEstimatedRowsEnabled,
                severity: Severity.medium,
              ),
              _buildSafetyRuleDivider(context),
              // B6 规则包（T14 收口，方案 §2.3 六条；前五条检测规则 +
              // 第六条审查降级 fail-closed）。
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleExecutableComment,
                description: l10n.safetyRuleExecutableCommentDesc,
                value: config.executableCommentEnabled,
                onChanged: qs.setExecutableCommentEnabled,
                severity: Severity.high,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleTautologyPredicate,
                description: l10n.safetyRuleTautologyPredicateDesc,
                value: config.tautologyPredicateEnabled,
                onChanged: qs.setTautologyPredicateEnabled,
                severity: Severity.high,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleComplementaryOr,
                description: l10n.safetyRuleComplementaryOrDesc,
                value: config.complementaryOrEnabled,
                onChanged: qs.setComplementaryOrEnabled,
                severity: Severity.high,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleWritableCte,
                description: l10n.safetyRuleWritableCteDesc,
                value: config.writableCteEnabled,
                onChanged: qs.setWritableCteEnabled,
                severity: Severity.medium,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleFileWrite,
                description: l10n.safetyRuleFileWriteDesc,
                value: config.fileWriteEnabled,
                onChanged: qs.setFileWriteEnabled,
                severity: Severity.high,
              ),
              _buildSafetyRuleDivider(context),
              _buildSafetyRuleRow(
                context,
                title: l10n.safetyRuleReviewFailClosed,
                description: l10n.safetyRuleReviewFailClosedDesc,
                value: config.reviewFailClosedEnabled,
                onChanged: qs.setReviewFailClosedEnabled,
                severity: null,
              ),
              _buildSafetyRuleDivider(context),
              // 统一行数阈值数值框（喂给 MissingLimit/ExplainFullScan/ExplainEstimatedRows）。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.safetyFullScanThreshold,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space3),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: TextEditingController(
                          text: config.fullScanRowThreshold.toString(),
                        ),
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.themeColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppDesignSystem.space2,
                            vertical: AppDesignSystem.space1_5,
                          ),
                          filled: true,
                          fillColor: context.themeColors.bgQuaternary,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppDesignSystem.radiusSm,
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (value) {
                          final intValue = int.tryParse(value);
                          if (intValue != null) {
                            // Provider 内部会 clamp 到合法范围。
                            qs.setFullScanRowThreshold(intValue);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 规则组内的紧凑行：级别圆点 + 标题/描述 + 开关（原型
  /// security-review.html 规则行语汇；开关序 = 测试 tapSwitch 索引契约）。
  Widget _buildSafetyRuleRow(
    BuildContext context, {
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Severity? severity,
  }) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    // null = 策略开关（fail-closed 降级），info 色区分于检测规则。
    final dotColor = severity == null
        ? colors.info
        : severity == Severity.high
        ? colors.error
        : colors.warning;
    final dotTooltip = severity == null
        ? l10n.safetySeverityPolicy
        : severity == Severity.high
        ? l10n.safetySeverityHigh
        : l10n.safetySeverityMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Tooltip(
              message: dotTooltip,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space0_5),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.accentBlue,
            activeTrackColor: colors.accentBlue.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyRuleDivider(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: context.themeColors.dividerColor,
    );
  }

  /// 应用更新区块（U15）：手动「检查更新」（GitHub Releases latest）+ 状态
  /// 展示 + 「前往下载」入口 + 启动自动检查开关（默认开）。server 版本及
  /// 兼容性提示一并列出（embedded 握手 / 远程 /api/instance 同源）。
  Widget _buildUpdateSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListenableBuilder(
          listenable: UpdateService.instance,
          builder: (context, _) {
            final svc = UpdateService.instance;
            final checking = svc.status == UpdateCheckStatus.checking;
            final showDownload =
                (svc.status == UpdateCheckStatus.available ||
                    svc.status == UpdateCheckStatus.unknown) &&
                svc.latestTag != null;
            return Container(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
                border: Border.all(color: context.themeColors.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.themeColors.accentBlue.withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusMd,
                      ),
                    ),
                    child: Icon(
                      LucideIcons.cloudDownload,
                      color: context.themeColors.accentBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.updateSectionTitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: context.themeColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppDesignSystem.space0_5),
                        Text(
                          _updateStatusText(context, svc),
                          style: TextStyle(
                            fontSize: 11,
                            color: svc.updateAvailable
                                ? context.themeColors.success
                                : context.themeColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        ..._serverVersionLines(context),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: checking ? null : svc.checkNow,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: context.themeColors.accentBlue,
                    ),
                    child: Text(
                      checking
                          ? l10n.updateStatusChecking
                          : l10n.updateCheckButton,
                    ),
                  ),
                  if (showDownload)
                    TextButton(
                      onPressed: () => _launchUpdateDownload(svc),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: context.themeColors.accentBlue,
                      ),
                      child: Text(l10n.updateGoDownload),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppDesignSystem.space2),
        ListenableBuilder(
          listenable: UpdateService.instance,
          builder: (context, _) {
            final svc = UpdateService.instance;
            return _buildSettingItem(
              context,
              title: l10n.updateAutoCheck,
              description: l10n.updateAutoCheckDesc,
              value: svc.autoCheckEnabled,
              onChanged: svc.setAutoCheckEnabled,
            );
          },
        ),
      ],
    );
  }

  String _updateStatusText(BuildContext context, UpdateService svc) {
    final l10n = AppLocalizations.of(context)!;
    final current = svc.appVersion.split('+').first;
    switch (svc.status) {
      case UpdateCheckStatus.checking:
        return l10n.updateStatusChecking;
      case UpdateCheckStatus.upToDate:
        return l10n.updateStatusUpToDate;
      case UpdateCheckStatus.available:
        return l10n.updateStatusAvailable(svc.latestTag ?? '');
      case UpdateCheckStatus.unknown:
        return svc.latestTag != null
            ? l10n.updateStatusUnknownLatest(svc.latestTag!)
            : l10n.updateStatusUnknownVersion;
      case UpdateCheckStatus.failed:
        return l10n.updateStatusFailed;
      case UpdateCheckStatus.idle:
        return l10n.updateCurrentVersion(current);
    }
  }

  /// server 版本行（已连接且拿到版本时显示）；低于最低兼容版本给告警色。
  List<Widget> _serverVersionLines(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conn = ServerConnection();
    final version = conn.serverVersion;
    if (version == null) return const [];
    return [
      const SizedBox(height: AppDesignSystem.space0_5),
      Text(
        conn.serverVersionOutdated
            ? l10n.serverVersionOutdated(
                version,
                ServerConnection.minCompatibleServerVersion,
              )
            : l10n.serverVersionLine(version),
        style: TextStyle(
          fontSize: 11,
          color: conn.serverVersionOutdated
              ? context.themeColors.warning
              : context.themeColors.textMuted,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ];
  }

  Future<void> _launchUpdateDownload(UpdateService svc) async {
    try {
      await launchUrl(svc.downloadUrl);
    } catch (_) {} // best-effort，对齐 server_connect_dialog 模式
  }

  /// 关于区块（U17）：版本信息（APP_VERSION，U15 构建注入）+ 反馈入口。
  Widget _buildAboutSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final version = UpdateService.instance.appVersion.split('+').first;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.themeColors.accentBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            ),
            child: Icon(
              LucideIcons.info,
              color: context.themeColors.accentBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAbout,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space0_5),
                Text(
                  l10n.aboutVersionLine(version),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await launchUrl(
                  Uri.parse('https://github.com/hobbs136/dbmaster/issues'),
                );
              } catch (_) {} // best-effort
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: context.themeColors.accentBlue,
            ),
            child: Text(l10n.aboutFeedback),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.themeColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.themeColors.accentBlue,
            activeTrackColor: context.themeColors.accentBlue.withValues(
              alpha: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
