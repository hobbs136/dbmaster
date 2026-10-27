// 生产守卫侧栏挂接点分流 + AI 备份胶水冒烟（v0.3.5 UI 批4 T9-B / B-07）。
//
// 验收条款直译：
// - 挂接点分流：production 连接的表右键 Drop/Truncate 触发
//   showProductionGuardDialog（L1，targetObjectName = 表名）；非 production
//   （environment null/testing/development）走既有 type-to-confirm 确认门
//   （UI35-442 widget 级补强；seam 级护栏见
//   test/services/query_execution_interceptor_test.dart）。
// - 确认后链路：guard true → 与既有门通过后同一执行链路（adapter 收到
//   truncate/drop）；false → 不执行（adapter 零调用）。
// - AI 胶水（验收 3 冒烟）：guard 弹窗点 AI 备份 → 经典 dock 开
//   （aiPanelOpen）+ composer 预填 prodGuardAiBackupPrompt({object}) 填充值
//   就位（T9-C 通道；通道级行为已由 ai_panel_prod_guard_prefill_test 的
//   UI35-443/444 覆盖，此处只断言本批接线）。
//
// 审计不旁路（logDmlBlocked → DmlSafetyService → AppLogger.w）为直调既有
// 已测 API，无观察面，不在 widget 层断言（代码走查 + 服务层测试覆盖）。
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';

/// 记录型占位 adapter：只实现 truncate/drop 执行链路触达的方法
/// （isConnected/useDatabase/truncateTable/dropTable），其余 Fake 兜底。
class _RecordingAdapter extends Fake implements DatabaseAdapter {
  final List<String> truncateCalls = [];
  final List<String> dropCalls = [];

  @override
  bool get isConnected => true;

  @override
  Future<void> useDatabase(String dbName) async {}

  @override
  Future<bool> truncateTable(String tableName, {TruncateOptions? options}) async {
    truncateCalls.add(tableName);
    return true;
  }

  @override
  Future<bool> dropTable(String tableName) async {
    dropCalls.add(tableName);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 沿 sidebar_menu_grouping_test 的 harness 形态，扩展 environment 注入；
  /// setActiveConnection 使 dbService 执行链（truncate/drop 默认路由）可达
  /// 记录 adapter。
  Future<(AppProvider, _RecordingAdapter)> pumpTree(
    WidgetTester tester, {
    ConnectionEnvironment? environment,
  }) async {
    final provider = AppProvider();
    final server = DbServer(
      id: 'conn-a',
      type: DatabaseType.mysql,
      name: 'Prod One',
      host: '192.0.2.1',
      port: 3306,
      username: 'root',
      password: 'x',
      environment: environment,
    );
    provider.connection.addSavedServerForTest(server);
    provider.connection.setCurrentServerForTest(server);
    final adapter = _RecordingAdapter();
    provider.connection.dbService.registerConnectedServerForTest(server);
    provider.connection.dbService.registerConnectedAdapterForTest(
      'conn-a',
      adapter,
    );
    provider.connection.dbService.setActiveConnection('conn-a');
    provider.connection.setConnectionDatabasesForTest(
      'conn-a',
      <String>['db_a'],
      <String>['db_a'],
    );
    provider.connection.setCachedDatabaseForTest(
      'conn-a',
      'db_a',
      Database(name: 'db_a', tables: <DbTable>[DbTable(name: 'users')]),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>(
                create: (_) => ThemeProvider()..load(),
              ),
              ChangeNotifierProvider<ServerConnectionProvider>(
                create: (_) => ServerConnectionProvider(),
              ),
            ],
            child: Scaffold(
              body: SidebarTree(
                expandedItems: const {'conn-a', 'conn-a:db_a:tables'},
                expandedDatabases: const {'conn-a:db_a'},
                expandedTables: const {},
                loadingDatabases: const {},
                loadedTableSchemas: const {},
                loadedTableForeignKeys: const {},
                loadingTableSchemas: const {},
                onToggleExpand: (_) {},
                onToggleDatabase: (_) {},
                onToggleTable: (_) {},
                onLoadDatabaseInfo: (a, b) async {},
                onShowConnectionManager: () {},
                onShowSettings: () {},
                onShowERDiagram: () {},
                onShowStoredProcedures: () {},
                onShowTriggers: () {},
                tableRowCounts: const {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (provider, adapter);
  }

  /// 右键表并点菜单项（label 定位），pump 后返回。
  Future<void> rightClickAndTapMenu(
    WidgetTester tester,
    AppLocalizations l10n,
    String menuLabel,
  ) async {
    await tester.tap(find.text('users'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(menuLabel).last);
    await tester.pumpAndSettle();
  }

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('T9-B 侧栏挂接点 production 分流（B-07）', () {
    testWidgets('production + truncate → 生产守卫 L1 弹窗（非既有确认门）', (
      tester,
    ) async {
      await pumpTree(tester, environment: ConnectionEnvironment.production);
      await rightClickAndTapMenu(tester, l10n, l10n.truncate);

      // 生产守卫打开：L1 标题 + SQL 预览（含库名.表名）。
      expect(
        find.text(l10n.prodGuardTitleL1),
        findsOneWidget,
        reason: 'production 连接 truncate 分流到生产守卫弹窗',
      );
      expect(find.text('TRUNCATE TABLE `db_a`.`users`'), findsOneWidget);
      // 既有确认门未出现。
      expect(
        find.text(l10n.truncateTableData),
        findsNothing,
        reason: 'production 分流不得再走既有 TruncateTableConfirmDialog',
      );
    });

    testWidgets('production + drop → 生产守卫 L1 弹窗（非既有确认门）', (
      tester,
    ) async {
      await pumpTree(tester, environment: ConnectionEnvironment.production);
      await rightClickAndTapMenu(tester, l10n, l10n.dropTable);

      expect(
        find.text(l10n.prodGuardTitleL1),
        findsOneWidget,
        reason: 'production 连接 drop 分流到生产守卫弹窗',
      );
      expect(find.text('DROP TABLE `db_a`.`users`'), findsOneWidget);
    });

    testWidgets('production truncate 取消 → 不执行（adapter 零调用）', (
      tester,
    ) async {
      final (_, adapter) = await pumpTree(
        tester,
        environment: ConnectionEnvironment.production,
      );
      await rightClickAndTapMenu(tester, l10n, l10n.truncate);

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(
        adapter.truncateCalls,
        isEmpty,
        reason: 'guard 取消（false）→ 不执行',
      );
      expect(
        find.text(l10n.prodGuardTitleL1),
        findsNothing,
        reason: '弹窗关闭',
      );
    });

    testWidgets('production truncate 确认（表名匹配解锁）→ 走既有执行链路', (
      tester,
    ) async {
      final (_, adapter) = await pumpTree(
        tester,
        environment: ConnectionEnvironment.production,
      );
      await rightClickAndTapMenu(tester, l10n, l10n.truncate);

      // L1：输入目标表名解锁确认钮 → 确认（name 输入框排除 SQL 预览文本，
      // 沿 production_guard_dialog_test._nameFieldFinder 口径）。
      const sqlPreview = 'TRUNCATE TABLE `db_a`.`users`';
      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && (w.controller?.text ?? '') != sqlPreview,
      );
      await tester.enterText(nameField, 'users');
      await tester.pump();
      await tester.tap(find.text(l10n.prodGuardConfirmDrop));
      await tester.pumpAndSettle();

      expect(
        adapter.truncateCalls,
        equals(const ['users']),
        reason: 'guard 确认 true → 与既有门通过后同一执行链路（adapter 收到）',
      );
    });

    testWidgets('非 production（environment null）truncate → 既有确认门不变', (
      tester,
    ) async {
      await pumpTree(tester, environment: null);
      await rightClickAndTapMenu(tester, l10n, l10n.truncate);

      expect(
        find.text(l10n.truncateTableData),
        findsOneWidget,
        reason: '非 production 走既有 TruncateTableConfirmDialog（UI35-442）',
      );
      expect(
        find.text(l10n.prodGuardTitleL1),
        findsNothing,
        reason: '非 production 不得触发生产守卫',
      );
    });

    testWidgets('非 production（environment null）drop → 既有确认门不变', (
      tester,
    ) async {
      await pumpTree(tester, environment: null);
      await rightClickAndTapMenu(tester, l10n, l10n.dropTable);

      // DropTableConfirmDialog 的标题即 l10n.dropTable（T018 既有门）。
      expect(
        find.text(l10n.dropTable),
        findsWidgets,
        reason: '非 production 走既有 DropTableConfirmDialog（UI35-442）',
      );
      expect(find.text(l10n.prodGuardTitleL1), findsNothing);
    });
  });

  group('T9-B AI 备份胶水（验收 3 冒烟）', () {
    testWidgets(
      'production guard 点 AI 备份 → 经典 dock 开 + composer 预填 {object} 填充值',
      (tester) async {
        final (provider, adapter) = await pumpTree(
          tester,
          environment: ConnectionEnvironment.production,
        );
        await rightClickAndTapMenu(tester, l10n, l10n.truncate);

        expect(provider.aiPanel.aiPanelOpen, isFalse, reason: '前置：dock 未开');

        await tester.tap(find.text(l10n.prodGuardAiBackup));
        await tester.pumpAndSettle();

        expect(
          provider.aiPanel.aiPanelOpen,
          isTrue,
          reason: 'AI 分流 → openAiPanel（经典 dock 打开）',
        );
        expect(
          provider.aiPanel.pendingComposerPrefill,
          equals(l10n.prodGuardAiBackupPrompt('users')),
          reason: 'AI 分流 → requestComposerPrefill(prodGuardAiBackupPrompt'
              '({object}=表名))；不自动发送（消息数为空由通道测试覆盖）',
        );
        expect(
          adapter.truncateCalls,
          isEmpty,
          reason: 'AI 分流返回 false → 不执行 truncate',
        );
      },
    );
  });
}
