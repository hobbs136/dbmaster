// C01a · UI 插件注册框架 —— 连接表单插件接口（C2 消费）。
//
// 对应原型「连接配置对话框」：两栏结构（类型导航 + 动态表单）的右侧
// 动态表单段由本接口的实现按类型提供。C08 起各类型表单模块位于
// `lib/organisms/connection/forms/`（注册表分发；C09 已删旧实现）。
//
// 生命周期采用「无状态插件 + 每次打开创建会话」：注册表持有插件单例，
// 会话持有表单控制器等可变资源——同一插件可同时服务多个打开中的对话框
// （主窗口 + 测试连接预览等）而不串状态。
import 'package:flutter/widgets.dart';

import '../models/database_models.dart';
import 'plugin_descriptor.dart';

/// 连接草稿：宿主对话框与表单会话共享的可变连接配置载体。
///
/// 刻意不用 `ValueNotifier<DbServer>`——[DbServer] 以 id 判等，copyWith
/// 产物与旧值 `==` 相等，会被 ValueNotifier 的相等性短路静默丢弃（单测
/// 实测踩中）。本类强制赋值 + 总是通知，任何 copyWith 推送都生效：
///
/// ```dart
/// draft.update(draft.value.copyWith(name: 'renamed'));
/// ```
class ConnectionDraft extends ChangeNotifier {
  DbServer _value;

  ConnectionDraft(DbServer initial) : _value = initial;

  /// 当前草稿。表单初值取此值，宿主头部字段（名称 / 分组 / 环境）与
  /// 表单字段都经 [update] 推 copyWith 新值。
  DbServer get value => _value;

  /// 推送新草稿。无条件赋值并通知（不做相等性短路，见类注释）。
  void update(DbServer newValue) {
    _value = newValue;
    notifyListeners();
  }
}

/// 连接表单会话的创建上下文（宿主对话框 → 表单插件）。
@immutable
class ConnectionFormPluginContext {
  /// 目标数据库类型。注册表已按 descriptor.supports 过滤，
  /// 会话内可直接假定类型匹配。
  final DatabaseType type;

  /// 编辑中的连接草稿（见 [ConnectionDraft] 的判等陷阱说明）。
  final ConnectionDraft draft;

  const ConnectionFormPluginContext({
    required this.type,
    required this.draft,
  });
}

/// 单次打开的表单会话：持有字段控制器等可变资源。
///
/// 宿主调用序：`createSession()` → `build()`（可多次）→ 保存时
/// `collect()` → 对话框关闭时 `dispose()`。collect 失败时由会话
/// 自行在表单内展示校验错误。
abstract interface class ConnectionFormSession {
  /// 渲染表单字段区（两栏结构的右侧动态表单段）。
  Widget build(BuildContext context);

  /// 收集表单值。校验未过返回 null（错误已在表单内展示）；
  /// 通过则返回合并了表单字段的完整连接配置，由宿主持久化。
  ///
  /// [forSave]（C08 增补）：true = 保存路径，会话按「保存密码」开关决定
  /// 是否携带密码；false = 测试连接路径，总是使用表单当前密码（重建前
  /// connection_dialog 的既有语义，接口落地实现时发现需要显式化）。
  DbServer? collect({bool forSave = false});

  /// 释放会话持有的控制器 / FocusNode 等资源。恰好调用一次。
  void dispose();
}

/// 连接表单插件（C2 消费；实现见 C08 起各类型表单模块）。
abstract interface class ConnectionFormPlugin {
  PluginDescriptor get descriptor;

  /// 为一次对话框打开创建表单会话。插件本体必须无状态。
  ConnectionFormSession createSession(ConnectionFormPluginContext context);
}
