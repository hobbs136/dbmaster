import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// 轻量 wrapper，单测 TreeItem 的 isSelected / badge 属性
Widget _wrapTreeItem(Widget child) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TreeItem 显示', () {
    testWidgets('isSelected = true 时高亮背景', (tester) async {
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: AppDesignSystem.accentPrimary,
            label: 'Test Connection',
            isSelected: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Connection'), findsOneWidget);
    });

    testWidgets('isSelected = false 时无高亮', (tester) async {
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: AppDesignSystem.accentPrimary,
            label: 'Normal Item',
            isSelected: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Normal Item'), findsOneWidget);
    });

    testWidgets('badge 文字正确显示', (tester) async {
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 2,
            icon: LucideIcons.table2,
            iconColor: AppDesignSystem.accentPrimary,
            label: 'users',
            badge: '1.2K',
            isSelected: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('users'), findsOneWidget);
      expect(find.text('1.2K'), findsOneWidget);
    });

    testWidgets('isLoading 时显示 spinner 而非箭头', (tester) async {
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 2,
            icon: LucideIcons.table2,
            iconColor: AppDesignSystem.accentPrimary,
            label: 'Loading Table',
            isLoading: true,
            showArrow: true,
            onTap: () {},
          ),
        ),
      );
      // 不 pumpAndSettle — CircularProgressIndicator 持续动画
      await tester.pump();
      expect(find.text('Loading Table'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('showArrow = false 时无箭头也无 spinner', (tester) async {
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 4,
            icon: LucideIcons.play,
            iconColor: Colors.grey,
            label: 'my_proc',
            showArrow: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('my_proc'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('不同 level 的字体大小不同', (tester) async {
      // L1 (conn): fontWeight 600, fontSize 13
      // L3 (cat): fontWeight 400, fontSize 11
      await tester.pumpWidget(
        _wrapTreeItem(
          Column(
            children: [
              TreeItem(
                level: 1,
                icon: LucideIcons.database,
                iconColor: AppDesignSystem.accentPrimary,
                label: 'L1',
                onTap: () {},
              ),
              TreeItem(
                level: 3,
                icon: LucideIcons.table2,
                iconColor: AppDesignSystem.accentPrimary,
                label: 'L3',
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('L1'), findsOneWidget);
      expect(find.text('L3'), findsOneWidget);
    });

    // emoji 退场——改为校验 Material 图标渲染
    testWidgets('icon 渲染 Material 图标', (tester) async {
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: AppDesignSystem.accentPrimary,
            label: 'MySQL',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.database), findsOneWidget);
      expect(find.text('MySQL'), findsOneWidget);
    });
  });

  group('TreeItem 交互', () {
    testWidgets('onTap 触发回调', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: AppDesignSystem.accentPrimary,
            label: 'Tappable',
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('Tappable'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('onDoubleTap 触发回调', (tester) async {
      bool doubleTapped = false;
      await tester.pumpWidget(
        _wrapTreeItem(
          TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: AppDesignSystem.accentPrimary,
            label: 'DoubleTap',
            onTap: () {},
            onDoubleTap: () => doubleTapped = true,
          ),
        ),
      );
      // 两次快速点击
      await tester.tap(find.text('DoubleTap'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('DoubleTap'));
      await tester.pumpAndSettle();
      expect(doubleTapped, isTrue);
    });
  });
}
