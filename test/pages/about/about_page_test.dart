// T4 开源迁移：About 页 widget 测试——版权行、AGPL 授权声明与许可证入口可达。
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/pages/about/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap() {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const AboutPage(),
  );
}

void main() {
  testWidgets('About 页展示应用身份、版本、版权行与 AGPL 授权声明', (tester) async {
    await tester.pumpWidget(_wrap());

    expect(find.text('DbMaster'), findsOneWidget);
    expect(find.text('AGPL-3.0-only'), findsOneWidget);
    expect(
      find.text('Copyright (c) 2026 dbmaster contributors'),
      findsOneWidget,
    );
    // 授权声明：同协议提供完整源码义务。
    expect(find.textContaining('licensed under AGPL-3.0-only'), findsOneWidget);
    expect(find.textContaining('complete source code'), findsOneWidget);
    // 版本行走 l10n（en: "Version {version}"）。
    expect(find.textContaining('Version '), findsOneWidget);
  });

  testWidgets('点击许可证卡片打开内建 LicensePage（展示许可证全文）', (tester) async {
    await tester.pumpWidget(_wrap());

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
