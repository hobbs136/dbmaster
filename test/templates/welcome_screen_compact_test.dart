// UIRV-B6 首页紧凑化 + 删重复 Recent（红测先行，条款直译）。
//
// 验收条款 → 用例：
// 1 → compact_card_geometry / single_primary_action_height_32
// 2 → no_recent_connections_block_in_center（含空态卡）
// 3 → recent_files_conditional_render（空态整段不出现 / 非空渲染）
// 4 → callbacks unchanged（tap 触发三回调）
// 5 → focus_order_primary_then_secondary_then_file_rows
// 6 → no_dashboard_or_growth_cards（中央仅 logo/标题/副标题/动作/Recent Files）
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/atoms/app_widgets.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/templates/welcome_screen.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/theme/design_system.dart';

Widget _buildTestWidget({
  AppProvider? provider,
  VoidCallback? onNewConnection,
  VoidCallback? onOpenConnectionManager,
  VoidCallback? onOpenSqliteFile,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('zh')],
    locale: const Locale('en'),
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>(
          create: (_) => provider ?? AppProvider(),
        ),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: Scaffold(
        body: WelcomeScreen(
          key: const ValueKey('welcome_screen'),
          onNewConnection: onNewConnection ?? () {},
          onOpenConnectionManager: onOpenConnectionManager ?? () {},
          onOpenSqliteFile: onOpenSqliteFile ?? () {},
        ),
      ),
    ),
  );
}

/// 条款 3 非空态种子：SQLite 保存连接经 prefs 'saved_connections' 键 +
/// loadSavedConnections 载入（绕开 saveConnection 的网关注册，见
/// workbench_observe_content_test 同款模式）。
Future<AppProvider> _seedSqliteRecentFile(String name) async {
  final server = DbServer(
    id: 'sqlite_seed_1',
    name: name,
    type: DatabaseType.sqlite,
    host: '/tmp/$name.db',
    port: 0,
    lastConnected: DateTime(2026, 10, 25),
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'saved_connections',
    jsonEncode([server.toJson()]),
  );
  final app = AppProvider();
  await app.connection.loadSavedConnections();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // loadSavedConnections 会读 secure storage（凭据）——flutter_tester 中必须
  // mock 平台通道，否则挂起（workbench_observe_content_test 同款）。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          switch (call.method) {
            case 'read':
            case 'write':
            case 'delete':
            case 'deleteAll':
              return null;
            case 'readAll':
              return <String, String>{};
            default:
              return null;
          }
        },
      );

  group('UIRV-B6 WelcomeScreen compact', () {
    tearDown(() {
      // 每用例独立 SharedPreferences 种子由 mock 初始值兜底。
    });

    testWidgets(
      'compact_card_geometry: welcome column width 400 with 24px padding',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget());
        await tester.pumpAndSettle();

        final root = find.byKey(const ValueKey('welcome_screen'));
        final containers = tester
            .widgetList<Container>(
              find.descendant(of: root, matching: find.byType(Container)),
            )
            .toList();

        final card = containers.firstWhere(
          (c) => c.constraints?.maxWidth == AppDesignSystem.inputMaxWidth,
          orElse: () => throw StateError(
            'No welcome card with width ${AppDesignSystem.inputMaxWidth}',
          ),
        );
        expect(card.constraints!.maxWidth, 400);
        expect(card.padding, EdgeInsets.all(AppDesignSystem.space6));
        expect(AppDesignSystem.space6, 24);
      },
    );

    testWidgets(
      'single_primary_action_height_32: New Connection is the only '
      'ElevatedButton and is 32px tall',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget());
        await tester.pumpAndSettle();

        final primaries = find.byType(ElevatedButton);
        expect(primaries, findsOneWidget);

        final sizedBox = tester
            .widgetList<SizedBox>(
              find.ancestor(
                of: primaries,
                matching: find.byType(SizedBox),
              ),
            )
            .where((s) => s.height != null)
            .toList();
        expect(sizedBox.any((s) => s.height == 32), isTrue);
      },
    );

    testWidgets(
      'compact_secondary_pair: Manage Connections and Open SQLite File '
      'are OutlinedButtons in one compact row',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget());
        await tester.pumpAndSettle();

        final secondary = find.byType(OutlinedButton);
        expect(secondary, findsNWidgets(2));

        // 同一水平行：两个次级钮 y 中心一致，且处于主行动之下。
        final manageCenter = tester.getCenter(
          find.widgetWithText(OutlinedButton, 'Manage Connection'),
        );
        final sqliteCenter = tester.getCenter(
          find.widgetWithText(OutlinedButton, 'Open SQLite File…'),
        );
        expect(manageCenter.dy, sqliteCenter.dy);
        final primaryCenter = tester.getCenter(find.byType(ElevatedButton));
        expect(primaryCenter.dy, lessThan(manageCenter.dy));
      },
    );

    testWidgets(
      'no_recent_connections_block_in_center: no chips / Recent heading / '
      'empty-state card even with saved (non-sqlite) connections',
      (tester) async {
        final mysql = DbServer(
          id: 'conn_mysql_seed',
          name: 'mysql-8.0',
          type: DatabaseType.mysql,
          host: '127.0.0.1',
          port: 3306,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'saved_connections',
          jsonEncode([mysql.toJson()]),
        );
        final app = AppProvider();
        await app.connection.loadSavedConnections();

        await tester.pumpWidget(_buildTestWidget(provider: app));
        await tester.pumpAndSettle();

        expect(app.connection.savedConnections, isNotEmpty);
        expect(app.connection.recentSqliteFiles, isEmpty);
        expect(find.byType(ActionChip), findsNothing);
        expect(find.text('Recent'), findsNothing);
        expect(find.text('No recent connections'), findsNothing);
        expect(find.byType(AppEmptyState), findsNothing);
      },
    );

    testWidgets(
      'recent_files_empty_no_section: no Recent Files heading and no '
      '"No recent files" placeholder when recentSqliteFiles is empty',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Recent Files'), findsNothing);
        expect(find.text('No recent files'), findsNothing);
      },
    );

    testWidgets(
      'recent_files_nonempty_renders_rows: heading + file entry when '
      'recentSqliteFiles is non-empty',
      (tester) async {
        final app = await _seedSqliteRecentFile('Chinook_Sqlite');
        await tester.pumpWidget(_buildTestWidget(provider: app));
        await tester.pumpAndSettle();

        expect(find.text('Recent Files'), findsOneWidget);
        expect(find.byType(ActionChip), findsOneWidget);
        expect(find.text('Chinook_Sqlite'), findsOneWidget);
        expect(find.text('No recent files'), findsNothing);
      },
    );

    testWidgets(
      'callbacks_invoked: three callbacks fire with signatures unchanged',
      (tester) async {
        var newConn = 0;
        var manage = 0;
        var openFile = 0;
        await tester.pumpWidget(
          _buildTestWidget(
            onNewConnection: () => newConn++,
            onOpenConnectionManager: () => manage++,
            onOpenSqliteFile: () => openFile++,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Manage Connection'),
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Open SQLite File…'),
        );
        await tester.pump();

        expect(newConn, 1);
        expect(manage, 1);
        expect(openFile, 1);
      },
    );

    testWidgets(
      'focus_order_primary_then_secondary_then_file_rows',
      (tester) async {
        final app = await _seedSqliteRecentFile('Chinook_Sqlite');
        await tester.pumpWidget(_buildTestWidget(provider: app));
        await tester.pumpAndSettle();

        // 初始焦点落到可遍历首节点后，沿 Tab 序收集焦点节点。
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();

        final order = <String>[];
        void record() {
          final focus = FocusManager.instance.primaryFocus;
          final ctx = focus?.context;
          if (ctx == null) return;
          // 沿祖先找带 ValueKey 描述的最近按钮/chip 语义。
          ctx.visitAncestorElements((element) {
            final w = element.widget;
            if (w is ElevatedButton) {
              order.add('primary');
              return false;
            }
            if (w is OutlinedButton) {
              final text = find
                  .descendant(
                    of: find.byWidget(w),
                    matching: find.byType(Text),
                  )
                  .evaluate();
              final label = text.isNotEmpty
                  ? (text.first.widget as Text).data ?? ''
                  : '';
              order.add(label);
              return false;
            }
            if (w is ActionChip) {
              order.add('file');
              return false;
            }
            return true;
          });
        }

        record(); // 首个 Tab 后的焦点
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          record();
        }

        expect(order, [
          'primary',
          'Manage Connection',
          'Open SQLite File…',
          'file',
        ], reason: 'Tab 序 = 主行动 → 次级双钮 → 文件行');
      },
    );

    testWidgets(
      'no_dashboard_or_growth_cards: center column holds only logo, title, '
      'subtitle, actions and conditional Recent Files',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('DbMaster'), findsOneWidget);
        // 无新手向导/增长卡常见文案（硬编码英文文案在 l10n 纪律下不应存在）。
        expect(find.text('Get started'), findsNothing);
        expect(find.text('Quick actions'), findsNothing);
        expect(find.text('What\'s new'), findsNothing);
        // 空态卡整体不存在。
        expect(find.byType(AppEmptyState), findsNothing);
      },
    );
  });
}
