// C01a · UI 插件注册框架 —— 统一插件描述符（manifest）。
//
// 设计铁律「能力单一真相」——manifest 只放
// UI 元数据（id / 名称 / 图标 / 适用类型 / 来源徽章），类型支持什么能力
// （DDL / 事务 / kill / 导入导出…）一律从 DbCapabilityPort（C01 落地）查询，
// 禁止在插件 manifest 里声明能力位，防止与 port 形成双源。
// 徽章示例：`mysql-connection-plugin` / `core` / `ai-skill-host`。
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/database_models.dart';

/// 插件来源徽章（原型侧边栏能力菜单的来源标注）。
enum PluginSource {
  /// 核心自带：跨类型通用件（如 AI 助手入口、通用表格渲染器）。
  core,

  /// 数据库类型专属：per-type 表单 / 对象树 / 渲染器（徽章 `mysql-plugin` 等）。
  databaseType,

  /// AI 技能插件（徽章 `ai-plugin`；本体二期 C23 实现）。
  ai,
}

/// UI 插件描述符 —— 所有插件的注册 manifest。
///
/// 字段刻意保持纯 UI 元数据；[supportedTypes] 只表达「这个插件为哪些类型
/// 提供 UI」，不表达「这些类型有什么能力」——后者归 port。
@immutable
class PluginDescriptor {
  /// 稳定技术标识，同时用作 UI 徽章文本（如 `mysql-connection-plugin`、
  /// `sql-result-renderer`）。全注册表内唯一（跨插件种类共享一个 id 空间）。
  final String id;

  /// 适用数据库类型。空集 = 不限类型的通用件（core 渲染器等）。
  final Set<DatabaseType> supportedTypes;

  /// 来源徽章，驱动「插件来源徽章（core/类型/AI）」的渲染。
  final PluginSource source;

  /// 图标。当前为 Material IconData；D9 拍板全面切 Lucide 后同为
  /// IconData 实例，类型无需变更。
  final IconData icon;

  /// 本地化显示名。为空时宿主回退展示 [id]（技术徽章场景）。
  final String Function(AppLocalizations l10n)? displayName;

  const PluginDescriptor({
    required this.id,
    this.supportedTypes = const <DatabaseType>{},
    this.source = PluginSource.core,
    required this.icon,
    this.displayName,
  });

  /// 该插件是否适用于 [type]。空集视为全类型适用。
  bool supports(DatabaseType type) =>
      supportedTypes.isEmpty || supportedTypes.contains(type);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PluginDescriptor && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PluginDescriptor($id)';
}
