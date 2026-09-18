import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/dialogs/execution_gate_dialog.dart';
import 'package:dbmaster/services/safety/safety_review_service.dart';
import 'package:dbmaster/theme/app_theme.dart';

void main() {
  group('QueryEditorWidgetState.appendSqlText', () {
    test('appends SQL to empty text without separator', () {
      expect(
        QueryEditorWidgetState.appendSqlText('', 'SELECT * FROM users'),
        'SELECT * FROM users',
      );
    });

    test('inserts newline separator when editor is not empty', () {
      expect(
        QueryEditorWidgetState.appendSqlText('SELECT 1', 'SELECT 2'),
        'SELECT 1\nSELECT 2',
      );
    });

    test('does not insert separator when editor contains only whitespace', () {
      expect(
        QueryEditorWidgetState.appendSqlText('   ', 'SELECT 1'),
        '   SELECT 1',
      );
    });
  });

  // U13：ClickHouse adapter 事务是基类 no-op，UI 不得显示事务按钮（防假回滚）。
  group('QueryEditorWidgetState.supportsTransactionFor', () {
    test('returns true for adapters with real transactions', () {
      for (final type in [
        DatabaseType.mysql,
        DatabaseType.postgresql,
        DatabaseType.sqlite,
        DatabaseType.doris,
        DatabaseType.sqlserver,
      ]) {
        expect(
          QueryEditorWidgetState.supportsTransactionFor(type),
          isTrue,
          reason: '$type should support transactions',
        );
      }
    });

    test('returns false for ClickHouse (no-op transaction adapter)', () {
      expect(
        QueryEditorWidgetState.supportsTransactionFor(DatabaseType.clickhouse),
        isFalse,
      );
    });

    test('returns false for non-SQL and unknown types', () {
      for (final type in [
        DatabaseType.mongodb,
        DatabaseType.redis,
        DatabaseType.tdengine,
      ]) {
        expect(
          QueryEditorWidgetState.supportsTransactionFor(type),
          isFalse,
          reason: '$type should not support transactions',
        );
      }
      expect(QueryEditorWidgetState.supportsTransactionFor(null), isFalse);
    });
  });

  // T13 · D2 fail-closed（2026-08-20 拍板：仅写类）：编辑器执行门整体
  // 异常 catch 对写类 SQL 注入 review_degraded_fail_closed（high）并走
  // 既有 ExecutionGateDialog 弹窗。_runSafetyReview 为私有方法且依赖
  // 真实 MySQL 连接上下文（无法在 widget 测试注入审查异常），此处直接
  // 验证其 catch 路径的两个构件：SafetyReviewService 的判定/工厂函数
  // （单测见 safety_review_fail_closed_test.dart）+ 该 finding 经
  // ExecutionGateDialog 展示后的用户决策路径（知情继续 / 取消）。
  // C22 M2：弹窗文案 l10n 化（默认 en locale），断言经 AppLocalizations。
  group('T13 fail-closed：review_degraded_fail_closed 经执行门展示', () {
    Future<ExecutionGateAction? Function()> pumpGateAndOpen(
      WidgetTester tester,
    ) async {
      ExecutionGateAction? action;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  action = await ExecutionGateDialog.show(
                    context,
                    findings: [SafetyReviewService.degradedFailClosedFinding()],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // 返回取值闭包（弹窗未决策时为 null——不能断言非空再取）。
      return () => action;
    }

    testWidgets('严重度徽章 + 中文标题/描述渲染，无建议按钮（单语句形态）', (tester) async {
      final getAction = await pumpGateAndOpen(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ExecutionGateDialog)),
      )!;

      // finding 卡片：严重度徽章（C22 M2：l10n 标签）+ 标题，描述另起。
      expect(find.text(l10n.safetySeverityHigh), findsOneWidget);
      expect(find.textContaining('安全审查降级'), findsOneWidget);
      expect(find.textContaining('知情后再决定'), findsOneWidget);
      // 无 suggestion → 不出现「采用全部建议」；单语句 → 无「跳过高危」。
      expect(find.text(l10n.gateApplySuggestions), findsNothing);
      expect(find.textContaining(l10n.gateSkipHighRisk(0, 0)), findsNothing);
      // 弹窗仍打开（未做任何决策）。
      expect(getAction(), isNull);

      // 关闭弹窗，避免泄漏 Warning。
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(getAction(), ExecutionGateAction.cancel);
    });

    testWidgets('用户「知情继续执行」→ proceed（fail-closed 非硬阻断）', (tester) async {
      final getAction = await pumpGateAndOpen(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ExecutionGateDialog)),
      )!;

      await tester.tap(find.text(l10n.gateProceed));
      await tester.pumpAndSettle();

      expect(getAction(), ExecutionGateAction.proceed);
    });

    testWidgets('用户取消 → cancel（默认不执行）', (tester) async {
      final getAction = await pumpGateAndOpen(tester);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ExecutionGateDialog)),
      )!;

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(getAction(), ExecutionGateAction.cancel);
    });
  });
}
