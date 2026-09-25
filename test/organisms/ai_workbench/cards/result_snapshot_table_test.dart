/// ResultSnapshotTable 组件测试（T12 阶段一）。
///
/// 覆盖面（任务书 T12 阶段一）：N 行渲染（虚拟化有界断言）、列数多/少边界、
/// 空行、长文本 ellipsis、只读断言（无交互回调面/无 TextField/无 GestureDetector）。
/// 另锁性能不变式（T01 复跑 gate 载体）：itemExtent 26、行不 keepAlive、
/// 无水平滚动视图/Scrollbar、表头固定不随滚动。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_snapshot_table.dart';
import 'package:dbmaster/theme/design_system.dart';

/// 匹配已构建的数据行（行带 ValueKey('result_snapshot_row_$index')）。
final Finder _builtRows = find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(
        'result_snapshot_row_',
      ),
);

List<List<String>> _rows(int count, {int cols = 3}) =>
    List.generate(count, (r) => List.generate(cols, (c) => 'r${r}c$c'));

Widget _harness({
  required List<String> columns,
  required List<List<String>> rows,
  double? height,
  double width = 600,
}) {
  Widget table = ResultSnapshotTable(columns: columns, rows: rows);
  if (height != null) {
    table = SizedBox(height: height, child: table);
  }
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: table),
      ),
    ),
  );
}

void main() {
  group('ResultSnapshotTable', () {
    testWidgets('渲染表头与数据行（基础路径）', (tester) async {
      await tester.pumpWidget(
        _harness(columns: const ['id', 'name', 'value'], rows: _rows(5)),
      );

      expect(find.text('id'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('value'), findsOneWidget);
      expect(find.text('r0c0'), findsOneWidget);
      expect(find.text('r4c2'), findsOneWidget);
      expect(_builtRows.evaluate().length, 5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('50 行虚拟化：已构建行数有界，屏外行不构建', (tester) async {
      await tester.pumpWidget(
        _harness(columns: const ['c0', 'c1', 'c2'], rows: _rows(50)),
      );

      // 有界断言：仅构建视口 + cacheExtent 内的行，远小于 50。
      final built = _builtRows.evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(50));
      // 首行在视口内、末行不在。
      expect(find.text('r0c0'), findsOneWidget);
      expect(find.text('r49c0'), findsNothing);
      expect(tester.takeException(), isNull);

      // 性能不变式锁定（gate 载体）：itemExtent 固定行高（产物为定长
      // SliverFixedExtentList）、行不保活/无逐行重绘边界。
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.itemExtent, ResultSnapshotTable.rowHeight);
      final delegate = tester
          .widget<SliverFixedExtentList>(find.byType(SliverFixedExtentList))
          .delegate;
      expect(delegate, isA<SliverChildBuilderDelegate>());
      final builderDelegate = delegate as SliverChildBuilderDelegate;
      expect(builderDelegate.addAutomaticKeepAlives, isFalse);
      expect(builderDelegate.addRepaintBoundaries, isFalse);
      expect(
        find.descendant(
          of: find.byType(ResultSnapshotTable),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('滚动揭示后续行，表头固定不随滚动', (tester) async {
      await tester.pumpWidget(
        _harness(columns: const ['c0', 'c1', 'c2'], rows: _rows(50)),
      );

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();

      // 末行进入视口、首行被虚拟化换出，表头仍固定可见。
      expect(find.text('r49c0'), findsOneWidget);
      expect(find.text('r0c0'), findsNothing);
      expect(find.text('c0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('列数多（40 列）：等分压缩 + ellipsis，无异常', (tester) async {
      final columns = List.generate(40, (i) => 'col_$i');
      await tester.pumpWidget(
        _harness(columns: columns, rows: _rows(3, cols: 40)),
      );

      expect(find.text('col_0'), findsOneWidget);
      expect(find.text('col_39'), findsOneWidget);
      expect(find.text('r0c39'), findsOneWidget);
      // 压缩后表头/单元格均按 ellipsis 截断（不溢出布局）。
      expect(
        tester.widget<Text>(find.text('col_0')).overflow,
        TextOverflow.ellipsis,
      );
      expect(
        tester.widget<Text>(find.text('r0c39')).overflow,
        TextOverflow.ellipsis,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('列数少（1 列）边界：整宽渲染无异常', (tester) async {
      await tester.pumpWidget(
        _harness(columns: const ['only'], rows: _rows(4, cols: 1)),
      );

      expect(find.text('only'), findsOneWidget);
      expect(find.text('r0c0'), findsOneWidget);
      expect(find.text('r3c0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空行数据（0 行）：仅表头，无数据行', (tester) async {
      await tester.pumpWidget(
        _harness(columns: const ['id', 'name'], rows: const []),
      );

      expect(find.text('id'), findsOneWidget);
      expect(_builtRows, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空字符串行与短行（防御）：不越界不异常', (tester) async {
      await tester.pumpWidget(
        _harness(
          columns: const ['id', 'name', 'value'],
          rows: const [
            ['', '', ''],
            ['only'],
          ],
        ),
      );

      expect(_builtRows.evaluate().length, 2);
      expect(find.text('only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('长文本单元格按 ellipsis 截断', (tester) async {
      final longText = 'x' * 500;
      await tester.pumpWidget(
        _harness(
          columns: const ['id'],
          rows: [
            [longText],
          ],
        ),
      );

      final text = tester.widget<Text>(find.text(longText));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('只读断言：无任何编辑/交互入口', (tester) async {
      await tester.pumpWidget(
        _harness(columns: const ['id', 'name'], rows: _rows(10)),
      );

      final table = find.byType(ResultSnapshotTable);
      expect(
        find.descendant(of: table, matching: find.byType(TextField)),
        findsNothing,
      );
      expect(
        find.descendant(of: table, matching: find.byType(EditableText)),
        findsNothing,
      );
      expect(
        find.descendant(of: table, matching: find.byType(GestureDetector)),
        findsNothing,
      );
      expect(
        find.descendant(of: table, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.descendant(of: table, matching: find.byType(MouseRegion)),
        findsNothing,
      );
      // 无滚动条、无水平滚动视图（对比 VirtualizedDataTable 的多滚动条脚手架）。
      expect(
        find.descendant(of: table, matching: find.byType(Scrollbar)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: table,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });

    testWidgets('高度上限消费 toolCardContentMaxHeight token', (tester) async {
      // 父约束 600（松约束）→ 取 token 360。
      await tester.pumpWidget(
        _harness(columns: const ['id'], rows: _rows(50, cols: 1)),
      );

      expect(
        tester.getSize(find.byType(ResultSnapshotTable)),
        Size(600.0, AppDesignSystem.toolCardContentMaxHeight),
      );
    });

    testWidgets('父高度更小时取父约束（不撑破布局）', (tester) async {
      await tester.pumpWidget(
        _harness(columns: const ['id'], rows: _rows(50, cols: 1), height: 100),
      );

      expect(
        tester.getSize(find.byType(ResultSnapshotTable)),
        const Size(600.0, 100.0),
      );
      expect(find.text('r0c0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('父高度无界（卡内直接嵌入场景）：按 token 上限渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                SizedBox(
                  width: 600,
                  child: ResultSnapshotTable(
                    columns: const ['id'],
                    rows: _rows(30, cols: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 垂直 ListView 给子项的是紧约束宽度（视口宽），本用例只断无界高度
      // 被钳到 token 上限（宽度由父决定，非本组件职责）。
      expect(
        tester.getSize(find.byType(ResultSnapshotTable)).height,
        AppDesignSystem.toolCardContentMaxHeight,
      );
      expect(_builtRows.evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
    });

    testWidgets('空列防御：零尺寸占位，不构建表格', (tester) async {
      await tester.pumpWidget(_harness(columns: const [], rows: _rows(3)));

      expect(tester.getSize(find.byType(ResultSnapshotTable)).height, 0.0);
      expect(
        find.descendant(
          of: find.byType(ResultSnapshotTable),
          matching: find.byType(ListView),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
