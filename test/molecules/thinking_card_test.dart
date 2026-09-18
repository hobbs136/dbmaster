import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/atoms/typewriter_text.dart';
import 'package:dbmaster/molecules/thinking_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('ThinkingCard', () {
    Widget buildTestWidget(Widget child) {
      return MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );
    }

    testWidgets('renders collapsed by default with preview', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ThinkingCard(
            thinkingProcess: 'Thinking about this...',
            initiallyExpanded: false,
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.brain), findsOneWidget);
      expect(find.text('Thinking about this...'), findsOneWidget);
    });

    testWidgets('expands when tapped', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ThinkingCard(
            thinkingProcess: 'Thinking about this...',
            initiallyExpanded: false,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await tester.pumpAndSettle();

      expect(find.byType(TypewriterText), findsOneWidget);
    });

    testWidgets('shows content when initially expanded', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ThinkingCard(
            thinkingProcess: 'Thinking about this...',
            initiallyExpanded: true,
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(TypewriterText), findsOneWidget);
    });

    testWidgets('shows loading indicator when streaming', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ThinkingCard(
            thinkingProcess: 'Thinking...',
            isStreaming: true,
            initiallyExpanded: false,
            typewriterConfig: TypewriterConfig(enabled: false),
          ),
        ),
      );

      await tester.pump();
      expect(find.byIcon(LucideIcons.brain), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows SelectableText when disabled and expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ThinkingCard(
            thinkingProcess: 'Direct text display',
            initiallyExpanded: true,
            typewriterConfig: TypewriterConfig(enabled: false),
          ),
        ),
      );

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('expand button icon changes when toggled', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ThinkingCard(
            thinkingProcess: 'Test content',
            initiallyExpanded: false,
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronUp), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.chevronUp), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
    });

    testWidgets('AnimatedCrossFade provides smooth expand/collapse', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          const ThinkingCard(
            thinkingProcess: 'Test content',
            initiallyExpanded: false,
          ),
        ),
      );

      expect(find.byType(AnimatedCrossFade), findsOneWidget);
      expect(find.text('Test content'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await tester.pumpAndSettle();

      expect(find.byType(TypewriterText), findsOneWidget);
    });
  });
}
