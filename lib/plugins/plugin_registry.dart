// C01a · UI 插件注册框架 —— 编译期插件注册表。
//
// 边界（C01a 铁律）：不做动态加载 / 插件管理 UI /
// 插件市场 / 对外 API 稳定承诺——注册只发生在编译期确定的引导代码
// （见 bootstrap.dart），是「一切皆插件」原型的编译期落地。
//
// Pro 注入接缝（spec 045 open-core）：注册方法是公开 API，OSS 引导注册
// 默认实现，Pro fork 追加注册或以 override 显式替换；核心不 import 任何
// Pro 实现，公开仓构建天然零 Pro 符号。
import '../models/database_models.dart';
import '../utils/app_logger.dart';
import 'ai_skill_plugin.dart';
import 'connection_form_plugin.dart';
import 'plugin_descriptor.dart';
import 'result_renderer_plugin.dart';
import 'sidebar_plugin.dart';

/// UI 插件注册表：按种类登记插件，按类型 / 结果形态查询。
///
/// 单线程 UI 线程使用，无锁。id 在全注册表（跨种类）唯一——原型徽章
/// 文本即 id，全局唯一保证「徽章 → 插件」反查无歧义。
class PluginRegistry {
  final Map<String, ConnectionFormPlugin> _connectionForms =
      <String, ConnectionFormPlugin>{};
  final Map<String, SidebarPlugin> _sidebars = <String, SidebarPlugin>{};
  final Map<String, ResultRendererPlugin> _resultRenderers =
      <String, ResultRendererPlugin>{};
  final Map<String, AiSkillPlugin> _aiSkills = <String, AiSkillPlugin>{};

  /// id → 描述符索引（跨种类），供徽章反查与调试列举。
  final Map<String, PluginDescriptor> _descriptors =
      <String, PluginDescriptor>{};

  bool _sealed = false;

  /// 注册 [plugin]，id 冲突时抛 [ArgumentError]（fail-loud）。
  ///
  /// [override]：Pro 层显式替换同 id 的 OSS 默认实现（spec 045 接缝），
  /// 替换写入 info 日志。
  void _register<T>(Map<String, T> store, T plugin, PluginDescriptor descriptor,
      {bool override = false}) {
    if (_sealed) {
      throw StateError(
        'PluginRegistry 已封口（sealed），禁止再注册：${descriptor.id}',
      );
    }
    final existing = _descriptors.containsKey(descriptor.id);
    if (existing && !override) {
      throw ArgumentError(
        '插件 id 冲突：${descriptor.id}（如需替换 OSS 默认实现请显式 override: true）',
      );
    }
    if (existing) {
      AppLogger.i('PluginRegistry', 'override 插件 ${descriptor.id}');
      _removeById(descriptor.id);
    }
    _descriptors[descriptor.id] = descriptor;
    store[descriptor.id] = plugin;
  }

  /// 从所有种类仓库中移除 id 对应的旧插件（override 路径专用）。
  void _removeById(String id) {
    _connectionForms.remove(id);
    _sidebars.remove(id);
    _resultRenderers.remove(id);
    _aiSkills.remove(id);
    _descriptors.remove(id);
  }

  // ── 注册 API（引导期调用）──────────────────────────────────────────

  void registerConnectionForm(ConnectionFormPlugin plugin,
          {bool override = false}) =>
      _register(_connectionForms, plugin, plugin.descriptor, override: override);

  void registerSidebar(SidebarPlugin plugin, {bool override = false}) =>
      _register(_sidebars, plugin, plugin.descriptor, override: override);

  void registerResultRenderer(ResultRendererPlugin plugin,
          {bool override = false}) =>
      _register(_resultRenderers, plugin, plugin.descriptor,
          override: override);

  void registerAiSkill(AiSkillPlugin plugin, {bool override = false}) =>
      _register(_aiSkills, plugin, plugin.descriptor, override: override);

  /// 封口：引导完成后调用，之后任何注册抛 [StateError]。
  /// 防止运行期散落注册打破「编译期注册」边界。
  void seal() => _sealed = true;

  // ── 查询 API（宿主消费）────────────────────────────────────────────

  /// 类型 → 连接表单插件。无适配插件返回 null（宿主回退通用表单或提示）；
  /// 多个命中取注册序首个并告警（配置错误尽早暴露）。
  ConnectionFormPlugin? connectionFormFor(DatabaseType type) =>
      _firstSupporting(
          _connectionForms.values, (p) => p.descriptor, type, 'connectionForm');

  /// 类型 → 侧边栏插件列表（注册序）。与表单不同，侧边栏是**多插件合并**
  /// 场景（C14 能力菜单：core 通用项 + per-type 项共存，原型徽章混排
  /// core/mysql-plugin/ai-plugin），取全部命中而非首个。
  List<SidebarPlugin> sidebarPluginsFor(DatabaseType type) => _sidebars.values
      .where((p) => p.descriptor.supports(type))
      .toList(growable: false);

  /// 渲染器查询：[type] 与 [shape] 为可选过滤（null = 不限），
  /// 返回注册序列表。视图切换 UI 按本列表生成模式集合。
  List<ResultRendererPlugin> resultRenderersFor(
      {DatabaseType? type, ResultDataShape? shape}) {
    return _resultRenderers.values
        .where((p) => type == null || p.descriptor.supports(type))
        .where((p) => shape == null || p.supportedShapes.contains(shape))
        .toList(growable: false);
  }

  /// 全部已注册 AI 技能（C23 消费）。
  List<AiSkillPlugin> get aiSkills =>
      _aiSkills.values.toList(growable: false);

  /// id → 描述符反查（徽章点击 / 调试列举）。
  PluginDescriptor? descriptorById(String id) => _descriptors[id];

  /// 已注册插件总数（跨种类）。
  int get pluginCount => _descriptors.length;

  T? _firstSupporting<T>(Iterable<T> plugins,
      PluginDescriptor Function(T plugin) descriptorOf, DatabaseType type,
      String kind) {
    T? match;
    for (final plugin in plugins) {
      final descriptor = descriptorOf(plugin);
      if (!descriptor.supports(type)) continue;
      if (match != null) {
        AppLogger.w('PluginRegistry',
            '$kind 对 ${type.name} 有多个插件命中，取注册序首个 ${descriptor.id}');
        break;
      }
      match = plugin;
    }
    return match;
  }
}
