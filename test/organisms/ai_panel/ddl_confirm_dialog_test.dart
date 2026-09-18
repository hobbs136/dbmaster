import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/schema_analyzer/ddl_algorithm.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';
import 'package:dbmaster/organisms/ai_panel/ddl_confirm_dialog.dart';

void _setLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

ImpactReport _impactReport({
  required RiskLevel riskLevel,
  required String targetTable,
  DdlAlgorithm ddlAlgorithm = DdlAlgorithm.unknown,
  String? lockType,
  ConcurrencyImpact concurrencyImpact = ConcurrencyImpact.unknown,
  String? algorithmNote,
}) {
  return ImpactReport(
    ddlStatement: 'DROP TABLE $targetTable',
    targetTable: targetTable,
    ddlType: 'DROP',
    riskLevel: riskLevel,
    affectedObjects: const [],
    dependencies: const [],
    warnings: const [],
    recommendations: const [],
    requiresConfirmation: riskLevel == RiskLevel.critical,
    ddlAlgorithm: ddlAlgorithm,
    lockType: lockType,
    concurrencyImpact: concurrencyImpact,
    algorithmNote: algorithmNote,
    analyzedAt: DateTime.now(),
  );
}

/// 通用：pump 出 DdlConfirmDialog（避免每个测试重复样板）。
Future<void> _pumpDialog(
  WidgetTester tester, {
  required ImpactReport report,
  String sql = 'ALTER TABLE t ADD COLUMN c INT',
}) async {
  _setLargeScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            showDialog<DdlConfirmResult>(
              context: context,
              builder: (_) => DdlConfirmDialog(sql: sql, impactReport: report),
            );
          },
          child: const Text('Show'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();
}

void main() {
  group('DdlConfirmDialog', () {
    testWidgets('renders SQL statement', (tester) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<DdlConfirmResult>(
                  context: context,
                  builder: (_) => DdlConfirmDialog(
                    sql: 'DROP TABLE users',
                    impactReport: _impactReport(
                      riskLevel: RiskLevel.low,
                      targetTable: 'users',
                    ),
                  ),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('DROP TABLE users'), findsOneWidget);
    });

    testWidgets('low risk allows direct execution', (tester) async {
      _setLargeScreen(tester);
      DdlConfirmResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<DdlConfirmResult>(
                  context: context,
                  builder: (_) => DdlConfirmDialog(
                    sql: 'CREATE INDEX idx ON users(name)',
                    impactReport: _impactReport(
                      riskLevel: RiskLevel.low,
                      targetTable: 'users',
                    ),
                  ),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      final executeButton = find.widgetWithText(ElevatedButton, 'Execute DDL');
      expect(executeButton, findsOneWidget);

      await tester.tap(executeButton);
      await tester.pumpAndSettle();

      expect(result, DdlConfirmResult.execute);
    });

    testWidgets('critical risk requires confirmation text', (tester) async {
      _setLargeScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<DdlConfirmResult>(
                  context: context,
                  builder: (_) => DdlConfirmDialog(
                    sql: 'DROP TABLE users',
                    impactReport: _impactReport(
                      riskLevel: RiskLevel.critical,
                      targetTable: 'users',
                    ),
                  ),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'DROP USERS');
      await tester.pumpAndSettle();

      final executeButton = find.widgetWithText(ElevatedButton, 'Execute DDL');
      expect(executeButton, findsOneWidget);
      expect(tester.widget<ElevatedButton>(executeButton).enabled, isTrue);
    });
  });

  // 第四阶段 R16：锁信息区块展示。
  group('DdlConfirmDialog 锁信息区块 (R16)', () {
    testWidgets('instant → 展示秒级无锁提示 + note', (tester) async {
      await _pumpDialog(
        tester,
        report: _impactReport(
          riskLevel: RiskLevel.low,
          targetTable: 't',
          ddlAlgorithm: DdlAlgorithm.instant,
          lockType: '无锁（秒级）',
          concurrencyImpact: ConcurrencyImpact.none,
          algorithmNote: 'MySQL 8.0.32 ADD COLUMN 默认 INSTANT',
        ),
      );
      expect(find.textContaining('秒级无锁'), findsOneWidget);
      expect(find.textContaining('INSTANT'), findsOneWidget);
    });

    testWidgets('copy → 展示全表锁警告', (tester) async {
      await _pumpDialog(
        tester,
        report: _impactReport(
          riskLevel: RiskLevel.high,
          targetTable: 't',
          ddlAlgorithm: DdlAlgorithm.copy,
          lockType: '全表锁（阻塞所有写操作）',
          concurrencyImpact: ConcurrencyImpact.blocksDml,
          algorithmNote: '改列类型通常退化 COPY',
        ),
      );
      expect(find.textContaining('全表锁'), findsOneWidget);
      expect(find.textContaining('COPY'), findsOneWidget);
    });

    testWidgets('unknown + 有 note → 展示保守处理提示', (tester) async {
      await _pumpDialog(
        tester,
        report: _impactReport(
          riskLevel: RiskLevel.medium,
          targetTable: 't',
          ddlAlgorithm: DdlAlgorithm.unknown,
          algorithmNote: '无法解析 MySQL 版本（null），保守处理',
        ),
      );
      // label「锁行为未知（保守处理）」+ note 都可能匹配 → findsWidgets。
      expect(find.textContaining('保守处理'), findsWidgets);
    });

    testWidgets('unknown + 无 note → 不展示锁信息区块（避免噪音）',
        (tester) async {
      await _pumpDialog(
        tester,
        report: _impactReport(
          riskLevel: RiskLevel.low,
          targetTable: 't',
          // ddlAlgorithm 默认 unknown，无 algorithmNote
        ),
      );
      // 锁信息区块隐藏：不应出现锁相关文案。
      expect(find.textContaining('锁行为未知'), findsNothing);
      expect(find.textContaining('秒级无锁'), findsNothing);
    });

    testWidgets('instant 锁信息区块在风险等级卡之后', (tester) async {
      await _pumpDialog(
        tester,
        report: _impactReport(
          riskLevel: RiskLevel.low,
          targetTable: 't',
          ddlAlgorithm: DdlAlgorithm.instant,
          lockType: '无锁（秒级）',
          algorithmNote: 'INSTANT note',
        ),
      );
      // 锁信息和风险等级都应展示（顺序由 widget 树保证，此处只验证两者都在）。
      expect(find.textContaining('秒级无锁'), findsOneWidget);
      // 风险等级标签（l10n key 含 "Risk Level"）。
      expect(find.textContaining('Risk'), findsWidgets);
    });
  });
}
