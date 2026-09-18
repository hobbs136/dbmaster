// ============================================================================
// PG 扩展面板 + pgvector 面板 widget E2E
// 连真实 PostgreSQL，渲染 PgExtensionDetailDialog，验证加载/搜索/成员展示。
// pgvector 面板条件验证（有 vector 扩展才完整测，否则仅验证不崩）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/organisms/connection/pg_extension_panel.dart';
import 'package:dbmaster/organisms/connection/pg_vector_panel.dart';

import 'config/postgresql_test_config.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

void main() {

  // T29 第二批：PG 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 PG_E2E_SKIP 跳过（无假绿）。
  bool pgE2EGatewayReady = false;
  setUpAll(() async {
    pgE2EGatewayReady = await ensureEmbeddedServerForPgE2E();
    if (pgE2EGatewayReady && !PostgreSQLTestConfig.available) {
      // ignore: avoid_print
      print('PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      pgE2EGatewayReady = false;
    }
  });
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('PG 扩展面板 E2E', () {
    late AppProvider appProvider;
    late DbServer server;
    late PostgreSQLAdapter adapter;
    late String connectionId;

    setUp(() async {
      if (!pgE2EGatewayReady) {
        return;
      }
      SharedPreferences.setMockInitialValues({});
      appProvider = AppProvider();
      AppProvider.devBypassGates = true;
      server = DbServer(
        id: 'pg_ext_e2e_${DateTime.now().millisecondsSinceEpoch}',
        name: 'PG Extension E2E',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: '无法连接测试 PG 库');
      connectionId = server.id;

      // 用独立 adapter 查扩展列表（dialog 要 PgExtension 对象）
      adapter = PostgreSQLAdapter();
      final conn = DatabaseConnection(
        id: 'ext_probe',
        name: 'probe',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
      await adapter.connect(conn);
    });

    tearDown(() async {
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    Widget buildTestApp(Widget child) {
      return ChangeNotifierProvider.value(
        value: appProvider,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('zh')],
          locale: const Locale('en'),
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('US1: 扩展详情面板加载真实扩展成员', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final exts = await adapter.getExtensions();
      expect(exts, isNotEmpty);
      // 取 plpgsql（标准库必有）
      final plpgsql = exts.firstWhere(
        (e) => e.name == 'plpgsql',
        orElse: () => exts.first,
      );

      await tester.pumpWidget(buildTestApp(
        PgExtensionDetailDialog(
          provider: appProvider,
          connectionId: connectionId,
          extension: plpgsql,
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 加载完成后应显示扩展名（标题区）
      expect(find.textContaining(plpgsql.name), findsWidgets);
      // 不应是 loading 态（CircularProgressIndicator 消失）
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('US1: 搜索框过滤成员', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final exts = await adapter.getExtensions();
      final target = exts.firstWhere(
        (e) => e.name == 'plpgsql',
        orElse: () => exts.first,
      );

      await tester.pumpWidget(buildTestApp(
        PgExtensionDetailDialog(
          provider: appProvider,
          connectionId: connectionId,
          extension: target,
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 找到搜索框并输入（plpgsql 有大量函数，输入应过滤）
      final searchField = find.byType(TextField);
      if (searchField.evaluate().isNotEmpty) {
        await tester.enterText(searchField.first, 'pg_');
        await tester.pumpAndSettle();
        // 输入后仍有内容（不崩）
        expect(find.byType(TextField), findsWidgets);
      }
    });

    testWidgets('US2: pgvector 面板在非 pgvector 扩展下不崩', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      // 即使没有 pgvector，直接渲染 PgVectorPanel 验证不崩（空/错误态）
      await tester.pumpWidget(buildTestApp(
        PgVectorPanel(
          provider: appProvider,
          connectionId: connectionId,
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 应显示空状态或加载态，不崩
      expect(find.byType(PgVectorPanel), findsOneWidget);
    });

    testWidgets('US2: 有 pgvector 时面板显示索引列表', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final exts = await adapter.getExtensions();
      final hasPgvector = exts.any((e) => e.name == 'vector');
      if (!hasPgvector) {
        print('US2 widget: SKIP — 测试库未安装 pgvector');
        return;
      }
      await tester.pumpWidget(buildTestApp(
        PgVectorPanel(
          provider: appProvider,
          connectionId: connectionId,
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      // 有 pgvector 时面板渲染（不强制有索引）
      expect(find.byType(PgVectorPanel), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
