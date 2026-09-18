// ============================================================================
// Redis Sidebar Menu End-to-End Integration Tests
// Tests: Real Redis server + full SidebarTree widget + context menus + dialogs
// Target: real Redis via DBMASTER_REDIS_* (see config/redis_test_config.dart)
//
// NOTE: This is intentionally Redis-specific. Redis has no databases/tables in
// the SQL sense; its sidebar exposes databases (dbN), key type categories,
// namespaces, TTL keys, DB stats and global INFO sections. Do not copy MySQL
// concepts (views, procedures, triggers, events, schema diff, etc.) here.
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:dbmaster/organisms/connection/connection_dialog.dart';
import 'package:dbmaster/organisms/connection/connection_export_import_dialog.dart';
import 'package:dbmaster/organisms/redis_key_editor/redis_key_editor_dialog.dart';
import 'package:dbmaster/organisms/redis_pubsub/redis_pubsub_panel.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_connection_selector.dart';
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

  group('Redis Sidebar Menu E2E', () {
    late AppProvider appProvider;
    late RedisAdapter adapter;
    late String testPrefix;
    late DbServer server;

    const connectionLabel = 'Redis Sidebar E2E';

    // Seeded key names.
    late String seedStringKey;
    late String seedHashKey;
    late String seedListKey;
    late String seedSetKey;
    late String seedZSetKey;
    late String seedNsUserKey;
    late String seedNsOrderKey;
    late String seedTtlKey;

    setUp(() async {
      adapter = RedisAdapter();
      testPrefix = RedisTestConfig.generateTestKeyPrefix();

      seedStringKey = '${testPrefix}_string';
      seedHashKey = '${testPrefix}_hash';
      seedListKey = '${testPrefix}_list';
      seedSetKey = '${testPrefix}_set';
      seedZSetKey = '${testPrefix}_zset';
      seedNsUserKey = '$testPrefix:user:1';
      seedNsOrderKey = '$testPrefix:order:1';
      // Apply TTL to the string key itself so there are only 3 string samples;
      // this guarantees seedStringKey appears in the first 3 string samples.
      seedTtlKey = seedStringKey;

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

      // Start from a clean DB so leftover keys from earlier failed runs do not
      // inflate type counts or push seeded keys out of the sampled top-3.
      await adapter.runCommand(['FLUSHDB']);

      await adapter.runCommand(['SET', seedStringKey, 'hello']);
      await adapter.runCommand(['HSET', seedHashKey, 'field', 'value']);
      await adapter.runCommand(['LPUSH', seedListKey, 'item']);
      await adapter.runCommand(['SADD', seedSetKey, 'member']);
      await adapter.runCommand(['ZADD', seedZSetKey, '1', 'member']);
      await adapter.runCommand(['SET', seedNsUserKey, 'alice']);
      await adapter.runCommand(['SET', seedNsOrderKey, 'order1']);
      await adapter.runCommand(['EXPIRE', seedStringKey, '60']);

      // 2. Connect the provider so it picks up the seeded database.
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      server = DbServer(
        id: 'redis_sidebar_e2e_${testPrefix.hashCode}',
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

      // Pre-load Redis-specific info so the tree can render key buckets,
      // namespaces and TTL keys without relying on async tree taps.
      await appProvider.loadRedisDatabaseKeyInfo(
        server.id,
        RedisTestConfig.database,
      );
      await appProvider.loadRedisTTLKeys(server.id, RedisTestConfig.database);
      await appProvider.loadRedisDBStats(server.id, RedisTestConfig.database);

      // Verify seeded keys are visible in the target DB; if this fails,
      // subsequent "Keys category" / key-menu tests cannot find sample leaves.
      final keyInfo = appProvider.connection.getRedisDatabaseKeyInfo(
        server.id,
        RedisTestConfig.database,
      );
      expect(keyInfo, isNotNull, reason: 'Redis key info not loaded');
      final typeCount = keyInfo!['typeCount'] as Map?;
      expect(
        typeCount,
        isNotEmpty,
        reason:
            'No key types found in ${RedisTestConfig.database}; seeded keys may be in the wrong DB',
      );
      expect(
        typeCount!['string'],
        greaterThanOrEqualTo(1),
        reason: 'Seeded string key not found in key info',
      );
    });

    tearDown(() async {
      try {
        final keys = await adapter.scanKeys(pattern: '$testPrefix*');
        if (keys.isNotEmpty) {
          await adapter.runCommand(['DEL', ...keys]);
        }
      } catch (e) {
        AppLogger.d('RedisSidebarE2E', 'Cleanup DEL failed: $e');
      }
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
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
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> rightClickNode(WidgetTester tester, String label) async {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(TreeItem),
      );
      expect(finder, findsOneWidget, reason: 'Node "$label" not found');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(finder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> rightClickNodeContaining(
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
      await tester.tap(finder.last, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> tapMenuItem(WidgetTester tester, String label) async {
      final menuFinder = find.byType(ContextMenu);
      expect(menuFinder, findsOneWidget, reason: 'Context menu not open');
      final finder = find.descendant(
        of: menuFinder,
        matching: find.text(label),
      );
      expect(finder, findsOneWidget, reason: 'Menu item "$label" not found');
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> tapPopupMenuItem(WidgetTester tester, String label) async {
      // byType 是精确类型匹配——db 菜单项已统一 CompactPopupMenuItem
      // （PopupMenuItem 子类），须按谓词做子类型匹配（历史 4 失败根因）。
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String>,
        ),
      );
      expect(finder, findsOneWidget, reason: 'Popup menu item not found');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> tapDialogButton(WidgetTester tester, String label) async {
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

    Future<void> expandConnection(WidgetTester tester) async {
      await tapNode(tester, connectionLabel);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandDatabase(WidgetTester tester, String dbName) async {
      await tapNode(tester, dbName);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandKeys(WidgetTester tester) async {
      await tapNode(tester, 'Keys');
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandNamespaces(WidgetTester tester) async {
      await tapNode(tester, 'Namespaces');
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandExpiringSoon(WidgetTester tester) async {
      await tapNode(tester, 'Expiring Soon');
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandDbInfo(WidgetTester tester) async {
      await tapNode(tester, 'DB Info');
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandGlobalNode(WidgetTester tester, String label) async {
      await tapNode(tester, label);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<bool> keyExists(String key) async {
      final serviceAdapter =
          appProvider.dbService.getAdapter(server.id) as RedisAdapter;
      final result = await serviceAdapter.runCommand(['EXISTS', key]);
      return (result as int) > 0;
    }

    Future<int> currentRedisTtl(String key) async {
      final serviceAdapter =
          appProvider.dbService.getAdapter(server.id) as RedisAdapter;
      return serviceAdapter.getTTL(key);
    }

    Future<void> setTtlViaDialog(
      WidgetTester tester,
      String key,
      String value, {
      String? chipLabel,
    }) async {
      await rightClickNodeContaining(tester, key);
      await tapMenuItem(tester, 'Set TTL');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      if (chipLabel != null) {
        final chip = find.widgetWithText(ChoiceChip, chipLabel);
        expect(chip, findsOneWidget, reason: 'TTL mode chip not found');
        await tester.tap(chip);
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      }
      await tester.enterText(find.byType(TextField).first, value);
      await tester.pump();
      await tapDialogButton(tester, 'Confirm');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(AlertDialog), findsNothing);
    }

    Future<void> doubleTapNode(WidgetTester tester, String label) async {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(TreeItem),
      );
      expect(finder, findsOneWidget, reason: 'Node "$label" not found');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

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

    Future<void> setClipboardMock(
      WidgetTester tester,
      void Function(String?) onCaptured,
    ) async {
      if (!redisE2EGatewayReady) return;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            onCaptured(call.arguments['text'] as String?);
            return null;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    // ----------------------------------------------------------------------
    // Connection node menu
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Disconnect disconnects the connection', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Disconnect');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.isConnectionConnected(server.id), isFalse);
    });

    testWidgets(
      'connection selector connects a saved disconnected server',
      (tester) async {
        if (!redisE2EGatewayReady) return;
        await pumpHarness(tester);
        await expandConnection(tester);

        const disconnectedLabel = 'Redis Sidebar E2E Disconnected';
        final disconnectedServer = DbServer(
          id: '${server.id}_disconnected',
          name: disconnectedLabel,
          type: DatabaseType.redis,
          host: server.host,
          port: server.port,
          password: server.password,
          database: server.database,
        );
        await appProvider.connection.saveConnection(disconnectedServer);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(
          appProvider.isConnectionConnected(disconnectedServer.id),
          isFalse,
        );

        // C22-1 单实例树：未连接的已保存连接不在树里，入口是顶部选择器下拉
        //（点下拉箭头打开；find.byType(PopupMenuItem) 精确匹配不到
        // PopupMenuItem<String> 实例，点项用 find.text 的 overlay 命中）。
        await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.tap(find.text(disconnectedLabel).last);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(
          appProvider.isConnectionConnected(disconnectedServer.id),
          isTrue,
        );
      },
    );

    testWidgets('connection node single-click switches active connection', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await tapNode(tester, connectionLabel);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(appProvider.connection.currentServer?.id, equals(server.id));
    });

    testWidgets(
      'connection root row double-click reconnects a disconnected connection',
      (tester) async {
        if (!redisE2EGatewayReady) return;
        await pumpHarness(tester);
        await expandConnection(tester);

        // 断开当前连接（右键菜单 Disconnect）。
        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Disconnect');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(appProvider.isConnectionConnected(server.id), isFalse);

        // 断开后树可能失去 currentServer 锚定——显式选中保住根行渲染。
        appProvider.sidebar.selectConnection(server.id);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // C22-1：根行双击在未连接态走连接流程。
        await doubleTapNode(tester, connectionLabel);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(appProvider.isConnectionConnected(server.id), isTrue);
      },
    );

    testWidgets('connection menu > Refresh refreshes database list', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Refresh');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final dbs = appProvider.connection.databases;
      expect(dbs, contains(RedisTestConfig.database));
    });

    testWidgets('connection menu > Edit Connection opens ConnectionDialog', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Edit Connection');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(ConnectionDialog), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('connection menu > Clone Connection clones the server', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      final before = appProvider.connection.savedConnections.length;

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Clone Connection');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        appProvider.connection.savedConnections.length,
        equals(before + 1),
      );
    });

    testWidgets(
      'connection menu > Export This Connection opens export dialog',
      (tester) async {
        if (!redisE2EGatewayReady) return;
        await pumpHarness(tester);
        await expandConnection(tester);

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Export This Connection');
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.byType(ConnectionExportImportDialog), findsOneWidget);

        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      },
    );

    testWidgets('connection menu > Toggle Read-Only changes read-only flag', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      final initial =
          appProvider.connection.getServerById(server.id)?.readOnly ?? false;

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(
        tester,
        initial ? 'Disable Read-Only' : 'Enable Read-Only',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final updated =
          appProvider.connection.getServerById(server.id)?.readOnly ?? false;
      expect(updated, equals(!initial));
    });

    testWidgets('connection menu > Collapse All collapses expanded nodes', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Collapse All');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Keys'), findsNothing);
    });

    testWidgets(
      'connection menu > Delete Connection removes the saved connection',
      (tester) async {
        if (!redisE2EGatewayReady) return;
        await pumpHarness(tester);
        await expandConnection(tester);

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Delete Connection');
        await tapDialogButton(tester, 'Delete');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(appProvider.connection.getServerById(server.id), isNull);
      },
    );

    testWidgets(
      'connection menu > Move to Group moves and removes the connection',
      (tester) async {
        if (!redisE2EGatewayReady) return;
        await pumpHarness(tester);
        await expandConnection(tester);

        const groupName = 'Redis E2E Group';
        final groupId = 'redis_e2e_group_${testPrefix.hashCode}';
        await appProvider.addConnectionGroup(
          ConnectionGroup(id: groupId, name: groupName, color: '#FF0000'),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Move to $groupName');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(
          appProvider.connection.savedConnections
              .firstWhere((s) => s.id == server.id)
              .groupId,
          equals(groupId),
        );

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Remove from Group');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(
          appProvider.connection.savedConnections
              .firstWhere((s) => s.id == server.id)
              .groupId,
          isNull,
        );
      },
    );

    // ----------------------------------------------------------------------
    // Database node menu
    // ----------------------------------------------------------------------
    testWidgets('database menu > Select DB switches current database', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);

      await rightClickNode(tester, RedisTestConfig.database);
      await tapPopupMenuItem(tester, 'Select DB');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        appProvider.connection.currentDatabase?.name,
        equals(RedisTestConfig.database),
      );
    });

    testWidgets('database menu > Refresh reloads database objects', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);

      await rightClickNode(tester, RedisTestConfig.database);
      await tapPopupMenuItem(tester, 'Refresh');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Keys'), findsOneWidget);
    });

    testWidgets('database menu > New Key creates a key via the dialog', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);

      await rightClickNode(tester, RedisTestConfig.database);
      await tapPopupMenuItem(tester, 'New Key');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final newKey = '${testPrefix}_new_key';
      final fields = find.byType(TextField);
      expect(fields, findsAtLeastNWidgets(2));
      await tester.enterText(fields.at(0), newKey);
      await tester.enterText(fields.at(1), 'new_value');
      await tester.pump();

      await tapDialogButton(tester, 'Add');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byType(AlertDialog), findsNothing);
      expect(await keyExists(newKey), isTrue);
    });

    testWidgets('database menu > Flush DB opens a FLUSHDB query tab', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);

      await rightClickNode(tester, RedisTestConfig.database);
      await tapPopupMenuItem(tester, 'Flush DB');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tapDialogButton(tester, 'Flush DB');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.tab.tabs.any((t) => t.title == 'FLUSHDB'), isTrue);
    });

    testWidgets('database double-click opens a query tab', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await doubleTapNode(tester, RedisTestConfig.database);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs, isNotEmpty);
    });

    testWidgets('database node tap selects the database', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await tapNode(tester, RedisTestConfig.database);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        appProvider.connection.currentDatabase?.name,
        equals(RedisTestConfig.database),
      );
    });

    // ----------------------------------------------------------------------
    // Keys category
    // ----------------------------------------------------------------------
    testWidgets('Keys category expands and renders key type buckets', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      expect(find.text('String (3)'), findsOneWidget);
      expect(find.text('Hash (1)'), findsOneWidget);
      expect(find.text('List (1)'), findsOneWidget);
      expect(find.text('Set (1)'), findsOneWidget);
      expect(find.text('Sorted Set (1)'), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // Key node menu
    // ----------------------------------------------------------------------
    testWidgets('key menu > Browse Data opens the Redis key editor dialog', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await rightClickNodeContaining(tester, seedStringKey);
      await tapMenuItem(tester, 'Browse Data');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(RedisKeyEditorDialog), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('key menu > Browse Data opens the editor for a hash key', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await rightClickNodeContaining(tester, seedHashKey);
      await tapMenuItem(tester, 'Browse Data');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(RedisKeyEditorDialog), findsOneWidget);
      expect(find.textContaining('Type: Hash'), findsWidgets);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('key menu > Copy Value opens a GET query tab', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await rightClickNodeContaining(tester, seedStringKey);
      await tapMenuItem(tester, 'Copy Value');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        appProvider.tab.tabs.any((t) => t.title == 'GET $seedStringKey'),
        isTrue,
      );
    });

    testWidgets('key menu > Copy column name copies the key name', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      String? captured;
      await setClipboardMock(tester, (text) => captured = text);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await rightClickNodeContaining(tester, seedStringKey);
      await tapMenuItem(tester, 'Copy column name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, equals(seedStringKey));
    });

    // Set TTL 走对话框直接调 adapter（EXPIRE/PEXPIRE/EXPIREAT 三模式），
    // 每个模式独立用例 + 独立 harness，避免树刷新后的右键菜单竞争。
    // TTL 统一设为 120s（< 300s 阈值），不影响后续 Expiring Soon 用例。
    testWidgets('key menu > Set TTL (seconds) sets EXPIRE via dialog', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await setTtlViaDialog(tester, seedStringKey, '120');
      expect(await currentRedisTtl(seedStringKey), inInclusiveRange(1, 120));
    });

    testWidgets('key menu > Set TTL (ms) sets PEXPIRE via dialog', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await setTtlViaDialog(
        tester,
        seedStringKey,
        '120000',
        chipLabel: 'Milli (PEXPIRE)',
      );
      expect(await currentRedisTtl(seedStringKey), inInclusiveRange(1, 120));
    });

    testWidgets('key menu > Set TTL (at) sets EXPIREAT via dialog', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      final at = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 120;
      await setTtlViaDialog(
        tester,
        seedStringKey,
        '$at',
        chipLabel: 'At (EXPIREAT)',
      );
      expect(await currentRedisTtl(seedStringKey), inInclusiveRange(1, 120));

      // Restore the short seed TTL for the "Expiring Soon" test case.
      final adapter =
          appProvider.dbService.getAdapter(server.id) as RedisAdapter;
      await adapter.setTTL(seedStringKey, const Duration(seconds: 60));
    });

    testWidgets('key menu > Remove TTL opens a PERSIST query tab', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await rightClickNodeContaining(tester, seedStringKey);
      await tapMenuItem(tester, 'Remove TTL');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs.any((t) => t.title == 'PERSIST'), isTrue);
    });

    testWidgets('key menu > Rename opens a RENAME query tab', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await rightClickNodeContaining(tester, seedStringKey);
      await tapMenuItem(tester, 'Rename');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.enterText(
        find.byType(TextField).first,
        '${seedStringKey}_renamed',
      );
      await tester.pump();
      await tapDialogButton(tester, 'Confirm');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs.any((t) => t.title == 'RENAME'), isTrue);
    });

    testWidgets('key menu > Delete opens a DEL query tab', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await rightClickNodeContaining(tester, seedStringKey);
      await tapMenuItem(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs.any((t) => t.title == 'DEL'), isTrue);
    });

    testWidgets('key double-click opens the Redis key editor dialog', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      await doubleTapNodeContaining(tester, seedStringKey);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(RedisKeyEditorDialog), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('key leaf single-click selects the leaf node', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandKeys(tester);

      final keyFinder = find.ancestor(
        of: find.textContaining(seedStringKey),
        matching: find.byType(TreeItem),
      );
      expect(keyFinder, findsAtLeastNWidgets(1));

      await tester.ensureVisible(keyFinder.last);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(keyFinder.last);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final keyItem = tester.widget<TreeItem>(keyFinder.last);
      expect(keyItem.isSelected, isTrue);
    });

    // ----------------------------------------------------------------------
    // Database children: Namespaces / Expiring Soon / DB Info
    // ----------------------------------------------------------------------
    testWidgets('Namespaces node expands and shows seeded namespaces', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandNamespaces(tester);

      expect(find.textContaining('$testPrefix:'), findsWidgets);
    });

    testWidgets('Expiring Soon node expands and shows the TTL key', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandExpiringSoon(tester);

      expect(find.textContaining(seedTtlKey), findsOneWidget);
    });

    testWidgets('DB Info node expands and shows key count', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, RedisTestConfig.database);
      await expandDbInfo(tester);

      expect(find.textContaining('Keys:'), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // Global nodes
    // ----------------------------------------------------------------------
    testWidgets('Server global node expands and loads server info', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandGlobalNode(tester, 'Server');

      expect(find.textContaining('Redis'), findsWidgets);
      expect(find.textContaining('Mode'), findsOneWidget);
    });

    testWidgets('Memory global node expands and shows memory info', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandGlobalNode(tester, 'Memory');

      expect(find.textContaining('Used:'), findsOneWidget);
    });

    testWidgets('Stats global node expands and shows statistics', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandGlobalNode(tester, 'Stats');

      expect(find.textContaining('Commands:'), findsOneWidget);
    });

    testWidgets('Clients global node expands and shows client info', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandGlobalNode(tester, 'Clients');

      expect(find.textContaining('Connected:'), findsOneWidget);
    });

    testWidgets('Config global node expands and shows configuration', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandGlobalNode(tester, 'Config');

      expect(find.textContaining('Databases:'), findsOneWidget);
    });

    testWidgets('Slow Log global node expands', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandGlobalNode(tester, 'Slow Log');

      expect(
        find.textContaining('No slow queries').evaluate().isNotEmpty ||
            find.textContaining('μs').evaluate().isNotEmpty,
        isTrue,
      );
    });

    testWidgets('Pub/Sub node opens the Pub/Sub panel dialog', (tester) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);
      await expandConnection(tester);

      final pubSubFinder = find.ancestor(
        of: find.text('Pub/Sub'),
        matching: find.byType(TreeItem),
      );
      expect(pubSubFinder, findsOneWidget);
      await tester.ensureVisible(pubSubFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(pubSubFinder);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(RedisPubSubPanel), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    // ----------------------------------------------------------------------
    // Drag-and-drop
    // ----------------------------------------------------------------------
    testWidgets('connection grouping via menu shows in selector dropdown', (
      tester,
    ) async {
      if (!redisE2EGatewayReady) return;
      await pumpHarness(tester);

      const groupName = 'Redis E2E Drag Group';
      final groupId = 'redis_e2e_drag_group_${testPrefix.hashCode}';
      await appProvider.addConnectionGroup(
        ConnectionGroup(id: groupId, name: groupName, color: '#00FF00'),
      );

      final secondServer = DbServer(
        id: '${server.id}_ingroup',
        name: 'Redis Sidebar E2E In Group',
        type: DatabaseType.redis,
        host: server.host,
        port: server.port,
        password: server.password,
        database: server.database,
        groupId: groupId,
      );
      await appProvider.connection.saveConnection(secondServer);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await expandConnection(tester);

      // C22-1：树内拖拽随连接卡下线，移组入口 = 根行右键菜单。
      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Move to $groupName');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        appProvider.connection.savedConnections
            .firstWhere((s) => s.id == server.id)
            .groupId,
        groupId,
      );

      // 选择器下拉按组分区：组头 + 组内成员可见。
      await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text(groupName), findsOneWidget);
      expect(find.text('Redis Sidebar E2E In Group'), findsOneWidget);
    });
  });
}

// =============================================================================
// Sidebar harness for Redis (mirrors SidebarWidget state management).
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
      // C22-1：树只渲染当前连接——连接已保存服务器的入口是顶部选择器下拉。
      body: Column(
        children: [
          SidebarConnectionSelector(
            onConnectionTap: (server) async {
              final ok = await widget.provider.connectToServer(server);
              if (ok) await widget.provider.refreshDatabases();
            },
            onManageConnections: () {},
          ),
          Expanded(
            child: SidebarTree(
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
          ),
        ],
      ),
    );
  }
}
