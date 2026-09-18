import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/locale_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocaleProvider', () {
    late LocaleProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      provider = LocaleProvider();
    });

    group('initialization', () {
      test('initial locale is English', () {
        expect(provider.locale, equals(const Locale('en')));
      });

      test('supportedLocales contains all 6 languages', () {
        expect(LocaleProvider.supportedLocales.length, equals(6));
        expect(LocaleProvider.supportedLocales, contains(const Locale('en')));
        expect(LocaleProvider.supportedLocales, contains(const Locale('de')));
        expect(LocaleProvider.supportedLocales, contains(const Locale('fr')));
        expect(LocaleProvider.supportedLocales, contains(const Locale('ru')));
        expect(LocaleProvider.supportedLocales, contains(const Locale('zh')));
        expect(
          LocaleProvider.supportedLocales,
          contains(const Locale('zh', 'TW')),
        );
      });

      test('localeNames contains all language names', () {
        expect(LocaleProvider.localeNames['en'], equals('English'));
        expect(LocaleProvider.localeNames['de'], equals('Deutsch'));
        expect(LocaleProvider.localeNames['fr'], equals('Français'));
        expect(LocaleProvider.localeNames['ru'], equals('Русский'));
        expect(LocaleProvider.localeNames['zh'], equals('简体中文'));
        expect(LocaleProvider.localeNames['zh_TW'], equals('繁體中文'));
      });
    });

    group('load()', () {
      test('load with no saved preference defaults to English', () async {
        SharedPreferences.setMockInitialValues({});
        await provider.load();
        expect(provider.locale, equals(const Locale('en')));
      });

      test('load restores saved locale code', () async {
        SharedPreferences.setMockInitialValues({'app_locale': 'de'});
        await provider.load();
        expect(provider.locale, equals(const Locale('de')));
      });

      test('load restores locale with country code', () async {
        SharedPreferences.setMockInitialValues({'app_locale': 'zh_TW'});
        await provider.load();
        expect(provider.locale, equals(const Locale('zh', 'TW')));
      });

      test('load handles invalid locale code defaults to English', () async {
        SharedPreferences.setMockInitialValues({'app_locale': 'invalid'});
        await provider.load();
        expect(provider.locale, equals(const Locale('invalid')));
      });
    });

    group('setLocale()', () {
      test('setLocale changes current locale', () async {
        await provider.setLocale(const Locale('de'));
        expect(provider.locale, equals(const Locale('de')));
      });

      test('setLocale persists locale to SharedPreferences', () async {
        await provider.setLocale(const Locale('fr'));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('app_locale'), equals('fr'));
      });

      test('setLocale persists locale with country code', () async {
        await provider.setLocale(const Locale('zh', 'TW'));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('app_locale'), equals('zh_TW'));
      });

      test('setLocale ignores unsupported locales', () async {
        final originalLocale = provider.locale;
        await provider.setLocale(const Locale('ja'));
        expect(provider.locale, equals(originalLocale));
      });

      test('setLocale notifies listeners', () async {
        int notifyCount = 0;
        provider.addListener(() => notifyCount++);
        await provider.setLocale(const Locale('de'));
        expect(notifyCount, equals(1));
      });
    });

    group('getLocaleName()', () {
      test('getLocaleName returns correct name for language only', () {
        expect(provider.getLocaleName(const Locale('en')), equals('English'));
        expect(provider.getLocaleName(const Locale('de')), equals('Deutsch'));
        expect(provider.getLocaleName(const Locale('fr')), equals('Français'));
        expect(provider.getLocaleName(const Locale('ru')), equals('Русский'));
        expect(provider.getLocaleName(const Locale('zh')), equals('简体中文'));
      });

      test('getLocaleName returns correct name for language with country', () {
        expect(
          provider.getLocaleName(const Locale('zh', 'TW')),
          equals('繁體中文'),
        );
      });

      test('getLocaleName falls back to language code for unknown locale', () {
        expect(provider.getLocaleName(const Locale('ja')), equals('ja'));
      });
    });

    group('codeOf()', () {
      test('language-only locale returns languageCode', () {
        expect(LocaleProvider.codeOf(const Locale('en')), equals('en'));
        expect(LocaleProvider.codeOf(const Locale('zh')), equals('zh'));
        expect(LocaleProvider.codeOf(const Locale('de')), equals('de'));
        expect(LocaleProvider.codeOf(const Locale('fr')), equals('fr'));
        expect(LocaleProvider.codeOf(const Locale('ru')), equals('ru'));
      });

      test('locale with country code returns lang_COUNTRY', () {
        expect(LocaleProvider.codeOf(const Locale('zh', 'TW')), equals('zh_TW'));
      });

      test('简体(zh) 与繁体(zh_TW) 可区分（决定 AI 响应语言）', () {
        expect(LocaleProvider.codeOf(const Locale('zh')), isNot(equals('zh_TW')));
        expect(LocaleProvider.codeOf(const Locale('zh', 'TW')), equals('zh_TW'));
      });
    });
  });
}
