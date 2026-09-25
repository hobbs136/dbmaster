import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_de.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/l10n/app_localizations_fr.dart';
import 'package:dbmaster/l10n/app_localizations_ru.dart';
import 'package:dbmaster/l10n/app_localizations_zh.dart';

/// workbench 前缀 key 的六语完整性校验（design 开放问题 5 的落点）。
///
/// 直接读取六个 ARB 源文件断言：
/// 1. 五语 workbench key 集合与 en 模板完全一致；
/// 2. 所有 workbench 值非空；
/// 3. 带参 key 的占位符名称与类型和 en 模板一致；
/// 4. 生成类六语均可取到 workbench 文案（ARB → gen-l10n 链路健全）。
void main() {
  const languages = ['zh', 'zh_TW', 'de', 'fr', 'ru'];

  Map<String, dynamic> loadArb(String locale) {
    final file = File(Directory.current.path + '/lib/l10n/app_$locale.arb');
    if (!file.existsSync()) {
      throw StateError('ARB 文件不存在: ${file.path}');
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// 提取 workbench 前缀的文案 key（排除 @ 元数据）。
  List<String> workbenchKeys(Map<String, dynamic> arb) =>
      arb.keys
          .where((k) => k.startsWith('workbench') && !k.startsWith('@'))
          .toList()
        ..sort();

  final enArb = loadArb('en');
  final enKeys = workbenchKeys(enArb);

  group('workbench l10n 六语完整性', () {
    test('en 模板包含全部 workbench key（含 workbenchErrorEmptySql）', () {
      // R2（T18，2026-09-22）：+7 上下文选择器 key（workbenchContextSwitchTip
      // + workbenchContextPicker* 6 个），基线 31 → 38。
      expect(enKeys.length, 38);
      expect(enKeys, contains('workbenchErrorEmptySql'));
      expect(enKeys, contains('workbenchContextPickerTitle'));
    });

    test('五语 workbench key 集合与 en 模板一致', () {
      for (final lang in languages) {
        final keys = workbenchKeys(loadArb(lang));
        expect(
          keys,
          unorderedEquals(enKeys),
          reason:
              '$lang 的 workbench key 集合应与 en 模板一致'
              '（缺失: ${enKeys.where((k) => !keys.contains(k)).toList()}'
              '；多余: ${keys.where((k) => !enKeys.contains(k)).toList()}）',
        );
      }
    });

    test('六语 workbench 值均非空', () {
      for (final locale in ['en', ...languages]) {
        final arb = loadArb(locale);
        for (final key in enKeys) {
          final value = arb[key];
          expect(value, isA<String>(), reason: '$locale/$key 应为字符串');
          expect(
            (value as String).trim(),
            isNotEmpty,
            reason: '$locale/$key 的值不应为空',
          );
        }
      }
    });

    test('带参 key 的占位符名称与类型和 en 模板一致', () {
      Map<String, String>? placeholdersOf(
        Map<String, dynamic> arb,
        String key,
      ) {
        final meta = arb['@$key'] as Map<String, dynamic>?;
        final raw = meta?['placeholders'] as Map<String, dynamic>?;
        return raw?.map(
          (k, v) => MapEntry(k, (v as Map<String, dynamic>)['type'] as String),
        );
      }

      for (final lang in languages) {
        final arb = loadArb(lang);
        for (final key in enKeys) {
          expect(
            placeholdersOf(arb, key),
            placeholdersOf(enArb, key),
            reason: '$lang/$key 的占位符应与 en 模板一致',
          );
        }
      }
    });

    test('生成类六语均可取到 workbench 文案（含新增 workbenchErrorEmptySql）', () {
      final instances = <AppLocalizations>[
        AppLocalizationsEn(),
        AppLocalizationsZh(),
        AppLocalizationsZhTw(),
        AppLocalizationsDe(),
        AppLocalizationsFr(),
        AppLocalizationsRu(),
      ];
      for (final l10n in instances) {
        expect(
          l10n.workbenchTitle,
          isNotEmpty,
          reason: '${l10n.localeName} workbenchTitle',
        );
        expect(
          l10n.workbenchErrorEmptySql,
          isNotEmpty,
          reason: '${l10n.localeName} workbenchErrorEmptySql',
        );
        // 占位符参数应真实参与拼串（结果卡元信息）。
        final meta = l10n.workbenchResultMeta(3, 42);
        expect(
          meta.contains('3'),
          isTrue,
          reason: '${l10n.localeName} rows 占位符',
        );
        expect(
          meta.contains('42'),
          isTrue,
          reason: '${l10n.localeName} ms 占位符',
        );
      }
    });
  });
}
