import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/organisms/connection/schema_diff/schema_diff_tree.dart';

/// SchemaDiffTree widget + 键盘导航纯函数测试。
void main() {
  group('SchemaDiffTree.objectKeys', () {
    test('按 渲染顺序 (tables → views → procedures) 展平 key', () {
      final keys = SchemaDiffTree.objectKeys(_report(), DiffCategory.all);
      expect(keys, ['table:users', 'table:orders', 'view:v1', 'proc:p1']);
    });

    test('DiffCategory.added 仅保留 added 项', () {
      final keys = SchemaDiffTree.objectKeys(_report(), DiffCategory.added);
      expect(keys, ['table:users', 'view:v1']);
    });

    test('空报告返回空列表', () {
      final keys = SchemaDiffTree.objectKeys(_emptyReport(), DiffCategory.all);
      expect(keys, isEmpty);
    });
  });

  group('SchemaDiffTree.moveSelection', () {
    const keys = ['a', 'b', 'c'];

    test('空列表返回 null', () {
      expect(SchemaDiffTree.moveSelection([], 'a', true), isNull);
    });

    test('无当前选择：↓ 进入首项，↑ 进入末项', () {
      expect(SchemaDiffTree.moveSelection(keys, null, true), 'a');
      expect(SchemaDiffTree.moveSelection(keys, null, false), 'c');
    });

    test('中部前/后移动', () {
      expect(SchemaDiffTree.moveSelection(keys, 'b', true), 'c');
      expect(SchemaDiffTree.moveSelection(keys, 'b', false), 'a');
    });

    test('边界钳制（不循环）', () {
      expect(SchemaDiffTree.moveSelection(keys, 'c', true), 'c');
      expect(SchemaDiffTree.moveSelection(keys, 'a', false), 'a');
    });

    test('当前 key 不在列表中时重置锚点', () {
      expect(SchemaDiffTree.moveSelection(keys, 'zzz', true), 'a');
      expect(SchemaDiffTree.moveSelection(keys, 'zzz', false), 'c');
    });
  });

  group('SchemaDiffTree widget', () {
    testWidgets('渲染对象名并响应点击回调', (tester) async {
      String? selected;
      await _pumpTree(
        tester,
        SchemaDiffTree(
          report: _report(),
          filter: DiffCategory.all,
          onSelect: (key) => selected = key,
        ),
      );

      expect(find.text('users'), findsOneWidget);
      expect(find.text('v1'), findsOneWidget);
      expect(find.text('Procedures'), findsOneWidget);

      await tester.tap(find.text('users'));
      await tester.pump();
      expect(selected, 'table:users');

      await tester.tap(find.text('v1'));
      await tester.pump();
      expect(selected, 'view:v1');
    });

    testWidgets('筛选器隐藏不匹配的项', (tester) async {
      await _pumpTree(
        tester,
        SchemaDiffTree(
          report: _report(),
          filter: DiffCategory.added,
          onSelect: (_) {},
        ),
      );

      expect(find.text('users'), findsOneWidget); // added
      expect(find.text('orders'), findsNothing); // removed，被隐藏
      expect(find.text('v1'), findsOneWidget); // added view
      expect(find.text('p1'), findsNothing); // procedures 段在 added 下不显示表/视图外
    });

    testWidgets('无匹配对象时显示空状态', (tester) async {
      await _pumpTree(
        tester,
        SchemaDiffTree(
          report: _emptyReport(),
          filter: DiffCategory.all,
          onSelect: (_) {},
        ),
      );

      expect(find.text('No matching objects'), findsOneWidget);
    });

    testWidgets('选中项高亮（选中 users 后再点击 orders 切换）', (tester) async {
      String? selected = 'table:users';
      await _pumpTree(
        tester,
        SchemaDiffTree(
          report: _report(),
          selectedObjectKey: selected,
          filter: DiffCategory.all,
          onSelect: (key) {
            selected = key;
          },
        ),
      );

      // users 应加粗（isSelected → FontWeight.w600）
      final usersText = tester.widget<Text>(find.text('users'));
      expect(usersText.style?.fontWeight, FontWeight.w600);
    });
  });
}

Future<void> _pumpTree(WidgetTester tester, Widget tree) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: tree)));
  await tester.pumpAndSettle();
}

SchemaDiffReport _emptyReport() => SchemaDiffReport(
      sourceConnection: 's',
      targetConnection: 't',
      sourceDatabase: 'src',
      targetDatabase: 'tgt',
      generatedAt: DateTime(2024, 1, 1),
    );

SchemaDiffReport _report() => SchemaDiffReport(
      sourceConnection: 's',
      targetConnection: 't',
      sourceDatabase: 'src',
      targetDatabase: 'tgt',
      generatedAt: DateTime(2024, 1, 1),
      tableDiffs: [
        TableDiff(name: 'users', type: DiffType.added, columnDiffs: [
          ColumnDiff(name: 'email', type: DiffType.added),
        ]),
        TableDiff(name: 'orders', type: DiffType.removed),
      ],
      viewDiffs: [
        ViewDiff(
          name: 'v1',
          type: DiffType.added,
          createStatement: 'CREATE VIEW v1 AS SELECT 1',
        ),
      ],
      procedureDiffs: [
        ProcedureDiff(name: 'p1', type: DiffType.removed),
      ],
    );
