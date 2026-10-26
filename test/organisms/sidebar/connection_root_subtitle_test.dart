// UIRV-B5（UI 审查修复批 W3）· 连接根行 host 副信息测试。
//
// 验收条款直译（.specs/tasks-ui-review-fixes.md §UIRV-B5 验收 1~3/4/5/7）：
// 1. 连接根行双行：主行 name + 类型徽章 + 状态点（现布局），副行 host
//    信息 mono 单行 ellipsis；两个同名连接根行同时读到不同 host:port。
// 2. SQLite 副行 = 文件路径（tooltip 完整路径）；socket tooltip =
//    「连接名 · host:port」（port==0 不拼 :0）；host 空省略副行。
// 3. 根行高度 ≈36px（28+8）；库/表/列行高度不变。
// 4. 环境色条参数（ConnectionEnvironment.badgeColor）仍随根行传入。
// 5. 浏览手势不变：点根行（含副行区域）= 纯展开 + 写侧栏选中，
//    零 switchToConnection；副行不是连接切换入口。
// 7. 展开/折叠箭头与右键连接管理菜单随行高适配不回归。
//
// 注：性能护栏（节点计数/惰性构建/断开灰化）由既有
// multi_connection_tree_test.dart 回归覆盖（本批运行确认全绿）。
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// switchToConnection 计数 spy——验收 5「零 switchToConnection」断言基座
/// （复用 multi_connection_tree_test 同款语义，不在册断言不得回归）。
class _SwitchSpyProvider extends AppProvider {
  int switchCalls = 0;
  final List<String> toggledIds = [];

  @override
  Future<bool> switchToConnection(String connectionId) async {
    switchCalls++;
    return true;
  }
}

/// 谎报已连接的最小 stub（hasConnection 按 adapter 判真）。
class _FakeTreeAdapter extends Fake implements DatabaseAdapter {
  @override
  bool get isConnected => true;
}

DbServer _server(
  String id,
  String name, {
  DatabaseType type = DatabaseType.mysql,
  required String host,
  int port = 3306,
  ConnectionEnvironment? environment,
}) {
  return DbServer(
    id: id,
    type: type,
    name: name,
    host: host,
    port: port,
    username: 'root',
    password: 'x',
    environment: environment,
  );
}

void _connectForTest(AppProvider provider, DbServer server) {
  provider.connection.dbService.registerConnectedServerForTest(server);
  provider.connection.dbService.registerConnectedAdapterForTest(
    server.id,
    _FakeTreeAdapter(),
  );
  provider.connection.setConnectionDatabasesForTest(
    server.id,
    ['db_${server.id}'],
    ['db_${server.id}'],
  );
}

Widget _buildTestApp(AppProvider provider, {Widget? child}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: provider),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()..load()),
      ChangeNotifierProvider<ServerConnectionProvider>(
        create: (_) => ServerConnectionProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 1200,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

SidebarTree _tree(AppProvider provider, {void Function(String)? onToggleExpand}) =>
    SidebarTree(
      expandedItems: const {},
      expandedDatabases: const {},
      expandedTables: const {},
      loadingDatabases: const {},
      loadedTableSchemas: const {},
      loadedTableForeignKeys: const {},
      loadingTableSchemas: const {},
      onToggleExpand: onToggleExpand ?? (_) {},
      onToggleDatabase: (_) {},
      onToggleTable: (_) {},
      onLoadDatabaseInfo: (a, b) async {},
      onShowConnectionManager: () {},
      onShowSettings: () {},
      onShowERDiagram: () {},
      onShowStoredProcedures: () {},
      onShowTriggers: () {},
      tableRowCounts: const {},
    );

TreeItem _treeItemOf(WidgetTester tester, String label) {
  return tester.widget<TreeItem>(
    find.byWidgetPredicate((w) => w is TreeItem && w.label == label),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UIRV-B5 · 连接根行 host 副信息', () {
    testWidgets('验收1：两个同名连接根行同时读到不同 host:port 副行', (tester) async {
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'mysql-8.0', host: '127.0.0.1', port: 3306),
      );
      provider.connection.addSavedServerForTest(
        _server('conn-b', 'mysql-8.0', host: '192.0.2.128', port: 3307),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      expect(find.text('mysql-8.0'), findsNWidgets(2));
      expect(find.text('127.0.0.1:3306'), findsOneWidget);
      expect(find.text('192.0.2.128:3307'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('验收1b：副行左缘与名称左缘对齐', (tester) async {
      // 2026-10-26 用户反馈：根行副行（地址）比名称更靠左。用户可见症状
      // = 副行文本左缘在名称文本左缘左侧（差值为主行固定前导：箭头位 14 +
      // space1 + icon + space2）。断言直译：两者 dx 相等。
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'mysql-8.0', host: '127.0.0.1', port: 3306),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      final nameTopLeft = tester.getTopLeft(find.text('mysql-8.0'));
      final subtitleTopLeft = tester.getTopLeft(find.text('127.0.0.1:3306'));

      expect(
        subtitleTopLeft.dx,
        moreOrLessEquals(nameTopLeft.dx, epsilon: 0.5),
        reason: '副行左缘须与名称文本左缘严格对齐（不得左突主行前导缩进）',
      );
      expect(
        subtitleTopLeft.dy,
        greaterThan(nameTopLeft.dy),
        reason: '副行为双行根行的第二行',
      );
      expect(tester.takeException(), isNull);

      // 窄宽（280px 侧栏）守卫：副行仍单行 ellipsis，无 RenderFlex overflow，
      // 且对齐关系不随宽度变化。
      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: Center(
            child: SizedBox(width: 280, child: _tree(provider)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('127.0.0.1:3306')).dx,
        moreOrLessEquals(
          tester.getTopLeft(find.text('mysql-8.0')).dx,
          epsilon: 0.5,
        ),
        reason: '窄宽下副行左缘仍与名称左缘对齐',
      );
    });

    testWidgets('验收2a：SQLite 根行副行 = 文件路径，tooltip 给完整路径', (tester) async {
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server(
          'sqlite-1',
          'app.db',
          type: DatabaseType.sqlite,
          host: '/data/very/long/path/to/app.db',
          port: 0,
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      expect(find.text('/data/very/long/path/to/app.db'), findsOneWidget);
      // tooltip 完整路径（副行 ellipsis 时悬停可读全值）。
      final tooltips = tester.widgetList<Tooltip>(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == '/data/very/long/path/to/app.db',
        ),
      );
      expect(tooltips, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('验收2b：socket tooltip = 连接名 · host:port；port==0 不拼 :0', (
      tester,
    ) async {
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'mysql-8.0', host: '127.0.0.1', port: 3306),
      );
      provider.connection.addSavedServerForTest(
        _server('conn-c', 'legacy', host: 'legacy-host', port: 0),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      final socketTooltip = tester.widgetList<Tooltip>(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'mysql-8.0 · 127.0.0.1:3306',
        ),
      );
      expect(socketTooltip, isNotEmpty);

      // port==0：副行只有 host，tooltip 不出现 ":0"。
      expect(find.text('legacy-host'), findsOneWidget);
      expect(find.text('legacy-host:0'), findsNothing);
      final zeroPortTooltips = tester.widgetList<Tooltip>(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message?.contains(':0') ?? false),
        ),
      );
      expect(zeroPortTooltips, isEmpty);
      final legacyTooltip = tester.widgetList<Tooltip>(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'legacy · legacy-host',
        ),
      );
      expect(legacyTooltip, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('验收2c：host 空的异常数据省略副行，不显示占位/null', (tester) async {
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-x', 'broken-conn', host: ''),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      expect(find.text('broken-conn'), findsOneWidget);
      // 副行整行省略：无空串副行文本、无 "null" 文本。
      expect(find.text('null'), findsNothing);
      expect(find.text(':3306'), findsNothing);
      expect(find.text(':0'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('验收3：根行高度 ≈36px（28+8），库/表/列行高度不变', (tester) async {
      // 独立 TreeItem 几何：level1 带 subtitle = 36 内容高（+2 margin）；
      // level1 无 subtitle 维持 28（+2 margin）；level2 维持 24（+2）；
      // level3 维持 22。
      final provider = _SwitchSpyProvider();
      Future<double> sizeOf(TreeItem item) async {
        await tester.pumpWidget(
          _buildTestApp(provider, child: Center(child: item)),
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(TreeItem)).height;
      }

      expect(
        await sizeOf(
          TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.blue,
            label: 'root',
            subtitle: '127.0.0.1:3306',
            onTap: () {},
          ),
        ),
        38,
        reason: '根行双行 = 36 内容高 + 2 margin',
      );
      expect(
        await sizeOf(
          TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.blue,
            label: 'root',
            onTap: () {},
          ),
        ),
        30,
        reason: '无副行根行维持 28 + 2 margin',
      );
      expect(
        await sizeOf(
          TreeItem(
            level: 2,
            icon: LucideIcons.database,
            iconColor: Colors.blue,
            label: 'db',
            onTap: () {},
          ),
        ),
        26,
        reason: '库行维持 24 + 2 margin',
      );
      expect(
        await sizeOf(
          TreeItem(
            level: 3,
            icon: LucideIcons.table2,
            iconColor: Colors.blue,
            label: 'table',
            showArrow: false,
            onTap: () {},
          ),
        ),
        22,
        reason: '表/列行维持 22',
      );
    });

    testWidgets('品牌色恒定：未连接根行类型图标仍用 brandColor（对齐折叠 rail）', (
      tester,
    ) async {
      // 真机走查裁决：展开树连接根行图标恒用品牌色，连接态由状态点/
      // 子树灰化承载，颜色不再编码连接态（未连接不再灰化为 textSecondary）。
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'mysql-8.0', host: '127.0.0.1'),
      );
      // 未连接：不调用 _connectForTest。

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      final item = _treeItemOf(tester, 'mysql-8.0');
      // mysql 走 brandColor 的 default 分支，亮/暗主题同值。
      expect(item.iconColor, DatabaseType.mysql.brandColor);
      // 连接态语义不丢：未连接不显示展开箭头，状态点 trailing 仍在。
      expect(item.showArrow, isFalse);
      expect(item.trailing, isNotNull);
      // 环境色条语义既有验收4已覆盖，不重复。
      expect(tester.takeException(), isNull);
    });

    testWidgets('验收4：环境色条仍随根行传入（ConnectionEnvironment 同源）', (tester) async {
      final provider = _SwitchSpyProvider();
      provider.connection.addSavedServerForTest(
        _server(
          'conn-a',
          'mysql-8.0',
          host: '127.0.0.1',
          environment: ConnectionEnvironment.testing,
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      final item = _treeItemOf(tester, 'mysql-8.0');
      // v0.3.5 T1：色值同源不变，透明度编码连接态——断开 = 40%。
      expect(item.environmentBarColor, isNotNull);
      expect(
        item.environmentBarColor!.a,
        closeTo(ConnectionEnvironment.testing.badgeColor.a * 0.4, 0.001),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('验收5：点根行/副行区域 = 纯展开 + 写侧栏选中，零 switchToConnection', (
      tester,
    ) async {
      final provider = _SwitchSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);
      _connectForTest(provider, server);
      final toggled = <String>[];

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: _tree(provider, onToggleExpand: toggled.add),
        ),
      );
      await tester.pumpAndSettle();

      // 点主行（行内有 onDoubleTap，onTap 需跨双击窗口后触发）。
      await tester.tap(find.text('mysql-8.0'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(provider.switchCalls, 0, reason: '浏览手势零 switchToConnection');
      expect(provider.sidebar.selectedConnectionId, 'conn-a');
      expect(toggled, contains('conn-a'));

      // 点副行区域（同一行卡片，副行不是独立切换入口）。
      toggled.clear();
      await tester.tap(find.text('127.0.0.1:3306'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(provider.switchCalls, 0, reason: '副行不是连接切换入口');
      expect(provider.sidebar.selectedConnectionId, 'conn-a');
      expect(toggled, contains('conn-a'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('验收7：右键连接管理菜单随双行根行命中不回归', (tester) async {
      final provider = _SwitchSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);
      _connectForTest(provider, server);

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('mysql-8.0'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      // 连接管理菜单打开（既有菜单项可见即命中区未回归）。
      expect(find.text(l10n.connectionCreateDatabase), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
