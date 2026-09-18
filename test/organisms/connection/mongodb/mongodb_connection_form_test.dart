// spec 044 T010 — MongoDB 集群连接表单 widget 测试。
// 覆盖：模式切换渲染、extra 回填、空种子校验、Pro 门控（Free 拒绝 + Pro 放行）。
// 用 setupHistoryTestBinding 等价的 channel mock（Pigeon + SharedPreferences +
// FlutterSecureStorage）；Pro 态经 ProModule SPI 注入 FakeProModule。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/connection_dialog.dart';
import 'package:dbmaster/organisms/connection/forms/mongo_connection_mode.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/providers/app_provider.dart';

import '../../../helpers/fake_pro_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pigeonAndroid = 'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi';
  const pigeonStorekit =
      'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchaseApi';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(secureChannel, (call) async => null);
    messenger.setMockMessageHandler(
      pigeonAndroid,
      (message) async =>
          const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
    );
    messenger.setMockMessageHandler(
      pigeonStorekit,
      (message) async =>
          const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
    );
    // C08：新壳经 defaultPluginRegistry 分发表单；main() 的注册在测试进程
    // 不执行，此处幂等补注册（全局单例，重复注册会因 id 冲突抛错）。
    if (defaultPluginRegistry.pluginCount == 0) {
      registerDefaultUiPlugins(defaultPluginRegistry);
    }
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(secureChannel, null);
    messenger.setMockMessageHandler(pigeonAndroid, null);
    messenger.setMockMessageHandler(pigeonStorekit, null);
  });

  /// 泵起 ConnectionDialog（MongoDB 类型），返回树中的 AppProvider。
  Future<AppProvider> pumpMongoDialog(
    WidgetTester tester, {
    Map<String, dynamic>? extra,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    final provider = AppProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: ConnectionDialog(
              existingServer: DbServer(
                id: 't',
                name: 't',
                type: DatabaseType.mongodb,
                host: 'localhost',
                port: 27017,
                extra: extra,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(ConnectionDialog).first))!;

  Finder mongoModeDropdown() => find.byWidgetPredicate(
        (w) => w is DropdownButton<MongoConnectionMode>,
      );

  group('MongoDB 集群连接表单（spec 044 T010）', () {
    testWidgets('Direct 模式：渲染模式选择器，但不渲染种子/副本集名字段', (tester) async {
      await pumpMongoDialog(tester);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.connectionMongoMode), findsOneWidget);
      expect(mongoModeDropdown(), findsOneWidget);
      expect(find.text(l10n.connectionMongoSeedHosts), findsNothing);
      expect(find.text(l10n.connectionMongoReplicaSetName), findsNothing);
      // Direct 模式：上方 host/port 行正常显示
      expect(find.text(l10n.connectionHost), findsOneWidget);
    });

    testWidgets('Replica Set 模式：渲染种子列表 + 副本集名，且从 extra 回填', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'replicaSet',
          'mongoHosts': [
            '192.0.2.128:27018',
            '192.0.2.128:27019',
            '192.0.2.128:27020',
          ],
          'mongoReplicaSet': 'rs0',
        },
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.connectionMongoSeedHosts), findsOneWidget);
      expect(find.text(l10n.connectionMongoReplicaSetName), findsOneWidget);
      // Replica Set 模式：上方 host/port 行隐藏（避免与种子列表重复误导）
      expect(find.text(l10n.connectionHost), findsNothing);
      // 回填校验：值在 TextFormField 的 controller 里（EditableText），非 Text widget
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EditableText &&
              w.controller.text.contains('192.0.2.128:27018'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'rs0',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Replica Set 空种子列表 → Save 触发校验错误', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'replicaSet',
          'mongoHosts': <String>[],
          'mongoReplicaSet': 'rs0',
        },
      );
      final l10n = l10nOf(tester);
      final saveBtn = find.text(l10n.commonSave);
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(find.text(l10n.connectionMongoSeedHostsRequired), findsOneWidget);
    });

    // Pro 门控在下拉 onChanged 中调用 tryMongoCluster；此处直接断言该门本身的 Free/Pro 语义
    // （dialog 据此决定是否 setState 切换模式——Free false ⇒ 不切 ⇒ 保持 Direct）。
    // M1 客户端免费化（spec 001 T020）后，tryMongoCluster 恒为 true。
    // 原断言「Free 拒绝 + pendingUpgradeFeature」已不符合新语义，更新为恒放行。
    test('门控移除：tryMongoCluster 恒放行（M1 免费化）', () async {
      final provider = AppProvider();
      final allowed = provider.tryMongoCluster('mongo_cluster_test_free');
      expect(allowed, isTrue);
      expect(provider.pendingUpgradeFeature, isNull);
    });

    test('Pro 门控：Pro → tryMongoCluster 放行，无升级标记', () async {
      // Phase A: 注入 FakeProModule(isPro=true) 替代 PurchaseService.debugSetProForTesting
      final provider = AppProvider(proModule: FakeProModule(isPro: true));
      final allowed = provider.tryMongoCluster('mongo_cluster_test_pro');
      expect(allowed, isTrue);
      expect(provider.pendingUpgradeFeature, isNull);
    });

    // ── US3 Advanced 模式（spec 044 T024/T029）──
    testWidgets('Advanced 模式：渲染连接串粘贴框，不渲染种子/副本集名/host', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'advanced',
          'mongoConnectionString': 'mongodb://cluster.example.net:27017',
        },
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.connectionMongoConnectionString), findsOneWidget);
      expect(find.text(l10n.connectionMongoSeedHosts), findsNothing);
      expect(find.text(l10n.connectionMongoReplicaSetName), findsNothing);
      // host/port 行在 advanced 模式也隐藏（避免与粘贴串重复误导）
      expect(find.text(l10n.connectionHost), findsNothing);
    });

    testWidgets('Advanced 模式：回填 credential-free 串且无 @（FR-007）', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'advanced',
          'mongoConnectionString':
              'mongodb+srv://cluster.example.net/?authSource=admin',
        },
      );
      final field = find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            w.controller.text ==
                'mongodb+srv://cluster.example.net/?authSource=admin',
      );
      expect(field, findsOneWidget);
      // 回填的 credentialFreeUri 绝不含 @（凭据已剥离）
      final text = tester.widget<EditableText>(field).controller.text;
      expect(text.contains('@'), isFalse);
    });

    testWidgets('Advanced 模式：空连接串 → Save 触发校验错误', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'advanced',
          'mongoConnectionString': '',
        },
      );
      final l10n = l10nOf(tester);
      await tester.ensureVisible(find.text(l10n.commonSave));
      await tester.tap(find.text(l10n.commonSave));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.connectionMongoConnectionStringRequired),
        findsOneWidget,
      );
    });

    // ── US2 Sharded 模式（spec 044 T018）──
    testWidgets('Sharded 模式：渲染 mongos 路由列表，隐藏种子/副本集名/连接串/host', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'sharded',
          'mongoHosts': ['mongos1.example.net:27017', 'mongos2.example.net:27017'],
        },
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.connectionMongoMongosHosts), findsOneWidget);
      expect(find.text(l10n.connectionMongoSeedHosts), findsNothing);
      expect(find.text(l10n.connectionMongoReplicaSetName), findsNothing);
      expect(find.text(l10n.connectionMongoConnectionString), findsNothing);
      expect(find.text(l10n.connectionHost), findsNothing); // host/port 隐藏
    });

    testWidgets('Sharded 模式：空 mongos 列表 → Save 触发校验错误', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'sharded',
          'mongoHosts': <String>[],
        },
      );
      final l10n = l10nOf(tester);
      await tester.ensureVisible(find.text(l10n.commonSave));
      await tester.tap(find.text(l10n.commonSave));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.connectionMongoMongosHostsRequired),
        findsOneWidget,
      );
    });

    testWidgets('Sharded/ReplicaSet：host:port 格式非法 → 校验错误', (tester) async {
      await pumpMongoDialog(
        tester,
        extra: {
          'mongoConnectionMode': 'sharded',
          'mongoHosts': ['mongos1.example.net:notaport'],
        },
      );
      final l10n = l10nOf(tester);
      await tester.ensureVisible(find.text(l10n.commonSave));
      await tester.tap(find.text(l10n.commonSave));
      await tester.pumpAndSettle();
      expect(find.text(l10n.connectionMongoInvalidHostPort), findsOneWidget);
    });
  });
}
