// RedisKeyEditorDialog widget 测试。
//
// 验证：
//   1. footer 假 "Save Changes" 按钮已移除（原 _saveChanges 空桩清理）
//   2. footer 含 Close 按钮（取代 Cancel，更准确：editor Save 已可能改数据）
//   3. dialog 渲染 StringEditor 不抛异常
//
// 不覆盖：各 editor 内部行为（各 editor 自有测试或 adapter 层覆盖）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/redis_key_editor/redis_key_editor_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// pump 出 RedisKeyEditorDialog，type 控制分发到哪个 editor。
  /// 真实 AppProvider() 无连接 → getRedisAdapter 返 null → editor 走错误态分支
  /// （dialog 自身不依赖 adapter，只分发到 editor）。
  Future<void> pumpDialog(
    WidgetTester tester, {
    String type = 'string',
  }) async {
    final provider = AppProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RedisKeyEditorDialog(
                  keyName: 'test-key',
                  type: type,
                  connectionId: 'test-conn',
                  databaseName: 'db0',
                  provider: provider,
                ),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
  }

  group('RedisKeyEditorDialog', () {
    testWidgets('footer 不含假 "Save Changes" 按钮（空桩已清理）', (tester) async {
      await pumpDialog(tester);

      // "Save Changes" 文案（l10n key redisKeySaveChanges）不应出现
      expect(find.text('Save Changes'), findsNothing);
    });

    testWidgets('footer 含 Close 按钮（取代 Cancel）', (tester) async {
      await pumpDialog(tester);

      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('dialog 分发到 StringEditor 不抛异常', (tester) async {
      await pumpDialog(tester, type: 'string');

      // dialog 标题（key name）应显示
      expect(find.text('test-key'), findsOneWidget);
      // Type 标签
      expect(find.textContaining('Type: String'), findsOneWidget);
    });
  });
}
