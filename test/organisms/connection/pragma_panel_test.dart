// PragmaExplorerDialog Widget 测试。
//
// 覆盖：错误态分支路由（无 adapter → pragmaNoAdapter 文案）。
// 不覆盖：正常加载态（需伪造 SQLite 连接注册到 dbService，成本高；
//   adapter 层逻辑已由 sqlite_adapter_test.dart 的 PRAGMA 组覆盖）。
// 不覆盖：非 PragmaAdapter 分支（需伪造非 SQLite 连接，成本高；
//   is! PragmaAdapter 是一行类型检查，逻辑简单）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/connection/pragma_panel.dart';
import 'package:dbmaster/providers/app_provider.dart';

void _setLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// pump 出 PragmaExplorerDialog。
/// 默认用真实 AppProvider()（无连接 → getAdapter 返回 null → pragmaNoAdapter 分支）。
Future<void> _pumpDialog(
  WidgetTester tester, {
  AppProvider? provider,
  String connectionId = 'test-conn',
}) async {
  _setLargeScreen(tester);
  final p = provider ?? AppProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: p,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => PragmaExplorerDialog.show(
              context,
              provider: p,
              connectionId: connectionId,
            ),
            child: const Text('Show'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();
}

void main() {
  group('PragmaExplorerDialog', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('无 adapter 时显示 pragmaNoAdapter 错误文案', (tester) async {
      // 真实 AppProvider 无连接 → getAdapter 返回 null → 走错误分支。
      await _pumpDialog(tester);

      // 应显示对话框标题 + pragmaNoAdapter 英文文案（locale=en）。
      expect(find.text('PRAGMA Explorer'), findsOneWidget);
      expect(find.text('No adapter'), findsOneWidget);
    });

    testWidgets('错误态显示 Retry 按钮 + Close 按钮始终可点', (tester) async {
      await _pumpDialog(tester);

      // 错误态内容区有 Retry（commonRetry），actions 有 Close（commonClose）。
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // 点 Close 关闭对话框。
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('PRAGMA Explorer'), findsNothing);
    });
  });
}
