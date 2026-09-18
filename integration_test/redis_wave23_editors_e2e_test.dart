// ============================================================================
// Redis Wave 2/3 Editors & Workbenches Integration Tests
// Covers (docs/test/redis_sidebar_e2e_report.md):
//   W2.4 Geo editor (member list / GEODIST / GEOADD / remove)
//   W2.5 Stream editor (XADD / XDEL / XTRIM / consumer groups)
//   W2.7 CONFIG SET via sidebar Config node
//   W2.8 Large hash/set editors open without blocking
//   W3.3-W3.6 Lua script workbench (CRUD / Sync / Run EVALSHA / Flush)
// Target: real Redis via DBMASTER_REDIS_* (see config/redis_test_config.dart)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/organisms/redis_key_editor/redis_key_editor_dialog.dart';
import 'package:dbmaster/organisms/redis_lua/redis_lua_panel.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/redis_test_config.dart';
import 'helpers/redis_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // T29 非 SQL 批次（B4）：Redis 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 REDIS_E2E_SKIP 跳过（无假绿）。
  var redisE2EGatewayReady = false;
  setUpAll(() async {
    redisE2EGatewayReady = await ensureEmbeddedServerForRedisE2E();
    if (redisE2EGatewayReady && !RedisTestConfig.available) {
      // ignore: avoid_print
      print('REDIS_E2E_SKIP: DBMASTER_REDIS_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      redisE2EGatewayReady = false;
    }
  });

  group('Redis Wave2/3 Editors E2E', () {
    late AppProvider appProvider;
    late RedisAdapter adapter;
    late String testPrefix;
    late DbServer server;

    const connectionLabel = 'Redis Wave23 E2E';

    late String geoKey;
    late String streamKey;
    late String luaKey;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();

      geoKey = '${testPrefix}_geo';
      streamKey = '${testPrefix}_stream';
      luaKey = '${testPrefix}_lua';

      // 1. Connect and seed keys in the configured test DB.
      final dbConn = DatabaseConnection(
        id: 'seed_${testPrefix.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      await adapter.connect(dbConn);
      await adapter.runCommand(['FLUSHDB']);

      // Geo key (zset under the hood): 3 city members.
      await adapter.runCommand([
        'GEOADD',
        geoKey,
        '113.2644',
        '23.1291',
        'guangzhou',
        '121.4737',
        '31.2304',
        'shanghai',
        '116.3974',
        '39.9093',
        'beijing',
      ]);
      // Stream key: 2 entries + 1 pre-seeded consumer group (the group
      // creation form only renders when >=1 group exists).
      await adapter.runCommand(['XADD', streamKey, '*', 'f1', 'v1']);
      await adapter.runCommand(['XADD', streamKey, '*', 'f2', 'v2']);
      await adapter.runCommand([
        'XGROUP',
        'CREATE',
        streamKey,
        'seedgroup',
        '0',
      ]);
      // Plain string key used by the Lua Run test.
      await adapter.runCommand(['SET', luaKey, 'hello-lua']);

      // 2. Connect the provider.
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      server = DbServer(
        id: 'redis_wave23_e2e_${testPrefix.hashCode}',
        name: connectionLabel,
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to Redis');
      await appProvider.refreshDatabases();
      await appProvider.loadRedisDatabaseKeyInfo(
        server.id,
        RedisTestConfig.database,
      );
    });

    tearDown(() async {
      try {
        final keys = await adapter.scanKeys(pattern: '$testPrefix*');
        if (keys.isNotEmpty) {
          await adapter.runCommand(['DEL', ...keys]);
        }
      } catch (e) {
        AppLogger.d('RedisWave23E2E', 'Cleanup DEL failed: $e');
      }
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('redis_scripts_v1');
        await prefs.remove('saved_queries');
        await prefs.remove('recent_tables');
        await prefs.remove('sidebar_favorite_tables');
        await prefs.remove('connection_groups');
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    // ----------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------
    Widget buildTestApp(AppProvider provider) {
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
          home: _SidebarTestHarness(provider: provider),
        ),
      );
    }

    Future<void> pumpHarness(WidgetTester tester) async {
      // Large surface so wide dialogs (geo dist tool, Lua panel) fit.
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(appProvider));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> tapNode(WidgetTester tester, String label) async {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(TreeItem),
      );
      expect(finder, findsOneWidget, reason: 'Node "$label" not found');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandConnection(WidgetTester tester) =>
        tapNode(tester, connectionLabel);

    Future<void> expandDatabase(WidgetTester tester) =>
        tapNode(tester, RedisTestConfig.database);

    Future<void> expandKeys(WidgetTester tester) => tapNode(tester, 'Keys');

    Future<void> doubleTapNodeContaining(
      WidgetTester tester,
      String text,
    ) async {
      if (!redisE2EGatewayReady) return;
      final finder = find.ancestor(
        of: find.textContaining(text),
        matching: find.byType(TreeItem),
      );
      expect(
        finder,
        findsAtLeastNWidgets(1),
        reason: 'Node containing "$text" not found',
      );
      await tester.ensureVisible(finder.last);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finder.last);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> openKeyEditor(WidgetTester tester, String keyName) async {
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester);
      await expandKeys(tester);
      await doubleTapNodeContaining(tester, keyName);
      expect(
        find.byType(RedisKeyEditorDialog),
        findsOneWidget,
        reason: 'Key editor dialog did not open for $keyName',
      );
    }

    Finder editorTextField(int index) => find
        .descendant(
          of: find.byType(RedisKeyEditorDialog),
          matching: find.byType(TextField),
        )
        .at(index);

    Future<void> selectDropdown(
      WidgetTester tester,
      String label,
      String value,
    ) async {
      if (!redisE2EGatewayReady) return;
      final dd = find.ancestor(
        of: find.text(label),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      expect(dd, findsOneWidget, reason: 'Dropdown "$label" not found');
      await tester.tap(dd);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      final item = find.text(value);
      expect(
        item,
        findsAtLeastNWidgets(1),
        reason: 'Dropdown item "$value" not found',
      );
      await tester.tap(item.last);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }

    Future<void> tapElevated(WidgetTester tester, String label) async {
      final btn = find.widgetWithText(ElevatedButton, label);
      expect(btn, findsOneWidget, reason: 'Button "$label" not found');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> closeDialog(WidgetTester tester) async {
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    /// SnackBars queue behind each other (4s each). Poll until the expected
    /// message becomes visible (integration tests run on the real clock).
    Future<void> waitForSnack(
      WidgetTester tester,
      String text, {
      int maxSeconds = 15,
    }) async {
      for (var i = 0; i < maxSeconds; i++) {
        if (find.textContaining(text).evaluate().isNotEmpty) return;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        find.textContaining(text),
        findsAtLeastNWidgets(1),
        reason: 'SnackBar "$text" never appeared',
      );
    }

    // ----------------------------------------------------------------------
    // W2.4 — Geo editor
    // ----------------------------------------------------------------------
    testWidgets('W2.4 geo editor: members, GEODIST, GEOADD, remove', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await openKeyEditor(tester, geoKey);

      // Opens as Sorted Set view; switch to Geo.
      expect(find.text('Type: Sorted Set'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Geo'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Type: Geo'), findsOneWidget);

      // Member list with coordinates.
      expect(find.text('Members: 3'), findsOneWidget);
      expect(find.text('guangzhou'), findsOneWidget);
      expect(find.text('shanghai'), findsOneWidget);
      expect(find.text('beijing'), findsOneWidget);
      expect(find.textContaining('113.264'), findsOneWidget);
      expect(find.textContaining('121.473'), findsOneWidget);

      // GEODIST guangzhou -> shanghai in km.
      await selectDropdown(tester, 'From', 'guangzhou');
      await selectDropdown(tester, 'To', 'shanghai');
      await selectDropdown(tester, 'Unit', 'km');
      final expected = await adapter.geoDist(
        geoKey,
        'guangzhou',
        'shanghai',
        unit: 'km',
      );
      expect(expected, isNotNull);
      await tapElevated(tester, 'Dist');
      expect(
        find.text('${expected!.toStringAsFixed(2)} km'),
        findsOneWidget,
        reason: 'GEODIST result not shown',
      );

      // GEOADD a new member via the form (Lng / Lat / Name + Add).
      await tester.enterText(editorTextField(0), '113.9304');
      await tester.enterText(editorTextField(1), '22.5333');
      await tester.enterText(editorTextField(2), 'shenzhen');
      await tapElevated(tester, 'Add');
      expect(find.text('Members: 4'), findsOneWidget);
      expect(find.text('shenzhen'), findsOneWidget);
      final zcard = await adapter.runCommand(['ZCARD', geoKey]);
      expect(zcard.toString(), '4', reason: 'GEOADD did not persist');

      // Remove the new member.
      final row = find.ancestor(
        of: find.text('shenzhen'),
        matching: find.byType(ListTile),
      );
      expect(row, findsOneWidget);
      await tester.tap(
        find.descendant(of: row, matching: find.byTooltip('Remove')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Members: 3'), findsOneWidget);
      expect(find.text('shenzhen'), findsNothing);
      final zcard2 = await adapter.runCommand(['ZCARD', geoKey]);
      expect(zcard2.toString(), '3', reason: 'Member remove did not persist');

      await closeDialog(tester);
    });

    // ----------------------------------------------------------------------
    // W2.5 — Stream editor
    // ----------------------------------------------------------------------
    testWidgets('W2.5 stream editor: XADD/XDEL/XTRIM/consumer groups', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await openKeyEditor(tester, streamKey);

      // Info bar + seeded entries.
      expect(find.textContaining('Length: 2'), findsOneWidget);
      expect(find.text('f1=v1'), findsOneWidget);

      // XADD a new entry (Field / Value + XADD button).
      await tester.enterText(editorTextField(0), 'f3');
      await tester.enterText(editorTextField(1), 'v3');
      await tapElevated(tester, 'XADD');
      expect(find.textContaining('Length: 3'), findsOneWidget);
      expect(find.text('f3=v3'), findsOneWidget);
      final xlen = await adapter.runCommand(['XLEN', streamKey]);
      expect(xlen.toString(), '3', reason: 'XADD did not persist');

      // XDEL the first entry.
      await tester.tap(find.byTooltip('XDEL').first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.textContaining('Length: 2'), findsOneWidget);
      final xlen2 = await adapter.runCommand(['XLEN', streamKey]);
      expect(xlen2.toString(), '2', reason: 'XDEL did not persist');

      // XTRIM MAXLEN (trim field is the 3rd TextField: Field/Value/Trim).
      // NOTE: adapter.streamTrim uses XTRIM MAXLEN ~ N (approximate). Tiny
      // streams (< one radix-tree node) are not trimmed, so assert the
      // command round-trips (snackbar + no error) rather than exact length.
      await tester.enterText(editorTextField(2), '1');
      final trimBtn = find.widgetWithText(TextButton, 'Trim');
      expect(trimBtn, findsOneWidget);
      await tester.tap(trimBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.textContaining('Trimmed'), findsOneWidget);
      final xlen3 = await adapter.runCommand(['XLEN', streamKey]);
      expect(
        int.parse(xlen3.toString()),
        lessThanOrEqualTo(2),
        reason: 'XTRIM must not grow the stream',
      );

      // Consumer groups: pre-seeded group chip is visible; create a second.
      expect(find.textContaining('Consumer Groups (1)'), findsOneWidget);
      expect(find.textContaining('seedgroup (pending:'), findsOneWidget);
      // Group name field is the 4th TextField.
      await tester.enterText(editorTextField(3), 'g2');
      await tapElevated(tester, 'XGROUP CREATE');
      expect(find.textContaining('Consumer Groups (2)'), findsOneWidget);
      expect(find.textContaining('g2 (pending:'), findsOneWidget);

      // Destroy the new group via its chip delete icon.
      final chip = find.widgetWithText(Chip, 'g2 (pending:0)');
      expect(chip, findsOneWidget);
      final chipIcons = find.descendant(of: chip, matching: find.byType(Icon));
      await tester.tap(chipIcons.last);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.textContaining('Consumer Groups (1)'), findsOneWidget);
      final groups = await adapter.xinfoGroups(streamKey);
      expect(groups.length, 1, reason: 'XGROUP DESTROY did not persist');

      await closeDialog(tester);
    });

    // ----------------------------------------------------------------------
    // W2.7 — CONFIG SET
    // ----------------------------------------------------------------------
    testWidgets('W2.7 CONFIG SET via Edit Config dialog', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      // Read current loglevel; pick a different valid value.
      final res = await adapter.runCommand(['CONFIG', 'GET', 'loglevel']);
      final String current;
      if (res is Map) {
        current = res['loglevel'].toString();
      } else if (res is List && res.length >= 2) {
        current = res[1].toString();
      } else {
        current = 'notice';
      }
      final newLevel = current == 'verbose' ? 'notice' : 'verbose';

      try {
        await tapNode(tester, 'Config');
        await tapNode(tester, 'Edit Config...');
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Edit Config'), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(0), 'loglevel');
        await tester.enterText(find.byType(TextField).at(1), newLevel);
        await tester.tap(find.widgetWithText(TextButton, 'Apply'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(find.text('Config updated: loglevel'), findsOneWidget);
        final after = await adapter.runCommand(['CONFIG', 'GET', 'loglevel']);
        final afterStr = after is Map
            ? after['loglevel'].toString()
            : (after as List)[1].toString();
        expect(afterStr, newLevel, reason: 'CONFIG SET did not take effect');

        // Read-only parameter gives a friendly failure hint.
        await tapNode(tester, 'Edit Config...');
        await tester.enterText(find.byType(TextField).at(0), 'databases');
        await tester.enterText(find.byType(TextField).at(1), '16');
        await tester.tap(find.widgetWithText(TextButton, 'Apply'));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await waitForSnack(tester, 'Failed');
      } finally {
        await adapter.runCommand(['CONFIG', 'SET', 'loglevel', current]);
      }
    });

    // ----------------------------------------------------------------------
    // W2.8 — Large hash/set editors open without blocking
    // ----------------------------------------------------------------------
    testWidgets('W2.8 large hash/set editors open without blocking', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      final bigHashKey = '${testPrefix}_bighash';
      final bigSetKey = '${testPrefix}_bigset';
      const memberCount = 3000;

      // Seed in batches of 200.
      for (var i = 0; i < memberCount; i += 200) {
        final hargs = <String>['HSET', bigHashKey];
        final sargs = <String>['SADD', bigSetKey];
        for (var j = i; j < i + 200; j++) {
          final n = j.toString().padLeft(6, '0');
          hargs.addAll(['field$n', 'value$n']);
          sargs.add('member$n');
        }
        await adapter.runCommand(hargs);
        await adapter.runCommand(sargs);
      }

      // Refresh key info so the new keys appear in tree samples.
      await appProvider.loadRedisDatabaseKeyInfo(
        server.id,
        RedisTestConfig.database,
      );

      // Big hash editor.
      await openKeyEditor(tester, bigHashKey);
      expect(
        find.descendant(
          of: find.byType(RedisKeyEditorDialog),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'Hash editor stuck loading 3000 fields',
      );
      // Rows are Containers (not ListTiles); HGETALL order is arbitrary, so
      // match any rendered field name (all start with 'field00').
      expect(
        find.descendant(
          of: find.byType(RedisKeyEditorDialog),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data?.startsWith('field00') ?? false),
          ),
        ),
        findsAtLeastNWidgets(3),
        reason: 'Hash editor did not render field rows',
      );
      expect(find.textContaining('Failed to load'), findsNothing);
      await closeDialog(tester);

      // Big set editor.
      await doubleTapNodeContaining(tester, bigSetKey);
      expect(find.byType(RedisKeyEditorDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RedisKeyEditorDialog),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data?.startsWith('member00') ?? false),
          ),
        ),
        findsAtLeastNWidgets(3),
        reason: 'Set editor did not render member rows',
      );
      expect(find.textContaining('Failed to load'), findsNothing);
      await closeDialog(tester);
    });

    // ----------------------------------------------------------------------
    // W3.3-W3.6 — Lua script workbench
    // ----------------------------------------------------------------------
    Future<void> openLuaPanel(WidgetTester tester) async {
      await pumpHarness(tester);
      await expandConnection(tester);
      await tapNode(tester, 'Lua Scripts');
      expect(find.byType(RedisLuaPanel), findsOneWidget);
    }

    Finder luaNameField() => find.ancestor(
      of: find.text('Script name'),
      matching: find.byType(TextField),
    );

    /// Lua 代码编辑器（re_editor 无 EditableText，改走 IME 入口 edit()）。
    Future<void> enterLuaCode(WidgetTester tester, String code) async {
      final editor = tester.widget<ReSqlEditor>(find.byType(ReSqlEditor));
      editor.controller.replaceAllText(code);
      await tester.pump();
    }

    Future<void> saveLuaScript(
      WidgetTester tester,
      String name,
      String code,
    ) async {
      if (!redisE2EGatewayReady) return;
      await tester.tap(find.byTooltip('New script'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.enterText(luaNameField(), name);
      await enterLuaCode(tester, code);
      await tapElevated(tester, 'Save');
      expect(find.text('Scripts (1)'), findsOneWidget);
    }

    testWidgets('W3.3 Lua workbench: create/save/rename/delete', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await openLuaPanel(tester);
      expect(find.text('No scripts'), findsOneWidget);

      final scriptName = '${testPrefix}_script';
      await saveLuaScript(tester, scriptName, 'return 1');
      expect(find.text(scriptName), findsWidgets);

      // Rename and save again (same script id).
      final renamed = '${scriptName}_v2';
      // re_editor 同款坑：面板内 Lua 代码编辑器持 IME 连接，第二次
      // enterText 的文本被路由到代码编辑器、名字段 controller 不更新
      // （实测探针：enterText 后 controller 仍旧值）——按 enterLuaCode
      // 的既有惯例直接写 controller。
      tester.widget<TextField>(luaNameField()).controller!.text = renamed;
      await tester.pump();
      await tapElevated(tester, 'Save');
      expect(find.text('Scripts (1)'), findsOneWidget);
      expect(find.text(renamed), findsWidgets);

      // Delete with confirmation dialog.
      await tapElevated(tester, 'Delete');
      expect(find.text('Delete script?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('No scripts'), findsOneWidget);
      expect(find.text('Scripts (0)'), findsOneWidget);

      await closeDialog(tester);
    });

    testWidgets('W3.4 Lua: Sync to Server stores SHA1', (tester) async {
      if (!redisE2EGatewayReady) return;
      await openLuaPanel(tester);

      const code = 'return redis.call("GET", KEYS[1])';
      await saveLuaScript(tester, '${testPrefix}_sync', code);
      await tapElevated(tester, 'Sync');

      await waitForSnack(tester, 'Synced, SHA:');
      expect(find.text('synced'), findsOneWidget);

      // Server-side: sha present in the script cache.
      final sha = await adapter.scriptLoad(code);
      final exists = await adapter.scriptExists([sha]);
      expect(exists, [true], reason: 'SCRIPT LOAD not visible server-side');

      await closeDialog(tester);
    });

    testWidgets('W3.5 Lua: Run EVALSHA then NOSCRIPT fallback to EVAL', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await openLuaPanel(tester);

      const code = 'return redis.call("GET", KEYS[1])';
      await saveLuaScript(tester, '${testPrefix}_run', code);
      await tapElevated(tester, 'Sync');

      // KEYS = luaKey -> returns 'hello-lua' (EVALSHA path).
      await tester.enterText(
        find.ancestor(
          of: find.text('key1, key2'),
          matching: find.byType(TextField),
        ),
        luaKey,
      );
      await tapElevated(tester, 'Run (EVALSHA→EVAL)');
      expect(find.text('hello-lua'), findsOneWidget);

      // Modify the script: stored sha is now stale -> NOSCRIPT -> fallback.
      await enterLuaCode(tester, 'return ARGV[1]');
      await tester.enterText(
        find.ancestor(
          of: find.text('arg1, arg2'),
          matching: find.byType(TextField),
        ),
        'fallback-ok',
      );
      await tapElevated(tester, 'Run (EVALSHA→EVAL)');
      expect(
        find.text('fallback-ok'),
        findsOneWidget,
        reason: 'NOSCRIPT fallback to EVAL failed',
      );

      await closeDialog(tester);
    });

    testWidgets('W3.6 Lua: Flush server script cache', (tester) async {
      if (!redisE2EGatewayReady) return;
      await openLuaPanel(tester);

      const code = 'return 1';
      await saveLuaScript(tester, '${testPrefix}_flush', code);
      await tapElevated(tester, 'Sync');

      final sha = await adapter.scriptLoad(code);
      expect(await adapter.scriptExists([sha]), [true]);

      final flushBtn = find.widgetWithText(TextButton, 'Flush');
      expect(flushBtn, findsOneWidget);
      await tester.tap(flushBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await waitForSnack(tester, 'Server script cache flushed');
      expect(
        await adapter.scriptExists([sha]),
        [false],
        reason: 'SCRIPT FLUSH did not invalidate cached sha',
      );

      await closeDialog(tester);
    });
  });
}

// =============================================================================
// Sidebar harness for Redis (mirrors SidebarWidget state management).
// Copied from redis_sidebar_menu_e2e_test.dart (private there).
// =============================================================================
class _SidebarTestHarness extends StatefulWidget {
  final AppProvider provider;

  const _SidebarTestHarness({required this.provider});

  @override
  State<_SidebarTestHarness> createState() => _SidebarTestHarnessState();
}

class _SidebarTestHarnessState extends State<_SidebarTestHarness> {
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
    setState(() {
      if (_expandedTables.contains(key)) {
        _expandedTables = _expandedTables.where((e) => e != key).toSet();
      } else {
        _expandedTables = {..._expandedTables, key};
      }
    });
  }

  Future<void> _loadDatabaseInfo(
    String connectionId,
    String databaseName,
  ) async {
    final key = '$connectionId:$databaseName';
    setState(() => _loadingDatabases = {..._loadingDatabases, key});
    try {
      await widget.provider.loadRedisDatabaseKeyInfo(
        connectionId,
        databaseName,
      );
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
