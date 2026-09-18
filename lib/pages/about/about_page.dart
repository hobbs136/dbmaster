// T4 开源迁移（AGPL-3.0）：关于页——应用身份、版权行、AGPL 授权声明与许可证入口。
//
// 入口在 SidebarFooter 动作行（全局 chrome §3.1.7）。许可证全文走 Flutter 内建
// showLicensePage：构建期 flutter 工具自动收集根 LICENSE（AGPL-3.0 全文）与
// third_party vendored 组件（lucide_icons_flutter / re_editor）各自 LICENSE，
// 此处不手工内嵌全文。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../services/update_service.dart';
import '../../theme/app_colors.dart';

/// 关于页：展示版本、版权与授权声明，并提供许可证全文入口。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  // 版权行与 AGPL 授权声明为法律声明文本：按许可证声明惯例保持单一权威
  // 表述、不本地化翻译（AGPL 原文本身即英文）；页面其余标签走 AppLocalizations。
  static const String _copyrightLine =
      'Copyright (c) 2026 dbmaster contributors';
  static const String _licenseNotice =
      'This program is licensed under AGPL-3.0-only. If you distribute a '
      'modified version, you must provide the complete source code under '
      'the same license.';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final version = UpdateService.instance.appVersion.split('+').first;
    return Scaffold(
      backgroundColor: colors.bgSecondary,
      appBar: AppBar(
        title: Text(
          l10n.settingsAbout,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        backgroundColor: colors.bgPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: colors.borderLight, height: 1),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            children: [
              const SizedBox(height: AppDesignSystem.space4),
              Icon(LucideIcons.database, size: 40, color: colors.accentBlue),
              const SizedBox(height: AppDesignSystem.space2),
              Center(
                child: Text(
                  'DbMaster',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppDesignSystem.space0_5),
              Center(
                child: Text(
                  l10n.aboutVersionLine(version),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: AppDesignSystem.space4),
              _buildLicenseCard(context),
              const SizedBox(height: AppDesignSystem.space3),
              Text(
                _licenseNotice,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 许可证卡片：协议名 + 版权行，点击打开内建许可证页（根 LICENSE 全文与
  /// third_party 许可证由 flutter 工具构建期收集）。
  Widget _buildLicenseCard(BuildContext context) {
    final colors = context.themeColors;
    return Material(
      color: colors.bgTertiary,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        onTap: () => _showLicenses(context),
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 20, color: colors.accentBlue),
              const SizedBox(width: AppDesignSystem.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AGPL-3.0-only',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppDesignSystem.space0_5),
                    Text(
                      _copyrightLine,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Icon(LucideIcons.chevronRight, size: 16, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showLicenses(BuildContext context) {
    final version = UpdateService.instance.appVersion.split('+').first;
    showLicensePage(
      context: context,
      applicationName: 'DbMaster',
      applicationVersion: version,
      applicationLegalese: _copyrightLine,
    );
  }
}
