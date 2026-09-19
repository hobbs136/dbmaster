// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get filterBarApply => '应用';

  @override
  String get filterBarAddCondition => '添加条件';

  @override
  String get filterBarAnd => '且';

  @override
  String get filterBarOr => '或';

  @override
  String get filterBarNoColumns => '无字段';

  @override
  String get filterBarLoading => '加载中…';

  @override
  String get mongoAutocompleteTitle => 'Mongo 自动补全';

  @override
  String get appTitle => 'DbMaster';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsGeneral => '常规';

  @override
  String get settingsConnection => '连接';

  @override
  String get settingsEditor => '编辑器';

  @override
  String get settingsAbout => '关于';

  @override
  String get connectionNewConnection => '新建连接';

  @override
  String get connectionEditConnection => '编辑连接';

  @override
  String get connectionManageConnection => '管理连接';

  @override
  String get connectionDeleteConnection => '删除连接';

  @override
  String get connectionConnect => '连接';

  @override
  String get connectionCreateDatabase => '新建数据库';

  @override
  String get connectionEnableReadOnly => '启用只读';

  @override
  String get connectionDisableReadOnly => '禁用只读';

  @override
  String connectionMoveToGroup(String groupName) {
    return '移动到 $groupName';
  }

  @override
  String get connectionRemoveFromGroup => '从分组移除';

  @override
  String get connectionCollapseAll => '全部折叠';

  @override
  String get connectionDisconnect => '断开连接';

  @override
  String get connectionTestConnection => '测试连接';

  @override
  String get connectionConnectionName => '连接名称';

  @override
  String get connectionHost => '主机';

  @override
  String get connectionPort => '端口';

  @override
  String get connectionUsername => '用户名';

  @override
  String get connectionPassword => '密码';

  @override
  String get connectionDatabase => '数据库';

  @override
  String get connectionEnvironment => '环境';

  @override
  String get connectionEnvironmentNone => '未指定';

  @override
  String get commonSave => '保存';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonAdd => '添加';

  @override
  String get commonClose => '关闭';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSelect => 'Select';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonLoading => '加载中...';

  @override
  String get commonNoData => '无数据';

  @override
  String get commonSuccess => '成功';

  @override
  String get commonError => '错误';

  @override
  String get commonWarning => '警告';

  @override
  String get tableNewTable => 'ER图';

  @override
  String get tableEditTable => '编辑表';

  @override
  String get tableDeleteTable => '删除表';

  @override
  String get tableTableName => '表名';

  @override
  String get tableColumns => '导入';

  @override
  String get tableIndexes => '索引';

  @override
  String get tablePrimaryKey => '主键';

  @override
  String get tableForeignKey => '外键';

  @override
  String get tableRenameTable => '重命名表';

  @override
  String get tableNewTableName => '新表名';

  @override
  String get queryExecute => '性能分析';

  @override
  String get queryExecuteSelected => '执行选中';

  @override
  String get queryFormat => '格式化';

  @override
  String get queryClear => '清除';

  @override
  String get queryHistory => '查询历史';

  @override
  String get queryResults => '结果';

  @override
  String get sidebarConnections => '连接';

  @override
  String get sidebarDatabases => '数据库';

  @override
  String get sidebarTables => '表';

  @override
  String get sidebarKeys => '键';

  @override
  String get sidebarCollections => '集合';

  @override
  String get sidebarSuperTables => '超级表';

  @override
  String get sidebarViews => '视图';

  @override
  String get sidebarSavedQueries => '已保存的查询';

  @override
  String get sidebarProcedures => '存储过程';

  @override
  String get sidebarTriggers => '触发器';

  @override
  String get sidebarFunctions => '函数';

  @override
  String get sidebarServer => '服务器';

  @override
  String get sidebarProcessList => '进程列表';

  @override
  String get sidebarServerStatus => '服务器状态';

  @override
  String get sidebarNoUsers => '无用户';

  @override
  String get sidebarNoActiveProcesses => '无活动进程';

  @override
  String sidebarTdColsTags(int cols, int tags) {
    return '$cols 列，$tags 标签';
  }

  @override
  String sidebarTdColumnsCount(int count) {
    return '列（$count）';
  }

  @override
  String sidebarTdTagsCount(int count) {
    return '标签（$count）';
  }

  @override
  String get sidebarTdDeleteTitle => '删除超级表';

  @override
  String sidebarTdDeleteConfirm(String name) {
    return '确定要删除超级表“$name”吗？\n\n这也会删除其所有子表！';
  }

  @override
  String get sidebarDeleteGroup => '删除分组';

  @override
  String get sidebarDeleteGroupPrompt => '选择要删除的分组：';

  @override
  String get sidebarConnectionSwitch => '切换连接';

  @override
  String get sidebarSelectConnectionHint => '从上方连接选择器选择一个连接开始';

  @override
  String get sidebarConnectionNone => '暂无连接';

  @override
  String get sidebarManageConnections => '管理连接…';

  @override
  String get sidebarExtensions => 'Extensions';

  @override
  String get noExtensionsInstalled => 'No extensions installed';

  @override
  String get sidebarSchemas => '模式';

  @override
  String get sidebarMaterializedViews => '物化视图';

  @override
  String get sidebarSequences => '序列';

  @override
  String get settingsGeneralSettings => '常规设置';

  @override
  String get settingsAppearanceSettings => '外观';

  @override
  String get settingsEditorSettings => '编辑器设置';

  @override
  String get settingsEnableAutocomplete => '启用自动完成';

  @override
  String get settingsAutocompleteDescription => '自动建议SQL关键字和表名';

  @override
  String get settingsSqlCoolTheme => 'SQL 冷主题高亮';

  @override
  String get settingsSqlCoolThemeDesc => '使用冷色系语法配色（与主题壳体协调）。关闭则用平台配套配色。';

  @override
  String get safetyRulesSectionTitle => '安全审查规则';

  @override
  String get safetyRuleSchemaCompat => 'Schema 兼容性检查';

  @override
  String get safetyRuleSchemaCompatDesc => '执行前检查 SQL 引用的列在表中是否存在';

  @override
  String get safetyRuleMissingLimit => '缺 LIMIT 警告';

  @override
  String get safetyRuleMissingLimitDesc => '查询大表且未加 LIMIT 子句时警告';

  @override
  String get safetyRuleFullTableScan => '全表扫描检测（静态）';

  @override
  String get safetyRuleFullTableScanDesc =>
      '检测 WHERE 子句中破坏索引的模式（如函数包裹列、LIKE 前缀通配）';

  @override
  String get safetyRuleSqlInjection => 'SQL 注入检测';

  @override
  String get safetyRuleSqlInjectionDesc => '标记常见 SQL 注入特征（永真式、注释截断等）';

  @override
  String get safetyRuleExplainFullScan => '全表扫描检测（EXPLAIN 实证）';

  @override
  String get safetyRuleExplainFullScanDesc => '执行 EXPLAIN 检测优化器实际选择的全表扫描';

  @override
  String get safetyRuleExplainEstimatedRows => '大结果集预警（EXPLAIN）';

  @override
  String get safetyRuleExplainEstimatedRowsDesc => '执行 EXPLAIN，预估返回行数超阈值时警告';

  @override
  String get safetyRuleExecutableComment => 'MySQL 可执行注释检测';

  @override
  String get safetyRuleExecutableCommentDesc =>
      '检测 /*! ... */ 版本注释内嵌的语句（MySQL 会执行注释内容）';

  @override
  String get safetyRuleTautologyPredicate => '恒真谓词检测';

  @override
  String get safetyRuleTautologyPredicateDesc =>
      '检测 WHERE 中的 1=1、TRUE、自比较等恒成立条件';

  @override
  String get safetyRuleComplementaryOr => '互补 OR 检测';

  @override
  String get safetyRuleComplementaryOrDesc =>
      '检测 x IS NULL OR x IS NOT NULL 等互补恒真分支';

  @override
  String get safetyRuleWritableCte => '可写 CTE 检测';

  @override
  String get safetyRuleWritableCteDesc =>
      '检测 WITH 子句 CTE 体内嵌的 DELETE/UPDATE/INSERT';

  @override
  String get safetyRuleFileWrite => '文件系统访问检测';

  @override
  String get safetyRuleFileWriteDesc =>
      '检测 INTO OUTFILE/DUMPFILE 与 LOAD_FILE 等服务器文件读写';

  @override
  String get safetyRuleReviewFailClosed => '审查降级写类拦截';

  @override
  String get safetyRuleReviewFailClosedDesc => '安全审查异常时对写操作注入高危告警（读操作不拦截）';

  @override
  String get safetyFullScanThreshold => '行数阈值（缺 LIMIT / 全表扫 / 大结果集通用）';

  @override
  String get settingsAiSettings => 'AI设置';

  @override
  String get settingsAutoExecuteSql => '自动执行SQL';

  @override
  String get settingsAutoExecuteSqlDescription => '打开标签页时自动执行SQL';

  @override
  String get settingsThemeSettings => '主题';

  @override
  String get settingsDarkMode => '深色';

  @override
  String get settingsLightMode => '浅色';

  @override
  String get shortcutCategoryFile => '文件';

  @override
  String get shortcutCategoryEdit => '编辑';

  @override
  String get shortcutCategoryView => '视图';

  @override
  String get shortcutCategoryAi => 'AI';

  @override
  String get shortcutCategoryTab => '标签页';

  @override
  String get shortcutNewConnection => '新建连接';

  @override
  String get shortcutNewTab => '新建标签页';

  @override
  String get shortcutCloseTab => '关闭标签页';

  @override
  String get shortcutSaveQuery => '保存查询';

  @override
  String get shortcutExportData => '导出数据';

  @override
  String get shortcutExecuteQuery => '执行查询';

  @override
  String get shortcutExecuteQueryNewTab => '在新标签页中执行';

  @override
  String get shortcutFormatSql => '格式化SQL';

  @override
  String get shortcutFind => '查找';

  @override
  String get shortcutReplace => '替换';

  @override
  String get shortcutAutocomplete => '自动完成';

  @override
  String get shortcutUndo => '撤销';

  @override
  String get shortcutRedo => '重做';

  @override
  String get shortcutToggleSidebar => '切换侧边栏';

  @override
  String get shortcutToggleAiPanel => '切换AI面板';

  @override
  String get shortcutCommandPalette => '命令面板';

  @override
  String get shortcutShortcutHelp => '快捷键帮助';

  @override
  String get shortcutGenerateSql => '生成SQL';

  @override
  String get shortcutOptimizeSql => '优化SQL';

  @override
  String get shortcutExplainSql => '解释SQL';

  @override
  String get shortcutNextTab => '下一个标签页';

  @override
  String get shortcutPreviousTab => '上一个标签页';

  @override
  String get shortcutSwitchToTab => '切换到标签页';

  @override
  String get shortcutToggleAiFullscreen => 'AI 面板全屏';

  @override
  String get shortcutAuditLog => '查询审计日志';

  @override
  String get shortcutIncreaseOpacity => '提高浮层不透明度';

  @override
  String get shortcutDecreaseOpacity => '降低浮层不透明度';

  @override
  String get tableCreateNewTable => '创建新表';

  @override
  String get toolbarBackup => '备份';

  @override
  String get toolbarImport => '导入';

  @override
  String get toolbarExport => '导出';

  @override
  String get sidebarExpand => '展开侧边栏';

  @override
  String get sidebarSettings => '设置';

  @override
  String get sidebarSearchHint => '搜索连接、表、视图...';

  @override
  String sidebarConnectionActive(Object count) {
    return '$count 个连接活跃';
  }

  @override
  String get sidebarNoConnections => '暂无保存的连接';

  @override
  String get sidebarClickToCreateConnection => '点击下方按钮新建连接';

  @override
  String get sidebarCreateConnection => '新建连接';

  @override
  String get resultsExport => '导出';

  @override
  String get resultsSave => '保存';

  @override
  String get resultsDiscard => '放弃';

  @override
  String get resultsNoDataToExport => '没有数据可导出';

  @override
  String get cellEditNotSupported => '暂不支持单元格编辑——修改无法写回数据库';

  @override
  String get exportExcelGenerating => '正在生成 Excel…';

  @override
  String get resultsCSV => 'CSV';

  @override
  String get resultsJSON => 'JSON';

  @override
  String get resultsExcel => 'Excel';

  @override
  String get resultsConfirmDiscardChanges => '确认放弃修改';

  @override
  String resultsDiscardChangesMessage(Object count) {
    return '确定要放弃 $count 处修改吗？此操作不可撤销。';
  }

  @override
  String get resultsContinueEditing => '继续编辑';

  @override
  String get resultsDiscardChanges => '放弃修改';

  @override
  String get resultsConfirmExecuteSQL => '确认执行SQL';

  @override
  String get resultsBarChart => '柱状图';

  @override
  String get resultsLineChart => '折线图';

  @override
  String get resultsPieChart => '饼图';

  @override
  String get resultsSelectAxisFields => '请选择X轴和Y轴字段';

  @override
  String get statusNotConnected => '未连接';

  @override
  String get statusConnected => '已连接';

  @override
  String statusTables(Object count) {
    return '$count 表';
  }

  @override
  String get statusNone => '无';

  @override
  String statusVersion(Object version) {
    return 'v$version';
  }

  @override
  String get backupManagement => '备份管理';

  @override
  String get backupList => '备份列表';

  @override
  String get createBackup => '创建备份';

  @override
  String get noBackupFiles => '暂无备份文件';

  @override
  String get clickCreateBackupTab => '点击\'创建备份\'标签页开始备份';

  @override
  String get importBackup => '导入备份';

  @override
  String get previewContent => '预览内容';

  @override
  String get exportFile => '导出文件';

  @override
  String get restoreBackup => '恢复备份';

  @override
  String get selectBackupToView => '选择一个备份查看详情';

  @override
  String get database => '数据库';

  @override
  String get backupType => '类型';

  @override
  String get backupSize => '大小';

  @override
  String get createdAt => '创建时间';

  @override
  String get tableCount => '表数量';

  @override
  String get description => '描述';

  @override
  String get preview => '预览';

  @override
  String get export => '导出';

  @override
  String get restore => '恢复';

  @override
  String get confirmRestore => '确认恢复';

  @override
  String confirmRestoreMessage(Object name) {
    return '确定要恢复备份 \"$name\" 吗？\n\n这将执行备份文件中的所有 SQL 语句，可能会覆盖现有数据。';
  }

  @override
  String get confirmDelete => '确认删除';

  @override
  String confirmDeleteMessage(Object name) {
    return '确定要删除备份 \"$name\" 吗？\n\n此操作不可撤销。';
  }

  @override
  String get backupFormat => '备份格式';

  @override
  String get backupContent => '备份内容';

  @override
  String get selectTablesHint => '选择表（留空备份所有）';

  @override
  String get advancedOptions => '高级选项';

  @override
  String get includeStructure => '包含表结构';

  @override
  String get includeStructureDesc => 'CREATE TABLE 语句';

  @override
  String get includeData => '包含数据';

  @override
  String get includeDataDesc => 'INSERT 语句或数据行';

  @override
  String get noTablesAvailable => '暂无可用表';

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String tablesSelected(Object count) {
    return '已选择 $count 个表';
  }

  @override
  String get addDropTable => '添加 DROP TABLE';

  @override
  String get useExtendedInsert => '使用扩展 INSERT';

  @override
  String get useExtendedInsertDesc => '多行值合并为一个 INSERT';

  @override
  String get rowLimitPerTable => '每表行数限制（可选）';

  @override
  String get leaveEmptyForNoLimit => '留空表示不限';

  @override
  String get whereCondition => 'WHERE 条件（可选）';

  @override
  String get whereConditionExample => '例如: id > 100';

  @override
  String get enterBackupDescription => '输入备份描述（可选）';

  @override
  String get startBackup => '开始备份';

  @override
  String get backupProgress => '备份进度';

  @override
  String get waitingToStartBackup => '等待开始备份...';

  @override
  String get currentTable => '当前表';

  @override
  String get progressPercent => '进度';

  @override
  String get backupComplete => '备份完成！';

  @override
  String get backupFailed => '备份失败';

  @override
  String get loadBackupListFailed => '加载备份列表失败';

  @override
  String get retry => '重试';

  @override
  String get previewFailed => '预览失败';

  @override
  String get exportedTo => '已导出到';

  @override
  String get backupRestoreSuccess => '备份恢复成功';

  @override
  String get restoreFailed => '恢复失败';

  @override
  String get backupDeleted => '备份已删除';

  @override
  String deleteFailed(Object error) {
    return '删除失败: $error';
  }

  @override
  String get selectBackupFile => '选择备份文件';

  @override
  String get backupImportSuccess => '备份文件导入成功';

  @override
  String importFailed(String error) {
    return '导入失败: $error';
  }

  @override
  String get selectAtLeastOneOption => '请至少选择备份结构或数据';

  @override
  String get backupFailedError => '备份失败';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get aiAnalyze => 'AI 分析';

  @override
  String get aiAnalyzeTable => 'AI 分析表';

  @override
  String get aiAnalyzeDatabase => 'AI 分析数据库';

  @override
  String get aiAnalyzeServer => 'AI 分析服务器';

  @override
  String get aiAnalyzeErrorResult => 'AI 分析错误';

  @override
  String aiAnalyzeNodeFailed(Object error) {
    return 'AI 分析失败：$error';
  }

  @override
  String get apiSettings => 'API设置';

  @override
  String get clearChat => '清空对话';

  @override
  String get model => '模型';

  @override
  String get enterModelName => '输入模型名称';

  @override
  String get autoExecuteSql => '自动执行SQL';

  @override
  String get autoExecuteSqlDesc => '启用后，AI生成的查询语句将自动执行';

  @override
  String get aiDatabaseAssistant => 'AI 数据库助手';

  @override
  String get aiAssistantDesc => '支持多家大模型厂商\n帮你编写SQL、优化查询、解释数据库结构';

  @override
  String get enterYourQuestion => '输入你的问题...';

  @override
  String configureApiKeyFirst(Object provider) {
    return '请先在设置中配置 $provider 的 API 密钥以启用AI对话功能。\n\n点击右上角设置图标进行配置。';
  }

  @override
  String get generationFailed => '生成失败';

  @override
  String get stepAnalyzeNeeds => '第一步：分析用户需求，确定需要查询的表...';

  @override
  String get stepGetTableSchema => '第二步：获取表的详细建表语句...';

  @override
  String get stepGenerateSql => '第三步：生成SQL语句...';

  @override
  String get analysisResultTables => '分析结果：需要查询的表';

  @override
  String get tableSchemaInfo => '表结构信息';

  @override
  String get operationCancelled => '操作已取消';

  @override
  String get executingSql => '正在执行SQL...';

  @override
  String executeSuccessRows(Object count) {
    return '执行成功，返回 $count 行数据';
  }

  @override
  String get executeFailedError => '执行失败';

  @override
  String get confirmDangerousOperation => '确认执行危险操作?';

  @override
  String get confirmExecuteSql => '确认执行SQL';

  @override
  String get dangerousOperationWarning => '此操作可能会修改或删除数据，请谨慎执行！';

  @override
  String get sqlCopied => 'SQL已复制';

  @override
  String get sqlGenerationComplete => 'SQL生成完成';

  @override
  String get dangerousOperation => '危险操作';

  @override
  String get dangerousOperationDesc => '这是一个危险操作，请谨慎处理';

  @override
  String get taskCompleteDesc => '任务已完成，您可以选择执行或复制SQL';

  @override
  String get generatedSql => '生成的 SQL';

  @override
  String get dangerous => '危险';

  @override
  String get confirmExecute => '确认执行';

  @override
  String get requestTimeout => '请求超时时间';

  @override
  String get seconds => '秒';

  @override
  String get apiSettingsSaved => 'API设置已保存';

  @override
  String get dataImport => '数据导入';

  @override
  String get selectFile => '选择文件';

  @override
  String get noFileSelected => '未选择文件';

  @override
  String get importConfig => '导入配置';

  @override
  String get targetTableName => '目标表名';

  @override
  String get enterTableName => '输入表名';

  @override
  String get includeHeader => '包含表头';

  @override
  String get delimiter => '分隔符';

  @override
  String get overwriteTable => '覆盖表';

  @override
  String get deleteExistingTable => '（删除已存在的表）';

  @override
  String get batchSize => '批量大小';

  @override
  String dataPreviewRows(Object count) {
    return '数据预览（$count 行）';
  }

  @override
  String get pleaseSelectFile => '请选择文件以预览数据';

  @override
  String get importProgress => '导入进度';

  @override
  String get importPreparing => '导入准备中...';

  @override
  String get totalRecords => '总数';

  @override
  String get importedRecords => '已导入';

  @override
  String get failedRecords => '失败';

  @override
  String get readyToImport => '准备导入';

  @override
  String get importingData => '正在导入数据...';

  @override
  String get importComplete => '导入完成！';

  @override
  String get parseFileFailed => '解析文件失败';

  @override
  String get noDataToImport => '没有可导入的数据';

  @override
  String get selectDatabaseFirst => '请先选择一个数据库';

  @override
  String get importFailedError => '导入失败';

  @override
  String get startImport => '开始导入';

  @override
  String get importing => '导入中...';

  @override
  String get optimizeSql => '优化SQL';

  @override
  String get explainQuery => '解释查询';

  @override
  String get generateInsert => '生成INSERT';

  @override
  String get generateUpdate => '生成UPDATE';

  @override
  String get generateDelete => '生成DELETE';

  @override
  String get createTableStatement => '建表语句';

  @override
  String get securityCheck => '安全检测';

  @override
  String get indexSuggestion => '索引建议';

  @override
  String get executionPlan => '执行计划';

  @override
  String get pleaseEnterSql => '请先输入SQL语句';

  @override
  String get pleaseConnectDatabase => '请先连接数据库';

  @override
  String get analysisFailed => '分析失败';

  @override
  String get loadHistoryFailed => '加载历史失败';

  @override
  String get noQueryHistory => '暂无查询历史记录\n\n执行SQL查询后，历史记录将保存在这里。';

  @override
  String queryHistoryRecords(Object count) {
    return '查询历史记录（最近 $count 条）';
  }

  @override
  String get databaseType => '数据库类型';

  @override
  String get server => '服务器';

  @override
  String get currentDatabase => '当前数据库';

  @override
  String get notConnected => '未连接';

  @override
  String get notSelected => '未选择';

  @override
  String get tableName => '表名';

  @override
  String get tableStructureInfo => '表结构信息';

  @override
  String get createStatement => '建表语句';

  @override
  String andMoreTables(Object count) {
    return '... 还有 $count 个表';
  }

  @override
  String get primaryKey => '主键';

  @override
  String get executionTime => '执行时间';

  @override
  String get status => '状态';

  @override
  String get commonFailed => '失败';

  @override
  String get format => '格式';

  @override
  String get connectionDefaultDatabase => '默认数据库';

  @override
  String get connectionSavePassword => '保存密码';

  @override
  String get connectionAdvancedOptions => '高级选项';

  @override
  String get connectionTimeout => '超时(秒)';

  @override
  String get connectionUseSSL => '使用 SSL/TLS';

  @override
  String get connectionEnableSecureConnection => '启用安全连接';

  @override
  String get connectionUseTls => '使用 TLS/SSL';

  @override
  String get connectionUseTlsDesc => '经 server 侧建立 TLS 加密连接';

  @override
  String get connectionTlsInsecure => '忽略证书校验（不安全）';

  @override
  String get connectionTlsInsecureDesc => '不校验服务端证书，仅限可信/测试环境';

  @override
  String get connectionSshSubtitleGateway =>
      'SSH 隧道由 dbmaster server 侧建立（配置随连接下发）';

  @override
  String get connectionAutoReconnect => '自动重连';

  @override
  String get connectionAutoReconnectDesc => '连接断开时自动尝试重连';

  @override
  String get connectionCharset => '字符集';

  @override
  String get connectionTimezone => '时区';

  @override
  String get connectionTestSuccess => '连接成功!';

  @override
  String connectionTestFailed(String error) {
    return '连接失败';
  }

  @override
  String get connectionDatabaseType => '数据库类型';

  @override
  String get connectionManager => '连接管理';

  @override
  String get connectionSavedConnections => '已保存的连接';

  @override
  String get connectionNoSavedConnections => '暂无保存的连接';

  @override
  String get connectionCurrent => '当前';

  @override
  String get connectionConnected => '已连接';

  @override
  String get connectionSwitchToConnection => '切换到此连接';

  @override
  String get connectionCloneConnection => '复制连接';

  @override
  String get connectionCloned => '已复制连接';

  @override
  String get connectionDeleteConnectionTitle => '删除连接';

  @override
  String get connectionDeleteConnectionConfirm => '确定要删除连接';

  @override
  String get connectionDisconnectAll => '断开全部';

  @override
  String get searchDialogTitle => '查询';

  @override
  String get searchHint => '搜索表、视图、存储过程、列...';

  @override
  String get searchNoResults => '未找到对象';

  @override
  String get searchTryDifferentKeywords => '尝试不同的关键词';

  @override
  String get searchNavigate => '导航';

  @override
  String get searchSelect => '选中';

  @override
  String get searchClose => '关闭';

  @override
  String searchResultsCount(Object count) {
    return '$count 个结果';
  }

  @override
  String get searchTypeConnection => '连接';

  @override
  String get searchTypeDatabase => '数据库';

  @override
  String get searchTypeTable => '表';

  @override
  String get searchTypeView => '视图';

  @override
  String get searchTypeProcedure => '存储过程';

  @override
  String get searchTypeColumn => '列';

  @override
  String get savedQueriesTitle => '已保存的查询';

  @override
  String get savedQueriesNoQueries => '暂无保存的查询';

  @override
  String get savedQueriesDeleteTitle => '删除查询';

  @override
  String get savedQueriesDeleteConfirm => '确定要删除此查询吗？';

  @override
  String get savedQueriesOpen => '打开';

  @override
  String get viewJson => '查看 JSON';

  @override
  String get extractFieldAsColumn => '提取字段为列';

  @override
  String get erDiagramTitle => 'ER 图';

  @override
  String get erDiagramSearchTables => '搜索表...';

  @override
  String get erDiagramHierarchicalLayout => '层级布局';

  @override
  String get erDiagramForceDirectedLayout => '力导向布局';

  @override
  String get erDiagramCircleLayout => '圆形布局';

  @override
  String get erDiagramResetLayout => '重置布局';

  @override
  String get erDiagramZoomIn => '放大';

  @override
  String get erDiagramZoomOut => '缩小';

  @override
  String get erDiagramFitToScreen => '适应屏幕';

  @override
  String get erDiagramRelations => '关系';

  @override
  String get erDiagramZoom => '缩放';

  @override
  String get erDiagramShowIsolated => '显示孤立节点';

  @override
  String get erDiagramExportAsPNG => '导出为 PNG';

  @override
  String get erDiagramExportAsJPG => '导出为 JPG';

  @override
  String get erDiagramLoading => '加载 ER 图中...';

  @override
  String get erDiagramErrorLoading => '加载 ER 图失败';

  @override
  String get erDiagramNoData => '无图表数据可用';

  @override
  String get erDiagramRetry => '重试';

  @override
  String get erDiagramSelectConnection => '选择连接';

  @override
  String get erDiagramSelectDatabase => '选择数据库';

  @override
  String get performanceAnalyzerTitle => '性能分析工具';

  @override
  String get performanceAnalyzerSearch => '搜索...';

  @override
  String get performanceAnalyzerRefresh => '刷新数据';

  @override
  String get performanceAnalyzerGenerateReport => '生成报告';

  @override
  String get performanceAnalyzerExport => '导出';

  @override
  String get performanceAnalyzerClose => '关闭';

  @override
  String get performanceAnalyzerNotConnected => '未连接到数据库';

  @override
  String get performanceAnalyzerNotConnectedDesc => '请先连接到数据库以使用性能分析功能';

  @override
  String get performanceAnalyzerConfirm => '确定';

  @override
  String get performanceAnalyzerSlowQueryAnalysis => '慢查询分析';

  @override
  String get performanceAnalyzerIndexAnalysis => '索引分析';

  @override
  String get performanceAnalyzerTableStatistics => '表统计';

  @override
  String get performanceAnalyzerPerformanceReport => '性能报告';

  @override
  String get performanceAnalyzerLoading => '正在分析数据库性能...';

  @override
  String get performanceAnalyzerLoadFailed => '加载失败';

  @override
  String get performanceAnalyzerRetry => '重试';

  @override
  String get performanceAnalyzerTimeThreshold => '时间阈值:';

  @override
  String get performanceAnalyzerNoSlowQueries => '没有找到慢查询';

  @override
  String get performanceAnalyzerSelectQuery => '选择一个查询查看详情';

  @override
  String get performanceAnalyzerQueryInfo => '查询信息';

  @override
  String get performanceAnalyzerExecutionTime => '执行时间';

  @override
  String get performanceAnalyzerDatabase => '数据库';

  @override
  String get performanceAnalyzerRowsScaned => '扫描行数';

  @override
  String get performanceAnalyzerRowsReturned => '返回行数';

  @override
  String get performanceAnalyzerTimestamp => '执行时间';

  @override
  String get performanceAnalyzerSqlStatement => 'SQL 语句';

  @override
  String get performanceAnalyzerExecutionPlan => '执行计划';

  @override
  String get performanceAnalyzerOptimizationSuggestions => '优化建议';

  @override
  String get performanceAnalyzerFullTableScan => '全表扫描检测';

  @override
  String get performanceAnalyzerFullTableScanDesc =>
      '查询使用了全表扫描(type=ALL)，建议在 WHERE 子句的列上添加索引';

  @override
  String get performanceAnalyzerFileSort => '文件排序';

  @override
  String get performanceAnalyzerFileSortDesc =>
      '查询使用了文件排序(Using filesort)，建议在 ORDER BY 列上添加索引';

  @override
  String get performanceAnalyzerTempTable => '临时表使用';

  @override
  String get performanceAnalyzerTempTableDesc =>
      '查询使用了临时表(Using temporary)，考虑优化 GROUP BY 或 DISTINCT 查询';

  @override
  String get performanceAnalyzerLowScanEfficiency => '扫描效率低';

  @override
  String get performanceAnalyzerNoIssues => '未发现明显问题';

  @override
  String get performanceAnalyzerNoIssuesDesc => '查询执行计划看起来正常';

  @override
  String get performanceAnalyzerIndexTypeDistribution => '索引类型分布';

  @override
  String get performanceAnalyzerNoData => '无数据';

  @override
  String get performanceAnalyzerTotalIndexes => '总索引';

  @override
  String get performanceAnalyzerUsedIndexes => '已使用';

  @override
  String get performanceAnalyzerUnusedIndexes => '未使用';

  @override
  String get performanceAnalyzerIndexes => '个索引';

  @override
  String get performanceAnalyzerColumns => '列:';

  @override
  String get performanceAnalyzerCardinality => '基数:';

  @override
  String get performanceAnalyzerTotalTables => '总表数';

  @override
  String get performanceAnalyzerTotalRows => '总行数';

  @override
  String get performanceAnalyzerDataSize => '数据大小';

  @override
  String get performanceAnalyzerIndexSize => '索引大小';

  @override
  String get performanceAnalyzerTotalSize => '总大小';

  @override
  String get performanceAnalyzerTableName => '表名';

  @override
  String get performanceAnalyzerEngine => '引擎';

  @override
  String get performanceAnalyzerRowCount => '行数';

  @override
  String get performanceAnalyzerPercentage => '占比';

  @override
  String get performanceAnalyzerTableSizeDistribution => '表大小分布 (Top 10)';

  @override
  String get performanceAnalyzerDatabasePerformanceReport => '数据库性能报告';

  @override
  String get performanceAnalyzerGeneratedAt => '生成时间:';

  @override
  String get performanceAnalyzerTableCount => '表数量';

  @override
  String get performanceAnalyzerSlowQueries => '慢查询';

  @override
  String get performanceAnalyzerSuggestions => '建议';

  @override
  String get performanceAnalyzerImpact => '影响:';

  @override
  String get performanceAnalyzerImpactHigh => '高';

  @override
  String get performanceAnalyzerImpactMedium => '中';

  @override
  String get performanceAnalyzerImpactLow => '低';

  @override
  String get performanceAnalyzerRecommendation => '建议操作:';

  @override
  String get performanceAnalyzerSlowQueriesTop => '慢查询 Top';

  @override
  String get performanceAnalyzerLargeTableStatistics => '大表统计';

  @override
  String get performanceAnalyzerClickGenerateReport => '点击\"生成报告\"按钮开始分析';

  @override
  String get sqlHistoryTitle => 'SQL 历史记录';

  @override
  String get sqlHistoryNoHistory => '暂无历史记录';

  @override
  String get sqlHistoryClose => '关闭';

  @override
  String get sqlHistoryDelete => '删除';

  @override
  String get sqlHistoryConfirmDelete => '确认删除';

  @override
  String get sqlHistoryDeleteConfirm => '确定要删除这条历史记录吗？';

  @override
  String get sqlHistoryJustNow => '刚刚';

  @override
  String sqlHistoryMinutesAgo(Object count) {
    return '$count 分钟前';
  }

  @override
  String sqlHistoryHoursAgo(Object count) {
    return '$count 小时前';
  }

  @override
  String sqlHistoryDaysAgo(Object count) {
    return '$count 天前';
  }

  @override
  String get aiPanelApiSettings => 'API 设置';

  @override
  String get aiPanelApiKey => 'API Key';

  @override
  String get aiPanelEnterApiKey => '输入API密钥';

  @override
  String get aiPanelApiBaseUrl => 'API Base URL (可选)';

  @override
  String get aiPanelCustomApiUrl => '自定义API地址';

  @override
  String get aiPanelRequestTimeout => '请求超时时间:';

  @override
  String get aiPanelSeconds => '秒';

  @override
  String get aiPanelSave => '保存';

  @override
  String get aiPanelApiSettingsSaved => 'API设置已保存';

  @override
  String get aiPanelConfirmDangerousOperation => '确认执行危险操作?';

  @override
  String get aiPanelConfirmExecuteSql => '确认执行SQL';

  @override
  String get aiPanelDangerousOperationWarning => '此操作可能会修改或删除数据，请谨慎执行！';

  @override
  String get aiPanelCancel => '取消';

  @override
  String get aiPanelConfirmExecute => '确认执行';

  @override
  String get aiPanelOperationCancelled => '操作已取消';

  @override
  String get aiPanelExecutingSql => '正在执行SQL...';

  @override
  String aiPanelExecuteSuccess(Object count) {
    return '执行成功，返回 $count 行';
  }

  @override
  String get aiPanelExecuteFailed => '执行失败';

  @override
  String get aiPanelDataPreview => '数据预览';

  @override
  String aiPanelAndMoreRows(Object count) {
    return '还有 $count 行数据';
  }

  @override
  String aiPanelSqlExecutionSuccess(Object count) {
    return 'SQL执行成功，返回 $count 行';
  }

  @override
  String get aiPanelSqlGenerationComplete => 'SQL生成完成';

  @override
  String get aiPanelSqlGenerationCompleteWarning => 'SQL生成完成 ⚠️';

  @override
  String get aiPanelTaskCompleteDesc => '任务已完成，您可以选择执行或复制SQL';

  @override
  String get aiPanelDangerousOperationDesc => '这是一个危险操作，请谨慎处理';

  @override
  String get aiPanelGeneratedSql => '生成的 SQL';

  @override
  String get aiPanelDangerous => '危险';

  @override
  String get aiPanelContinue => '继续';

  @override
  String get aiPanelClose => '关闭';

  @override
  String get aiPanelCopy => '复制';

  @override
  String get aiPanelExecute => '执行';

  @override
  String get aiPanelConfirmExecuteDangerous => '确认执行';

  @override
  String get quickActionsTitle => '快捷操作';

  @override
  String get quickActionsNewTable => '新表';

  @override
  String get quickActionsNewQuery => '新查询';

  @override
  String get quickActionsAiAssistant => 'AI助手';

  @override
  String get quickActionsSelectDatabaseFirst => '请先选择一个数据库';

  @override
  String get resultsTabResults => '结果';

  @override
  String get resultsTabMessages => '消息';

  @override
  String get resultsTabExecutionPlan => '执行计划';

  @override
  String get resultsTabExecutionDetails => '执行详情';

  @override
  String get resultsSearchBtn => '搜索';

  @override
  String get resultsSearchHint => '在结果中搜索…';

  @override
  String resultsSearchNoMatch(Object query) {
    return '没有匹配「$query」的行';
  }

  @override
  String get resultsClear => '清空';

  @override
  String get resultsSubmit => '提交';

  @override
  String get resultsSearchResults => '搜索结果';

  @override
  String get resultsViewTable => '表格';

  @override
  String get resultsViewCard => '卡片';

  @override
  String get resultsViewChart => '图表';

  @override
  String get resultsViewStatistics => '统计';

  @override
  String get paginationShowing => '显示';

  @override
  String get paginationRows => '共';

  @override
  String get paginationFirstPage => '第一页';

  @override
  String get paginationPreviousPage => '上一页';

  @override
  String get paginationNextPage => '下一页';

  @override
  String get paginationLastPage => '最后一页';

  @override
  String get editModeTitle => '编辑模式';

  @override
  String get editModeChanges => '处修改';

  @override
  String get editModeHint => '双击编辑 | Enter确认 | Esc取消当前 | Tab切换';

  @override
  String get resultsNoDataTitle => '无结果数据';

  @override
  String get resultsNoDataMessage => '执行查询后将显示结果';

  @override
  String get resultsNoDataCardMessage => '执行查询后将显示卡片视图';

  @override
  String get resultsNoDataChartMessage => '执行查询后将显示图表';

  @override
  String get resultsNoDataStatisticsMessage => '执行查询后将显示统计信息';

  @override
  String get resultsNoDataExecutionPlanMessage => '点击\"执行计划\"按钮查看查询执行计划';

  @override
  String get statisticsTotalRows => '总行数';

  @override
  String get statisticsFieldInfo => '字段信息';

  @override
  String get statisticsNumeric => '数值';

  @override
  String get statisticsText => '文本';

  @override
  String get statisticsNumericStats => '数值统计';

  @override
  String get statisticsCount => '数量';

  @override
  String get statisticsSum => '总和';

  @override
  String get statisticsAvg => '平均值';

  @override
  String get statisticsMin => '最小值';

  @override
  String get statisticsMax => '最大值';

  @override
  String get chartXAxis => 'X 轴';

  @override
  String get chartYAxis => 'Y 轴';

  @override
  String get chartType => '类型: ';

  @override
  String get chartCannotGenerate => '无法生成图表：请确保Y轴字段包含数值数据';

  @override
  String messagesQuerySuccess(Object cols, Object rows) {
    return '查询成功，返回 $rows 行，$cols 列';
  }

  @override
  String get messagesExecuteToSeeResults => '执行查询后将显示结果信息';

  @override
  String sqlPreviewWillExecute(Object count, Object table) {
    return '即将对表 `$table` 执行以下 $count 条SQL语句：';
  }

  @override
  String get saveErrorNoTab => '无法保存：当前标签页不存在';

  @override
  String get saveErrorCannotExtractTable => '无法保存：无法从查询中提取表名';

  @override
  String saveErrorFailed(Object error) {
    return '保存失败: $error';
  }

  @override
  String get exportSelectFormat => '选择导出格式';

  @override
  String get toolbarExecute => '执行';

  @override
  String get toolbarStop => '停止';

  @override
  String get toolbarReadOnlyChip => '只读';

  @override
  String get toolbarLimitChipTooltip => '此连接的行数限制（自动 LIMIT）';

  @override
  String get toolbarTimeoutChipTooltip => '此连接的查询超时';

  @override
  String get toolbarChipFollowSettings => '跟随设置';

  @override
  String get toolbarChipOff => '关闭';

  @override
  String get toolbarChipFollowConnection => '跟随连接';

  @override
  String get gridEditBlockedReadOnly => '连接为只读，单元格编辑已禁用。';

  @override
  String get gridEditBlockedNoTable => '无法从结果推断目标表——单元格编辑需要单表查询。';

  @override
  String gridEditsCount(Object count, Object rows) {
    return '$count 处修改 · $rows 行';
  }

  @override
  String get gridCommitButton => '提交更改';

  @override
  String get gridDiscardButton => '放弃修改';

  @override
  String gridCommitSuccess(Object rows) {
    return '已写回 $rows 行';
  }

  @override
  String gridCommitNoPrimaryKey(Object table) {
    return '表 $table 无主键，无法写回。';
  }

  @override
  String gridCommitFailed(Object error) {
    return '写回失败：$error';
  }

  @override
  String get statusBarReady => '就绪';

  @override
  String get statusBarExecuting => '执行中';

  @override
  String statusBarElapsed(String duration) {
    return '已耗时 $duration';
  }

  @override
  String statusBarLineCol(int line, int column) {
    return '行 $line, 列 $column';
  }

  @override
  String executionStatusBarRows(int count) {
    return '$count 行';
  }

  @override
  String get executionStatusBarErrorHint => '点击结果子标签查看错误详情';

  @override
  String get statusBarConnectionErrorTooltip => '存在未处理的连接错误，点击查看';

  @override
  String get toolbarExecutionPlan => '执行计划';

  @override
  String get toolbarFormat => '格式化';

  @override
  String get toolbarSave => '保存';

  @override
  String get splitButton => '分屏编辑';

  @override
  String get horizontalSplit => '水平分屏';

  @override
  String get verticalSplit => '垂直分屏';

  @override
  String get refreshData => '刷新数据';

  @override
  String get analyzingDatabasePerformance => '正在分析数据库性能...';

  @override
  String get fullTableScanDetected => '全表扫描检测';

  @override
  String get fullTableScanDesc => '查询使用了全表扫描(type=ALL)，建议在 WHERE 子句的列上添加索引';

  @override
  String get timeThreshold => '时间阈值：';

  @override
  String get searchPlaceholder => '搜索...';

  @override
  String get closeBtn => '关闭';

  @override
  String get apiSettingsSavedMsg => 'API设置已保存';

  @override
  String get resultsHeaderExport => '导出';

  @override
  String get resultsHeaderSearch => '搜索';

  @override
  String get resultsHeaderClear => '清空';

  @override
  String get resultsHeaderSubmit => '提交';

  @override
  String get connectionStatusConnected => '已连接';

  @override
  String get connectionStatusNotConnected => '未连接';

  @override
  String get selectConnection => '选择连接...';

  @override
  String get selectDatabase => '选择数据库';

  @override
  String get aiQuickActionOptimizeSql => '优化SQL';

  @override
  String get aiQuickActionExplainQuery => '解释查询';

  @override
  String get aiQuickActionGenerateInsert => '生成INSERT';

  @override
  String get aiQuickActionGenerateUpdate => '生成UPDATE';

  @override
  String get aiQuickActionGenerateDelete => '生成DELETE';

  @override
  String get aiQuickActionCreateTable => '建表语句';

  @override
  String get aiQuickActionSecurityCheck => '安全检测';

  @override
  String get aiQuickActionIndexSuggestion => '索引建议';

  @override
  String get aiQuickActionExecutionPlan => '执行计划';

  @override
  String get aiQuickActionQueryHistory => '查询历史';

  @override
  String get shortcutCategoryQuery => '查询';

  @override
  String get queryCancelled => '查询已取消';

  @override
  String queryFailed(Object error) {
    return '查询失败: $error';
  }

  @override
  String querySuccessWithTime(Object count, Object time) {
    return '查询成功，返回 $count 行数据 (${time}ms)';
  }

  @override
  String get cancelingQuery => '正在取消查询...';

  @override
  String get cancelQueryFailed => '取消查询失败';

  @override
  String get confirmCancelTransaction => '确认取消事务';

  @override
  String get confirmCancelTransactionMessage =>
      '当前连接有未提交的事务。取消查询将断开并重新连接，导致事务回滚。是否继续？';

  @override
  String get cancel => '取消';

  @override
  String get explainPlanSuccess => '执行计划获取成功';

  @override
  String explainPlanFailed(Object error) {
    return '获取执行计划失败: $error';
  }

  @override
  String get queryEmptyCannotSave => '查询内容为空，无法保存';

  @override
  String get saveQueryTitle => '保存查询';

  @override
  String get queryName => '查询名称';

  @override
  String get enterQueryName => '输入查询名称';

  @override
  String get saveQueryHint => '将保存到已保存查询列表中（最多20个）';

  @override
  String querySaved(Object name) {
    return '查询已保存: $name';
  }

  @override
  String get saveQueryLimitReached => '已达到保存上限（20个），请先删除一些查询';

  @override
  String savedQueryNameExists(Object name) {
    return '保存查询名称 \"$name\" 在当前连接下已存在';
  }

  @override
  String get sqlFormatted => 'SQL 已格式化';

  @override
  String get pleaseEnterSqlCode => '请输入 SQL 代码';

  @override
  String get noConnectedServer => '没有已连接的服务器';

  @override
  String get split2Hint => '分屏 2 - 输入 SQL 查询...';

  @override
  String get toolbarClose => '关闭';

  @override
  String connectedToServer(Object serverName) {
    return '已连接到 $serverName';
  }

  @override
  String openTableDataFailed(Object error) {
    return '打开表数据失败: $error';
  }

  @override
  String queryTable(Object tableName) {
    return '查询 $tableName';
  }

  @override
  String openViewFailed(Object error) {
    return '打开视图失败: $error';
  }

  @override
  String queryView(Object viewName) {
    return '查询 $viewName';
  }

  @override
  String openProcedureFailed(Object error) {
    return '打开存储过程失败: $error';
  }

  @override
  String callProcedure(Object procName) {
    return '调用 $procName';
  }

  @override
  String get cancelConnection => '取消连接';

  @override
  String get deleteConnectionTitle => '删除连接';

  @override
  String deleteConnectionConfirm(Object serverName) {
    return '确定要删除连接 \"$serverName\" 吗？';
  }

  @override
  String get refresh => '刷新';

  @override
  String get createNewTable => '新建表';

  @override
  String get erDiagram => 'ER 图';

  @override
  String get properties => '属性';

  @override
  String get exportStructure => '导出结构';

  @override
  String get dropDatabase => '删除数据库';

  @override
  String get confirmDeleteDatabase => '删除数据库';

  @override
  String get confirmDropTable => '删除表';

  @override
  String typeNameToConfirm(String name) {
    return '输入 \"$name\" 以确认';
  }

  @override
  String dropDatabaseWarning(String name) {
    return '数据库 \"$name\" 将被永久删除。';
  }

  @override
  String objectCountWarning(int count, String type) {
    return '$count 个$type将被销毁';
  }

  @override
  String get allDataWillBeLost => '所有数据将丢失';

  @override
  String copiedDbStructureToClipboard(Object dbName) {
    return '已复制 $dbName 的结构到剪贴板';
  }

  @override
  String databaseDeleted(Object dbName) {
    return '数据库 $dbName 已删除';
  }

  @override
  String get browseData => '浏览数据';

  @override
  String get editTable => '修改表';

  @override
  String get copyTableName => '复制表名';

  @override
  String get copyColumnName => '复制列名';

  @override
  String get copyIndexName => '复制索引名';

  @override
  String get dropColumn => '删除列';

  @override
  String get editIndex => '编辑索引';

  @override
  String get dropIndex => '删除索引';

  @override
  String confirmDropColumn(Object column, Object table) {
    return '确定要删除表 \"$table\" 中的列 \"$column\" 吗？';
  }

  @override
  String confirmDropIndex(Object index) {
    return '确定要删除索引 \"$index\" 吗？';
  }

  @override
  String columnDropped(Object column) {
    return '列 \"$column\" 已删除';
  }

  @override
  String indexDropped(Object index) {
    return '索引 \"$index\" 已删除';
  }

  @override
  String dropColumnFailed(Object error) {
    return '删除列失败: $error';
  }

  @override
  String dropIndexFailed(Object error) {
    return '删除索引失败: $error';
  }

  @override
  String get loadingSchema => '加载中...';

  @override
  String get noColumns => '无列';

  @override
  String get noIndexes => '无索引';

  @override
  String get noProgrammableObjects => '此数据库类型不支持可编程对象';

  @override
  String get exportData => '导出数据';

  @override
  String get dataSync => '数据同步';

  @override
  String get rename => '重命名';

  @override
  String get truncate => '清空数据';

  @override
  String get dropTable => '删除表';

  @override
  String loadTableStructureFailed(Object error) {
    return '加载表结构失败: $error';
  }

  @override
  String get tableNameCopied => '已复制表名';

  @override
  String copiedTableDataToClipboard(Object tableName) {
    return '已复制 $tableName 的数据到剪贴板';
  }

  @override
  String tableRenamedTo(Object newName) {
    return '表已重命名为 $newName';
  }

  @override
  String renameFailed(Object error) {
    return '重命名失败: $error';
  }

  @override
  String tableTruncated(Object tableName) {
    return '表 $tableName 已清空';
  }

  @override
  String truncateFailed(Object error) {
    return '清空失败: $error';
  }

  @override
  String tableDeleted(Object tableName) {
    return '表 $tableName 已删除';
  }

  @override
  String get analyzeTable => '分析表';

  @override
  String get optimizeTable => '优化表';

  @override
  String get checkTable => '检查表';

  @override
  String confirmAnalyzeTable(Object tableName) {
    return '分析表 $tableName';
  }

  @override
  String confirmAnalyzeTableMessage(Object tableName) {
    return '这将更新表 \"$tableName\" 的索引统计信息。';
  }

  @override
  String confirmOptimizeTable(Object tableName) {
    return '优化表 $tableName';
  }

  @override
  String confirmOptimizeTableMessage(Object tableName) {
    return '这将整理表 \"$tableName\" 的碎片并回收未使用空间。';
  }

  @override
  String confirmCheckTable(Object tableName) {
    return '检查表 $tableName';
  }

  @override
  String confirmCheckTableMessage(Object tableName) {
    return '这将检查表 \"$tableName\" 是否存在错误。';
  }

  @override
  String get optimizeTableWarning => '此操作可能会锁表，在大表上可能需要较长时间。';

  @override
  String analyzeTableResultTitle(Object tableName) {
    return '分析结果：$tableName';
  }

  @override
  String optimizeTableResultTitle(Object tableName) {
    return '优化结果：$tableName';
  }

  @override
  String checkTableResultTitle(Object tableName) {
    return '检查结果：$tableName';
  }

  @override
  String get maintenanceExecutedSql => '执行的 SQL';

  @override
  String get maintenanceResult => '结果';

  @override
  String maintenanceFailed(Object operation, Object error) {
    return '$operation 失败：$error';
  }

  @override
  String get tableMaintenance => 'Table Maintenance';

  @override
  String get vacuumTable => 'VACUUM';

  @override
  String get vacuumFullTable => 'VACUUM FULL';

  @override
  String get analyzeTablePg => 'ANALYZE';

  @override
  String get reindexTable => 'REINDEX';

  @override
  String get reindexTableConcurrently => 'REINDEX CONCURRENTLY';

  @override
  String get clusterTable => 'CLUSTER';

  @override
  String confirmVacuumTable(Object tableName) {
    return 'VACUUM $tableName';
  }

  @override
  String confirmVacuumTableMessage(Object tableName) {
    return 'This will reclaim storage occupied by dead tuples in table \"$tableName\".';
  }

  @override
  String confirmVacuumFullTable(Object tableName) {
    return 'VACUUM FULL $tableName';
  }

  @override
  String confirmVacuumFullTableMessage(Object tableName) {
    return 'This will completely rewrite table \"$tableName\" and reclaim all free space back to the OS.';
  }

  @override
  String confirmAnalyzeTablePg(Object tableName) {
    return 'ANALYZE $tableName';
  }

  @override
  String confirmAnalyzeTablePgMessage(Object tableName) {
    return 'This will update query planner statistics for table \"$tableName\".';
  }

  @override
  String confirmReindexTable(Object tableName) {
    return 'REINDEX $tableName';
  }

  @override
  String confirmReindexTableMessage(Object tableName) {
    return 'This will rebuild all indexes on table \"$tableName\" to eliminate bloat.';
  }

  @override
  String confirmReindexConcurrentlyTable(Object tableName) {
    return 'REINDEX CONCURRENTLY $tableName';
  }

  @override
  String confirmReindexConcurrentlyTableMessage(Object tableName) {
    return 'This will rebuild all indexes on table \"$tableName\" without blocking writes.';
  }

  @override
  String confirmClusterTable(Object tableName) {
    return 'CLUSTER $tableName';
  }

  @override
  String confirmClusterTableMessage(Object tableName) {
    return 'This will physically reorder table \"$tableName\" based on its primary index.';
  }

  @override
  String get vacuumFullWarning =>
      'This operation acquires an ACCESS EXCLUSIVE lock and blocks all concurrent reads/writes.';

  @override
  String get reindexWarning =>
      'This operation blocks writes to the table until the index rebuild completes.';

  @override
  String get clusterWarning =>
      'This operation acquires an ACCESS EXCLUSIVE lock and rewrites the entire table.';

  @override
  String vacuumTableResultTitle(Object tableName) {
    return 'VACUUM Result: $tableName';
  }

  @override
  String vacuumFullTableResultTitle(Object tableName) {
    return 'VACUUM FULL Result: $tableName';
  }

  @override
  String analyzeTablePgResultTitle(Object tableName) {
    return 'ANALYZE Result: $tableName';
  }

  @override
  String reindexTableResultTitle(Object tableName) {
    return 'REINDEX Result: $tableName';
  }

  @override
  String reindexConcurrentlyTableResultTitle(Object tableName) {
    return 'REINDEX CONCURRENTLY Result: $tableName';
  }

  @override
  String clusterTableResultTitle(Object tableName) {
    return 'CLUSTER Result: $tableName';
  }

  @override
  String get indexTypeNormal => '普通';

  @override
  String get indexTypeUnique => '唯一';

  @override
  String get hintIndexColumns => '如: id, name';

  @override
  String get pleaseDefineAtLeastOneColumn => '请至少定义一个列';

  @override
  String tableCreated(Object tableName) {
    return '表 $tableName 创建成功';
  }

  @override
  String createFailed(Object error) {
    return '创建失败: $error';
  }

  @override
  String get tableModified => '表修改成功';

  @override
  String modifyFailed(Object error) {
    return '修改失败: $error';
  }

  @override
  String get noInformation => '无信息';

  @override
  String get truncateTableData => '清空表数据';

  @override
  String get menuCut => '剪切';

  @override
  String get menuCopy => '复制';

  @override
  String get menuPaste => '粘贴';

  @override
  String get menuSelectAll => '全选';

  @override
  String get menuFormatSql => '格式化 SQL';

  @override
  String get menuExecuteQuery => '执行查询';

  @override
  String get commandNewConnection => '新建连接';

  @override
  String get commandNewTab => '新建标签';

  @override
  String get commandExecuteQuery => '执行查询';

  @override
  String get commandFormatSql => '格式化 SQL';

  @override
  String get commandToggleAiPanel => '切换 AI 面板';

  @override
  String get commandQueryHistory => '查询历史';

  @override
  String get commandShortcuts => '快捷键';

  @override
  String get commandSettings => '设置';

  @override
  String get commandCategoryHistory => '历史';

  @override
  String get commandCategoryHelp => '帮助';

  @override
  String get commandDescNewConnection => '创建新的数据库连接';

  @override
  String get commandDescNewTab => '创建新的查询标签';

  @override
  String get commandDescExecuteQuery => '运行当前 SQL 查询';

  @override
  String get commandDescFormatSql => '美化 SQL 代码格式';

  @override
  String get commandDescToggleSidebar => '显示或隐藏侧边栏';

  @override
  String get commandDescToggleAiPanel => '显示或隐藏 AI 助手面板';

  @override
  String get commandDescQueryHistory => '查看执行历史';

  @override
  String get commandDescShortcuts => '查看所有快捷键';

  @override
  String get commandDescSettings => '打开应用设置';

  @override
  String get searchNavigateKeys => '↑↓/鼠标';

  @override
  String get menuConnect => '连接';

  @override
  String get menuCancelConnection => '取消连接';

  @override
  String get menuDisconnect => '断开连接';

  @override
  String get menuRefresh => '刷新';

  @override
  String get menuEditConnection => '编辑连接';

  @override
  String get menuCloneConnection => '复制连接';

  @override
  String get menuDeleteConnection => '删除连接';

  @override
  String get addColumn => '添加列';

  @override
  String get addIndex => '添加索引';

  @override
  String get noIndexesClickToAdd => '暂无索引，点击上方按钮添加';

  @override
  String get formatCSV => 'CSV';

  @override
  String get formatJSON => 'JSON';

  @override
  String get formatExcel => 'Excel';

  @override
  String get formatMarkdown => 'Markdown';

  @override
  String get formatSqlInsert => 'SQL INSERT';

  @override
  String get formatCSVDesc =>
      'CSV 是通用的电子表格格式，兼容 Excel、Numbers、Google Sheets 等工具。';

  @override
  String get formatJSONDesc => 'JSON 是结构化数据格式，适合程序读取或 API 接口调用。';

  @override
  String get formatExcelDesc => 'Excel 格式保留数据类型和格式，适合深度数据分析。';

  @override
  String get formatMarkdownDesc => 'Markdown 表格格式适合文档、报告或代码审查中使用。';

  @override
  String get formatSqlInsertDesc => 'SQL INSERT 语句可直接导入到其他数据库，适合数据迁移。';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get hintFormatName => '例如：我的格式';

  @override
  String get hintOptionalDescription => '可选描述';

  @override
  String get formatterSelectPreset => '选择预设';

  @override
  String get formatterFormat => '格式化';

  @override
  String get formatterCopyResult => '复制结果';

  @override
  String get formatterHintInputSql => '在此输入 SQL 代码...';

  @override
  String get formatterSpace => '空格';

  @override
  String get formatterTab => 'Tab';

  @override
  String get formatterIndentSize => '缩进大小';

  @override
  String get formatterMaxLineLength => '最大行长度';

  @override
  String get formatterUppercaseKeywords => '关键字大写';

  @override
  String get formatterAlignKeywords => '对齐关键字';

  @override
  String get formatterPreserveComments => '保留注释';

  @override
  String get formatterNewlineBeforeParentheses => '括号前换行';

  @override
  String get formatterCompactMode => '紧凑模式';

  @override
  String get formatterPosition => '位置';

  @override
  String get formatterEnd => '末尾';

  @override
  String get formatterStart => '开头';

  @override
  String loadFailed(Object error) {
    return '加载失败: $error';
  }

  @override
  String exportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String timeAgoDays(Object count) {
    return '$count天前';
  }

  @override
  String timeAgoHours(Object count) {
    return '$count小时前';
  }

  @override
  String timeAgoMinutes(Object count) {
    return '$count分钟前';
  }

  @override
  String get timeAgoJustNow => '刚刚';

  @override
  String get optimizationFullTableScan => '全表扫描检测';

  @override
  String get optimizationFullTableScanDesc =>
      '查询使用了全表扫描(type=ALL)，建议在 WHERE 子句的列上添加索引';

  @override
  String get optimizationFilesort => '文件排序';

  @override
  String get optimizationFilesortDesc =>
      '查询使用了文件排序(Using filesort)，建议在 ORDER BY 列上添加索引';

  @override
  String get optimizationTemporary => '临时表使用';

  @override
  String get optimizationTemporaryDesc =>
      '查询使用了临时表(Using temporary)，考虑优化 GROUP BY 或 DISTINCT 查询';

  @override
  String get optimizationLowEfficiency => '扫描效率低';

  @override
  String optimizationLowEfficiencyDesc(
    Object ratio,
    Object rowsExamined,
    Object rowsSent,
  ) {
    return '扫描了 $rowsExamined 行但只返回了 $rowsSent 行，扫描比例为 $ratio:1';
  }

  @override
  String get optimizationNoIssue => '未发现明显问题';

  @override
  String get optimizationNoIssueDesc => '查询执行计划看起来正常';

  @override
  String get optimizationSuggestions => '优化建议';

  @override
  String get indexTypeDistribution => '索引类型分布';

  @override
  String get noData => '无数据';

  @override
  String get indexPrimary => '主键';

  @override
  String get indexUnique => '唯一';

  @override
  String get indexNormal => '普通';

  @override
  String get totalIndexes => '总索引';

  @override
  String get indexUsed => '已使用';

  @override
  String get indexUnused => '未使用';

  @override
  String indexCount(Object count) {
    return '$count 个索引';
  }

  @override
  String columnCardinality(Object cardinality) {
    return '基数: $cardinality';
  }

  @override
  String columnsLabel(Object columns) {
    return '列: $columns';
  }

  @override
  String get totalTables => '总表数';

  @override
  String get totalRows => '总行数';

  @override
  String get dataSize => '数据大小';

  @override
  String get indexSize => '索引大小';

  @override
  String get tableSizeDistribution => '表大小分布 (Top 10)';

  @override
  String get tableNameLabel => '表名';

  @override
  String get tableEngineLabel => '引擎';

  @override
  String get tableRowCountLabel => '行数';

  @override
  String get tableDataSizeLabel => '数据大小';

  @override
  String get tableIndexSizeLabel => '索引大小';

  @override
  String get tableTotalSizeLabel => '总大小';

  @override
  String get tableRatioLabel => '占比';

  @override
  String get databasePerformanceReport => '数据库性能报告';

  @override
  String databaseLabel(Object name) {
    return '数据库: $name';
  }

  @override
  String generatedAtLabel(Object time) {
    return '生成时间: $time';
  }

  @override
  String get tableCountLabel => '表数量';

  @override
  String get slowQueryCountLabel => '慢查询';

  @override
  String get suggestionCountLabel => '建议';

  @override
  String impactLevel(Object level) {
    return '影响: $level';
  }

  @override
  String get impactHigh => '高';

  @override
  String get impactMedium => '中';

  @override
  String get impactLow => '低';

  @override
  String get recommendedAction => '建议操作:';

  @override
  String slowQueryTopN(Object count) {
    return '慢查询 Top $count';
  }

  @override
  String get largeTableStats => '大表统计';

  @override
  String get tabRenameTitle => '重命名查询';

  @override
  String get tabRenameHint => '输入查询名称';

  @override
  String get tabRename => '重命名';

  @override
  String get tabClose => '关闭';

  @override
  String get tabCloseOthers => '关闭其他';

  @override
  String get tabCloseToRight => '关闭右侧';

  @override
  String get tabCloseAll => '关闭所有';

  @override
  String get tabDuplicate => '复制标签页';

  @override
  String get tabNewTooltip => '新建查询 (Ctrl+T)';

  @override
  String tabNewQueryTitle(Object count) {
    return '查询$count';
  }

  @override
  String get confirm => '确定';

  @override
  String get copySuffix => '（副本）';

  @override
  String get triggerTitle => '触发器';

  @override
  String triggerFailedToLoad(Object error) {
    return '加载触发器失败: $error';
  }

  @override
  String get triggerFailedToLoadDefinition => '加载触发器定义失败';

  @override
  String get triggerDeleteTitle => '删除触发器';

  @override
  String triggerDeleteConfirm(Object name) {
    return '确定要删除触发器 \"$name\" 吗？';
  }

  @override
  String triggerDeleted(Object name) {
    return '触发器 \"$name\" 已删除';
  }

  @override
  String triggerDeleteFailed(Object error) {
    return '删除触发器失败: $error';
  }

  @override
  String get triggerCannotDisable => 'MySQL 触发器无法直接禁用。请使用删除来移除。';

  @override
  String get triggerShowList => '显示列表';

  @override
  String get triggerGroupByTable => '按表分组';

  @override
  String get triggerSearchHint => '搜索触发器...';

  @override
  String get triggerNoTriggers => '未找到触发器';

  @override
  String get triggerCreate => '创建触发器';

  @override
  String get triggerViewDefinition => '查看定义';

  @override
  String get triggerCopyName => '复制名称';

  @override
  String triggerCopied(Object name) {
    return '已复制 \"$name\" 到剪贴板';
  }

  @override
  String get triggerNew => '新建触发器';

  @override
  String triggerDefinition(Object name) {
    return '触发器: $name';
  }

  @override
  String get formatterSqlFormat => 'SQL 格式化';

  @override
  String get formatterSavePreset => '保存预设';

  @override
  String get formatterPresetName => '预设名称';

  @override
  String get formatterCustomPreset => '自定义预设';

  @override
  String get formatterBuiltIn => '内置';

  @override
  String get formatterSaveAsPreset => '保存当前设置为预设';

  @override
  String get formatterDeletePreset => '删除预设';

  @override
  String get formatterInput => '输入';

  @override
  String get formatterOptions => '格式化选项';

  @override
  String get formatterIndent => '缩进';

  @override
  String get formatterKeywords => '关键字';

  @override
  String get formatterCommaStyle => '逗号风格';

  @override
  String get formatterApplyToEditor => '应用到编辑器';

  @override
  String filterTitle(String columnName) {
    return '筛选: $columnName';
  }

  @override
  String get filterEquals => '等于';

  @override
  String get filterNotEquals => '不等于';

  @override
  String get filterContains => '包含';

  @override
  String get filterNotContains => '不包含';

  @override
  String get filterGreaterThan => '大于';

  @override
  String get filterLessThan => '小于';

  @override
  String get filterIsEmpty => '为空';

  @override
  String get filterIsNotEmpty => '不为空';

  @override
  String get filterRegex => '正则表达式';

  @override
  String get filterValue => '值';

  @override
  String get filterEnterValue => '输入筛选值';

  @override
  String get filterCaseSensitive => '区分大小写';

  @override
  String get filterTimeFilter => '时间筛选';

  @override
  String get filterToday => '今天';

  @override
  String get filterLast24Hours => '最近24小时';

  @override
  String get filterLast7Days => '最近7天';

  @override
  String get filterLast30Days => '最近30天';

  @override
  String rowCountLabel(Object count) {
    return '$count 行';
  }

  @override
  String get toolbarCodeSnippets => '代码片段 (Ctrl+Shift+S)';

  @override
  String get toolbarCloseSplit => '关闭分屏';

  @override
  String get editorHintText =>
      '输入 SQL 查询... (Ctrl+Space 自动完成, F5/Ctrl+Enter 执行)';

  @override
  String get editorHintTextMongodb => '输入 MongoDB 查询... (F5/Ctrl+Enter 执行)';

  @override
  String get editorHintTextRedis => '输入 Redis 命令... (F5/Ctrl+Enter 执行)';

  @override
  String allStatementsSuccess(int count, int time) {
    return '全部 $count 条语句执行成功 (${time}ms)';
  }

  @override
  String statementsPartialSuccess(
    int success,
    int total,
    int failed,
    int time,
  ) {
    return '$success/$total 条成功, $failed 条失败 (${time}ms)';
  }

  @override
  String statementsAllSuccess(int count) {
    return '$count 条语句执行成功';
  }

  @override
  String statementsPartialSuccessShort(int success, int total, int failed) {
    return '$success/$total 成功，$failed 失败';
  }

  @override
  String get aiPanelCustomModel => '自定义模型';

  @override
  String get aiPanelBookmarks => '书签';

  @override
  String get aiPanelScrollToMessageDeveloping => '滚动到消息功能开发中';

  @override
  String get aiPanelBranchConversationCreated => '已创建分支对话';

  @override
  String get aiPanelNoConnections => '暂无连接，请在连接管理中创建';

  @override
  String get aiPanelConversationList => '会话列表';

  @override
  String get aiPanelSelectConnection => '选择连接';

  @override
  String get aiPanelNoConnection => '无连接';

  @override
  String get aiPanelSelectDatabaseFirst => '先选择连接';

  @override
  String get aiPanelSelectDatabase => '选择数据库';

  @override
  String get aiPanelAllDatabases => '所有数据库';

  @override
  String get aiPanelConnectionFailed => '连接失败';

  @override
  String get aiPanelUnknownError => '未知错误';

  @override
  String get aiPanelLoadDatabasesFailed => '加载数据库失败';

  @override
  String get aiPanelDangerousOperation => '危险操作';

  @override
  String get aiPanelOptimizeSql => '优化SQL';

  @override
  String get aiPanelSecurityAnalysis => '安全分析';

  @override
  String get aiPanelExecutionPlan => '执行计划';

  @override
  String get aiPanelIndexSuggestions => '索引建议';

  @override
  String get aiPanelInputHint => '请输入您的数据库问题，例如：如何优化这个查询？';

  @override
  String get aiPanelStop => '停止';

  @override
  String get aiPanelSend => '发送';

  @override
  String get aiPanelSelectConnectionFirst => '请先在上方的下拉框中选择一个连接实例。';

  @override
  String aiPanelConnectionNotAvailable(Object name) {
    return '连接实例 \"$name\" 未连接或不可用，请先连接该实例。';
  }

  @override
  String get aiPanelTable => '表';

  @override
  String get aiPanelDangerousOperationBadge => '危险操作';

  @override
  String get aiPanelThinkingProcess => '思考过程';

  @override
  String get aiPanelExpandThinking => '展开思考过程';

  @override
  String get aiPanelCollapseThinking => '收起思考过程';

  @override
  String get aiPanelRenameSession => '重命名会话';

  @override
  String get aiPanelSessionTitle => '会话标题';

  @override
  String get aiPanelDeleteSession => '删除会话';

  @override
  String aiPanelDeleteSessionConfirm(Object name) {
    return '确定要删除 \"$name\" 吗？';
  }

  @override
  String get aiPanelRename => '重命名';

  @override
  String get aiPanelUnarchive => '取消归档';

  @override
  String get aiPanelArchive => '归档';

  @override
  String get aiPanelSessions => '会话';

  @override
  String get aiPanelSearchSessions => '搜索会话';

  @override
  String get aiPanelNoSessions => '暂无会话';

  @override
  String aiPanelArchivedSessions(Object count) {
    return '归档会话 ($count)';
  }

  @override
  String get aiPanelJustNow => '刚刚';

  @override
  String aiPanelMinutesAgo(Object count) {
    return '$count分钟前';
  }

  @override
  String aiPanelHoursAgo(Object count) {
    return '$count小时前';
  }

  @override
  String aiPanelDaysAgo(Object count) {
    return '$count天前';
  }

  @override
  String get aiPanelSelectProvider => '选择模型厂商';

  @override
  String aiPanelSelectModelCurrent(Object provider) {
    return '选择模型 (当前: $provider)';
  }

  @override
  String aiPanelApiConfigCurrent(Object provider) {
    return 'API 配置 (当前: $provider)';
  }

  @override
  String get aiPanelModelProviderMismatch => '所选模型不属于所选厂商';

  @override
  String get aiPanelAllowSession => '允许本次会话';

  @override
  String get aiPanelNoBookmarks => '暂无书签';

  @override
  String get aiPanelClickBookmarkIcon => '点击消息上的书签图标添加';

  @override
  String get aiCmdOptimizeSql => '优化SQL语句';

  @override
  String get aiCmdExplainQuery => '解释查询计划';

  @override
  String get aiCmdGenerateCrud => '生成CRUD语句';

  @override
  String get aiCmdAnalyzeTable => '分析表结构';

  @override
  String get aiCmdShowHistory => '查看查询历史';

  @override
  String get aiCmdShowBookmarks => '查看书签';

  @override
  String get aiCmdBranchConversation => '创建分支对话';

  @override
  String get aiCmdListDatabases => '列出所有数据库';

  @override
  String get aiCmdListTables => '列出所有表';

  @override
  String get settingsThemeMode => '主题模式';

  @override
  String get settingsThemeColor => '主题色';

  @override
  String get settingsSystem => '跟随系统';

  @override
  String get settingsPreview => '预览效果';

  @override
  String get settingsPrimaryButton => '主要按钮';

  @override
  String get settingsSecondaryButton => '次要按钮';

  @override
  String get settingsApply => '应用';

  @override
  String get colorBlue => '蓝色';

  @override
  String get colorPurple => '紫色';

  @override
  String get colorGreen => '绿色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorRed => '红色';

  @override
  String get colorCyan => '青色';

  @override
  String get colorPink => '粉色';

  @override
  String get colorYellow => '黄色';

  @override
  String get aiChatPageTitle => 'AI 助手';

  @override
  String get messageLabelYou => '你';

  @override
  String get messageLabelAi => 'AI';

  @override
  String get messageStatusSending => '发送中';

  @override
  String get messageStatusGenerating => '生成中';

  @override
  String get messageStatusFailed => '失败';

  @override
  String get messageStatusCancelled => '已取消';

  @override
  String get messageStatusError => '出错了';

  @override
  String get messageStatusThinking => '思考中';

  @override
  String tokenUsagePrompt(int count) {
    return '输入 $count';
  }

  @override
  String tokenUsageCompletion(int count) {
    return '输出 $count';
  }

  @override
  String tokenUsageTotal(int count) {
    return '总计 $count';
  }

  @override
  String sessionTokenUsage(
    int promptTokens,
    int completionTokens,
    int totalTokens,
  ) {
    return '会话：输入 $promptTokens · 输出 $completionTokens · 总计 $totalTokens';
  }

  @override
  String get messageActionRegenerate => '重新生成';

  @override
  String get tooltipCopyCode => '复制代码';

  @override
  String get tooltipExecuteCode => '执行代码';

  @override
  String get messageCopied => '已复制';

  @override
  String toolCallTitle(String name) {
    return '工具: $name';
  }

  @override
  String toolResultTitle(String name) {
    return '结果: $name';
  }

  @override
  String get toolCallCompleted => '已调用并完成';

  @override
  String get toolParamLabel => '参数';

  @override
  String get toolResultLabel => '结果';

  @override
  String get toolGroupTitle => '工具执行组';

  @override
  String toolGroupSummary(int count) {
    return '执行了 $count 个工具';
  }

  @override
  String toolGroupItemTitle(int index, String name) {
    return '工具 $index: $name';
  }

  @override
  String get toolNoParams => '无参数';

  @override
  String get aiWelcomeTitle => 'AI 数据库助手';

  @override
  String get aiWelcomeDescription =>
      '我可以帮你写 SQL、优化查询、分析表结构、检查安全问题，或者解答任何数据库相关的疑问。';

  @override
  String aiConnectedTo(String name) {
    return '已连接: $name';
  }

  @override
  String get aiExampleSectionTitle => '试试这样问我';

  @override
  String get aiQuickActionsSectionTitle => '快捷操作';

  @override
  String get aiTipQuickSend => 'Ctrl + Enter 快速发送';

  @override
  String get aiTipSlashCommands => '输入 / 查看所有命令';

  @override
  String get aiExampleQuestion1 => '优化这个查询的性能';

  @override
  String get aiExampleQuestion2 => '分析当前表结构';

  @override
  String get aiExampleQuestion3 => '检查这段 SQL 的安全性';

  @override
  String get errorApiKeyRequired => '请先填写 API Key';

  @override
  String get errorBaseUrlRequired => '请先填写 Base URL';

  @override
  String errorFetchModelsFailed(String error) {
    return '获取模型列表失败: $error';
  }

  @override
  String get tooltipRefreshModels => '刷新模型列表';

  @override
  String get labelCustomModelInput => '手动输入模型名称';

  @override
  String get tooltipAddModel => '添加模型';

  @override
  String get hintFetchOrInputModel => '点击刷新按钮获取或手动输入模型名称';

  @override
  String get hintFetchModels => '点击刷新按钮获取模型列表';

  @override
  String get errorSelectModelRequired => '请选择或输入一个模型';

  @override
  String errorSaveFailed(String error) {
    return '保存失败: $error';
  }

  @override
  String connErrorWithMessage(String error) {
    return 'Error: $error';
  }

  @override
  String get connSearchSnippetsHint => 'Search snippets...';

  @override
  String get connPreview => 'Preview';

  @override
  String get connInsert => 'Insert';

  @override
  String get connApply => 'Apply';

  @override
  String get connClearAll => 'Clear All';

  @override
  String connSaveConnectionFailed(String error) {
    return 'Failed to save connection: $error';
  }

  @override
  String connDeleteConnectionFailed(String error) {
    return 'Failed to delete connection: $error';
  }

  @override
  String get connCreateStatement => 'Create Statement';

  @override
  String get connCreateStatementCopied => 'Create statement copied';

  @override
  String get connCopyCreateStatement => 'Copy Create Statement';

  @override
  String get connDeleteDatabase => 'Delete Database';

  @override
  String get connCopiedToClipboard => 'Copied to clipboard';

  @override
  String get connCopy => 'Copy';

  @override
  String get connExportFeatureSetup =>
      'Export feature requires additional setup';

  @override
  String connExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String erDiagramExportSuccess(String path) {
    return '图表已保存到 $path';
  }

  @override
  String get erDiagramExportNoCanvas => '没有可导出的图。请先加载一个 schema。';

  @override
  String get erDiagramExportEncodeFailed => 'PNG 编码失败，请重试。';

  @override
  String connCopiedTableName(String tableName) {
    return 'Copied: $tableName';
  }

  @override
  String get connRetry => 'Retry';

  @override
  String get connReportIssue => 'Report Issue';

  @override
  String get connEnterTableName => 'Enter table name';

  @override
  String get connParameterName => 'Parameter name';

  @override
  String get connClear => 'Clear';

  @override
  String get connCharset => 'Charset';

  @override
  String get connComment => 'Comment';

  @override
  String get connName => 'Name';

  @override
  String get connDefault => 'Default';

  @override
  String get connIndexName => 'Index Name';

  @override
  String get connTruncate => 'Truncate';

  @override
  String get dlgProcedureUpdated =>
      'Stored procedure/function updated successfully';

  @override
  String get dlgProcedureCreated =>
      'Stored procedure/function created successfully';

  @override
  String dlgOperationFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get dlgType => 'Type';

  @override
  String get dlgProcedureType => 'Procedure (PROCEDURE)';

  @override
  String get dlgFunctionType => 'Function (FUNCTION)';

  @override
  String get dlgReturnType => 'Return Type';

  @override
  String get dlgEnterSqlHint => 'Enter SQL code...';

  @override
  String dlgExecutionFailed(String error) {
    return 'Execution failed: $error';
  }

  @override
  String get dlgExecute => 'Execute';

  @override
  String get dlgEnterValue => 'Enter value';

  @override
  String get dlgCopied => 'Copied';

  @override
  String get dlgNoHistory => 'No history yet';

  @override
  String get dlgConfirmDeleteTitle => 'Confirm Delete';

  @override
  String dlgConfirmDeleteHistoryMessage(String sql) {
    return 'Are you sure you want to delete this history record?\n\n$sql';
  }

  @override
  String get dlgTestSyntax => 'Test Syntax';

  @override
  String dlgSyntaxError(String message) {
    return 'Syntax error: $message';
  }

  @override
  String get dlgSyntaxLooksGood => 'Syntax looks good!';

  @override
  String get dlgEnterTriggerName => 'Enter trigger name';

  @override
  String dlgEnterVariableValue(String variable) {
    return 'Enter $variable';
  }

  @override
  String get molChooseFromGallery => 'Choose from Gallery';

  @override
  String get molTakePhoto => 'Take Photo';

  @override
  String molPickImageFailed(String error) {
    return 'Failed to pick image: $error';
  }

  @override
  String get molSend => 'Send';

  @override
  String svcExportSuccess(String result) {
    return 'File exported: $result';
  }

  @override
  String svcExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String scrInitFailed(String error) {
    return 'Initialization failed: $error';
  }

  @override
  String get smartImportTitle => 'AI 智能导入';

  @override
  String get smartImportSubtitle => '自动分析文件结构并导入数据库';

  @override
  String get smartImportClose => '关闭';

  @override
  String get smartImportTarget => '导入目标';

  @override
  String smartImportSelectedTable(String table) {
    return '已选择表: $table';
  }

  @override
  String get smartImportAutoInfer => '未选择表，将由 AI 自动推断';

  @override
  String get smartImportLoadTables => '加载表列表...';

  @override
  String get smartImportTableHint => '搜索或输入表名（留空由 AI 推断）';

  @override
  String get smartImportStepSelectFile => '选择文件';

  @override
  String get smartImportStepAnalyze => '分析文件';

  @override
  String get smartImportStepImport => '导入数据';

  @override
  String get smartImportStepComplete => '完成';

  @override
  String get smartImportSelectFileTitle => '选择要导入的文件';

  @override
  String get smartImportSelectFileHint => '点击选择 CSV 或 JSON 文件';

  @override
  String get smartImportReselectFile => '点击重新选择';

  @override
  String get smartImportSupportedFormats => '支持格式: CSV, TSV, JSON, JSON Lines';

  @override
  String get smartImportAnalyzing => '正在分析文件结构...';

  @override
  String get smartImportTableNotFound => '目标表不存在';

  @override
  String smartImportTableNotFoundMessage(String table) {
    return '表 \"$table\" 在当前数据库中不存在。';
  }

  @override
  String get smartImportCreateTableHint => '请先在 SQL 编辑器中执行以下建表语句，然后重新打开智能导入。';

  @override
  String get smartImportSuggestedSQL => '建议的建表语句';

  @override
  String get smartImportCopySQL => '复制语句';

  @override
  String get smartImportSQLCopied => '建表语句已复制到剪贴板';

  @override
  String get smartImportImporting => '正在导入数据...';

  @override
  String get smartImportImported => '已导入';

  @override
  String get smartImportTotalRecords => '总数据';

  @override
  String get smartImportFailedRecords => '失败';

  @override
  String get smartImportProgress => '进度';

  @override
  String get smartImportImportComplete => '导入完成';

  @override
  String get smartImportTargetTable => '目标表';

  @override
  String get smartImportSuccessRows => '成功导入';

  @override
  String get smartImportFailedRows => '失败跳过';

  @override
  String get smartImportTotalRows => '表当前总行数';

  @override
  String get smartImportImportFailed => '导入失败';

  @override
  String get smartImportFilePreview => '文件预览';

  @override
  String get smartImportSampleData => '样本数据（前3行）';

  @override
  String get smartImportLogs => '导入日志';

  @override
  String get smartImportClearLogs => '清空';

  @override
  String get smartImportReimport => '重新导入';

  @override
  String get smartImportStartAnalysis => '开始分析';

  @override
  String get smartImportStartImport => '开始导入';

  @override
  String get smartImportCancelImport => '取消导入';

  @override
  String get smartImportUserCancelled => '用户取消导入';

  @override
  String smartImportFileSelected(String name) {
    return '已选择文件：$name';
  }

  @override
  String smartImportAnalysisComplete(
    String format,
    String encoding,
    String fields,
  ) {
    return '文件分析完成。格式: $format, 编码: $encoding, 字段数: $fields';
  }

  @override
  String smartImportEstimatedRows(String rows) {
    return '估计总行数: ~$rows';
  }

  @override
  String smartImportUsingSelectedTable(String table) {
    return '使用已选择的表: $table';
  }

  @override
  String get smartImportCheckTableExists => '检查目标表是否存在...';

  @override
  String smartImportTableExists(String table, String count) {
    return '表 \"$table\" 已存在，当前有 $count 行数据';
  }

  @override
  String smartImportTableNotExists(String table) {
    return '表 \"$table\" 不存在。请先创建表。';
  }

  @override
  String get smartImportAiInferringTable => 'AI 正在推断表名';

  @override
  String smartImportAiSuggestedTable(String name) {
    return 'AI 建议表名: $name';
  }

  @override
  String get smartImportDoNotImport => '不导入';

  @override
  String smartImportTaskDescription(int count, String table) {
    return '导入 $count 到 $table';
  }

  @override
  String smartImportStartImporting(String table) {
    return '开始导入数据到表 \"$table\"...';
  }

  @override
  String smartImportImportResult(String imported, String failed) {
    return '导入完成！成功: $imported 行, 失败: $failed 行';
  }

  @override
  String get smartImportQueryRowCount => '正在查询表总行数...';

  @override
  String smartImportTableTotalRows(String table, String count) {
    return '表 \"$table\" 当前共有 $count 行数据';
  }

  @override
  String smartImportQueryCountFailed(String error) {
    return '查询数量失败: $error';
  }

  @override
  String smartImportImportError(String error) {
    return '导入失败: $error';
  }

  @override
  String get smartImportCopySuccess => 'SQL 语句已复制';

  @override
  String smartImportRows(String count) {
    return '$count 行';
  }

  @override
  String get smartImportAiModel => 'AI 模型';

  @override
  String get aiPanelFullscreen => '全屏模式';

  @override
  String get aiPanelExitFullscreen => '退出全屏';

  @override
  String get aiPanelOpenInNewQuery => '已在新查询中打开';

  @override
  String aiPanelInsertStatementsGenerated(int count, String tableName) {
    return 'AI 已生成 $count 条 INSERT 语句，准备插入到表 [$tableName]。';
  }

  @override
  String get aiPanelSqlPreviewTitle => 'SQL 预览（前3条）:';

  @override
  String aiPanelMoreStatements(int count) {
    return '... 还有 $count 条语句';
  }

  @override
  String aiAgentToolCallLimitReached(int count) {
    return 'AI助手已达到工具调用上限（$count次）。请简化您的问题，或分步进行操作。';
  }

  @override
  String get aiAgentMaxIterationsReached => 'Agent 达到最大迭代次数，未能完成对话。';

  @override
  String get aiAgentDuplicateQuery => '该查询已执行过，请基于已有结果直接回答，不要重复查询相同信息。';

  @override
  String aiAgentToolExecutionFailed(String error) {
    return '工具执行失败: $error';
  }

  @override
  String aiAgentUnknownTool(String name) {
    return '未知工具: $name';
  }

  @override
  String aiContextCurrentDatabase(String name) {
    return '当前数据库: $name';
  }

  @override
  String aiContextCurrentTable(String name) {
    return '当前表: $name';
  }

  @override
  String aiContextRecentQueries(String queries) {
    return '最近查询: $queries';
  }

  @override
  String aiContextGoalSummary(String summary) {
    return '当前会话目标摘要: $summary';
  }

  @override
  String get taskPanelTitle => '任务';

  @override
  String get taskPanelEmpty => '暂无任务';

  @override
  String get taskPanelEmptyDesc => '导入或导出操作将显示在这里';

  @override
  String get taskPanelClearCompleted => '清除已完成';

  @override
  String get taskPanelStatusPending => '等待中';

  @override
  String get taskPanelStatusRunning => '执行中';

  @override
  String get taskPanelStatusPaused => '已暂停';

  @override
  String get taskPanelStatusCompleted => '已完成';

  @override
  String get taskPanelStatusFailed => '失败';

  @override
  String get taskPanelStatusCancelled => '已取消';

  @override
  String get taskTypeImport => '导入';

  @override
  String get taskTypeExport => '导出';

  @override
  String get taskTypeQuery => '查询';

  @override
  String get taskActionCancel => '取消';

  @override
  String get taskActionRetry => '重试';

  @override
  String get taskActionRemove => '删除';

  @override
  String get taskActionOpenFolder => '打开目录';

  @override
  String get taskCreateExportTitle => '创建导出任务';

  @override
  String get taskCreateExportFormat => '导出格式';

  @override
  String get taskCreateExportPath => '输出路径';

  @override
  String get taskCreateExportPathPlaceholder => '点击右侧按钮选择保存位置';

  @override
  String get taskCreateExportPathSelect => '选择保存位置';

  @override
  String get taskCreateExportStart => '创建任务';

  @override
  String get taskValidationPathRequired => '请选择输出路径';

  @override
  String get taskValidationPathNotWritable => '目录不可写，请选择其他位置';

  @override
  String get taskValidationPathExists => '文件已存在，将被覆盖';

  @override
  String taskStatusBarTasks(int count) {
    return '$count 个任务';
  }

  @override
  String taskStatusBarRunning(int count) {
    return '$count 个运行中';
  }

  @override
  String get taskLogInfo => '信息';

  @override
  String get taskLogWarning => '警告';

  @override
  String get taskLogError => '错误';

  @override
  String get taskLogSuccess => '成功';

  @override
  String get taskDetailTitle => '任务详情';

  @override
  String get taskDetailBasicInfo => '基本信息';

  @override
  String get taskDetailStatistics => '执行统计';

  @override
  String get taskDetailError => '错误信息';

  @override
  String get taskDetailOutputFile => '输出文件';

  @override
  String get taskDetailLogs => '执行日志';

  @override
  String get taskDetailCopied => '路径已复制到剪贴板';

  @override
  String get taskPhaseAnalyzing => '正在分析...';

  @override
  String get taskPhaseQuerying => '正在查询数据...';

  @override
  String get taskPhaseFormatting => '正在格式化数据...';

  @override
  String get taskPhaseWriting => '正在写入文件...';

  @override
  String get taskPhaseCompleted => '已完成';

  @override
  String get aiExportButtonCreate => '创建导出任务';

  @override
  String get aiExportButtonAnalyzing => '分析中...';

  @override
  String get aiMessageExportAction => '导出此数据';

  @override
  String get smartImportCreateTask => '在后台创建导入任务';

  @override
  String get schemaDiffTitle => 'Schema 对比与同步';

  @override
  String get schemaDiffMenuItem => 'Schema 对比与同步';

  @override
  String get schemaDiffSource => '源数据库';

  @override
  String get schemaDiffTarget => '目标数据库';

  @override
  String get schemaDiffCompareButton => '对比';

  @override
  String get schemaDiffSelectDatabases => '请选择源数据库和目标数据库进行对比';

  @override
  String get schemaDiffTabOverview => '概览';

  @override
  String get schemaDiffTabDetails => '详情';

  @override
  String get schemaDiffTabSync => '同步';

  @override
  String get sidebarColumns => '列';

  @override
  String get sidebarIndexes => '索引';

  @override
  String get sidebarInsertIntoEditor => '插入到编辑器';

  @override
  String get sidebarForeignKeys => '外键';

  @override
  String get sidebarCopyIndexName => '复制索引名';

  @override
  String get sidebarCopyForeignKeyName => '复制外键名';

  @override
  String get sidebarCopyName => '复制名称';

  @override
  String get sidebarReadOnlyConnection => '只读连接';

  @override
  String get sidebarCopyColumnName => '复制列名';

  @override
  String get sidebarCopyColumnType => '复制列类型';

  @override
  String get sidebarCopyAllColumnNames => '复制全部列名';

  @override
  String get sidebarOpenEditorFirst => '请先打开查询标签';

  @override
  String get sidebarEvents => '事件';

  @override
  String get sidebarProgrammableObjects => '可编程对象';

  @override
  String get selectDatabaseHint => '双击数据库查看其对象';

  @override
  String get workspaceEmptyTitle => '没有打开的查询';

  @override
  String get workspaceEmptyHint => '创建新查询标签页以开始工作';

  @override
  String get noSearchResults => '无匹配结果';

  @override
  String get page => '页';

  @override
  String get settingsSubscriptionSettings => '订阅';

  @override
  String get settingsFreePlan => '免费版';

  @override
  String get settingsFreePlanDesc => '您当前使用的是免费版';

  @override
  String get settingsProActivated => 'Pro 已激活';

  @override
  String get settingsProActivatedDesc => '所有 Pro 功能已解锁';

  @override
  String get settingsUpgradeToPro => '升级到 Pro';

  @override
  String get settingsRestorePurchases => '恢复购买';

  @override
  String get purchaseDialogTitle => '升级到 Pro';

  @override
  String get purchaseDialogDesc => '订阅 Pro 解锁所有高级功能';

  @override
  String get purchaseDialogNoProducts => '暂无可用产品';

  @override
  String freeAiQuotaExceeded(int count) {
    return '本月 $count 次免费 AI 消息额度已用完。升级到 Pro 即可无限使用 AI。';
  }

  @override
  String freeConnectionLimitReached(int count) {
    return 'Free 计划最多保存 $count 个连接。升级到 Pro 以解锁无限连接。';
  }

  @override
  String freeTabLimitReached(int count) {
    return 'Free 计划最多同时打开 $count 个查询标签页。升级到 Pro 以解锁无限标签页。';
  }

  @override
  String get schemaDiffSyncProFeature =>
      'Schema Diff 同步是 Pro 功能。开始免费试用或升级到 Pro 以执行同步。';

  @override
  String get tableMetadataComment => '注释';

  @override
  String get tableMetadataRowCount => '行数';

  @override
  String get tableMetadataDataSize => '大小';

  @override
  String get tableMetadataEngine => '引擎';

  @override
  String get tableMetadataUpdateTime => '更新时间';

  @override
  String resultsTruncatedMessage(Object count) {
    return '结果已限制为前 $count 行，可能还有更多数据';
  }

  @override
  String get settingsQueryLimit => '查询限制';

  @override
  String get settingsAutoLimitEnabled => '自动 LIMIT';

  @override
  String get settingsAutoLimitValue => '限制行数';

  @override
  String get sidebarFavorites => 'Favorites';

  @override
  String get recentTables => '最近';

  @override
  String get dataSyncTitle => '数据同步';

  @override
  String get dataSyncCancel => '取消';

  @override
  String get dataSyncClose => '关闭';

  @override
  String get dataSyncRestart => '重新同步';

  @override
  String get dataSyncStart => '开始同步';

  @override
  String get dataSyncExecutionLocation => 'Execution Location';

  @override
  String get dataSyncExecutionLocal => 'Local (immediate)';

  @override
  String get dataSyncExecutionLocalDesc =>
      'Run directly from this client. Best for one-off single-table syncs.';

  @override
  String get dataSyncExecutionServer => 'Server (background)';

  @override
  String get dataSyncExecutionServerDesc =>
      'Submit to the Server for background execution with scheduling. Best for large tables and recurring syncs.';

  @override
  String get dataSyncServerTaskName => 'Task Name';

  @override
  String get dataSyncServerTaskNameHint => 'my-daily-sync';

  @override
  String get dataSyncScheduleImmediate => 'Run once now';

  @override
  String get dataSyncScheduleCron => 'Recurring (cron)';

  @override
  String get dataSyncCronExpr => 'Cron Expression';

  @override
  String get dataSyncCronExprHelp =>
      '5-field: minute hour day-of-month month day-of-week (UTC).';

  @override
  String get dataSyncCronPresetDaily3am => 'Daily 03:00';

  @override
  String get dataSyncCronPresetHourly => 'Hourly';

  @override
  String get dataSyncCronPresetWeekly => 'Weekly (Mon 03:00)';

  @override
  String dataSyncServerTaskCreated(String taskId) {
    return 'Server task created: $taskId';
  }

  @override
  String get dataSyncServerEntitlementGated =>
      'Server license is gated. Activate or renew the Server license to use background execution.';

  @override
  String get dataSyncJoinTables => 'Join Tables (LEFT JOIN)';

  @override
  String get dataSyncAddJoinTable => 'Add join table';

  @override
  String dataSyncJoinTableTitle(int index, String alias) {
    return 'Join table #$index ($alias)';
  }

  @override
  String get dataSyncJoinTableRemove => 'Remove this join table';

  @override
  String get dataSyncJoinOn => 'ON condition';

  @override
  String get dataSyncJoinSelectColumns => 'Columns to include';

  @override
  String get dataSyncViewTasks => 'View tasks';

  @override
  String get dataSyncMenuLabel => 'Data Sync Tasks';

  @override
  String get dataSyncTaskListTitle => 'Data Sync Tasks';

  @override
  String get dataSyncTaskListEmpty =>
      'No sync tasks yet. Create one from a table\'s right-click menu → Data Sync → Server (background).';

  @override
  String get dataSyncTaskRun => 'Run now';

  @override
  String get dataSyncTaskCancel => 'Cancel';

  @override
  String get dataSyncTaskCancelRequested =>
      'Cancel requested. The run will stop after the current batch completes.';

  @override
  String get dataSyncTaskHistory => 'History';

  @override
  String get dataSyncTaskDelete => 'Delete';

  @override
  String get dataSyncTaskDeleteConfirm =>
      'Delete this task? This cannot be undone.';

  @override
  String get dataSyncTaskPaused => 'paused';

  @override
  String get dataSyncTaskNeverRun => 'Never run';

  @override
  String dataSyncRunProgress(int percent) {
    return '$percent%';
  }

  @override
  String dataSyncRunRows(int processed, int total) {
    return '$processed / $total rows';
  }

  @override
  String dataSyncRunRowsOnly(int processed) {
    return '$processed rows';
  }

  @override
  String dataSyncHistoryTitle(String name) {
    return 'Run history — $name';
  }

  @override
  String dataSyncHistoryDuration(int ms) {
    return '$ms ms';
  }

  @override
  String get dataSyncHistoryEmpty => 'No runs yet.';

  @override
  String get dataSyncStatusRunning => 'Running';

  @override
  String get dataSyncStatusSucceeded => 'Succeeded';

  @override
  String get dataSyncStatusFailed => '同步失败';

  @override
  String get dataSyncStatusCanceled => 'Canceled';

  @override
  String get dataSyncRefresh => 'Refresh';

  @override
  String get dataSyncNotConnected => 'Not connected to a DbMaster server.';

  @override
  String get dataSyncSourceConfig => '源配置';

  @override
  String get dataSyncSourceConnection => '源连接';

  @override
  String get dataSyncSourceDatabase => '源数据库';

  @override
  String get dataSyncSourceTable => '源表';

  @override
  String get dataSyncTargetConfig => '目标配置';

  @override
  String get dataSyncTargetConnection => '目标连接';

  @override
  String get dataSyncTargetDatabase => '目标数据库';

  @override
  String get dataSyncTargetTable => '目标表';

  @override
  String get dataSyncSegmentConfig => '分段配置';

  @override
  String get dataSyncSegmentStrategy => '分段策略';

  @override
  String get dataSyncSegmentTypeNumeric => '数值分段';

  @override
  String get dataSyncSegmentTypeTime => '时间分段';

  @override
  String get dataSyncSegmentField => '分段字段';

  @override
  String get dataSyncTimeUnit => '时间单位';

  @override
  String get dataSyncTimeUnitMinute => '分钟';

  @override
  String get dataSyncTimeUnitHour => '小时';

  @override
  String get dataSyncTimeUnitDay => '天';

  @override
  String get dataSyncIntervalValue => '间隔值';

  @override
  String get dataSyncSegmentSize => '每段大小';

  @override
  String get dataSyncAdvancedOptions => '高级选项';

  @override
  String get dataSyncPageSize => '页大小';

  @override
  String get dataSyncTargetStrategy => '目标策略';

  @override
  String get dataSyncStrategyTruncate => '清空后同步';

  @override
  String get dataSyncStrategyAppend => '追加（忽略冲突）';

  @override
  String get dataSyncStrategyReplace => '覆盖（REPLACE）';

  @override
  String get dataSyncStrategyUpsert => '冲突时更新';

  @override
  String get dataSyncServerTimeOnlyHint => 'Server 后台模式仅支持按时间窗口分批；数值分段仅本地模式可用。';

  @override
  String get dataSyncReplaceDowngradeWarning =>
      'Server 后台模式不支持 REPLACE INTO：提交后将降级为「清空后同步」（truncate）——目标表会先被清空，再全量写入。';

  @override
  String get dataSyncCancelling => '正在取消，等待当前批次完成…';

  @override
  String get dataSyncSegmentIntervalMs => '段间间隔(ms)';

  @override
  String get dataSyncPageIntervalMs => '页间间隔(ms)';

  @override
  String get dataSyncPleaseCompleteConfig => '请完善所有配置项';

  @override
  String get dataSyncConnectionNotFound => '连接未找到';

  @override
  String dataSyncFailed(String error) {
    return '同步失败: $error';
  }

  @override
  String get dataSyncCancelledByUser => '用户取消';

  @override
  String get dataSyncCompleted => '同步完成';

  @override
  String get dataSyncStatusSuccess => '同步成功';

  @override
  String get dataSyncStatusCancelled => '同步已取消';

  @override
  String get dataSyncResultSourceTable => '源表';

  @override
  String get dataSyncResultTargetTable => '目标表';

  @override
  String get dataSyncResultSyncedRows => '已同步行数';

  @override
  String get dataSyncResultFailedRows => '失败行数';

  @override
  String get dataSyncResultDuration => '总耗时';

  @override
  String dataSyncPleaseSelect(String label) {
    return '请选择$label';
  }

  @override
  String get dataSyncProgressDetectingSchema => '正在探测表结构...';

  @override
  String get dataSyncProgressCountingRows => '正在统计总行数...';

  @override
  String get dataSyncProgressCalculatingSegments => '正在计算分段...';

  @override
  String get dataSyncProgressEmptyTable => '源表无数据，同步完成';

  @override
  String get dataSyncProgressTruncatingTarget => '正在清空目标表...';

  @override
  String get dataSyncProgressCancelled => '同步已取消';

  @override
  String dataSyncProgressSyncingSegment(int current, int total) {
    return '正在同步第 $current/$total 段...';
  }

  @override
  String dataSyncProgressPageStatus(
    int current,
    int total,
    int synced,
    int totalRows,
  ) {
    return '第 $current/$total 段，已同步 $synced / $totalRows 行';
  }

  @override
  String dataSyncProgressCompleted(int synced, int failed, int skipped) {
    return '同步完成！成功 $synced 行，失败 $failed 行，跳过 $skipped 行';
  }

  @override
  String dataSyncErrorDateTimeParse(String field, String min, String max) {
    return '字段 `$field` 的值无法解析为日期时间: min=$min, max=$max';
  }

  @override
  String dataSyncErrorNumericParse(String field, String min, String max) {
    return '字段 `$field` 的值无法解析为数值: min=$min, max=$max';
  }

  @override
  String get statsToggle => '统计';

  @override
  String get statsChooseColumns => '选择显示列';

  @override
  String get statsApproximateTooltip => '带 ~ 前缀的为近似值';

  @override
  String statsApproximateValue(String value) {
    return '近似值（~$value）';
  }

  @override
  String get statsExactValue => '精确值';

  @override
  String get statsForeignKeys => 'Foreign Keys';

  @override
  String get statsNoForeignKeys => 'No foreign keys';

  @override
  String dataSyncProgressSynced(int count) {
    return '已同步 $count 行';
  }

  @override
  String dataSyncProgressTotal(int count) {
    return '$count 行';
  }

  @override
  String dataSyncProgressFailed(int count) {
    return '失败 $count 行';
  }

  @override
  String get unsavedChangesTitle => '未保存的更改';

  @override
  String get unsavedChangesMessage => '此标签页有未保存的更改，关闭后不保存？';

  @override
  String get discardChanges => '不保存';

  @override
  String tabCloseConfirmMessage(String title) {
    return '是否保存对「$title」的更改？';
  }

  @override
  String get bulkCloseDialogTitle => '未保存的更改';

  @override
  String get bulkCloseDialogMessage => '以下标签页包含未保存的更改：';

  @override
  String get bulkCloseSaveAll => '全部保存';

  @override
  String get bulkCloseDiscardAll => '全部不保存';

  @override
  String get bulkCloseReviewTitle => '检查标签页';

  @override
  String get bulkCloseDecisionSave => '保存';

  @override
  String get bulkCloseDecisionDiscard => '不保存';

  @override
  String get bulkCloseDecisionPending => '保持打开';

  @override
  String bulkCloseSaveFailed(Object title) {
    return '保存 $title 失败。';
  }

  @override
  String get aiPanelOverlayClickMask => 'Click mask';

  @override
  String get aiPanelOverlayCloseOverlay => 'Close overlay';

  @override
  String get aiPanelOverlayDragEdges => 'Drag edges / corners';

  @override
  String get aiPanelOverlayDragToolbar => 'Drag toolbar';

  @override
  String get aiPanelOverlayMoveOverlay => 'Move overlay';

  @override
  String get aiPanelOverlayResizeOverlay => 'Resize overlay';

  @override
  String get aiPanelOverlaySwitchToSidebar => 'Switch to sidebar mode';

  @override
  String get aiPanelOverlayToggleMode => 'Toggle overlay/sidebar mode';

  @override
  String get aiPanelOverlay_aiPanelShortcuts => 'AI panel shortcuts';

  @override
  String get aiSettingsDisclosureTitle => 'About AI Features';

  @override
  String get aiSettingsDisclosureBody =>
      'AI features require your own API Key. All AI requests are sent directly from your device to the AI service provider you choose. DbMaster does not collect your data or relay requests through our servers.';

  @override
  String get exportConnectionsTitle => '导出全部连接';

  @override
  String get importConnectionsTitle => '导入连接';

  @override
  String get exportConnectionsCount => '待导出连接数';

  @override
  String get exportPasswordHint => '备份密码';

  @override
  String get confirmExportPasswordHint => '确认备份密码';

  @override
  String get passwordsDoNotMatch => '密码不一致';

  @override
  String get importPasswordHint => '备份密码';

  @override
  String get selectExportFile => '保存到文件';

  @override
  String get selectImportFile => '选择备份文件';

  @override
  String selectImportFileFailed(String error) {
    return '选择文件失败: $error';
  }

  @override
  String get conflictStrategyLabel => '若连接名称已存在';

  @override
  String get conflictStrategySkip => '跳过';

  @override
  String get conflictStrategyRename => '重命名';

  @override
  String get conflictStrategyOverwrite => '覆盖';

  @override
  String get exportSuccess => '连接导出成功';

  @override
  String get importSuccess => '连接导入成功';

  @override
  String get invalidPassword => '密码错误';

  @override
  String get invalidFile => '文件无效或已损坏';

  @override
  String get noConnectionsToExport => '没有可导出的连接';

  @override
  String get exportThisConnection => '导出此连接';

  @override
  String get commandCategoryTools => '工具';

  @override
  String get passwordRequiredTitle => '需要密码';

  @override
  String passwordRequiredMessage(String serverName) {
    return '请输入 $serverName 的连接密码';
  }

  @override
  String get connectionConnectNoPassword => '不使用密码连接';

  @override
  String get embeddedRequiresRemoteServer => '需要远程 Server';

  @override
  String get serverSessionExpiredTitle => '会话已过期';

  @override
  String get serverSessionExpiredMessage => '与服务器的会话已过期或已被吊销，请重新登录后继续。';

  @override
  String get serverSessionRelogin => '重新登录';

  @override
  String get serverReconnectLastSession => '重连上次的会话';

  @override
  String get serverReconnectFailed => '上次会话已失效，请重新登录。';

  @override
  String sidebarEmptyTableFailed(String error) {
    return 'Failed to empty table: $error';
  }

  @override
  String sidebarDropViewFailed(String error) {
    return '删除视图失败：$error';
  }

  @override
  String sidebarDropTriggerFailed(String error) {
    return 'Failed to drop trigger: $error';
  }

  @override
  String sidebarToggleWalFailed(String error) {
    return 'Failed to toggle WAL mode: $error';
  }

  @override
  String sidebarOptimizeDbFailed(String error) {
    return 'Failed to optimize database: $error';
  }

  @override
  String sidebarSaveAsSuccess(String path) {
    return '数据库已保存到 $path';
  }

  @override
  String sidebarSaveAsFailed(String error) {
    return '保存数据库失败：$error';
  }

  @override
  String sidebarSaveAsExists(String path) {
    return '文件已存在：$path';
  }

  @override
  String sidebarRebuildIndexFailed(String error) {
    return 'Failed to rebuild index: $error';
  }

  @override
  String get sidebarNewIndex => 'New Index';

  @override
  String get sidebarInsertDocument => 'Insert Document';

  @override
  String sidebarCollectionDropped(String name) {
    return 'Collection $name dropped';
  }

  @override
  String sidebarDropCollectionConfirm(String name) {
    return 'Are you sure you want to drop collection \"$name\"?\n\nThis action cannot be undone.';
  }

  @override
  String sidebarDropIndexConfirm(String indexName, String collectionName) {
    return 'Are you sure you want to drop index \"$indexName\" from \"$collectionName\"?\n\nThis action cannot be undone.';
  }

  @override
  String sidebarDropTableConfirm(String tableName) {
    return 'Are you sure you want to drop table \"$tableName\"?\n\nThis action cannot be undone.';
  }

  @override
  String sidebarDropViewConfirm(String viewName) {
    return '确定要删除视图 \"$viewName\" 吗？\n\n此操作无法撤销。';
  }

  @override
  String sidebarEmptyTableConfirm(String tableName) {
    return 'Are you sure you want to empty all data from table \"$tableName\"?\n\nThis action cannot be undone.';
  }

  @override
  String get sidebarCreateNewIndex => 'Create New Index';

  @override
  String get sidebarCreateNewView => 'Create New View';

  @override
  String get sidebarCreateNewMaterializedView => 'Create New Materialized View';

  @override
  String get sidebarCreateNewTrigger => 'Create New Trigger';

  @override
  String addColumnFailed(String error) {
    return 'Failed to add column: $error';
  }

  @override
  String createIndexFailed(String error) {
    return 'Failed to create index: $error';
  }

  @override
  String dropTableFailed(String error) {
    return 'Failed to drop table: $error';
  }

  @override
  String get insertDocumentFailed => 'Failed to insert document';

  @override
  String get sidebarEmptyTable => 'Empty Table';

  @override
  String sidebarEmptyTableSuccess(String tableName) {
    return 'Table \"$tableName\" emptied successfully';
  }

  @override
  String get sidebarDropSuccess => 'Dropped successfully';

  @override
  String sidebarCreateIndexTitle(String tableName) {
    return 'Create Index on \"$tableName\"';
  }

  @override
  String sidebarIndexCreated(String indexName, String tableName) {
    return 'Index \"$indexName\" created on \"$tableName\"';
  }

  @override
  String sidebarIndexDropped(String indexName) {
    return 'Index \"$indexName\" dropped successfully';
  }

  @override
  String sidebarIndexRebuilt(String indexName) {
    return 'Index \"$indexName\" rebuilt successfully';
  }

  @override
  String get sidebarDropColumnTitle => 'Drop Column';

  @override
  String get sidebarViewStructure => 'View Structure';

  @override
  String get sidebarBrowseData => '浏览数据';

  @override
  String get sidebarRefresh => 'Refresh';

  @override
  String get sidebarImportSQL => 'Import SQL';

  @override
  String get sidebarNewTable => 'New Table';

  @override
  String get sidebarIndexName => 'Index Name';

  @override
  String get sidebarCreate => 'Create';

  @override
  String get sidebarDrop => 'Drop';

  @override
  String get sidebarIndexFieldsRequired => 'Index name and fields are required';

  @override
  String get sidebarViewStats => 'View Stats';

  @override
  String get sidebarDropCollectionTitle => 'Drop Collection';

  @override
  String get sidebarNewKey => 'New Key';

  @override
  String get sidebarFlushDB => 'Flush DB';

  @override
  String sidebarFlushConfirm(String dbName) {
    return 'Are you sure you want to flush $dbName? This will delete ALL keys in this database.';
  }

  @override
  String sidebarFlushFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String sidebarKeyCreated(String key) {
    return 'Key \"$key\" created successfully';
  }

  @override
  String sidebarKeyFailed(String error) {
    return 'Failed to create key: $error';
  }

  @override
  String get sidebarDropCollectionFailed => 'Failed to drop collection';

  @override
  String get sidebarLoadDbInfoFailed => 'Failed to load database info';

  @override
  String renameSuccess(String tableName, String newName) {
    return 'Table \"$tableName\" renamed to \"$newName\"';
  }

  @override
  String get dropIndexTitle => 'Drop Index?';

  @override
  String get sidebarIndexSize => 'Index Size';

  @override
  String get connectionSchema => 'Schema';

  @override
  String get connectionDbFile => 'Database File';

  @override
  String get connectionSelectDbFile => 'Select SQLite Database File';

  @override
  String get connectionDbFileRequired => 'Please select a database file';

  @override
  String get connectionPrivateKey => 'Private Key';

  @override
  String get connectionSelectSshKey => 'Select SSH Private Key';

  @override
  String get connectionPassphrase => 'Passphrase';

  @override
  String get connectionKeyPassphrase => 'Key Passphrase (optional)';

  @override
  String get connectionAuthSection => 'Authentication';

  @override
  String get connectionSshSubtitle => 'Connect via SSH jump host';

  @override
  String get connectionSshConfig => 'SSH Configuration';

  @override
  String get connectionAutoCharset => 'Auto (utf8mb4)';

  @override
  String get connectionAutoSystem => 'Auto (System)';

  @override
  String get connectionPasteKeyHint => 'Paste key content or use file picker →';

  @override
  String get connectionMongoMode => '连接模式';

  @override
  String get connectionMongoModeDirect => '直连（单机）';

  @override
  String get connectionMongoModeReplicaSet => '副本集';

  @override
  String get connectionMongoSeedHosts => '种子节点列表';

  @override
  String get connectionMongoSeedHostsHint =>
      '列出所有副本集成员节点（host:port，每行一个）。驱动自动发现 primary，连接以此列表为准。';

  @override
  String get connectionMongoSeedHostsRequired => '至少需要一个种子节点（host:port）';

  @override
  String get connectionMongoReplicaSetName => '副本集名称';

  @override
  String get connectionMongoReplicaSetNameRequired => '副本集名称不能为空';

  @override
  String get connectionMongoModeAdvanced => '高级（连接串）';

  @override
  String get connectionMongoModeSharded => '分片（mongos）';

  @override
  String get connectionMongoMongosHosts => 'mongos 路由节点';

  @override
  String get connectionMongoMongosHostsHint =>
      '列出所有 mongos 路由节点（host:port，每行一个）。驱动经 mongos 连接，分片透明。';

  @override
  String get connectionMongoMongosHostsRequired =>
      '至少需要一个 mongos 路由节点（host:port）';

  @override
  String get connectionMongoInvalidHostPort => '条目格式无效（应为 host 或 host:port）';

  @override
  String get connectionMongoConnectionString => '连接串';

  @override
  String get connectionMongoConnectionStringHint =>
      '粘贴完整连接串（mongodb:// 或 mongodb+srv://，含 Atlas）。凭据自动剥离，密码单独加密存储。';

  @override
  String get connectionMongoConnectionStringRequired => '请粘贴连接串';

  @override
  String get connectionMongoConnectionStringInvalid =>
      '无效连接串（须以 mongodb:// 或 mongodb+srv:// 开头）';

  @override
  String get connInvalidPort => 'Invalid port';

  @override
  String get connUsernameRequired => '用户名为必填项';

  @override
  String get connNameRequired => '连接名称为必填项';

  @override
  String get connHostRequired => '主机为必填项';

  @override
  String get connPortRequired => '端口为必填项';

  @override
  String get connRequired => 'Required';

  @override
  String get snippetCategoryAll => 'All';

  @override
  String get snippetCategoryDML => 'DML';

  @override
  String get snippetCategoryDDL => 'DDL';

  @override
  String get snippetCategoryQuery => 'Query';

  @override
  String get snippetCategoryUtility => 'Utility';

  @override
  String get snippetCategoryCustom => 'Custom';

  @override
  String get sidebarManageGroups => 'Manage Groups';

  @override
  String get sidebarNewGroup => 'New Group';

  @override
  String get sidebarGroupName => 'Group Name';

  @override
  String get sidebarGroupHint => 'e.g., Production';

  @override
  String get sidebarFilterHint => 'Filter...';

  @override
  String sidebarTableExported(String tableName) {
    return 'Table \"$tableName\" exported to clipboard';
  }

  @override
  String sidebarExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String sidebarConnectFailed(String serverName) {
    return 'Failed to connect to $serverName';
  }

  @override
  String sidebarSuperTableDeleted(String name) {
    return 'SuperTable \"$name\" deleted';
  }

  @override
  String sidebarDeleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String sidebarColumnAdded(String column, String table) {
    return 'Column \"$column\" added to \"$table\"';
  }

  @override
  String get sidebarColumnName => 'Column Name';

  @override
  String get sidebarDataType => 'Data Type';

  @override
  String get sidebarDataTypeHint => 'TEXT, INTEGER, REAL, BLOB, etc.';

  @override
  String get sidebarDefaultValueOptional => 'Default Value (optional)';

  @override
  String get sidebarRedisType => 'Type';

  @override
  String get sidebarRedisField => 'Field';

  @override
  String get sidebarRedisFieldValue => 'Field Value';

  @override
  String get sidebarRedisValue => 'Value';

  @override
  String get sidebarRedisExpire => 'Expire After';

  @override
  String get sidebarRedisFieldsRequired => 'Please fill in all required fields';

  @override
  String get sidebarCommandPalette => 'Command Palette';

  @override
  String get sidebarCaseSensitive => 'Case Sensitive';

  @override
  String get sidebarCollapse => 'Collapse';

  @override
  String get sidebarIndexColumns => 'Columns';

  @override
  String get sidebarIndexColumnsHint => 'column1, column2, ...';

  @override
  String get sidebarIndexFieldsHint => 'e.g. name, email, age';

  @override
  String get sidebarColumnNameHint => 'column_name';

  @override
  String get sidebarTagNameHint => 'tag_name';

  @override
  String get sidebarInsertDocHint => 'field: value';

  @override
  String get sidebarJsonHint => 'JSON...';

  @override
  String get sidebarSuperTableName => 'SuperTable Name';

  @override
  String get sidebarCommentOptional => 'Comment (Optional)';

  @override
  String get connectionNewChat => 'New Chat';

  @override
  String connectionTestFailedShort(String error) {
    return 'Test failed: $error';
  }

  @override
  String sidebarFailedInsert(String error) {
    return 'Invalid JSON or insert failed: $error';
  }

  @override
  String sidebarCollectionDroppedSnack(String name) {
    return 'Collection $name dropped';
  }

  @override
  String sidebarFileCreateFailed(String error) {
    return 'Failed to create file: $error';
  }

  @override
  String sidebarSaveFailed(String error) {
    return 'Failed to save: $error';
  }

  @override
  String get sidebarSqlCopied => 'SQL copied to clipboard';

  @override
  String get sidebarLogsExported => 'Logs exported to clipboard as CSV';

  @override
  String get toolbarBeginTransaction => 'BEGIN TRANSACTION';

  @override
  String get toolbarCommit => 'COMMIT';

  @override
  String get toolbarRollback => 'ROLLBACK';

  @override
  String get toolbarQueryPlan => 'Query Plan';

  @override
  String get toolbarPiiMasking => 'PII Masking Settings';

  @override
  String get toolbarCloseAll => 'Close all results';

  @override
  String get dlgSearchHint => 'Search SQL or connection...';

  @override
  String get dlgOpenInNewTab => 'Open in new tab';

  @override
  String get dlgCopySQL => 'Copy SQL';

  @override
  String get dlgChooseDatabase => 'Select database';

  @override
  String get dlgChooseTableOrAI =>
      'Select existing table or leave blank for AI inference';

  @override
  String get dlgRemoveFile => 'Remove file';

  @override
  String get dlgSkipImport => 'Skip import';

  @override
  String get dlgDeleteParam => 'Delete parameter';

  @override
  String get dbDialogDbName => 'Database Name';

  @override
  String get dbDialogDbNameHint => 'Enter database name';

  @override
  String get dbDialogCharsetOptional => 'Character Set (optional)';

  @override
  String get dbDialogCollationOptional => 'Collation (optional)';

  @override
  String get dbDialogIndexName => 'Index Name';

  @override
  String get dbDialogSchema => 'Schema';

  @override
  String get dbDialogTablespace => 'Tablespace';

  @override
  String get filterEnable => 'Enable';

  @override
  String get filterFrom => 'From';

  @override
  String get filterTo => 'To';

  @override
  String get filterClear => 'Clear';

  @override
  String get errorRetry => 'Retry';

  @override
  String get errorReport => 'Report Issue';

  @override
  String get sqliteOpenExisting => 'Open existing database';

  @override
  String get sqliteCreateNew => 'Create new database';

  @override
  String get focusModeEnabled => 'Focus Mode';

  @override
  String get focusModeDisabled => 'Exit Focus Mode';

  @override
  String get sidebarSearchScopeAll => 'All';

  @override
  String get sidebarSearchScopeConnection => 'Connection';

  @override
  String get sidebarSearchScopeDatabase => 'Database';

  @override
  String get sidebarSearchScopeTable => 'Table';

  @override
  String get sidebarSearchScopeView => 'View';

  @override
  String get sidebarSearchScopeProcedure => 'Procedure';

  @override
  String get sidebarSearchScopeTrigger => 'Trigger';

  @override
  String get sidebarSearchScopeEvent => 'Event';

  @override
  String sidebarSearchScopeTooltip(String scope) {
    return 'Search scope: $scope';
  }

  @override
  String get sidebarDropEvent => '删除事件';

  @override
  String sidebarDropEventConfirm(String name) {
    return '确定要删除事件 \"$name\" 吗？\n\n此操作不可撤销。';
  }

  @override
  String sidebarEventOperationFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String get sidebarEventNoDefinition => '无定义';

  @override
  String get sidebarDropSynonym => '删除同义词';

  @override
  String sidebarDropSynonymConfirm(String name) {
    return '确定要删除同义词 \"$name\" 吗？\n\n此操作不可撤销。';
  }

  @override
  String sidebarSynonymOperationFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String get sidebarEnableEvent => '启用事件';

  @override
  String get sidebarDisableEvent => '禁用事件';

  @override
  String get sidebarEventProperties => '属性';

  @override
  String get sidebarSynonyms => '同义词';

  @override
  String get sidebarBrowseSynonym => '浏览同义词';

  @override
  String get sidebarScriptSynonymAsSelect => '生成 SELECT 脚本';

  @override
  String sidebarShowRemaining(int remaining) {
    return 'Show remaining $remaining';
  }

  @override
  String sidebarLoadMore(int batchSize, int remaining) {
    return 'Load $batchSize more ($remaining remaining)';
  }

  @override
  String get schemaDiffDatabaseTypeMismatch =>
      'Source and target database types do not match';

  @override
  String schemaDiffErrorWithMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get schemaDiffRetryButton => 'Retry';

  @override
  String get schemaDiffCapturingTitle => 'Capturing Schema';

  @override
  String get schemaDiffSourceLabel => 'Source';

  @override
  String get schemaDiffTargetLabel => 'Target';

  @override
  String get schemaDiffCancelling => 'Cancelling...';

  @override
  String get schemaDiffCancelButton => 'Cancel';

  @override
  String get schemaDiffResultsPreviewLoading => 'Loading preview...';

  @override
  String get schemaDiffPhaseStarting => 'Starting';

  @override
  String get schemaDiffPhaseListingTables => 'Listing tables';

  @override
  String get schemaDiffPhaseCapturingTables => 'Capturing tables';

  @override
  String get schemaDiffPhaseCapturingCreateStatements =>
      'Capturing create statements';

  @override
  String get schemaDiffPhaseCapturingViews => 'Capturing views';

  @override
  String get schemaDiffPhaseCapturingProcedures => 'Capturing procedures';

  @override
  String get schemaDiffPhaseCompleted => 'Completed';

  @override
  String get schemaDiffPhaseCancelled => 'Cancelled';

  @override
  String get schemaDiffPhaseError => 'Error';

  @override
  String get schemaDiffPhaseWaiting => 'Waiting';

  @override
  String get schemaDiffCaptureIncomplete => 'Schema capture incomplete';

  @override
  String get schemaDiffDryRunCompleted => 'Dry run completed';

  @override
  String get schemaDiffSyncSuccess => 'Sync completed successfully';

  @override
  String schemaDiffSyncFailed(String message) {
    return 'Sync failed: $message';
  }

  @override
  String get schemaDiffSelectConnectionHint => 'Select connection';

  @override
  String get schemaDiffSelectDatabaseHint => 'Select database';

  @override
  String get schemaDiffAddedTables => 'Added tables';

  @override
  String get schemaDiffRemovedTables => 'Removed tables';

  @override
  String get schemaDiffModifiedTables => 'Modified tables';

  @override
  String get schemaDiffUnchangedTables => 'Unchanged tables';

  @override
  String get schemaDiffDetailedChanges => 'Detailed changes';

  @override
  String get schemaDiffColumnChanges => 'Columns';

  @override
  String get schemaDiffIndexChanges => 'Indexes';

  @override
  String get schemaDiffViewChanges => 'Views';

  @override
  String get schemaDiffProcedureChanges => 'Procedures';

  @override
  String get schemaDiffNoDetailedChanges => 'No detailed changes';

  @override
  String get schemaDiffNoDifferences => 'No differences';

  @override
  String get schemaDiffNoResults => 'No results';

  @override
  String get schemaDiffSearchHint => 'Search objects...';

  @override
  String get schemaDiffFilterAdded => 'Added';

  @override
  String get schemaDiffFilterModified => 'Modified';

  @override
  String get schemaDiffFilterRemoved => 'Removed';

  @override
  String get schemaDiffObjectTypeTables => 'Tables';

  @override
  String get schemaDiffObjectTypeViews => 'Views';

  @override
  String get schemaDiffObjectTypeProcedures => 'Procedures';

  @override
  String get schemaDiffStatusAdded => 'Added';

  @override
  String get schemaDiffStatusRemoved => 'Removed';

  @override
  String get schemaDiffStatusModified => 'Modified';

  @override
  String get schemaDiffStatusUnchanged => 'Unchanged';

  @override
  String schemaDiffChangeCount(int count) {
    return '$count changes';
  }

  @override
  String get schemaDiffColumns => 'Columns';

  @override
  String get schemaDiffIndexes => 'Indexes';

  @override
  String get schemaDiffDdlComparison => 'DDL comparison';

  @override
  String get schemaDiffColumnPk => 'PK';

  @override
  String get schemaDiffColumnNotNull => 'NOT NULL';

  @override
  String get schemaDiffIndexUnique => 'Unique';

  @override
  String get schemaDiffGenerateSyncPlanHint => 'Generate sync plan';

  @override
  String get schemaDiffGenerateSyncPlanButton => 'Generate Plan';

  @override
  String schemaDiffOperationsCount(int count) {
    return '$count operations';
  }

  @override
  String get schemaDiffDryRunMode => 'Dry run';

  @override
  String get schemaDiffDryRunButton => 'Dry Run';

  @override
  String get schemaDiffExecuteButton => 'Execute';

  @override
  String schemaDiffOperationsFailed(int count) {
    return '$count operations failed';
  }

  @override
  String get schemaDiffExecuteConfirmTitle => 'Execute sync plan?';

  @override
  String get schemaDiffExecuteConfirmMessage =>
      'This will apply the generated sync plan to the target database. Continue?';

  @override
  String get schemaDiffExecuteConfirmCancel => 'Cancel';

  @override
  String get schemaDiffExecuteConfirmExecute => 'Execute';

  @override
  String get schemaDiffSaveSnapshot => 'Save Schema Snapshot';

  @override
  String get schemaDiffSnapshotTitle => 'Schema Snapshots';

  @override
  String get schemaDiffSnapshotNoSnapshots => 'No snapshots saved yet';

  @override
  String get schemaDiffSnapshotDeleteConfirm =>
      'Are you sure you want to delete this snapshot?';

  @override
  String get schemaDiffSyncExecuting => 'Executing Sync Plan';

  @override
  String get schemaDiffSyncComplete => 'Sync Complete';

  @override
  String get schemaDiffSyncRollback => 'Transaction rolled back due to errors';

  @override
  String get viewMenuTitle => '视图';

  @override
  String get viewMenuToggleSidebar => '左侧边栏';

  @override
  String get viewMenuToggleAiPanel => 'AI 面板';

  @override
  String get viewMenuToggleBottomPanel => '底部面板';

  @override
  String get viewMenuExpandWorkspace => '扩展工作区';

  @override
  String get viewMenuLayoutPresets => '布局预设';

  @override
  String get viewMenuLayoutPresetDefault => '默认';

  @override
  String get viewMenuLayoutPresetExpand => '扩展工作区';

  @override
  String get expandWorkspaceEnabled => '扩展工作区';

  @override
  String get expandWorkspaceDisabled => '退出扩展工作区';

  @override
  String get bottomPanelTabResults => '结果';

  @override
  String get bottomPanelTabLogs => '日志';

  @override
  String get bottomPanelTabHistory => '历史';

  @override
  String get bottomPanelTabTasks => '任务';

  @override
  String get bottomPanelResultsEmpty => 'No results to display';

  @override
  String get bottomPanelResultsEmptyHint => 'Execute a query to see results';

  @override
  String get bottomPanelLogsTitle => 'Query Audit Log';

  @override
  String get bottomPanelLogsEmpty => 'No audit logs yet';

  @override
  String get bottomPanelLogsEmptyHint =>
      'Execute queries to start recording logs';

  @override
  String get bottomPanelLogsStatusAll => 'All';

  @override
  String get bottomPanelLogsStatusSuccess => 'Success';

  @override
  String get bottomPanelLogsStatusFailed => 'Failed';

  @override
  String get bottomPanelLogsExport => 'Export';

  @override
  String get bottomPanelLogsClearAll => 'Clear All';

  @override
  String get bottomPanelLogsConfirmClearTitle => 'Clear Audit Logs';

  @override
  String get bottomPanelLogsConfirmClearMessage =>
      'Are you sure you want to clear all audit logs? This action cannot be undone.';

  @override
  String get bottomPanelHistoryTitle => 'SQL History';

  @override
  String get bottomPanelHistoryEmpty => 'No history yet';

  @override
  String get bottomPanelHistoryFilterAll => 'All';

  @override
  String get bottomPanelHistoryJustNow => 'Just now';

  @override
  String bottomPanelHistoryMinutesAgo(int count) {
    return '$count minutes ago';
  }

  @override
  String bottomPanelHistoryHoursAgo(int count) {
    return '$count hours ago';
  }

  @override
  String bottomPanelHistoryDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String bottomPanelHistoryDateFormat(
    int month,
    int day,
    int hour,
    String minute,
  ) {
    return '$month/$day $hour:$minute';
  }

  @override
  String bottomPanelHistoryDeleted(String sql) {
    return 'Deleted \"$sql\"';
  }

  @override
  String bottomPanelHistoryDeletedCount(int count) {
    return 'Deleted $count history records';
  }

  @override
  String get bottomPanelHistoryCopied => 'SQL copied to clipboard';

  @override
  String get bottomPanelHistoryUndo => 'Undo';

  @override
  String bottomPanelStatusRows(int count) {
    return '$count rows';
  }

  @override
  String get bottomPanelStatusClickTabForError =>
      'Click tab to view error details';

  @override
  String get resultsQueryFailedTitle => 'Query failed';

  @override
  String get resultsUnknownError => 'Unknown error';

  @override
  String get queryHistoryTitle => '查询历史';

  @override
  String get queryHistoryEmpty => '暂无查询记录 — 执行一条查询即可在此显示';

  @override
  String get queryHistoryLoading => '正在加载历史...';

  @override
  String get queryHistorySearchHint => '搜索历史...';

  @override
  String get queryHistoryExecutedAt => '执行时间';

  @override
  String get queryHistorySqlPreview => 'SQL 预览';

  @override
  String get queryHistoryDuration => '耗时';

  @override
  String get queryHistoryRowCount => '行数';

  @override
  String get queryHistoryStatusSuccess => '成功';

  @override
  String get queryHistoryStatusError => '失败';

  @override
  String get queryHistoryClearAll => '清空全部历史';

  @override
  String get queryHistoryDelete => '删除';

  @override
  String get queryHistoryRename => '重命名';

  @override
  String get queryHistoryConfirmClearAll => '确定要清空当前连接的全部历史记录吗？';

  @override
  String queryHistoryConfirmDelete(String name) {
    return '确定要删除\"$name\"吗？';
  }

  @override
  String get queryHistoryToday => '今天';

  @override
  String get queryHistoryYesterday => '昨天';

  @override
  String get queryHistoryLast7Days => '最近 7 天';

  @override
  String get queryHistoryOlder => '更早';

  @override
  String get queryHistorySaved => '已保存';

  @override
  String get resultHistorySubTabLabel => '历史';

  @override
  String get dmlCriticalTitle => '极高风险操作';

  @override
  String get dmlHighWarningTitle => '高风险操作';

  @override
  String get dmlHighWarningBody => '此操作将影响所有符合条件的行，建议添加 LIMIT';

  @override
  String get dmlAddLimit => '添加 LIMIT';

  @override
  String get dmlConfirmExecute => '确认执行';

  @override
  String get dmlRiskSummary => '风险摘要';

  @override
  String get dmlStatementsToExecute => '待执行的语句：';

  @override
  String dmlEstimatedAffectedRows(Object count) {
    return '预计影响行数：$count';
  }

  @override
  String dmlSqlInjectionDetail(Object details) {
    return 'SQL 注入：$details';
  }

  @override
  String get dmlTriggerDeleteWithoutWhere => '不带 WHERE 条件的 DELETE';

  @override
  String get dmlTriggerUpdateWithoutWhere => '不带 WHERE 条件的 UPDATE';

  @override
  String get dmlTriggerDropTable => 'DROP TABLE 操作';

  @override
  String get dmlTriggerDropDatabase => 'DROP DATABASE 操作';

  @override
  String get dmlTriggerTruncateTable => 'TRUNCATE TABLE 操作';

  @override
  String get dmlTriggerDmlWithoutLimit => '不带 LIMIT 的 DML';

  @override
  String get dmlTriggerAlterDropColumn => 'ALTER TABLE DROP COLUMN';

  @override
  String get dmlTriggerSqlInjection => '检测到 SQL 注入模式';

  @override
  String dropTableDeleteConfirmBody(Object tableName) {
    return '确定要删除表 \"$tableName\" 吗？';
  }

  @override
  String get dropTableDeleteImpact => '此操作无法撤销。表中的所有数据将被永久删除。';

  @override
  String get dropTableCheckingDependencies => '正在检查依赖...';

  @override
  String get dropTableDependencyWarning => '依赖警告';

  @override
  String get connectionReadOnlyMode => '只读模式';

  @override
  String get connectionReadOnlyModeDesc => '禁止执行 INSERT/UPDATE/DELETE/DDL 操作';

  @override
  String get connectionSshHost => 'SSH 主机';

  @override
  String get connectionSshUsername => 'SSH 用户名';

  @override
  String get connectionSshPassword => 'SSH 密码';

  @override
  String get connSshHostRequired => 'SSH 主机为必填项';

  @override
  String get commonNavigate => '导航';

  @override
  String get resultsSqlStatementLabel => 'SQL 语句：';

  @override
  String get resultsExecutionSuccess => '执行成功';

  @override
  String resultsAffectedRows(Object count) {
    return '影响 $count 行';
  }

  @override
  String resultsElapsedMs(Object ms) {
    return '耗时 ${ms}ms';
  }

  @override
  String resultsFilterConditions(Object count) {
    return '筛选：$count 个条件';
  }

  @override
  String resultsShowingRows(Object filtered, Object total) {
    return '显示 $filtered / $total 行';
  }

  @override
  String get resultsClearFilter => '清除筛选';

  @override
  String get resultsNoDataGuidance => '在编辑器中编写查询，按 Ctrl+Enter（或 F5）执行';

  @override
  String get queryHistoryEmptyHint => '使用 Ctrl+Enter 或 F5 执行查询后，将自动记录在这里';

  @override
  String get safetyExplainWarning => '性能警告';

  @override
  String safetyExplainFullScan(Object rows) {
    return '检测到全表扫描，预计扫描约 $rows 行';
  }

  @override
  String get safetyExecuteAnyway => '仍然执行';

  @override
  String get safetyCancelAndOptimize => '取消并查看执行计划';

  @override
  String get safetyPreflightTimeout => '预检超时，跳过性能分析';

  @override
  String get dmlAuditBlocked => 'DML 操作被拦截';

  @override
  String get processListKillQuery => '终止查询';

  @override
  String get processListKillConfirmTitle => '终止进程';

  @override
  String processListKillConfirm(String id, String user, String host) {
    return '确定终止连接 $id ($user@$host)?';
  }

  @override
  String get processListCopyQuery => '复制查询';

  @override
  String get processListAutoRefresh => '自动刷新';

  @override
  String get processListRefreshInterval => '刷新间隔';

  @override
  String get processManagerTitle => '进程管理';

  @override
  String get processListNoProcesses => '无活跃进程';

  @override
  String get processListNoQueryText => '无查询文本';

  @override
  String get engineStatusTitle => '引擎状态';

  @override
  String get engineInnodbStatus => 'InnoDB 状态';

  @override
  String get engineRowFormat => '行格式';

  @override
  String get engineCompression => '压缩状态';

  @override
  String get engineTablespace => '表空间';

  @override
  String get replicationRunning => '复制: 运行中';

  @override
  String get replicationStopped => '复制: 已停止';

  @override
  String replicationLag(int seconds) {
    return '延迟: $seconds秒';
  }

  @override
  String get replicationNotConfigured => '未配置复制';

  @override
  String get replicationDetailTitle => '复制状态';

  @override
  String get replicationIoThread => 'IO 线程';

  @override
  String get replicationSqlThread => 'SQL 线程';

  @override
  String get openSqliteFile => '打开 SQLite 文件…';

  @override
  String get recentFiles => '最近文件';

  @override
  String get recentFilesEmpty => '暂无最近文件';

  @override
  String get dragDropDbHint => '提示：将 .db 文件拖到窗口任意位置即可打开';

  @override
  String get sqliteOpenError => '打开 SQLite 文件失败';

  @override
  String get sidebarServerGlobal => '服务器';

  @override
  String get sidebarPerformance => '性能';

  @override
  String get sidebarUsers => '用户';

  @override
  String serverInfoVersion(String version) {
    return 'MySQL $version';
  }

  @override
  String serverInfoUptime(String duration) {
    return '运行时间：$duration';
  }

  @override
  String serverInfoThreads(String active, String running) {
    return '$active 活动连接 / $running 运行中';
  }

  @override
  String serverInfoQueries(String count) {
    return '$count 次查询';
  }

  @override
  String serverInfoSlowQueries(String count) {
    return '$count 条慢查询';
  }

  @override
  String get serverVarMaxConnections => '最大连接数';

  @override
  String get serverVarBufferPool => '缓冲池';

  @override
  String get serverVarCharset => '字符集';

  @override
  String get serverStatusUnavailable => '服务器状态不可用';

  @override
  String get processListRefreshLabel => '刷新：';

  @override
  String get processListRefreshOff => '关闭';

  @override
  String processListMore(num count) {
    return '…还有 $count 条';
  }

  @override
  String get usersNoUsers => '未找到用户';

  @override
  String get usersLocked => '已锁定';

  @override
  String sidebarDbTableCount(num count) {
    return '$count 个表';
  }

  @override
  String get mongoNodeReplication => '复制集';

  @override
  String get mongoNodeSharding => '分片';

  @override
  String get mongoValidationRules => '验证规则';

  @override
  String get mongoReplicationStandalone => '独立实例 - 不是副本集的一部分';

  @override
  String get mongoShardingNotSharded => '非分片集群';

  @override
  String get mongoValidationNoRules => '无验证规则';

  @override
  String get resultColumnTruncated => '值可能被截断（大对象类型）';

  @override
  String get dorisUpdateGuardMessage =>
      'Doris 的 Duplicate/Aggregate 模型表不支持 UPDATE，仅 Unique/Primary Key 模型支持。';

  @override
  String get dorisTableModelLabel => '表模型';

  @override
  String get dorisModelDuplicate => '明细 (Duplicate)';

  @override
  String get dorisModelUnique => '主键去重 (Unique)';

  @override
  String get dorisModelPrimaryKey => '主键 (Primary Key)';

  @override
  String get dorisHashColumnLabel => '分桶列';

  @override
  String get dorisBucketsLabel => '桶数';

  @override
  String get dorisModelNeedsKeyColumn => '该模型需要至少一个键列（在某列勾选主键）';

  @override
  String get dorisAggregateFunctionLabel => '聚合函数';

  @override
  String get dorisModelAggregate => '聚合 (Aggregate)';

  @override
  String get dorisPartitionColumn => '分区列';

  @override
  String get dorisPartitionName => '分区名';

  @override
  String get dorisPartitionLessThan => '小于值';

  @override
  String get dorisAddPartition => '添加分区';

  @override
  String get offlineLicenseTitle => '离线授权';

  @override
  String get offlineLicensePurchaseHint =>
      '升级方式：扫描 GitHub/Gitee 页面上的付款码付款后，将本机机器码与付款截图发送至作者邮箱，收到授权后在下方导入。';

  @override
  String get machineCodeLabel => '机器码';

  @override
  String get machineCodeUnavailable => '无法读取本机机器码';

  @override
  String get importLicense => '导入授权';

  @override
  String get importLicenseHint => '粘贴授权字符串，或选择 .dbmlicense 文件';

  @override
  String get buyLicense => '购买 License';

  @override
  String get machineCodeCopied => '机器码已复制到剪贴板';

  @override
  String get licenseFilePick => '选择文件';

  @override
  String get licenseTypeYearly => '年订阅';

  @override
  String get licenseTypeLifetime => '买断';

  @override
  String licenseExpiresAt(String date) {
    return '到期：$date';
  }

  @override
  String get removeLicense => '移除授权';

  @override
  String get licenseImportSuccess => '授权成功，Pro 功能已解锁';

  @override
  String get licenseErrorInvalid => '授权码格式无效';

  @override
  String get licenseErrorSignature => '授权签名校验失败';

  @override
  String get licenseErrorMachine => '该授权绑定的是其他机器';

  @override
  String get licenseErrorExpired => '授权已过期';

  @override
  String get licenseErrorNoMachine => '无法读取机器码，本设备不支持离线授权';

  @override
  String licenseActiveInfo(String email) {
    return '授权给 $email';
  }

  @override
  String get errorCopy => '复制';

  @override
  String get errorCopied => '已复制';

  @override
  String get errorAnalyzeWithAi => 'AI 分析';

  @override
  String trialRemaining(int count, String feature) {
    return '$feature 剩余 $count 次试用';
  }

  @override
  String trialUsedUp(String feature) {
    return '$feature 试用已用完';
  }

  @override
  String get centerTitle => '执行中心';

  @override
  String get centerTabTasks => '任务';

  @override
  String get centerTabErrors => '错误';

  @override
  String get centerClearErrors => '清除错误';

  @override
  String get centerDismissError => '忽略';

  @override
  String get aiPromptErrorHeader => '请诊断这个数据库错误：说明原因并给出修复建议。';

  @override
  String get commonUndo => '撤销';

  @override
  String commonDeleteWithCount(Object count) {
    return '删除（$count）';
  }

  @override
  String aiPanelSessionsDeletedCount(Object count) {
    return '已删除 $count 个会话';
  }

  @override
  String aiPanelSessionDeleted(Object title) {
    return '已删除“$title”';
  }

  @override
  String get aiPanelSelectDatabaseRequired => '请先在上方的下拉框中选择一个数据库。';

  @override
  String get aiPanelMongoExecutionPlan => '🔍 Mongo 执行计划';

  @override
  String get aiPanelSelectSessions => '选择会话';

  @override
  String get aiPanelExportTaskCreated => '导出任务已创建';

  @override
  String get aiPanelDdlOperationCancelled => 'DDL 操作已被用户取消。';

  @override
  String get aiAssistantOpenTooltip => '打开 AI 助手';

  @override
  String get schemaImpactRiskLow => '低风险';

  @override
  String get schemaImpactRiskMedium => '中风险';

  @override
  String get schemaImpactRiskHigh => '高风险';

  @override
  String get schemaImpactRiskCritical => '极高风险';

  @override
  String get schemaImpactTitle => '结构影响分析';

  @override
  String schemaImpactSubtitle(Object table, Object type) {
    return '$type 于`$table`';
  }

  @override
  String get schemaImpactDataLossWarning => '数据丢失风险：此操作将永久删除数据。';

  @override
  String schemaImpactAffectedObjects(Object count) {
    return '受影响的对象（$count）';
  }

  @override
  String schemaImpactWarnings(Object count) {
    return '警告（$count）';
  }

  @override
  String get schemaImpactRecommendations => '建议';

  @override
  String get schemaImpactHideRollbackScript => '隐藏回滚脚本';

  @override
  String get schemaImpactShowRollbackScript => '显示回滚脚本';

  @override
  String get schemaImpactNoRollbackAvailable => '无可用回滚';

  @override
  String get schemaImpactRollbackCaveat =>
      '自动回滚为 best-effort 草稿 - 列类型/约束可能有误。执行前请核对；数据无法自动恢复。';

  @override
  String get schemaImpactBackupRequired => '回滚前需备份数据';

  @override
  String get schemaImpactConfirmationRequired => '此操作执行前需要您的明确确认。';

  @override
  String get ddlConfirmDialogTitle => '需要 DDL 确认';

  @override
  String ddlAffectedObjectsCount(Object count) {
    return '受影响的对象（$count）';
  }

  @override
  String get ddlExecuteButton => '执行 DDL';

  @override
  String get ddlSqlStatementLabel => 'SQL 语句：';

  @override
  String ddlRiskLevelLabel(Object level) {
    return '风险等级：$level';
  }

  @override
  String get ddlDataLossRiskDetected => '检测到数据丢失风险';

  @override
  String ddlWarningsCount(Object count) {
    return '警告（$count）';
  }

  @override
  String get ddlTypeConfirmationToProceed => '输入确认以继续';

  @override
  String ddlTypeToConfirmDestructive(Object token) {
    return '输入“$token”以确认此破坏性操作：';
  }

  @override
  String get commonUnknown => '未知';

  @override
  String get commonDismiss => '关闭';

  @override
  String get readOnlyModeBlocked => '此连接为只读模式，写操作已禁用。';

  @override
  String get dlgFillVariables => '填写变量';

  @override
  String dlgVariableRequired(String variable) {
    return '请输入$variable';
  }

  @override
  String get dlgEditTrigger => '编辑触发器';

  @override
  String get dlgCreateTrigger => '创建触发器';

  @override
  String triggerLoadTablesFailed(String error) {
    return '加载表失败: $error';
  }

  @override
  String get triggerSelectTableRequired => '请选择表';

  @override
  String get triggerSelectEventRequired => '请至少选择一个事件';

  @override
  String get triggerUpdated => '触发器更新成功';

  @override
  String get triggerCreated => '触发器创建成功';

  @override
  String triggerSaveFailed(String error) {
    return '保存触发器失败: $error';
  }

  @override
  String get triggerNameLabel => '触发器名称';

  @override
  String get triggerNameRequired => '触发器名称不能为空';

  @override
  String get triggerNameInvalid => '触发器名称格式无效';

  @override
  String get triggerTimingLabel => '时机';

  @override
  String get triggerEventLabel => '事件';

  @override
  String get triggerTableLabel => '表';

  @override
  String get triggerSelectTableHint => '请选择表';

  @override
  String get triggerBodyLabel => '触发器主体';

  @override
  String get triggerBodyHint =>
      '输入触发器主体（SQL 语句）\n示例：\nSET NEW.updated_at = NOW();';

  @override
  String triggerCount(int count) {
    return '$count 个触发器';
  }

  @override
  String get dlgExecutionResult => '执行结果';

  @override
  String dlgExecuteRoutine(String type) {
    return '执行$type';
  }

  @override
  String dlgRoutineName(String name) {
    return '名称: $name';
  }

  @override
  String dlgRoutineType(String type) {
    return '类型: $type';
  }

  @override
  String dlgRoutineReturnType(String type) {
    return '返回类型: $type';
  }

  @override
  String get dlgParameters => '参数';

  @override
  String get dlgRoutineNoParams => '此存储过程/函数不需要参数';

  @override
  String get dlgOutputParam => '输出参数';

  @override
  String get dlgReturnValueLabel => '返回值:';

  @override
  String dlgRowsAffected(int count) {
    return '受影响的行数: $count';
  }

  @override
  String dlgEditRoutine(String type) {
    return '编辑$type';
  }

  @override
  String routineParameterCount(int count) {
    return '$count 个参数';
  }

  @override
  String routineDeleteConfirmation(String type, String name) {
    return '删除$type\"$name\"?';
  }

  @override
  String get routineListTitle => '存储过程和函数';

  @override
  String routineDefinitionTitle(String type) {
    return '$type定义';
  }

  @override
  String get queryExecutionPlan => '查询执行计划';

  @override
  String dlgCreateRoutine(String type) {
    return '创建$type';
  }

  @override
  String get dlgNameRequired => '请输入名称';

  @override
  String get dlgRoutineNameInvalid => '名称只能包含字母、数字和下划线，且不能以数字开头';

  @override
  String get dlgReturnTypeRequired => '请选择返回类型';

  @override
  String get dlgSqlCode => 'SQL 代码';

  @override
  String get dlgRoutineProcedure => '存储过程';

  @override
  String get dlgRoutineFunction => '函数';

  @override
  String get commonUpdate => '更新';

  @override
  String get commonCreate => '创建';

  @override
  String get auditLogTitle => '查询审计日志';

  @override
  String get auditLogAllStatus => '全部状态';

  @override
  String get auditLogAll => '全部';

  @override
  String get auditLogTime => '时间';

  @override
  String get auditLogDuration => '耗时';

  @override
  String get auditLogRows => '行数';

  @override
  String get auditLogStatus => '状态';

  @override
  String get auditLogEmpty => '暂无审计日志';

  @override
  String get auditLogEmptyHint => '执行查询后开始记录日志';

  @override
  String get auditLogTotal => '总计';

  @override
  String get auditLogWrite => '写入';

  @override
  String get auditLogAvgTime => '平均耗时';

  @override
  String get auditLogClearTitle => '清空审计日志';

  @override
  String get auditLogClearConfirm => '确定要清空所有审计日志吗？此操作无法撤销。';

  @override
  String get auditLogClear => '清空';

  @override
  String get piiMaskingTitle => 'PII 数据脱敏';

  @override
  String get piiMaskingEnable => '启用 PII 脱敏';

  @override
  String get piiMaskingEnableDesc => '自动脱敏查询结果中的敏感数据';

  @override
  String get piiMaskingTypes => '敏感数据类型';

  @override
  String get piiTypeEmail => '电子邮箱地址';

  @override
  String get piiTypePhone => '电话号码';

  @override
  String get piiTypeIdCard => '身份证号';

  @override
  String get piiTypeCreditCard => '信用卡';

  @override
  String get piiTypeBankCard => '银行账户';

  @override
  String get piiTypePassword => '密码';

  @override
  String get piiTypeIpAddress => 'IP 地址';

  @override
  String get shortcutNoMatching => '无匹配的快捷键';

  @override
  String get shortcutPressEscToClose => '按 ESC 关闭';

  @override
  String get indexTypePrimary => '主键';

  @override
  String get performanceAnalyzerWeeklyReportTitle => '每周慢查询报告';

  @override
  String get performanceAnalyzerWeeklyReportDesc =>
      '每周一获取 Top 10 慢查询及 EXPLAIN 分析';

  @override
  String get performanceAnalyzerLearnMore => '了解更多';

  @override
  String get backupListLoading => '加载备份列表...';

  @override
  String dbPropertiesTitle(String name) {
    return '数据库属性 - $name';
  }

  @override
  String get dbPropertyName => '名称';

  @override
  String get dbPropertyCharset => '字符集';

  @override
  String get dbPropertyCollation => '排序规则';

  @override
  String get dbPropertySize => '大小';

  @override
  String get dbPropertyTableCount => '表数量';

  @override
  String get dbPropertyViewCount => '视图数量';

  @override
  String get dbPropertyRoutineCount => '存储过程/函数';

  @override
  String get exportFormatLabel => '导出格式';

  @override
  String exportRowCount(int count) {
    return '共 $count 行数据';
  }

  @override
  String get taskCreateExportFilter => '筛选';

  @override
  String get taskCreateExportEstRows => '估计行数';

  @override
  String get taskCreateExportValidating => '验证中...';

  @override
  String get taskCreateExportSaveDialogTitle => '选择导出文件保存位置';

  @override
  String taskValidationPathNotExists(String path) {
    return '目录不存在: $path';
  }

  @override
  String taskCreateExportDesc(String table) {
    return '导出 $table';
  }

  @override
  String taskCreateExportDescFiltered(String table) {
    return '导出 $table（筛选）';
  }

  @override
  String get sqliteConnectionEditTitle => '编辑 SQLite 连接';

  @override
  String get sqliteConnectionNewTitle => '新建 SQLite 连接';

  @override
  String get createSuperTableTitle => '创建超级表';

  @override
  String get importWizardTitle => '数据导入向导';

  @override
  String dbCreateSuccess(String name) {
    return '数据库 \"$name\" 创建成功';
  }

  @override
  String get dbCreateFailed => '创建数据库失败';

  @override
  String dbCreateError(String error) {
    return '错误: $error';
  }

  @override
  String get dbOperationCannotBeUndone => '此操作无法撤销！';

  @override
  String dropTablePermanentWarning(String table) {
    return '表 \"$table\" 及其所有数据将被永久删除。';
  }

  @override
  String get dropTableDataLossWarning => '此操作无法撤销！该表中的所有数据将永久丢失。';

  @override
  String get objectTypeTable => '表';

  @override
  String get objectTypeView => '视图';

  @override
  String get commonRemove => '移除';

  @override
  String get commonRequired => '必填';

  @override
  String get commonInvalidIdentifier => '标识符无效';

  @override
  String get mongoValidationJsonObject => 'JSON 必须是对象';

  @override
  String mongoValidationInvalidJson(String error) {
    return 'JSON 无效: $error';
  }

  @override
  String get settingsAutoLimitEnabledDesc => '自动为 SELECT 查询添加 LIMIT';

  @override
  String get sqliteConnectionInfo => '连接信息';

  @override
  String get sqliteNameHint => '我的 SQLite 数据库';

  @override
  String get connectionDirNotExists => '目录不存在';

  @override
  String get indexSelectColumnRequired => '请至少选择一列';

  @override
  String indexCreateFailed(String error) {
    return '创建索引失败: $error';
  }

  @override
  String indexUpdateFailed(String error) {
    return '更新索引失败: $error';
  }

  @override
  String get indexNameRequired => '索引名称为必填项';

  @override
  String get superTableTags => '标签';

  @override
  String get superTableCreated => '超级表创建成功';

  @override
  String get redisLibNameCodeRequired => '库名称和代码为必填项';

  @override
  String get redisAdapterNotAvailable => 'Redis 适配器不可用';

  @override
  String get redisLibraryCreated => '函数库创建成功';

  @override
  String redisLibraryCreateFailed(String error) {
    return '创建函数库失败: $error';
  }

  @override
  String get redisLibraryUsageHint => '用于 #!lua name=<library>';

  @override
  String get redisInsertExample => '插入示例';

  @override
  String get redisCreateLibrary => '创建库';

  @override
  String redisKeyLoadFailed(String error) {
    return '加载键数据失败: $error';
  }

  @override
  String get redisKeyUpdated => '键更新成功';

  @override
  String redisKeySaveFailed(String error) {
    return '保存键失败: $error';
  }

  @override
  String get redisKeySaveChanges => '保存更改';

  @override
  String get serverConnectTitle => '连接到服务器';

  @override
  String get serverConnectUrl => '服务器 URL';

  @override
  String get serverUrlRequired => '服务器 URL 为必填项';

  @override
  String get serverUrlInvalid => 'URL 无效（例如 https://myserver:3000）';

  @override
  String get serverConnectEmail => '电子邮箱';

  @override
  String get serverEmailRequired => '电子邮箱为必填项';

  @override
  String get serverEmailInvalid => '电子邮箱无效';

  @override
  String get serverPasswordRequired => '密码为必填项';

  @override
  String get mongoValidationFixErrors => '请先修复 JSON 错误再应用';

  @override
  String get mongoValidationApplied => '验证规则应用成功';

  @override
  String get mongoValidationRemoved => '验证规则已移除';

  @override
  String get mongoValidationLevel => '验证级别';

  @override
  String get mongoValidationAction => '验证动作';

  @override
  String mongoValidationApplyFailed(String error) {
    return '应用验证规则失败: $error';
  }

  @override
  String get indexSelectColumns => '选择列';

  @override
  String get redisLibraryTitle => '创建函数库';

  @override
  String get redisLibraryNameLabel => '库名称';

  @override
  String get redisLibraryCreateFailedSyntax => '创建库失败（需要 Redis 7.0+，请检查语法）';

  @override
  String get redisLuaCodeLabel => 'Lua 代码';

  @override
  String get redisReplaceExisting => '替换同名已有库（FUNCTION LOAD REPLACE）';

  @override
  String get redisLibraryInfoText =>
      '库名称会自动写入 #!lua shebang。Lua 代码应包含 redis.register_function() 调用。请勿自行编写 shebang。';

  @override
  String get superTableCreateFailed => '创建超级表失败';

  @override
  String get superTableColumns => '列';

  @override
  String get errorTitle => '出错了';

  @override
  String get errorDescriptionLabel => '错误信息：';

  @override
  String get errorStackLabel => '堆栈跟踪：';

  @override
  String get columnFilterTypeNumeric => '数值';

  @override
  String get columnFilterTypeDateTime => '时间';

  @override
  String get columnFilterTypeText => '文本';

  @override
  String get columnFilterPlaceholderNumeric => '输入数值';

  @override
  String get columnFilterPlaceholderDateTime => '输入时间（如：2024-01-01）';

  @override
  String get columnFilterPlaceholderText => '输入文本';

  @override
  String columnFilterFor(String columnName) {
    return '筛选：$columnName';
  }

  @override
  String columnFilterActive(int count) {
    return '已应用 $count 个筛选条件';
  }

  @override
  String columnFilterRowCount(String filtered, String total) {
    return '$filtered / $total 行';
  }

  @override
  String get filterOpEquals => '等于';

  @override
  String get filterOpNotEquals => '不等于';

  @override
  String get filterOpContains => '包含';

  @override
  String get filterOpNotContains => '不包含';

  @override
  String get filterOpStartsWith => '开头为';

  @override
  String get filterOpEndsWith => '结尾为';

  @override
  String get filterOpGreaterThan => '大于';

  @override
  String get filterOpGreaterThanOrEqual => '大于等于';

  @override
  String get filterOpLessThan => '小于';

  @override
  String get filterOpLessThanOrEqual => '小于等于';

  @override
  String get filterOpBetween => '介于';

  @override
  String get filterOpIsNull => '为空';

  @override
  String get filterOpIsNotNull => '不为空';

  @override
  String get filterOpIsEmpty => '为空字符串';

  @override
  String get filterOpIsNotEmpty => '不为空字符串';

  @override
  String get tableNoData => '无数据';

  @override
  String tableRowCountTotal(String count) {
    return '共 $count 行';
  }

  @override
  String get tableLargeDatasetHint => '（大数据集，请滚动查看更多）';

  @override
  String tableRowRange(String start, String end, String total) {
    return '$start-$end / $total 行';
  }

  @override
  String get importWizStepSelectFile => '选择文件';

  @override
  String get importWizStepAnalyzeFile => '分析文件';

  @override
  String get importWizStepColumnMapping => '列映射';

  @override
  String get importWizStepPreviewPII => '预览 & PII';

  @override
  String get importWizStepConfirmImport => '确认导入';

  @override
  String importWizStepOf(String current, String total, String title) {
    return '第 $current 步（共 $total 步）：$title';
  }

  @override
  String get importWizTargetDatabase => '目标数据库';

  @override
  String get importWizSelectDatabase => '选择数据库';

  @override
  String get importWizTargetTableOptional => '目标表（可选）';

  @override
  String get importWizLetAiInfer => '-- 让 AI 推断表名 --';

  @override
  String get importWizChooseFile => '点击选择文件或拖拽到此处';

  @override
  String get importWizChangeFile => '更换文件';

  @override
  String get importWizSupportedFormats => '支持 CSV、JSON、Excel、TSV 格式';

  @override
  String get importWizFileUnknown => '未知';

  @override
  String get importWizAiAnalyzing => 'AI 正在分析文件...';

  @override
  String get importWizDetectingFormat => '正在检测格式、编码、字段类型...';

  @override
  String get importWizFileAnalysisResult => '文件分析结果';

  @override
  String get importWizFormat => '格式';

  @override
  String get importWizEncoding => '编码';

  @override
  String get importWizFieldCount => '字段数';

  @override
  String get importWizEstimatedRows => '估计行数';

  @override
  String get importWizFileSize => '文件大小';

  @override
  String get importWizDelimiter => '分隔符';

  @override
  String get importWizDetectedFields => '检测到的字段';

  @override
  String get importWizAiSuggestion => 'AI 建议';

  @override
  String importWizTargetTableName(String tableName) {
    return '目标表名：$tableName';
  }

  @override
  String get importWizNoAnalysisResult => '暂无分析结果';

  @override
  String get importWizSelectFileFirst => '请先选择文件';

  @override
  String get importWizNoColumnMapping => '暂无列映射';

  @override
  String get importWizGeneratingMapping => '正在生成映射...';

  @override
  String get importWizColumnMappingConfig => '列映射配置';

  @override
  String importWizColumnsMapped(String mapped, String total) {
    return '$mapped/$total 列已映射';
  }

  @override
  String get importWizMappingDescription => '将文件中的列映射到数据库表的列。选择\"不导入\"跳过该列。';

  @override
  String get importWizFileColumn => '文件列';

  @override
  String get importWizDatabaseColumn => '数据库列';

  @override
  String get importWizType => '类型';

  @override
  String get importWizPiiDetection => 'PII 敏感数据检测';

  @override
  String get importWizPiiDetectionMessage => '检测到以下敏感字段，请确认是否继续导入：';

  @override
  String get importWizPiiAcknowledge => '我已知晓，继续导入';

  @override
  String get importWizDataPreview => '数据预览';

  @override
  String importWizWarnings(String count) {
    return '$count 个警告';
  }

  @override
  String importWizFirstRows(String count) {
    return '前 $count 行';
  }

  @override
  String get importWizSensitiveField => '敏感字段';

  @override
  String get importWizDataValidationWarnings => '数据验证警告';

  @override
  String importWizValidationRowFormat(String row, String col, String msg) {
    return '第 $row 行，$col 列：$msg';
  }

  @override
  String get importWizImportSummary => '导入配置摘要';

  @override
  String get importWizSummaryTargetDatabase => '目标数据库';

  @override
  String get importWizSummaryTargetTable => '目标表';

  @override
  String get importWizSummaryFile => '文件';

  @override
  String get importWizSummaryMappedColumns => '映射列';

  @override
  String get importWizSummaryDataRows => '数据行数';

  @override
  String get importWizConflictStrategy => '冲突处理策略';

  @override
  String get importWizConflictSkip => '跳过重复行';

  @override
  String get importWizConflictSkipDesc => '当遇到重复键时，跳过该行继续导入';

  @override
  String get importWizConflictUpdate => '更新现有行';

  @override
  String get importWizConflictUpdateDesc => '当遇到重复键时，更新已有数据';

  @override
  String get importWizConflictAbort => '中止导入';

  @override
  String get importWizConflictAbortDesc => '当遇到重复键时，立即停止导入';

  @override
  String get importWizConflictSkipName => 'Skip duplicates';

  @override
  String get importWizConflictUpdateName => 'Update existing';

  @override
  String get importWizConflictAbortName => 'Abort';

  @override
  String get importWizImporting => '导入中...';

  @override
  String importWizRowsProgress(String imported, String total) {
    return '$imported/$total 行';
  }

  @override
  String importWizFailedRows(String count) {
    return '失败：$count 行';
  }

  @override
  String get importWizImportComplete => '导入完成！';

  @override
  String importWizImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String importWizImportSuccessMsg(String count) {
    return '成功导入 $count 行数据';
  }

  @override
  String get importWizImportErrorMsg => '导入过程中发生错误';

  @override
  String get importWizPreviousStep => '上一步';

  @override
  String get importWizClose => '关闭';

  @override
  String get importWizStartImport => '开始导入';

  @override
  String get importWizNextStep => '下一步';

  @override
  String get importWizReimport => '重新导入';

  @override
  String importWizLoadDatabasesFailed(String error) {
    return '加载数据库列表失败：$error';
  }

  @override
  String importWizLoadTablesFailed(String error) {
    return '加载表列表失败：$error';
  }

  @override
  String importWizPickFileFailed(String error) {
    return '选择文件失败：$error';
  }

  @override
  String importWizAnalysisFailed(String error) {
    return '分析失败：$error';
  }

  @override
  String importWizMappingFailed(String error) {
    return '生成列映射失败：$error';
  }

  @override
  String get importWizFileAnalysisFailed => '文件分析失败';

  @override
  String get importWizImportFailedGeneric => '导入失败';

  @override
  String get importWizNotSelected => '未选择';

  @override
  String get importWizNotSet => '未设置';

  @override
  String get importWizUnknown => '未知';

  @override
  String get importWizPiiDetectionSummary => 'PII 检测';

  @override
  String importWizSensitiveFieldCount(String count) {
    return '$count 个敏感字段';
  }

  @override
  String get smartImportAnalyzingDetail => 'AI 正在识别字段类型并生成建表语句';

  @override
  String get smartImportColumnMapping => '列映射';

  @override
  String smartImportColumnsMapped(String mapped, String total) {
    return '$mapped/$total 列已映射';
  }

  @override
  String get smartImportFileColumn => '文件列';

  @override
  String get smartImportTableColumn => '表列';

  @override
  String get smartImportConflictResolution => '冲突处理';

  @override
  String get smartImportDataPreview => '数据预览';

  @override
  String smartImportFirstRows(String count) {
    return '前 $count 行';
  }

  @override
  String get smartImportBack => '返回';

  @override
  String get smartImportBackgroundTask => '后台导入';

  @override
  String get smartImportFailedToGenerateSql => '-- 未能生成建表语句';

  @override
  String smartImportTargetTableSelected(String table) {
    return '已选择目标表：$table';
  }

  @override
  String smartImportTargetTableEntered(String table) {
    return '已输入目标表：$table';
  }

  @override
  String smartImportAnalysisFailed(String error) {
    return '文件分析失败：$error';
  }

  @override
  String smartImportColumnMappingsComplete(String mapped, String total) {
    return '列映射完成：$mapped/$total 列自动匹配';
  }

  @override
  String smartImportPiiDetected(String types) {
    return 'PII 检测：发现敏感字段 - $types';
  }

  @override
  String get smartImportPiiNone => 'PII 检测：未发现敏感字段';

  @override
  String smartImportPiiFailed(String error) {
    return 'PII 检测失败：$error';
  }

  @override
  String smartImportPreviewGenerated(String count) {
    return '数据预览已生成（$count 行）';
  }

  @override
  String smartImportPreviewFailed(String error) {
    return '生成预览失败：$error';
  }

  @override
  String smartImportMappingFailed(String error) {
    return '生成列映射失败：$error';
  }

  @override
  String importServiceStartImport(String table) {
    return '开始导入数据到表 \"$table\"...';
  }

  @override
  String importServiceColumnMapping(String mapped, String total) {
    return '列映射：$mapped/$total 列已映射';
  }

  @override
  String importServiceConflictStrategy(String strategy) {
    return '冲突处理策略：$strategy';
  }

  @override
  String get importServiceImporting => '开始导入数据...';

  @override
  String importServiceBatchSuccess(String batch, String count) {
    return '批次 $batch：成功导入 $count 行';
  }

  @override
  String importServiceBatchInsertFailed(String count) {
    return '批量插入失败（$count 行），尝试逐条插入...';
  }

  @override
  String importServiceUpdateFailed(String error) {
    return '更新失败：$error';
  }

  @override
  String importServiceDataTooLong(String row) {
    return '第 $row 行数据过长，已跳过';
  }

  @override
  String importServiceRowInsertFailed(String row, String error) {
    return '第 $row 行插入失败：$error';
  }

  @override
  String importServiceBatchSkipped(String count) {
    return '本批次跳过：$count 行（重复）';
  }

  @override
  String importServiceBatchUpdated(String count) {
    return '本批次更新：$count 行';
  }

  @override
  String importServiceBatchFailed(String count) {
    return '本批次失败：$count 行';
  }

  @override
  String importServicePhaseProgress(
    String imported,
    String skipped,
    String updated,
  ) {
    return '已导入 $imported 行，跳过 $skipped 行，更新 $updated 行...';
  }

  @override
  String get importServiceImportCancelled => '导入已取消';

  @override
  String importServiceFileReadFailed(String error) {
    return '文件读取失败：$error';
  }

  @override
  String importServiceImportComplete(String imported, String failed) {
    return '数据导入完成！成功：$imported 行，失败：$failed 行';
  }

  @override
  String taskExecutorAnalyzeFile(String path) {
    return '开始分析文件：$path';
  }

  @override
  String taskExecutorFileFormat(String format, String encoding, String rows) {
    return '文件格式：$format，编码：$encoding，预估行数：$rows';
  }

  @override
  String get taskExecutorTableNotExists => '表不存在，正在创建表...';

  @override
  String get taskExecutorTableCreated => '表创建成功';

  @override
  String get taskExecutorTableCreateFailed => '创建表失败';

  @override
  String taskExecutorTableNotExistsError(String table) {
    return '目标表 \"$table\" 不存在，请先创建表';
  }

  @override
  String get taskExecutorNoColumnMapping => '没有可用的列映射，请检查文件字段与表字段是否匹配';

  @override
  String taskExecutorColumnMapping(String mapped, String total) {
    return '列映射：$mapped/$total 列已映射';
  }

  @override
  String get taskExecutorStartImport => '开始导入数据...';

  @override
  String taskExecutorImportComplete(String imported, String failed) {
    return '导入完成！成功：$imported 行，失败：$failed 行';
  }

  @override
  String get taskExecutorImportFinished => '导入完成';

  @override
  String get serverConnectNoServerLearnMore =>
      'Don\'t have a server? Learn more';

  @override
  String get touchpointLiteLearnMore => 'See how';

  @override
  String get touchpointLiteSlowQueryTitle => 'Recurring slow queries?';

  @override
  String get touchpointLiteSlowQueryDesc =>
      'DbMaster Server can track these automatically and alert you on schedule.';

  @override
  String get touchpointLiteSchemaDiffTitle => 'Repeat schema comparisons?';

  @override
  String get touchpointLiteSchemaDiffDesc =>
      'DbMaster Server can run this on a schedule, retry on failure, and send Feishu/DingTalk alerts.';

  @override
  String get touchpointLiteDataSyncTitle => 'Tired of running this manually?';

  @override
  String get touchpointLiteDataSyncDesc =>
      'DbMaster Server can automate this sync with retries and team notifications.';

  @override
  String get driftMenuLabel => 'Schema 漂移告警';

  @override
  String get driftTaskListTitle => 'Schema 漂移告警';

  @override
  String get driftTaskListEmpty => '还没有漂移任务。创建一个任务来监控源库的 Schema 变更。';

  @override
  String get driftTaskListEmptyHint => '漂移任务会按计划对只读源库做快照,Schema 发生变化时给你告警。';

  @override
  String get driftCreateTaskButton => '新建漂移任务';

  @override
  String get driftRunNowButton => '立即运行';

  @override
  String get driftHistoryButton => '历史';

  @override
  String get driftViewDiffButton => '查看差异';

  @override
  String get driftDeleteTaskButton => '删除';

  @override
  String get driftColTaskName => '任务';

  @override
  String get driftColSource => '源库';

  @override
  String get driftColInterval => '间隔';

  @override
  String get driftColLastRun => '上次运行';

  @override
  String get driftColStatus => '状态';

  @override
  String driftIntervalMinutes(String minutes) {
    return '每 $minutes 分钟';
  }

  @override
  String driftIntervalHours(String hours) {
    return '每 $hours 小时';
  }

  @override
  String get driftIntervalUnknown => '服务端默认';

  @override
  String get driftEditIntervalTooltip => '修改检查间隔';

  @override
  String get driftEditIntervalTitle => '修改检查间隔';

  @override
  String get driftIntervalUpdated => '间隔已更新,下次调度扫描生效。';

  @override
  String get driftStatusNever => '未运行';

  @override
  String get driftStatusRunning => '运行中';

  @override
  String get driftStatusSucceeded => '成功';

  @override
  String get driftStatusFailed => '失败';

  @override
  String get driftStatusUnknown => '未知';

  @override
  String get driftCreateTaskTitle => '创建漂移任务';

  @override
  String get driftCreateTaskName => '任务名';

  @override
  String get driftCreateTaskSource => '源连接(只读)';

  @override
  String get driftCreateTaskNoSources => '还没有只读源连接。';

  @override
  String get driftCreateTaskAddSource => '添加源连接';

  @override
  String get driftCreateTaskInterval => '检查间隔';

  @override
  String get driftCreateTaskWebhook => 'Webhook URL(可选,https)';

  @override
  String get driftCreateTaskWebhookHint => '飞书 / 钉钉 / Slack webhook，多个用逗号分隔';

  @override
  String get driftCreateTaskSubmit => '创建任务';

  @override
  String get driftCreateTaskInvalidName => '请输入任务名。';

  @override
  String get driftCreateTaskInvalidSource => '请选择源连接。';

  @override
  String get driftCreateTaskInvalidInterval => '间隔必须在 1 到 1440 分钟之间。';

  @override
  String get driftCreateTaskInvalidWebhook => 'Webhook URL 必须以 https:// 开头。';

  @override
  String get driftGatedTitle => 'Server 许可已锁定';

  @override
  String get driftGatedBody => '激活或续费 Server 许可后才能创建或运行漂移任务。已有数据仍可查看。';

  @override
  String get driftCreateSourceTitle => '添加只读源连接';

  @override
  String get driftCreateSourceDbType => '数据库类型';

  @override
  String get driftCreateSourceHost => '主机';

  @override
  String get driftCreateSourcePort => '端口';

  @override
  String get driftCreateSourceUsername => '用户名(只读账号)';

  @override
  String get driftCreateSourcePassword => '密码';

  @override
  String get driftCreateSourceDatabase => '数据库(可选)';

  @override
  String get driftCreateSourceSubmit => '添加连接';

  @override
  String get driftCreateSourceCanaryNote =>
      'Server 在保存前会探测账号权限 — 可写账号会被拒绝。请使用 SELECT-only 账号。';

  @override
  String get driftRunQueued => '运行已排队,完成后列表会自动更新。';

  @override
  String driftRunFailed(String error) {
    return '运行失败:$error';
  }

  @override
  String get driftHistoryTitle => '运行历史';

  @override
  String get driftHistoryColStarted => '开始时间';

  @override
  String get driftHistoryColDuration => '耗时';

  @override
  String get driftHistoryColDrift => '漂移';

  @override
  String get driftHistoryColTrigger => '触发';

  @override
  String get driftHistoryColWebhook => 'Webhook';

  @override
  String get driftHistoryNoDrift => '无漂移';

  @override
  String driftHistoryHasDrift(String count) {
    return '$count 处变更';
  }

  @override
  String driftHistoryError(String error) {
    return '错误:$error';
  }

  @override
  String get driftTriggerManual => '手动';

  @override
  String get driftTriggerScheduler => '调度器';

  @override
  String get driftDiffTitle => '漂移差异';

  @override
  String get driftDiffPickSnapshots => '选择两个快照进行对比';

  @override
  String get driftDiffSnapshotNewer => '较新';

  @override
  String get driftDiffSnapshotOlder => '较旧';

  @override
  String get driftDiffCompare => '对比';

  @override
  String get driftDiffNoComparable => '请选择两个不同的快照进行对比。';

  @override
  String get driftDiffEmpty => '这两个快照之间没有差异。';

  @override
  String get driftLoading => '加载中…';

  @override
  String get driftRetry => '重试';

  @override
  String get driftClose => '关闭';

  @override
  String get viewModeTable => '表格';

  @override
  String get viewModeChart => '图表';

  @override
  String get viewModeCard => '卡片';

  @override
  String get viewModeDocument => '文档卡片';

  @override
  String get viewModeJsonTree => 'JSON 树';

  @override
  String get viewModeKeyValue => '键值视图';

  @override
  String get documentExpand => '展开';

  @override
  String get documentCollapse => '折叠';

  @override
  String documentExpandMore(int count) {
    return '展开其余 $count 个字段';
  }

  @override
  String jsonTreeItemCount(int count) {
    return '$count 项';
  }

  @override
  String get keyValueField => '字段';

  @override
  String get keyValueValue => '值';

  @override
  String keyValueFieldLabel(String field) {
    return '字段：$field';
  }

  @override
  String keyValueLengthLabel(int length) {
    return '长度：$length 字符';
  }

  @override
  String get chartViewComingSoon => '图表视图（即将上线）';

  @override
  String chartExportSuccess(String path) {
    return '图表已保存到 $path';
  }

  @override
  String chartExportFailed(String error) {
    return '图表导出失败：$error';
  }

  @override
  String chartSamplingNotice(int count) {
    return '数据量较大：已采样 $count 个点以保证性能';
  }

  @override
  String get chartAiTrend => 'AI 趋势分析';

  @override
  String get chartTypeLine => '折线';

  @override
  String get chartTypeBar => '柱状';

  @override
  String get chartTypePie => '饼图';

  @override
  String get chartTypeScatter => '散点';

  @override
  String get statisticsPanelTitle => '统计';

  @override
  String get exportStepBack => '上一步';

  @override
  String get exportStepNext => '下一步';

  @override
  String get noJsonDataToSample => '无数据可采样';

  @override
  String get noLeafNodes => '无可提取字段';

  @override
  String get fieldNotInAllRows => '非所有行都有';

  @override
  String get commonRetry => '重试';

  @override
  String get extensionNoAdapter => '无适配器';

  @override
  String get extensionNotPostgres => '非 PostgreSQL 连接';

  @override
  String get extensionLoadFailed => '加载成员失败';

  @override
  String get extensionTypes => '类型';

  @override
  String get extensionFunctions => '函数';

  @override
  String get extensionOperators => '运算符';

  @override
  String get extensionSchema => '模式';

  @override
  String get extensionDescription => '描述';

  @override
  String get vectorLoadFailed => '加载向量索引失败';

  @override
  String get vectorNoAdapter => '无适配器';

  @override
  String get vectorNoIndexes => '未定义向量索引';

  @override
  String get jsonInvalidJson => '无效 JSON';

  @override
  String get jsonNoMatches => '无匹配';

  @override
  String get jsonSearchHint => '搜索键或值…';

  @override
  String get jsonMaxDepthReached => '<已达最大深度>';

  @override
  String get jsonTruncated => '<已截断>';

  @override
  String get commonApply => '应用';

  @override
  String get pragmaExplorerTitle => 'PRAGMA 探索器';

  @override
  String get pragmaNoAdapter => '无适配器';

  @override
  String get pragmaNotSQLite => 'PRAGMA 探索器仅适用于 SQLite 连接';

  @override
  String get pragmaSearchHint => '按名称或值搜索 PRAGMA…';

  @override
  String get pragmaCategoryPerformance => '性能';

  @override
  String get pragmaCategoryDurability => '持久性';

  @override
  String get pragmaCategorySecurity => '安全';

  @override
  String get pragmaCategoryDebug => '调试';

  @override
  String get pragmaSetValue => '设置值';

  @override
  String get sqliteCopyFilePath => '复制文件路径';

  @override
  String get sqliteOpenInFolder => '在文件夹中打开';

  @override
  String get sqliteToggleWalMode => '切换 WAL 模式';

  @override
  String get sqliteOptimizeDatabase => '优化数据库';

  @override
  String get sqliteVacuum => 'VACUUM';

  @override
  String get sqliteIntegrityCheck => '完整性检查';

  @override
  String get sqliteSaveAs => '另存为…';

  @override
  String get sqliteStatusWal => 'WAL';

  @override
  String get sqliteStatusPageSize => '页大小';

  @override
  String get sqliteStatusFileSize => '文件';

  @override
  String get sqliteAttachDatabase => '附加数据库…';

  @override
  String get sqliteDetach => '分离';

  @override
  String get sqliteAttachFileLabel => '数据库文件';

  @override
  String get sqliteAttachFileHint => '选择要附加的 .db 文件';

  @override
  String get sqliteAttachPickFile => '选择文件';

  @override
  String get sqliteAttachAliasLabel => '别名';

  @override
  String get sqliteAttachAliasHint => 'archive';

  @override
  String get sqliteAttachAliasHelp =>
      '字母、数字、下划线。作为跨库查询的 schema 前缀（如 SELECT * FROM 别名.表名）。';

  @override
  String get sqliteAttachButton => '附加';

  @override
  String sqliteAttachSuccess(String alias) {
    return '已附加 $alias';
  }

  @override
  String sqliteAttachFailed(String error) {
    return '附加失败：$error';
  }

  @override
  String sqliteDetachSuccess(String alias) {
    return '已分离 $alias';
  }

  @override
  String sqliteDetachFailed(String error) {
    return '分离失败：$error';
  }

  @override
  String get sqliteAttachAliasInvalid => '别名需以字母或下划线开头，只能包含字母、数字、下划线。';

  @override
  String get sqliteAttachAliasReserved => '别名 \"main\" 和 \"temp\" 是保留名。';

  @override
  String get sqliteAttachAliasKeyword => '别名是 SQLite 关键字，请换一个。';

  @override
  String get sqliteAttachAliasDuplicate => '该别名已被附加库占用。';

  @override
  String get mongoNestedFields => '嵌套字段';

  @override
  String get healthMenuLabel => '健康检查';

  @override
  String get healthDialogTitle => '健康检查';

  @override
  String get healthDialogSubtitle => '定时数据库健康巡检（ADR-0004）';

  @override
  String get healthStatusHealthy => '健康';

  @override
  String get healthStatusWarning => '有告警';

  @override
  String get healthStatusCritical => '检查失败';

  @override
  String get healthStatusUnknown => '无数据';

  @override
  String get healthNoTasks => '未配置任何健康检查任务。';

  @override
  String get healthNoTasksHint => '任务通过 Server API 或管理后台创建。';

  @override
  String healthBadgeAlerts(int n) {
    return '$n 个告警';
  }

  @override
  String get healthColumnTask => '任务';

  @override
  String get healthColumnStatus => '状态';

  @override
  String get healthColumnLastCheck => '上次检查';

  @override
  String get healthColumnConnection => '连接';

  @override
  String get healthRunNow => '立即运行';

  @override
  String get healthRunQueued => '已排队运行，稍后自动刷新。';

  @override
  String get healthRefreshFailed => '加载健康检查结果失败。';

  @override
  String get healthNoResults => '暂无结果';

  @override
  String get healthAgoJustNow => '刚刚';

  @override
  String healthAgoMinutes(int n) {
    return '$n 分钟前';
  }

  @override
  String healthAgoHours(int n) {
    return '$n 小时前';
  }

  @override
  String healthAgoDays(int n) {
    return '$n 天前';
  }

  @override
  String healthLatencyMs(int ms) {
    return '$ms 毫秒';
  }

  @override
  String healthAlertsCount(int n) {
    return '$n 个告警';
  }

  @override
  String get healthMetricConnectivity => '连通性';

  @override
  String get healthMetricRowCount => '行数';

  @override
  String get healthMetricMissingPk => '缺少主键';

  @override
  String get healthMetricConnectionCount => '连接数';

  @override
  String get healthClose => '关闭';

  @override
  String get healthLoading => '加载中…';

  @override
  String get healthResultSuccess => '成功';

  @override
  String get healthResultPartial => '部分成功';

  @override
  String get healthResultFailed => '失败';

  @override
  String get healthRefresh => '刷新';

  @override
  String get healthCreateTaskTitle => '创建健康检查任务';

  @override
  String get healthCreateTaskName => '任务名';

  @override
  String get healthCreateTaskInvalidName => '请输入任务名。';

  @override
  String get healthCreateTaskSource => '源连接';

  @override
  String get healthCreateTaskNoConnections =>
      'Server 上还没有数据库连接，请先在「管理 Server 连接」中添加。';

  @override
  String get healthCreateTaskCron => 'Cron 调度';

  @override
  String get healthCreateTaskCronHint => '5 段 cron 表达式，如 */5 * * * *（每 5 分钟）';

  @override
  String get healthCreateTaskInvalidCron => '请输入有效的 5 段 cron 表达式。';

  @override
  String get healthCreateTaskFailThreshold => '告警阈值';

  @override
  String get healthCreateTaskFailThresholdHint => '连续失败几次后告警（1-10）';

  @override
  String get healthCreateTaskInvalidFailThreshold => '阈值需在 1 到 10 之间。';

  @override
  String get healthCreateTaskWebhook => 'Webhook URL（可选）';

  @override
  String get healthCreateTaskWebhookHint => 'https:// URL，用于接收健康告警。';

  @override
  String get healthCreateTaskInvalidWebhook => 'Webhook 必须是 https:// URL。';

  @override
  String get healthCreateTaskSubmit => '创建任务';

  @override
  String get healthCreateTaskButton => '新建任务';

  @override
  String get healthGatedTitle => 'Server 许可已锁定';

  @override
  String get healthGatedBody => '激活或续费 Server 许可后才能创建健康检查任务。已有数据仍可查看。';

  @override
  String get healthHistoryTitle => '运行历史';

  @override
  String get healthViewAllHistory => '查看全部历史';

  @override
  String healthHistoryError(String error) {
    return '错误：$error';
  }

  @override
  String get healthTriggerManual => '手动';

  @override
  String get healthTriggerScheduler => '定时';

  @override
  String get dataSyncCreateTaskButton => '新建同步任务';

  @override
  String get taskEditTitle => '编辑任务';

  @override
  String get taskEditName => '任务名称';

  @override
  String get taskEditInvalidName => '名称不能为空';

  @override
  String get taskEditEnabled => '启用';

  @override
  String get taskEditEnabledHint => '调度已激活（按 cron 配置触发）';

  @override
  String get taskEditDisabledHint => '已暂停 — cron 不会触发';

  @override
  String get taskEditCron => 'Cron 表达式';

  @override
  String get taskEditCronHint => '5 段：分 时 日 月 周（如 */5 * * * *）';

  @override
  String get taskEditInvalidCron => '请输入 5 段空格分隔的字段';

  @override
  String get taskEditWebhook => 'Webhook URL';

  @override
  String get taskEditWebhookHint => '可选 HTTPS webhook，多个用逗号分隔';

  @override
  String get taskEditInvalidWebhook => '必须以 https:// 开头';

  @override
  String get taskEditCancel => '取消';

  @override
  String get taskEditSubmit => '保存修改';

  @override
  String get taskTogglePauseTooltip => '暂停调度';

  @override
  String get taskToggleResumeTooltip => '恢复调度';

  @override
  String get taskEditTooltip => '编辑任务';

  @override
  String get taskDeleteTooltip => '删除任务';

  @override
  String get taskDeleteConfirm => '删除此任务？此操作无法撤销。';

  @override
  String get teamQueryTitle => '团队查询库';

  @override
  String get teamQueryRefresh => '刷新';

  @override
  String get teamQuerySearchHint => '搜索标题或 SQL…';

  @override
  String get teamQueryTagHint => '按标签过滤';

  @override
  String get teamQueryEmpty => '暂无团队查询。从编辑器发布一个。';

  @override
  String get teamQueryNotConnected => '未连接到 DbMaster 服务器。';

  @override
  String get teamQueryFork => '打开（载入到编辑器）';

  @override
  String get teamQueryDelete => '删除';

  @override
  String get teamQueryCancel => '取消';

  @override
  String teamQueryDeleteConfirm(String title) {
    return '从团队库删除「$title」？';
  }

  @override
  String get teamQueryForkNoConnection => '请先打开数据库连接，再载入团队查询。';

  @override
  String teamQueryForked(String title) {
    return '已在新标签页打开「$title」。';
  }

  @override
  String teamQueryCreatedBy(String author) {
    return '作者：$author';
  }

  @override
  String get teamQueryMenuLabel => '团队查询库';

  @override
  String get saveToTeamTooltip => '保存到团队库';

  @override
  String get saveToTeamTitle => '发布到团队库';

  @override
  String get saveToTeamNameLabel => '查询名称';

  @override
  String get saveToTeamTagsLabel => '标签（逗号分隔）';

  @override
  String get saveToTeamTagsHint => '可选——帮助队友找到此查询';

  @override
  String get saveToTeamCancel => '取消';

  @override
  String get saveToTeamSubmit => '发布';

  @override
  String saveToTeamSuccess(String title) {
    return '已发布「$title」到团队库。';
  }

  @override
  String get saveToTeamGated => '许可已锁定——激活 Server 许可后才能发布团队查询。';

  @override
  String get approvalMenuLabel => 'DDL 审批';

  @override
  String get approvalListTitle => 'DDL 审批';

  @override
  String get approvalAddTooltip => '提交新 DDL';

  @override
  String get approvalRefresh => '刷新';

  @override
  String get approvalNotConnected => '连接 DbMaster server 以查看审批。';

  @override
  String get approvalListEmpty => '暂无 DDL 审批。';

  @override
  String get approvalSubmitTitle => '提交 DDL 审批';

  @override
  String get approvalSubmitButton => '提交审批';

  @override
  String get approvalSubmitDdlLabel => 'DDL 语句';

  @override
  String get approvalSubmitDdlHint => '粘贴待审批的 DDL';

  @override
  String get approvalSubmitRequired => 'DDL 语句不能为空';

  @override
  String get approvalSubmitInvalidSql =>
      '看起来不是 DDL（需以 CREATE/ALTER/DROP/TRUNCATE/RENAME 开头）';

  @override
  String get approvalSubmitTargetDb => '目标连接';

  @override
  String get approvalSubmitNoConnection =>
      '没有可用的 Server 连接，请先在「管理 Server 连接」中添加。';

  @override
  String get approvalSubmitSuccess => 'DDL 已提交审批。';

  @override
  String get approvalLoading => '加载中…';

  @override
  String get approvalCancel => '取消';

  @override
  String get approvalApprove => '批准并执行';

  @override
  String get approvalReject => '拒绝';

  @override
  String get approvalRejectTitle => '拒绝审批';

  @override
  String get approvalRejectConfirm => '拒绝此 DDL 审批？Server 将不会执行该 DDL。此操作不可撤销。';

  @override
  String get approvalViewDdl => '查看 DDL';

  @override
  String get approvalStatusPending => '待审批';

  @override
  String get approvalStatusExecuting => '执行中';

  @override
  String get approvalStatusApproved => '已批准';

  @override
  String get approvalStatusFailed => '失败';

  @override
  String get approvalStatusRejected => '已拒绝';

  @override
  String approvalExecError(String error) {
    return '错误：$error';
  }

  @override
  String get approvalAlreadyResolved => '此审批已被其他审核人处理。';

  @override
  String get approvalConflict => '其他审核人已先处理此审批。';

  @override
  String get approvalNotFound => '审批未找到（可能已被删除）。';

  @override
  String get approvalGatedTitle => '需要许可证';

  @override
  String get approvalGatedBody => '激活或续期 Server 许可证以管理 DDL 审批。';

  @override
  String approvalMetaLine(String target, String submitter) {
    return '→ $target • 提交人 $submitter';
  }

  @override
  String approvalBadgeCount(int n) {
    return '$n 项待审';
  }

  @override
  String get submitApprovalTooltip => '提交 DDL 审批';

  @override
  String get workspacesMenuLabel => '工作空间';

  @override
  String get workspacesTitle => '工作空间';

  @override
  String get workspacesRefresh => '刷新';

  @override
  String get workspacesCreate => '新建工作空间';

  @override
  String get workspacesJoin => '加入工作空间';

  @override
  String get workspacesNotConnected => '连接 DbMaster 服务器以管理工作空间。';

  @override
  String get workspacesEmpty => '还没有工作空间。新建一个或用邀请码加入。';

  @override
  String get workspacesMembers => '成员';

  @override
  String get workspacesLeave => '退出';

  @override
  String get workspacesDelete => '删除';

  @override
  String workspacesMemberCount(int n) {
    return '$n 位成员';
  }

  @override
  String get workspacesRoleAdmin => '管理员';

  @override
  String get workspacesScopeNotice =>
      '工作空间用于成员分组与邀请协作。自动化任务、连接与团队查询库在整个 Server 实例内全局共享，不按工作空间隔离。';

  @override
  String get workspacesRoleMember => '成员';

  @override
  String workspacesLeaveConfirm(String name) {
    return '退出工作空间「$name」？';
  }

  @override
  String workspacesDeleteConfirm(String name) {
    return '删除工作空间「$name」？将移除所有成员。';
  }

  @override
  String workspacesCreated(String name) {
    return '已创建工作空间「$name」。';
  }

  @override
  String workspacesLeft(String name) {
    return '已退出工作空间「$name」。';
  }

  @override
  String workspacesDeleted(String name) {
    return '已删除工作空间「$name」。';
  }

  @override
  String get workspacesJoined => '已加入工作空间。';

  @override
  String get workspacesCancel => '取消';

  @override
  String get workspacesCreateTitle => '新建工作空间';

  @override
  String get workspacesCreateNameLabel => '工作空间名称';

  @override
  String get workspacesCreateNameHint => '例如：数据平台团队';

  @override
  String get workspacesCreateRequired => '名称不能为空。';

  @override
  String get workspacesCreateTooLong => '名称不能超过 100 个字符。';

  @override
  String get workspacesCreateButton => '创建';

  @override
  String get workspacesJoinTitle => '加入工作空间';

  @override
  String get workspacesJoinIdLabel => '工作空间 ID';

  @override
  String get workspacesJoinIdHint => '粘贴管理员分享的工作空间 ID';

  @override
  String get workspacesJoinCodeLabel => '邀请码';

  @override
  String get workspacesJoinCodeHint => '6 位邀请码';

  @override
  String get workspacesJoinRequired => '两个字段都必须填写。';

  @override
  String get workspacesJoinHint => '向工作空间管理员索取工作空间 ID 和邀请码，然后分别粘贴到上方。';

  @override
  String get workspacesJoinButton => '加入';

  @override
  String workspacesMembersTitle(String name) {
    return '成员 — $name';
  }

  @override
  String get workspacesInviteCode => '邀请码';

  @override
  String get workspacesCopyInvite => '复制邀请';

  @override
  String get workspacesInviteCopied => '已复制工作空间 ID 和邀请码，可转发给同事。';

  @override
  String get workspacesMembersEmpty => '暂无成员。';

  @override
  String get workspacesRemoveMember => '移除';

  @override
  String workspacesRemoveMemberConfirm(String name) {
    return '将 $name 从该工作空间移除？';
  }

  @override
  String get workspacesYou => '（你）';

  @override
  String get layoutInsufficientSpace => '空间不足，无法展开此面板——请放大窗口';

  @override
  String get welcomeSubtitle => 'AI 增强的数据库管理';

  @override
  String get mcpTokensMenuLabel => 'MCP 令牌';

  @override
  String get mcpTokensTitle => 'MCP 令牌';

  @override
  String get mcpTokensIntro =>
      '供 AI 客户端（Claude Code、Cursor）使用的长效令牌。把它作为 Bearer token 配进客户端的 MCP 配置即可；随时可吊销。';

  @override
  String get mcpTokensNotConnected => '连接 DbMaster 服务器后才能管理 MCP 令牌。';

  @override
  String get mcpTokensEmpty => '还没有令牌。为你的 AI 客户端创建一个吧。';

  @override
  String get mcpTokensNameHint => '令牌名称（如 claude-code-mac）';

  @override
  String get mcpTokensCreate => '创建';

  @override
  String mcpTokensOnceTitle(String name) {
    return '令牌「$name」已创建';
  }

  @override
  String get mcpTokensOnceWarning =>
      '请立即复制——出于安全考虑不会再显示。将它作为 Bearer token 配置到 MCP 客户端（如 mcp.json）。';

  @override
  String get mcpTokensCopy => '复制';

  @override
  String get mcpTokensCopied => '令牌已复制到剪贴板';

  @override
  String get mcpTokensDone => '完成';

  @override
  String mcpTokensLastUsed(String value) {
    return '最近使用：$value';
  }

  @override
  String get mcpTokensNeverUsed => '从未使用';

  @override
  String get mcpTokensRevoke => '吊销';

  @override
  String get mcpTokensRevokeTitle => '吊销此令牌？';

  @override
  String mcpTokensRevokeBody(String name, String prefix) {
    return '使用「$name」（$prefix…）的客户端将立即失效，且不可恢复。';
  }

  @override
  String get serverConnectionsMenuLabel => '管理 Server 连接';

  @override
  String get serverConnectionsTitle => 'Server 连接管理';

  @override
  String get serverConnectionsIntro =>
      '注册在 Server 上的数据库连接。数据同步、健康检查、DDL 审批都基于这些连接运行；桌面侧栏的连接列表是独立的。';

  @override
  String get serverConnectionsNotConnected => '未连接 Server。';

  @override
  String get serverConnectionsEmpty =>
      'Server 上还没有连接。请先添加，数据同步 / 健康检查 / 审批任务才有可用的数据库。';

  @override
  String get serverConnectionsAdd => '添加';

  @override
  String get serverConnectionsEdit => '编辑';

  @override
  String get serverConnectionsDelete => '删除';

  @override
  String get serverConnectionsKindCollab => '协作';

  @override
  String get serverConnectionsKindSourceDrift => 'Drift 源（只读）';

  @override
  String get serverConnectionsDeleteTitle => '删除连接';

  @override
  String serverConnectionsDeleteBody(String name) {
    return '删除 Server 连接「$name」？';
  }

  @override
  String serverConnectionsDeleteTaskWarning(num count) {
    return '有 $count 个任务引用此连接，将随之被删除（作为源）或断开（作为目标）。';
  }

  @override
  String get serverConnFormCreateTitle => '添加 Server 连接';

  @override
  String get serverConnFormEditTitle => '编辑 Server 连接';

  @override
  String get serverConnFormName => '名称';

  @override
  String get serverConnFormType => '类型';

  @override
  String get serverConnFormHost => '主机';

  @override
  String get serverConnFormPort => '端口';

  @override
  String get serverConnFormUsername => '用户名';

  @override
  String get serverConnFormPassword => '密码';

  @override
  String get serverConnFormPasswordKeepHint => '留空保持原密码不变';

  @override
  String get serverConnFormDatabase => '默认数据库（可选）';

  @override
  String get serverConnFormSqlitePath => '数据库文件路径';

  @override
  String get serverConnFormSave => '保存';

  @override
  String get serverConnFormRequired => '必填';

  @override
  String get serverConnFormInvalidPort => '端口必须是数字';

  @override
  String get dataSyncConnectionNotOnServer =>
      '所选连接尚未注册到 Server。请先在「管理 Server 连接」中添加，再重试。';

  @override
  String get settingsLogs => '日志';

  @override
  String get logsUnavailable => '日志未启用';

  @override
  String get logsOpenFolder => '打开目录';

  @override
  String get logsExport => '导出';

  @override
  String get logsExportSuccess => '日志已导出';

  @override
  String logsExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get logsOpenFolderFailed => '打开目录失败';

  @override
  String get updateSectionTitle => '更新';

  @override
  String get updateCheckButton => '检查更新';

  @override
  String get updateGoDownload => '前往下载';

  @override
  String get updateStatusChecking => '检查中…';

  @override
  String get updateStatusUpToDate => '已是最新版本';

  @override
  String updateStatusAvailable(String version) {
    return '有新版本：$version';
  }

  @override
  String get updateStatusUnknownVersion => '当前版本未知（开发构建）';

  @override
  String updateStatusUnknownLatest(String version) {
    return '最新版本：$version（当前版本未知）';
  }

  @override
  String get updateStatusFailed => '检查失败，请稍后重试';

  @override
  String updateCurrentVersion(String version) {
    return '当前版本：$version';
  }

  @override
  String get updateAutoCheck => '启动时自动检查更新';

  @override
  String get updateAutoCheckDesc => '静默检查 GitHub Releases（每 24 小时至多一次）';

  @override
  String serverVersionLine(String version) {
    return 'Server 版本：$version';
  }

  @override
  String serverVersionOutdated(String version, String min) {
    return 'Server $version 低于最低兼容版本 $min，请升级 dbmaster-server';
  }

  @override
  String updateAvailableSnackbar(String version) {
    return '新版本 $version 已发布';
  }

  @override
  String crashRestoredTabs(int count) {
    return '检测到上次异常退出，已恢复 $count 个标签页';
  }

  @override
  String get saveQueryNoConnection => '无法保存——当前没有数据库连接';

  @override
  String get saveQueryReadOnly => '无法保存——该连接为只读';

  @override
  String saveQueryFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get editorSuggestionApplied => '✓ 已采用建议，SQL 已更新';

  @override
  String get editorRestoreOriginalSql => '还原原始 SQL';

  @override
  String get editorIndexDdlFilled => '✓ 索引 DDL 已填入编辑器，点执行以运行（将进行安全审查）';

  @override
  String get safetyReviewedLabel => '已审查';

  @override
  String get statusConnecting => '连接中…';

  @override
  String get resultsContextCopyCell => '复制单元格';

  @override
  String get resultsContextCopyRowJson => '复制整行（JSON）';

  @override
  String get resultsContextExportRowInsert => '导出该行为 SQL INSERT';

  @override
  String get resultsContextExportAllInsert => '导出全部为 SQL INSERT';

  @override
  String get resultsExtractNoKeys => '未找到顶层键';

  @override
  String resultsExtractFieldTitle(String column) {
    return '从 \"$column\" 提取字段';
  }

  @override
  String resultsCopiedExpression(String expression) {
    return '已复制：$expression';
  }

  @override
  String get resultsExtractInvalidJson => '无效 JSON';

  @override
  String get resultsInsertNoTableName => '无法从查询中确定表名';

  @override
  String get resultsInsertRowDone => '该行已作为 SQL INSERT 导出到剪贴板';

  @override
  String get resultsInsertNoData => '没有可导出的数据';

  @override
  String resultsInsertAllDone(int count) {
    return '已导出 $count 行到剪贴板（SQL INSERT）';
  }

  @override
  String connectionFailedWith(String error) {
    return '连接失败：$error';
  }

  @override
  String get viewTableDdl => '查看 DDL';

  @override
  String aboutVersionLine(String version) {
    return '版本 $version';
  }

  @override
  String get aboutFeedback => '反馈';

  @override
  String get driftHistoryBaseline => '基线已建立';

  @override
  String get driftDiffOnlyBaseline => '目前只有基线快照——下次运行将与其比对，漂移检测从第二个快照开始。';

  @override
  String mcpTokensCreatedAt(String time) {
    return '创建于 $time';
  }

  @override
  String get mcpTokensEndpointHint =>
      '在 MCP 客户端（如 mcp.json）配置此端点 URL 与 token（Bearer）：';

  @override
  String get mcpTokensEndpointCopied => '端点已复制';

  @override
  String get historyLoadMore => '加载更多';

  @override
  String connectionFormProvidedBy(String plugin) {
    return '由 $plugin 提供';
  }

  @override
  String get connectionDbIndex => '数据库索引';

  @override
  String get connectionAuthDatabase => '认证数据库';

  @override
  String get connectionRedisAuthNone => '无认证';

  @override
  String get connectionRedisAuthNoneDesc => '无需认证';

  @override
  String get connectionRedisAuthPasswordOnly => '仅密码';

  @override
  String get connectionRedisAuthPasswordOnlyDesc => 'AUTH 密码（Redis < 6.0）';

  @override
  String get connectionRedisAuthUsernamePassword => '用户名 + 密码（ACL）';

  @override
  String get connectionRedisAuthUsernamePasswordDesc =>
      'AUTH 用户名 密码（Redis 6.0+ ACL）';

  @override
  String get connectionSshAuthPassword => '密码';

  @override
  String get connectionSshAuthPrivateKey => '私钥';

  @override
  String get sidebarCapabilityTitle => '能力';

  @override
  String get sidebarCapGroupDatabaseObjects => '数据库对象';

  @override
  String get sidebarCapGroupAdvanced => '高级';

  @override
  String get redisCapGroupKeyspace => '键空间';

  @override
  String get redisCapWorkbench => '命令行工作台';

  @override
  String get redisCapPubsub => '发布订阅';

  @override
  String get redisCapLua => 'Lua 脚本';

  @override
  String get redisCapPipeline => '管道';

  @override
  String get redisCapTransaction => '事务';

  @override
  String get redisCapMemoryAnalysis => '内存分析';

  @override
  String get redisCapKeyspaceNotifications => '键空间通知';

  @override
  String get redisCapAcl => 'ACL 管理';

  @override
  String get redisCapConfig => '编辑配置';

  @override
  String get mongoValidationTitle => '验证规则';

  @override
  String get mongoValidationNoValidator =>
      '此集合未配置验证规则（可通过 collMod 或 MongoDB Shell 添加）。';

  @override
  String mongoValidationLoadFailed(String error) {
    return '加载验证规则失败：$error';
  }

  @override
  String sidebarDocumentInserted(String collection) {
    return '文档已插入到 $collection';
  }

  @override
  String get aiSkillCatalogTitle => '技能目录';

  @override
  String get aiSkillGroupSql => 'SQL 类';

  @override
  String get aiSkillGroupData => '数据类';

  @override
  String get aiSkillGroupSchema => '结构类';

  @override
  String get aiSkillGroupOps => '运维类';

  @override
  String get aiSkillNl2sqlName => '自然语言转 SQL';

  @override
  String get aiSkillNl2sqlDesc => '用自然语言描述需求，生成 SQL';

  @override
  String get aiSkillSqlExplainName => 'SQL 解释';

  @override
  String get aiSkillSqlExplainDesc => '逐段解释一条 SQL 的作用';

  @override
  String get aiSkillSqlExplainPrompt => '请逐段解释这条 SQL 的作用：\n```\n\n```';

  @override
  String get aiSkillQueryOptimizerName => '查询优化';

  @override
  String get aiSkillQueryOptimizerDesc => '分析慢查询并给出优化建议';

  @override
  String get aiSkillQueryOptimizerPrompt => '请分析这条查询的性能问题并给出优化建议：\n```\n\n```';

  @override
  String get aiSkillDataCleaningName => '数据清洗建议';

  @override
  String get aiSkillDataCleaningDesc => '针对表中的脏数据给出清洗建议';

  @override
  String get aiSkillDataCleaningPrompt => '我表里存在脏数据，请针对以下问题给出清洗步骤：';

  @override
  String get aiSkillImportMappingName => '导入映射生成';

  @override
  String get aiSkillImportMappingDesc => '为数据导入生成列映射';

  @override
  String get aiSkillImportMappingPrompt =>
      '请生成把以下文件导入目标表的列映射（JSON）。\n源文件列：\n目标表列：';

  @override
  String get aiSkillSchemaAnalysisName => 'Schema 分析';

  @override
  String get aiSkillSchemaAnalysisDesc => '审视当前库的表结构并指出风险';

  @override
  String get aiSkillSchemaAnalysisPrompt => '请审视当前库的表结构，指出设计风险与改进建议。';

  @override
  String get aiSkillSchemaDiffName => '结构比对助手';

  @override
  String get aiSkillSchemaDiffDesc => '比较两段结构定义并输出 diff';

  @override
  String get aiSkillSchemaDiffPrompt =>
      '请比较以下两段结构定义并输出 unified diff：\n<schema-a>\n\n</schema-a>\n<schema-b>\n\n</schema-b>';

  @override
  String get aiSkillIndexSuggestName => '索引建议';

  @override
  String get aiSkillIndexSuggestDesc => '针对查询或表给出索引建议';

  @override
  String get aiSkillIndexSuggestPrompt => '请针对这条查询给出索引建议并说明理由：\n```\n\n```';

  @override
  String get aiSkillErrorDiagnosisName => '错误诊断';

  @override
  String get aiSkillErrorDiagnosisDesc => '诊断数据库报错';

  @override
  String get aiSkillErrorDiagnosisPrompt => '请诊断这个数据库报错并给出修复方案：\n```\n\n```';

  @override
  String get aiSkillSlowQueryName => 'Slow Query 分析';

  @override
  String get aiSkillSlowQueryDesc => '分析慢查询日志';

  @override
  String get aiSkillSlowQueryPrompt => '请分析这条慢查询日志并定位瓶颈：\n```\n\n```';

  @override
  String get aiContextPanelTitle => '上下文';

  @override
  String get aiContextConnectionSection => '当前连接';

  @override
  String get aiContextDatabaseSection => '当前数据库';

  @override
  String get aiContextNoConnection => '未选择连接';

  @override
  String get aiContextSchemaContext => '附加 Schema 上下文';

  @override
  String get aiContextSchemaContextDesc => '发送时附带当前库的表结构信息';

  @override
  String get aiPanelOpenSkillCatalog => '技能目录';

  @override
  String get aiPanelOpenContextPanel => '上下文面板';

  @override
  String get safetyBannerAddLimit => '追加 LIMIT';

  @override
  String safetyBannerCooldown(int seconds) {
    return '确认（${seconds}s）';
  }

  @override
  String get safetyDmlAllRowsWarning => '此操作将影响所有匹配行，建议附加 LIMIT 子句。';

  @override
  String get safetySeverityHigh => '高危';

  @override
  String get safetySeverityMedium => '警告';

  @override
  String get safetySeverityLow => '信息';

  @override
  String get safetySeverityPolicy => '策略';

  @override
  String gateTitleSingle(int count) {
    return '执行确认：此 SQL 存在 $count 项风险';
  }

  @override
  String gateTitleMulti(int count, int total) {
    return '执行确认：$total 条语句中发现 $count 项风险';
  }

  @override
  String get gateDdlImpactTitle => 'DDL 影响分析';

  @override
  String gateStatementLabel(int n) {
    return '语句 $n';
  }

  @override
  String get gateSuggestionLabel => '建议修复';

  @override
  String gateOverview(int total, int high, int medium, int low, int ok) {
    return '$total 条语句 · 高危 $high · 警告 $medium · 信息 $low · 通过 $ok';
  }

  @override
  String gateSkipHighRisk(int skip, int exec) {
    return '跳过 $skip 条高危，执行 $exec 条';
  }

  @override
  String get gateAllHighDisabled => '全部为高危——无可执行语句';

  @override
  String get gateApplySuggestions => '采用全部建议';

  @override
  String get gateProceed => '知情继续执行';

  @override
  String get gateProceedAll => '全部继续执行';

  @override
  String get gateCancelAll => '全部取消';

  @override
  String get settingsNavAppearance => '外观';

  @override
  String get settingsNavAi => 'AI 配置';

  @override
  String get settingsNavQuery => '查询';

  @override
  String get settingsNavLanguage => '语言';

  @override
  String get settingsNavSecurity => '安全';

  @override
  String get settingsNavAbout => '关于';

  @override
  String get piiExportStepFormat => '格式';

  @override
  String get piiExportStepScan => 'PII 检测';

  @override
  String get piiExportStepConfirm => '确认';

  @override
  String get piiExportNoPiiTitle => '未检测到 PII 数据';

  @override
  String get piiExportNoPiiSubtitle => '所有列将原值导出';

  @override
  String piiExportDetectedCount(int count) {
    return '检测到 $count 个含 PII 的列';
  }

  @override
  String get piiExportHighSensitivity => '（高敏感）';

  @override
  String get piiExportKeep => '保留';

  @override
  String get piiExportMask => '掩码';

  @override
  String get piiExportHash => '哈希';

  @override
  String get piiExportDrop => '删除此列';

  @override
  String get piiExportReadyTitle => '准备导出';

  @override
  String get piiExportSummaryFormat => '格式';

  @override
  String get piiExportSummaryRows => '行数';

  @override
  String get piiExportSummaryPiiColumns => 'PII 处理列数';

  @override
  String get piiExportFootnote => 'PII 列将按所选方式处理，非 PII 列原值导出';

  @override
  String get serverBarNotConnected => '未连接';

  @override
  String get serverBarConnecting => '连接中…';

  @override
  String get serverBarLocal => '本地';

  @override
  String get serverBarConnected => '已连接';

  @override
  String get serverBarReconnecting => '重连中…';

  @override
  String serverBarReconnectingIn(int seconds) {
    return '$seconds 秒后重连…';
  }

  @override
  String serverBarServerUrl(String url) {
    return '服务器：$url';
  }

  @override
  String get serverBarDisconnect => '断开连接';

  @override
  String get serverBarUnknownUser => '未知用户';

  @override
  String get serverConnectUnexpectedError => '发生未知错误。';

  @override
  String get cellViewerCopy => '复制';

  @override
  String cellViewerChars(Object count) {
    return '$count 个字符';
  }

  @override
  String get slowQueryMenuLabel => '慢查询统计';

  @override
  String get slowQueryDialogTitle => '慢查询统计';

  @override
  String slowQueryScopeBanner(int thresholdMs) {
    return '记录经 dbmaster/server 执行且超过 $thresholdMs 毫秒的查询；实例启用原生慢日志采集时另含数据库自身的慢查询（按 source 区分）。';
  }

  @override
  String get slowQueryWindow1h => '近 1 小时';

  @override
  String get slowQueryWindow24h => '近 24 小时';

  @override
  String get slowQueryWindow7d => '近 7 天';

  @override
  String get slowQuerySortTotalMs => '总耗时';

  @override
  String get slowQuerySortCount => '次数';

  @override
  String get slowQuerySortAvgMs => '平均耗时';

  @override
  String get slowQuerySortMaxMs => '最大耗时';

  @override
  String get slowQueryAllConnections => '全部连接';

  @override
  String slowQueryDigestStats(int count, String total, String avg, String max) {
    return '$count 次 · 总 $total · 均 $avg · 峰 $max';
  }

  @override
  String slowQueryLastSeen(String time) {
    return '最近发生 $time';
  }

  @override
  String get slowQueryEmptyTitle => '暂无慢查询';

  @override
  String get slowQueryEmptyBody => '该时间窗内没有超过采样阈值的查询。用 dbmaster 跑些慢的再回来看看。';

  @override
  String get slowQueryLoadFailed => '慢查询统计加载失败。';

  @override
  String get slowQueryRetry => '重试';

  @override
  String slowQueryLoadMore(int shown, int total) {
    return '加载更多（已显示 $shown / 共 $total）';
  }

  @override
  String get slowQueryStatusOk => '正常';

  @override
  String get slowQueryStatusError => '错误';

  @override
  String get slowQueryStatusCancelled => '已取消';

  @override
  String get slowQueryDatabaseLabel => '数据库';

  @override
  String get slowQueryNoPlaintext => '该实例已关闭明文 SQL（仅 digest）。';

  @override
  String get slowQueryCopySql => '复制 SQL';

  @override
  String get slowQueryCopied => '已复制';

  @override
  String get reportsMenuLabel => '报告中心';

  @override
  String get reportsDialogTitle => '报告中心';

  @override
  String get reportsGenerateButton => '生成本期周报';

  @override
  String get reportsGeneratedToast => '周报已生成。';

  @override
  String get reportsExistingToast => '本期周报已存在。';

  @override
  String get reportsEmptyTitle => '暂无报告';

  @override
  String get reportsEmptyBody => '手动生成本期慢查询周报，或等待每周自动生成。';

  @override
  String get reportsLoadFailed => '报告加载失败。';

  @override
  String get reportsRetry => '重试';

  @override
  String reportsLoadMore(int shown, int total) {
    return '加载更多（已显示 $shown / 共 $total）';
  }

  @override
  String get reportsWindowLabel => '统计窗口';

  @override
  String get reportsTruncatedHint => '窗口不完整：更早的采样已被 retention 清理。';

  @override
  String get reportsSamplesLabel => '采样数';

  @override
  String get reportsDistinctLabel => '不同查询';

  @override
  String get reportsTotalTimeLabel => '总耗时';

  @override
  String get reportsErrorsLabel => '错误';

  @override
  String get reportsWowLabel => '较上周';

  @override
  String get reportsTopSection => 'Top 查询';

  @override
  String get reportsByDaySection => '按天分布';

  @override
  String get reportsByConnectionSection => '按连接分布';

  @override
  String get reportsUnknownType => '未知报告类型——原始内容：';

  @override
  String get reportsAnalyzeWithAi => 'AI 分析';

  @override
  String get connectFailureTitle => '无法连接';

  @override
  String get connectFailureFileLocked => '文件正被其他程序占用。请关闭占用该文件的程序后重试。';

  @override
  String get connectFailureFileNotFound => '文件不存在，可能已被移动或删除。';

  @override
  String get connectFailurePermissionDenied => '没有访问权限，请检查文件权限后重试。';

  @override
  String get connectFailureNotADatabase => '该文件不是有效的数据库文件。';

  @override
  String get connectFailureCorrupt => '数据库文件似乎已损坏。';

  @override
  String get connectFailureAuthFailed => '认证失败，请检查用户名和密码。';

  @override
  String get connectFailureUnreachable => '无法连接到服务器，请检查地址与网络。';

  @override
  String get connectFailureUnknown => '无法连接到数据库。';

  @override
  String get connectFailureRetry => '重试';

  @override
  String get connectFailureChooseFile => '重新选择文件';

  @override
  String get connectFailureCopyDetails => '复制详情';

  @override
  String get connectFailureTechnicalDetails => '技术详情';

  @override
  String get connectFailureErrorCode => '错误码';

  @override
  String get connectFailureStatement => '出错语句';

  @override
  String get connectFailureFile => '文件';

  @override
  String get connectFailureRawError => '原始异常';

  @override
  String connectFailureLatestTooltip(String message) {
    return '最近连接失败：$message';
  }
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get filterBarApply => '套用';

  @override
  String get filterBarAddCondition => '新增條件';

  @override
  String get filterBarAnd => '且';

  @override
  String get filterBarOr => '或';

  @override
  String get filterBarNoColumns => '無欄位';

  @override
  String get filterBarLoading => '載入中…';

  @override
  String get mongoAutocompleteTitle => 'Mongo 自動補全';

  @override
  String get appTitle => 'DbMaster';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsLanguage => '語言';

  @override
  String get settingsTheme => '主題';

  @override
  String get settingsGeneral => '一般';

  @override
  String get settingsConnection => '連線';

  @override
  String get settingsEditor => '編輯器';

  @override
  String get settingsAbout => '關於';

  @override
  String get connectionNewConnection => '新建連線';

  @override
  String get connectionEditConnection => '編輯連線';

  @override
  String get connectionManageConnection => '管理連線';

  @override
  String get connectionDeleteConnection => '刪除連線';

  @override
  String get connectionConnect => '連線';

  @override
  String get connectionCreateDatabase => '新增資料庫';

  @override
  String get connectionEnableReadOnly => '啟用唯讀';

  @override
  String get connectionDisableReadOnly => '停用唯讀';

  @override
  String connectionMoveToGroup(String groupName) {
    return '移動至 $groupName';
  }

  @override
  String get connectionRemoveFromGroup => '從群組移除';

  @override
  String get connectionCollapseAll => '全部摺疊';

  @override
  String get connectionDisconnect => '斷開';

  @override
  String get connectionTestConnection => '測試連線';

  @override
  String get connectionConnectionName => '連線名稱';

  @override
  String get connectionHost => '主機';

  @override
  String get connectionPort => '連接埠';

  @override
  String get connectionUsername => '使用者名稱';

  @override
  String get connectionPassword => '密碼';

  @override
  String get connectionDatabase => '資料庫';

  @override
  String get connectionEnvironment => '環境';

  @override
  String get connectionEnvironmentNone => '未指定';

  @override
  String get commonSave => '儲存';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDelete => '刪除';

  @override
  String get commonEdit => '編輯';

  @override
  String get commonAdd => '新增';

  @override
  String get commonClose => '關閉';

  @override
  String get commonConfirm => '確認';

  @override
  String get commonSearch => '搜尋';

  @override
  String get commonRefresh => '重新整理';

  @override
  String get commonLoading => '載入中...';

  @override
  String get commonNoData => '無資料';

  @override
  String get commonSuccess => '成功';

  @override
  String get commonError => '錯誤';

  @override
  String get commonWarning => '警告';

  @override
  String get tableNewTable => '新建資料表';

  @override
  String get tableEditTable => '編輯資料表';

  @override
  String get tableDeleteTable => '刪除資料表';

  @override
  String get tableTableName => '資料表名稱';

  @override
  String get tableColumns => '欄位';

  @override
  String get tableIndexes => '索引';

  @override
  String get tablePrimaryKey => '主鍵';

  @override
  String get tableForeignKey => '外鍵';

  @override
  String get tableRenameTable => '重新命名表';

  @override
  String get tableNewTableName => '新表名';

  @override
  String get queryExecute => '執行';

  @override
  String get queryExecuteSelected => '執行選取';

  @override
  String get queryFormat => '格式化';

  @override
  String get queryClear => '清除';

  @override
  String get queryHistory => '歷史';

  @override
  String get queryResults => '結果';

  @override
  String get sidebarConnections => '連線';

  @override
  String get sidebarDatabases => '資料庫';

  @override
  String get sidebarTables => '資料表';

  @override
  String get sidebarKeys => '鍵';

  @override
  String get sidebarCollections => '集合';

  @override
  String get sidebarSuperTables => '超級表';

  @override
  String get sidebarViews => '檢視';

  @override
  String get sidebarSavedQueries => '已保存的查詢';

  @override
  String get sidebarProcedures => '預存程序';

  @override
  String get sidebarTriggers => '觸發程序';

  @override
  String get sidebarFunctions => '函數';

  @override
  String get sidebarServer => '伺服器';

  @override
  String get sidebarProcessList => '處理程序清單';

  @override
  String get sidebarServerStatus => '伺服器狀態';

  @override
  String get sidebarNoUsers => '無使用者';

  @override
  String get sidebarNoActiveProcesses => '無活動處理程序';

  @override
  String sidebarTdColsTags(int cols, int tags) {
    return '$cols 欄，$tags 標籤';
  }

  @override
  String sidebarTdColumnsCount(int count) {
    return '欄（$count）';
  }

  @override
  String sidebarTdTagsCount(int count) {
    return '標籤（$count）';
  }

  @override
  String get sidebarTdDeleteTitle => '刪除超級表';

  @override
  String sidebarTdDeleteConfirm(String name) {
    return '確定要刪除超級表「$name」嗎？\n\n這也會刪除其所有子表！';
  }

  @override
  String get sidebarDeleteGroup => '刪除分組';

  @override
  String get sidebarDeleteGroupPrompt => '選擇要刪除的分組：';

  @override
  String get sidebarConnectionSwitch => '切換連線';

  @override
  String get sidebarSelectConnectionHint => '從上方連線選擇器選擇一個連線開始';

  @override
  String get sidebarConnectionNone => '暫無連線';

  @override
  String get sidebarManageConnections => '管理連線…';

  @override
  String get sidebarExtensions => 'Extensions';

  @override
  String get noExtensionsInstalled => 'No extensions installed';

  @override
  String get sidebarSchemas => '模式';

  @override
  String get sidebarMaterializedViews => '物化檢視';

  @override
  String get sidebarSequences => '序列';

  @override
  String get settingsGeneralSettings => '常規設置';

  @override
  String get settingsAppearanceSettings => '外觀';

  @override
  String get settingsEditorSettings => '編輯器設置';

  @override
  String get settingsEnableAutocomplete => '啟用自動完成';

  @override
  String get settingsAutocompleteDescription => '自動建議SQL關鍵字和表名';

  @override
  String get settingsAiSettings => 'AI設置';

  @override
  String get settingsAutoExecuteSql => '自動執行SQL';

  @override
  String get settingsAutoExecuteSqlDescription => '打開標籤頁時自動執行SQL';

  @override
  String get settingsThemeSettings => '主題';

  @override
  String get settingsDarkMode => '深色';

  @override
  String get settingsLightMode => '淺色';

  @override
  String get shortcutCategoryFile => '檔案';

  @override
  String get shortcutCategoryEdit => '編輯';

  @override
  String get shortcutCategoryView => '檢視';

  @override
  String get shortcutCategoryAi => 'AI';

  @override
  String get shortcutCategoryTab => '標籤頁';

  @override
  String get shortcutNewConnection => '新建連線';

  @override
  String get shortcutNewTab => '新建標籤頁';

  @override
  String get shortcutCloseTab => '關閉標籤頁';

  @override
  String get shortcutSaveQuery => '儲存查詢';

  @override
  String get shortcutExportData => '匯出資料';

  @override
  String get shortcutExecuteQuery => '執行查詢';

  @override
  String get shortcutExecuteQueryNewTab => '在新標籤頁中執行';

  @override
  String get shortcutFormatSql => '格式化SQL';

  @override
  String get shortcutFind => '尋找';

  @override
  String get shortcutReplace => '取代';

  @override
  String get shortcutAutocomplete => '自動完成';

  @override
  String get shortcutUndo => '復原';

  @override
  String get shortcutRedo => '重做';

  @override
  String get shortcutToggleSidebar => '切換側邊欄';

  @override
  String get shortcutToggleAiPanel => '切換AI面板';

  @override
  String get shortcutCommandPalette => '命令面板';

  @override
  String get shortcutShortcutHelp => '快捷鍵說明';

  @override
  String get shortcutGenerateSql => '生成SQL';

  @override
  String get shortcutOptimizeSql => '優化SQL';

  @override
  String get shortcutExplainSql => '解釋SQL';

  @override
  String get shortcutNextTab => '下一個標籤頁';

  @override
  String get shortcutPreviousTab => '上一個標籤頁';

  @override
  String get shortcutSwitchToTab => '切換到標籤頁';

  @override
  String get shortcutToggleAiFullscreen => 'AI 面板全屏';

  @override
  String get shortcutAuditLog => '查詢稽核日誌';

  @override
  String get shortcutIncreaseOpacity => '提高浮層不透明度';

  @override
  String get shortcutDecreaseOpacity => '降低浮層不透明度';

  @override
  String get tableCreateNewTable => '創建新資料表';

  @override
  String get toolbarBackup => '备份';

  @override
  String get toolbarImport => '导入';

  @override
  String get toolbarExport => '导出';

  @override
  String get sidebarExpand => '展开侧边栏';

  @override
  String get sidebarSettings => '设置';

  @override
  String get sidebarSearchHint => '搜索连接、表、视图...';

  @override
  String sidebarConnectionActive(Object count) {
    return '$count 个连接活跃';
  }

  @override
  String get sidebarNoConnections => '暂无保存的连接';

  @override
  String get sidebarClickToCreateConnection => '点击下方按钮新建连接';

  @override
  String get sidebarCreateConnection => '新建连接';

  @override
  String get resultsExport => '导出';

  @override
  String get resultsSave => '保存';

  @override
  String get resultsDiscard => '放弃';

  @override
  String get resultsNoDataToExport => '没有数据可导出';

  @override
  String get resultsCSV => 'CSV';

  @override
  String get resultsJSON => 'JSON';

  @override
  String get resultsExcel => 'Excel';

  @override
  String get resultsConfirmDiscardChanges => '确认放弃修改';

  @override
  String resultsDiscardChangesMessage(Object count) {
    return '确定要放弃 $count 处修改吗？此操作不可撤销。';
  }

  @override
  String get resultsContinueEditing => '继续编辑';

  @override
  String get resultsDiscardChanges => '放弃修改';

  @override
  String get resultsConfirmExecuteSQL => '确认执行SQL';

  @override
  String get resultsBarChart => '柱状图';

  @override
  String get resultsLineChart => '折线图';

  @override
  String get resultsPieChart => '饼图';

  @override
  String get resultsSelectAxisFields => '请选择X轴和Y轴字段';

  @override
  String get statusNotConnected => '未连接';

  @override
  String get statusConnected => '已连接';

  @override
  String statusTables(Object count) {
    return '$count 表';
  }

  @override
  String get statusNone => '无';

  @override
  String statusVersion(Object version) {
    return 'v$version';
  }

  @override
  String get backupManagement => '备份管理';

  @override
  String get backupList => '备份列表';

  @override
  String get createBackup => '创建备份';

  @override
  String get noBackupFiles => '暂无备份文件';

  @override
  String get clickCreateBackupTab => '点击\'创建备份\'标签页开始备份';

  @override
  String get importBackup => '导入备份';

  @override
  String get previewContent => '预览内容';

  @override
  String get exportFile => '导出文件';

  @override
  String get restoreBackup => '恢复备份';

  @override
  String get selectBackupToView => '选择一个备份查看详情';

  @override
  String get database => '数据库';

  @override
  String get backupType => '类型';

  @override
  String get backupSize => '大小';

  @override
  String get createdAt => '创建时间';

  @override
  String get tableCount => '表数量';

  @override
  String get description => '描述';

  @override
  String get preview => '预览';

  @override
  String get export => '导出';

  @override
  String get restore => '恢复';

  @override
  String get confirmRestore => '确认恢复';

  @override
  String confirmRestoreMessage(Object name) {
    return '确定要恢复备份 \"$name\" 吗？\n\n这将执行备份文件中的所有 SQL 语句，可能会覆盖现有数据。';
  }

  @override
  String get confirmDelete => '确认删除';

  @override
  String confirmDeleteMessage(Object name) {
    return '确定要删除备份 \"$name\" 吗？\n\n此操作不可撤销。';
  }

  @override
  String get backupFormat => '备份格式';

  @override
  String get backupContent => '备份内容';

  @override
  String get selectTablesHint => '选择表（留空备份所有）';

  @override
  String get advancedOptions => '高级选项';

  @override
  String get includeStructure => '包含表结构';

  @override
  String get includeStructureDesc => 'CREATE TABLE 语句';

  @override
  String get includeData => '包含数据';

  @override
  String get includeDataDesc => 'INSERT 语句或数据行';

  @override
  String get noTablesAvailable => '暂无可用表';

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String tablesSelected(Object count) {
    return '已选择 $count 个表';
  }

  @override
  String get addDropTable => '添加 DROP TABLE';

  @override
  String get useExtendedInsert => '使用扩展 INSERT';

  @override
  String get useExtendedInsertDesc => '多行值合并为一个 INSERT';

  @override
  String get rowLimitPerTable => '每表行数限制（可选）';

  @override
  String get leaveEmptyForNoLimit => '留空表示不限';

  @override
  String get whereCondition => 'WHERE 条件（可选）';

  @override
  String get whereConditionExample => '例如: id > 100';

  @override
  String get enterBackupDescription => '输入备份描述（可选）';

  @override
  String get startBackup => '开始备份';

  @override
  String get backupProgress => '备份进度';

  @override
  String get waitingToStartBackup => '等待开始备份...';

  @override
  String get currentTable => '当前表';

  @override
  String get progressPercent => '进度';

  @override
  String get backupComplete => '备份完成！';

  @override
  String get backupFailed => '备份失败';

  @override
  String get loadBackupListFailed => '加载备份列表失败';

  @override
  String get retry => '重试';

  @override
  String get previewFailed => '预览失败';

  @override
  String get exportedTo => '已导出到';

  @override
  String get backupRestoreSuccess => '备份恢复成功';

  @override
  String get restoreFailed => '恢复失败';

  @override
  String get backupDeleted => '备份已删除';

  @override
  String deleteFailed(Object error) {
    return '删除失败: $error';
  }

  @override
  String get selectBackupFile => '选择备份文件';

  @override
  String get backupImportSuccess => '备份文件导入成功';

  @override
  String importFailed(String error) {
    return '匯入失敗：$error';
  }

  @override
  String get selectAtLeastOneOption => '请至少选择备份结构或数据';

  @override
  String get backupFailedError => '备份失败';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get aiAnalyze => 'AI 分析';

  @override
  String get aiAnalyzeTable => 'AI 分析表';

  @override
  String get aiAnalyzeDatabase => 'AI 分析資料庫';

  @override
  String get aiAnalyzeServer => 'AI 分析伺服器';

  @override
  String get aiAnalyzeErrorResult => 'AI 分析錯誤';

  @override
  String aiAnalyzeNodeFailed(Object error) {
    return 'AI 分析失敗：$error';
  }

  @override
  String get apiSettings => 'API设置';

  @override
  String get clearChat => '清空对话';

  @override
  String get model => '模型';

  @override
  String get enterModelName => '输入模型名称';

  @override
  String get autoExecuteSql => '自动执行SQL';

  @override
  String get autoExecuteSqlDesc => '启用后，AI生成的查询语句将自动执行';

  @override
  String get aiDatabaseAssistant => 'AI 数据库助手';

  @override
  String get aiAssistantDesc => '支持多家大模型厂商\n帮你编写SQL、优化查询、解释数据库结构';

  @override
  String get enterYourQuestion => '输入你的问题...';

  @override
  String configureApiKeyFirst(Object provider) {
    return '请先在设置中配置 $provider 的 API 密钥以启用AI对话功能。\n\n点击右上角设置图标进行配置。';
  }

  @override
  String get generationFailed => '生成失败';

  @override
  String get stepAnalyzeNeeds => '第一步：分析用户需求，确定需要查询的表...';

  @override
  String get stepGetTableSchema => '第二步：获取表的详细建表语句...';

  @override
  String get stepGenerateSql => '第三步：生成SQL语句...';

  @override
  String get analysisResultTables => '分析结果：需要查询的表';

  @override
  String get tableSchemaInfo => '表结构信息';

  @override
  String get operationCancelled => '操作已取消';

  @override
  String get executingSql => '正在执行SQL...';

  @override
  String executeSuccessRows(Object count) {
    return '执行成功，返回 $count 行数据';
  }

  @override
  String get executeFailedError => '执行失败';

  @override
  String get confirmDangerousOperation => '确认执行危险操作?';

  @override
  String get confirmExecuteSql => '确认执行SQL';

  @override
  String get dangerousOperationWarning => '此操作可能会修改或删除数据，请谨慎执行！';

  @override
  String get sqlCopied => 'SQL已复制';

  @override
  String get sqlGenerationComplete => 'SQL生成完成';

  @override
  String get dangerousOperation => '危险操作';

  @override
  String get dangerousOperationDesc => '这是一个危险操作，请谨慎处理';

  @override
  String get taskCompleteDesc => '任务已完成，您可以选择执行或复制SQL';

  @override
  String get generatedSql => '生成的 SQL';

  @override
  String get dangerous => '危险';

  @override
  String get confirmExecute => '確認執行';

  @override
  String get requestTimeout => '请求超时时间';

  @override
  String get seconds => '秒';

  @override
  String get apiSettingsSaved => 'API设置已保存';

  @override
  String get dataImport => '数据导入';

  @override
  String get selectFile => '选择文件';

  @override
  String get noFileSelected => '未选择文件';

  @override
  String get importConfig => '导入配置';

  @override
  String get targetTableName => '目标表名';

  @override
  String get enterTableName => '输入表名';

  @override
  String get includeHeader => '包含表头';

  @override
  String get delimiter => '分隔符';

  @override
  String get overwriteTable => '覆盖表';

  @override
  String get deleteExistingTable => '（删除已存在的表）';

  @override
  String get batchSize => '批量大小';

  @override
  String dataPreviewRows(Object count) {
    return '数据预览（$count 行）';
  }

  @override
  String get pleaseSelectFile => '请选择文件以预览数据';

  @override
  String get importProgress => '导入进度';

  @override
  String get importPreparing => '导入准备中...';

  @override
  String get totalRecords => '总数';

  @override
  String get importedRecords => '已导入';

  @override
  String get failedRecords => '失败';

  @override
  String get readyToImport => '准备导入';

  @override
  String get importingData => '正在导入数据...';

  @override
  String get importComplete => '导入完成！';

  @override
  String get parseFileFailed => '解析文件失败';

  @override
  String get noDataToImport => '没有可导入的数据';

  @override
  String get selectDatabaseFirst => '请先选择一个数据库';

  @override
  String get importFailedError => '导入失败';

  @override
  String get startImport => '开始导入';

  @override
  String get importing => '导入中...';

  @override
  String get optimizeSql => '优化SQL';

  @override
  String get explainQuery => '解释查询';

  @override
  String get generateInsert => '生成INSERT';

  @override
  String get generateUpdate => '生成UPDATE';

  @override
  String get generateDelete => '生成DELETE';

  @override
  String get createTableStatement => '建表语句';

  @override
  String get securityCheck => '安全检测';

  @override
  String get indexSuggestion => '索引建议';

  @override
  String get executionPlan => '执行计划';

  @override
  String get pleaseEnterSql => '请先输入SQL语句';

  @override
  String get pleaseConnectDatabase => '请先连接数据库';

  @override
  String get analysisFailed => '分析失败';

  @override
  String get loadHistoryFailed => '加载历史失败';

  @override
  String get noQueryHistory => '暂无查询历史记录\n\n执行SQL查询后，历史记录将保存在这里。';

  @override
  String queryHistoryRecords(Object count) {
    return '查询历史记录（最近 $count 条）';
  }

  @override
  String get databaseType => '数据库类型';

  @override
  String get server => '服务器';

  @override
  String get currentDatabase => '当前数据库';

  @override
  String get notConnected => '未连接';

  @override
  String get notSelected => '未选择';

  @override
  String get tableName => '表名';

  @override
  String get tableStructureInfo => '表结构信息';

  @override
  String get createStatement => '建表语句';

  @override
  String andMoreTables(Object count) {
    return '... 还有 $count 个表';
  }

  @override
  String get primaryKey => '主键';

  @override
  String get executionTime => '执行时间';

  @override
  String get status => '状态';

  @override
  String get commonFailed => '失败';

  @override
  String get format => '格式';

  @override
  String get connectionDefaultDatabase => '默认数据库';

  @override
  String get connectionSavePassword => '保存密码';

  @override
  String get connectionAdvancedOptions => '高级选项';

  @override
  String get connectionTimeout => '超时(秒)';

  @override
  String get connectionUseSSL => '使用 SSL/TLS';

  @override
  String get connectionEnableSecureConnection => '启用安全连接';

  @override
  String get connectionUseTls => '使用 TLS/SSL';

  @override
  String get connectionUseTlsDesc => '經 server 端建立 TLS 加密連線';

  @override
  String get connectionTlsInsecure => '忽略憑證校驗（不安全）';

  @override
  String get connectionTlsInsecureDesc => '不校驗伺服器端憑證，僅限可信/測試環境';

  @override
  String get connectionSshSubtitleGateway =>
      'SSH 通道由 dbmaster server 端建立（設定隨連線下發）';

  @override
  String get connectionAutoReconnect => '自动重连';

  @override
  String get connectionAutoReconnectDesc => '连接断开时自动尝试重连';

  @override
  String get connectionCharset => '字元集';

  @override
  String get connectionTimezone => '時區';

  @override
  String get connectionTestSuccess => '连接成功!';

  @override
  String connectionTestFailed(String error) {
    return '连接失败';
  }

  @override
  String get connectionDatabaseType => '数据库类型';

  @override
  String get connectionManager => '连接管理';

  @override
  String get connectionSavedConnections => '已保存的连接';

  @override
  String get connectionNoSavedConnections => '暂无保存的连接';

  @override
  String get connectionCurrent => '当前';

  @override
  String get connectionConnected => '已连接';

  @override
  String get connectionSwitchToConnection => '切换到此连接';

  @override
  String get connectionCloneConnection => '复制连接';

  @override
  String get connectionCloned => '已复制连接';

  @override
  String get connectionDeleteConnectionTitle => '删除连接';

  @override
  String get connectionDeleteConnectionConfirm => '确定要删除连接';

  @override
  String get connectionDisconnectAll => '断开全部';

  @override
  String get searchDialogTitle => '查询';

  @override
  String get searchHint => '搜索表、视图、存储过程、列...';

  @override
  String get searchNoResults => '未找到对象';

  @override
  String get searchTryDifferentKeywords => '尝试不同的关键词';

  @override
  String get searchNavigate => '导航';

  @override
  String get searchSelect => '选中';

  @override
  String get searchClose => '关闭';

  @override
  String searchResultsCount(Object count) {
    return '$count 个结果';
  }

  @override
  String get searchTypeConnection => '连接';

  @override
  String get searchTypeDatabase => '数据库';

  @override
  String get searchTypeTable => '表';

  @override
  String get searchTypeView => '视图';

  @override
  String get searchTypeProcedure => '存储过程';

  @override
  String get searchTypeColumn => '列';

  @override
  String get savedQueriesTitle => '已保存的查询';

  @override
  String get savedQueriesNoQueries => '暂无保存的查询';

  @override
  String get savedQueriesDeleteTitle => '删除查询';

  @override
  String get savedQueriesDeleteConfirm => '确定要删除此查询吗？';

  @override
  String get savedQueriesOpen => '打开';

  @override
  String get viewJson => '檢視 JSON';

  @override
  String get extractFieldAsColumn => '擷取欄位為列';

  @override
  String get erDiagramTitle => 'ER 圖';

  @override
  String get erDiagramSearchTables => '搜尋資料表...';

  @override
  String get erDiagramHierarchicalLayout => '层級佈局';

  @override
  String get erDiagramForceDirectedLayout => '力導向佈局';

  @override
  String get erDiagramCircleLayout => '圆形佈局';

  @override
  String get erDiagramResetLayout => '重置佈局';

  @override
  String get erDiagramZoomIn => '放大';

  @override
  String get erDiagramZoomOut => '縮小';

  @override
  String get erDiagramFitToScreen => '適應螢幕';

  @override
  String get erDiagramRelations => '關係';

  @override
  String get erDiagramZoom => '縮放';

  @override
  String get erDiagramShowIsolated => '顯示孤立節點';

  @override
  String get erDiagramExportAsPNG => '匯出為 PNG';

  @override
  String get erDiagramExportAsJPG => '匯出為 JPG';

  @override
  String get erDiagramLoading => '載入 ER 圖中...';

  @override
  String get erDiagramErrorLoading => '載入 ER 圖失敗';

  @override
  String get erDiagramNoData => '無圖資料表數據可用';

  @override
  String get erDiagramRetry => '重試';

  @override
  String get erDiagramSelectConnection => '选择连接';

  @override
  String get erDiagramSelectDatabase => '选择数据库';

  @override
  String get performanceAnalyzerTitle => '性能分析工具';

  @override
  String get performanceAnalyzerSearch => '搜尋...';

  @override
  String get performanceAnalyzerRefresh => '重新整理資料';

  @override
  String get performanceAnalyzerGenerateReport => '產生報告';

  @override
  String get performanceAnalyzerExport => '匯出';

  @override
  String get performanceAnalyzerClose => '關閉';

  @override
  String get performanceAnalyzerNotConnected => '未連線到資料庫';

  @override
  String get performanceAnalyzerNotConnectedDesc => '請先連線到資料庫以使用效能分析功能';

  @override
  String get performanceAnalyzerConfirm => '確定';

  @override
  String get performanceAnalyzerSlowQueryAnalysis => '慢查詢分析';

  @override
  String get performanceAnalyzerIndexAnalysis => '索引分析';

  @override
  String get performanceAnalyzerTableStatistics => '表統計';

  @override
  String get performanceAnalyzerPerformanceReport => '效能報告';

  @override
  String get performanceAnalyzerLoading => '正在分析資料庫效能...';

  @override
  String get performanceAnalyzerLoadFailed => '載入失敗';

  @override
  String get performanceAnalyzerRetry => '重試';

  @override
  String get performanceAnalyzerTimeThreshold => '時間閾值:';

  @override
  String get performanceAnalyzerNoSlowQueries => '沒有找到慢查詢';

  @override
  String get performanceAnalyzerSelectQuery => '選擇一個查詢查看詳情';

  @override
  String get performanceAnalyzerQueryInfo => '查詢資訊';

  @override
  String get performanceAnalyzerExecutionTime => '執行時間';

  @override
  String get performanceAnalyzerDatabase => '資料庫';

  @override
  String get performanceAnalyzerRowsScaned => '掃描行數';

  @override
  String get performanceAnalyzerRowsReturned => '返回行數';

  @override
  String get performanceAnalyzerTimestamp => '執行時間';

  @override
  String get performanceAnalyzerSqlStatement => 'SQL 語句';

  @override
  String get performanceAnalyzerExecutionPlan => '執行計畫';

  @override
  String get performanceAnalyzerOptimizationSuggestions => '最佳化建議';

  @override
  String get performanceAnalyzerFullTableScan => '全表掃描偵測';

  @override
  String get performanceAnalyzerFullTableScanDesc =>
      '查詢使用了全表掃描(type=ALL)，建議在 WHERE 子句的欄位上新增索引';

  @override
  String get performanceAnalyzerFileSort => '檔案排序';

  @override
  String get performanceAnalyzerFileSortDesc =>
      '查詢使用了檔案排序(Using filesort)，建議在 ORDER BY 欄位上新增索引';

  @override
  String get performanceAnalyzerTempTable => '臨時表使用';

  @override
  String get performanceAnalyzerTempTableDesc =>
      '查詢使用了臨時表(Using temporary)，考慮最佳化 GROUP BY 或 DISTINCT 查詢';

  @override
  String get performanceAnalyzerLowScanEfficiency => '掃描效率低';

  @override
  String get performanceAnalyzerNoIssues => '未發現明顯問題';

  @override
  String get performanceAnalyzerNoIssuesDesc => '查詢執行計畫看起來正常';

  @override
  String get performanceAnalyzerIndexTypeDistribution => '索引類型分布';

  @override
  String get performanceAnalyzerNoData => '無資料';

  @override
  String get performanceAnalyzerTotalIndexes => '總索引';

  @override
  String get performanceAnalyzerUsedIndexes => '已使用';

  @override
  String get performanceAnalyzerUnusedIndexes => '未使用';

  @override
  String get performanceAnalyzerIndexes => '個索引';

  @override
  String get performanceAnalyzerColumns => '欄位:';

  @override
  String get performanceAnalyzerCardinality => '基數:';

  @override
  String get performanceAnalyzerTotalTables => '總表數';

  @override
  String get performanceAnalyzerTotalRows => '總行數';

  @override
  String get performanceAnalyzerDataSize => '資料大小';

  @override
  String get performanceAnalyzerIndexSize => '索引大小';

  @override
  String get performanceAnalyzerTotalSize => '總大小';

  @override
  String get performanceAnalyzerTableName => '資料表名稱';

  @override
  String get performanceAnalyzerEngine => '引擎';

  @override
  String get performanceAnalyzerRowCount => '行數';

  @override
  String get performanceAnalyzerPercentage => '占比';

  @override
  String get performanceAnalyzerTableSizeDistribution => '資料表大小分布 (Top 10)';

  @override
  String get performanceAnalyzerDatabasePerformanceReport => '資料庫效能報告';

  @override
  String get performanceAnalyzerGeneratedAt => '產生時間:';

  @override
  String get performanceAnalyzerTableCount => '表數量';

  @override
  String get performanceAnalyzerSlowQueries => '慢查詢';

  @override
  String get performanceAnalyzerSuggestions => '建議';

  @override
  String get performanceAnalyzerImpact => '影響:';

  @override
  String get performanceAnalyzerImpactHigh => '高';

  @override
  String get performanceAnalyzerImpactMedium => '中';

  @override
  String get performanceAnalyzerImpactLow => '低';

  @override
  String get performanceAnalyzerRecommendation => '建議操作:';

  @override
  String get performanceAnalyzerSlowQueriesTop => '慢查詢 Top';

  @override
  String get performanceAnalyzerLargeTableStatistics => '大表統計';

  @override
  String get performanceAnalyzerClickGenerateReport => '點擊\"產生報告\"按鈕開始分析';

  @override
  String get sqlHistoryTitle => 'SQL 历史记录';

  @override
  String get sqlHistoryNoHistory => '暂无历史记录';

  @override
  String get sqlHistoryClose => '关闭';

  @override
  String get sqlHistoryDelete => '删除';

  @override
  String get sqlHistoryConfirmDelete => '确认删除';

  @override
  String get sqlHistoryDeleteConfirm => '确定要删除这条历史记录吗？';

  @override
  String get sqlHistoryJustNow => '刚刚';

  @override
  String sqlHistoryMinutesAgo(Object count) {
    return '$count 分钟前';
  }

  @override
  String sqlHistoryHoursAgo(Object count) {
    return '$count 小时前';
  }

  @override
  String sqlHistoryDaysAgo(Object count) {
    return '$count 天前';
  }

  @override
  String get aiPanelApiSettings => 'API 设置';

  @override
  String get aiPanelApiKey => 'API Key';

  @override
  String get aiPanelEnterApiKey => '输入API密钥';

  @override
  String get aiPanelApiBaseUrl => 'API Base URL (可选)';

  @override
  String get aiPanelCustomApiUrl => '自定义API地址';

  @override
  String get aiPanelRequestTimeout => '请求超时时间:';

  @override
  String get aiPanelSeconds => '秒';

  @override
  String get aiPanelSave => '保存';

  @override
  String get aiPanelApiSettingsSaved => 'API设置已保存';

  @override
  String get aiPanelConfirmDangerousOperation => '确认执行危险操作?';

  @override
  String get aiPanelConfirmExecuteSql => '确认执行SQL';

  @override
  String get aiPanelDangerousOperationWarning => '此操作可能会修改或删除数据，请谨慎执行！';

  @override
  String get aiPanelCancel => '取消';

  @override
  String get aiPanelConfirmExecute => '确认执行';

  @override
  String get aiPanelOperationCancelled => '操作已取消';

  @override
  String get aiPanelExecutingSql => '正在执行SQL...';

  @override
  String aiPanelExecuteSuccess(Object count) {
    return '执行成功，返回 $count 行';
  }

  @override
  String get aiPanelExecuteFailed => '执行失败';

  @override
  String get aiPanelDataPreview => '数据预览';

  @override
  String aiPanelAndMoreRows(Object count) {
    return '还有 $count 行数据';
  }

  @override
  String aiPanelSqlExecutionSuccess(Object count) {
    return 'SQL执行成功，返回 $count 行';
  }

  @override
  String get aiPanelSqlGenerationComplete => 'SQL生成完成';

  @override
  String get aiPanelSqlGenerationCompleteWarning => 'SQL生成完成 ⚠️';

  @override
  String get aiPanelTaskCompleteDesc => '任务已完成，您可以选择执行或复制SQL';

  @override
  String get aiPanelDangerousOperationDesc => '这是一个危险操作，请谨慎处理';

  @override
  String get aiPanelGeneratedSql => '生成的 SQL';

  @override
  String get aiPanelDangerous => '危险';

  @override
  String get aiPanelContinue => '继续';

  @override
  String get aiPanelClose => '关闭';

  @override
  String get aiPanelCopy => '复制';

  @override
  String get aiPanelExecute => '执行';

  @override
  String get aiPanelConfirmExecuteDangerous => '确认执行';

  @override
  String get quickActionsTitle => '快捷操作';

  @override
  String get quickActionsNewTable => '新資料表';

  @override
  String get quickActionsNewQuery => '新查詢';

  @override
  String get quickActionsAiAssistant => 'AI助手';

  @override
  String get quickActionsSelectDatabaseFirst => '請先選擇一個資料庫';

  @override
  String get resultsTabResults => '結果';

  @override
  String get resultsTabMessages => '訊息';

  @override
  String get resultsTabExecutionPlan => '執行計畫';

  @override
  String get resultsTabExecutionDetails => '執行詳情';

  @override
  String get resultsSearchBtn => '搜尋';

  @override
  String get resultsClear => '清除';

  @override
  String get resultsSubmit => '提交';

  @override
  String get resultsSearchResults => '搜尋結果';

  @override
  String get resultsViewTable => '表格';

  @override
  String get resultsViewCard => '卡片';

  @override
  String get resultsViewChart => '圖表';

  @override
  String get resultsViewStatistics => '統計';

  @override
  String get paginationShowing => '顯示';

  @override
  String get paginationRows => '行';

  @override
  String get paginationFirstPage => '第一頁';

  @override
  String get paginationPreviousPage => '上一頁';

  @override
  String get paginationNextPage => '下一頁';

  @override
  String get paginationLastPage => '最後一頁';

  @override
  String get editModeTitle => '編輯模式';

  @override
  String get editModeChanges => '處修改';

  @override
  String get editModeHint => '雙擊編輯 | Enter確認 | Esc取消 | Tab切換';

  @override
  String get resultsNoDataTitle => '無結果資料';

  @override
  String get resultsNoDataMessage => '執行查詢後將顯示結果';

  @override
  String get resultsNoDataCardMessage => '執行查詢後將顯示卡片視圖';

  @override
  String get resultsNoDataChartMessage => '執行查詢後將顯示圖表';

  @override
  String get resultsNoDataStatisticsMessage => '執行查詢後將顯示統計資訊';

  @override
  String get resultsNoDataExecutionPlanMessage => '點擊「執行計畫」按鈕查看查詢執行計畫';

  @override
  String get statisticsTotalRows => '總行數';

  @override
  String get statisticsFieldInfo => '欄位資訊';

  @override
  String get statisticsNumeric => '數值';

  @override
  String get statisticsText => '文字';

  @override
  String get statisticsNumericStats => '數值統計';

  @override
  String get statisticsCount => '數量';

  @override
  String get statisticsSum => '總和';

  @override
  String get statisticsAvg => '平均值';

  @override
  String get statisticsMin => '最小值';

  @override
  String get statisticsMax => '最大值';

  @override
  String get chartXAxis => 'X 軸';

  @override
  String get chartYAxis => 'Y 軸';

  @override
  String get chartType => '類型: ';

  @override
  String get chartCannotGenerate => '無法生成圖表：請確保Y軸欄位包含數值資料';

  @override
  String messagesQuerySuccess(Object cols, Object rows) {
    return '查詢成功，返回 $rows 行，$cols 列';
  }

  @override
  String get messagesExecuteToSeeResults => '執行查詢後將顯示結果資訊';

  @override
  String sqlPreviewWillExecute(Object count, Object table) {
    return '即將對資料表 `$table` 執行以下 $count 條SQL語句：';
  }

  @override
  String get saveErrorNoTab => '無法儲存：目前標籤頁不存在';

  @override
  String get saveErrorCannotExtractTable => '無法儲存：無法從查詢中提取資料表名稱';

  @override
  String saveErrorFailed(Object error) {
    return '儲存失敗: $error';
  }

  @override
  String get exportSelectFormat => '選擇匯出格式';

  @override
  String get toolbarExecute => '執行';

  @override
  String get toolbarStop => '停止';

  @override
  String get toolbarReadOnlyChip => '唯讀';

  @override
  String get toolbarLimitChipTooltip => '此連線的行數限制（自動 LIMIT）';

  @override
  String get toolbarTimeoutChipTooltip => '此連線的查詢逾時';

  @override
  String get toolbarChipFollowSettings => '跟隨設定';

  @override
  String get toolbarChipOff => '關閉';

  @override
  String get toolbarChipFollowConnection => '跟隨連線';

  @override
  String get gridEditBlockedReadOnly => '連線為唯讀，儲存格編輯已停用。';

  @override
  String get gridEditBlockedNoTable => '無法從結果推斷目標表——儲存格編輯需要單表查詢。';

  @override
  String gridEditsCount(Object count, Object rows) {
    return '$count 處修改 · $rows 行';
  }

  @override
  String get gridCommitButton => '提交變更';

  @override
  String get gridDiscardButton => '放棄修改';

  @override
  String gridCommitSuccess(Object rows) {
    return '已寫回 $rows 行';
  }

  @override
  String gridCommitNoPrimaryKey(Object table) {
    return '表 $table 無主鍵，無法寫回。';
  }

  @override
  String gridCommitFailed(Object error) {
    return '寫回失敗：$error';
  }

  @override
  String get statusBarReady => '就緒';

  @override
  String get statusBarExecuting => '執行中';

  @override
  String statusBarElapsed(String duration) {
    return '已耗時 $duration';
  }

  @override
  String statusBarLineCol(int line, int column) {
    return '行 $line, 列 $column';
  }

  @override
  String executionStatusBarRows(int count) {
    return '$count 行';
  }

  @override
  String get executionStatusBarErrorHint => '點擊結果子標籤查看錯誤詳情';

  @override
  String get statusBarConnectionErrorTooltip => '存在未處理的連線錯誤，點擊查看';

  @override
  String get toolbarExecutionPlan => '執行計畫';

  @override
  String get toolbarFormat => '格式化';

  @override
  String get toolbarSave => '儲存';

  @override
  String get splitButton => '分割';

  @override
  String get horizontalSplit => '水平分割';

  @override
  String get verticalSplit => '垂直分割';

  @override
  String get refreshData => '重新整理資料';

  @override
  String get analyzingDatabasePerformance => '正在分析資料庫效能...';

  @override
  String get fullTableScanDetected => '偵測到全表掃描';

  @override
  String get fullTableScanDesc => '查詢使用全表掃描(type=ALL)，建議在WHERE子句欄位新增索引';

  @override
  String get timeThreshold => '時間閾值：';

  @override
  String get searchPlaceholder => '搜尋...';

  @override
  String get closeBtn => '關閉';

  @override
  String get apiSettingsSavedMsg => 'API設定已儲存';

  @override
  String get resultsHeaderExport => '匯出';

  @override
  String get resultsHeaderSearch => '搜尋';

  @override
  String get resultsHeaderClear => '清除';

  @override
  String get resultsHeaderSubmit => '提交';

  @override
  String get connectionStatusConnected => '已連線';

  @override
  String get connectionStatusNotConnected => '未連線';

  @override
  String get selectConnection => '選擇連線...';

  @override
  String get selectDatabase => '選擇資料庫';

  @override
  String get aiQuickActionOptimizeSql => '最佳化SQL';

  @override
  String get aiQuickActionExplainQuery => '解釋查詢';

  @override
  String get aiQuickActionGenerateInsert => '產生INSERT';

  @override
  String get aiQuickActionGenerateUpdate => '產生UPDATE';

  @override
  String get aiQuickActionGenerateDelete => '產生DELETE';

  @override
  String get aiQuickActionCreateTable => '建立資料表';

  @override
  String get aiQuickActionSecurityCheck => '安全性檢查';

  @override
  String get aiQuickActionIndexSuggestion => '索引建議';

  @override
  String get aiQuickActionExecutionPlan => '執行計畫';

  @override
  String get aiQuickActionQueryHistory => '查詢歷史';

  @override
  String get shortcutCategoryQuery => '查詢';

  @override
  String get queryCancelled => '查詢已取消';

  @override
  String queryFailed(Object error) {
    return '查詢失敗: $error';
  }

  @override
  String querySuccessWithTime(Object count, Object time) {
    return '查詢成功，返回 $count 行資料 (${time}ms)';
  }

  @override
  String get cancelingQuery => '正在取消查詢...';

  @override
  String get cancelQueryFailed => '取消查詢失敗';

  @override
  String get confirmCancelTransaction => '確認取消交易';

  @override
  String get confirmCancelTransactionMessage =>
      '目前連線有未提交的異動。取消查詢將會中斷並重新連線，導致異動回復。是否繼續？';

  @override
  String get cancel => '取消';

  @override
  String get explainPlanSuccess => '執行計畫成功取得';

  @override
  String explainPlanFailed(Object error) {
    return '取得執行計畫失敗: $error';
  }

  @override
  String get queryEmptyCannotSave => '查詢內容為空，無法儲存';

  @override
  String get saveQueryTitle => '儲存查詢';

  @override
  String get queryName => '查詢名稱';

  @override
  String get enterQueryName => '輸入查詢名稱';

  @override
  String get saveQueryHint => '將儲存到已儲存查詢列表中（最多20個）';

  @override
  String querySaved(Object name) {
    return '查詢已儲存: $name';
  }

  @override
  String get saveQueryLimitReached => '已達到儲存上限（20個），請先刪除一些查詢';

  @override
  String savedQueryNameExists(Object name) {
    return '儲存查詢名稱 \"$name\" 在目前連線下已存在';
  }

  @override
  String get sqlFormatted => 'SQL 已格式化';

  @override
  String get pleaseEnterSqlCode => '請輸入 SQL 程式碼';

  @override
  String get noConnectedServer => '沒有已連線的伺服器';

  @override
  String get split2Hint => '分割 2 - 輸入 SQL 查詢...';

  @override
  String get toolbarClose => '關閉';

  @override
  String connectedToServer(Object serverName) {
    return '已连接到 $serverName';
  }

  @override
  String openTableDataFailed(Object error) {
    return '打开表数据失败: $error';
  }

  @override
  String queryTable(Object tableName) {
    return '查询 $tableName';
  }

  @override
  String openViewFailed(Object error) {
    return '打开视图失败: $error';
  }

  @override
  String queryView(Object viewName) {
    return '查询 $viewName';
  }

  @override
  String openProcedureFailed(Object error) {
    return '打开存储过程失败: $error';
  }

  @override
  String callProcedure(Object procName) {
    return '调用 $procName';
  }

  @override
  String get cancelConnection => '取消连接';

  @override
  String get deleteConnectionTitle => '删除连接';

  @override
  String deleteConnectionConfirm(Object serverName) {
    return '确定要删除连接 \"$serverName\" 吗？';
  }

  @override
  String get refresh => '刷新';

  @override
  String get createNewTable => '新建表';

  @override
  String get erDiagram => 'ER 图';

  @override
  String get properties => '属性';

  @override
  String get exportStructure => '导出结构';

  @override
  String get dropDatabase => '删除数据库';

  @override
  String get confirmDeleteDatabase => '刪除資料庫';

  @override
  String get confirmDropTable => '刪除表';

  @override
  String typeNameToConfirm(String name) {
    return '輸入 \"$name\" 以確認';
  }

  @override
  String dropDatabaseWarning(String name) {
    return '資料庫 \"$name\" 將被永久刪除。';
  }

  @override
  String objectCountWarning(int count, String type) {
    return '$count 個$type將被銷毀';
  }

  @override
  String get allDataWillBeLost => '所有資料將遺失';

  @override
  String copiedDbStructureToClipboard(Object dbName) {
    return '已复制 $dbName 的结构到剪贴板';
  }

  @override
  String databaseDeleted(Object dbName) {
    return '数据库 $dbName 已删除';
  }

  @override
  String get browseData => '浏览数据';

  @override
  String get editTable => '修改表';

  @override
  String get copyTableName => '复制表名';

  @override
  String get copyColumnName => '複製欄位名稱';

  @override
  String get copyIndexName => '複製索引名稱';

  @override
  String get dropColumn => '刪除欄位';

  @override
  String get editIndex => '編輯索引';

  @override
  String get dropIndex => '刪除索引';

  @override
  String confirmDropColumn(Object column, Object table) {
    return '確定要刪除資料表「$table」中的欄位「$column」嗎？';
  }

  @override
  String confirmDropIndex(Object index) {
    return '確定要刪除索引「$index」嗎？';
  }

  @override
  String columnDropped(Object column) {
    return '已刪除欄位「$column」';
  }

  @override
  String indexDropped(Object index) {
    return '已刪除索引「$index」';
  }

  @override
  String dropColumnFailed(Object error) {
    return '刪除欄位失敗：$error';
  }

  @override
  String dropIndexFailed(Object error) {
    return '刪除索引失敗：$error';
  }

  @override
  String get loadingSchema => '載入中...';

  @override
  String get noColumns => '無欄位';

  @override
  String get noIndexes => '无索引';

  @override
  String get noProgrammableObjects => '此資料庫類型不支援可程式化物件';

  @override
  String get exportData => '导出数据';

  @override
  String get dataSync => '資料同步';

  @override
  String get rename => '重命名';

  @override
  String get truncate => '清空数据';

  @override
  String get dropTable => '删除表';

  @override
  String loadTableStructureFailed(Object error) {
    return '加载表结构失败: $error';
  }

  @override
  String get tableNameCopied => '已复制表名';

  @override
  String copiedTableDataToClipboard(Object tableName) {
    return '已复制 $tableName 的数据到剪贴板';
  }

  @override
  String tableRenamedTo(Object newName) {
    return '表已重命名为 $newName';
  }

  @override
  String renameFailed(Object error) {
    return '重命名失败: $error';
  }

  @override
  String tableTruncated(Object tableName) {
    return '表 $tableName 已清空';
  }

  @override
  String truncateFailed(Object error) {
    return '清空失败: $error';
  }

  @override
  String tableDeleted(Object tableName) {
    return '表 $tableName 已删除';
  }

  @override
  String get analyzeTable => '分析表';

  @override
  String get optimizeTable => '最佳化表';

  @override
  String get checkTable => '檢查表';

  @override
  String confirmAnalyzeTable(Object tableName) {
    return '分析表 $tableName';
  }

  @override
  String confirmAnalyzeTableMessage(Object tableName) {
    return '這將更新資料表 \"$tableName\" 的索引統計資訊。';
  }

  @override
  String confirmOptimizeTable(Object tableName) {
    return '最佳化表 $tableName';
  }

  @override
  String confirmOptimizeTableMessage(Object tableName) {
    return '這將整理資料表 \"$tableName\" 的碎片並回收未使用空間。';
  }

  @override
  String confirmCheckTable(Object tableName) {
    return '檢查表 $tableName';
  }

  @override
  String confirmCheckTableMessage(Object tableName) {
    return '這將檢查資料表 \"$tableName\" 是否有錯誤。';
  }

  @override
  String get optimizeTableWarning => '此操作可能會鎖定資料表，在大型資料表上可能需要較長時間。';

  @override
  String analyzeTableResultTitle(Object tableName) {
    return '分析結果：$tableName';
  }

  @override
  String optimizeTableResultTitle(Object tableName) {
    return '最佳化結果：$tableName';
  }

  @override
  String checkTableResultTitle(Object tableName) {
    return '檢查結果：$tableName';
  }

  @override
  String get maintenanceExecutedSql => '執行的 SQL';

  @override
  String get maintenanceResult => '結果';

  @override
  String maintenanceFailed(Object operation, Object error) {
    return '$operation 失敗：$error';
  }

  @override
  String get indexTypeNormal => '普通';

  @override
  String get indexTypeUnique => '唯一';

  @override
  String get hintIndexColumns => '如: id, name';

  @override
  String get pleaseDefineAtLeastOneColumn => '请至少定义一个列';

  @override
  String tableCreated(Object tableName) {
    return '表 $tableName 创建成功';
  }

  @override
  String createFailed(Object error) {
    return '创建失败: $error';
  }

  @override
  String get tableModified => '表修改成功';

  @override
  String modifyFailed(Object error) {
    return '修改失败: $error';
  }

  @override
  String get noInformation => '无信息';

  @override
  String get truncateTableData => '清空表数据';

  @override
  String get menuCut => '剪切';

  @override
  String get menuCopy => '复制';

  @override
  String get menuPaste => '粘贴';

  @override
  String get menuSelectAll => '全选';

  @override
  String get menuFormatSql => '格式化 SQL';

  @override
  String get menuExecuteQuery => '执行查询';

  @override
  String get commandNewConnection => '新建连接';

  @override
  String get commandNewTab => '新建标签';

  @override
  String get commandExecuteQuery => '执行查询';

  @override
  String get commandFormatSql => '格式化 SQL';

  @override
  String get commandToggleAiPanel => '切换 AI 面板';

  @override
  String get commandQueryHistory => '查询历史';

  @override
  String get commandShortcuts => '快捷键';

  @override
  String get commandSettings => '设置';

  @override
  String get commandCategoryHistory => '歷史';

  @override
  String get commandCategoryHelp => '幫助';

  @override
  String get commandDescNewConnection => '建立新的資料庫連線';

  @override
  String get commandDescNewTab => '建立新的查詢標籤';

  @override
  String get commandDescExecuteQuery => '執行目前的 SQL 查詢';

  @override
  String get commandDescFormatSql => '美化 SQL 程式碼格式';

  @override
  String get commandDescToggleSidebar => '顯示或隱藏側邊欄';

  @override
  String get commandDescToggleAiPanel => '顯示或隱藏 AI 助手面板';

  @override
  String get commandDescQueryHistory => '檢視執行歷史';

  @override
  String get commandDescShortcuts => '檢視所有快捷鍵';

  @override
  String get commandDescSettings => '開啟應用設定';

  @override
  String get searchNavigateKeys => '↑↓/滑鼠';

  @override
  String get menuConnect => '连接';

  @override
  String get menuCancelConnection => '取消连接';

  @override
  String get menuDisconnect => '断开连接';

  @override
  String get menuRefresh => '刷新';

  @override
  String get menuEditConnection => '编辑连接';

  @override
  String get menuCloneConnection => '复制连接';

  @override
  String get menuDeleteConnection => '删除连接';

  @override
  String get addColumn => '添加列';

  @override
  String get addIndex => '添加索引';

  @override
  String get noIndexesClickToAdd => '暂无索引，点击上方按钮添加';

  @override
  String get formatCSV => 'CSV';

  @override
  String get formatJSON => 'JSON';

  @override
  String get formatExcel => 'Excel';

  @override
  String get formatMarkdown => 'Markdown';

  @override
  String get formatSqlInsert => 'SQL INSERT';

  @override
  String get formatCSVDesc =>
      'CSV 是通用的电子表格格式，兼容 Excel、Numbers、Google Sheets 等工具。';

  @override
  String get formatJSONDesc => 'JSON 是结构化数据格式，适合程序读取或 API 接口调用。';

  @override
  String get formatExcelDesc => 'Excel 格式保留数据类型和格式，适合深度数据分析。';

  @override
  String get formatMarkdownDesc => 'Markdown 表格格式适合文档、报告或代码审查中使用。';

  @override
  String get formatSqlInsertDesc => 'SQL INSERT 语句可直接导入到其他数据库，适合数据迁移。';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get hintFormatName => '例如：我的格式';

  @override
  String get hintOptionalDescription => '可选描述';

  @override
  String get formatterSelectPreset => '选择预设';

  @override
  String get formatterFormat => '格式化';

  @override
  String get formatterCopyResult => '复制结果';

  @override
  String get formatterHintInputSql => '在此输入 SQL 代码...';

  @override
  String get formatterSpace => '空格';

  @override
  String get formatterTab => 'Tab';

  @override
  String get formatterIndentSize => '缩进大小';

  @override
  String get formatterMaxLineLength => '最大行长度';

  @override
  String get formatterUppercaseKeywords => '关键字大写';

  @override
  String get formatterAlignKeywords => '对齐关键字';

  @override
  String get formatterPreserveComments => '保留注释';

  @override
  String get formatterNewlineBeforeParentheses => '括号前换行';

  @override
  String get formatterCompactMode => '紧凑模式';

  @override
  String get formatterPosition => '位置';

  @override
  String get formatterEnd => '末尾';

  @override
  String get formatterStart => '开头';

  @override
  String loadFailed(Object error) {
    return '載入失敗';
  }

  @override
  String exportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String timeAgoDays(Object count) {
    return '$count天前';
  }

  @override
  String timeAgoHours(Object count) {
    return '$count小時前';
  }

  @override
  String timeAgoMinutes(Object count) {
    return '$count分鐘前';
  }

  @override
  String get timeAgoJustNow => '剛剛';

  @override
  String get optimizationFullTableScan => '全資料表掃描偵測';

  @override
  String get optimizationFullTableScanDesc =>
      '查詢使用了全資料表掃描(type=ALL)，建議在 WHERE 子句的欄位上新增索引';

  @override
  String get optimizationFilesort => '檔案排序';

  @override
  String get optimizationFilesortDesc =>
      '查詢使用了檔案排序(Using filesort)，建議在 ORDER BY 欄位上添加索引';

  @override
  String get optimizationTemporary => '臨時資料表使用';

  @override
  String get optimizationTemporaryDesc =>
      '查詢使用了臨時資料表(Using temporary)，考慮最佳化 GROUP BY 或 DISTINCT 查詢';

  @override
  String get optimizationLowEfficiency => '掃描效率低';

  @override
  String optimizationLowEfficiencyDesc(
    Object ratio,
    Object rowsExamined,
    Object rowsSent,
  ) {
    return '掃描了 $rowsExamined 行但只返回了 $rowsSent 行，掃描比例為 $ratio:1';
  }

  @override
  String get optimizationNoIssue => '未發現明顯問題';

  @override
  String get optimizationNoIssueDesc => '查詢執行計畫看起來正常';

  @override
  String get optimizationSuggestions => '最佳化建議';

  @override
  String get indexTypeDistribution => '索引類型分布';

  @override
  String get noData => '無數據';

  @override
  String get indexPrimary => '主鍵';

  @override
  String get indexUnique => '唯一';

  @override
  String get indexNormal => '普通';

  @override
  String get totalIndexes => '總索引';

  @override
  String get indexUsed => '已使用';

  @override
  String get indexUnused => '未使用';

  @override
  String indexCount(Object count) {
    return '$count 個索引';
  }

  @override
  String columnCardinality(Object cardinality) {
    return '基數: $cardinality';
  }

  @override
  String columnsLabel(Object columns) {
    return '欄位: $columns';
  }

  @override
  String get totalTables => '總資料表數';

  @override
  String get totalRows => '總行數';

  @override
  String get dataSize => '數據大小';

  @override
  String get indexSize => '索引大小';

  @override
  String get tableSizeDistribution => '資料表大小分布 (Top 10)';

  @override
  String get tableNameLabel => '資料表名';

  @override
  String get tableEngineLabel => '引擎';

  @override
  String get tableRowCountLabel => '行數';

  @override
  String get tableDataSizeLabel => '數據大小';

  @override
  String get tableIndexSizeLabel => '索引大小';

  @override
  String get tableTotalSizeLabel => '總大小';

  @override
  String get tableRatioLabel => '占比';

  @override
  String get databasePerformanceReport => '資料庫效能報告';

  @override
  String databaseLabel(Object name) {
    return '資料庫: $name';
  }

  @override
  String generatedAtLabel(Object time) {
    return '產生時間: $time';
  }

  @override
  String get tableCountLabel => '資料表數量';

  @override
  String get slowQueryCountLabel => '慢查詢';

  @override
  String get suggestionCountLabel => '建議';

  @override
  String impactLevel(Object level) {
    return '影響: $level';
  }

  @override
  String get impactHigh => '高';

  @override
  String get impactMedium => '中';

  @override
  String get impactLow => '低';

  @override
  String get recommendedAction => '建議操作:';

  @override
  String slowQueryTopN(Object count) {
    return '慢查詢 Top $count';
  }

  @override
  String get largeTableStats => '大表統計';

  @override
  String get tabRenameTitle => '重新命名查詢';

  @override
  String get tabRenameHint => '輸入查詢名稱';

  @override
  String get tabRename => '重新命名';

  @override
  String get tabClose => '關閉';

  @override
  String get tabCloseOthers => '關閉其他';

  @override
  String get tabCloseToRight => '關閉右側';

  @override
  String get tabCloseAll => '關閉所有';

  @override
  String get tabDuplicate => '複製標籤頁';

  @override
  String get tabNewTooltip => '新建查詢 (Ctrl+T)';

  @override
  String tabNewQueryTitle(Object count) {
    return '查詢$count';
  }

  @override
  String get confirm => '確定';

  @override
  String get copySuffix => '（副本）';

  @override
  String get triggerTitle => '觸發器';

  @override
  String triggerFailedToLoad(Object error) {
    return '載入觸發器失敗: $error';
  }

  @override
  String get triggerFailedToLoadDefinition => '載入觸發器定義失敗';

  @override
  String get triggerDeleteTitle => '刪除觸發器';

  @override
  String triggerDeleteConfirm(Object name) {
    return '確定要刪除觸發器 \"$name\" 嗎？';
  }

  @override
  String triggerDeleted(Object name) {
    return '觸發器 \"$name\" 已刪除';
  }

  @override
  String triggerDeleteFailed(Object error) {
    return '刪除觸發器失敗: $error';
  }

  @override
  String get triggerCannotDisable => 'MySQL 觸發器無法直接停用。請使用刪除來移除。';

  @override
  String get triggerShowList => '顯示列表';

  @override
  String get triggerGroupByTable => '按表分組';

  @override
  String get triggerSearchHint => '搜尋觸發器...';

  @override
  String get triggerNoTriggers => '未找到觸發器';

  @override
  String get triggerCreate => '建立觸發器';

  @override
  String get triggerViewDefinition => '檢視定義';

  @override
  String get triggerCopyName => '複製名稱';

  @override
  String triggerCopied(Object name) {
    return '已複製 \"$name\" 到剪貼簿';
  }

  @override
  String get triggerNew => '新建觸發器';

  @override
  String triggerDefinition(Object name) {
    return '觸發器: $name';
  }

  @override
  String get formatterSqlFormat => 'SQL 格式化';

  @override
  String get formatterSavePreset => '儲存預設';

  @override
  String get formatterPresetName => '預設名稱';

  @override
  String get formatterCustomPreset => '自訂預設';

  @override
  String get formatterBuiltIn => '內建';

  @override
  String get formatterSaveAsPreset => '儲存目前設定為預設';

  @override
  String get formatterDeletePreset => '刪除預設';

  @override
  String get formatterInput => '輸入';

  @override
  String get formatterOptions => '格式化選項';

  @override
  String get formatterIndent => '縮排';

  @override
  String get formatterKeywords => '關鍵字';

  @override
  String get formatterCommaStyle => '逗號樣式';

  @override
  String get formatterApplyToEditor => '套用到編輯器';

  @override
  String filterTitle(String columnName) {
    return '篩選: $columnName';
  }

  @override
  String get filterEquals => '等於';

  @override
  String get filterNotEquals => '不等於';

  @override
  String get filterContains => '包含';

  @override
  String get filterNotContains => '不包含';

  @override
  String get filterGreaterThan => '大於';

  @override
  String get filterLessThan => '小於';

  @override
  String get filterIsEmpty => '為空';

  @override
  String get filterIsNotEmpty => '不為空';

  @override
  String get filterRegex => '正規表達式';

  @override
  String get filterValue => '值';

  @override
  String get filterEnterValue => '輸入篩選值';

  @override
  String get filterCaseSensitive => '區分大小寫';

  @override
  String get filterTimeFilter => '時間篩選';

  @override
  String get filterToday => '今天';

  @override
  String get filterLast24Hours => '最近24小時';

  @override
  String get filterLast7Days => '最近7天';

  @override
  String get filterLast30Days => '最近30天';

  @override
  String rowCountLabel(Object count) {
    return '$count 列';
  }

  @override
  String get toolbarCodeSnippets => '程式碼片段 (Ctrl+Shift+S)';

  @override
  String get toolbarCloseSplit => '關閉分割';

  @override
  String get editorHintText =>
      '輸入 SQL 查詢... (Ctrl+Space 自動完成, F5/Ctrl+Enter 執行)';

  @override
  String get editorHintTextMongodb => '輸入 MongoDB 查詢... (F5/Ctrl+Enter 執行)';

  @override
  String get editorHintTextRedis => '輸入 Redis 命令... (F5/Ctrl+Enter 執行)';

  @override
  String allStatementsSuccess(int count, int time) {
    return '全部 $count 條語句執行成功 (${time}ms)';
  }

  @override
  String statementsPartialSuccess(
    int success,
    int total,
    int failed,
    int time,
  ) {
    return '$success/$total 條成功, $failed 條失敗 (${time}ms)';
  }

  @override
  String statementsAllSuccess(int count) {
    return '$count 條語句執行成功';
  }

  @override
  String statementsPartialSuccessShort(int success, int total, int failed) {
    return '$success/$total 成功，$failed 失敗';
  }

  @override
  String get aiPanelCustomModel => '自訂模型';

  @override
  String get aiPanelBookmarks => '書籤';

  @override
  String get aiPanelScrollToMessageDeveloping => '滾動到訊息功能開發中';

  @override
  String get aiPanelBranchConversationCreated => '已建立分支對話';

  @override
  String get aiPanelNoConnections => '暫無連線，請在連線管理中建立';

  @override
  String get aiPanelConversationList => '對話列表';

  @override
  String get aiPanelSelectConnection => '選擇連線';

  @override
  String get aiPanelNoConnection => '無連線';

  @override
  String get aiPanelSelectDatabaseFirst => '先選擇連線';

  @override
  String get aiPanelSelectDatabase => '選擇資料庫';

  @override
  String get aiPanelAllDatabases => '所有資料庫';

  @override
  String get aiPanelConnectionFailed => '連線失敗';

  @override
  String get aiPanelUnknownError => '未知錯誤';

  @override
  String get aiPanelLoadDatabasesFailed => '載入資料庫失敗';

  @override
  String get aiPanelDangerousOperation => '危險操作';

  @override
  String get aiPanelOptimizeSql => '最佳化SQL';

  @override
  String get aiPanelSecurityAnalysis => '安全性分析';

  @override
  String get aiPanelExecutionPlan => '執行計畫';

  @override
  String get aiPanelIndexSuggestions => '索引建議';

  @override
  String get aiPanelInputHint => '請輸入您的資料庫問題，例如：如何最佳化這個查詢？';

  @override
  String get aiPanelStop => '停止';

  @override
  String get aiPanelSend => '發送';

  @override
  String get aiPanelSelectConnectionFirst => '請先在上方的下拉框中選擇一個連線實例。';

  @override
  String aiPanelConnectionNotAvailable(Object name) {
    return '連線實例 \"$name\" 未連線或不可用，請先連線該實例。';
  }

  @override
  String get aiPanelTable => '表';

  @override
  String get aiPanelDangerousOperationBadge => '危險操作';

  @override
  String get aiPanelThinkingProcess => '思考過程';

  @override
  String get aiPanelExpandThinking => '展開思考過程';

  @override
  String get aiPanelCollapseThinking => '收起思考過程';

  @override
  String get aiPanelRenameSession => '重新命名對話';

  @override
  String get aiPanelSessionTitle => '對話標題';

  @override
  String get aiPanelDeleteSession => '刪除對話';

  @override
  String aiPanelDeleteSessionConfirm(Object name) {
    return '確定要刪除 \"$name\" 嗎？';
  }

  @override
  String get aiPanelRename => '重新命名';

  @override
  String get aiPanelUnarchive => '取消歸檔';

  @override
  String get aiPanelArchive => '歸檔';

  @override
  String get aiPanelSessions => '對話';

  @override
  String get aiPanelSearchSessions => '搜尋對話';

  @override
  String get aiPanelNoSessions => '暫無對話';

  @override
  String aiPanelArchivedSessions(Object count) {
    return '歸檔對話 ($count)';
  }

  @override
  String get aiPanelJustNow => '剛剛';

  @override
  String aiPanelMinutesAgo(Object count) {
    return '$count分鐘前';
  }

  @override
  String aiPanelHoursAgo(Object count) {
    return '$count小時前';
  }

  @override
  String aiPanelDaysAgo(Object count) {
    return '$count天前';
  }

  @override
  String get aiPanelSelectProvider => '選擇模型廠商';

  @override
  String aiPanelSelectModelCurrent(Object provider) {
    return '選擇模型 (目前: $provider)';
  }

  @override
  String aiPanelApiConfigCurrent(Object provider) {
    return 'API 設定 (目前: $provider)';
  }

  @override
  String get aiPanelModelProviderMismatch => '所選模型不屬於所選廠商';

  @override
  String get aiPanelAllowSession => '允許本次會話';

  @override
  String get aiPanelNoBookmarks => '暫無書籤';

  @override
  String get aiPanelClickBookmarkIcon => '點擊訊息上的書籤圖示添加';

  @override
  String get aiCmdOptimizeSql => '最佳化SQL語句';

  @override
  String get aiCmdExplainQuery => '解釋查詢計畫';

  @override
  String get aiCmdGenerateCrud => '產生CRUD語句';

  @override
  String get aiCmdAnalyzeTable => '分析表結構';

  @override
  String get aiCmdShowHistory => '查看查詢歷史';

  @override
  String get aiCmdShowBookmarks => '查看書籤';

  @override
  String get aiCmdBranchConversation => '建立分支對話';

  @override
  String get aiCmdListDatabases => '列出所有資料庫';

  @override
  String get aiCmdListTables => '列出所有資料表';

  @override
  String get settingsThemeMode => '主題模式';

  @override
  String get settingsThemeColor => '主題色';

  @override
  String get settingsSystem => '跟隨系統';

  @override
  String get settingsPreview => '預覽效果';

  @override
  String get settingsPrimaryButton => '主要按鈕';

  @override
  String get settingsSecondaryButton => '次要按鈕';

  @override
  String get settingsApply => '應用';

  @override
  String get colorBlue => '藍色';

  @override
  String get colorPurple => '紫色';

  @override
  String get colorGreen => '綠色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorRed => '紅色';

  @override
  String get colorCyan => '青色';

  @override
  String get colorPink => '粉色';

  @override
  String get colorYellow => '黃色';

  @override
  String get aiChatPageTitle => 'AI 助手';

  @override
  String get messageLabelYou => '你';

  @override
  String get messageLabelAi => 'AI';

  @override
  String get messageStatusSending => '發送中';

  @override
  String get messageStatusGenerating => '生成中';

  @override
  String get messageStatusFailed => '失敗';

  @override
  String get messageStatusCancelled => '已取消';

  @override
  String get messageStatusError => '出錯了';

  @override
  String get messageStatusThinking => '思考中';

  @override
  String tokenUsagePrompt(int count) {
    return '輸入 $count';
  }

  @override
  String tokenUsageCompletion(int count) {
    return '輸出 $count';
  }

  @override
  String tokenUsageTotal(int count) {
    return '總計 $count';
  }

  @override
  String sessionTokenUsage(
    int promptTokens,
    int completionTokens,
    int totalTokens,
  ) {
    return '會話：輸入 $promptTokens · 輸出 $completionTokens · 總計 $totalTokens';
  }

  @override
  String get messageActionRegenerate => '重新生成';

  @override
  String get tooltipCopyCode => '複製程式碼';

  @override
  String get tooltipExecuteCode => '執行程式碼';

  @override
  String get messageCopied => '已複製';

  @override
  String toolCallTitle(String name) {
    return '工具: $name';
  }

  @override
  String toolResultTitle(String name) {
    return '結果: $name';
  }

  @override
  String get toolCallCompleted => '已呼叫並完成';

  @override
  String get toolParamLabel => '參數';

  @override
  String get toolResultLabel => '結果';

  @override
  String get toolGroupTitle => '工具執行組';

  @override
  String toolGroupSummary(int count) {
    return '執行了 $count 個工具';
  }

  @override
  String toolGroupItemTitle(int index, String name) {
    return '工具 $index: $name';
  }

  @override
  String get toolNoParams => '無參數';

  @override
  String get aiWelcomeTitle => 'AI 資料庫助手';

  @override
  String get aiWelcomeDescription =>
      '我可以幫你寫 SQL、優化查詢、分析表結構、檢查安全問題，或者解答任何資料庫相關的疑問。';

  @override
  String aiConnectedTo(String name) {
    return '已連線: $name';
  }

  @override
  String get aiExampleSectionTitle => '試試這樣問我';

  @override
  String get aiQuickActionsSectionTitle => '快捷操作';

  @override
  String get aiTipQuickSend => 'Ctrl + Enter 快速發送';

  @override
  String get aiTipSlashCommands => '輸入 / 查看所有命令';

  @override
  String get aiExampleQuestion1 => '優化這個查詢的效能';

  @override
  String get aiExampleQuestion2 => '分析目前表結構';

  @override
  String get aiExampleQuestion3 => '檢查這段 SQL 的安全性';

  @override
  String get errorApiKeyRequired => '請先填寫 API Key';

  @override
  String get errorBaseUrlRequired => '請先填寫 Base URL';

  @override
  String errorFetchModelsFailed(String error) {
    return '取得模型列表失敗: $error';
  }

  @override
  String get tooltipRefreshModels => '重新整理模型列表';

  @override
  String get labelCustomModelInput => '手動輸入模型名稱';

  @override
  String get tooltipAddModel => '新增模型';

  @override
  String get hintFetchOrInputModel => '點擊重新整理按鈕取得或手動輸入模型名稱';

  @override
  String get hintFetchModels => '點擊重新整理按鈕取得模型列表';

  @override
  String get errorSelectModelRequired => '請選擇或輸入一個模型';

  @override
  String errorSaveFailed(String error) {
    return '儲存失敗: $error';
  }

  @override
  String connErrorWithMessage(String error) {
    return '錯誤：$error';
  }

  @override
  String get connSearchSnippetsHint => '搜尋程式碼片段...';

  @override
  String get connPreview => '預覽';

  @override
  String get connInsert => '插入';

  @override
  String get connApply => '套用';

  @override
  String get connClearAll => '全部清除';

  @override
  String connSaveConnectionFailed(String error) {
    return '儲存連線失敗：$error';
  }

  @override
  String connDeleteConnectionFailed(String error) {
    return '刪除連線失敗：$error';
  }

  @override
  String get connCreateStatement => '建立語句';

  @override
  String get connCreateStatementCopied => '建立語句已複製';

  @override
  String get connCopyCreateStatement => '複製建立語句';

  @override
  String get connDeleteDatabase => '刪除資料庫';

  @override
  String get connCopiedToClipboard => '已複製到剪貼簿';

  @override
  String get connCopy => '複製';

  @override
  String get connExportFeatureSetup => '匯出功能需要額外設定';

  @override
  String connExportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String connCopiedTableName(String tableName) {
    return '已複製：$tableName';
  }

  @override
  String get connRetry => '重試';

  @override
  String get connReportIssue => '回報問題';

  @override
  String get connEnterTableName => '輸入資料表名稱';

  @override
  String get connParameterName => '參數名稱';

  @override
  String get connClear => '清除';

  @override
  String get connCharset => '字元集';

  @override
  String get connComment => '註解';

  @override
  String get connName => '名稱';

  @override
  String get connDefault => '預設值';

  @override
  String get connIndexName => '索引名稱';

  @override
  String get connTruncate => '截斷';

  @override
  String get dlgProcedureUpdated => '預存程序/函數更新成功';

  @override
  String get dlgProcedureCreated => '預存程序/函數建立成功';

  @override
  String dlgOperationFailed(String error) {
    return '操作失敗：$error';
  }

  @override
  String get dlgType => '類型';

  @override
  String get dlgProcedureType => '程序 (PROCEDURE)';

  @override
  String get dlgFunctionType => '函數 (FUNCTION)';

  @override
  String get dlgReturnType => '回傳類型';

  @override
  String get dlgEnterSqlHint => '輸入 SQL 程式碼...';

  @override
  String dlgExecutionFailed(String error) {
    return '執行失敗：$error';
  }

  @override
  String get dlgExecute => '執行';

  @override
  String get dlgEnterValue => '輸入值';

  @override
  String get dlgCopied => '已複製';

  @override
  String get dlgNoHistory => '尚無歷史記錄';

  @override
  String get dlgConfirmDeleteTitle => '確認刪除';

  @override
  String dlgConfirmDeleteHistoryMessage(String sql) {
    return '確定要刪除此歷史記錄嗎？\n\n$sql';
  }

  @override
  String get dlgTestSyntax => '測試語法';

  @override
  String dlgSyntaxError(String message) {
    return '語法錯誤：$message';
  }

  @override
  String get dlgSyntaxLooksGood => '語法看起來沒問題！';

  @override
  String get dlgEnterTriggerName => '輸入觸發器名稱';

  @override
  String dlgEnterVariableValue(String variable) {
    return '輸入 $variable';
  }

  @override
  String get molChooseFromGallery => '從相簿選擇';

  @override
  String get molTakePhoto => '拍照';

  @override
  String molPickImageFailed(String error) {
    return '選取圖片失敗：$error';
  }

  @override
  String get molSend => '發送';

  @override
  String svcExportSuccess(String result) {
    return '檔案已匯出：$result';
  }

  @override
  String svcExportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String scrInitFailed(String error) {
    return '初始化失敗：$error';
  }

  @override
  String get smartImportTitle => 'AI 智能導入';

  @override
  String get smartImportSubtitle => '自動分析文件結構並導入數據庫';

  @override
  String get smartImportClose => '關閉';

  @override
  String get smartImportTarget => '導入目標';

  @override
  String smartImportSelectedTable(String table) {
    return '已選擇表: $table';
  }

  @override
  String get smartImportAutoInfer => '未選擇表，將由 AI 自動推斷';

  @override
  String get smartImportLoadTables => '加載表列表...';

  @override
  String get smartImportTableHint => '搜索或輸入表名（留空由 AI 推斷）';

  @override
  String get smartImportStepSelectFile => '選擇文件';

  @override
  String get smartImportStepAnalyze => '分析文件';

  @override
  String get smartImportStepImport => '導入數據';

  @override
  String get smartImportStepComplete => '完成';

  @override
  String get smartImportSelectFileTitle => '選擇要導入的文件';

  @override
  String get smartImportSelectFileHint => '點擊選擇 CSV 或 JSON 文件';

  @override
  String get smartImportReselectFile => '點擊重新選擇';

  @override
  String get smartImportSupportedFormats => '支持格式: CSV, TSV, JSON, JSON Lines';

  @override
  String get smartImportAnalyzing => '正在分析文件結構...';

  @override
  String get smartImportTableNotFound => '目標表不存在';

  @override
  String smartImportTableNotFoundMessage(String table) {
    return '表 \"$table\" 在當前數據庫中不存在。';
  }

  @override
  String get smartImportCreateTableHint => '請先在 SQL 編輯器中執行以下建表語句，然後重新打開智能導入。';

  @override
  String get smartImportSuggestedSQL => '建議的建表語句';

  @override
  String get smartImportCopySQL => '複製語句';

  @override
  String get smartImportSQLCopied => '建表語句已複製到剪貼板';

  @override
  String get smartImportImporting => '正在導入數據...';

  @override
  String get smartImportImported => '已導入';

  @override
  String get smartImportTotalRecords => '總數據';

  @override
  String get smartImportFailedRecords => '失敗';

  @override
  String get smartImportProgress => '進度';

  @override
  String get smartImportImportComplete => '導入完成';

  @override
  String get smartImportTargetTable => '目標表';

  @override
  String get smartImportSuccessRows => '成功導入';

  @override
  String get smartImportFailedRows => '失敗跳過';

  @override
  String get smartImportTotalRows => '表當前總行數';

  @override
  String get smartImportImportFailed => '導入失敗';

  @override
  String get smartImportFilePreview => '文件預覽';

  @override
  String get smartImportSampleData => '樣本數據（前3行）';

  @override
  String get smartImportLogs => '導入日誌';

  @override
  String get smartImportClearLogs => '清空';

  @override
  String get smartImportReimport => '重新導入';

  @override
  String get smartImportStartAnalysis => '開始分析';

  @override
  String get smartImportStartImport => '開始導入';

  @override
  String get smartImportCancelImport => '取消導入';

  @override
  String get smartImportUserCancelled => '用戶取消導入';

  @override
  String smartImportFileSelected(String name) {
    return '已選擇檔案：$name';
  }

  @override
  String smartImportAnalysisComplete(
    String format,
    String encoding,
    String fields,
  ) {
    return '文件分析完成。格式: $format, 編碼: $encoding, 字段數: $fields';
  }

  @override
  String smartImportEstimatedRows(String rows) {
    return '估計總行數: ~$rows';
  }

  @override
  String smartImportUsingSelectedTable(String table) {
    return '使用已選擇的表: $table';
  }

  @override
  String get smartImportCheckTableExists => '檢查目標表是否存在...';

  @override
  String smartImportTableExists(String table, String count) {
    return '表 \"$table\" 已存在，當前有 $count 行數據';
  }

  @override
  String smartImportTableNotExists(String table) {
    return '表 \"$table\" 不存在。請先創建表。';
  }

  @override
  String get smartImportAiInferringTable => 'AI 正在推斷表名';

  @override
  String smartImportAiSuggestedTable(String name) {
    return 'AI 建議表名: $name';
  }

  @override
  String get smartImportDoNotImport => '不匯入';

  @override
  String smartImportTaskDescription(int count, String table) {
    return '匯入 $count 到 $table';
  }

  @override
  String smartImportStartImporting(String table) {
    return '開始導入數據到表 \"$table\"...';
  }

  @override
  String smartImportImportResult(String imported, String failed) {
    return '導入完成！成功: $imported 行, 失敗: $failed 行';
  }

  @override
  String get smartImportQueryRowCount => '正在查詢表總行數...';

  @override
  String smartImportTableTotalRows(String table, String count) {
    return '表 \"$table\" 當前共有 $count 行數據';
  }

  @override
  String smartImportQueryCountFailed(String error) {
    return '查詢數量失敗: $error';
  }

  @override
  String smartImportImportError(String error) {
    return '導入失敗: $error';
  }

  @override
  String get smartImportCopySuccess => 'SQL 語句已複製';

  @override
  String smartImportRows(String count) {
    return '$count 行';
  }

  @override
  String get smartImportAiModel => 'AI 模型';

  @override
  String get aiPanelFullscreen => '全屏模式';

  @override
  String get aiPanelExitFullscreen => '退出全屏';

  @override
  String get aiPanelOpenInNewQuery => '已在新查詢中打開';

  @override
  String aiPanelInsertStatementsGenerated(int count, String tableName) {
    return 'AI 已生成 $count 條 INSERT 語句，準備插入到表 [$tableName]。';
  }

  @override
  String get aiPanelSqlPreviewTitle => 'SQL 預覽（前3條）:';

  @override
  String aiPanelMoreStatements(int count) {
    return '... 還有 $count 條語句';
  }

  @override
  String aiAgentToolCallLimitReached(int count) {
    return 'AI助手已達到工具調用上限（$count次）。請簡化您的問題，或分步進行操作。';
  }

  @override
  String get aiAgentMaxIterationsReached => 'Agent 達到最大迭代次數，未能完成對話。';

  @override
  String get aiAgentDuplicateQuery => '該查詢已執行過，請基於已有結果直接回答，不要重複查詢相同信息。';

  @override
  String aiAgentToolExecutionFailed(String error) {
    return '工具執行失敗: $error';
  }

  @override
  String aiAgentUnknownTool(String name) {
    return '未知工具: $name';
  }

  @override
  String aiContextCurrentDatabase(String name) {
    return '當前數據庫: $name';
  }

  @override
  String aiContextCurrentTable(String name) {
    return '當前表: $name';
  }

  @override
  String aiContextRecentQueries(String queries) {
    return '最近查詢: $queries';
  }

  @override
  String aiContextGoalSummary(String summary) {
    return '當前會話目標摘要: $summary';
  }

  @override
  String get taskPanelTitle => '任務';

  @override
  String get taskPanelEmpty => '暫無任務';

  @override
  String get taskPanelEmptyDesc => '導入或導出操作將顯示在這裡';

  @override
  String get taskPanelClearCompleted => '清除已完成';

  @override
  String get taskPanelStatusPending => '等待中';

  @override
  String get taskPanelStatusRunning => '執行中';

  @override
  String get taskPanelStatusPaused => '已暫停';

  @override
  String get taskPanelStatusCompleted => '已完成';

  @override
  String get taskPanelStatusFailed => '失敗';

  @override
  String get taskPanelStatusCancelled => '已取消';

  @override
  String get taskTypeImport => '導入';

  @override
  String get taskTypeExport => '導出';

  @override
  String get taskTypeQuery => '查詢';

  @override
  String get taskActionCancel => '取消';

  @override
  String get taskActionRetry => '重試';

  @override
  String get taskActionRemove => '刪除';

  @override
  String get taskActionOpenFolder => '打開目錄';

  @override
  String get taskCreateExportTitle => '創建導出任務';

  @override
  String get taskCreateExportFormat => '導出格式';

  @override
  String get taskCreateExportPath => '輸出路徑';

  @override
  String get taskCreateExportPathPlaceholder => '點擊右側按鈕選擇保存位置';

  @override
  String get taskCreateExportPathSelect => '選擇保存位置';

  @override
  String get taskCreateExportStart => '創建任務';

  @override
  String get taskValidationPathRequired => '請選擇輸出路徑';

  @override
  String get taskValidationPathNotWritable => '目錄不可寫，請選擇其他位置';

  @override
  String get taskValidationPathExists => '文件已存在，將被覆蓋';

  @override
  String taskStatusBarTasks(int count) {
    return '$count 個任務';
  }

  @override
  String taskStatusBarRunning(int count) {
    return '$count 個執行中';
  }

  @override
  String get taskLogInfo => '信息';

  @override
  String get taskLogWarning => '警告';

  @override
  String get taskLogError => '錯誤';

  @override
  String get taskLogSuccess => '成功';

  @override
  String get taskDetailTitle => '任務詳情';

  @override
  String get taskDetailBasicInfo => '基本信息';

  @override
  String get taskDetailStatistics => '執行統計';

  @override
  String get taskDetailError => '錯誤信息';

  @override
  String get taskDetailOutputFile => '輸出文件';

  @override
  String get taskDetailLogs => '執行日誌';

  @override
  String get taskDetailCopied => '路徑已複製到剪貼板';

  @override
  String get taskPhaseAnalyzing => '正在分析...';

  @override
  String get taskPhaseQuerying => '正在查詢數據...';

  @override
  String get taskPhaseFormatting => '正在格式化數據...';

  @override
  String get taskPhaseWriting => '正在寫入文件...';

  @override
  String get taskPhaseCompleted => '已完成';

  @override
  String get aiExportButtonCreate => '創建導出任務';

  @override
  String get aiExportButtonAnalyzing => '分析中...';

  @override
  String get aiMessageExportAction => '導出此數據';

  @override
  String get smartImportCreateTask => '在後台創建導入任務';

  @override
  String get schemaDiffTitle => 'Schema 比對與同步';

  @override
  String get schemaDiffMenuItem => 'Schema 比對與同步';

  @override
  String get schemaDiffSource => '來源資料庫';

  @override
  String get schemaDiffTarget => '目標資料庫';

  @override
  String get schemaDiffCompareButton => '比對';

  @override
  String get schemaDiffSelectDatabases => '請選擇來源資料庫和目標資料庫進行比對';

  @override
  String get schemaDiffTabOverview => '概覽';

  @override
  String get schemaDiffTabDetails => '詳情';

  @override
  String get schemaDiffTabSync => '同步';

  @override
  String get sidebarColumns => '欄位';

  @override
  String get sidebarIndexes => '索引';

  @override
  String get sidebarInsertIntoEditor => '插入到編輯器';

  @override
  String get sidebarForeignKeys => '外部索引鍵';

  @override
  String get sidebarCopyIndexName => '複製索引名';

  @override
  String get sidebarCopyForeignKeyName => '複製外部索引鍵名稱';

  @override
  String get sidebarCopyName => '複製名稱';

  @override
  String get sidebarReadOnlyConnection => '唯讀連線';

  @override
  String get sidebarCopyColumnName => '複製欄位名稱';

  @override
  String get sidebarCopyColumnType => '複製欄位類型';

  @override
  String get sidebarCopyAllColumnNames => '複製全部欄位名稱';

  @override
  String get sidebarOpenEditorFirst => '請先開啟查詢分頁';

  @override
  String get sidebarEvents => '事件';

  @override
  String get sidebarProgrammableObjects => '可程式化物件';

  @override
  String get selectDatabaseHint => '雙擊資料庫以檢視其物件';

  @override
  String get workspaceEmptyTitle => '沒有開啟的查詢';

  @override
  String get workspaceEmptyHint => '建立新查詢標籤頁以開始工作';

  @override
  String get noSearchResults => '無符合的結果';

  @override
  String get page => '頁面';

  @override
  String get settingsSubscriptionSettings => '訂閱';

  @override
  String get settingsFreePlan => '免費版';

  @override
  String get settingsFreePlanDesc => '您目前使用的是免費版';

  @override
  String get settingsProActivated => 'Pro 已啟用';

  @override
  String get settingsProActivatedDesc => '所有 Pro 功能已解鎖';

  @override
  String get settingsUpgradeToPro => '升級到 Pro';

  @override
  String get settingsRestorePurchases => '恢復購買';

  @override
  String get purchaseDialogTitle => '升級到 Pro';

  @override
  String get purchaseDialogDesc => '訂閱 Pro 解鎖所有進階功能';

  @override
  String get purchaseDialogNoProducts => '暫無可用產品';

  @override
  String freeAiQuotaExceeded(int count) {
    return '本月 $count 次免費 AI 訊息額度已用完。升級到 Pro 即可無限使用 AI。';
  }

  @override
  String freeConnectionLimitReached(int count) {
    return 'Free 計畫最多儲存 $count 個連線。升級到 Pro 以解鎖無限連線。';
  }

  @override
  String freeTabLimitReached(int count) {
    return 'Free 計畫最多同時開啟 $count 個查詢分頁。升級到 Pro 以解鎖無限分頁。';
  }

  @override
  String get schemaDiffSyncProFeature =>
      'Schema Diff 同步是 Pro 功能。開始免費試用或升級到 Pro 以執行同步。';

  @override
  String get tableMetadataComment => 'Comment';

  @override
  String get tableMetadataRowCount => 'Rows';

  @override
  String get tableMetadataDataSize => 'Size';

  @override
  String get tableMetadataEngine => 'Engine';

  @override
  String get tableMetadataUpdateTime => 'Updated';

  @override
  String resultsTruncatedMessage(Object count) {
    return 'Results limited to first $count rows. More data may be available.';
  }

  @override
  String get settingsQueryLimit => 'Query Limit';

  @override
  String get settingsAutoLimitEnabled => 'Auto LIMIT';

  @override
  String get settingsAutoLimitValue => 'Limit Value';

  @override
  String get sidebarFavorites => 'Favorites';

  @override
  String get recentTables => '最近';

  @override
  String get dataSyncTitle => '資料同步';

  @override
  String get dataSyncCancel => '取消';

  @override
  String get dataSyncClose => '關閉';

  @override
  String get dataSyncRestart => '重新同步';

  @override
  String get dataSyncStart => '開始同步';

  @override
  String get dataSyncStatusFailed => '同步失敗';

  @override
  String get dataSyncSourceConfig => '源配置';

  @override
  String get dataSyncSourceConnection => '源連接';

  @override
  String get dataSyncSourceDatabase => '源資料庫';

  @override
  String get dataSyncSourceTable => '源表';

  @override
  String get dataSyncTargetConfig => '目標配置';

  @override
  String get dataSyncTargetConnection => '目標連接';

  @override
  String get dataSyncTargetDatabase => '目標資料庫';

  @override
  String get dataSyncTargetTable => '目標表';

  @override
  String get dataSyncSegmentConfig => '分段配置';

  @override
  String get dataSyncSegmentStrategy => '分段策略';

  @override
  String get dataSyncSegmentTypeNumeric => '數值分段';

  @override
  String get dataSyncSegmentTypeTime => '時間分段';

  @override
  String get dataSyncSegmentField => '分段欄位';

  @override
  String get dataSyncTimeUnit => '時間單位';

  @override
  String get dataSyncTimeUnitMinute => '分鐘';

  @override
  String get dataSyncTimeUnitHour => '小時';

  @override
  String get dataSyncTimeUnitDay => '天';

  @override
  String get dataSyncIntervalValue => '間隔值';

  @override
  String get dataSyncSegmentSize => '每段大小';

  @override
  String get dataSyncAdvancedOptions => '進階選項';

  @override
  String get dataSyncPageSize => '頁大小';

  @override
  String get dataSyncTargetStrategy => '目標策略';

  @override
  String get dataSyncStrategyTruncate => '清空後同步';

  @override
  String get dataSyncStrategyAppend => '追加（忽略衝突）';

  @override
  String get dataSyncStrategyReplace => '覆蓋（REPLACE）';

  @override
  String get dataSyncStrategyUpsert => '衝突時更新';

  @override
  String get dataSyncSegmentIntervalMs => '段間間隔(ms)';

  @override
  String get dataSyncPageIntervalMs => '頁間間隔(ms)';

  @override
  String get dataSyncPleaseCompleteConfig => '請完善所有配置項';

  @override
  String get dataSyncConnectionNotFound => '連接未找到';

  @override
  String dataSyncFailed(String error) {
    return '同步失敗: $error';
  }

  @override
  String get dataSyncCancelledByUser => '用戶取消';

  @override
  String get dataSyncCompleted => '同步完成';

  @override
  String get dataSyncStatusSuccess => '同步成功';

  @override
  String get dataSyncStatusCancelled => '同步已取消';

  @override
  String get dataSyncResultSourceTable => '源表';

  @override
  String get dataSyncResultTargetTable => '目標表';

  @override
  String get dataSyncResultSyncedRows => '已同步行數';

  @override
  String get dataSyncResultFailedRows => '失敗行數';

  @override
  String get dataSyncResultDuration => '總耗時';

  @override
  String dataSyncPleaseSelect(String label) {
    return '請選擇$label';
  }

  @override
  String get dataSyncProgressDetectingSchema => '正在探測表結構...';

  @override
  String get dataSyncProgressCountingRows => '正在統計總行數...';

  @override
  String get dataSyncProgressCalculatingSegments => '正在計算分段...';

  @override
  String get dataSyncProgressEmptyTable => '源表無資料，同步完成';

  @override
  String get dataSyncProgressTruncatingTarget => '正在清空目標表...';

  @override
  String get dataSyncProgressCancelled => '同步已取消';

  @override
  String dataSyncProgressSyncingSegment(int current, int total) {
    return '正在同步第 $current/$total 段...';
  }

  @override
  String dataSyncProgressPageStatus(
    int current,
    int total,
    int synced,
    int totalRows,
  ) {
    return '第 $current/$total 段，已同步 $synced / $totalRows 行';
  }

  @override
  String dataSyncProgressCompleted(int synced, int failed, int skipped) {
    return '同步完成！成功 $synced 行，失敗 $failed 行，跳過 $skipped 行';
  }

  @override
  String dataSyncErrorDateTimeParse(String field, String min, String max) {
    return '欄位 `$field` 的值無法解析為日期時間: min=$min, max=$max';
  }

  @override
  String dataSyncErrorNumericParse(String field, String min, String max) {
    return '欄位 `$field` 的值無法解析為數值: min=$min, max=$max';
  }

  @override
  String get statsToggle => '統計';

  @override
  String get statsChooseColumns => '選擇顯示欄';

  @override
  String get statsApproximateTooltip => '帶 ~ 前綴的為近似值';

  @override
  String statsApproximateValue(String value) {
    return '近似值（~$value）';
  }

  @override
  String get statsExactValue => '精確值';

  @override
  String get statsForeignKeys => 'Foreign Keys';

  @override
  String get statsNoForeignKeys => 'No foreign keys';

  @override
  String dataSyncProgressSynced(int count) {
    return '已同步 $count 行';
  }

  @override
  String dataSyncProgressTotal(int count) {
    return '$count 行';
  }

  @override
  String dataSyncProgressFailed(int count) {
    return '失敗 $count 行';
  }

  @override
  String get unsavedChangesTitle => '未儲存的變更';

  @override
  String get unsavedChangesMessage => '此標籤頁有未儲存的變更，關閉後不儲存？';

  @override
  String get discardChanges => '不儲存';

  @override
  String tabCloseConfirmMessage(String title) {
    return '是否儲存對「$title」的變更？';
  }

  @override
  String get aiPanelOverlayClickMask => 'Click mask';

  @override
  String get aiPanelOverlayCloseOverlay => 'Close overlay';

  @override
  String get aiPanelOverlayDragEdges => 'Drag edges / corners';

  @override
  String get aiPanelOverlayDragToolbar => 'Drag toolbar';

  @override
  String get aiPanelOverlayMoveOverlay => 'Move overlay';

  @override
  String get aiPanelOverlayResizeOverlay => 'Resize overlay';

  @override
  String get aiPanelOverlaySwitchToSidebar => 'Switch to sidebar mode';

  @override
  String get aiPanelOverlayToggleMode => 'Toggle overlay/sidebar mode';

  @override
  String get aiPanelOverlay_aiPanelShortcuts => 'AI panel shortcuts';

  @override
  String get aiSettingsDisclosureTitle => 'About AI Features';

  @override
  String get aiSettingsDisclosureBody =>
      'AI features require your own API Key. All AI requests are sent directly from your device to the AI service provider you choose. DbMaster does not collect your data or relay requests through our servers.';

  @override
  String get exportConnectionsTitle => '匯出連線';

  @override
  String get importConnectionsTitle => '匯入連線';

  @override
  String get exportConnectionsCount => '待匯出連線數';

  @override
  String get exportPasswordHint => '備份密碼';

  @override
  String get confirmExportPasswordHint => '確認備份密碼';

  @override
  String get passwordsDoNotMatch => '密碼不一致';

  @override
  String get importPasswordHint => '備份密碼';

  @override
  String get selectExportFile => '儲存到檔案';

  @override
  String get selectImportFile => '選擇備份檔案';

  @override
  String selectImportFileFailed(String error) {
    return '選擇檔案失敗：$error';
  }

  @override
  String get conflictStrategyLabel => '若連線名稱已存在';

  @override
  String get conflictStrategySkip => '跳過';

  @override
  String get conflictStrategyRename => '重新命名';

  @override
  String get conflictStrategyOverwrite => '覆寫';

  @override
  String get exportSuccess => '連線匯出成功';

  @override
  String get importSuccess => '連線匯入成功';

  @override
  String get invalidPassword => '密碼錯誤';

  @override
  String get invalidFile => '檔案無效或已損毀';

  @override
  String get noConnectionsToExport => '沒有可匯出的連線';

  @override
  String get exportThisConnection => '匯出此連線';

  @override
  String get commandCategoryTools => '工具';

  @override
  String get passwordRequiredTitle => '需要密碼';

  @override
  String passwordRequiredMessage(String serverName) {
    return '請輸入 $serverName 的連線密碼';
  }

  @override
  String get connectionConnectNoPassword => '不使用密碼連線';

  @override
  String get embeddedRequiresRemoteServer => '需要遠端 Server';

  @override
  String get serverSessionExpiredTitle => '會話已過期';

  @override
  String get serverSessionExpiredMessage => '與伺服器的會話已過期或已被撤銷，請重新登入後繼續。';

  @override
  String get serverSessionRelogin => '重新登入';

  @override
  String get serverReconnectLastSession => '重新連線上次的會話';

  @override
  String get serverReconnectFailed => '上次會話已失效，請重新登入。';

  @override
  String sidebarDropViewFailed(String error) {
    return '刪除檢視表失敗：$error';
  }

  @override
  String sidebarDropViewConfirm(String viewName) {
    return '確定要刪除檢視表 \"$viewName\" 嗎？\n\n此動作無法復原。';
  }

  @override
  String get sidebarBrowseData => '瀏覽資料';

  @override
  String get connectionMongoMode => '連線模式';

  @override
  String get connectionMongoModeDirect => '直連（單機）';

  @override
  String get connectionMongoModeReplicaSet => '副本集';

  @override
  String get connectionMongoSeedHosts => '種子節點清單';

  @override
  String get connectionMongoSeedHostsHint =>
      '列出所有副本集成員節點（host:port，每行一個）。驅動自動發現 primary，連線以此清單為準。';

  @override
  String get connectionMongoSeedHostsRequired => '至少需要一個種子節點（host:port）';

  @override
  String get connectionMongoReplicaSetName => '副本集名稱';

  @override
  String get connectionMongoReplicaSetNameRequired => '副本集名稱不可為空';

  @override
  String get connectionMongoModeAdvanced => '進階（連線字串）';

  @override
  String get connectionMongoModeSharded => '分片（mongos）';

  @override
  String get connectionMongoMongosHosts => 'mongos 路由節點';

  @override
  String get connectionMongoMongosHostsHint =>
      '列出所有 mongos 路由節點（host:port，每行一個）。驅動經 mongos 連線，分片透明。';

  @override
  String get connectionMongoMongosHostsRequired =>
      '至少需要一個 mongos 路由節點（host:port）';

  @override
  String get connectionMongoInvalidHostPort => '項目格式無效（應為 host 或 host:port）';

  @override
  String get connectionMongoConnectionString => '連線字串';

  @override
  String get connectionMongoConnectionStringHint =>
      '貼上完整連線字串（mongodb:// 或 mongodb+srv://，含 Atlas）。憑證自動剝離，密碼單獨加密儲存。';

  @override
  String get connectionMongoConnectionStringRequired => '請貼上連線字串';

  @override
  String get connectionMongoConnectionStringInvalid =>
      '無效連線字串（須以 mongodb:// 或 mongodb+srv:// 開頭）';

  @override
  String get connUsernameRequired => '使用者名稱為必填';

  @override
  String get connNameRequired => '連線名稱為必填';

  @override
  String get connHostRequired => '主機為必填';

  @override
  String get connPortRequired => '連接埠為必填';

  @override
  String sidebarDeleteFailed(String error) {
    return '刪除失敗：$error';
  }

  @override
  String get sidebarDropEvent => '刪除事件';

  @override
  String sidebarDropEventConfirm(String name) {
    return '確定要刪除事件 \"$name\" 嗎？\n\n此操作無法復原。';
  }

  @override
  String sidebarEventOperationFailed(String error) {
    return '操作失敗：$error';
  }

  @override
  String get sidebarEventNoDefinition => '無定義';

  @override
  String get sidebarDropSynonym => '刪除同義詞';

  @override
  String sidebarDropSynonymConfirm(String name) {
    return '確定要刪除同義詞 \"$name\" 嗎？\n\n此操作無法復原。';
  }

  @override
  String sidebarSynonymOperationFailed(String error) {
    return '操作失敗：$error';
  }

  @override
  String get sidebarEnableEvent => '啟用事件';

  @override
  String get sidebarDisableEvent => '停用事件';

  @override
  String get sidebarEventProperties => '屬性';

  @override
  String get sidebarSynonyms => '同義詞';

  @override
  String get sidebarBrowseSynonym => '瀏覽同義詞';

  @override
  String get sidebarScriptSynonymAsSelect => '產生 SELECT 腳本';

  @override
  String get viewMenuTitle => '視圖';

  @override
  String get viewMenuToggleSidebar => '左側邊欄';

  @override
  String get viewMenuToggleAiPanel => 'AI 面板';

  @override
  String get viewMenuToggleBottomPanel => '底部面板';

  @override
  String get viewMenuExpandWorkspace => '擴展工作區';

  @override
  String get viewMenuLayoutPresets => '布局預設';

  @override
  String get viewMenuLayoutPresetDefault => '預設';

  @override
  String get viewMenuLayoutPresetExpand => '擴展工作區';

  @override
  String get expandWorkspaceEnabled => '擴展工作區';

  @override
  String get expandWorkspaceDisabled => '退出擴展工作區';

  @override
  String get bottomPanelTabResults => '結果';

  @override
  String get bottomPanelTabLogs => '日誌';

  @override
  String get bottomPanelTabHistory => '歷史';

  @override
  String get bottomPanelTabTasks => '任務';

  @override
  String get dmlCriticalTitle => '極高風險操作';

  @override
  String get dmlHighWarningTitle => '高風險操作';

  @override
  String get dmlHighWarningBody => '此操作將影響所有符合條件的行，建議添加 LIMIT';

  @override
  String get dmlAddLimit => '添加 LIMIT';

  @override
  String get dmlConfirmExecute => '確認執行';

  @override
  String get dmlRiskSummary => '風險摘要';

  @override
  String get dmlStatementsToExecute => '待執行的語句：';

  @override
  String dmlEstimatedAffectedRows(Object count) {
    return '預計影響行數：$count';
  }

  @override
  String dmlSqlInjectionDetail(Object details) {
    return 'SQL 注入：$details';
  }

  @override
  String get dmlTriggerDeleteWithoutWhere => '不含 WHERE 條件的 DELETE';

  @override
  String get dmlTriggerUpdateWithoutWhere => '不含 WHERE 條件的 UPDATE';

  @override
  String get dmlTriggerDropTable => 'DROP TABLE 操作';

  @override
  String get dmlTriggerDropDatabase => 'DROP DATABASE 操作';

  @override
  String get dmlTriggerTruncateTable => 'TRUNCATE TABLE 操作';

  @override
  String get dmlTriggerDmlWithoutLimit => '不含 LIMIT 的 DML';

  @override
  String get dmlTriggerAlterDropColumn => 'ALTER TABLE DROP COLUMN';

  @override
  String get dmlTriggerSqlInjection => '偵測到 SQL 注入模式';

  @override
  String dropTableDeleteConfirmBody(Object tableName) {
    return '確定要刪除表 \"$tableName\" 嗎？';
  }

  @override
  String get dropTableDeleteImpact => '此操作無法復原。表中的所有資料將被永久刪除。';

  @override
  String get dropTableCheckingDependencies => '正在檢查相依性...';

  @override
  String get dropTableDependencyWarning => '相依性警告';

  @override
  String get connectionReadOnlyMode => '唯讀模式';

  @override
  String get connectionReadOnlyModeDesc => '禁止執行 INSERT/UPDATE/DELETE/DDL 操作';

  @override
  String get connectionSshHost => 'SSH 主機';

  @override
  String get connectionSshUsername => 'SSH 使用者名稱';

  @override
  String get connectionSshPassword => 'SSH 密碼';

  @override
  String get connSshHostRequired => 'SSH 主機為必填項';

  @override
  String get commonNavigate => '導覽';

  @override
  String get resultsSqlStatementLabel => 'SQL 語句：';

  @override
  String get resultsExecutionSuccess => '執行成功';

  @override
  String resultsAffectedRows(Object count) {
    return '影響 $count 列';
  }

  @override
  String resultsElapsedMs(Object ms) {
    return '耗時 ${ms}ms';
  }

  @override
  String resultsFilterConditions(Object count) {
    return '篩選：$count 個條件';
  }

  @override
  String resultsShowingRows(Object filtered, Object total) {
    return '顯示 $filtered / $total 列';
  }

  @override
  String get resultsClearFilter => '清除篩選';

  @override
  String get resultsNoDataGuidance => '在編輯器中撰寫查詢，按 Ctrl+Enter（或 F5）執行';

  @override
  String get queryHistoryEmptyHint => '使用 Ctrl+Enter 或 F5 執行查詢後，將自動記錄在這裡';

  @override
  String get safetyExplainWarning => '效能警告';

  @override
  String safetyExplainFullScan(Object rows) {
    return '偵測到全表掃描，預計掃描約 $rows 行';
  }

  @override
  String get safetyExecuteAnyway => '仍然執行';

  @override
  String get safetyCancelAndOptimize => '取消並檢視執行計畫';

  @override
  String get safetyPreflightTimeout => '預檢逾時，跳過效能分析';

  @override
  String get dmlAuditBlocked => 'DML 操作被攔截';

  @override
  String get processListKillQuery => 'Kill Query';

  @override
  String get processListKillConfirmTitle => 'Kill Process';

  @override
  String processListKillConfirm(String id, String user, String host) {
    return 'Kill connection $id ($user@$host)?';
  }

  @override
  String get processListCopyQuery => 'Copy Query';

  @override
  String get processListAutoRefresh => 'Auto-refresh';

  @override
  String get processListRefreshInterval => 'Refresh interval';

  @override
  String get processManagerTitle => '程序管理';

  @override
  String get processListNoProcesses => 'No active processes';

  @override
  String get processListNoQueryText => '無查詢文字';

  @override
  String get engineStatusTitle => 'Engine Status';

  @override
  String get engineInnodbStatus => 'InnoDB Status';

  @override
  String get engineRowFormat => 'Row Format';

  @override
  String get engineCompression => 'Compression';

  @override
  String get engineTablespace => 'Tablespace';

  @override
  String get replicationRunning => 'Replication: Running';

  @override
  String get replicationStopped => 'Replication: Stopped';

  @override
  String replicationLag(int seconds) {
    return 'Lag: ${seconds}s';
  }

  @override
  String get replicationNotConfigured => 'Replication not configured';

  @override
  String get replicationDetailTitle => 'Replication Status';

  @override
  String get replicationIoThread => 'IO Thread';

  @override
  String get replicationSqlThread => 'SQL Thread';

  @override
  String get sidebarServerGlobal => '伺服器';

  @override
  String get sidebarPerformance => '效能';

  @override
  String get sidebarUsers => '使用者';

  @override
  String serverInfoVersion(String version) {
    return 'MySQL $version';
  }

  @override
  String serverInfoUptime(String duration) {
    return '運行時間：$duration';
  }

  @override
  String serverInfoThreads(String active, String running) {
    return '$active 活動連線 / $running 執行中';
  }

  @override
  String serverInfoQueries(String count) {
    return '$count 次查詢';
  }

  @override
  String serverInfoSlowQueries(String count) {
    return '$count 條慢查詢';
  }

  @override
  String get serverVarMaxConnections => '最大連線數';

  @override
  String get serverVarBufferPool => '緩衝池';

  @override
  String get serverVarCharset => '字元集';

  @override
  String get serverStatusUnavailable => '伺服器狀態不可用';

  @override
  String get processListRefreshLabel => '重新整理：';

  @override
  String get processListRefreshOff => '關閉';

  @override
  String processListMore(num count) {
    return '…還有 $count 條';
  }

  @override
  String get usersNoUsers => '找不到使用者';

  @override
  String get usersLocked => '已鎖定';

  @override
  String sidebarDbTableCount(num count) {
    return '$count 個資料表';
  }

  @override
  String get mongoNodeReplication => '複製集';

  @override
  String get mongoNodeSharding => '分片';

  @override
  String get mongoValidationRules => '驗證規則';

  @override
  String get mongoReplicationStandalone => '獨立實例 - 不是副本集的一部分';

  @override
  String get mongoShardingNotSharded => '非分片集群';

  @override
  String get mongoValidationNoRules => '無驗證規則';

  @override
  String get resultColumnTruncated => '值可能被截斷（大物件類型）';

  @override
  String get dorisUpdateGuardMessage =>
      'Doris 的 Duplicate/Aggregate 模型表不支援 UPDATE，僅 Unique/Primary Key 模型支援。';

  @override
  String get dorisTableModelLabel => '表模型';

  @override
  String get dorisModelDuplicate => '明細 (Duplicate)';

  @override
  String get dorisModelUnique => '主鍵去重 (Unique)';

  @override
  String get dorisModelPrimaryKey => '主鍵 (Primary Key)';

  @override
  String get dorisHashColumnLabel => '分桶列';

  @override
  String get dorisBucketsLabel => '桶數';

  @override
  String get dorisModelNeedsKeyColumn => '該模型需要至少一個鍵列（在某列勾選主鍵）';

  @override
  String get dorisAggregateFunctionLabel => '聚合函數';

  @override
  String get dorisModelAggregate => '聚合 (Aggregate)';

  @override
  String get dorisPartitionColumn => '分區列';

  @override
  String get dorisPartitionName => '分區名';

  @override
  String get dorisPartitionLessThan => '小於值';

  @override
  String get dorisAddPartition => '新增分區';

  @override
  String get offlineLicenseTitle => '離線授權';

  @override
  String get offlineLicensePurchaseHint =>
      '升級方式：掃描 GitHub/Gitee 頁面上的付款碼付款後，將本機機器碼與付款截圖傳送至作者信箱，收到授權後在下方匯入。';

  @override
  String get machineCodeLabel => '機器碼';

  @override
  String get machineCodeUnavailable => '無法讀取本機機器碼';

  @override
  String get importLicense => '匯入授權';

  @override
  String get importLicenseHint => '貼上授權字串，或選擇 .dbmlicense 檔案';

  @override
  String get buyLicense => '購買 License';

  @override
  String get machineCodeCopied => '機器碼已複製到剪貼板';

  @override
  String get licenseFilePick => '選擇檔案';

  @override
  String get licenseTypeYearly => '年訂閱';

  @override
  String get licenseTypeLifetime => '買斷';

  @override
  String licenseExpiresAt(String date) {
    return '到期：$date';
  }

  @override
  String get removeLicense => '移除授權';

  @override
  String get licenseImportSuccess => '授權成功，Pro 功能已解鎖';

  @override
  String get licenseErrorInvalid => '授權碼格式無效';

  @override
  String get licenseErrorSignature => '授權簽名校驗失敗';

  @override
  String get licenseErrorMachine => '該授權綁定的是其他機器';

  @override
  String get licenseErrorExpired => '授權已過期';

  @override
  String get licenseErrorNoMachine => '無法讀取機器碼，本裝置不支援離線授權';

  @override
  String licenseActiveInfo(String email) {
    return '授權給 $email';
  }

  @override
  String get errorCopy => '複製';

  @override
  String get errorCopied => '已複製';

  @override
  String get errorAnalyzeWithAi => 'AI 分析';

  @override
  String trialRemaining(int count, String feature) {
    return '$feature 剩餘 $count 次試用';
  }

  @override
  String trialUsedUp(String feature) {
    return '$feature 試用已用完';
  }

  @override
  String get centerTitle => '執行中心';

  @override
  String get centerTabTasks => '任務';

  @override
  String get centerTabErrors => '錯誤';

  @override
  String get centerClearErrors => '清除錯誤';

  @override
  String get centerDismissError => '忽略';

  @override
  String get aiPromptErrorHeader => '請診斷這個資料庫錯誤：說明原因並給出修復建議。';

  @override
  String get commonUndo => '復原';

  @override
  String commonDeleteWithCount(Object count) {
    return '刪除（$count）';
  }

  @override
  String aiPanelSessionsDeletedCount(Object count) {
    return '已刪除 $count 個對話';
  }

  @override
  String aiPanelSessionDeleted(Object title) {
    return '已刪除「$title」';
  }

  @override
  String get aiPanelSelectDatabaseRequired => '請先在上方的下拉選單中選擇一個資料庫。';

  @override
  String get aiPanelMongoExecutionPlan => '🔍 Mongo 執行計畫';

  @override
  String get aiPanelSelectSessions => '選擇對話';

  @override
  String get aiPanelExportTaskCreated => '匯出工作已建立';

  @override
  String get aiPanelDdlOperationCancelled => 'DDL 操作已被使用者取消。';

  @override
  String get aiAssistantOpenTooltip => '開啟 AI 助理';

  @override
  String get schemaImpactRiskLow => '低風險';

  @override
  String get schemaImpactRiskMedium => '中風險';

  @override
  String get schemaImpactRiskHigh => '高風險';

  @override
  String get schemaImpactRiskCritical => '極高風險';

  @override
  String get schemaImpactTitle => '結構影響分析';

  @override
  String schemaImpactSubtitle(Object table, Object type) {
    return '$type 於`$table`';
  }

  @override
  String get schemaImpactDataLossWarning => '資料遺失風險：此操作將永久刪除資料。';

  @override
  String schemaImpactAffectedObjects(Object count) {
    return '受影響的物件（$count）';
  }

  @override
  String schemaImpactWarnings(Object count) {
    return '警告（$count）';
  }

  @override
  String get schemaImpactRecommendations => '建議';

  @override
  String get schemaImpactHideRollbackScript => '隱藏回滾指令碼';

  @override
  String get schemaImpactShowRollbackScript => '顯示回滾指令碼';

  @override
  String get schemaImpactNoRollbackAvailable => '無可用回滾';

  @override
  String get schemaImpactRollbackCaveat =>
      '自動回滾為 best-effort 草稿 - 欄類型/約束可能有誤。執行前請核對；資料無法自動恢復。';

  @override
  String get schemaImpactBackupRequired => '回滾前需備份資料';

  @override
  String get schemaImpactConfirmationRequired => '此操作執行前需要您的明確確認。';

  @override
  String get ddlConfirmDialogTitle => '需要 DDL 確認';

  @override
  String ddlAffectedObjectsCount(Object count) {
    return '受影響的物件（$count）';
  }

  @override
  String get ddlExecuteButton => '執行 DDL';

  @override
  String get ddlSqlStatementLabel => 'SQL 陳述式：';

  @override
  String ddlRiskLevelLabel(Object level) {
    return '風險等級：$level';
  }

  @override
  String get ddlDataLossRiskDetected => '偵測到資料遺失風險';

  @override
  String ddlWarningsCount(Object count) {
    return '警告（$count）';
  }

  @override
  String get ddlTypeConfirmationToProceed => '輸入確認以繼續';

  @override
  String ddlTypeToConfirmDestructive(Object token) {
    return '輸入「$token」以確認此破壞性操作：';
  }

  @override
  String get commonUnknown => '未知';

  @override
  String get commonDismiss => '關閉';

  @override
  String get readOnlyModeBlocked => '此連線為唯讀模式，寫入操作已停用。';

  @override
  String get dlgFillVariables => '填寫變數';

  @override
  String dlgVariableRequired(String variable) {
    return '請輸入$variable';
  }

  @override
  String get dlgEditTrigger => '編輯觸發器';

  @override
  String get dlgCreateTrigger => '建立觸發器';

  @override
  String triggerLoadTablesFailed(String error) {
    return '載入資料表失敗: $error';
  }

  @override
  String get triggerSelectTableRequired => '請選擇資料表';

  @override
  String get triggerSelectEventRequired => '請至少選擇一個事件';

  @override
  String get triggerUpdated => '觸發器更新成功';

  @override
  String get triggerCreated => '觸發器建立成功';

  @override
  String triggerSaveFailed(String error) {
    return '儲存觸發器失敗: $error';
  }

  @override
  String get triggerNameLabel => '觸發器名稱';

  @override
  String get triggerNameRequired => '觸發器名稱為必填';

  @override
  String get triggerNameInvalid => '觸發器名稱格式無效';

  @override
  String get triggerTimingLabel => '時機';

  @override
  String get triggerEventLabel => '事件';

  @override
  String get triggerTableLabel => '資料表';

  @override
  String get triggerSelectTableHint => '請選擇資料表';

  @override
  String get triggerBodyLabel => '觸發器主體';

  @override
  String get triggerBodyHint =>
      '輸入觸發器主體（SQL 語句）\n範例：\nSET NEW.updated_at = NOW();';

  @override
  String triggerCount(int count) {
    return '$count 個觸發器';
  }

  @override
  String get dlgExecutionResult => '執行結果';

  @override
  String dlgExecuteRoutine(String type) {
    return '執行$type';
  }

  @override
  String dlgRoutineName(String name) {
    return '名稱: $name';
  }

  @override
  String dlgRoutineType(String type) {
    return '類型: $type';
  }

  @override
  String dlgRoutineReturnType(String type) {
    return '回傳類型: $type';
  }

  @override
  String get dlgParameters => '參數';

  @override
  String get dlgRoutineNoParams => '此預存程序/函式不需要參數';

  @override
  String get dlgOutputParam => '輸出參數';

  @override
  String get dlgReturnValueLabel => '回傳值:';

  @override
  String dlgRowsAffected(int count) {
    return '受影響的列數: $count';
  }

  @override
  String dlgEditRoutine(String type) {
    return '編輯$type';
  }

  @override
  String routineParameterCount(int count) {
    return '$count 個參數';
  }

  @override
  String routineDeleteConfirmation(String type, String name) {
    return '刪除$type\"$name\"?';
  }

  @override
  String get routineListTitle => '預存程序和函式';

  @override
  String routineDefinitionTitle(String type) {
    return '$type定義';
  }

  @override
  String get queryExecutionPlan => '查詢執行計畫';

  @override
  String dlgCreateRoutine(String type) {
    return '建立$type';
  }

  @override
  String get dlgNameRequired => '請輸入名稱';

  @override
  String get dlgRoutineNameInvalid => '名稱只能包含字母、數字和底線，且不能以數字開頭';

  @override
  String get dlgReturnTypeRequired => '請選擇回傳類型';

  @override
  String get dlgSqlCode => 'SQL 程式碼';

  @override
  String get dlgRoutineProcedure => '預存程序';

  @override
  String get dlgRoutineFunction => '函式';

  @override
  String get commonUpdate => '更新';

  @override
  String get commonCreate => '建立';

  @override
  String get auditLogTitle => '查詢稽核日誌';

  @override
  String get auditLogAllStatus => '全部狀態';

  @override
  String get auditLogAll => '全部';

  @override
  String get auditLogTime => '時間';

  @override
  String get auditLogDuration => '耗時';

  @override
  String get auditLogRows => '列數';

  @override
  String get auditLogStatus => '狀態';

  @override
  String get auditLogEmpty => '尚無稽核日誌';

  @override
  String get auditLogEmptyHint => '執行查詢後開始記錄日誌';

  @override
  String get auditLogTotal => '總計';

  @override
  String get auditLogWrite => '寫入';

  @override
  String get auditLogAvgTime => '平均耗時';

  @override
  String get auditLogClearTitle => '清除稽核日誌';

  @override
  String get auditLogClearConfirm => '確定要清除所有稽核日誌嗎？此操作無法復原。';

  @override
  String get auditLogClear => '清除';

  @override
  String get piiMaskingTitle => 'PII 資料遮罩';

  @override
  String get piiMaskingEnable => '啟用 PII 遮罩';

  @override
  String get piiMaskingEnableDesc => '自動遮罩查詢結果中的敏感資料';

  @override
  String get piiMaskingTypes => '敏感資料類型';

  @override
  String get piiTypeEmail => '電子郵件地址';

  @override
  String get piiTypePhone => '電話號碼';

  @override
  String get piiTypeIdCard => '身分證字號';

  @override
  String get piiTypeCreditCard => '信用卡';

  @override
  String get piiTypeBankCard => '銀行帳戶';

  @override
  String get piiTypePassword => '密碼';

  @override
  String get piiTypeIpAddress => 'IP 位址';

  @override
  String get shortcutNoMatching => '無符合的快速鍵';

  @override
  String get shortcutPressEscToClose => '按 ESC 關閉';

  @override
  String get indexTypePrimary => '主鍵';

  @override
  String get performanceAnalyzerWeeklyReportTitle => '每週慢查詢報告';

  @override
  String get performanceAnalyzerWeeklyReportDesc =>
      '每週一取得 Top 10 慢查詢及 EXPLAIN 分析';

  @override
  String get performanceAnalyzerLearnMore => '瞭解更多';

  @override
  String get backupListLoading => '載入備份清單...';

  @override
  String dbPropertiesTitle(String name) {
    return '資料庫屬性 - $name';
  }

  @override
  String get dbPropertyName => '名稱';

  @override
  String get dbPropertyCharset => '字元集';

  @override
  String get dbPropertyCollation => '定序';

  @override
  String get dbPropertySize => '大小';

  @override
  String get dbPropertyTableCount => '資料表數量';

  @override
  String get dbPropertyViewCount => '檢視數量';

  @override
  String get dbPropertyRoutineCount => '預存程序/函式';

  @override
  String get exportFormatLabel => '匯出格式';

  @override
  String exportRowCount(int count) {
    return '共 $count 列資料';
  }

  @override
  String get taskCreateExportFilter => '篩選';

  @override
  String get taskCreateExportEstRows => '估計列數';

  @override
  String get taskCreateExportValidating => '驗證中...';

  @override
  String get taskCreateExportSaveDialogTitle => '選擇匯出檔案儲存位置';

  @override
  String taskValidationPathNotExists(String path) {
    return '目錄不存在: $path';
  }

  @override
  String taskCreateExportDesc(String table) {
    return '匯出 $table';
  }

  @override
  String taskCreateExportDescFiltered(String table) {
    return '匯出 $table（篩選）';
  }

  @override
  String get sqliteConnectionEditTitle => '編輯 SQLite 連線';

  @override
  String get sqliteConnectionNewTitle => '新增 SQLite 連線';

  @override
  String get createSuperTableTitle => '建立超級表';

  @override
  String get importWizardTitle => '資料匯入精靈';

  @override
  String dbCreateSuccess(String name) {
    return '資料庫 \"$name\" 建立成功';
  }

  @override
  String get dbCreateFailed => '建立資料庫失敗';

  @override
  String dbCreateError(String error) {
    return '錯誤: $error';
  }

  @override
  String get dbOperationCannotBeUndone => '此操作無法復原！';

  @override
  String dropTablePermanentWarning(String table) {
    return '資料表 \"$table\" 及其所有資料將被永久刪除。';
  }

  @override
  String get dropTableDataLossWarning => '此操作無法復原！該資料表中的所有資料將永久遺失。';

  @override
  String get objectTypeTable => '資料表';

  @override
  String get objectTypeView => '檢視';

  @override
  String get commonRemove => '移除';

  @override
  String get commonRequired => '必填';

  @override
  String get commonInvalidIdentifier => '識別碼無效';

  @override
  String get mongoValidationJsonObject => 'JSON 必須是物件';

  @override
  String mongoValidationInvalidJson(String error) {
    return 'JSON 無效: $error';
  }

  @override
  String get settingsAutoLimitEnabledDesc => '自動為 SELECT 查詢加上 LIMIT';

  @override
  String get sqliteConnectionInfo => '連線資訊';

  @override
  String get sqliteNameHint => '我的 SQLite 資料庫';

  @override
  String get connectionDirNotExists => '目錄不存在';

  @override
  String get indexSelectColumnRequired => '請至少選擇一欄';

  @override
  String indexCreateFailed(String error) {
    return '建立索引失敗: $error';
  }

  @override
  String indexUpdateFailed(String error) {
    return '更新索引失敗: $error';
  }

  @override
  String get indexNameRequired => '索引名稱為必填項';

  @override
  String get superTableTags => '標籤';

  @override
  String get superTableCreated => '超級表建立成功';

  @override
  String get redisLibNameCodeRequired => '庫名稱和程式碼為必填項';

  @override
  String get redisAdapterNotAvailable => 'Redis 轉接器不可用';

  @override
  String get redisLibraryCreated => '函式庫建立成功';

  @override
  String redisLibraryCreateFailed(String error) {
    return '建立函式庫失敗: $error';
  }

  @override
  String get redisLibraryUsageHint => '用於 #!lua name=<library>';

  @override
  String get redisInsertExample => '插入範例';

  @override
  String get redisCreateLibrary => '建立庫';

  @override
  String redisKeyLoadFailed(String error) {
    return '載入鍵資料失敗: $error';
  }

  @override
  String get redisKeyUpdated => '鍵更新成功';

  @override
  String redisKeySaveFailed(String error) {
    return '儲存鍵失敗: $error';
  }

  @override
  String get redisKeySaveChanges => '儲存變更';

  @override
  String get serverConnectTitle => '連線到伺服器';

  @override
  String get serverConnectUrl => '伺服器 URL';

  @override
  String get serverUrlRequired => '伺服器 URL 為必填項';

  @override
  String get serverUrlInvalid => 'URL 無效（例如 https://myserver:3000）';

  @override
  String get serverConnectEmail => '電子郵件';

  @override
  String get serverEmailRequired => '電子郵件為必填項';

  @override
  String get serverEmailInvalid => '電子郵件無效';

  @override
  String get serverPasswordRequired => '密碼為必填項';

  @override
  String get mongoValidationFixErrors => '請先修正 JSON 錯誤再套用';

  @override
  String get mongoValidationApplied => '驗證規則套用成功';

  @override
  String get mongoValidationRemoved => '驗證規則已移除';

  @override
  String get mongoValidationLevel => '驗證級別';

  @override
  String get mongoValidationAction => '驗證動作';

  @override
  String mongoValidationApplyFailed(String error) {
    return '套用驗證規則失敗: $error';
  }

  @override
  String get indexSelectColumns => '選擇欄';

  @override
  String get redisLibraryTitle => '建立函式庫';

  @override
  String get redisLibraryNameLabel => '庫名稱';

  @override
  String get redisLibraryCreateFailedSyntax => '建立庫失敗（需要 Redis 7.0+，請檢查語法）';

  @override
  String get redisLuaCodeLabel => 'Lua 程式碼';

  @override
  String get redisReplaceExisting => '取代同名既有庫（FUNCTION LOAD REPLACE）';

  @override
  String get redisLibraryInfoText =>
      '庫名稱會自動寫入 #!lua shebang。Lua 程式碼應包含 redis.register_function() 呼叫。請勿自行撰寫 shebang。';

  @override
  String get superTableCreateFailed => '建立超級表失敗';

  @override
  String get superTableColumns => '欄';

  @override
  String get errorTitle => '發生錯誤';

  @override
  String get errorDescriptionLabel => '錯誤資訊：';

  @override
  String get errorStackLabel => '堆疊追蹤：';

  @override
  String get columnFilterTypeNumeric => '數值';

  @override
  String get columnFilterTypeDateTime => '時間';

  @override
  String get columnFilterTypeText => '文字';

  @override
  String get columnFilterPlaceholderNumeric => '輸入數值';

  @override
  String get columnFilterPlaceholderDateTime => '輸入時間（如：2024-01-01）';

  @override
  String get columnFilterPlaceholderText => '輸入文字';

  @override
  String columnFilterFor(String columnName) {
    return '篩選：$columnName';
  }

  @override
  String columnFilterActive(int count) {
    return '已套用 $count 個篩選條件';
  }

  @override
  String columnFilterRowCount(String filtered, String total) {
    return '$filtered / $total 列';
  }

  @override
  String get filterOpEquals => '等於';

  @override
  String get filterOpNotEquals => '不等於';

  @override
  String get filterOpContains => '包含';

  @override
  String get filterOpNotContains => '不包含';

  @override
  String get filterOpStartsWith => '開頭為';

  @override
  String get filterOpEndsWith => '結尾為';

  @override
  String get filterOpGreaterThan => '大於';

  @override
  String get filterOpGreaterThanOrEqual => '大於等於';

  @override
  String get filterOpLessThan => '小於';

  @override
  String get filterOpLessThanOrEqual => '小於等於';

  @override
  String get filterOpBetween => '介於';

  @override
  String get filterOpIsNull => '為空';

  @override
  String get filterOpIsNotNull => '不為空';

  @override
  String get filterOpIsEmpty => '為空字串';

  @override
  String get filterOpIsNotEmpty => '不為空字串';

  @override
  String get tableNoData => '無資料';

  @override
  String tableRowCountTotal(String count) {
    return '共 $count 列';
  }

  @override
  String get tableLargeDatasetHint => '（大數據集，請捲動查看更多）';

  @override
  String tableRowRange(String start, String end, String total) {
    return '$start-$end / $total 列';
  }

  @override
  String get importWizStepSelectFile => '選擇檔案';

  @override
  String get importWizStepAnalyzeFile => '分析檔案';

  @override
  String get importWizStepColumnMapping => '欄位對應';

  @override
  String get importWizStepPreviewPII => '預覽 & PII';

  @override
  String get importWizStepConfirmImport => '確認匯入';

  @override
  String importWizStepOf(String current, String total, String title) {
    return '第 $current 步（共 $total 步）：$title';
  }

  @override
  String get importWizTargetDatabase => '目標資料庫';

  @override
  String get importWizSelectDatabase => '選擇資料庫';

  @override
  String get importWizTargetTableOptional => '目標資料表（可選）';

  @override
  String get importWizLetAiInfer => '-- 讓 AI 推斷資料表名稱 --';

  @override
  String get importWizChooseFile => '點擊選擇檔案或拖曳至此處';

  @override
  String get importWizChangeFile => '更換檔案';

  @override
  String get importWizSupportedFormats => '支援 CSV、JSON、Excel、TSV 格式';

  @override
  String get importWizFileUnknown => '未知';

  @override
  String get importWizAiAnalyzing => 'AI 正在分析檔案...';

  @override
  String get importWizDetectingFormat => '正在檢測格式、編碼、欄位類型...';

  @override
  String get importWizFileAnalysisResult => '檔案分析結果';

  @override
  String get importWizFormat => '格式';

  @override
  String get importWizEncoding => '編碼';

  @override
  String get importWizFieldCount => '欄位數';

  @override
  String get importWizEstimatedRows => '估計列數';

  @override
  String get importWizFileSize => '檔案大小';

  @override
  String get importWizDelimiter => '分隔符';

  @override
  String get importWizDetectedFields => '檢測到的欄位';

  @override
  String get importWizAiSuggestion => 'AI 建議';

  @override
  String importWizTargetTableName(String tableName) {
    return '目標資料表：$tableName';
  }

  @override
  String get importWizNoAnalysisResult => '尚無分析結果';

  @override
  String get importWizSelectFileFirst => '請先選擇檔案';

  @override
  String get importWizNoColumnMapping => '尚無欄位對應';

  @override
  String get importWizGeneratingMapping => '正在產生對應...';

  @override
  String get importWizColumnMappingConfig => '欄位對應設定';

  @override
  String importWizColumnsMapped(String mapped, String total) {
    return '$mapped/$total 欄已對應';
  }

  @override
  String get importWizMappingDescription => '將檔案中的欄位對應到資料庫資料表的欄位。選擇「不匯入」跳過該欄位。';

  @override
  String get importWizFileColumn => '檔案欄位';

  @override
  String get importWizDatabaseColumn => '資料庫欄位';

  @override
  String get importWizType => '類型';

  @override
  String get importWizPiiDetection => 'PII 敏感資料檢測';

  @override
  String get importWizPiiDetectionMessage => '檢測到以下敏感欄位，請確認是否繼續匯入：';

  @override
  String get importWizPiiAcknowledge => '我已知悉，繼續匯入';

  @override
  String get importWizDataPreview => '資料預覽';

  @override
  String importWizWarnings(String count) {
    return '$count 個警告';
  }

  @override
  String importWizFirstRows(String count) {
    return '前 $count 列';
  }

  @override
  String get importWizSensitiveField => '敏感欄位';

  @override
  String get importWizDataValidationWarnings => '資料驗證警告';

  @override
  String importWizValidationRowFormat(String row, String col, String msg) {
    return '第 $row 列，$col 欄：$msg';
  }

  @override
  String get importWizImportSummary => '匯入設定摘要';

  @override
  String get importWizSummaryTargetDatabase => '目標資料庫';

  @override
  String get importWizSummaryTargetTable => '目標資料表';

  @override
  String get importWizSummaryFile => '檔案';

  @override
  String get importWizSummaryMappedColumns => '對應欄位';

  @override
  String get importWizSummaryDataRows => '資料列數';

  @override
  String get importWizConflictStrategy => '衝突處理策略';

  @override
  String get importWizConflictSkip => '跳過重複列';

  @override
  String get importWizConflictSkipDesc => '當遇到重複鍵時，跳過該列繼續匯入';

  @override
  String get importWizConflictUpdate => '更新現有列';

  @override
  String get importWizConflictUpdateDesc => '當遇到重複鍵時，更新已有資料';

  @override
  String get importWizConflictAbort => '中止匯入';

  @override
  String get importWizConflictAbortDesc => '當遇到重複鍵時，立即停止匯入';

  @override
  String get importWizImporting => '匯入中...';

  @override
  String importWizRowsProgress(String imported, String total) {
    return '$imported/$total 列';
  }

  @override
  String importWizFailedRows(String count) {
    return '失敗：$count 列';
  }

  @override
  String get importWizImportComplete => '匯入完成！';

  @override
  String importWizImportFailed(String error) {
    return '匯入失敗：$error';
  }

  @override
  String importWizImportSuccessMsg(String count) {
    return '成功匯入 $count 列資料';
  }

  @override
  String get importWizImportErrorMsg => '匯入過程中發生錯誤';

  @override
  String get importWizPreviousStep => '上一步';

  @override
  String get importWizClose => '關閉';

  @override
  String get importWizStartImport => '開始匯入';

  @override
  String get importWizNextStep => '下一步';

  @override
  String get importWizReimport => '重新匯入';

  @override
  String importWizLoadDatabasesFailed(String error) {
    return '載入資料庫列表失敗：$error';
  }

  @override
  String importWizLoadTablesFailed(String error) {
    return '載入資料表列表失敗：$error';
  }

  @override
  String importWizPickFileFailed(String error) {
    return '選擇檔案失敗：$error';
  }

  @override
  String importWizAnalysisFailed(String error) {
    return '分析失敗：$error';
  }

  @override
  String importWizMappingFailed(String error) {
    return '產生欄位對應失敗：$error';
  }

  @override
  String get importWizFileAnalysisFailed => '檔案分析失敗';

  @override
  String get importWizImportFailedGeneric => '匯入失敗';

  @override
  String get importWizNotSelected => '未選擇';

  @override
  String get importWizNotSet => '未設定';

  @override
  String get importWizUnknown => '未知';

  @override
  String get importWizPiiDetectionSummary => 'PII 檢測';

  @override
  String importWizSensitiveFieldCount(String count) {
    return '$count 個敏感欄位';
  }

  @override
  String get smartImportAnalyzingDetail => 'AI 正在識別欄位類型並產生建表語句';

  @override
  String get smartImportColumnMapping => '欄位對應';

  @override
  String smartImportColumnsMapped(String mapped, String total) {
    return '$mapped/$total 欄已對應';
  }

  @override
  String get smartImportFileColumn => '檔案欄位';

  @override
  String get smartImportTableColumn => '資料表欄位';

  @override
  String get smartImportConflictResolution => '衝突處理';

  @override
  String get smartImportDataPreview => '資料預覽';

  @override
  String smartImportFirstRows(String count) {
    return '前 $count 列';
  }

  @override
  String get smartImportBack => '返回';

  @override
  String get smartImportBackgroundTask => '背景匯入';

  @override
  String get smartImportFailedToGenerateSql => '-- 未能產生建表語句';

  @override
  String smartImportTargetTableSelected(String table) {
    return '已選擇目標資料表：$table';
  }

  @override
  String smartImportTargetTableEntered(String table) {
    return '已輸入目標資料表：$table';
  }

  @override
  String smartImportAnalysisFailed(String error) {
    return '檔案分析失敗：$error';
  }

  @override
  String smartImportColumnMappingsComplete(String mapped, String total) {
    return '欄位對應完成：$mapped/$total 欄自動匹配';
  }

  @override
  String smartImportPiiDetected(String types) {
    return 'PII 檢測：發現敏感欄位 - $types';
  }

  @override
  String get smartImportPiiNone => 'PII 檢測：未發現敏感欄位';

  @override
  String smartImportPiiFailed(String error) {
    return 'PII 檢測失敗：$error';
  }

  @override
  String smartImportPreviewGenerated(String count) {
    return '資料預覽已產生（$count 列）';
  }

  @override
  String smartImportPreviewFailed(String error) {
    return '產生預覽失敗：$error';
  }

  @override
  String smartImportMappingFailed(String error) {
    return '產生欄位對應失敗：$error';
  }

  @override
  String importServiceStartImport(String table) {
    return '開始匯入資料到資料表 \"$table\"...';
  }

  @override
  String importServiceColumnMapping(String mapped, String total) {
    return '欄位對應：$mapped/$total 欄已對應';
  }

  @override
  String importServiceConflictStrategy(String strategy) {
    return '衝突處理策略：$strategy';
  }

  @override
  String get importServiceImporting => '開始匯入資料...';

  @override
  String importServiceBatchSuccess(String batch, String count) {
    return '批次 $batch：成功匯入 $count 列';
  }

  @override
  String importServiceBatchInsertFailed(String count) {
    return '批次插入失敗（$count 列），嘗試逐列插入...';
  }

  @override
  String importServiceUpdateFailed(String error) {
    return '更新失敗：$error';
  }

  @override
  String importServiceDataTooLong(String row) {
    return '第 $row 列資料過長，已跳過';
  }

  @override
  String importServiceRowInsertFailed(String row, String error) {
    return '第 $row 列插入失敗：$error';
  }

  @override
  String importServiceBatchSkipped(String count) {
    return '此批次跳過：$count 列（重複）';
  }

  @override
  String importServiceBatchUpdated(String count) {
    return '此批次更新：$count 列';
  }

  @override
  String importServiceBatchFailed(String count) {
    return '此批次失敗：$count 列';
  }

  @override
  String importServicePhaseProgress(
    String imported,
    String skipped,
    String updated,
  ) {
    return '已匯入 $imported 列，跳過 $skipped 列，更新 $updated 列...';
  }

  @override
  String get importServiceImportCancelled => '匯入已取消';

  @override
  String importServiceFileReadFailed(String error) {
    return '檔案讀取失敗：$error';
  }

  @override
  String importServiceImportComplete(String imported, String failed) {
    return '資料匯入完成！成功：$imported 列，失敗：$failed 列';
  }

  @override
  String taskExecutorAnalyzeFile(String path) {
    return '開始分析檔案：$path';
  }

  @override
  String taskExecutorFileFormat(String format, String encoding, String rows) {
    return '檔案格式：$format，編碼：$encoding，預估列數：$rows';
  }

  @override
  String get taskExecutorTableNotExists => '資料表不存在，正在建立資料表...';

  @override
  String get taskExecutorTableCreated => '資料表建立成功';

  @override
  String get taskExecutorTableCreateFailed => '建立資料表失敗';

  @override
  String taskExecutorTableNotExistsError(String table) {
    return '目標資料表 \"$table\" 不存在，請先建立資料表';
  }

  @override
  String get taskExecutorNoColumnMapping => '沒有可用的欄位對應，請檢查檔案欄位與資料表欄位是否匹配';

  @override
  String taskExecutorColumnMapping(String mapped, String total) {
    return '欄位對應：$mapped/$total 欄已對應';
  }

  @override
  String get taskExecutorStartImport => '開始匯入資料...';

  @override
  String taskExecutorImportComplete(String imported, String failed) {
    return '匯入完成！成功：$imported 列，失敗：$failed 列';
  }

  @override
  String get taskExecutorImportFinished => '匯入完成';

  @override
  String get serverConnectNoServerLearnMore =>
      'Don\'t have a server? Learn more';

  @override
  String get touchpointLiteLearnMore => 'See how';

  @override
  String get touchpointLiteSlowQueryTitle => 'Recurring slow queries?';

  @override
  String get touchpointLiteSlowQueryDesc =>
      'DbMaster Server can track these automatically and alert you on schedule.';

  @override
  String get touchpointLiteSchemaDiffTitle => 'Repeat schema comparisons?';

  @override
  String get touchpointLiteSchemaDiffDesc =>
      'DbMaster Server can run this on a schedule, retry on failure, and send Feishu/DingTalk alerts.';

  @override
  String get touchpointLiteDataSyncTitle => 'Tired of running this manually?';

  @override
  String get touchpointLiteDataSyncDesc =>
      'DbMaster Server can automate this sync with retries and team notifications.';

  @override
  String get viewModeTable => '表格';

  @override
  String get viewModeChart => '圖表';

  @override
  String get viewModeCard => '卡片';

  @override
  String get viewModeDocument => '文件卡片';

  @override
  String get viewModeJsonTree => 'JSON 樹';

  @override
  String get viewModeKeyValue => '鍵值視圖';

  @override
  String get documentExpand => '展開';

  @override
  String get documentCollapse => '摺疊';

  @override
  String documentExpandMore(int count) {
    return '展開其餘 $count 個欄位';
  }

  @override
  String jsonTreeItemCount(int count) {
    return '$count 項';
  }

  @override
  String get keyValueField => '欄位';

  @override
  String get keyValueValue => '值';

  @override
  String keyValueFieldLabel(String field) {
    return '欄位：$field';
  }

  @override
  String keyValueLengthLabel(int length) {
    return '長度：$length 字元';
  }

  @override
  String get chartViewComingSoon => '圖表視圖（即將上線）';

  @override
  String chartExportSuccess(String path) {
    return '圖表已儲存到 $path';
  }

  @override
  String chartExportFailed(String error) {
    return '圖表匯出失敗：$error';
  }

  @override
  String chartSamplingNotice(int count) {
    return '資料量較大：已取樣 $count 個點以保證效能';
  }

  @override
  String get chartAiTrend => 'AI 趨勢分析';

  @override
  String get chartTypeLine => '折線';

  @override
  String get chartTypeBar => '柱狀';

  @override
  String get chartTypePie => '圓餅';

  @override
  String get chartTypeScatter => '散佈';

  @override
  String get statisticsPanelTitle => '統計';

  @override
  String get exportStepBack => '上一步';

  @override
  String get exportStepNext => '下一步';

  @override
  String get noJsonDataToSample => '無資料可取樣';

  @override
  String get noLeafNodes => '無可提取欄位';

  @override
  String get fieldNotInAllRows => '非所有列都有';

  @override
  String get commonRetry => '重試';

  @override
  String get extensionNoAdapter => '無介面卡';

  @override
  String get extensionNotPostgres => '非 PostgreSQL 連線';

  @override
  String get extensionLoadFailed => '載入成員失敗';

  @override
  String get extensionTypes => '類型';

  @override
  String get extensionFunctions => '函式';

  @override
  String get extensionOperators => '運算子';

  @override
  String get extensionSchema => '結構描述';

  @override
  String get extensionDescription => '描述';

  @override
  String get vectorLoadFailed => '載入向量索引失敗';

  @override
  String get vectorNoAdapter => '無介面卡';

  @override
  String get vectorNoIndexes => '未定義向量索引';

  @override
  String get jsonInvalidJson => '無效 JSON';

  @override
  String get jsonNoMatches => '無符合';

  @override
  String get jsonSearchHint => '搜尋鍵或值…';

  @override
  String get mcpTokensMenuLabel => 'MCP 權杖';

  @override
  String get mcpTokensTitle => 'MCP 權杖';

  @override
  String get mcpTokensIntro =>
      '供 AI 用戶端（Claude Code、Cursor）使用的長效權杖。將它作為 Bearer token 設定到用戶端的 MCP 設定即可；隨時可撤銷。';

  @override
  String get mcpTokensNotConnected => '連線 DbMaster 伺服器後才能管理 MCP 權杖。';

  @override
  String get mcpTokensEmpty => '還沒有權杖。為你的 AI 用戶端建立一個吧。';

  @override
  String get mcpTokensNameHint => '權杖名稱（如 claude-code-mac）';

  @override
  String get mcpTokensCreate => '建立';

  @override
  String mcpTokensOnceTitle(String name) {
    return '權杖「$name」已建立';
  }

  @override
  String get mcpTokensOnceWarning =>
      '請立即複製——基於安全考量不會再次顯示。將它作為 Bearer token 設定到 MCP 用戶端（如 mcp.json）。';

  @override
  String get mcpTokensCopy => '複製';

  @override
  String get mcpTokensCopied => '權杖已複製到剪貼簿';

  @override
  String get mcpTokensDone => '完成';

  @override
  String mcpTokensLastUsed(String value) {
    return '最近使用：$value';
  }

  @override
  String get mcpTokensNeverUsed => '從未使用';

  @override
  String get mcpTokensRevoke => '撤銷';

  @override
  String get mcpTokensRevokeTitle => '撤銷此權杖？';

  @override
  String mcpTokensRevokeBody(String name, String prefix) {
    return '使用「$name」（$prefix…）的用戶端將立即失效，且無法復原。';
  }

  @override
  String get serverConnectionsMenuLabel => '管理 Server 連線';

  @override
  String get serverConnectionsTitle => 'Server 連線管理';

  @override
  String get serverConnectionsIntro =>
      '註冊在 Server 上的資料庫連線。資料同步、健康檢查、DDL 審批都基於這些連線執行；桌面側欄的連線清單是獨立的。';

  @override
  String get serverConnectionsNotConnected => '未連線 Server。';

  @override
  String get serverConnectionsEmpty =>
      'Server 上還沒有連線。請先新增，資料同步 / 健康檢查 / 審批任務才有可用的資料庫。';

  @override
  String get serverConnectionsAdd => '新增';

  @override
  String get serverConnectionsEdit => '編輯';

  @override
  String get serverConnectionsDelete => '刪除';

  @override
  String get serverConnectionsKindCollab => '協作';

  @override
  String get serverConnectionsKindSourceDrift => 'Drift 來源（唯讀）';

  @override
  String get serverConnectionsDeleteTitle => '刪除連線';

  @override
  String serverConnectionsDeleteBody(String name) {
    return '刪除 Server 連線「$name」？';
  }

  @override
  String serverConnectionsDeleteTaskWarning(num count) {
    return '有 $count 個任務引用此連線，將隨之被刪除（作為來源）或斷開（作為目標）。';
  }

  @override
  String get serverConnFormCreateTitle => '新增 Server 連線';

  @override
  String get serverConnFormEditTitle => '編輯 Server 連線';

  @override
  String get serverConnFormName => '名稱';

  @override
  String get serverConnFormType => '類型';

  @override
  String get serverConnFormHost => '主機';

  @override
  String get serverConnFormPort => '連接埠';

  @override
  String get serverConnFormUsername => '使用者名稱';

  @override
  String get serverConnFormPassword => '密碼';

  @override
  String get serverConnFormPasswordKeepHint => '留空保持原密碼不變';

  @override
  String get serverConnFormDatabase => '預設資料庫（可選）';

  @override
  String get serverConnFormSqlitePath => '資料庫檔案路徑';

  @override
  String get serverConnFormSave => '儲存';

  @override
  String get serverConnFormRequired => '必填';

  @override
  String get serverConnFormInvalidPort => '連接埠必須是數字';

  @override
  String get dataSyncConnectionNotOnServer =>
      '所選連線尚未註冊到 Server。請先在「管理 Server 連線」中新增，再重試。';

  @override
  String connectionFormProvidedBy(String plugin) {
    return '由 $plugin 提供';
  }

  @override
  String get connectionDbIndex => '資料庫索引';

  @override
  String get connectionAuthDatabase => '認證資料庫';

  @override
  String get connectionRedisAuthNone => '無認證';

  @override
  String get connectionRedisAuthNoneDesc => '無需認證';

  @override
  String get connectionRedisAuthPasswordOnly => '僅密碼';

  @override
  String get connectionRedisAuthPasswordOnlyDesc => 'AUTH 密碼（Redis < 6.0）';

  @override
  String get connectionRedisAuthUsernamePassword => '帳號 + 密碼（ACL）';

  @override
  String get connectionRedisAuthUsernamePasswordDesc =>
      'AUTH 帳號 密碼（Redis 6.0+ ACL）';

  @override
  String get connectionSshAuthPassword => '密碼';

  @override
  String get connectionSshAuthPrivateKey => '私鑰';

  @override
  String get sidebarCapabilityTitle => '能力';

  @override
  String get sidebarCapGroupDatabaseObjects => '資料庫物件';

  @override
  String get sidebarCapGroupAdvanced => '進階';

  @override
  String get redisCapGroupKeyspace => '鍵空間';

  @override
  String get redisCapWorkbench => '命令列工作台';

  @override
  String get redisCapPubsub => '發布訂閱';

  @override
  String get redisCapLua => 'Lua 腳本';

  @override
  String get redisCapPipeline => '管線';

  @override
  String get redisCapTransaction => '交易';

  @override
  String get redisCapMemoryAnalysis => '記憶體分析';

  @override
  String get redisCapKeyspaceNotifications => '鍵空間通知';

  @override
  String get redisCapAcl => 'ACL 管理';

  @override
  String get redisCapConfig => '編輯設定';

  @override
  String get mongoValidationTitle => '驗證規則';

  @override
  String get mongoValidationNoValidator =>
      '此集合未設定驗證規則（可透過 collMod 或 MongoDB Shell 新增）。';

  @override
  String mongoValidationLoadFailed(String error) {
    return '載入驗證規則失敗：$error';
  }

  @override
  String sidebarDocumentInserted(String collection) {
    return '文件已插入到 $collection';
  }

  @override
  String get aiSkillCatalogTitle => '技能目錄';

  @override
  String get aiSkillGroupSql => 'SQL 類';

  @override
  String get aiSkillGroupData => '資料類';

  @override
  String get aiSkillGroupSchema => '結構類';

  @override
  String get aiSkillGroupOps => '維運類';

  @override
  String get aiSkillNl2sqlName => '自然語言轉 SQL';

  @override
  String get aiSkillNl2sqlDesc => '用自然語言描述需求，產生 SQL';

  @override
  String get aiSkillSqlExplainName => 'SQL 解釋';

  @override
  String get aiSkillSqlExplainDesc => '逐段解釋一條 SQL 的作用';

  @override
  String get aiSkillSqlExplainPrompt => '請逐段解釋這條 SQL 的作用：\n```\n\n```';

  @override
  String get aiSkillQueryOptimizerName => '查詢最佳化';

  @override
  String get aiSkillQueryOptimizerDesc => '分析慢查詢並給出最佳化建議';

  @override
  String get aiSkillQueryOptimizerPrompt => '請分析這條查詢的效能問題並給出最佳化建議：\n```\n\n```';

  @override
  String get aiSkillDataCleaningName => '資料清理建議';

  @override
  String get aiSkillDataCleaningDesc => '針對表中的髒資料給出清理建議';

  @override
  String get aiSkillDataCleaningPrompt => '我表裡存在髒資料，請針對以下問題給出清理步驟：';

  @override
  String get aiSkillImportMappingName => '匯入對應產生';

  @override
  String get aiSkillImportMappingDesc => '為資料匯入產生欄位對應';

  @override
  String get aiSkillImportMappingPrompt =>
      '請產生把以下檔案匯入目標表的欄位對應（JSON）。\n來源檔欄位：\n目標表欄位：';

  @override
  String get aiSkillSchemaAnalysisName => 'Schema 分析';

  @override
  String get aiSkillSchemaAnalysisDesc => '審視目前庫的表結構並指出風險';

  @override
  String get aiSkillSchemaAnalysisPrompt => '請審視目前庫的表結構，指出設計風險與改進建議。';

  @override
  String get aiSkillSchemaDiffName => '結構比對助手';

  @override
  String get aiSkillSchemaDiffDesc => '比較兩段結構定義並輸出 diff';

  @override
  String get aiSkillSchemaDiffPrompt =>
      '請比較以下兩段結構定義並輸出 unified diff：\n<schema-a>\n\n</schema-a>\n<schema-b>\n\n</schema-b>';

  @override
  String get aiSkillIndexSuggestName => '索引建議';

  @override
  String get aiSkillIndexSuggestDesc => '針對查詢或表給出索引建議';

  @override
  String get aiSkillIndexSuggestPrompt => '請針對這條查詢給出索引建議並說明理由：\n```\n\n```';

  @override
  String get aiSkillErrorDiagnosisName => '錯誤診斷';

  @override
  String get aiSkillErrorDiagnosisDesc => '診斷資料庫報錯';

  @override
  String get aiSkillErrorDiagnosisPrompt => '請診斷這個資料庫報錯並給出修復方案：\n```\n\n```';

  @override
  String get aiSkillSlowQueryName => 'Slow Query 分析';

  @override
  String get aiSkillSlowQueryDesc => '分析慢查詢日誌';

  @override
  String get aiSkillSlowQueryPrompt => '請分析這條慢查詢日誌並定位瓶頸：\n```\n\n```';

  @override
  String get aiContextPanelTitle => '上下文';

  @override
  String get aiContextConnectionSection => '目前連線';

  @override
  String get aiContextDatabaseSection => '目前資料庫';

  @override
  String get aiContextNoConnection => '未選擇連線';

  @override
  String get aiContextSchemaContext => '附加 Schema 上下文';

  @override
  String get aiContextSchemaContextDesc => '傳送時附帶目前庫的表結構資訊';

  @override
  String get aiPanelOpenSkillCatalog => '技能目錄';

  @override
  String get aiPanelOpenContextPanel => '上下文面板';

  @override
  String get safetyBannerAddLimit => '追加 LIMIT';

  @override
  String safetyBannerCooldown(int seconds) {
    return '確認（${seconds}s）';
  }

  @override
  String get safetyDmlAllRowsWarning => '此操作將影響所有符合行，建議附加 LIMIT 子句。';

  @override
  String get safetySeverityHigh => '高危';

  @override
  String get safetySeverityMedium => '警告';

  @override
  String get safetySeverityLow => '資訊';

  @override
  String get safetySeverityPolicy => '策略';

  @override
  String gateTitleSingle(int count) {
    return '執行確認：此 SQL 存在 $count 項風險';
  }

  @override
  String gateTitleMulti(int count, int total) {
    return '執行確認：$total 條語句中發現 $count 項風險';
  }

  @override
  String get gateDdlImpactTitle => 'DDL 影響分析';

  @override
  String gateStatementLabel(int n) {
    return '語句 $n';
  }

  @override
  String get gateSuggestionLabel => '建議修復';

  @override
  String gateOverview(int total, int high, int medium, int low, int ok) {
    return '$total 條語句 · 高危 $high · 警告 $medium · 資訊 $low · 通過 $ok';
  }

  @override
  String gateSkipHighRisk(int skip, int exec) {
    return '跳過 $skip 條高危，執行 $exec 條';
  }

  @override
  String get gateAllHighDisabled => '全部為高危——無可執行語句';

  @override
  String get gateApplySuggestions => '採用全部建議';

  @override
  String get gateProceed => '知情繼續執行';

  @override
  String get gateProceedAll => '全部繼續執行';

  @override
  String get gateCancelAll => '全部取消';

  @override
  String get settingsNavAppearance => '外觀';

  @override
  String get settingsNavAi => 'AI 設定';

  @override
  String get settingsNavQuery => '查詢';

  @override
  String get settingsNavLanguage => '語言';

  @override
  String get settingsNavSecurity => '安全性';

  @override
  String get settingsNavAbout => '關於';

  @override
  String get piiExportStepFormat => '格式';

  @override
  String get piiExportStepScan => 'PII 偵測';

  @override
  String get piiExportStepConfirm => '確認';

  @override
  String get piiExportNoPiiTitle => '未偵測到 PII 資料';

  @override
  String get piiExportNoPiiSubtitle => '所有欄位將以原始值匯出';

  @override
  String piiExportDetectedCount(int count) {
    return '偵測到 $count 個含 PII 的欄位';
  }

  @override
  String get piiExportHighSensitivity => '（高敏感）';

  @override
  String get piiExportKeep => '保留';

  @override
  String get piiExportMask => '遮罩';

  @override
  String get piiExportHash => '雜湊';

  @override
  String get piiExportDrop => '刪除此欄';

  @override
  String get piiExportReadyTitle => '準備匯出';

  @override
  String get piiExportSummaryFormat => '格式';

  @override
  String get piiExportSummaryRows => '行數';

  @override
  String get piiExportSummaryPiiColumns => 'PII 處理欄數';

  @override
  String get piiExportFootnote => 'PII 欄位將依所選方式處理，非 PII 欄位以原始值匯出';

  @override
  String get serverBarNotConnected => '未連線';

  @override
  String get serverBarConnecting => '連線中…';

  @override
  String get serverBarLocal => '本機';

  @override
  String get serverBarConnected => '已連線';

  @override
  String get serverBarReconnecting => '重新連線中…';

  @override
  String serverBarReconnectingIn(int seconds) {
    return '$seconds 秒後重新連線…';
  }

  @override
  String serverBarServerUrl(String url) {
    return '伺服器：$url';
  }

  @override
  String get serverBarDisconnect => '中斷連線';

  @override
  String get serverBarUnknownUser => '未知使用者';

  @override
  String get serverConnectUnexpectedError => '發生未知錯誤。';

  @override
  String get cellViewerCopy => '複製';

  @override
  String cellViewerChars(Object count) {
    return '$count 個字元';
  }

  @override
  String get slowQueryMenuLabel => '慢查詢統計';

  @override
  String get slowQueryDialogTitle => '慢查詢統計';

  @override
  String slowQueryScopeBanner(int thresholdMs) {
    return '記錄經 dbmaster/server 執行且超過 $thresholdMs 毫秒的查詢；實例啟用原生慢日誌採集時另含資料庫自身的慢查詢（按 source 區分）。';
  }

  @override
  String get slowQueryWindow1h => '近 1 小時';

  @override
  String get slowQueryWindow24h => '近 24 小時';

  @override
  String get slowQueryWindow7d => '近 7 天';

  @override
  String get slowQuerySortTotalMs => '總耗時';

  @override
  String get slowQuerySortCount => '次數';

  @override
  String get slowQuerySortAvgMs => '平均耗時';

  @override
  String get slowQuerySortMaxMs => '最大耗時';

  @override
  String get slowQueryAllConnections => '全部連線';

  @override
  String slowQueryDigestStats(int count, String total, String avg, String max) {
    return '$count 次 · 總 $total · 均 $avg · 峰 $max';
  }

  @override
  String slowQueryLastSeen(String time) {
    return '最近發生 $time';
  }

  @override
  String get slowQueryEmptyTitle => '暫無慢查詢';

  @override
  String get slowQueryEmptyBody => '該時間窗內沒有超過取樣閾值的查詢。用 dbmaster 跑些慢的再回來看看。';

  @override
  String get slowQueryLoadFailed => '慢查詢統計載入失敗。';

  @override
  String get slowQueryRetry => '重試';

  @override
  String slowQueryLoadMore(int shown, int total) {
    return '載入更多（已顯示 $shown / 共 $total）';
  }

  @override
  String get slowQueryStatusOk => '正常';

  @override
  String get slowQueryStatusError => '錯誤';

  @override
  String get slowQueryStatusCancelled => '已取消';

  @override
  String get slowQueryDatabaseLabel => '資料庫';

  @override
  String get slowQueryNoPlaintext => '該實例已關閉明文 SQL（僅 digest）。';

  @override
  String get slowQueryCopySql => '複製 SQL';

  @override
  String get slowQueryCopied => '已複製';

  @override
  String get reportsMenuLabel => '報告中心';

  @override
  String get reportsDialogTitle => '報告中心';

  @override
  String get reportsGenerateButton => '產生本期週報';

  @override
  String get reportsGeneratedToast => '週報已產生。';

  @override
  String get reportsExistingToast => '本期週報已存在。';

  @override
  String get reportsEmptyTitle => '暫無報告';

  @override
  String get reportsEmptyBody => '手動產生本期慢查詢週報，或等待每週自動產生。';

  @override
  String get reportsLoadFailed => '報告載入失敗。';

  @override
  String get reportsRetry => '重試';

  @override
  String reportsLoadMore(int shown, int total) {
    return '載入更多（已顯示 $shown / 共 $total）';
  }

  @override
  String get reportsWindowLabel => '統計視窗';

  @override
  String get reportsTruncatedHint => '視窗不完整：更早的取樣已被 retention 清理。';

  @override
  String get reportsSamplesLabel => '取樣數';

  @override
  String get reportsDistinctLabel => '不同查詢';

  @override
  String get reportsTotalTimeLabel => '總耗時';

  @override
  String get reportsErrorsLabel => '錯誤';

  @override
  String get reportsWowLabel => '較上週';

  @override
  String get reportsTopSection => 'Top 查詢';

  @override
  String get reportsByDaySection => '按天分佈';

  @override
  String get reportsByConnectionSection => '按連線分佈';

  @override
  String get reportsUnknownType => '未知報告類型——原始內容：';

  @override
  String get reportsAnalyzeWithAi => 'AI 分析';

  @override
  String get connectFailureTitle => '無法連線';

  @override
  String get connectFailureFileLocked => '檔案正被其他程式佔用。請關閉佔用該檔案的程式後重試。';

  @override
  String get connectFailureFileNotFound => '檔案不存在，可能已被移動或刪除。';

  @override
  String get connectFailurePermissionDenied => '沒有存取權限，請檢查檔案權限後重試。';

  @override
  String get connectFailureNotADatabase => '該檔案不是有效的資料庫檔案。';

  @override
  String get connectFailureCorrupt => '資料庫檔案似乎已損毀。';

  @override
  String get connectFailureAuthFailed => '認證失敗，請檢查使用者名稱與密碼。';

  @override
  String get connectFailureUnreachable => '無法連線到伺服器，請檢查位址與網路。';

  @override
  String get connectFailureUnknown => '無法連線到資料庫。';

  @override
  String get connectFailureRetry => '重試';

  @override
  String get connectFailureChooseFile => '重新選擇檔案';

  @override
  String get connectFailureCopyDetails => '複製詳情';

  @override
  String get connectFailureTechnicalDetails => '技術詳情';

  @override
  String get connectFailureErrorCode => '錯誤碼';

  @override
  String get connectFailureStatement => '出錯語句';

  @override
  String get connectFailureFile => '檔案';

  @override
  String get connectFailureRawError => '原始例外';

  @override
  String connectFailureLatestTooltip(String message) {
    return '最近連線失敗：$message';
  }
}
