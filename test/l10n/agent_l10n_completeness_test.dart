import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_de.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/l10n/app_localizations_fr.dart';
import 'package:dbmaster/l10n/app_localizations_ru.dart';
import 'package:dbmaster/l10n/app_localizations_zh.dart';

/// agent 前缀 key 的六语完整性校验（T33，NF4.1/4.2 发布门；镜像
/// workbench_l10n_completeness_test.dart 的模式）。
///
/// 直接读取六个 ARB 源文件断言：
/// 1. en 模板 agent* key 全集为 116（含 agentStage* / agentArtifact* /
///    agentPlanDmlHigh*）；
/// 2. 五语 agent* key 集合与 en 模板完全一致（无缺键）；
/// 3. 所有 agent* 值非空；
/// 4. 带参 key 的占位符名称与类型和 en 模板一致；
/// 5. 抽查 10 个代表 key（标题/动作/状态/tab）五语非空且不等于英文原文；
/// 6. 生成类六语均可取到 agent 文案、占位符真实参与拼串（ARB → gen-l10n 链路健全）；
/// 7. 守卫：en 的 workbench* key 计数保持 38（agent 族补齐不得串扰 workbench 族）。
void main() {
  const languages = ['zh', 'zh_TW', 'de', 'fr', 'ru'];

  Map<String, dynamic> loadArb(String locale) {
    final file = File(Directory.current.path + '/lib/l10n/app_$locale.arb');
    if (!file.existsSync()) {
      throw StateError('ARB 文件不存在: ${file.path}');
    }
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// 提取 agent 前缀的文案 key（排除 @ 元数据）。
  List<String> agentKeys(Map<String, dynamic> arb) =>
      arb.keys
          .where((k) => k.startsWith('agent') && !k.startsWith('@'))
          .toList()
        ..sort();

  final enArb = loadArb('en');
  final enKeys = agentKeys(enArb);

  group('agent l10n 六语完整性', () {
    test('en 模板包含全部 agent key（116，含 agentPlanDmlHigh* 两 key）', () {
      expect(enKeys.length, 116);
      expect(enKeys, contains('agentTrajectoryTitle'));
      expect(enKeys, contains('agentStageTabGrid'));
      expect(enKeys, contains('agentArtifactEmpty'));
      expect(enKeys, contains('agentPlanDmlHighBadge'));
      expect(enKeys, contains('agentPlanDmlHighTriggers'));
    });

    test('五语 agent key 集合与 en 模板一致（无缺键）', () {
      for (final lang in languages) {
        final keys = agentKeys(loadArb(lang));
        expect(
          keys,
          unorderedEquals(enKeys),
          reason:
              '$lang 的 agent key 集合应与 en 模板一致'
              '（缺失: ${enKeys.where((k) => !keys.contains(k)).toList()}'
              '；多余: ${keys.where((k) => !enKeys.contains(k)).toList()}）',
        );
      }
    });

    test('六语 agent 值均非空', () {
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

    test('抽查 10 个代表 key：五语非空且不等于英文原文', () {
      // 标题 3（轨迹/确认/计划）+ 舞台开关 + 动作 3（批准/会话允许/生成回退）
      // + 状态 2（待批准/部分失败）+ 舞台 tab 1（网格）。
      const representatives = [
        'agentTrajectoryTitle',
        'agentConfirmReadTitle',
        'agentPlanTitle',
        'agentStageToggle',
        'agentPlanApprove',
        'agentConfirmAllowSession',
        'agentPlanGenerateRollback',
        'agentPlanStatusPending',
        'agentPlanStatusPartialFailed',
        'agentStageTabGrid',
      ];
      expect(representatives.length, 10);
      for (final lang in languages) {
        final arb = loadArb(lang);
        for (final key in representatives) {
          final value = arb[key] as String;
          expect(
            value.trim(),
            isNotEmpty,
            reason: '$lang/$key 应非空',
          );
          expect(
            value,
            isNot(enArb[key]),
            reason: '$lang/$key 不应保留英文原文（应为本语译文）',
          );
        }
      }
    });

    test('生成类六语均可取到 agent 文案且占位符参与拼串', () {
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
          l10n.agentTrajectoryTitle,
          isNotEmpty,
          reason: '${l10n.localeName} agentTrajectoryTitle',
        );
        expect(
          l10n.agentPlanApprove,
          isNotEmpty,
          reason: '${l10n.localeName} agentPlanApprove',
        );
        // 占位符参数应真实参与拼串。
        final tokens = l10n.agentSessionTokens('1337');
        expect(
          tokens.contains('1337'),
          isTrue,
          reason: '${l10n.localeName} agentSessionTokens n 占位符: $tokens',
        );
        final meta = l10n.agentStepResultMeta(1204, 12, 128);
        for (final part in ['1204', '12', '128']) {
          expect(
            meta.contains(part),
            isTrue,
            reason: '${l10n.localeName} agentStepResultMeta 占位符: $meta',
          );
        }
        final steps = l10n.agentTrajectorySteps(3, 25);
        expect(
          steps.contains('3') && steps.contains('25'),
          isTrue,
          reason: '${l10n.localeName} agentTrajectorySteps 占位符: $steps',
        );
        final triggers = l10n.agentPlanDmlHighTriggers('UPDATE, DELETE');
        expect(
          triggers.contains('UPDATE, DELETE'),
          isTrue,
          reason: '${l10n.localeName} agentPlanDmlHighTriggers 占位符: $triggers',
        );
      }
    });

    test('守卫：en 的 workbench key 计数保持 38（agent 族补齐不串扰）', () {
      final wbKeys =
          enArb.keys
              .where((k) => k.startsWith('workbench') && !k.startsWith('@'))
              .toList()
            ..sort();
      expect(wbKeys.length, 38);
      // 两个词根集合互不重叠。
      expect(
        wbKeys.where((k) => k.startsWith('agent')),
        isEmpty,
      );
      expect(
        enKeys.where((k) => k.startsWith('workbench')),
        isEmpty,
      );
    });
  });
}
