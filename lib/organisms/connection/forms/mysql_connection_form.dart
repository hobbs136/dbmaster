// C08 · MySQL 连接表单模块（插件形）。
//
// 字段集 = 重建前 connection_dialog 对 mysql 的分支：基础网络字段 +
// 高级折叠内 charset/timezone 下拉。Doris 复用同一会话（字段集相同，
// charset 列表含 gbk——c03 §2 核对一致），见 doris_connection_form.dart。
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../plugins/connection_form_plugin.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../theme/app_theme.dart';
import 'connection_form_fields.dart';
import 'network_connection_form.dart';

/// MySQL/Doris 共用会话：charset + timezone 高级下拉。
class SqlConnectionFormSession extends NetworkConnectionFormSession {
  SqlConnectionFormSession(super.ctx);

  static const List<String> charsets = [
    'utf8mb4',
    'utf8',
    'latin1',
    'gbk',
    'gb2312',
    'big5',
  ];

  static const List<String> timezones = [
    '+00:00', '+01:00', '+02:00', '+03:00', '+04:00', '+05:00', '+05:30',
    '+06:00', '+07:00', '+08:00', '+09:00', '+10:00', '+11:00', '+12:00',
    '-01:00', '-02:00', '-03:00', '-04:00', '-05:00', '-06:00', '-07:00',
    '-08:00', '-09:00', '-10:00', '-11:00', '-12:00',
  ];

  String? selectedCharset;
  String? selectedTimezone;

  @override
  List<Widget> buildAdvancedFields(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      const SizedBox(height: AppDesignSystem.space3),
      ConnectionDropdownField<String?>(
        label: l10n.connectionCharset,
        value: selectedCharset,
        hint: l10n.connectionAutoCharset,
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(
              l10n.connectionAutoCharset,
              style: _itemStyle(context),
            ),
          ),
          ...charsets.map(
            (c) => DropdownMenuItem<String?>(
              value: c,
              child: Text(c, style: _itemStyle(context)),
            ),
          ),
        ],
        onChanged: (v) => toggle(() => selectedCharset = v),
      ),
      const SizedBox(height: AppDesignSystem.space3),
      ConnectionDropdownField<String?>(
        label: l10n.connectionTimezone,
        value: selectedTimezone,
        hint: l10n.connectionAutoSystem,
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(
              l10n.connectionAutoSystem,
              style: _itemStyle(context),
            ),
          ),
          ...timezones.map(
            (tz) => DropdownMenuItem<String?>(
              value: tz,
              child: Text(tz, style: _itemStyle(context)),
            ),
          ),
        ],
        onChanged: (v) => toggle(() => selectedTimezone = v),
      ),
    ];
  }

  TextStyle _itemStyle(BuildContext context) => TextStyle(
        color: context.themeColors.textPrimary,
        fontSize: 13,
      );

  @override
  String? get charsetValue => selectedCharset;

  @override
  String? get timezoneValue => selectedTimezone;
}

/// MySQL 会话（含编辑回填）。
class MySqlConnectionFormSession extends SqlConnectionFormSession {
  MySqlConnectionFormSession(super.ctx) {
    selectedCharset = initial.charset;
    selectedTimezone = initial.timezone;
  }
}

/// MySQL 连接表单插件。
///
/// T22-T25 · MySQL 协议族薄适配四成员（OceanBase/TiDB/StarRocks/MariaDB）
/// 复用本表单（字段集与 MySQL 一致：网络字段 + charset/timezone 高级下拉；
/// server 侧差异经网关薄适配 profile 收敛，客户端表单无方言分支）。
class MySqlConnectionFormPlugin implements ConnectionFormPlugin {
  const MySqlConnectionFormPlugin();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'mysql-connection-plugin',
        supportedTypes: const {
          DatabaseType.mysql,
          DatabaseType.oceanbase,
          DatabaseType.tidb,
          DatabaseType.starrocks,
          DatabaseType.mariadb,
        },
        source: PluginSource.databaseType,
        icon: DatabaseType.mysql.typeIcon,
      );

  @override
  ConnectionFormSession createSession(ConnectionFormPluginContext context) =>
      MySqlConnectionFormSession(context);
}
