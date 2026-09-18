import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/connection/error_boundary.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/l10n/app_localizations.dart';

void main() {
  group('ErrorBoundary.isTransientConnectionError', () {
    // 回归 — postgres "Connection is closing down"（并发竞态致连接
    // 瞬态关闭）是可恢复错误，不应触发全屏错误屏。
    test('postgres "Connection is closing down" 视为瞬态', () {
      expect(
        ErrorBoundary.isTransientConnectionError(
          Exception('Severity.error Connection is closing down'),
        ),
        isTrue,
      );
    });

    test('被 executeQuery 包装后仍识别', () {
      expect(
        ErrorBoundary.isTransientConnectionError(
          Exception('查询执行失败: Severity.error Connection is closing down'),
        ),
        isTrue,
      );
    });

    test('其它 mid-session 瞬态网络错误识别', () {
      expect(
        ErrorBoundary.isTransientConnectionError(Exception('broken pipe')),
        isTrue,
      );
      expect(
        ErrorBoundary.isTransientConnectionError(
          Exception('Connection reset by peer'),
        ),
        isTrue,
      );
    });

    test('真实业务错误不识别（不误吞，仍触发错误屏）', () {
      expect(
        ErrorBoundary.isTransientConnectionError(
          Exception('permission denied for database new_db'),
        ),
        isFalse,
      );
      expect(
        ErrorBoundary.isTransientConnectionError(
          Exception('database "x" already exists'),
        ),
        isFalse,
      );
      expect(
        ErrorBoundary.isTransientConnectionError(
          Exception('syntax error at or near "CREATE"'),
        ),
        isFalse,
      );
      // connect 失败由连接对话框单独处理，不在此吞
      expect(
        ErrorBoundary.isTransientConnectionError(
          Exception('connection refused'),
        ),
        isFalse,
      );
      expect(
        ErrorBoundary.isTransientConnectionError(StateError('bad state')),
        isFalse,
      );
    });
  });

  // 2026-08-22 灰屏卡死事故回归：ErrorBoundary 包在 MaterialApp 外层，错误屏
  // 接管时没有 Localizations 祖先——原实现 AppLocalizations.of(context)! 空断言
  // 崩溃，错误屏自己挂掉 → release 灰屏无响应。错误屏必须自包含可回退。
  group('ErrorBoundary 错误屏自包含（灰屏事故回归）', () {
    // ErrorBoundary 的 initState 会覆写全局 FlutterError.onError /
    // PlatformDispatcher.onError。flutter_test 的 binding 在**测试体结束**时
    // 即断言 onError 已还原——tearDown/addTearDown 都晚于该检查（会触发
    // "overrode FlutterError.onError" 断言 + 后续用例 did not complete）。
    // 因此捕获还原闭包、在每例体末尾显式调用。
    VoidCallback captureHandlers() {
      final savedOnError = FlutterError.onError;
      final savedPlatformOnError = PlatformDispatcher.instance.onError;
      return () {
        FlutterError.onError = savedOnError;
        PlatformDispatcher.instance.onError = savedPlatformOnError;
      };
    }

    void triggerError() {
      // Exception 非 AssertionError/ArgumentError/StateError/RenderBox——
      // 通过 _isLayoutError 过滤，走 _handleError 全屏替换路径。
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: Exception('gray screen repro'),
          stack: StackTrace.current,
        ),
      );
    }

    testWidgets('无 Localizations 祖先：英文回退渲染，错误屏不崩', (tester) async {
      final restore = captureHandlers();
      try {
        await tester.pumpWidget(const ErrorBoundary(child: SizedBox.shrink()));
        triggerError();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Something went wrong'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        // 渲染文本是 redactSecrets(error.toString()) = "Exception: gray screen
        // repro"——用 textContaining 匹配消息体。
        expect(find.textContaining('gray screen repro'), findsOneWidget);
      } finally {
        restore();
      }
    });

    testWidgets('有 Localizations 祖先：走 l10n 文案', (tester) async {
      final restore = captureHandlers();
      try {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const ErrorBoundary(child: SizedBox.shrink()),
          ),
        );
        triggerError();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('An error occurred'), findsOneWidget);
        expect(find.text('Report Issue'), findsOneWidget);
      } finally {
        restore();
      }
    });

    testWidgets('Retry 恢复子树', (tester) async {
      final restore = captureHandlers();
      try {
        await tester.pumpWidget(
          const ErrorBoundary(child: Text('child-content')),
        );
        triggerError();
        await tester.pump();
        expect(find.text('Something went wrong'), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(find.text('child-content'), findsOneWidget);
        expect(find.text('Something went wrong'), findsNothing);
      } finally {
        restore();
      }
    });
  });

  // AppErrorHandler 语义色按主题分发（F-11/F-15）
  // 注意：必须显式 themeMode——测试平台亮度为 dark 时，
  // MaterialApp 默认 themeMode=system 会忽略 theme: lightTheme 而走暗色
  group('AppErrorHandler 语义色主题分发', () {
    Future<void> pumpWithTrigger(
      WidgetTester tester,
      ThemeMode mode,
      void Function(BuildContext) onTap,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          // 注意：换主题重泵必须带 key——无 key 时 MaterialApp 复用 State，
          // 主题不随 themeMode 更新（flutter_test 陷阱）
          key: ValueKey(mode),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onTap(context),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('trigger'));
      await tester.pump();
    }

    testWidgets('success：亮色用 successLight，暗色用 success', (tester) async {
      await pumpWithTrigger(
        tester,
        ThemeMode.light,
        (c) => AppErrorHandler.showSuccessSnackBar(c, 'ok'),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFF16A34A),
      );

      await pumpWithTrigger(
        tester,
        ThemeMode.dark,
        (c) => AppErrorHandler.showSuccessSnackBar(c, 'ok'),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFF46BF72),
      );
    });

    testWidgets('warning：亮色用 warningLight，暗色用 warning', (tester) async {
      await pumpWithTrigger(
        tester,
        ThemeMode.light,
        (c) => AppErrorHandler.showWarningSnackBar(c, 'warn'),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFFD97706),
      );

      await pumpWithTrigger(
        tester,
        ThemeMode.dark,
        (c) => AppErrorHandler.showWarningSnackBar(c, 'warn'),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFFFF8A30),
      );
    });

    testWidgets('error：亮色用 errorLight，暗色用 error', (tester) async {
      await pumpWithTrigger(
        tester,
        ThemeMode.light,
        (c) => AppErrorHandler.showErrorSnackBar(c, 'err'),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFFDC2626),
      );

      await pumpWithTrigger(
        tester,
        ThemeMode.dark,
        (c) => AppErrorHandler.showErrorSnackBar(c, 'err'),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        const Color(0xFFFF5C5C),
      );
    });
  });

  // ThemeColors 新令牌亮暗分发（accentPurple / codeBlockBg）
  group('ThemeColors 新令牌分发', () {
    Future<ThemeColors> colorsOf(WidgetTester tester, ThemeMode mode) async {
      late ThemeColors colors;
      await tester.pumpWidget(
        MaterialApp(
          // 注意：换主题重泵必须带 key——无 key 时 MaterialApp 复用 State，
          // 主题不随 themeMode 更新（flutter_test 陷阱）
          key: ValueKey(mode),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: Builder(
            builder: (context) {
              colors = context.themeColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return colors;
    }

    // accentPurple 已收敛至 primary（plan §2.3/§8：移除独立紫色 accent）。
    // darkTheme primary = accentPrimaryDark，lightTheme primary = accentPrimary。
    testWidgets(
      'accentPurple：收敛至 primary（暗 accentPrimaryDark / 亮 accentPrimary）',
      (tester) async {
        expect(
          (await colorsOf(tester, ThemeMode.dark)).accentPurple,
          AppDesignSystem.accentPrimaryDark,
        );
        expect(
          (await colorsOf(tester, ThemeMode.light)).accentPurple,
          AppDesignSystem.accentPrimary,
        );
      },
    );

    testWidgets('codeBlockBg：暗 #161616 / 亮 Slate-100（plan §2）', (
      tester,
    ) async {
      expect(
        (await colorsOf(tester, ThemeMode.dark)).codeBlockBg,
        const Color(0xFF161616),
      );
      expect(
        (await colorsOf(tester, ThemeMode.light)).codeBlockBg,
        const Color(0xFFF1F5F9),
      );
    });
  });
}
