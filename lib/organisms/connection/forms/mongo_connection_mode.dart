/// MongoDB 连接模式（spec 044）—— UI 侧枚举。
///
/// 仅 [MongodbConnectionFormSession]（C08 迁入 forms/，原 ConnectionDialog
/// 的模式下拉框）使用；持久化时写入
/// `DbServer.extra['mongoConnectionMode']`（取 [extraValue] 字符串），
/// 数据层（adapter）按字符串字面量解析。缺省/未知 ⇒ [direct]（向后兼容：
/// 旧 Mongo 连接无 `extra`，等价于直连单 host）。
///
/// 全部四种模式已接线（spec 044）：[direct](US1)/[replicaSet](US1)/
/// [sharded](US2 via mongos)/[advanced](US3 粘贴连接串)。下拉框全暴露。
enum MongoConnectionMode {
  direct('direct'),
  replicaSet('replicaSet'),
  sharded('sharded'),
  advanced('advanced');

  const MongoConnectionMode(this.extraValue);

  /// 持久化进 `extra['mongoConnectionMode']` 的字符串值。
  final String extraValue;

  /// 解析持久化的模式字符串；null/未知 ⇒ [direct]（向后兼容）。
  static MongoConnectionMode fromExtra(Object? value) {
    switch (value) {
      case 'replicaSet':
        return MongoConnectionMode.replicaSet;
      case 'sharded':
        return MongoConnectionMode.sharded;
      case 'advanced':
        return MongoConnectionMode.advanced;
      default:
        return MongoConnectionMode.direct;
    }
  }
}
