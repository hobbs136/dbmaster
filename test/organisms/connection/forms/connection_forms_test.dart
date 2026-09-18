// C08 · per-type 连接表单模块测试。
// 覆盖：注册表分发（8 类型命中 + SS 兜底 null）、各类型会话
// collect 往返（保存→重开→字段无损的等价断言）、forSave 密码语义、
// TD extra 镜像、Redis 三态/db index、Mongo 集群 extra（键常量表）、
// 壳的类型导航切换。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/connection_dialog.dart';
import 'package:dbmaster/organisms/connection/forms/connection_extra_keys.dart';
import 'package:dbmaster/organisms/connection/forms/mongodb_connection_form.dart';
import 'package:dbmaster/organisms/connection/forms/mysql_connection_form.dart';
import 'package:dbmaster/organisms/connection/forms/redis_connection_form.dart';
import 'package:dbmaster/organisms/connection/forms/sqlite_connection_form.dart';
import 'package:dbmaster/organisms/connection/forms/tdengine_connection_form.dart';
import 'package:dbmaster/organisms/connection/forms/mongo_connection_mode.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/plugins/connection_form_plugin.dart';
import 'package:dbmaster/plugins/plugin_registry.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectionFormPluginContext ctxFor(
    DatabaseType type,
    DbServer server,
  ) =>
      ConnectionFormPluginContext(
        type: type,
        draft: ConnectionDraft(server),
      );

  group('注册表分发（C08 注册 8 件 + SS 兜底）', () {
    test('registerDefaultUiPlugins：8 类型各命中专属插件，SS 无命中', () {
      final registry = PluginRegistry();
      registerDefaultUiPlugins(registry);
      final expected = <DatabaseType, String>{
        DatabaseType.mysql: 'mysql-connection-plugin',
        DatabaseType.postgresql: 'postgresql-connection-plugin',
        DatabaseType.mongodb: 'mongodb-connection-plugin',
        DatabaseType.sqlite: 'sqlite-connection-plugin',
        DatabaseType.redis: 'redis-connection-plugin',
        DatabaseType.doris: 'doris-connection-plugin',
        DatabaseType.tdengine: 'tdengine-connection-plugin',
        DatabaseType.clickhouse: 'clickhouse-connection-plugin',
      };
      expected.forEach((type, id) {
        final plugin = registry.connectionFormFor(type);
        expect(plugin, isNotNull, reason: '$type 应有专属表单');
        expect(plugin!.descriptor.id, id);
      });
      // SQL Server 押后至 C20（与 T28 同窗）：无注册 → 宿主回退通用表单
      expect(registry.connectionFormFor(DatabaseType.sqlserver), isNull);
    });
  });

  group('MySQL / Doris（charset/timezone + forSave 密码语义）', () {
    test('MySQL：编辑回填 + collect 往返无损', () {
      final server = DbServer(
        id: 'srv-1',
        name: 'prod',
        type: DatabaseType.mysql,
        host: '192.0.2.128',
        port: 3306,
        username: 'root',
        password: 'secret',
        database: 'chinook',
        charset: 'gbk',
        timezone: '+08:00',
        timeoutSeconds: 45,
      );
      final session = MySqlConnectionFormSession(ctxFor(DatabaseType.mysql, server));
      final collected = session.collect(forSave: true)!;
      expect(collected.host, '192.0.2.128');
      expect(collected.port, 3306);
      expect(collected.charset, 'gbk');
      expect(collected.timezone, '+08:00');
      expect(collected.timeoutSeconds, 45);
      expect(collected.database, 'chinook');
      // 编辑态 password 非空 → savePassword=true → forSave 保留密码
      expect(collected.password, 'secret');
      session.dispose();
    });

    test('forSave=false（测试连接）：密码总是携带，不受 savePassword 影响', () {
      final server = DbServer(
        id: 'srv-2',
        name: 'n',
        type: DatabaseType.mysql,
        host: 'h',
        port: 3306,
      );
      final session = MySqlConnectionFormSession(ctxFor(DatabaseType.mysql, server));
      session.passwordController.text = 'pw';
      session.savePassword = false;
      final collected = session.collect(forSave: false)!;
      expect(collected.password, 'pw');
      // forSave=true 且未勾选保存密码 → 不携带（既有语义）
      final saved = session.collect(forSave: true)!;
      expect(saved.password, isNull);
      session.dispose();
    });
  });

  group('SQLite（路径承载 + 只读）', () {
    test('collect：host=路径、port=0、username/password 不适用', () {
      final server = DbServer(
        id: 'sq',
        name: 'local',
        type: DatabaseType.sqlite,
        host: 'C:/data/chinook.db',
        port: 0,
        readOnly: true,
      );
      final session = SqliteConnectionFormSession(ctxFor(DatabaseType.sqlite, server));
      final collected = session.collect(forSave: true)!;
      expect(collected.type, DatabaseType.sqlite);
      expect(collected.host, 'C:/data/chinook.db');
      expect(collected.port, 0);
      expect(collected.username, isNull);
      expect(collected.password, isNull);
      expect(collected.readOnly, isTrue);
      session.dispose();
    });

    test('空路径 → collect 返回 null（校验拦截）', () {
      final server = DbServer(
        id: 'sq2',
        name: 'x',
        type: DatabaseType.sqlite,
        host: '',
        port: 0,
      );
      final session = SqliteConnectionFormSession(ctxFor(DatabaseType.sqlite, server));
      expect(session.collect(), isNull);
      session.dispose();
    });
  });

  group('Redis（auth 三态 + db index = database 字段承载）', () {
    RedisConnectionFormSession sessionOf(DbServer server) =>
        RedisConnectionFormSession(ctxFor(DatabaseType.redis, server));

    test('三态回填：username+password → ACL；仅 password → passwordOnly', () {
      final acl = sessionOf(DbServer(
        id: 'r1', name: 'r', type: DatabaseType.redis,
        host: 'h', port: 6379, username: 'default', password: 'p',
      ));
      expect(acl.authMode, RedisAuthMode.usernamePassword);
      final pwOnly = sessionOf(DbServer(
        id: 'r2', name: 'r', type: DatabaseType.redis,
        host: 'h', port: 6379, password: 'p',
      ));
      expect(pwOnly.authMode, RedisAuthMode.passwordOnly);
      acl.dispose();
      pwOnly.dispose();
    });

    test('db index：db2 回填为 2，collect 写回纯数字串', () {
      final session = sessionOf(DbServer(
        id: 'r3', name: 'r', type: DatabaseType.redis,
        host: 'h', port: 6379, database: 'db2',
      ));
      expect(session.databaseController.text, '2');
      final collected = session.collect()!;
      expect(collected.database, '2');
      session.dispose();
    });

    test('无认证态：collect 凭据双 null', () {
      final session = sessionOf(DbServer(
        id: 'r4', name: 'r', type: DatabaseType.redis,
        host: 'h', port: 6379, username: 'default', password: 'p',
      ));
      session.authMode = RedisAuthMode.none;
      final collected = session.collect()!;
      expect(collected.username, isNull);
      expect(collected.password, isNull);
      session.dispose();
    });
  });

  group('TDengine（超时镜像 extra）', () {
    test('collect：timeoutSeconds 镜像进 extra[timeout]，adapter 实际消费该键', () {
      final server = DbServer(
        id: 'td', name: 'td', type: DatabaseType.tdengine,
        host: 'h', port: 6041, username: 'root', timeoutSeconds: 60,
      );
      final session =
          TDengineConnectionFormSession(ctxFor(DatabaseType.tdengine, server));
      final collected = session.collect()!;
      expect(collected.timeoutSeconds, 60);
      expect(collected.extra?[ConnectionExtraKeys.tdTimeout], 60);
      session.dispose();
    });
  });

  group('MongoDB 集群 extra（键常量表，spec 044 契约）', () {
    test('replicaSet 模式：extra 三键齐备且 direct 模式为 null（向后兼容）', () {
      final base = DbServer(
        id: 'm', name: 'm', type: DatabaseType.mongodb,
        host: 'h', port: 27017, username: 'admin',
      );
      final direct = MongodbConnectionFormSession(ctxFor(DatabaseType.mongodb, base));
      expect(direct.buildExtra(), isNull);
      direct.dispose();

      final rs = MongodbConnectionFormSession(ctxFor(DatabaseType.mongodb, base));
      rs.mode = MongoConnectionMode.replicaSet;
      rs.hostsController.text = '10.0.0.1:27018\n10.0.0.2:27018';
      rs.replicaSetController.text = 'rs0';
      final extra = rs.buildExtra()!;
      expect(extra[ConnectionExtraKeys.mongoConnectionMode], 'replicaSet');
      expect(extra[ConnectionExtraKeys.mongoHosts], ['10.0.0.1:27018', '10.0.0.2:27018']);
      expect(extra[ConnectionExtraKeys.mongoReplicaSet], 'rs0');
      rs.dispose();
    });

    test('advanced 模式：凭据剥离（FR-007），host/port 派生首节点', () {
      final base = DbServer(
        id: 'm2', name: 'm', type: DatabaseType.mongodb,
        host: 'h', port: 27017,
      );
      final s = MongodbConnectionFormSession(ctxFor(DatabaseType.mongodb, base));
      s.mode = MongoConnectionMode.advanced;
      s.connStringController.text =
          'mongodb://alice:s3cret@cluster.example.net:27017/?authSource=admin';
      // 新连接存量密码为空 → savePassword=false；勾选后 forSave 才携带
      // （URI 凭据与手输密码同受「保存密码」开关约束——重建前既有语义）
      s.savePassword = true;
      final collected = s.collect(forSave: true)!;
      expect(collected.username, 'alice');
      expect(collected.password, 's3cret');
      expect(collected.host, 'cluster.example.net');
      expect(collected.port, 27017);
      final uri = collected.extra![ConnectionExtraKeys.mongoConnectionString] as String;
      expect(uri, 'mongodb://cluster.example.net:27017/?authSource=admin');
      expect(uri.contains('@'), isFalse);
      s.dispose();
    });
  });

  group('壳 · 类型导航切换（widget）', () {
    testWidgets('切换类型 → 端口默认值与插件徽章跟随', (tester) async {
      if (defaultPluginRegistry.pluginCount == 0) {
        registerDefaultUiPlugins(defaultPluginRegistry);
      }
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      final provider = AppProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(body: ConnectionDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ConnectionDialog)),
      )!;
      // 初始 MySQL：footer 徽章 + 端口 3306（导航提示与端口输入框各一处）
      expect(
        find.text(l10n.connectionFormProvidedBy('mysql-connection-plugin')),
        findsOneWidget,
      );
      expect(find.text('3306'), findsAtLeastNWidgets(1));

      // 点左栏 PostgreSQL → 端口 5432 + 徽章切换
      await tester.tap(find.text(DatabaseType.postgresql.displayName));
      await tester.pumpAndSettle();
      expect(find.text('5432'), findsAtLeastNWidgets(1));
      expect(
        find.text(l10n.connectionFormProvidedBy('postgresql-connection-plugin')),
        findsOneWidget,
      );

      // 点 SQL Server → 无注册插件 → 通用兜底徽章（C20 前形态）
      await tester.tap(find.text(DatabaseType.sqlserver.displayName));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.connectionFormProvidedBy('core-connection-form')),
        findsOneWidget,
      );
      expect(find.text('1433'), findsAtLeastNWidgets(1));
    });

    testWidgets('编辑态：类型导航禁用——点其他类型不切换表单', (tester) async {
      if (defaultPluginRegistry.pluginCount == 0) {
        registerDefaultUiPlugins(defaultPluginRegistry);
      }
      await tester.binding.setSurfaceSize(const Size(1200, 900));
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
                  id: 'edit-1',
                  name: 'prod mysql',
                  type: DatabaseType.mysql,
                  host: '192.0.2.128',
                  port: 3306,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ConnectionDialog)),
      )!;
      // 编辑既有连接：类型是固有属性，点 PostgreSQL 不生效——仍为 MySQL 表单
      await tester.tap(find.text(DatabaseType.postgresql.displayName));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.connectionFormProvidedBy('mysql-connection-plugin')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.connectionFormProvidedBy('postgresql-connection-plugin')),
        findsNothing,
      );
    });
  });
}
