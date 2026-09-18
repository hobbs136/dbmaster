import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/l10n/app_localizations_zh.dart';
import 'package:dbmaster/l10n/app_localizations_de.dart';
import 'package:dbmaster/l10n/app_localizations_fr.dart';
import 'package:dbmaster/l10n/app_localizations_ru.dart';

void main() {
  group('AppLocalizations', () {
    final localizations = <AppLocalizations>[
      AppLocalizationsEn(),
      AppLocalizationsZh(),
      AppLocalizationsDe(),
      AppLocalizationsFr(),
      AppLocalizationsRu(),
    ];

    test('所有语言应有非空的 localeName', () {
      for (final l10n in localizations) {
        expect(l10n.localeName, isNotEmpty);
      }
    });

    test('英文本地化应有基本的应用标题', () {
      final en = AppLocalizationsEn();
      expect(en.appTitle, 'DbMaster');
    });

    test('中文本地化应有中文应用标题', () {
      final zh = AppLocalizationsZh();
      expect(zh.appTitle, isNotEmpty);
      // 中文标题应包含中文字符或 DbMaster
      expect(
        zh.appTitle.contains('DbMaster') || _containsChinese(zh.appTitle),
        isTrue,
      );
    });

    test('所有语言应有非空的应用标题', () {
      for (final l10n in localizations) {
        expect(
          l10n.appTitle,
          isNotEmpty,
          reason: '${l10n.localeName} appTitle should not be empty',
        );
      }
    });

    test('所有语言应有基本的导航标签', () {
      for (final l10n in localizations) {
        expect(
          l10n.sidebarConnections,
          isNotEmpty,
          reason: '${l10n.localeName} sidebarConnections should not be empty',
        );
        expect(
          l10n.sidebarDatabases,
          isNotEmpty,
          reason: '${l10n.localeName} sidebarDatabases should not be empty',
        );
      }
    });

    test('所有语言应有查询相关标签', () {
      for (final l10n in localizations) {
        expect(
          l10n.queryExecute,
          isNotEmpty,
          reason: '${l10n.localeName} queryExecute should not be empty',
        );
        expect(
          l10n.queryHistory,
          isNotEmpty,
          reason: '${l10n.localeName} queryHistory should not be empty',
        );
      }
    });

    test('所有语言应有 AI 相关标签', () {
      for (final l10n in localizations) {
        expect(
          l10n.aiAssistant,
          isNotEmpty,
          reason: '${l10n.localeName} aiAssistant should not be empty',
        );
      }
    });

    test('所有语言应有设置相关标签', () {
      for (final l10n in localizations) {
        expect(
          l10n.settingsTitle,
          isNotEmpty,
          reason: '${l10n.localeName} settingsTitle should not be empty',
        );
      }
    });

    test('AppLocalizations.supportedLocales 应包含所有支持的语言', () {
      expect(AppLocalizations.supportedLocales.length, greaterThanOrEqualTo(5));
    });

    test('AppLocalizations.localizationsDelegates 不应为空', () {
      expect(AppLocalizations.localizationsDelegates, isNotEmpty);
    });

    test('各语言本地化类应实现 AppLocalizations', () {
      expect(AppLocalizationsEn(), isA<AppLocalizations>());
      expect(AppLocalizationsZh(), isA<AppLocalizations>());
      expect(AppLocalizationsDe(), isA<AppLocalizations>());
      expect(AppLocalizationsFr(), isA<AppLocalizations>());
      expect(AppLocalizationsRu(), isA<AppLocalizations>());
    });
  });
}

bool _containsChinese(String text) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
}
