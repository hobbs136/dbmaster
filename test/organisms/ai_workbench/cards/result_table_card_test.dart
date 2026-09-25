// T12 阶段二结果表格卡组件测试（design-ai-workbench §8【三】/§11.1）。
//
// 覆盖：AC5.1 快照（前 N 行）/ AC5.2 上限与截断提示 + 在网格中打开（仅
// M>N）/ AC5.3 M≤N 全量无误导提示 / AC5.5 只读 / AC5.6 空态 / NF1.3 懒构建
// / 错误态渲染分支（左色条 error 语义、triangleAlert、摘要、可折技术详情、
// ≥1 出口、初始展开可折叠）/ 快照行 null 显示惯例。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_snapshot_table.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_table_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/theme/design_system.dart';

Widget _wrap(Widget child, {double width = 720}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    ),
  ),
);

List<Map<String, dynamic>> _rows(int count) => List.generate(count, (i) => {
  'id': i + 1,
  'name': 'row-$i',
  'note': i == 2 ? null : 'note-$i',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = AppLocalizationsEn();

  WorkbenchResultCardPayload payload({required int rowCount, int? rowCountOverride}) {
    return WorkbenchResultCardPayload(
      sql: 'SELECT * FROM t',
      rowCount: rowCountOverride ?? rowCount,
      durationMs: 42,
      columns: const ['id', 'name', 'note'],
      rows: _rows(rowCount),
    );
  }

  /// 展开卡：点击 header 元信息文本（header 行内避开动作钮的稳定热区）。
  Future<void> expand(WidgetTester tester, Finder tapTarget) async {
    await tester.tap(tapTarget);
    await tester.pumpAndSettle();
  }

  group('AC5.1/5.2 快照与上限（M>N）', () {
    testWidgets('折叠元信息 M 行 · ms；展开显示前 N 行快照 + 截断提示 + 在网格中打开', (
      tester,
    ) async {
      // M=25 > N → 快照 take(N)。
      final p = payload(rowCount: 25);
      await tester.pumpWidget(
        _wrap(ResultTableCard(payload: p, onOpenInGrid: (_) {}, onOpenInClassic: (_) {})),
      );
      await tester.pumpAndSettle();

      // 折叠态：元信息 + 成功图标；懒构建（NF1.3）。
      expect(
        find.text(l10n.workbenchResultMeta(p.rowCount, p.durationMs)),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.circleCheckBig), findsOneWidget);
      expect(find.byKey(ResultTableCard.contentKey), findsNothing);

      await expand(tester, find.text(l10n.workbenchResultMeta(25, 42)));

      // 快照表出现，且行数 = N（token 引用断言）。
      expect(find.byType(ResultSnapshotTable), findsOneWidget);
      final table = tester.widget<ResultSnapshotTable>(
        find.byType(ResultSnapshotTable),
      );
      expect(table.rows.length, AppDesignSystem.toolCardSnapshotRows);
      expect(table.columns, p.columns);

      // 截断提示（shown=N, total=M）与表尾「在网格中打开」。
      expect(
        find.text(
          l10n.workbenchResultTruncated(
            AppDesignSystem.toolCardSnapshotRows,
            p.rowCount,
          ),
        ),
        findsOneWidget,
      );
      // marker-expand-mn
      expect(
        find.byKey(ResultTableCard.truncatedFooterKey),
        findsOneWidget,
      );
      expect(find.byKey(ResultTableCard.openInGridButtonKey), findsWidgets);
    });

    testWidgets('在网格中打开回调携带 payload（M>N）', (tester) async {
      final p = payload(rowCount: 25);
      WorkbenchResultCardPayload? gridPayload;
      await tester.pumpWidget(
        _wrap(
          ResultTableCard(payload: p, onOpenInGrid: (x) => gridPayload = x),
        ),
      );
      await tester.pumpAndSettle();
      await expand(tester, find.text(l10n.workbenchResultMeta(25, 42)));

      await tester.tap(find.byKey(ResultTableCard.openInGridButtonKey).last);
      await tester.pump();
      expect(gridPayload, isNotNull);
      expect(gridPayload!.rowCount, 25);
    });

    testWidgets('快照行值显示：map 值转字符串、null → NULL（经典惯例）', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(ResultTableCard(payload: payload(rowCount: 3))));
      await tester.pumpAndSettle();
      await expand(tester, find.text(l10n.workbenchResultMeta(3, 42)));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('row-0'), findsOneWidget);
      expect(find.text('note-2'), findsNothing);
      expect(find.text('NULL'), findsOneWidget, reason: 'null 单元格显示 NULL');
    });
  });

  group('AC5.3 M≤N 全量无误导提示', () {
    testWidgets('全量结果：无截断提示、无在网格中打开按钮', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ResultTableCard(
            payload: payload(rowCount: 3),
            onOpenInGrid: (_) {},
            onOpenInClassic: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expand(tester, find.text(l10n.workbenchResultMeta(3, 42)));

      expect(
        find.byKey(ResultTableCard.truncatedFooterKey),
        findsNothing,
        reason: 'M≤N 不得出现截断提示（无误导）',
      );
      expect(
        find.byKey(ResultTableCard.openInGridButtonKey),
        findsNothing,
        reason: '「在网格中打开」仅 M>N 渲染',
      );
      expect(find.byType(ResultSnapshotTable), findsOneWidget);
      final table = tester.widget<ResultSnapshotTable>(
        find.byType(ResultSnapshotTable),
      );
      expect(table.rows.length, 3, reason: '全量行都在快照内');
    });
  });

  group('AC5.5 只读', () {
    testWidgets('结果卡无任何编辑入口（无 TextField/EditableText）', (tester) async {
      await tester.pumpWidget(
        _wrap(ResultTableCard(payload: payload(rowCount: 25))),
      );
      await tester.pumpAndSettle();
      await expand(tester, find.text(l10n.workbenchResultMeta(25, 42)));

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(DropdownButton<Object>), findsNothing);
    });
  });

  group('AC5.6 空态', () {
    testWidgets('0 行 · ms + 居中提示，无错误图标', (tester) async {
      final p = WorkbenchResultCardPayload(
        sql: 'SELECT * FROM empty_t',
        rowCount: 0,
        durationMs: 12,
        columns: const ['id'],
        rows: const [],
      );
      await tester.pumpWidget(_wrap(ResultTableCard(payload: p)));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.workbenchEmptyResult(0, 12)),
        findsOneWidget,
        reason: '空态元信息 0 行 · 12ms',
      );
      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing,
          reason: '空态无错误图标');
      expect(find.byIcon(LucideIcons.circleAlert), findsNothing);

      await expand(tester, find.text(l10n.workbenchEmptyResult(0, 12)));
      expect(find.byKey(ResultTableCard.emptyHintKey), findsOneWidget);
      expect(find.text(l10n.workbenchEmptyResultHint), findsOneWidget);
      expect(find.byType(ResultSnapshotTable), findsNothing,
          reason: '空结果无快照表');
    });
  });

  group('错误态渲染分支（§8【三】；数据由 T13 产生）', () {
    testWidgets('左色条 error 语义 + triangleAlert + 摘要 + 可折技术详情 + 出口', (
      tester,
    ) async {
      final error = WorkbenchErrorCardPayload(
        sql: 'UPDATE t SET x = 1',
        summary: 'Execution failed: syntax error',
        detail: 'SQLException: near FROM: line 1 col 3',
      );
      var retried = false;
      var opened = false;
      await tester.pumpWidget(
        _wrap(
          ResultTableCard(
            error: error,
            onRetry: (_) => retried = true,
            onOpenErrorInClassic: (_) => opened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始展开（§8：错误卡初始展开）+ 错误图标。
      expect(find.byKey(ResultTableCard.contentKey), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);

      // 摘要（header 省略版 + 内容 14px 全文）。
      expect(
        find.byKey(ResultTableCard.errorSummaryKey),
        findsOneWidget,
      );

      // 可折技术详情（mono 11 codeBlockBg）。
      expect(find.text(l10n.workbenchErrorDetail), findsOneWidget);
      expect(find.text(error.detail!), findsOneWidget);

      // ≥1 出口：重试 + 在经典中打开（回调注入即渲染）。
      expect(find.byKey(ResultTableCard.retryButtonKey), findsOneWidget);
      expect(find.byKey(ResultTableCard.openInClassicButtonKey), findsOneWidget);

      await tester.tap(find.byKey(ResultTableCard.retryButtonKey));
      await tester.pump();
      await tester.tap(find.byKey(ResultTableCard.openInClassicButtonKey));
      await tester.pump();
      expect(retried, isTrue);
      expect(opened, isTrue);

      // 手动折叠仍可用。
      await expand(tester, find.byKey(ResultTableCard.errorSummaryKey));
      expect(find.byKey(ResultTableCard.contentKey), findsNothing);
    });

    testWidgets('技术详情可折叠（点击标题行切换）', (tester) async {
      final error = WorkbenchErrorCardPayload(
        sql: 'SELECT 1',
        summary: 'boom',
        detail: 'stack trace text',
      );
      await tester.pumpWidget(_wrap(ResultTableCard(error: error)));
      await tester.pumpAndSettle();

      expect(find.text('stack trace text'), findsOneWidget);
      await tester.tap(find.text(l10n.workbenchErrorDetail));
      await tester.pumpAndSettle();
      expect(find.text('stack trace text'), findsNothing);
    });

    test('错误卡 payload toJson/fromJson 往返一致', () {
      final error = WorkbenchErrorCardPayload(
        sql: 'UPDATE t SET x = 1',
        summary: 'summary text',
        detail: 'detail text',
      );
      final restored = WorkbenchErrorCardPayload.fromJson(error.toJson());
      expect(restored, isNotNull);
      expect(restored!.sql, error.sql);
      expect(restored.summary, error.summary);
      expect(restored.detail, error.detail);

      // kind 不匹配 / 关键字段畸形 → null（C-2 容错）。
      expect(
        WorkbenchErrorCardPayload.fromJson({'kind': 'sql_card'}),
        isNull,
      );
      expect(
        WorkbenchErrorCardPayload.fromJson({
          'kind': 'error_card',
          'sql': 1,
          'summary': 's',
        }),
        isNull,
      );
    });
  });

  group('折叠交互与懒构建（NF1.3）', () {
    testWidgets('正常卡折叠态不构建快照表', (tester) async {
      await tester.pumpWidget(_wrap(ResultTableCard(payload: payload(rowCount: 25))));
      await tester.pumpAndSettle();

      expect(find.byKey(ResultTableCard.contentKey), findsNothing);
      expect(find.byType(ResultSnapshotTable), findsNothing);
      expect(find.byType(ListView), findsNothing,
          reason: '折叠态连快照滚动视图都不构建');
    });

    testWidgets('Space 在 header 上折叠（键盘同效）', (tester) async {
      await tester.pumpWidget(_wrap(ResultTableCard(payload: payload(rowCount: 3))));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.workbenchResultMeta(3, 42)));
      await tester.pumpAndSettle();
      expect(find.byKey(ResultTableCard.contentKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byKey(ResultTableCard.contentKey), findsNothing);
    });
  });
}
