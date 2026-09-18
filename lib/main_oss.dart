import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'main.dart' show DbmasterApp;
import 'services/pro_module.dart';

/// 全免费公开仓入口——注入 [FreeProModule]（isPro 恒 true）。
///
/// 客户端全功能免费，与 `main.dart` 等效。保留此入口用于构建脚本兼容。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    center: true,
    minimumSize: Size(800, 600),
    title: 'DbMaster',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(DbmasterApp(proModule: FreeProModule()));
}
