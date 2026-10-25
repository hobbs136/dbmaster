// v0.3.5 批1 T1 · 侧栏连接树视觉减负与状态强化（Epic 1.1 + 1.2）。
//
// 验收条款直译（UI35-101~115）：
// 101. 根行不再有类型文字徽章；品牌色图标保留。
// 102. 副行显隐：展开且已连接 → subtitle 为 null、行高 28；其余显示
//      副行、行高 36。
// 103. 行高 200ms 过渡（AnimatedContainer + curveDefault）+ 副行 100ms
//      淡出（AnimatedOpacity）；disableAnimations 时 0ms。
// 104. tooltip = 类型 + 端点；无版本源 → connectionTooltipTypeOnly，
//      禁止伪造版本。
// 105. 长连接名（>22 字符）在 280px 侧栏不被徽章提前截断；超物理宽度
//      中间省略（首段+尾段），完整值进 tooltip。
// 106-108. 状态点三态：失败 → error 实心；未连接 → 空心环（1.5px
//      textDisabled 描边 + 透明填充）；已连接 → success 实心（current
//      与否同色）。
// 110-111. 连接名：已连接 → connectionLabelConnected；未连接 →
//      connectionLabelDisconnected；均 fontWeightSemibold。
// 112. 环境圆点移除（与 3px 色条重复）。
// 113. 3px 环境条：断开 40% 透明度、连接 100%（token 色值不变）。
// 114-115. 回归红线（连接动作/switchToConnection/brandColor/子树/SSL
//      锁）由既有测试文件回归覆盖（multi_connection_tree_test 等）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class _NoopSpyProvider extends AppProvider {}

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

/// 主题 token 捕获（断言 token 引用而非字面色值）。
ThemeColors? _capturedTokens;

Widget _buildTestApp(
  AppProvider provider, {
  Widget? child,
  bool disableAnimations = false,
  double width = 400,
}) {
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
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Builder(
            builder: (context) {
              _capturedTokens = context.themeColors;
              return SizedBox(width: width, height: 1200, child: child);
            },
          ),
        ),
      ),
    ),
  );
}

SidebarTree _tree(
  AppProvider provider, {
  Set<String> expandedItems = const {},
  void Function(String)? onToggleExpand,
}) =>
    SidebarTree(
      expandedItems: expandedItems,
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

Size _sizeOfRootRow(WidgetTester tester, String label) {
  return tester.getSize(
    find.byWidgetPredicate((w) => w is TreeItem && w.label == label),
  );
}

/// 根行 10x10 状态点容器（Tooltip message 定位，与锁定/健康点区分）。
Container? _statusDotOf(WidgetTester tester, String tooltipMessage) {
  final tooltips = tester.widgetList<Tooltip>(
    find.byWidgetPredicate(
      (w) => w is Tooltip && w.message == tooltipMessage,
    ),
  );
  for (final t in tooltips) {
    final containers = tester.widgetList<Container>(
      find.descendant(of: find.byWidget(t), matching: find.byType(Container)),
    );
    for (final c in containers) {
      final decoration = c.decoration;
      if (decoration is BoxDecoration &&
          decoration.shape == BoxShape.circle &&
          c.constraints?.maxWidth == 10) {
        return c;
      }
    }
  }
  return null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _capturedTokens = null;
  });

  group('UI35 · 根行视觉减负（Epic 1.1）', () {
    testWidgets('UI35-101：根行无类型文字徽章；品牌色图标保留', (tester) async {
      final provider = _NoopSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'mysql-8.0', host: '127.0.0.1'),
      );

      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();

      final item = _treeItemOf(tester, 'mysql-8.0');
      expect(item.badge, isNull, reason: '根行不再传类型文字徽章');
      expect(item.iconColor, DatabaseType.mysql.brandColor);
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-102：展开+已连接 → subtitle null；未展开 → 副行显示', (tester) async {
      final provider = _NoopSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);
      _connectForTest(provider, server);

      // 未展开：副行显示。
      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();
      var item = _treeItemOf(tester, 'mysql-8.0');
      expect(item.subtitle, '127.0.0.1:3306');

      // 展开（expandedItems 含该连接且已连接）：subtitle 为 null。
      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: _tree(provider, expandedItems: const {'conn-a'}),
        ),
      );
      await tester.pumpAndSettle();
      item = _treeItemOf(tester, 'mysql-8.0');
      expect(item.subtitle, isNull, reason: '展开且已连接 → 副行让位给子树');
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-102b：展开+已连接行高 28（+2 margin=30），未展开 36（+2=38）', (tester) async {
      final provider = _NoopSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);
      _connectForTest(provider, server);

      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();
      expect(_sizeOfRootRow(tester, 'mysql-8.0').height, 38);

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: _tree(provider, expandedItems: const {'conn-a'}),
        ),
      );
      await tester.pumpAndSettle();
      expect(_sizeOfRootRow(tester, 'mysql-8.0').height, 30);
    });

    testWidgets('UI35-103：行高 200ms curveDefault 过渡 + 副行 100ms 淡出；disableAnimations → 0ms', (tester) async {
      final provider = _NoopSpyProvider();

      Future<void> pump(TreeItem item, {bool disableAnimations = false}) async {
        await tester.pumpWidget(
          _buildTestApp(
            provider,
            child: Center(child: item),
            disableAnimations: disableAnimations,
          ),
        );
        await tester.pumpAndSettle();
      }

      TreeItem item({String? subtitle}) => TreeItem(
            level: 1,
            icon: LucideIcons.database,
            iconColor: Colors.blue,
            label: 'root',
            subtitle: subtitle,
            onTap: () {},
          );

      await pump(item(subtitle: 'h:1'));
      // 行高过渡容器：AnimatedContainer 200ms + curveDefault。
      final animated = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(TreeItem),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(animated.duration, const Duration(milliseconds: 200));
      expect(animated.curve, AppDesignSystem.curveDefault);

      // 副行淡出：AnimatedOpacity 100ms。
      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(TreeItem),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.duration, const Duration(milliseconds: 100));

      // 切到无副行：淡出过渡期（未 settle）透明度动画目标 0。
      await tester.pumpWidget(
        _buildTestApp(provider, child: Center(child: item())),
      );
      await tester.pump(const Duration(milliseconds: 10));
      final fadingOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(TreeItem),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(fadingOpacity.opacity, 0);

      // disableAnimations：时长归零。
      await pump(item(subtitle: 'h:1'), disableAnimations: true);
      final zeroAnimated = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(TreeItem),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(zeroAnimated.duration, Duration.zero);
      final zeroOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(TreeItem),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(zeroOpacity.duration, Duration.zero);
    });

    testWidgets('UI35-104：tooltip = 类型 + 端点（无版本源 → type-only，不伪造版本）', (tester) async {
      final provider = _NoopSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'mysql-8.0', host: '127.0.0.1'),
      );

      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      final expected = l10n.connectionTooltipTypeOnly(
        DatabaseType.mysql.displayName,
      );
      // 主行 tooltip = 类型行 + 完整连接名（中间省略的全值载体）。
      final tooltips = tester.widgetList<Tooltip>(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              w.message != null &&
              w.message!.startsWith(expected) &&
              w.message!.contains('mysql-8.0'),
        ),
      );
      expect(tooltips, isNotEmpty);
      // 端点全值仍在副行 tooltip（「连接名 · host:port」）——tooltip = 类型+端点。
      final endpointTooltip = tester.widgetList<Tooltip>(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'mysql-8.0 · 127.0.0.1:3306',
        ),
      );
      expect(endpointTooltip, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-104：展开+已连接（副行隐藏）时主行 tooltip 仍含端点', (tester) async {
      final provider = _NoopSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);
      _connectForTest(provider, server);

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider, expandedItems: {'conn-a'})),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      final expected = l10n.connectionTooltipTypeOnly(
        DatabaseType.mysql.displayName,
      );
      // 副行隐藏（UI35-102），端点全值必须仍可从主行 tooltip 看到：
      // 类型行 + 连接名 + host:port 三行。
      final labelTooltip = tester
          .widgetList<Tooltip>(
            find.byWidgetPredicate(
              (w) =>
                  w is Tooltip &&
                  w.message != null &&
                  w.message!.startsWith(expected) &&
                  w.message!.contains('mysql-8.0'),
            ),
          )
          .first;
      expect(
        labelTooltip.message!.contains('127.0.0.1:3306'),
        isTrue,
        reason: '副行隐藏后端点必须在主行 tooltip 保留：${labelTooltip.message}',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-105：280px 下长连接名中间省略（首段+尾段保留），完整值进 tooltip', (tester) async {
      final provider = _NoopSpyProvider();
      const longName = 'prod-analytics-replica-cluster';
      provider.connection.addSavedServerForTest(
        _server('conn-a', longName, host: '127.0.0.1'),
      );

      await tester.pumpWidget(
        _buildTestApp(provider, child: _tree(provider), width: 280),
      );
      await tester.pumpAndSettle();

      // 渲染文本被中间省略：不再是全名，保留首段与尾段，省略号在中间。
      final candidates = tester
          .widgetList<Text>(
            find.byWidgetPredicate(
              (w) => w is Text && w.data != null && w.data != longName,
            ),
          )
          .map((t) => t.data!)
          .where((d) => d.startsWith('prod-') || d.contains('…'))
          .toList();
      expect(candidates, isNotEmpty, reason: '长名应被截短渲染');
      final rendered = candidates.first;
      expect(rendered.startsWith('prod-'), isTrue, reason: '保留首段: $rendered');
      expect(rendered.endsWith('cluster'), isTrue, reason: '保留尾段: $rendered');
      expect(rendered.contains('…'), isTrue, reason: '含省略号: $rendered');
      expect(rendered.endsWith('…'), isFalse, reason: '应为中间省略: $rendered');

      // 完整值进 tooltip：TreeItem.label 保持全值（Tooltip 载体）。
      final item = _treeItemOf(tester, longName);
      expect(item.label, longName);
      final nameTooltips = tester.widgetList<Tooltip>(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message?.contains(longName) ?? false),
        ),
      );
      expect(nameTooltips, isNotEmpty, reason: '完整连接名进 tooltip');
      expect(tester.takeException(), isNull);
    });
  });

  group('UI35 · 状态强化（Epic 1.2）', () {
    testWidgets('UI35-106：意外断连失败 → 状态点 error 实心', (tester) async {
      final provider = _NoopSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);

      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();

      // 意外断连（无主动断开标记）→ 记录未处置失败。
      provider.connection.dbService.addEventForTest(
        ConnectionDisconnected(server.id, server),
      );
      await tester.pumpAndSettle();
      expect(provider.connection.lastFailureFor(server.id), isNotNull);

      final l10n = AppLocalizationsEn();
      final dot = _statusDotOf(
        tester,
        l10n.connectFailureLatestTooltip(l10n.connectFailureUnknown),
      );
      expect(dot, isNotNull);
      final decoration = dot!.decoration! as BoxDecoration;
      expect(decoration.color, _capturedTokens!.error, reason: 'error 实心');
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-107：未连接 → 空心环（透明填充 + 1.5px textDisabled 描边）', (tester) async {
      final provider = _NoopSpyProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'mysql-8.0', host: '127.0.0.1'),
      );
      // 不连接。

      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      final dot = _statusDotOf(tester, l10n.connectionDisconnect);
      expect(dot, isNotNull);
      final decoration = dot!.decoration! as BoxDecoration;
      // 形状编码：空心 = 透明填充 + textDisabled 描边（token 引用）。
      expect(decoration.color, Colors.transparent);
      final border = decoration.border! as Border;
      expect(border.top.width, 1.5);
      expect(border.top.color, _capturedTokens!.textDisabled);
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-108：已连接 → success 实心；current 与非 current 同色', (tester) async {
      final provider = _NoopSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);
      _connectForTest(provider, server);

      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      // 非 current：connected 分支，success 实心。
      final dot = _statusDotOf(tester, l10n.connectionConnected);
      expect(dot, isNotNull);
      final colorA = (dot!.decoration! as BoxDecoration).color;
      expect(colorA, _capturedTokens!.success);

      // 点选使其成为 current：仍 success 实心（双色编码退役）。
      await tester.tap(find.text('mysql-8.0'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(provider.activeContextConnection?.id, 'conn-a');
      final dotCurrent = _statusDotOf(tester, l10n.connectionCurrent);
      expect(dotCurrent, isNotNull);
      expect(
        (dotCurrent!.decoration! as BoxDecoration).color,
        _capturedTokens!.success,
        reason: 'current 与否同色',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-110/111：连接名颜色 token 化（连接/断开）+ semibold', (tester) async {
      final provider = _NoopSpyProvider();
      final server = _server('conn-a', 'mysql-8.0', host: '127.0.0.1');
      provider.connection.addSavedServerForTest(server);

      // 未连接。
      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();
      var item = _treeItemOf(tester, 'mysql-8.0');
      expect(
        item.labelColor,
        AppDesignSystem.connectionLabelDisconnected,
      );

      // 已连接。
      _connectForTest(provider, server);
      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();
      item = _treeItemOf(tester, 'mysql-8.0');
      expect(item.labelColor, AppDesignSystem.connectionLabelConnected);
      // level1 基线即 semibold（fontWeightSemibold = w600），由组件档位表承载。
      expect(AppDesignSystem.fontWeightSemibold, FontWeight.w600);
      expect(tester.takeException(), isNull);
    });

    testWidgets('UI35-112/113：环境圆点移除；环境条断开 40% / 连接 100%', (tester) async {
      final provider = _NoopSpyProvider();
      final server = _server(
        'conn-a',
        'mysql-8.0',
        host: '127.0.0.1',
        environment: ConnectionEnvironment.testing,
      );
      provider.connection.addSavedServerForTest(server);

      // 未连接：环境条 40% 透明度。
      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();
      var item = _treeItemOf(tester, 'mysql-8.0');
      expect(item.environmentBarColor, isNotNull);
      expect(
        item.environmentBarColor!.a,
        closeTo(ConnectionEnvironment.testing.badgeColor.a * 0.4, 0.001),
        reason: '断开 = 40% 透明度（token 色值不变）',
      );
      // 环境圆点已移除：无以环境名为 tooltip 的 10px 圆点。
      final envDot = _statusDotOf(
        tester,
        ConnectionEnvironment.testing.displayName,
      );
      expect(envDot, isNull, reason: '环境圆点与 3px 色条重复，已移除');

      // 已连接：环境条 100%。
      _connectForTest(provider, server);
      await tester.pumpWidget(_buildTestApp(provider, child: _tree(provider)));
      await tester.pumpAndSettle();
      item = _treeItemOf(tester, 'mysql-8.0');
      expect(
        item.environmentBarColor!.a,
        ConnectionEnvironment.testing.badgeColor.a,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
