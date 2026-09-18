// ============================================================================
// Doris Sidebar E2E Helpers
// 提供 pump 局部 harness、右键菜单、确认弹窗等 helper，供 Doris 侧边栏
// widget 级端到端测试使用。
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';

/// 构建只含 SidebarTree 的测试 App，不 pump 完整 DbmasterApp，
/// 避免触发 PurchaseProvider.initialize() 导致 Pigeon 通道挂起。
Widget buildDorisSidebarApp(AppProvider provider) {
  return MultiProvider(
    providers: [
      // 树内连接状态点（server-platform M1 起）watch 团队服务器连接态；
      // 本 harness 不涉团队服务器，供断开态实例即可。
      ChangeNotifierProvider<ServerConnectionProvider>(
        create: (_) => ServerConnectionProvider(),
      ),
      ChangeNotifierProvider.value(value: provider),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      locale: const Locale('en'),
      home: DorisSidebarHarness(provider: provider),
    ),
  );
}

Future<void> pumpDorisHarness(WidgetTester tester, AppProvider provider) async {
  await tester.pumpWidget(buildDorisSidebarApp(provider));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> tapDorisNode(WidgetTester tester, String label) async {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byType(TreeItem),
  );
  expect(finder, findsOneWidget, reason: 'Node "$label" not found');
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> rightClickDorisNode(WidgetTester tester, String label) async {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byType(TreeItem),
  );
  expect(finder, findsOneWidget, reason: 'Node "$label" not found');
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> tapDorisMenuItem(WidgetTester tester, String label) async {
  final menuFinder = find.byType(ContextMenu);
  expect(menuFinder, findsOneWidget, reason: 'Context menu not open');
  final finder = find.descendant(of: menuFinder, matching: find.text(label));
  expect(finder, findsOneWidget, reason: 'Menu item "$label" not found');
  await tester.tap(finder);
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> tapDorisDialogButton(WidgetTester tester, String label) async {
  final dialogFinder = find.byType(AlertDialog);
  final finder = find.descendant(
    of: dialogFinder,
    matching: find.widgetWithText(TextButton, label),
  );
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder);
  } else {
    final elevatedFinder = find.descendant(
      of: dialogFinder,
      matching: find.widgetWithText(ElevatedButton, label),
    );
    expect(elevatedFinder, findsOneWidget);
    await tester.tap(elevatedFinder);
  }
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> enterDorisConfirmationName(
  WidgetTester tester,
  String name,
) async {
  final field = find.byType(TextField);
  expect(
    field,
    findsOneWidget,
    reason: 'Confirmation dialog should have one TextField',
  );
  await tester.enterText(field, name);
  await tester.pump();
}

Future<void> expandDorisConnection(
  WidgetTester tester,
  String connectionLabel,
) async {
  await tapDorisNode(tester, connectionLabel);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> expandDorisDatabase(WidgetTester tester, String dbName) async {
  await tapDorisNode(tester, dbName);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> expandDorisCategory(
  WidgetTester tester,
  Pattern categoryPrefix,
) async {
  final headerFinder = find.ancestor(
    of: find.textContaining(categoryPrefix),
    matching: find.byType(TreeItem),
  );
  expect(headerFinder, findsOneWidget);
  await tester.ensureVisible(headerFinder);
  await tester.pumpAndSettle();
  await tester.tap(headerFinder);
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

// =============================================================================
// Minimal SidebarTree harness that mirrors SidebarWidget state management.
// =============================================================================
class DorisSidebarHarness extends StatefulWidget {
  final AppProvider provider;

  const DorisSidebarHarness({super.key, required this.provider});

  @override
  State<DorisSidebarHarness> createState() => _DorisSidebarHarnessState();
}

class _DorisSidebarHarnessState extends State<DorisSidebarHarness> {
  Set<String> _expandedItems = {};
  Set<String> _expandedDatabases = {};
  Set<String> _expandedTables = {};
  Set<String> _loadingDatabases = {};
  final Map<String, DbTable> _loadedTableSchemas = {};
  final Map<String, List<ForeignKey>> _loadedTableForeignKeys = {};
  final Set<String> _loadingTableSchemas = {};
  String? _rightClickedNodeKey;
  String? _selectedNodeKey;

  void _toggleExpand(String key) {
    setState(() {
      if (_expandedItems.contains(key)) {
        _expandedItems = _expandedItems.where((e) => e != key).toSet();
      } else {
        _expandedItems = {..._expandedItems, key};
      }
    });
  }

  void _toggleDatabase(String key) {
    setState(() {
      if (_expandedDatabases.contains(key)) {
        _expandedDatabases = _expandedDatabases.where((e) => e != key).toSet();
      } else {
        _expandedDatabases = {..._expandedDatabases, key};
      }
    });
  }

  void _toggleTable(String key) {
    final willExpand = !_expandedTables.contains(key);
    setState(() {
      if (_expandedTables.contains(key)) {
        _expandedTables = _expandedTables.where((e) => e != key).toSet();
      } else {
        _expandedTables = {..._expandedTables, key};
      }
    });
    if (willExpand) _loadTableSchema(key);
  }

  Future<void> _loadTableSchema(String tableKey) async {
    if (_loadingTableSchemas.contains(tableKey) ||
        _loadedTableSchemas.containsKey(tableKey)) {
      return;
    }
    final parts = tableKey.split(':');
    if (parts.length < 3) return;
    final connectionId = parts[0];
    final databaseName = parts[1];
    final tableName = parts.sublist(2).join(':');

    setState(() => _loadingTableSchemas.add(tableKey));
    try {
      final provider = widget.provider;
      final dbType = provider.dbService.getDatabaseType(connectionId);
      final columns = await provider.dbService.getTableColumns(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      final indexes = await provider.dbService.getTableIndexes(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      List<ForeignKey>? foreignKeys;
      if (dbType?.supportsForeignKeys ?? false) {
        foreignKeys = await provider.dbService.getForeignKeys(
          tableName,
          connectionId: connectionId,
          databaseName: databaseName,
        );
      }
      setState(() {
        _loadedTableSchemas[tableKey] = DbTable(
          name: tableName,
          columns: columns,
          indexes: indexes,
        );
        if (foreignKeys != null && foreignKeys.isNotEmpty) {
          _loadedTableForeignKeys[tableKey] = foreignKeys;
        }
        _loadingTableSchemas.remove(tableKey);
      });
    } catch (_) {
      setState(() => _loadingTableSchemas.remove(tableKey));
    }
  }

  Future<void> _loadDatabaseInfo(
    String connectionId,
    String databaseName,
  ) async {
    final key = '$connectionId:$databaseName';
    setState(() => _loadingDatabases = {..._loadingDatabases, key});
    try {
      await widget.provider.loadDatabaseInfo(connectionId, databaseName);
    } finally {
      setState(
        () => _loadingDatabases = _loadingDatabases
            .where((e) => e != key)
            .toSet(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SidebarTree(
        expandedItems: _expandedItems,
        expandedDatabases: _expandedDatabases,
        expandedTables: _expandedTables,
        loadingDatabases: _loadingDatabases,
        loadedTableSchemas: _loadedTableSchemas,
        loadedTableForeignKeys: _loadedTableForeignKeys,
        loadingTableSchemas: _loadingTableSchemas,
        onToggleExpand: _toggleExpand,
        onToggleDatabase: _toggleDatabase,
        onToggleTable: _toggleTable,
        onLoadDatabaseInfo: _loadDatabaseInfo,
        onLoadTableSchema: _loadTableSchema,
        onShowConnectionManager: () {},
        onShowSettings: () {},
        onShowERDiagram: () {},
        onShowStoredProcedures: () {},
        onShowTriggers: () {},
        onCollapseAll: () {
          setState(() {
            _expandedItems = {};
            _expandedDatabases = {};
            _expandedTables = {};
          });
        },
        rightClickedNodeKey: _rightClickedNodeKey,
        onRightClickTargetChanged: (key) {
          setState(() => _rightClickedNodeKey = key);
        },
        selectedNodeKey: _selectedNodeKey,
        onSelectNode: (key) {
          setState(() => _selectedNodeKey = key);
        },
      ),
    );
  }
}
