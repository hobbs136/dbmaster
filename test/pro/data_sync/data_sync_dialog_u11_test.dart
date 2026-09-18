//! U11 (task_usage_loop) — data sync 语义诚实化 widget tests：
//! ① server 后台模式禁用 numeric 分段（切换时强制 time + 提示文案），
//!    不再静默偷换固定 3600s 时间窗口；
//! ② server 模式选 replace 时明示「降级 truncate、目标表先清空」警告；
//!    本地模式 replace 是行级 REPLACE INTO，不弹警告；
//! ③ 取消等待反馈横幅（DataSyncCancellingBanner）渲染。
//!
//! 对话框 initState 会走 AppProvider.connection.loadSavedConnections ——
//! 空 SharedPreferences mock 让它无害地落到空连接列表。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/pro/data_sync/data_sync_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    // Dialog 固定 700x650；默认 800x600 测试表面放不下（溢出异常）。
    await tester.binding.setSurfaceSize(const Size(1200, 950));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>(
        create: (_) => AppProvider(),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DataSyncDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'server mode forces time segmentation and shows the time-only hint',
    (tester) async {
      await pumpDialog(tester);

      // 本地模式默认 numeric：显示「每段大小」输入，无时间单位行、无提示。
      expect(find.text('Segment Size'), findsOneWidget);
      expect(find.text('Unit'), findsNothing);

      await tester.tap(find.text('Server (background)'));
      await tester.pumpAndSettle();

      // 切到 server：numeric 被强制回 time —— 时间单位/间隔行出现，
      // numeric 的「每段大小」输入消失，且给出仅支持时间分段的提示。
      expect(find.text('Segment Size'), findsNothing);
      expect(find.text('Unit'), findsOneWidget);
      expect(
        find.text(
          'Server background mode batches by time window only. Numeric segmentation is available in local mode.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'replace in server mode shows the truncate downgrade warning; local does not',
    (tester) async {
      await pumpDialog(tester);

      // 策略下拉在可滚动区域深处（默认视口外）——先滚到可见再交互。
      // currentLabel = 关闭态下拉显示的当前值（点它展开菜单）。
      Future<void> selectStrategy(
        String currentLabel,
        String targetLabel,
      ) async {
        final closed = find.text(currentLabel).first;
        await tester.ensureVisible(closed);
        await tester.pumpAndSettle();
        await tester.tap(closed);
        await tester.pumpAndSettle();
        await tester.tap(find.text(targetLabel).last);
        await tester.pumpAndSettle();
      }

      // 本地模式选 replace：无警告（本地 replace = REPLACE INTO 行级语义）。
      await selectStrategy('Append (ignore conflicts)', 'Replace');
      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);

      // 切到 server 模式：警告出现（提交端会降级 truncate，先清空目标表）。
      await tester.ensureVisible(find.text('Server (background)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Server (background)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no REPLACE INTO'), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);

      // 换回 append：警告消失（非破坏性策略不误伤）。
      await selectStrategy('Replace', 'Append (ignore conflicts)');
      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
    },
  );

  testWidgets('cancelling banner renders the waiting feedback text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Center(child: DataSyncCancellingBanner())),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('Cancelling — waiting for the current batch to finish…'),
      findsOneWidget,
    );
  });
}
