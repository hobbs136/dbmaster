// T04（design §6.3 / AC7.2）：AI 面板执行 SQL 后取消隐式写回。
//
// 改动前：_executeSql 两条落账路径在执行成功后把 sql/connectionId/
// databaseName/executionResults 写入 activeTab 并 bindTabContext——用户
// 编辑器里的既有 tab 被 AI 执行静默覆盖。T04 删除这两组写回语句：
// 结果只在消息流呈现（addAiMessage）+ SnackBar 保留。
//
// 本文件两条用例分别覆盖两条被删路径（真实 SQLite 本地文件库，永久
// 直连豁免网关——功能流程测试纪律见组件 AGENTS.md §5）：
//   1) 普通执行成功路径（SELECT）；
//   2) DDL 确认后绕过路径（DROP TABLE → ConfirmExecuteDialog →
//      DdlConfirmDialog → executeQueryBypassDdl）。
// 断言方向（AC7.2）：执行前后 activeTab 的 sql / connectionId /
// databaseName / executionResults / isContextBound 逐字段一致；消息流
// 落账正常（结果消息 + SnackBar）。
//
// 异步纪律：SQLite 经 sqflite_common_ffi 真实异步完成（后台 isolate），
// 在 FakeAsync 测试 zone 内直接 await 永不完成。处理方式沿用仓内金标准
// test/screens/home/sqlite_open_error_dialog_test.dart 的 waitUntilSettled
// 模式：tester.runAsync 让出真实事件循环轮询完成，再以固定小步 pump
// 推进帧（不用 pumpAndSettle——加载骨架等常驻 repeat 动画会让 settle
// 永不满足）。testWidgets 的 setUp/tearDown 运行在测试 zone 之外的真实
// 事件循环，其中的 await 正常完成；测试 body 内的 sqflite 调用（种子
// 建表 / getTables）须逐个包 runAsync。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connectionId = 't04-sqlite';
  // 与 AI 面板所选连接不同的值——若写回路径残留，这些字段会被覆盖，
  // 用例即红。
  const existingTabSql = 'SELECT 999 AS existing_editor_content';
  const existingTabConnection = 'a-different-connection';
  const existingTabDatabase = 'a_different_database';

  late AppProvider app;
  late String dbPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dbPath =
        '${DateTime.now().millisecondsSinceEpoch}_t04_no_writeback_test.db';
    app = AppProvider();

    // 连真实 SQLite（本地临时文件库；端口 0、无凭据）。
    // setUp 在真实事件循环运行，sqflite 的真实异步在此正常完成。
    final connected = await app.dbService.connect(
      DbServer(
        id: connectionId,
        name: 'T04 SQLite',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
      ),
    );
    expect(connected, isTrue, reason: 'SQLite 测试库连接失败');

    // AI 面板选中该连接（不选库——SQLite 单文件库无需 useDatabase）。
    app.aiPanel.setSelectedConnection(connectionId);

    // 建活动会话（无会话时 addMessage 静默 no-op，消息列表为空）。
    app.aiPanel.sessionManager.createSession();

    // 既有 tab：预置与 AI 面板选择不同的 sql/连接/库，并显式绑定上下文。
    // 注意：无参 addNewTab 在 activeDatabaseName 为 null 时静默不建 tab
    // （SQLite DbServer 无 database），必须显式传参。
    await app.addNewTab(
      connectionId: existingTabConnection,
      databaseName: existingTabDatabase,
      bindContext: true,
    );
    app.updateTabSql(0, existingTabSql);
    expect(app.activeTab, isNotNull, reason: '种子 tab 应已创建');
  });

  tearDown(() async {
    await app.dbService.disconnect();
    final file = File(dbPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  /// 等待条件满足：runAsync 让出真实事件循环（sqflite isolate 往返在
  /// 此完成），固定小步 pump 推进 fake 时间并驱动 UI 重建；60 轮约 3s
  /// 真实时间预算。返回是否满足——不满足时由调用方 expect 显式失败。
  Future<bool> waitUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    return done();
  }

  Future<void> pumpPanel(WidgetTester tester) async {
    final layout = LayoutPreferencesProvider();
    await layout.load();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layout,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: AiPanelWidget()),
        ),
      ),
    );
    // 有界 pump：面板可能存在常驻动画，不用 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 在带代码块的消息上点击执行按钮（AiMessageItem 内 LucideIcons.play）。
  Future<void> tapCodeBlockPlay(WidgetTester tester) async {
    final play = find.descendant(
      of: find.byType(AiMessageItem),
      matching: find.byIcon(LucideIcons.play),
    );
    expect(play, findsOneWidget, reason: '代码块执行按钮应可见');
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 断言 activeTab 五项状态与执行前一致（AC7.2 核心断言）。
  void expectTabUnchanged() {
    final tab = app.activeTab;
    expect(tab, isNotNull);
    expect(tab!.sql, existingTabSql, reason: 'tab sql 不得被 AI 执行覆写');
    expect(
      tab.connectionId,
      existingTabConnection,
      reason: 'tab connectionId 不得被 AI 执行覆写',
    );
    expect(
      tab.databaseName,
      existingTabDatabase,
      reason: 'tab databaseName 不得被 AI 执行覆写',
    );
    expect(
      tab.executionResults,
      isEmpty,
      reason: 'AI 执行结果不得写入 tab 的 executionResults',
    );
    expect(
      tab.isContextBound,
      isTrue,
      reason: 'tab 既有上下文绑定保持不变（不被 AI 执行重绑）',
    );
  }

  /// 调试辅助：把当前消息流压成一行（失败 reason 里展示）。
  String dumpMessages() => app.aiMessages
      .map((m) => '${m.isLoading ? '[L]' : ''}${m.content}')
      .join(' || ');

  testWidgets('SELECT 执行成功后 activeTab 状态前后一致（主路径）', (
    tester,
  ) async {
    const sql = 'SELECT 1 AS t04';
    app.addAiMessage(
      AiMessage(
        id: 't04-seed-select',
        isUser: false,
        content: 'Here is the SQL.',
        code: sql,
        isDangerous: false,
        timestamp: DateTime.now(),
      ),
    );
    await pumpPanel(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tapCodeBlockPlay(tester);
    // 非危险 SQL 且连接不在会话白名单 → 先出 ConfirmExecuteDialog。
    final confirmShown = await waitUntil(
      tester,
      () => find.text(l10n.aiPanelConfirmExecute).evaluate().isNotEmpty,
    );
    expect(
      confirmShown,
      isTrue,
      reason: '执行确认弹窗应在 3s 内出现，messages: ${dumpMessages()}',
    );
    await tester.tap(find.text(l10n.aiPanelConfirmExecute));
    await tester.pump();

    // 等执行真正完成（sqflite 真实异步经 runAsync 轮询完成）：
    // 末消息不再是加载态，且内容含成功文案。
    final successText = l10n.aiPanelExecuteSuccess(1);
    final executed = await waitUntil(
      tester,
      () =>
          app.aiMessages.isNotEmpty &&
          !app.aiMessages.last.isLoading &&
          app.aiMessages.last.content.contains(successText),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(executed, isTrue, reason: '执行应在 3s 内完成，messages: ${dumpMessages()}');

    // AC7.2：tab 状态前后一致。
    expectTabUnchanged();

    // 消息流落账保留：结果消息含成功文案与 SQL。
    final last = app.aiMessages.last;
    final dump = dumpMessages();
    expect(last.isUser, isFalse, reason: 'messages: $dump');
    expect(
      last.content,
      contains('SELECT 1 AS t04'),
      reason: 'messages: $dump',
    );
    expect(
      last.content,
      contains(successText),
      reason: '执行结果应在消息流呈现',
    );

    // SnackBar 保留。
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(l10n.aiPanelSqlExecutionSuccess(1)),
      findsOneWidget,
      reason: '成功 SnackBar 应保留',
    );

    // 推过 SnackBar 自动关闭时长，清掉其 pending Timer 再结束用例。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('DDL 确认执行后 activeTab 状态前后一致（DDL 绕过路径）', (
    tester,
  ) async {
    // SQLite 下 DROP TABLE 会先被 DML 安全守卫以 critical 拦截（抛
    // DmlConfirmationRequiredException，AI 面板不处理该异常类型）。要触
    // 达本用例目标的 DDL 确认路径（DdlConfirmDialog），需关闭 DML 检查、
    // 让 DROP TABLE 落入 DDL 影响分析（DROP_TABLE 无依赖 → high → 需确
    // 认）。这是产品暴露的服务配置面（interceptor.enableDmlCheck 公开可
    // 变，executeQueryBypassDml 内部同款惯用法）；确认后的重执行
    // executeQueryBypassDdl 只关 DDL 分析不关 DML 检查，故须等执行完成
    // 后再恢复标志。
    final wasDmlCheckEnabled = app.dbService.interceptor.enableDmlCheck;
    app.dbService.interceptor.enableDmlCheck = false;

    // 种子表：经 bypassDdl 建（避免种子阶段触发 DDL 确认弹窗）。
    // 测试 body 处于 fakeAsync zone，sqflite 真实异步须走 runAsync。
    await tester.runAsync(() async {
      await app.dbService.executeQueryBypassDdl(
        'CREATE TABLE t04_seed (id INTEGER PRIMARY KEY)',
        connectionId: connectionId,
      );
    });

    const sql = 'DROP TABLE t04_seed';
    app.addAiMessage(
      AiMessage(
        id: 't04-seed-ddl',
        isUser: false,
        content: 'Drop the seed table.',
        code: sql,
        isDangerous: false,
        timestamp: DateTime.now(),
      ),
    );
    await pumpPanel(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tapCodeBlockPlay(tester);
    // 第一道：ConfirmExecuteDialog → 允许本次。
    final confirmShown = await waitUntil(
      tester,
      () => find.text(l10n.aiPanelConfirmExecute).evaluate().isNotEmpty,
    );
    expect(
      confirmShown,
      isTrue,
      reason: '执行确认弹窗应在 3s 内出现，messages: ${dumpMessages()}',
    );
    await tester.tap(find.text(l10n.aiPanelConfirmExecute));
    await tester.pump();

    // 第二道：DROP TABLE 命中 DDL 拦截 → DdlConfirmDialog。
    final ddlDialogShown = await waitUntil(
      tester,
      () => find.text(l10n.ddlExecuteButton).evaluate().isNotEmpty,
    );
    expect(
      ddlDialogShown,
      isTrue,
      reason: 'DDL 确认弹窗应在 3s 内出现，messages: ${dumpMessages()}',
    );
    await tester.tap(find.text(l10n.ddlExecuteButton));
    await tester.pump();

    // 等 bypassDdl 执行真正完成：末消息非加载态且含成功文案（0 行）。
    final successText = l10n.aiPanelExecuteSuccess(0);
    final executed = await waitUntil(
      tester,
      () =>
          app.aiMessages.isNotEmpty &&
          !app.aiMessages.last.isLoading &&
          app.aiMessages.last.content.contains(successText),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(executed, isTrue, reason: '执行应在 3s 内完成，messages: ${dumpMessages()}');

    // AC7.2：DDL 确认后执行同样不写回 tab。
    expectTabUnchanged();

    // 消息流落账保留：结果消息含成功文案。
    final last = app.aiMessages.last;
    expect(last.isUser, isFalse, reason: 'messages: ${dumpMessages()}');
    expect(
      last.content,
      contains(successText),
      reason: 'DDL 执行成功（0 行）应在消息流呈现',
    );

    // SnackBar 保留（0 行）。
    expect(
      find.text(l10n.aiPanelSqlExecutionSuccess(0)),
      findsOneWidget,
      reason: '成功 SnackBar 应保留',
    );

    // 执行已完成，恢复 DML 检查标志。
    app.dbService.interceptor.enableDmlCheck = wasDmlCheckEnabled;

    // 表确实被删除——执行真实生效，而非仅 UI 走过场。
    // （getTables 也是 sqflite 真实异步，在 fakeAsync zone 内须走 runAsync。）
    var tables = <String>[];
    await tester.runAsync(() async {
      tables = await app.dbService.getTables(connectionId: connectionId);
    });
    expect(tables, isNot(contains('t04_seed')));

    // 推过 SnackBar 自动关闭时长，清掉其 pending Timer 再结束用例。
    await tester.pump(const Duration(seconds: 5));
  });
}
