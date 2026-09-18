// C12 · 结果数据形态——决定结果面板哪些渲染器适用。
//
// 形态由执行的连接类型决定（DatabaseService.executeQuery 侧按 server.type
// 判定后经 ExecutionResult.dataShape 下行）；渲染器经 supportedShapes 声明
// 消费形态，宿主按「结果携带的形态」查注册表生成视图切换集合。
// 定义在 models 层供 ExecutionResult 序列化复用；plugins 层
// （result_renderer_plugin.dart）re-export 保持既有 import 不动。
import 'database_models.dart';

enum ResultDataShape {
  /// 行集（列 + 行）：SQL 查询与拍平路径的通用形态。
  sqlRows,

  /// NoSQL 文档 / 聚合结果（Mongo）。行内值保留嵌套结构（Map/List），
  /// 每行即一份文档——文档卡片 / JSON 树渲染器直接消费，不再拍平。
  nosqlDocument,

  /// Redis 键值（命令输出 / 键值对；TTL/编码元信息视数据来源可得）。
  redisKeyValue;

  /// 连接类型 → 默认结果形态（C12 形态判定单一真相）。
  ///
  /// Mongo 结果按文档渲染（文档卡片默认 + JSON 树 + 表格兜底）；Redis
  /// 结果按键值渲染（键值卡默认 + JSON 树 + 表格兜底）；SQL 家族恒行集。
  static ResultDataShape shapeForDatabaseType(DatabaseType type) {
    switch (type) {
      case DatabaseType.mongodb:
        return ResultDataShape.nosqlDocument;
      case DatabaseType.redis:
        return ResultDataShape.redisKeyValue;
      case DatabaseType.mysql:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.sqlserver:
      case DatabaseType.doris:
      case DatabaseType.clickhouse:
      case DatabaseType.tdengine:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return ResultDataShape.sqlRows;
    }
  }
}
