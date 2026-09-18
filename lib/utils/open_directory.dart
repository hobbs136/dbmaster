import 'dart:io';

import 'app_logger.dart';

/// 在系统文件管理器中打开目录（macOS `open` / Linux `xdg-open` /
/// Windows `explorer`）。原 sqlite_tree_builder 与 task_list_item 各一份
/// 重复实现，U14 设置页「打开日志目录」为第三处使用，收敛于此。
///
/// 返回是否成功发起（不保证文件管理器窗口真的弹出）；失败只记日志不抛。
Future<bool> openDirectoryInFileManager(String dirPath) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [dirPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dirPath]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [dirPath.replaceAll('/', '\\')]);
    } else {
      return false;
    }
    return true;
  } catch (e) {
    AppLogger.w('OpenDirectory', 'Failed to open folder: $e');
    return false;
  }
}
