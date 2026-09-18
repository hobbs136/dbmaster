// StringEditor widget 测试。
//
// 覆盖：
//   1. 无 adapter 错误态（null 守卫生效，显示 Retry）
//   2. 有 adapter：GET 命令调用、值显示、Save 按钮渲染
//   3. Save 走 runCommand(['SET', key, value]) —— value 作为单独 bulk 参数，
//      含空格/特殊字符不损坏（修复前 'SET key value' 拼接会让 'hello world' 只存 'hello'）
//   4. Save 失败显示红色 SnackBar
//
// 不覆盖：adapter 层 SET/GET 语义（redis_adapter_test.dart 已大量覆盖 runCommand）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/organisms/redis_key_editor/editors/string_editor.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Fake RedisAdapter —— 重写 runCommand 记录调用并返回可控响应。
/// 不连接真实 Redis；用于 widget 测试验证 UI 接线。
class _FakeRedisAdapter extends RedisAdapter {
  _FakeRedisAdapter({this.getValue = 'initial-value'});

  final String? getValue;
  final List<List<String>> calls = [];
  Object? setCommandError;

  @override
  Future<dynamic> runCommand(List<String> args) async {
    calls.add(List<String>.from(args));
    final cmd = args.isEmpty ? '' : args.first.toUpperCase();
    if (cmd == 'GET') return getValue;
    if (cmd == 'SET') {
      if (setCommandError != null) throw setCommandError!;
      return 'OK';
    }
    return null;
  }
}

/// Fake AppProvider —— 重写 getRedisAdapter 返回可控 adapter。
class _FakeAppProvider extends AppProvider {
  _FakeAppProvider(this.adapter);
  final RedisAdapter? adapter;

  @override
  RedisAdapter? getRedisAdapter(String connectionId) => adapter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required AppProvider provider,
    String keyName = 'test-key',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StringEditor(
            keyName: keyName,
            connectionId: 'test-conn',
            databaseName: 'db0',
            provider: provider,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('StringEditor', () {
    testWidgets('无 adapter 时显示 "Redis adapter not available" + Retry 按钮', (
      tester,
    ) async {
      final provider = _FakeAppProvider(null);
      await pumpEditor(tester, provider: provider);

      expect(find.text('Redis adapter not available'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // 错误态分支不应渲染 Save 按钮
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(LucideIcons.save), findsNothing);
    });

    testWidgets('有 adapter 时调 GET 命令加载值 + 渲染 Save 按钮', (tester) async {
      final adapter = _FakeRedisAdapter(getValue: 'hello world');
      final provider = _FakeAppProvider(adapter);
      await pumpEditor(tester, provider: provider);

      // GET 命令被调用，key 作为单独参数（不拼接）
      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.first, ['GET', 'test-key']);

      // 值显示在文本框里
      expect(find.text('hello world'), findsOneWidget);

      // Save 按钮渲染
      expect(find.text('Save'), findsOneWidget);
      expect(find.byIcon(LucideIcons.save), findsOneWidget);
    });

    testWidgets('点击 Save 调用 runCommand(["SET", key, value])，value 含空格不损坏', (
      tester,
    ) async {
      final adapter = _FakeRedisAdapter(getValue: 'initial');
      final provider = _FakeAppProvider(adapter);
      await pumpEditor(tester, provider: provider);

      // 修改文本为含空格的值
      await tester.enterText(find.byType(TextField), 'hello world with spaces');
      await tester.pump();

      // 只观察 Save 触发的 SET 调用（清掉之前 GET 的记录）
      adapter.calls.clear();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // SET 命令被调用，key + value 作为独立参数（不拼接）
      // 修复前 'SET ${key} ${value}' 拼接会让 'hello world' 只存 'hello'。
      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.first, [
        'SET',
        'test-key',
        'hello world with spaces',
      ]);

      // 成功 SnackBar
      expect(find.text('String saved successfully'), findsOneWidget);
    });

    testWidgets('value 含特殊字符（换行/引号）也作为单参数完整传入', (tester) async {
      final adapter = _FakeRedisAdapter(getValue: 'x');
      final provider = _FakeAppProvider(adapter);
      await pumpEditor(tester, provider: provider);

      const special = 'line1\nline2 "quoted" `backtick`';
      await tester.enterText(find.byType(TextField), special);
      await tester.pump();

      adapter.calls.clear();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.first, ['SET', 'test-key', special]);
    });

    testWidgets('Save 失败时显示红色 "Failed to save value" SnackBar', (tester) async {
      final adapter = _FakeRedisAdapter();
      adapter.setCommandError = Exception('Redis write failed');
      final provider = _FakeAppProvider(adapter);
      await pumpEditor(tester, provider: provider);

      // GET 在 initState 已调用成功；只对 SET 抛错
      expect(adapter.calls.any((c) => c.first == 'GET'), isTrue);

      await tester.enterText(find.byType(TextField), 'new-value');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // SET 被调用但抛错 → 错误 SnackBar
      expect(find.textContaining('Failed to save value'), findsOneWidget);
      // 不应显示成功 SnackBar
      expect(find.text('String saved successfully'), findsNothing);
    });
  });
}
