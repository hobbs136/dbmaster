/// 受试用额度约束的 Pro **动作型**功能。
///
/// open-core：连接数/Tab 上限与 SSH 门禁已移除（三家竞品 free 均不限），
/// 此处仅剩 power features 的试用配额。
///
/// fullTableScan / sqlInjection 是审查 Pro 规则（第二阶段）。当前桌面端门控
/// 整体禁用，实际都启用；此处注册为未来恢复门控做好准备。
enum ProFeature {
  schemaDiffSync,
  dataSync,
  dataImport,
  mongoCluster,
  aiAgent,
  fullTableScan,
  sqlInjection,
  explainFullScan,
  explainEstimatedRows;

  /// 与 `assets/config/trial_quota.json` 的键名对应。
  String get configKey => name;
}
