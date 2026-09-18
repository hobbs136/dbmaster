import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/telemetry_service.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _localeKey = 'app_locale';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('de'),
    Locale('fr'),
    Locale('ru'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  static const Map<String, String> localeNames = {
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Français',
    'ru': 'Русский',
    'zh': '简体中文',
    'zh_TW': '繁體中文',
  };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final localeCode = prefs.getString(_localeKey) ?? 'en';

    if (localeCode.contains('_')) {
      final parts = localeCode.split('_');
      _locale = Locale(parts[0], parts[1]);
    } else {
      _locale = Locale(localeCode);
    }
    TelemetryService.instance.setLocale(codeOf(_locale));
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (!supportedLocales.contains(locale)) return;

    _locale = locale;
    TelemetryService.instance.setLocale(codeOf(_locale));
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (locale.countryCode != null) {
      await prefs.setString(
        _localeKey,
        '${locale.languageCode}_${locale.countryCode}',
      );
    } else {
      await prefs.setString(_localeKey, locale.languageCode);
    }
  }

  String getLocaleName(Locale locale) {
    final key = locale.countryCode != null
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    return localeNames[key] ??
        localeNames[locale.languageCode] ??
        locale.languageCode;
  }

  /// 含 country code 的 locale 串（如 `zh_TW`），供无 BuildContext 的服务层区分简繁。
  /// 仅简体 `zh` → `zh`；繁体 `zh`+TW → `zh_TW`；其余原样返回 languageCode。
  static String codeOf(Locale locale) {
    return locale.countryCode != null
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
  }
}
