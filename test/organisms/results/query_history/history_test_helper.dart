import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';

/// Initializes the test binding and mocks platform channels that would
/// otherwise be triggered when constructing [AppProvider].
void setupHistoryTestBinding() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi',
    (message) async =>
        const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
  );
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchaseApi',
    (message) async =>
        const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
  );
  SharedPreferences.setMockInitialValues({});
}

/// Wraps [child] with the localization and provider scaffolding used by
/// history panel widget tests.
Widget buildHistoryTestApp(AppProvider appProvider, {required Widget child}) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: appProvider,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  );
}
