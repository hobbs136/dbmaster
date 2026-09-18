import 'package:flutter/material.dart';

import 'package:dbmaster/organisms/pro/pro_sync_ui.dart';
import 'package:dbmaster/pro/data_sync/data_sync_dialog.dart';

/// [ProSyncUi] 的 Pro 实现（open-core B.2）。
///
/// 直接转发到 [DataSyncDialog.show]——`lib/pro/data_sync/data_sync_dialog.dart`
/// 已在 B.1 阶段随数据同步功能迁入 Pro 仓，所有内部依赖（[DataSyncService] /
/// 批量插入器等）随同迁入，故此处无需再做任何胶合。
class RealProSyncUi extends ProSyncUi {
  const RealProSyncUi();

  @override
  Future<void> openDataSyncDialog(
    BuildContext context, {
    required String connectionId,
    required String database,
    required String table,
  }) {
    return DataSyncDialog.show(
      context,
      connectionId: connectionId,
      database: database,
      table: table,
    );
  }
}
