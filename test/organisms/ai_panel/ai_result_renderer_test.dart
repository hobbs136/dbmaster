import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/atoms/sql_code_block.dart';
import 'package:dbmaster/organisms/ai_panel/ai_result_renderer.dart';
import 'package:dbmaster/plugins/ai_skill_plugin.dart';
import 'package:dbmaster/theme/app_theme.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('AiResultRenderer', () {
    testWidgets('renders SQL code block', (tester) async {
      const sql = '```sql\nSELECT * FROM users;\n```';
      await tester.pumpWidget(_wrap(const AiResultRenderer(content: sql)));
      await tester.pumpAndSettle();

      expect(find.byType(SqlCodeBlock), findsOneWidget);
    });

    testWidgets('renders JSON code block', (tester) async {
      const json = '{"name":"test","value":1}';
      await tester.pumpWidget(_wrap(const AiResultRenderer(content: json)));
      await tester.pumpAndSettle();

      expect(find.byType(SqlCodeBlock), findsOneWidget);
    });

    testWidgets('renders plain markdown text', (tester) async {
      const text = 'This is a **bold** result.';
      await tester.pumpWidget(_wrap(const AiResultRenderer(content: text)));
      await tester.pumpAndSettle();

      expect(find.byType(SqlCodeBlock), findsNothing);
      expect(find.textContaining('This is a'), findsOneWidget);
    });
  });

  group('AiResultRenderer · C23 envelope 分发', () {
    testWidgets('envelope sql：无围栏裸 SQL 直接渲染代码块', (tester) async {
      const sql = 'SELECT * FROM users WHERE id = 1;';
      await tester.pumpWidget(
        _wrap(
          const AiResultRenderer(
            content: sql,
            envelopeType: AiSkillEnvelopeType.sql,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlCodeBlock), findsOneWidget);
    });

    testWidgets('envelope json：走代码块渲染（格式化后渲染）', (tester) async {
      const json = '{"name":"test","value":1}';
      await tester.pumpWidget(
        _wrap(
          const AiResultRenderer(
            content: json,
            envelopeType: AiSkillEnvelopeType.json,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 分发语义：envelope json → 代码块路径（SqlCodeBlock 富文本 span
      // 逐 token 渲染，不做整串文本断言）
      expect(find.byType(SqlCodeBlock), findsOneWidget);
    });

    testWidgets('envelope diff：+/- 行渲染且不进 SqlCodeBlock', (tester) async {
      const diff = '@@ -1,2 +1,3 @@\n'
          ' context line\n'
          '-removed line\n'
          '+added line';
      await tester.pumpWidget(
        _wrap(
          const AiResultRenderer(
            content: diff,
            envelopeType: AiSkillEnvelopeType.diff,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlCodeBlock), findsNothing);
      expect(find.text('-removed line'), findsOneWidget);
      expect(find.text('+added line'), findsOneWidget);
      expect(find.textContaining('@@'), findsOneWidget);
    });

    testWidgets('envelope markdown：走 markdown 渲染', (tester) async {
      const text = 'Review conclusion: **ok**';
      await tester.pumpWidget(
        _wrap(
          const AiResultRenderer(
            content: text,
            envelopeType: AiSkillEnvelopeType.markdown,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SqlCodeBlock), findsNothing);
      expect(find.textContaining('Review conclusion'), findsOneWidget);
    });

    testWidgets('无 envelope：含围栏 SQL 仍走启发式（存量行为）', (tester) async {
      const sql = '```sql\nSELECT 1;\n```';
      await tester.pumpWidget(_wrap(const AiResultRenderer(content: sql)));
      await tester.pumpAndSettle();

      expect(find.byType(SqlCodeBlock), findsOneWidget);
    });
  });
}
