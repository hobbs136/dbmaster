import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/results/pii_export_dialog.dart';
import 'package:dbmaster/services/export_service.dart' show PiiMaskAction;

// ============================================================================
// PiiExportDialog Widget Tests（C22-M2 导入导出向导迁移）
//
// 覆盖三步流程契约：格式选择 → PII 检测（行级脱敏动作）→ 确认导出。
// 断言功能而非样式（AGENTS §5.1）；返回值 PiiExportSelection 是调用方
// ExportService.exportWithMasking 的输入契约。
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 含 email 列（PII 检测命中）+ id/name 列（非 PII）
  List<Map<String, dynamic>> piiData() => [
    {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'},
    {'id': 2, 'name': 'Bob', 'email': 'bob@example.com'},
  ];

  List<Map<String, dynamic>> cleanData() => [
    {'id': 1, 'count': 10},
    {'id': 2, 'count': 20},
  ];

  Future<void> pumpDialog(WidgetTester tester, List<Map<String, dynamic>> data) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Center(
            child: PiiExportDialog(data: data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) {
    return AppLocalizations.of(
      tester.element(find.byType(PiiExportDialog)),
    )!;
  }

  group('PiiExportDialog', () {
    testWidgets('PII-EXP-001: step indicator labels + format chips, CSV default', (tester) async {
      await pumpDialog(tester, cleanData());
      final loc = l10n(tester);

      // 三步标签随行渲染
      expect(find.text(loc.piiExportStepFormat), findsOneWidget);
      expect(find.text(loc.piiExportStepScan), findsOneWidget);
      expect(find.text(loc.piiExportStepConfirm), findsOneWidget);

      // 格式选项三枚；Next 可点（默认 csv）
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('Excel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, loc.exportStepNext), findsOneWidget);
    });

    testWidgets('PII-EXP-002: email column detected with per-column action dropdown', (tester) async {
      await pumpDialog(tester, piiData());
      final loc = l10n(tester);

      await tester.tap(find.text(loc.exportStepNext));
      await tester.pumpAndSettle();

      expect(
        find.text(loc.piiExportDetectedCount(1)),
        findsOneWidget,
      );
      // email 行 + 默认动作下拉（普通 PII 默认 mask）
      expect(find.text('email'), findsOneWidget);
      final dropdown = find.byType(DropdownButton<PiiMaskAction>);
      expect(dropdown, findsOneWidget);
      expect(
        tester.widget<DropdownButton<PiiMaskAction>>(dropdown).value,
        PiiMaskAction.mask,
      );
    });

    testWidgets('PII-EXP-003: clean data shows no-PII state', (tester) async {
      await pumpDialog(tester, cleanData());
      final loc = l10n(tester);

      await tester.tap(find.text(loc.exportStepNext));
      await tester.pumpAndSettle();

      expect(find.text(loc.piiExportNoPiiTitle), findsOneWidget);
      expect(find.text(loc.piiExportNoPiiSubtitle), findsOneWidget);
      expect(find.byType(DropdownButton<PiiMaskAction>), findsNothing);
    });

    testWidgets('PII-EXP-004: full flow returns selection with chosen format and column actions', (tester) async {
      PiiExportSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => FilledButton(
                  onPressed: () async {
                    result = await PiiExportDialog.show(
                      context,
                      data: piiData(),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final loc = l10n(tester);

      // Step1: 切 JSON
      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();

      // Step2: PII 检测（email 默认 mask）
      await tester.tap(find.text(loc.exportStepNext));
      await tester.pumpAndSettle();

      // Step3: 确认汇总 + 导出
      await tester.tap(find.text(loc.exportStepNext));
      await tester.pumpAndSettle();
      expect(find.text(loc.piiExportReadyTitle), findsOneWidget);
      // "Format" 同词命中步骤指示器标签 + 汇总行标签（en 下均为 Format）
      expect(find.text(loc.piiExportSummaryFormat), findsNWidgets(2));
      expect(find.text(loc.piiExportSummaryRows), findsOneWidget);

      // "Export" 与标题 toolbarExport 同词——按按钮类型定位
      await tester.tap(find.widgetWithText(FilledButton, loc.resultsExport));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.format, 'json');
      expect(result!.columnActions['email'], PiiMaskAction.mask);
      expect(result!.columnActions['id'], PiiMaskAction.keep);
      expect(result!.columnActions['name'], PiiMaskAction.keep);
    });
  });
}
