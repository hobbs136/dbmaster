//! Widget tests for the reports hub dialog (reports-M2 / #29). Mirrors the
//! fake-service pattern of `slow_query_dialog_test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/report_models.dart';
import 'package:dbmaster/organisms/server/reports/reports_dialog.dart';
import 'package:dbmaster/services/reports_api_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _contentV1 = '{"content_version":1,"report_type":"slow_query_weekly",'
    '"window_from":"2026-08-20T12:00:00+00:00","window_to":"2026-08-27T12:00:00+00:00",'
    '"window_truncated":false,'
    '"summary":{"total_samples":2,"distinct_digests":1,"total_ms":5000,'
    '"error_count":0,"cancelled_count":0,"week_over_week_pct":null},'
    '"top":[{"digest":"SELECT SLEEP(?)","db_kind":"mysql","conn_id":"c1",'
    '"count":2,"total_ms":5000,"avg_ms":2500.0,"max_ms":3000,'
    '"sample_sql_text":"SELECT SLEEP(1.5)"}],'
    '"by_connection":[{"conn_id":"c1","db_kind":"mysql","count":2,"total_ms":5000}],'
    '"by_day":[{"date":"2026-08-27","count":2,"total_ms":5000}]}';

Report _report(String id, {String reportType = 'slow_query_weekly'}) => Report(
      id: id,
      taskId: null,
      reportType: reportType,
      title: 'Slow query weekly · 2026-W35',
      content: _contentV1,
      generatedAt: '2026-08-27T12:00:00+00:00',
    );

class _FakeApi extends ReportsApiService {
  final ReportsPage page;
  final GenerateReportResult generateResult;
  final Object? listError;

  _FakeApi({
    List<Report> items = const [],
    this.generateResult = const GenerateReportResult(
        id: 'r1', created: true, reportType: 'slow_query_weekly'),
    this.listError,
  }) : page = ReportsPage(items: items, total: items.length, limit: 50, offset: 0);

  @override
  Future<ReportsPage> listReports({
    String? reportType,
    int limit = 50,
    int offset = 0,
  }) async {
    if (listError != null) throw listError!;
    return page;
  }

  @override
  Future<GenerateReportResult> generateWeekly() async => generateResult;
}

Future<void> _pumpApp(WidgetTester tester, {ReportsApiService? api}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showReportsDialog(context, api: api),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders report cards and opens typed weekly detail', (tester) async {
    await _pumpApp(tester, api: _FakeApi(items: [_report('r1')]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // 列表卡片：类型 chip + 标题 + 生成按钮。
    expect(find.text('slow_query_weekly'), findsOneWidget);
    expect(find.text('Slow query weekly · 2026-W35'), findsOneWidget);
    expect(find.text('Generate weekly report'), findsOneWidget);

    // 点开 → typed 详情（窗口行 + Top 段 + 按天/按连接段 + digest 行复用 M1 键）。
    await tester.tap(find.text('Slow query weekly · 2026-W35'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.textContaining('Window:'), findsOneWidget);
    expect(find.text('Top queries'), findsOneWidget);
    expect(find.text('By day'), findsOneWidget);
    expect(find.text('By connection'), findsOneWidget);
    expect(find.textContaining('SELECT SLEEP(?)'), findsOneWidget);
    // truncated=false → 无截断提示。
    expect(find.textContaining('Partial window'), findsNothing);
    // M3（ADR-0007）：typed 详情带「AI 分析」按钮（回退视图无——不在此断言）。
    expect(find.text('Analyze with AI'), findsOneWidget);
  });

  testWidgets('unknown report type falls back to raw JSON view', (tester) async {
    await _pumpApp(
      tester,
      api: _FakeApi(items: [_report('r1', reportType: 'drift_weekly')]),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await tester.tap(find.text('Slow query weekly · 2026-W35'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.textContaining('Unknown report type'), findsOneWidget);
    // 美化 JSON 里有缩进内容。
    expect(find.textContaining('"content_version"'), findsOneWidget);
  });

  testWidgets('empty state and generate toast', (tester) async {
    await _pumpApp(tester, api: _FakeApi(items: const []));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('No reports'), findsOneWidget);

    // 生成 → snackbar「已生成」→ reload 后出现卡片。
    await tester.tap(find.text('Generate weekly report'));
    await tester.pump();
    expect(find.text('Weekly report generated.'), findsOneWidget);
  });

  testWidgets('load failure renders the error view', (tester) async {
    await _pumpApp(
      tester,
      api: _FakeApi(listError: const ReportsApiException('boom')),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('Failed to load reports.'), findsOneWidget);
    expect(find.byIcon(LucideIcons.cloudOff), findsOneWidget);
  });
}
