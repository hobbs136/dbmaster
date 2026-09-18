// C20 复现守卫：SS 全局树展开 Server Status 后，其余全局节点（Process
// List / Users）必须仍在树中（E2E GLOB-001 在网关链路下曾失败于此——
// 本单测以 mock executeQuery 锚定插件装配行为，不依赖真库）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/sqlserver_sidebar_plugin.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

class _StubQueryAppProvider extends AppProvider {
  int queryCount = 0;

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    queryCount++;
    if (sql.contains('@@VERSION')) {
      return [
        {
          'version':
              'Microsoft SQL Server 2022 (RTM-CU14) - 16.0.4165.4 (X64) '
              'Copyright (C) 2022 Microsoft Corporation on Windows Server',
          'edition': 'Developer Edition (64-bit)',
          'product_version': '16.0.4165.4',
          'user_connections': 3,
          'blocked_requests': 0,
        },
      ];
    }
    if (sql.contains('sys.dm_exec_sessions')) {
      return [
        {
          'spid': 55,
          'loginame': 'sa',
          'status': 'running',
          'program': 'dbmaster',
          'dbname': 'master',
          'blocked': null,
        },
      ];
    }
    if (sql.contains('sys.sql_logins')) {
      return [
        {
          'name': 'sa',
          'type_desc': 'SQL_LOGIN',
          'create_date': '2020-01-01T00:00:00',
          'is_disabled': false,
        },
      ];
    }
    return [];
  }
}

void main() {
  testWidgets('展开 Server Status 后 Process List / Users 节点仍在树中', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = _StubQueryAppProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: _GlobalTreeHarness(expandedItems: const {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Server Status'), findsOneWidget);
    expect(find.text('Process List'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);

    // 展开 Server Status（模拟 E2E tapNode → onToggleExpand）。
    (tester.state(find.byType(_GlobalTreeHarness)) as _GlobalTreeHarnessState)
        .toggle('ss_conn:sqlserver_status');
    await tester.pumpAndSettle();

    // 展开内容渲染 + 其余两个全局节点仍在。
    expect(find.textContaining('Microsoft SQL Server 2022'), findsWidgets);
    expect(find.text('Process List'), findsOneWidget,
        reason: 'E2E GLOB-001 回归锚点：展开 Server Status 不得移除其余节点');
    expect(find.text('Users'), findsOneWidget);
  });
}

class _GlobalTreeHarness extends StatefulWidget {
  const _GlobalTreeHarness({required this.expandedItems});
  final Set<String> expandedItems;

  @override
  State<_GlobalTreeHarness> createState() => _GlobalTreeHarnessState();
}

class _GlobalTreeHarnessState extends State<_GlobalTreeHarness> {
  late Set<String> _expanded = Set.from(widget.expandedItems);

  void toggle(String key) => setState(() => _expanded = {..._expanded, key});

  @override
  Widget build(BuildContext context) {
    final nodes = const SqlserverSidebarPlugin().buildGlobalTree(
      context,
      SidebarTreeContext(
        provider: context.read<AppProvider>(),
        connectionId: 'ss_conn',
        expandedItems: _expanded,
        onToggleExpand: (_) {},
      ),
    );
    return ListView(children: nodes);
  }
}
