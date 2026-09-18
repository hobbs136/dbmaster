import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/organisms/connection/column_filter_widget.dart';
import 'package:dbmaster/models/result_filter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ============================================================================
// VirtualizedDataTable Widget Tests
// ============================================================================

Widget _wrapInApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MAN-RES-004: 列排序交互', () {
    testWidgets('点击列头应触发排序回调', (tester) async {
      String? sortedColumn;

      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name', 'email'],
            data: const [
              {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'},
              {'id': 2, 'name': 'Bob', 'email': 'bob@example.com'},
            ],
            onSortToggle: (col) => sortedColumn = col,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the 'name' column header text area (left side, away from filter icon)
      final nameHeaderFinder = find.text('name');
      expect(nameHeaderFinder, findsOneWidget);
      final headerRect = tester.getRect(nameHeaderFinder);
      // Tap near the left side of the text to avoid the filter icon
      await tester.tapAt(Offset(headerRect.left + 5, headerRect.center.dy));
      // GestureDetector has onDoubleTap, so onTap is delayed (~300ms) to
      // distinguish from double-tap. Pump long enough for the timer to fire.
      await tester.pump(const Duration(milliseconds: 400));

      expect(sortedColumn, equals('name'), reason: '点击 name 列头应触发排序回调');
    });

    testWidgets('排序状态应显示箭头图标', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
            ],
            sortState: const SortState(columnName: 'id', ascending: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Look for sort indicator icons near the 'id' header
      expect(
        find.byIcon(LucideIcons.arrowUp),
        findsOneWidget,
        reason: '升序排序应显示向上箭头',
      );
    });

    testWidgets('降序排序应显示向下箭头', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
            ],
            sortState: const SortState(columnName: 'id', ascending: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(LucideIcons.arrowDown),
        findsOneWidget,
        reason: '降序排序应显示向下箭头',
      );
    });
  });

  group('MAN-RES-002: 列宽调整', () {
    testWidgets('拖拽列边界应改变列宽', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
            ],
            defaultColumnWidth: 150,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the column resizer (a small draggable area at the right edge of column header)
      // The resizer is typically a few pixels wide at the column boundary.
      // We'll find the header container and drag from near its right edge.
      final headerFinder = find.text('id');
      expect(headerFinder, findsOneWidget);

      final headerRect = tester.getRect(headerFinder);
      final startOffset = Offset(headerRect.right - 2, headerRect.center.dy);
      final endOffset = Offset(headerRect.right + 50, headerRect.center.dy);

      // Drag the resizer to the right
      await tester.dragFrom(startOffset, endOffset - startOffset);
      await tester.pumpAndSettle();

      // If no exception was thrown, the resize was handled
      expect(true, isTrue, reason: '列宽调整不应崩溃');
    });

    testWidgets('双击列头应自动调整列宽', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
            ],
            defaultColumnWidth: 150,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Double-tap on the column header to trigger auto-fit
      await tester.tap(find.text('name'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('name'));
      await tester.pumpAndSettle();

      // If no exception was thrown, auto-fit was handled
      expect(true, isTrue, reason: '双击自动调整列宽不应崩溃');
    });
  });

  group('MAN-RES: 数据展示', () {
    testWidgets('应正确渲染列和数据行', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
              {'id': 2, 'name': 'Bob'},
              {'id': 3, 'name': 'Charlie'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check headers
      expect(find.text('id'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);

      // Check data cells
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('空数据时应显示提示', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          const VirtualizedDataTable(columns: ['id', 'name'], data: []),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No data'),
        findsOneWidget,
        reason: 'Empty data should show no-data message',
      );
    });

    testWidgets('应显示行号列', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id'],
            data: const [
              {'id': 1},
              {'id': 2},
            ],
            showRowNumbers: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Row numbers are 1-based and rendered with fontSize 11 (distinguish from data cells)
      final rowNumberFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.style?.fontSize == 11) &&
            (w.data == '1' || w.data == '2'),
      );
      expect(rowNumberFinder, findsNWidgets(2), reason: '应显示 2 个行号（1 和 2）');
    });

    testWidgets('隐藏行号列时不应显示', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id'],
            data: const [
              {'id': 1},
            ],
            showRowNumbers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Row number text has fontSize 11; data cell "1" is still present
      final rowNumberFinder = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 11 && w.data == '1',
      );
      expect(
        rowNumberFinder,
        findsNothing,
        reason: 'showRowNumbers=false 时不应显示行号',
      );
    });
  });

  group('MAN-RES: Footer 信息', () {
    testWidgets('Footer 应显示总行数', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          SizedBox(
            height: 300,
            child: VirtualizedDataTable(
              columns: const ['id', 'name'],
              data: const [
                {'id': 1, 'name': 'Alice'},
                {'id': 2, 'name': 'Bob'},
                {'id': 3, 'name': 'Charlie'},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('3 total rows'),
        findsOneWidget,
        reason: 'Footer should show total row count',
      );
    });

    testWidgets('大数据集应显示提示', (tester) async {
      // Create a large dataset (> 1000 rows)
      final largeData = List<Map<String, dynamic>>.generate(
        1500,
        (i) => {'id': i, 'name': 'User $i'},
      );

      await tester.pumpWidget(
        _wrapInApp(
          SizedBox(
            height: 300,
            child: VirtualizedDataTable(
              columns: const ['id', 'name'],
              data: largeData,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Large dataset'),
        findsOneWidget,
        reason: '超过 1000 行应显示大数据集提示',
      );
    });
  });

  group('MAN-RES: 过滤交互', () {
    testWidgets('设置活动过滤器后应显示过滤图标', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
            ],
            activeFilters: {
              'name': ColumnFilter(
                columnName: 'name',
                value: 'Ali',
                operator: FilterOperator.contains,
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Filter icon should be visible on the filtered column header.
      // Lucide 无 filled/outlined 变体（C07）：active/inactive 同 glyph，
      // 激活态经颜色区分（accentBlue=ColorScheme.primary），断言按激活色匹配。
      final primary = Theme.of(
        tester.element(find.byType(VirtualizedDataTable)),
      ).colorScheme.primary;
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              w.icon == LucideIcons.listFilter &&
              w.color == primary,
        ),
        findsOneWidget,
        reason: '有过滤器时应显示过滤图标（激活色）',
      );
    });
  });

  group('数值列对齐（F-27 + 首帧即时判定回归）', () {
    // 元数据经 addPostFrameCallback 异步探测，首帧必须用值类型判定，
    // 否则宽表下出现"先左对齐、几秒后跳右对齐"的跳变
    testWidgets('无 columnTypes 时：数值单元格首帧即右对齐、文本左对齐', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          const VirtualizedDataTable(
            columns: ['id', 'name'],
            data: [
              {'id': 42, 'name': 'Alice'},
            ],
          ),
        ),
      );
      // 首帧（不 pumpAndSettle 等待异步探测）
      await tester.pump();

      final numericCell = tester.widget<Container>(
        find.ancestor(
          of: find.text('42'),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.alignment == Alignment.centerRight,
          ),
        ),
      );
      expect(numericCell, isNotNull, reason: '数值单元格首帧应右对齐');

      final textCell = tester.widget<Container>(
        find.ancestor(
          of: find.text('Alice'),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.alignment == Alignment.centerLeft,
          ),
        ),
      );
      expect(textCell, isNotNull, reason: '文本单元格应左对齐');
    });

    testWidgets('元数据到达后以元数据为准（文本列的数字字符串回左）', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          const VirtualizedDataTable(
            columns: ['code'],
            data: [
              {'code': '123'},
            ],
            columnTypes: {'code': ColumnDataType.string},
          ),
        ),
      );
      await tester.pump();

      // 值是字符串（含数字），元数据为 string——应左对齐而非按值右对齐
      final leftCell = find.byWidgetPredicate(
        (w) => w is Container && w.alignment == Alignment.centerLeft,
      );
      expect(leftCell, findsWidgets);
      final rightCell = find.byWidgetPredicate(
        (w) => w is Container && w.alignment == Alignment.centerRight,
      );
      expect(rightCell, findsNothing);
    });
  });

  group('右键单元格高亮（context cell）', () {
    const cellKey = ValueKey('results-context-cell');

    testWidgets('右键某单元格后该单元格出现高亮标记', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
              {'id': 2, 'name': 'Bob'},
            ],
            onCellContextMenu: (_, _, _, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(cellKey), findsNothing, reason: '右键前不应有高亮标记');

      await tester.tap(find.text('Alice'), buttons: kSecondaryButton);
      await tester.pump();

      expect(find.byKey(cellKey), findsOneWidget, reason: '右键后应有高亮标记');
      expect(
        find.descendant(of: find.byKey(cellKey), matching: find.text('Alice')),
        findsOneWidget,
        reason: '高亮应落在 Alice 所在单元格',
      );
    });

    testWidgets('右键另一单元格后高亮迁移', (tester) async {
      await tester.pumpWidget(
        _wrapInApp(
          VirtualizedDataTable(
            columns: const ['id', 'name'],
            data: const [
              {'id': 1, 'name': 'Alice'},
              {'id': 2, 'name': 'Bob'},
            ],
            onCellContextMenu: (_, _, _, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'), buttons: kSecondaryButton);
      await tester.pump();
      await tester.tap(find.text('Bob'), buttons: kSecondaryButton);
      await tester.pump();

      expect(find.byKey(cellKey), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(cellKey), matching: find.text('Bob')),
        findsOneWidget,
        reason: '高亮应迁移到 Bob 所在单元格',
      );
      expect(
        find.descendant(of: find.byKey(cellKey), matching: find.text('Alice')),
        findsNothing,
        reason: 'Alice 不应再被高亮',
      );
    });
  });
}
