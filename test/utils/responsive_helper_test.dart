import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/utils/responsive_helper.dart';

void main() {
  group('ResponsiveHelper', () {
    group('getScreenSize', () {
      test('< 600 应为 compact', () {
        expect(ResponsiveHelper.getScreenSize(599), ScreenSize.compact);
        expect(ResponsiveHelper.getScreenSize(0), ScreenSize.compact);
      });

      test('600-899 应为 medium', () {
        expect(ResponsiveHelper.getScreenSize(600), ScreenSize.medium);
        expect(ResponsiveHelper.getScreenSize(899), ScreenSize.medium);
      });

      test('900-1199 应为 expanded', () {
        expect(ResponsiveHelper.getScreenSize(900), ScreenSize.expanded);
        expect(ResponsiveHelper.getScreenSize(1199), ScreenSize.expanded);
      });

      test('>= 1200 应为 large', () {
        expect(ResponsiveHelper.getScreenSize(1200), ScreenSize.large);
        expect(ResponsiveHelper.getScreenSize(2000), ScreenSize.large);
      });
    });

    group('Widget 响应式方法', () {
      testWidgets('isCompact 在小屏幕应为 true', (tester) async {
        tester.view.physicalSize = const Size(500, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                expect(ResponsiveHelper.isCompact(context), isTrue);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });

      testWidgets('isMedium 在中等屏幕应为 true', (tester) async {
        tester.view.physicalSize = const Size(700, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                expect(ResponsiveHelper.isMedium(context), isTrue);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });

      testWidgets('isExpanded 在大屏幕应为 true', (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                expect(ResponsiveHelper.isExpanded(context), isTrue);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });

      testWidgets('isLarge 在超大屏幕应为 true', (tester) async {
        tester.view.physicalSize = const Size(1700, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                expect(ResponsiveHelper.isLarge(context), isTrue);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });

      testWidgets('getSidebarWidth 在不同屏幕宽度下应变化', (tester) async {
        tester.view.physicalSize = const Size(500, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                // compact 屏幕下 sidebar 应为 0
                expect(ResponsiveHelper.getSidebarWidth(context), 0);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });

      testWidgets('getGridCrossAxisCount 应随屏幕宽度增加', (tester) async {
        tester.view.physicalSize = const Size(1700, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                expect(ResponsiveHelper.getGridCrossAxisCount(context), 5);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });

      testWidgets('shouldShowLabels 在中等及以上屏幕应为 true', (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                expect(ResponsiveHelper.shouldShowLabels(context), isTrue);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      });
    });
  });
}
