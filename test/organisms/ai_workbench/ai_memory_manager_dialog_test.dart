//! T3 · AI 记忆管理对话框 widget 测试（AI-MEM-010/011）。
//!
//! 先例 `test/organisms/server/mcp_token_dialog_test.dart`：MaterialApp
//! (en locale) + 按钮触发 showXxxDialog helper。只断言结构（find.text /
//! find.byTooltip / find.byType），禁止视觉样式断言。种子数据经
//! AiMemoryService 单例写入（flush 落盘后由对话框 initialize 加载）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_memory_item.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_memory_manager_dialog.dart';
import 'package:dbmaster/services/ai/ai_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiMemoryService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiMemoryService().resetForTesting();
    service = AiMemoryService();
  });

  tearDown(() {
    // 取消在途防抖 Timer，避免跨用例迟到落盘。
    service.resetForTesting();
  });

  /// 种子数据并落盘（在 pumpWidget 前完成，无 pending Timer）。
  Future<void> seed() async {
    await service.initialize();
    await service.add(
      scope: AiMemoryScope.global,
      subject: 'orders.status',
      content: 'Order status flow is pending → paid → shipped.',
    );
    await service.add(
      scope: AiMemoryScope.connection,
      connectionId: 'conn_x',
      source: AiMemorySource.agent,
      content: 'Column updated_at is maintained by a trigger.',
    );
    await service.flush();
  }

  Future<void> pumpHost(WidgetTester tester, {String? connectionId}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAiMemoryManagerDialog(
                context,
                connectionId: connectionId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('未选连接：标题 + 全局/连接分区 + 连接分区引导空态（AI-MEM-010）', (tester) async {
    await pumpHost(tester);

    expect(find.text('AI Memory'), findsOneWidget);
    expect(find.text('Global'), findsOneWidget);
    expect(find.text('This connection'), findsOneWidget);
    expect(
      find.text('Select a connection to manage its memories'),
      findsOneWidget,
    );
    // 空态。
    expect(find.text('No memories yet'), findsOneWidget);
  });

  testWidgets('已选连接：渲染分区条目（subject + content + 来源）（AI-MEM-010）', (
    tester,
  ) async {
    await seed();
    await pumpHost(tester, connectionId: 'conn_x');

    // 全局条目（manual）。
    expect(find.text('orders.status'), findsOneWidget);
    expect(find.textContaining('pending → paid → shipped'), findsOneWidget);
    expect(find.textContaining('Manual'), findsOneWidget); // 来源标签 · 时间
    // 连接条目（agent）。
    expect(find.text('No subject'), findsOneWidget);
    expect(find.textContaining('maintained by a trigger'), findsOneWidget);
    expect(find.textContaining('Agent'), findsOneWidget); // 来源标签 · 时间
    // 连接分区非空，无空态文案（全局分区有条目，同样无空态）。
    expect(find.text('No memories yet'), findsNothing);
    expect(
      find.text('Select a connection to manage its memories'),
      findsNothing,
    );
  });

  testWidgets('新增流：编辑器保存后列表刷新（AI-MEM-011）', (tester) async {
    await pumpHost(tester, connectionId: 'conn_x');

    // 全局分区头的新增按钮（此时连接分区也有一个，取第一个 = 全局）。
    await tester.tap(find.byTooltip('Add memory').first);
    await tester.pumpAndSettle();

    // 编辑器：subject + content 两个输入框。
    expect(find.text('Add memory'), findsOneWidget); // 编辑器标题
    await tester.enterText(find.byType(TextField).at(0), 'payments.retry');
    await tester.enterText(
      find.byType(TextField).at(1),
      'Payments retry with exponential backoff.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // 列表刷新，新条目可见。
    expect(find.text('payments.retry'), findsOneWidget);
    expect(find.textContaining('exponential backoff'), findsOneWidget);

    // R-1 作用域断言：连接在场时点「全局」分区 + 必须落全局作用域——
    // listGlobal() +1，listForConnection 不变（连接分区仍为空态）。
    expect(service.listGlobal(), hasLength(1));
    expect(service.listGlobal().single.subject, 'payments.retry');
    expect(service.listForConnection('conn_x'), isEmpty);
    expect(find.text('No memories yet'), findsOneWidget); // 连接分区空态

    // 冲掉防抖落盘 Timer（避免 testWidgets 尾部 pending timer 报错）。
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  });

  testWidgets('新增流：连接分区 + 落连接作用域，全局不变（AI-MEM-011）', (tester) async {
    await pumpHost(tester, connectionId: 'conn_x');

    // 连接分区头的新增按钮（最后一个 = 连接分区）。
    await tester.tap(find.byTooltip('Add memory').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'conn.charset');
    await tester.enterText(find.byType(TextField).at(1), 'Use utf8mb4 everywhere.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // R-1 作用域断言：连接分区 + 落连接作用域，全局分区不受影响。
    expect(service.listForConnection('conn_x'), hasLength(1));
    expect(service.listForConnection('conn_x').single.subject, 'conn.charset');
    expect(service.listGlobal(), isEmpty);
    expect(find.text('conn.charset'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  });

  testWidgets('新增流：空内容保存被拦截（AI-MEM-011）', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.byTooltip('Add memory'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // 校验错误文案出现，编辑器未关闭。
    expect(find.text('Content cannot be empty'), findsOneWidget);
    expect(find.text('Add memory'), findsOneWidget);
  });

  testWidgets('编辑流：编辑器预填并保存更新（AI-MEM-011）', (tester) async {
    await seed();
    await pumpHost(tester, connectionId: 'conn_x');

    await tester.tap(find.byTooltip('Edit memory').first);
    await tester.pumpAndSettle();

    expect(find.text('Edit memory'), findsOneWidget); // 编辑器标题
    // 预填校验：subject 输入框含种子 subject。
    final subjectField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(subjectField.controller?.text, 'orders.status');

    await tester.enterText(
      find.byType(TextField).at(1),
      'Updated flow: pending → paid.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Updated flow'), findsOneWidget);
    expect(find.textContaining('pending → paid → shipped'), findsNothing);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  });

  testWidgets('删除流：确认 AlertDialog 后条目移除（AI-MEM-011）', (tester) async {
    await seed();
    await pumpHost(tester, connectionId: 'conn_x');

    await tester.tap(find.byTooltip('Delete memory').first);
    await tester.pumpAndSettle();

    // 确认框（先例 mcp_token_dialog._revoke）。
    expect(find.text('Delete this memory?'), findsOneWidget);
    await tester.tap(find.text('Delete memory'));
    await tester.pumpAndSettle();

    // 全局条目移除，全局分区回到空态。
    expect(find.text('orders.status'), findsNothing);
    expect(find.textContaining('pending → paid → shipped'), findsNothing);
    expect(find.text('No memories yet'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  });
}
