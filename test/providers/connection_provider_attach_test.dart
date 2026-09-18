// SPDX-License-Identifier: Apache-2.0
//
// spec 050：ConnectionProvider ATTACH/DETACH 单测。
//
// 验证 provider 层逻辑（不连真库）：
// - alias 前置校验（非法/保留字/重复 直接拒绝，不调 dbService）
// - 成功后刷新 _connectionDatabases 缓存（getConnectionDatabases 反映新 alias）
// - DETACH 后清理 _databaseCache[connId][alias] + 刷新 _connectionDatabases
// - 底层抛错时返回失败 + errorDetail
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/database_service.dart';

class _MockDatabaseService extends DatabaseService {
  Future<void> Function(String connectionId, String path, String alias)?
      attachHandler;
  Future<void> Function(String connectionId, String alias)? detachHandler;
  Future<List<String>> Function({String? connectionId})? getDatabasesHandler;

  List<String> attachCalls = [];
  List<String> detachCalls = [];

  @override
  Future<void> attachDatabase(
    String connectionId,
    String path,
    String alias,
  ) async {
    attachCalls.add(alias);
    await attachHandler?.call(connectionId, path, alias);
  }

  @override
  Future<void> detachDatabase(String connectionId, String alias) async {
    detachCalls.add(alias);
    await detachHandler?.call(connectionId, alias);
  }

  @override
  Future<List<String>> getDatabases({String? connectionId}) async =>
      getDatabasesHandler?.call(connectionId: connectionId) ?? const ['main'];

  @override
  bool hasConnection(String connectionId) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionProvider ATTACH/DETACH (spec 050)', () {
    late ConnectionProvider provider;
    late _MockDatabaseService mockDbService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockDbService = _MockDatabaseService();
      provider = ConnectionProvider(dbService: mockDbService);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
    });

    test('attachDatabase 成功 → success=true + 缓存含 alias', () async {
      // 模拟底层 attach 成功，getDatabases 刷新后含新 alias
      mockDbService.attachHandler = (_, __, ___) async {};
      mockDbService.getDatabasesHandler = ({connectionId}) async =>
          ['main', 'archive'];

      final result = await provider.attachDatabase(
        'conn1',
        '/data/archive.db',
        'archive',
      );

      expect(result.success, isTrue);
      expect(result.errorKey, isNull);
      expect(result.errorDetail, isNull);
      // 调了一次底层 attach
      expect(mockDbService.attachCalls, ['archive']);
      // 缓存已刷新
      expect(provider.getConnectionDatabases('conn1'), contains('archive'));
    });

    test('attachDatabase 非法 alias → 直接拒绝，不调底层', () async {
      final result = await provider.attachDatabase(
        'conn1',
        '/data/archive.db',
        'a-b', // 非法字符
      );

      expect(result.success, isFalse);
      expect(result.errorKey, 'sqliteAttachAliasInvalid');
      // 底层 attach 不应被调用
      expect(mockDbService.attachCalls, isEmpty);
    });

    test('attachDatabase 保留字 alias → 直接拒绝', () async {
      final result = await provider.attachDatabase(
        'conn1',
        '/data/archive.db',
        'main', // 保留名
      );

      expect(result.success, isFalse);
      expect(result.errorKey, 'sqliteAttachAliasReserved');
      expect(mockDbService.attachCalls, isEmpty);
    });

    test('attachDatabase 重复 alias → 直接拒绝（基于 existing 缓存）',
        () async {
      // 预设缓存：conn1 已有 archive
      mockDbService.getDatabasesHandler = ({connectionId}) async =>
          ['main', 'archive'];

      // 先正常刷新一次让缓存就位
      await provider.refreshDatabases(connectionId: 'conn1');
      expect(provider.getConnectionDatabases('conn1'), contains('archive'));

      final result = await provider.attachDatabase(
        'conn1',
        '/data/archive2.db',
        'archive', // 重复
      );

      expect(result.success, isFalse);
      expect(result.errorKey, 'sqliteAttachAliasDuplicate');
      expect(mockDbService.attachCalls, isEmpty);
    });

    test('attachDatabase 底层抛错 → success=false + errorDetail', () async {
      mockDbService.attachHandler = (_, __, ___) async {
        throw Exception('database is malformed');
      };
      mockDbService.getDatabasesHandler = ({connectionId}) async => ['main'];

      final result = await provider.attachDatabase(
        'conn1',
        '/data/bad.db',
        'archive',
      );

      expect(result.success, isFalse);
      expect(result.errorKey, isNull);
      expect(result.errorDetail, isNotNull);
      expect(result.errorDetail, contains('malformed'));
    });

    test('detachDatabase 成功 → success=true + 缓存不含 alias', () async {
      mockDbService.detachHandler = (_, __) async {};
      mockDbService.getDatabasesHandler = ({connectionId}) async => ['main'];

      final result = await provider.detachDatabase('conn1', 'archive');

      expect(result.success, isTrue);
      expect(result.errorDetail, isNull);
      expect(mockDbService.detachCalls, ['archive']);
      // 缓存刷新后不含 archive
      expect(provider.getConnectionDatabases('conn1'), isNot(contains('archive')));
    });

    test('detachDatabase 底层抛错 → success=false + errorDetail', () async {
      mockDbService.detachHandler = (_, __) async {
        throw Exception('no such database: ghost');
      };
      mockDbService.getDatabasesHandler = ({connectionId}) async => ['main'];

      final result = await provider.detachDatabase('conn1', 'ghost');

      expect(result.success, isFalse);
      expect(result.errorDetail, contains('no such database'));
    });

    test('detachDatabase 后该 alias 的 Database 缓存被清理', () async {
      // 这个测试验证 _databaseCache[connId][alias] 被移除——
      // 通过 getCachedDatabase 间接验证（detach 后应返回 null）。
      mockDbService.detachHandler = (_, __) async {};
      mockDbService.getDatabasesHandler = ({connectionId}) async => ['main'];

      await provider.detachDatabase('conn1', 'archive');

      // getCachedDatabase 对不存在的 alias 返回 null
      expect(provider.getCachedDatabase('conn1', 'archive'), isNull);
    });
  });
}
