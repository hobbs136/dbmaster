import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/atoms/typewriter_text.dart';

void main() {
  group('TypewriterText', () {
    testWidgets('renders all text immediately when disabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TypewriterText(
            text: 'Hello World',
            config: TypewriterConfig.disabled,
          ),
        ),
      );

      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('renders partial text with typewriter effect', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TypewriterText(
            text: 'Hello',
            config: TypewriterConfig(charDelay: Duration(milliseconds: 100)),
          ),
        ),
      );

      // Initially should not have full text
      expect(find.text('Hello'), findsNothing);

      // Wait for animation to complete
      await tester.pumpAndSettle(const Duration(milliseconds: 1000));

      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows cursor when typing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TypewriterText(
            text: 'Test',
            config: TypewriterConfig(charDelay: Duration(seconds: 1)),
          ),
        ),
      );

      // Should find the cursor widget
      expect(find.text('|'), findsOneWidget);
    });

    testWidgets('calls onComplete when done', (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TypewriterText(
            text: 'Done',
            config: TypewriterConfig.disabled,
            onComplete: () => completed = true,
          ),
        ),
      );

      await tester.pump();
      expect(completed, isTrue);
    });
  });
}
