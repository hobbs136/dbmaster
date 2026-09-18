// C01a · UI 插件注册框架 —— 引导与 Pro 注入接缝（spec 045 open-core）。
//
// 接缝形态（与既有 ProModule 注入同一模式，见 AppProvider(proModule:)）：
// [defaultPluginRegistry] 创建即注册 OSS 默认实现（见下方声明），main()
// 仅负责 `seal()`；Pro fork 在 seal 前追加自己的 registerXxx（或对同 id
// 显式 override: true）注入 Pro UI 插件——核心代码不 import 任何 Pro 实现，
// 公开仓构建零 Pro 符号。ProModule 管 entitlement（能不能用），插件注册管
// UI 提供（有没有这块界面），两缝互补、互不替代。
//
// 当前默认注册 = C08 连接表单八件（mysql/pg/mongo/sqlite/redis/doris/td/ch）
// + C14 core 侧边栏 + C15 MySQL/PG 侧边栏 + C16 SQLite 侧边栏
// + C17 MongoDB/Redis 侧边栏 + C18 Doris/TDengine 侧边栏 + C20 SQL Server
// 侧边栏；SQL Server 无表单注册 → 宿主回退通用表单。结果渲染器 = C11
// 三件（table/chart/card，sqlRows）+ C12 三件（document/jsonTree/keyValue，
// nosqlDocument / redisKeyValue 形态默认视图）。
import '../organisms/connection/forms/clickhouse_connection_form.dart';
import '../organisms/connection/forms/doris_connection_form.dart';
import '../organisms/connection/forms/mongodb_connection_form.dart';
import '../organisms/connection/forms/mysql_connection_form.dart';
import '../organisms/connection/forms/postgresql_connection_form.dart';
import '../organisms/connection/forms/redis_connection_form.dart';
import '../organisms/connection/forms/sqlite_connection_form.dart';
import '../organisms/connection/forms/tdengine_connection_form.dart';
import '../organisms/ai_panel/skills/builtin_ai_skills.dart';
import '../organisms/results/plugins/card_result_renderer.dart';
import '../organisms/results/plugins/chart_result_renderer.dart';
import '../organisms/results/plugins/document_result_renderer.dart';
import '../organisms/results/plugins/json_tree_result_renderer.dart';
import '../organisms/results/plugins/key_value_result_renderer.dart';
import '../organisms/results/plugins/table_result_renderer.dart';
import '../organisms/sidebar/capability/core_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/doris_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/mongodb_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/mysql_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/postgresql_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/redis_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/sqlite_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/sqlserver_sidebar_plugin.dart';
import '../organisms/sidebar/plugins/tdengine_sidebar_plugin.dart';
import 'plugin_registry.dart';

/// 应用全局默认注册表。**创建即注册 OSS 默认插件**（Dart 顶层 final 惰性
/// 初始化，首次读取时生效），**不封口**——封口归 main()，Pro fork 在 seal
/// 前仍可追加注入（spec 045 接缝）。
///
/// 为何不依赖 main() 注册：宿主（SidebarTree 树分缝 / 能力菜单）直接消费
/// 本注册表，而 e2e/集成测试自建 widget 树不经 main()——默认注册必须在
/// 注册表首次可及时就位（C15 教训：全局节点分缝后 MySQL/PG 树由插件提供，
/// 空注册表 = 树消失）。测试如需覆盖默认件，对独立 `PluginRegistry()` 调
/// [registerDefaultUiPlugins]；对 defaultPluginRegistry 重复调用会因 id
/// 冲突 fail-loud（防双重初始化）。
final PluginRegistry defaultPluginRegistry = _registryWithDefaults();

PluginRegistry _registryWithDefaults() {
  final registry = PluginRegistry();
  registerDefaultUiPlugins(registry);
  return registry;
}

/// 注册 OSS 默认 UI 插件（spec 045 接缝的 OSS 半边）。
///
/// Pro fork 的引导序列：
/// ```dart
/// registerDefaultUiPlugins(defaultPluginRegistry); // OSS 默认
/// registerProUiPlugins(defaultPluginRegistry);     // Pro 注入（Pro 仓自有）
/// defaultPluginRegistry.seal();
/// ```
void registerDefaultUiPlugins(PluginRegistry registry) {
  // C08 · 连接表单（按 descriptor.supportedTypes 分发）
  registry.registerConnectionForm(const MySqlConnectionFormPlugin());
  registry.registerConnectionForm(const PostgresqlConnectionFormPlugin());
  registry.registerConnectionForm(const MongodbConnectionFormPlugin());
  registry.registerConnectionForm(const SqliteConnectionFormPlugin());
  registry.registerConnectionForm(const RedisConnectionFormPlugin());
  registry.registerConnectionForm(const DorisConnectionFormPlugin());
  registry.registerConnectionForm(const TDengineConnectionFormPlugin());
  registry.registerConnectionForm(const ClickhouseConnectionFormPlugin());

  // C14 · core 侧边栏插件（通用能力菜单层；per-type 插件注册序在 core 之后
  // = 同 id 能力项可覆盖 core 通用实现）。
  registry.registerSidebar(const CoreSidebarPlugin());

  // C15 · per-type 侧边栏插件（MySQL/PG：连接级全局树 + 类型专有能力项；
  // PG 另接管库级 schema 树）。
  registry.registerSidebar(const MysqlSidebarPlugin());
  registry.registerSidebar(const PostgresqlSidebarPlugin());

  // C16 · SQLite 侧边栏插件（整树连接级：单库扁平 / ATTACH 多库 header；
  // 能力项 attach / pragma explorer）。
  registry.registerSidebar(const SqliteSidebarPlugin());

  // C17 · MongoDB/Redis 侧边栏插件（Mongo 两级树：全局 Server/Replication/
  // Sharding + 库级 Collections/Views/GridFS；Redis 整树连接级：逻辑库列表
  // + 全局节点 + 9 面板能力项）。
  registry.registerSidebar(const MongodbSidebarPlugin());
  registry.registerSidebar(const RedisSidebarPlugin());

  // C18 · Doris/TDengine 侧边栏插件（Doris 全局树 Server/Performance +
  // process.kill 能力项，库级走泛 SQL 路径；TD 库级 SuperTables 树迁入，
  // 全局恒空——刻意省略 server 级节点）。
  registry.registerSidebar(const DorisSidebarPlugin());
  registry.registerSidebar(const TdengineSidebarPlugin());

  // C20 · SQL Server 侧边栏插件（收官件）：全局树 Server Status/Process
  // List/Users + 库级 schema-first 树（Schema → Tables/Views/Procedures/
  // Functions）；能力菜单恒空（process.kill 位不含 ss——进程只读）。
  registry.registerSidebar(const SqlserverSidebarPlugin());

  // C12 · 形态专有渲染器（nosqlDocument：文档卡片 + JSON 树；
  // redisKeyValue：键值卡 + JSON 树）。jsonTree 双形态声明 → 注册序必须
  // 在 document/keyValue 之后（否则它是两形态的默认视图）；形态命中时
  // 专有卡是默认视图；table 同声明这两形态，保留为可切换兜底（不因换脸
  // 丢失拍平视图）。
  registry.registerResultRenderer(const DocumentResultRenderer());
  registry.registerResultRenderer(const KeyValueResultRenderer());
  registry.registerResultRenderer(const JsonTreeResultRenderer());

// C11 · 结果渲染器三件（sqlRows 形态）：table/chart/card，viewModeId
  // 与原 ResultViewMode 枚举名对齐；宿主视图切换条按本注册生成。
  registry.registerResultRenderer(const TableResultRenderer());
  registry.registerResultRenderer(const ChartResultRenderer());
  registry.registerResultRenderer(const CardResultRenderer());

  // C23.1 · 内置 AI 技能（技能目录消费；Pro 按同 id + override 替换）。
  for (final skill in builtinAiSkills) {
    registry.registerAiSkill(skill);
  }
}
